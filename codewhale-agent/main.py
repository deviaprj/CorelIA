"""
CodeWhale Agent Cloud — API REST pour exécution autonome de tâches.

Ce microservice expose une API que CorelIA (et d'autres clients) peut appeler
pour exécuter des actions complexes : analyse de code, refactoring, déploiement,
recherche web, exécution de scripts, etc.

L'agent utilise l'API DeepSeek avec tool calling pour exécuter les tâches
de manière autonome dans un workspace Docker isolé.

Endpoints:
    POST /agent/run          — Soumettre une tâche (retourne task_id)
    GET  /agent/status/{id}  — Statut d'une tâche
    GET  /agent/result/{id}  — Résultat final d'une tâche
    GET  /agent/stream/{id}  — SSE stream temps réel
    GET  /agent/tools        — Liste des outils disponibles
    GET  /health             — Health check
"""

import asyncio
import hashlib
import json
import os
import subprocess
import time
import traceback
import uuid
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, AsyncGenerator

import httpx
from fastapi import FastAPI, HTTPException, Request, status
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse, StreamingResponse
from openai import AsyncOpenAI
from pydantic import BaseModel, Field
from pydantic_settings import BaseSettings, SettingsConfigDict

# ══════════════════════════════════════════════════════════════════════════════
# CONFIG
# ══════════════════════════════════════════════════════════════════════════════

class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", env_file_encoding="utf-8", extra="ignore")

    deepseek_api_key: str = ""
    openrouter_api_key: str = ""
    api_secret_key: str = ""
    workspace_dir: str = "/workspace"
    ollama_host: str = "http://ollama:11434"
    max_concurrent_tasks: int = 5
    task_timeout_seconds: int = 600
    app_env: str = "production"

settings = Settings()

# ══════════════════════════════════════════════════════════════════════════════
# FASTAPI APP
# ══════════════════════════════════════════════════════════════════════════════

app = FastAPI(title="CodeWhale Agent Cloud", version="1.0.0")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# ══════════════════════════════════════════════════════════════════════════════
# MODELS
# ══════════════════════════════════════════════════════════════════════════════

class TaskRequest(BaseModel):
    prompt: str = Field(..., description="Description de la tâche en langage naturel")
    model: str = Field(default="deepseek-v4-pro", description="Modèle à utiliser")
    max_turns: int = Field(default=20, ge=1, le=100, description="Nombre max d'itérations agent")
    workspace: str = Field(default="", description="Sous-dossier workspace optionnel")
    stream: bool = Field(default=False, description="Retourner en streaming SSE")

class TaskResponse(BaseModel):
    task_id: str
    status: str
    created_at: str

class TaskStatus(BaseModel):
    task_id: str
    status: str  # queued | running | completed | failed
    progress: str
    created_at: str
    started_at: str | None = None
    completed_at: str | None = None
    model: str = ""

class TaskResult(BaseModel):
    task_id: str
    status: str
    result: str
    turns: int = 0
    tool_calls: list[dict[str, Any]] = []
    error: str | None = None
    duration_seconds: float = 0.0

# ══════════════════════════════════════════════════════════════════════════════
# TOOL DEFINITIONS (OpenAI/DeepSeek function calling format)
# ══════════════════════════════════════════════════════════════════════════════

TOOLS = [
    {
        "type": "function",
        "function": {
            "name": "read_file",
            "description": "Lire le contenu d'un fichier dans le workspace.",
            "strict": True,
            "parameters": {
                "type": "object",
                "properties": {
                    "path": {"type": "string", "description": "Chemin relatif du fichier"},
                    "max_lines": {"type": "integer", "description": "Nombre max de lignes (défaut: 200)"},
                },
                "required": ["path"],
                "additionalProperties": False,
            },
        },
    },
    {
        "type": "function",
        "function": {
            "name": "write_file",
            "description": "Écrire ou écraser un fichier dans le workspace.",
            "strict": True,
            "parameters": {
                "type": "object",
                "properties": {
                    "path": {"type": "string", "description": "Chemin relatif du fichier"},
                    "content": {"type": "string", "description": "Contenu à écrire"},
                },
                "required": ["path", "content"],
                "additionalProperties": False,
            },
        },
    },
    {
        "type": "function",
        "function": {
            "name": "list_directory",
            "description": "Lister le contenu d'un dossier.",
            "strict": True,
            "parameters": {
                "type": "object",
                "properties": {
                    "path": {"type": "string", "description": "Chemin du dossier (défaut: racine)"},
                },
                "additionalProperties": False,
            },
        },
    },
    {
        "type": "function",
        "function": {
            "name": "run_command",
            "description": "Exécuter une commande shell dans le workspace (timeout 60s).",
            "strict": True,
            "parameters": {
                "type": "object",
                "properties": {
                    "command": {"type": "string", "description": "Commande shell à exécuter"},
                },
                "required": ["command"],
                "additionalProperties": False,
            },
        },
    },
    {
        "type": "function",
        "function": {
            "name": "search_web",
            "description": "Rechercher sur le web via DuckDuckGo.",
            "strict": True,
            "parameters": {
                "type": "object",
                "properties": {
                    "query": {"type": "string", "description": "Requête de recherche"},
                    "max_results": {"type": "integer", "description": "Nombre max de résultats (défaut: 5)"},
                },
                "required": ["query"],
                "additionalProperties": False,
            },
        },
    },
    {
        "type": "function",
        "function": {
            "name": "git_diff",
            "description": "Voir les modifications git en cours.",
            "strict": True,
            "parameters": {
                "type": "object",
                "properties": {
                    "path": {"type": "string", "description": "Fichier ou dossier spécifique"},
                },
                "additionalProperties": False,
            },
        },
    },
    {
        "type": "function",
        "function": {
            "name": "git_log",
            "description": "Voir l'historique des commits.",
            "strict": True,
            "parameters": {
                "type": "object",
                "properties": {
                    "max_count": {"type": "integer", "description": "Nombre de commits (défaut: 10)"},
                },
                "additionalProperties": False,
            },
        },
    },
    {
        "type": "function",
        "function": {
            "name": "task_complete",
            "description": "Marquer la tâche comme terminée et retourner le résumé final.",
            "strict": True,
            "parameters": {
                "type": "object",
                "properties": {
                    "summary": {"type": "string", "description": "Résumé de ce qui a été fait"},
                    "files_changed": {
                        "type": "array",
                        "items": {"type": "string"},
                        "description": "Liste des fichiers modifiés",
                    },
                },
                "required": ["summary"],
                "additionalProperties": False,
            },
        },
    },
]

# ══════════════════════════════════════════════════════════════════════════════
# TOOL EXECUTORS
# ══════════════════════════════════════════════════════════════════════════════

async def exec_read_file(path: str, max_lines: int = 200, offset: int = 0) -> str:
    wp = Path(settings.workspace_dir) / path
    if not wp.resolve().is_relative_to(Path(settings.workspace_dir).resolve()):
        return "Erreur: Accès refusé (path traversal)"
    if not wp.exists():
        return f"Erreur: Fichier introuvable: {path}"
    try:
        lines = wp.read_text(encoding="utf-8").splitlines()
        if len(lines) > max_lines:
            return "\n".join(lines[:max_lines]) + f"\n... (tronqué, {len(lines)} lignes total)"
        return "\n".join(lines)
    except Exception as e:
        return f"Erreur lecture: {e}"

async def exec_write_file(path: str, content: str) -> str:
    wp = Path(settings.workspace_dir) / path
    if not wp.resolve().is_relative_to(Path(settings.workspace_dir).resolve()):
        return "Erreur: Accès refusé (path traversal)"
    try:
        wp.parent.mkdir(parents=True, exist_ok=True)
        wp.write_text(content, encoding="utf-8")
        return f"Fichier écrit: {path} ({len(content)} caractères)"
    except Exception as e:
        return f"Erreur écriture: {e}"

async def exec_list_directory(path: str = ".") -> str:
    wp = Path(settings.workspace_dir) / path
    if not wp.resolve().is_relative_to(Path(settings.workspace_dir).resolve()):
        return "Erreur: Accès refusé"
    if not wp.is_dir():
        return f"Erreur: Pas un dossier: {path}"
    try:
        items = sorted(wp.iterdir(), key=lambda x: (not x.is_dir(), x.name))
        lines = []
        for item in items[:100]:
            suffix = "/" if item.is_dir() else ""
            size = ""
            if item.is_file():
                s = item.stat().st_size
                size = f" ({s:,} o)"
            lines.append(f"  {item.name}{suffix}{size}")
        return "\n".join(lines) if lines else "(dossier vide)"
    except Exception as e:
        return f"Erreur listing: {e}"

async def exec_run_command(command: str) -> str:
    try:
        proc = await asyncio.create_subprocess_shell(
            command,
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.PIPE,
            cwd=settings.workspace_dir,
        )
        stdout, stderr = await asyncio.wait_for(proc.communicate(), timeout=60.0)
        out = stdout.decode("utf-8", errors="replace")[:5000]
        err = stderr.decode("utf-8", errors="replace")[:2000]
        result = out
        if err:
            result += f"\n[stderr]:\n{err}"
        if proc.returncode != 0:
            result += f"\n[exit code: {proc.returncode}]"
        return result.strip() or "(sortie vide)"
    except asyncio.TimeoutError:
        return "Erreur: Timeout (60s) dépassé"
    except Exception as e:
        return f"Erreur exécution: {e}"

async def exec_search_web(query: str, max_results: int = 5) -> str:
    try:
        async with httpx.AsyncClient(timeout=15.0) as client:
            resp = await client.get(
                "https://html.duckduckgo.com/html/",
                params={"q": query},
                headers={"User-Agent": "Mozilla/5.0 (compatible; CodeWhaleAgent/1.0)"},
            )
            # Extraction basique des résultats
            from html.parser import HTMLParser
            
            class ResultParser(HTMLParser):
                def __init__(self):
                    super().__init__()
                    self.results: list[dict[str, str]] = []
                    self.current: dict[str, str] = {}
                    self.in_result = False
                    self.in_snippet = False
                    self.in_link = False

                def handle_starttag(self, tag, attrs):
                    attrs_dict = dict(attrs)
                    if tag == "a" and "result__a" in attrs_dict.get("class", ""):
                        self.in_link = True
                        self.current["title"] = ""
                        self.current["url"] = attrs_dict.get("href", "")
                    if tag == "a" and "result__snippet" in attrs_dict.get("class", ""):
                        self.in_snippet = True
                        self.current["snippet"] = ""

                def handle_endtag(self, tag):
                    if tag == "a" and self.in_link:
                        self.in_link = False
                        if self.current.get("title"):
                            self.results.append(self.current.copy())
                            self.current = {}
                    if tag == "a" and self.in_snippet:
                        self.in_snippet = False

                def handle_data(self, data):
                    if self.in_link:
                        self.current["title"] += data
                    if self.in_snippet:
                        self.current["snippet"] += data

            parser = ResultParser()
            parser.feed(resp.text)
            
            lines = []
            for i, r in enumerate(parser.results[:max_results]):
                title = r.get("title", "").strip()
                snippet = r.get("snippet", "").strip()
                url = r.get("url", "")
                lines.append(f"{i+1}. {title}\n   {snippet}\n   {url}")
            return "\n\n".join(lines) if lines else "Aucun résultat trouvé."
    except Exception as e:
        return f"Erreur recherche: {e}"

async def exec_git_diff(path: str = "") -> str:
    try:
        cmd = ["git", "-C", settings.workspace_dir, "diff", "--stat"]
        if path:
            cmd.append(path)
        proc = await asyncio.create_subprocess_exec(*cmd, stdout=asyncio.subprocess.PIPE, stderr=asyncio.subprocess.PIPE)
        stdout, _ = await proc.communicate()
        return stdout.decode("utf-8", errors="replace")[:3000] or "Aucune modification."
    except Exception as e:
        return f"Erreur git diff: {e}"

async def exec_git_log(max_count: int = 10) -> str:
    try:
        cmd = ["git", "-C", settings.workspace_dir, "log", f"--max-count={max_count}", "--oneline", "--decorate"]
        proc = await asyncio.create_subprocess_exec(*cmd, stdout=asyncio.subprocess.PIPE, stderr=asyncio.subprocess.PIPE)
        stdout, _ = await proc.communicate()
        return stdout.decode("utf-8", errors="replace")[:3000] or "Aucun commit."
    except Exception as e:
        return f"Erreur git log: {e}"

TOOL_EXECUTORS = {
    "read_file": exec_read_file,
    "write_file": exec_write_file,
    "list_directory": exec_list_directory,
    "run_command": exec_run_command,
    "search_web": exec_search_web,
    "git_diff": exec_git_diff,
    "git_log": exec_git_log,
}

# ══════════════════════════════════════════════════════════════════════════════
# SYSTEM PROMPT
# ══════════════════════════════════════════════════════════════════════════════

SYSTEM_PROMPT = """Tu es CodeWhale Agent Cloud, un assistant IA autonome qui exécute des tâches 
de développement logiciel dans un environnement Docker isolé.

Ton workspace est dans /workspace. Tu as accès à des outils pour :
- Lire/écrire des fichiers
- Lister des dossiers
- Exécuter des commandes shell
- Rechercher sur le web
- Voir l'état Git

RÈGLES :
1. Analyse la demande, planifie les étapes, puis exécute.
2. Vérifie TOUJOURS le résultat d'un outil avant de passer à l'étape suivante.
3. Appelle `task_complete` quand la tâche est terminée, avec un résumé clair.
4. Si tu rencontres une erreur, explique-la et propose une alternative.
5. Reste concis — ne décris pas ce que tu vas faire, FAIS-LE.
"""

# ══════════════════════════════════════════════════════════════════════════════
# TASK STORE (in-memory — upgrade to Redis for production)
# ══════════════════════════════════════════════════════════════════════════════

class TaskStore:
    def __init__(self):
        self._tasks: dict[str, dict[str, Any]] = {}
        self._events: dict[str, asyncio.Queue] = {}

    def create(self, prompt: str, model: str) -> str:
        task_id = uuid.uuid4().hex[:12]
        self._tasks[task_id] = {
            "task_id": task_id,
            "status": "queued",
            "progress": "En attente...",
            "prompt": prompt,
            "model": model,
            "result": "",
            "turns": 0,
            "tool_calls": [],
            "error": None,
            "created_at": datetime.now(timezone.utc).isoformat(),
            "started_at": None,
            "completed_at": None,
        }
        self._events[task_id] = asyncio.Queue()
        return task_id

    def get(self, task_id: str) -> dict | None:
        return self._tasks.get(task_id)

    def update(self, task_id: str, **kwargs):
        if task_id in self._tasks:
            self._tasks[task_id].update(kwargs)

    async def emit(self, task_id: str, event: dict):
        if task_id in self._events:
            await self._events[task_id].put(event)

    async def events(self, task_id: str) -> AsyncGenerator[dict, None]:
        if task_id not in self._events:
            yield {"type": "error", "message": "Tâche introuvable"}
            return
        q = self._events[task_id]
        # Send current state
        task = self._tasks.get(task_id, {})
        yield {"type": "status", "status": task.get("status", "unknown")}
        while True:
            try:
                event = await asyncio.wait_for(q.get(), timeout=30.0)
                yield event
                if event.get("type") in ("complete", "error"):
                    break
            except asyncio.TimeoutError:
                yield {"type": "heartbeat"}
                continue

store = TaskStore()

# ══════════════════════════════════════════════════════════════════════════════
# AGENT LOOP
# ══════════════════════════════════════════════════════════════════════════════

async def run_agent(task_id: str, prompt: str, model: str, max_turns: int):
    """Boucle agent principale : LLM + tool calling."""
    task = store.get(task_id)
    if not task:
        return

    store.update(task_id, status="running", started_at=datetime.now(timezone.utc).isoformat())
    await store.emit(task_id, {"type": "status", "status": "running"})

    client = AsyncOpenAI(
        api_key=settings.deepseek_api_key,
        base_url="https://api.deepseek.com/v1",
    )

    messages: list[dict[str, Any]] = [
        {"role": "system", "content": SYSTEM_PROMPT},
        {"role": "user", "content": prompt},
    ]

    tool_results: list[dict[str, Any]] = []

    try:
        for turn in range(max_turns):
            store.update(task_id, progress=f"Tour {turn + 1}/{max_turns}...")
            await store.emit(task_id, {"type": "progress", "turn": turn + 1, "max_turns": max_turns})

            response = await asyncio.wait_for(
                client.chat.completions.create(
                    model=model,
                    messages=messages,
                    tools=TOOLS,
                    tool_choice="auto",
                    temperature=0.3,
                    max_tokens=4096,
                ),
                timeout=120.0,
            )

            msg = response.choices[0].message

            # Tool calls ?
            if msg.tool_calls:
                for tc in msg.tool_calls:
                    name = tc.function.name
                    args = json.loads(tc.function.arguments)

                    await store.emit(task_id, {
                        "type": "tool_call",
                        "tool": name,
                        "args": args,
                    })

                    if name == "task_complete":
                        result_text = args.get("summary", "")
                        store.update(
                            task_id,
                            status="completed",
                            result=result_text,
                            turns=turn + 1,
                            tool_calls=tool_results,
                            completed_at=datetime.now(timezone.utc).isoformat(),
                        )
                        await store.emit(task_id, {
                            "type": "complete",
                            "result": result_text,
                            "turns": turn + 1,
                        })
                        return

                    executor = TOOL_EXECUTORS.get(name)
                    if executor:
                        result = await executor(**args)
                    else:
                        result = f"Outil inconnu: {name}"

                    tool_results.append({"tool": name, "args": args, "result": result[:2000]})
                    messages.append(msg.model_dump())
                    messages.append({
                        "role": "tool",
                        "tool_call_id": tc.id,
                        "content": result[:4000],
                    })
            else:
                # Réponse texte sans tool call
                content = msg.content or ""
                messages.append({"role": "assistant", "content": content})
                
                # Si pas de tool call après plusieurs tours, on force la fin
                if turn >= 2:
                    store.update(
                        task_id,
                        status="completed",
                        result=content,
                        turns=turn + 1,
                        tool_calls=tool_results,
                        completed_at=datetime.now(timezone.utc).isoformat(),
                    )
                    await store.emit(task_id, {
                        "type": "complete",
                        "result": content,
                        "turns": turn + 1,
                    })
                    return

        # Max tours atteint
        store.update(
            task_id,
            status="completed",
            result=f"Tâche terminée après {max_turns} tours (limite atteinte).",
            turns=max_turns,
            tool_calls=tool_results,
            completed_at=datetime.now(timezone.utc).isoformat(),
        )
        await store.emit(task_id, {
            "type": "complete",
            "result": f"Limite de {max_turns} tours atteinte.",
            "turns": max_turns,
        })

    except asyncio.TimeoutError:
        store.update(task_id, status="failed", error="Timeout dépassé")
        await store.emit(task_id, {"type": "error", "message": "Timeout"})
    except Exception as e:
        store.update(task_id, status="failed", error=str(e))
        await store.emit(task_id, {"type": "error", "message": str(e)})

# ══════════════════════════════════════════════════════════════════════════════
# ROUTES
# ══════════════════════════════════════════════════════════════════════════════

@app.get("/health")
async def health():
    return {
        "status": "ok",
        "service": "codewhale-agent",
        "env": settings.app_env,
        "workspace": settings.workspace_dir,
        "tasks_active": sum(1 for t in store._tasks.values() if t["status"] in ("running", "queued")),
    }

@app.get("/agent/tools")
async def list_tools():
    return {"tools": [t["function"]["name"] for t in TOOLS], "count": len(TOOLS)}

@app.post("/agent/run", response_model=TaskResponse)
async def agent_run(req: TaskRequest):
    """Soumettre une tâche à l'agent."""
    task_id = store.create(req.prompt, req.model)
    # Lancer en arrière-plan
    asyncio.create_task(run_agent(task_id, req.prompt, req.model, req.max_turns))
    return TaskResponse(task_id=task_id, status="queued", created_at=store._tasks[task_id]["created_at"])

@app.get("/agent/status/{task_id}", response_model=TaskStatus)
async def agent_status(task_id: str):
    """Vérifier le statut d'une tâche."""
    task = store.get(task_id)
    if not task:
        raise HTTPException(status_code=404, detail="Tâche introuvable")
    return TaskStatus(
        task_id=task["task_id"],
        status=task["status"],
        progress=task["progress"],
        created_at=task["created_at"],
        started_at=task.get("started_at"),
        completed_at=task.get("completed_at"),
        model=task["model"],
    )

@app.get("/agent/result/{task_id}", response_model=TaskResult)
async def agent_result(task_id: str):
    """Récupérer le résultat final d'une tâche."""
    task = store.get(task_id)
    if not task:
        raise HTTPException(status_code=404, detail="Tâche introuvable")
    if task["status"] not in ("completed", "failed"):
        raise HTTPException(status_code=409, detail=f"Tâche encore en cours: {task['status']}")
    
    duration = 0.0
    if task.get("started_at") and task.get("completed_at"):
        try:
            start = datetime.fromisoformat(task["started_at"])
            end = datetime.fromisoformat(task["completed_at"])
            duration = (end - start).total_seconds()
        except Exception:
            pass

    return TaskResult(
        task_id=task["task_id"],
        status=task["status"],
        result=task["result"],
        turns=task["turns"],
        tool_calls=task["tool_calls"],
        error=task.get("error"),
        duration_seconds=duration,
    )

@app.get("/agent/stream/{task_id}")
async def agent_stream(task_id: str, request: Request):
    """Stream SSE des événements d'une tâche."""
    if task_id not in store._tasks:
        raise HTTPException(status_code=404, detail="Tâche introuvable")

    async def event_generator():
        async for event in store.events(task_id):
            if await request.is_disconnected():
                break
            yield f"data: {json.dumps(event)}\n\n"

    return StreamingResponse(
        event_generator(),
        media_type="text/event-stream",
        headers={
            "Cache-Control": "no-cache",
            "X-Accel-Buffering": "no",
        },
    )
