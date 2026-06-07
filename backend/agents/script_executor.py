"""On-the-fly script execution sandbox for AI-generated Python scripts.

Generates Python scripts via DeepSeek (JSON mode) from natural-language
instructions and executes them in a subprocess sandbox with timeout.
"""

import json
import subprocess
import tempfile
import textwrap
from pathlib import Path
from typing import Any

import httpx

from backend.core.config import settings
from backend.core.logging import get_logger

logger = get_logger(__name__)

# ── Safety: blocked imports / patterns ───────────────────────────────────────
_BLOCKED_IMPORTS: set[str] = {
    "os",
    "subprocess",
    "shutil",
    "sys",
    "socket",
    "ctypes",
    "multiprocessing",
    "signal",
    "pty",
    "fcntl",
    "posix",
    "importlib",
    "__import__",
    "compile",
    "eval",
    "exec",
    "open",
}
_ALLOWED_IMPORTS: set[str] = {
    "httpx",
    "bs4",
    "BeautifulSoup",
    "json",
    "re",
    "math",
    "datetime",
    "collections",
    "itertools",
    "functools",
    "typing",
    "dataclasses",
    "hashlib",
    "base64",
    "urllib.parse",
    "html",
    "textwrap",
    "string",
    "csv",
    "io",
}  # fmt: skip

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


def _is_safe_script(code: str) -> bool:
    """Check that the script doesn't use blocked imports or dangerous calls."""
    code_lower = code.lower()
    for blocked in _BLOCKED_IMPORTS:
        if f"import {blocked}" in code_lower:
            return False
        if f"from {blocked}" in code_lower:
            return False
    # Check for dangerous builtins
    dangerous = ["__import__(", "eval(", "exec(", "compile(", "open("]
    for d in dangerous:
        if d in code_lower:
            return False
    return True


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


async def execute_script(script: str, timeout: int = 30) -> dict[str, Any]:
    """Execute a Python script in a subprocess sandbox and return the JSON result."""
    if not _is_safe_script(script):
        return {
            "success": False,
            "error": "Script contains blocked imports or dangerous calls",
        }

    with tempfile.NamedTemporaryFile(
        mode="w", suffix=".py", delete=False, encoding="utf-8"
    ) as f:
        f.write(script)
        script_path = f.name

    try:
        result = subprocess.run(
            ["python3", script_path],
            capture_output=True,
            text=True,
            timeout=timeout,
            cwd="/tmp",
        )

        if result.returncode != 0:
            return {
                "success": False,
                "error": result.stderr.strip() or "Unknown error",
                "stdout": result.stdout.strip()[:500],
            }

        stdout = result.stdout.strip()
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

    except subprocess.TimeoutExpired:
        return {"success": False, "error": f"Script timed out after {timeout}s"}
    except Exception as exc:
        return {"success": False, "error": str(exc)}
    finally:
        Path(script_path).unlink(missing_ok=True)


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
    """Full pipeline: generate scrape script → execute → return result."""
    logger.info(
        "Generating scrape script", extra={"url": url, "instruction": instruction}
    )

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
    """Generate and execute an API fetch/transform script."""
    logger.info(
        "Generating api-fetch script", extra={"url": url, "instruction": instruction}
    )

    try:
        script = await generate_api_fetch_script(instruction, url)
    except Exception as exc:
        logger.error("API fetch script generation failed", extra={"error": str(exc)})
        return {"success": False, "error": f"AI script generation failed: {exc}"}

    return await _run_generated_script(script, context="api-fetch")
