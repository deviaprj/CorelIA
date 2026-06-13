"""Agent router — Pont entre CorelIA Backend et CodeWhale Agent Cloud.

Ces routes appellent le microservice codewhale-agent (interne, port 8001)
et exposent les résultats via l'API publique api.zentic.fr.

Endpoints:
    POST /agent/execute       — Exécuter une tâche agent
    GET  /agent/status/{id}   — Statut d'une tâche
    GET  /agent/result/{id}   — Résultat final
    GET  /agent/stream/{id}   — SSE streaming
    GET  /agent/tools         — Outils disponibles
"""

import os

import httpx
from fastapi import APIRouter, HTTPException, Request
from fastapi.responses import StreamingResponse

from backend.core.config import settings
from backend.core.logging import get_logger

logger = get_logger(__name__)
router = APIRouter(prefix="/agent", tags=["agent"])

# URL du service CodeWhale Agent interne
AGENT_URL = os.environ.get("AGENT_URL", "http://codewhale-agent:8001")


def _agent_headers() -> dict[str, str]:
    """Headers pour les appels internes au CodeWhale Agent."""
    return {
        "Content-Type": "application/json",
        "X-Service": "corelia-backend",
    }


@router.get("/tools")
async def agent_tools():
    """Liste les outils disponibles dans l'agent."""
    async with httpx.AsyncClient(timeout=10.0) as client:
        try:
            resp = await client.get(f"{AGENT_URL}/agent/tools")
            resp.raise_for_status()
            return resp.json()
        except httpx.HTTPError as e:
            logger.error("agent_tools failed", extra={"error": str(e)})
            return {"tools": [], "error": "Agent indisponible"}


@router.get("/health")
async def agent_health():
    """Vérifie la santé du service agent."""
    async with httpx.AsyncClient(timeout=5.0) as client:
        try:
            resp = await client.get(f"{AGENT_URL}/health")
            resp.raise_for_status()
            return resp.json()
        except httpx.HTTPError:
            return {"status": "unreachable", "agent_url": AGENT_URL}


@router.post("/execute")
async def agent_execute(request: Request):
    """Soumettre une tâche à l'agent. Supporte le streaming SSE.

    Body: {"prompt": "...", "model": "deepseek-v4-pro", "max_turns": 20, "stream": false}

    Si stream=true, retourne un flux SSE. Sinon, retourne le task_id pour polling.
    """
    body = await request.json()

    async with httpx.AsyncClient(timeout=30.0) as client:
        try:
            resp = await client.post(
                f"{AGENT_URL}/agent/run",
                json={
                    "prompt": body.get("prompt", ""),
                    "model": body.get("model", "deepseek-v4-pro"),
                    "max_turns": body.get("max_turns", 20),
                },
                headers=_agent_headers(),
            )
            resp.raise_for_status()
            task_data = resp.json()
            task_id = task_data["task_id"]

            # Si le client veut du streaming, on proxy le flux SSE
            if body.get("stream"):
                async def sse_proxy():
                    async with httpx.AsyncClient(timeout=600.0) as stream_client:
                        async with stream_client.stream(
                            "GET", f"{AGENT_URL}/agent/stream/{task_id}"
                        ) as sse_resp:
                            async for line in sse_resp.aiter_lines():
                                if await request.is_disconnected():
                                    break
                                yield line + "\n"

                return StreamingResponse(
                    sse_proxy(),
                    media_type="text/event-stream",
                    headers={
                        "Cache-Control": "no-cache",
                        "X-Accel-Buffering": "no",
                        "X-Task-Id": task_id,
                    },
                )

            return {
                "task_id": task_id,
                "status": "queued",
                "message": "Tâche soumise. Utilisez GET /agent/status/{task_id} pour suivre.",
            }

        except httpx.HTTPError as e:
            logger.error("agent_execute failed", extra={"error": str(e)})
            raise HTTPException(status_code=503, detail=f"Agent indisponible: {e}")


@router.get("/status/{task_id}")
async def agent_status(task_id: str):
    """Statut d'une tâche agent."""
    async with httpx.AsyncClient(timeout=10.0) as client:
        try:
            resp = await client.get(f"{AGENT_URL}/agent/status/{task_id}")
            resp.raise_for_status()
            return resp.json()
        except httpx.HTTPError as e:
            if hasattr(e, "response") and e.response.status_code == 404:
                raise HTTPException(status_code=404, detail="Tâche introuvable")
            logger.error("agent_status failed", extra={"task_id": task_id, "error": str(e)})
            raise HTTPException(status_code=503, detail="Agent indisponible")


@router.get("/result/{task_id}")
async def agent_result(task_id: str):
    """Résultat final d'une tâche agent."""
    async with httpx.AsyncClient(timeout=10.0) as client:
        try:
            resp = await client.get(f"{AGENT_URL}/agent/result/{task_id}")
            resp.raise_for_status()
            return resp.json()
        except httpx.HTTPError as e:
            if hasattr(e, "response"):
                if e.response.status_code == 404:
                    raise HTTPException(status_code=404, detail="Tâche introuvable")
                if e.response.status_code == 409:
                    raise HTTPException(status_code=409, detail="Tâche encore en cours")
            logger.error("agent_result failed", extra={"task_id": task_id, "error": str(e)})
            raise HTTPException(status_code=503, detail="Agent indisponible")
