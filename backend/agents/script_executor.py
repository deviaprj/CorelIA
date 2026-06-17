"""On-the-fly script execution sandbox for AI-generated Python scripts.

Generates Python scripts via DeepSeek (JSON mode) from natural-language
instructions and executes them in a subprocess sandbox with timeout.
"""

import asyncio
import ast
import json
import os
import tempfile
import textwrap
from pathlib import Path
from typing import Any

import httpx

from backend.core.config import settings
from backend.core.logging import get_logger
from backend.core.net_guard import UnsafeUrlError, assert_safe_url

logger = get_logger(__name__)

# ── Sandbox allow/deny lists ──────────────────────────────────────────────────
# Allow-list of modules the generated script may import. Anything not here is
# rejected by the AST validator — defense-in-depth on top of the LLM system
# prompt that already restricts imports.
_ALLOWED_MODULES: set[str] = {
    "httpx", "bs4", "json", "re", "math", "datetime", "collections",
    "itertools", "functools", "typing", "dataclasses", "hashlib", "base64",
    "urllib", "urllib.parse", "html", "textwrap", "string", "csv", "io",
    "decimal", "statistics", "fractions", "random", "uuid",
}

# Builtins the generated script must never call. ``open`` blocks disk I/O;
# ``eval``/``exec``/``compile``/``__import__`` block code-generation escapes;
# ``getattr``/``setattr``/``delattr`` block dynamic dunder access;
# ``globals``/``locals``/``vars`` block builtins-dict escapes.
_DANGEROUS_NAMES: set[str] = {
    "eval", "exec", "compile", "open", "__import__", "getattr", "setattr",
    "delattr", "globals", "locals", "vars", "input", "breakpoint",
    "exit", "quit", "help", "__builtins__",
}

# Attribute names that are classic sandbox-escape primitives. Accessing any of
# these (e.g. ``obj.__class__.__subclasses__()``) is rejected outright.
_DANGEROUS_ATTRS: set[str] = {
    "__builtins__", "__globals__", "__class__", "__subclasses__", "__mro__",
    "__bases__", "__dict__", "__import__", "__getattribute__",
}

# ── System prompt for script generation ──────────────────────────────────────
_SCRIPT_SYSTEM_PROMPT = textwrap.dedent("""\
    Tu es un générateur de scripts Python. L'utilisateur va te donner:
    1. L'URL d'une page web à scraper
    2. Une instruction en langage naturel sur ce qu'il faut extraire

    Tu dois générer un script Python qui:
    - Fait une requête HTTP GET vers l'URL avec httpx (User-Agent desktop)
    - Parse le HTML avec BeautifulSoup
    - Extrait exactement ce que l'utilisateur demande
    - Retourne UNIQUEMENT un objet JSON valide à la fin avec print(json.dumps(result))

    RÈGLES:
    - Tu ne peux utiliser QUE ces imports: httpx, bs4 (BeautifulSoup), json, re, urllib.parse, html
    - Pas de os, sys, subprocess, eval, exec, open(), ni aucun import système
    - User-Agent: "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36"
    - Gère les timeouts et les erreurs HTTP
    - Le script doit être autonome et s'exécuter en moins de 30 secondes
    - Pas de commentaires inutiles, code propre et direct
    - La dernière ligne doit être: print(json.dumps(result, ensure_ascii=False))

    Retourne UNIQUEMENT le code Python, pas d'explication autour.
    Pas de ```python, pas de markdown. Juste le code brut.
    """)  # noqa: E501

_EXEC_SYSTEM_PROMPT = textwrap.dedent("""\
    Tu es un générateur de scripts Python. L'utilisateur te donne une instruction
    en langage naturel. Génère un script Python autonome qui accomplit la tâche.

    RÈGLES:
    - Imports autorisés UNIQUEMENT: httpx, bs4 (BeautifulSoup), json, re, urllib.parse,
      html, math, datetime, collections, itertools, hashlib, base64, csv, io
    - Pas de os, sys, subprocess, eval, exec, open(), ni import système
    - User-Agent desktop pour les requêtes HTTP
    - Gère timeouts et erreurs avec try/except
    - La dernière ligne DOIT être: print(json.dumps(result, ensure_ascii=False))
    - Le script doit s'exécuter en moins de 30 secondes

    Retourne UNIQUEMENT le code Python brut, sans markdown ni explication.
    """)

_API_FETCH_SYSTEM_PROMPT = textwrap.dedent("""\
    Tu es un générateur de scripts Python pour appeler des APIs REST et transformer
    les réponses JSON selon les instructions utilisateur.

    RÈGLES:
    - Utilise httpx pour GET/POST vers l'URL fournie
    - Parse la réponse JSON et transforme selon l'instruction (tableau, filtres, etc.)
    - Imports autorisés: httpx, json, re, urllib.parse, datetime, collections
    - Pas de os, sys, subprocess, eval, exec, open()
    - Gère les erreurs HTTP avec try/except
    - Dernière ligne: print(json.dumps(result, ensure_ascii=False))

    Retourne UNIQUEMENT le code Python brut, sans markdown.
    """)


def _strip_code_fences(script: str) -> str:
    """Remove markdown code fences from LLM output."""
    script = script.strip()
    if not script.startswith("```"):
        return script
    lines = script.split("\n")
    if lines[0].startswith("```"):
        lines = lines[1:]
    if lines and lines[-1].startswith("```"):
        lines = lines[:-1]
    return "\n".join(lines).strip()


class _ScriptValidator(ast.NodeVisitor):
    """Walk a generated script's AST and reject anything outside the sandbox.

    Replaces the old ``_is_safe_script`` substring check, which was trivially
    bypassable: ``__import__("o" + "s").system("rm -rf /")`` contains no
    ``import os`` substring, so it passed. The AST walk inspects the actual
    structure, so concatenation tricks no longer help.
    """

    def __init__(self) -> None:
        self.errors: list[str] = []

    def _fail(self, msg: str) -> None:
        self.errors.append(msg)

    def visit_Import(self, node: ast.Import) -> None:  # noqa: N802
        for alias in node.names:
            root = alias.name.split(".")[0]
            if root not in _ALLOWED_MODULES:
                self._fail(f"Import not allowed: {alias.name}")
        self.generic_visit(node)

    def visit_ImportFrom(self, node: ast.ImportFrom) -> None:  # noqa: N802
        if node.module is None:
            self._fail("Relative imports are not allowed")
        elif node.module.split(".")[0] not in _ALLOWED_MODULES:
            self._fail(f"Import not allowed: {node.module}")
        self.generic_visit(node)

    def visit_Call(self, node: ast.Call) -> None:  # noqa: N802
        if isinstance(node.func, ast.Name) and node.func.id in _DANGEROUS_NAMES:
            self._fail(f"Call to disallowed builtin: {node.func.id}()")
        self.generic_visit(node)

    def visit_Attribute(self, node: ast.Attribute) -> None:  # noqa: N802
        if node.attr in _DANGEROUS_ATTRS:
            self._fail(f"Access to dangerous attribute: .{node.attr}")
        self.generic_visit(node)

    def visit_Name(self, node: ast.Name) -> None:  # noqa: N802
        # Bare reference to a dangerous builtin/escape (e.g. ``f = eval; f()``).
        if node.id in _DANGEROUS_NAMES:
            self._fail(f"Reference to disallowed name: {node.id}")
        self.generic_visit(node)


def _validate_script_ast(code: str) -> None:
    """Parse ``code`` and reject any AST node outside the sandbox.

    Raises ``ValueError`` with the first violations found. Catches the string-
    concatenation bypass that defeated the old substring check.
    """
    try:
        tree = ast.parse(code)
    except SyntaxError as exc:
        raise ValueError(f"Script is not valid Python: {exc}") from exc
    validator = _ScriptValidator()
    validator.visit(tree)
    if validator.errors:
        raise ValueError(
            "Script rejected by sandbox: " + "; ".join(validator.errors[:3])
        )


async def _generate_script_from_prompt(system_prompt: str, user_prompt: str) -> str:
    """Call DeepSeek to generate a Python script."""
    if not settings.deepseek_api_key:
        raise RuntimeError("DeepSeek API key not configured")

    payload = {
        "model": "deepseek-v4-flash",
        "messages": [
            {"role": "system", "content": system_prompt},
            {"role": "user", "content": user_prompt},
        ],
        "temperature": 0.3,
        "max_tokens": 2048,
        "stream": False,
    }

    async with httpx.AsyncClient(timeout=30.0) as client:
        response = await client.post(
            "https://api.deepseek.com/v1/chat/completions",
            headers={
                "Authorization": f"Bearer {settings.deepseek_api_key}",
                "Content-Type": "application/json",
            },
            json=payload,
        )
        response.raise_for_status()
        data = response.json()
        script = data["choices"][0]["message"]["content"]
        return _strip_code_fences(script)


async def generate_script(instruction: str, url: str) -> str:
    """Generate a scraping script from URL + natural-language instructions."""
    user_prompt = f"URL: {url}\nInstruction: {instruction}"
    return await _generate_script_from_prompt(_SCRIPT_SYSTEM_PROMPT, user_prompt)


async def generate_generic_script(instruction: str) -> str:
    """Generate a generic Python script from natural-language instructions."""
    return await _generate_script_from_prompt(_EXEC_SYSTEM_PROMPT, instruction)


async def generate_api_fetch_script(instruction: str, url: str) -> str:
    """Generate a Python script that calls an API and transforms JSON."""
    user_prompt = f"URL: {url}\nInstruction: {instruction}"
    return await _generate_script_from_prompt(_API_FETCH_SYSTEM_PROMPT, user_prompt)


# Minimal environment for the sandboxed subprocess — do NOT inherit the
# server's env (which holds DEEPSEEK_API_KEY, API_SECRET_KEY, ...). Only what
# Python + the allow-listed libs need to run.
_SANDBOX_ENV = {
    "PATH": os.environ.get("PATH", "/usr/local/bin:/usr/bin:/bin"),
    "LANG": "C.UTF-8",
    "LC_ALL": "C.UTF-8",
    "PYTHONDONTWRITEBYTECODE": "1",
    "PYTHONUNBUFFERED": "1",
    "HOME": "/tmp",
}


async def execute_script(script: str, timeout: int = 15) -> dict[str, Any]:
    """Execute a Python script in an isolated subprocess sandbox.

    Defense layers:
    1. AST validation (``_validate_script_ast``) — reject blocked imports /
       dangerous builtins / dunder escapes BEFORE running anything. Replaces
       the old substring check (bypassable via string concatenation).
    2. Isolated cwd — a fresh temp dir per run (not /tmp), auto-cleaned, so the
       script cannot clobber files left by sibling runs.
    3. Minimal env — no API keys leak into the subprocess.
    4. Tight timeout (15s) + captured stdout/stderr.
    """
    try:
        _validate_script_ast(script)
    except ValueError as exc:
        return {"success": False, "error": str(exc)}

    with tempfile.TemporaryDirectory(prefix="corelia_sandbox_") as tmpdir:
        script_path = Path(tmpdir) / "generated.py"
        script_path.write_text(script, encoding="utf-8")
        try:
            # Spawn the sandbox subprocess WITHOUT blocking the event loop.
            # The old ``subprocess.run(timeout=...)`` was a synchronous call that
            # froze the entire asyncio loop for up to ``timeout`` seconds (15s
            # default) — stalling every concurrent request (chat streaming,
            # /scrape, /search_smart, …) for the whole sandbox run. Using
            # ``asyncio.create_subprocess_exec`` lets the loop keep serving while
            # the child runs in its own process; we then await its output with a
            # hard timeout. Behavior is otherwise identical (cwd, minimal env,
            # captured stdout/stderr, JSON parse).
            proc = await asyncio.create_subprocess_exec(
                "python3",
                str(script_path),
                stdout=asyncio.subprocess.PIPE,
                stderr=asyncio.subprocess.PIPE,
                cwd=tmpdir,
                env=_SANDBOX_ENV,
            )
            try:
                stdout_b, stderr_b = await asyncio.wait_for(
                    proc.communicate(), timeout=timeout
                )
            except asyncio.TimeoutError:
                # ``wait_for`` cancels ``communicate()`` but does NOT kill the
                # child — reap it explicitly so no zombie outlives the request
                # and keeps burning CPU/memory past its deadline. (Note:
                # ``asyncio.wait_for`` raises ``asyncio.TimeoutError`` — the
                # builtin ``TimeoutError`` alias — NOT ``TimeoutExpired``,
                # which only exists on the synchronous ``subprocess`` API.)
                # ``proc.kill()`` is guarded: if the child exited on its own
                # in the tiny window between the timeout firing and the kill,
                # ``ProcessLookupError`` is raised — swallow it and still reap
                # via ``wait()`` so we never leak a process nor lose the timeout
                # message to the outer ``except Exception``.
                try:
                    proc.kill()
                except ProcessLookupError:
                    pass  # already exited — nothing to signal
                await proc.wait()
                return {"success": False, "error": f"Script timed out after {timeout}s"}

            stdout = (stdout_b or b"").decode("utf-8", errors="replace").strip()
            stderr = (stderr_b or b"").decode("utf-8", errors="replace").strip()

            if proc.returncode != 0:
                return {
                    "success": False,
                    "error": stderr or "Unknown error",
                    "stdout": stdout[:500],
                }

            if not stdout:
                return {"success": False, "error": "Script produced no output"}

            try:
                parsed = json.loads(stdout)
                return {"success": True, "data": parsed}
            except json.JSONDecodeError:
                return {
                    "success": False,
                    "error": "Script output is not valid JSON",
                    "raw_output": stdout[:2000],
                }

        except Exception as exc:
            return {"success": False, "error": str(exc)}


async def _run_generated_script(
    script: str,
    *,
    context: str,
) -> dict[str, Any]:
    """Execute a generated script and attach the source code to the result."""
    logger.info("Executing generated script", extra={"context": context, "script_len": len(script)})
    result = await execute_script(script)
    result["script"] = script
    return result


async def scrape_with_script(url: str, instruction: str) -> dict[str, Any]:
    """Full pipeline: SSRF-check URL → generate scrape script → execute → return."""
    logger.info(
        "Generating scrape script", extra={"url": url, "instruction": instruction}
    )

    try:
        assert_safe_url(url)
    except UnsafeUrlError as exc:
        logger.warning("scrape_with_script blocked URL", extra={"url": url, "error": str(exc)})
        return {"success": False, "error": f"URL not allowed: {exc}"}

    try:
        script = await generate_script(instruction, url)
    except Exception as exc:
        logger.error("Script generation failed", extra={"error": str(exc)})
        return {"success": False, "error": f"AI script generation failed: {exc}"}

    return await _run_generated_script(script, context="scrape")


async def exec_with_instruction(instruction: str) -> dict[str, Any]:
    """Generate and execute a generic Python script from instructions."""
    logger.info("Generating exec script", extra={"instruction": instruction[:120]})

    try:
        script = await generate_generic_script(instruction)
    except Exception as exc:
        logger.error("Exec script generation failed", extra={"error": str(exc)})
        return {"success": False, "error": f"AI script generation failed: {exc}"}

    return await _run_generated_script(script, context="exec")


async def api_fetch_with_script(url: str, instruction: str) -> dict[str, Any]:
    """SSRF-check URL → generate and execute an API fetch/transform script."""
    logger.info(
        "Generating api-fetch script", extra={"url": url, "instruction": instruction}
    )

    try:
        assert_safe_url(url)
    except UnsafeUrlError as exc:
        logger.warning("api_fetch_with_script blocked URL", extra={"url": url, "error": str(exc)})
        return {"success": False, "error": f"URL not allowed: {exc}"}

    try:
        script = await generate_api_fetch_script(instruction, url)
    except Exception as exc:
        logger.error("API fetch script generation failed", extra={"error": str(exc)})
        return {"success": False, "error": f"AI script generation failed: {exc}"}

    return await _run_generated_script(script, context="api-fetch")
