"""Streaming chat endpoint with provider fallback chain."""

import json
import uuid
from datetime import datetime, timezone
from typing import Any, AsyncGenerator

import httpx
from fastapi import APIRouter, Depends, Request
from fastapi.responses import StreamingResponse

from backend.agents.tools import execute_tool, get_tool_definitions
from backend.core.auth import verify_firebase_token
from backend.core.config import settings
from backend.core.logging import get_logger
from backend.core.template_renderer import render_and_parse
from backend.schemas.chat import ChatRequest, ChatResponse, Message, Role

logger = get_logger(__name__)
router = APIRouter(prefix="/chat", tags=["chat"])


async def _stream_deepseek(
    messages: list[dict[str, Any]],
    model: str = "deepseek-v4-flash",
    temperature: float = 0.7,
    reasoning_effort: str | None = None,
) -> AsyncGenerator[str, None]:
    """Stream completions from DeepSeek API.

    Args:
        messages: Liste des messages formatés
        model: Identifiant du modèle (ex: 'deepseek-v4-pro')
        temperature: Température (0.0-2.0)
        reasoning_effort: 'off', 'high', ou 'max' — contrôle le budget thinking tokens
    """
    if not settings.deepseek_api_key:
        raise RuntimeError("DeepSeek API key not configured")

    url = "https://api.deepseek.com/v1/chat/completions"
    payload: dict[str, Any] = {
        "model": model,
        "messages": messages,
        "stream": True,
        "temperature": temperature,
    }
    # Injecter reasoning_effort si spécifié (paramètre officiel DeepSeek)
    if reasoning_effort and reasoning_effort in ("off", "high", "max"):
        payload["reasoning_effort"] = reasoning_effort
    headers = {
        "Content-Type": "application/json",
        "Authorization": f"Bearer {settings.deepseek_api_key}",
    }

    async with httpx.AsyncClient(timeout=120.0) as client:
        async with client.stream("POST", url, json=payload, headers=headers) as response:
            response.raise_for_status()
            async for line in response.aiter_lines():
                if line.startswith("data: "):
                    chunk = line.removeprefix("data: ").strip()
                    if chunk == "[DONE]":
                        break
                    try:
                        data = json.loads(chunk)
                    except json.JSONDecodeError:
                        continue
                    delta = data.get("choices", [{}])[0].get("delta", {})
                    content = delta.get("content", "")
                    if content:
                        yield f"data: {json.dumps({'content': content})}\n\n"


async def _stream_openrouter(
    messages: list[dict[str, Any]],
    model: str = "mistralai/mistral-7b-instruct",
    temperature: float = 0.7,
) -> AsyncGenerator[str, None]:
    """Stream completions from OpenRouter."""
    if not settings.openrouter_api_key:
        raise RuntimeError("OpenRouter API key not configured")

    url = "https://openrouter.ai/api/v1/chat/completions"
    payload: dict[str, Any] = {
        "model": model,
        "messages": messages,
        "stream": True,
        "temperature": temperature,
    }
    headers = {
        "Content-Type": "application/json",
        "Authorization": f"Bearer {settings.openrouter_api_key}",
        "HTTP-Referer": "https://zentic.fr",
        "X-Title": "CorelIA",
    }

    async with httpx.AsyncClient(timeout=120.0) as client:
        async with client.stream("POST", url, json=payload, headers=headers) as response:
            response.raise_for_status()
            async for line in response.aiter_lines():
                if line.startswith("data: "):
                    chunk = line.removeprefix("data: ").strip()
                    if chunk == "[DONE]":
                        break
                    try:
                        data = json.loads(chunk)
                    except json.JSONDecodeError:
                        continue
                    delta = data.get("choices", [{}])[0].get("delta", {})
                    content = delta.get("content", "")
                    if content:
                        yield f"data: {json.dumps({'content': content})}\n\n"


async def _chat_with_fallback(
    messages: list[dict[str, Any]],
    preferred_model: str | None = None,
    temperature: float = 0.7,
    reasoning_effort: str | None = None,
) -> AsyncGenerator[str, None]:
    """Route chat request through fallback chain: DeepSeek -> OpenRouter."""

    providers: list[tuple[str, Any]] = []

    if preferred_model:
        # Modèle DeepSeek direct (ex: "deepseek-v4-pro", "deepseek-v4-flash")
        if preferred_model.startswith("deepseek-"):
            providers.append(("deepseek", lambda msgs, t=temperature, re=reasoning_effort: _stream_deepseek(msgs, model=preferred_model, temperature=t, reasoning_effort=re)))
        # Modèle OpenRouter (ex: "openai/gpt-4o-mini", "deepseek/deepseek-v4-pro")
        elif "/" in preferred_model:
            providers.append(("openrouter", lambda msgs, t=temperature: _stream_openrouter(msgs, model=preferred_model, temperature=t)))
        else:
            # Modèle non reconnu → fallback chain par défaut
            providers.append(("deepseek", lambda msgs, t=temperature, re=reasoning_effort: _stream_deepseek(msgs, temperature=t, reasoning_effort=re)))
            providers.append(("openrouter", lambda msgs, t=temperature: _stream_openrouter(msgs, model="mistralai/mistral-7b-instruct", temperature=t)))
    else:
        # Aucun modèle spécifié → fallback chain par défaut
        providers.append(("deepseek", lambda msgs, t=temperature, re=reasoning_effort: _stream_deepseek(msgs, temperature=t, reasoning_effort=re)))
        providers.append(
            ("openrouter", lambda msgs, t=temperature: _stream_openrouter(msgs, model="mistralai/mistral-7b-instruct", temperature=t))
        )

    last_error: Exception | None = None
    for name, stream_fn in providers:
        try:
            logger.info("Trying chat provider", extra={"provider": name})
            async for chunk in stream_fn(messages):
                yield chunk
            return
        except Exception as exc:
            logger.warning("Provider failed", extra={"provider": name, "error": str(exc)})
            last_error = exc
            continue

    if last_error:
        raise last_error
    raise RuntimeError("All chat providers exhausted")


@router.post("/completions", response_model=None)
async def chat_completions(
    request: Request,
    body: ChatRequest,
    current_user: dict[str, Any] = Depends(verify_firebase_token),
):
    """Chat completions with SSE streaming and provider fallback."""
    messages_raw = [m.model_dump(exclude_none=True) for m in body.messages]

    # Appliquer le template Jinja2 si spécifié
    if body.template:
        try:
            from backend.core.skills_discovery import get_skills_context
            skills_ctx = get_skills_context() if body.template == "deepseek_agent" else ""
            messages_raw = render_and_parse(
                name=body.template,
                messages=messages_raw,
                tools=body.tools,
                add_generation_prompt=True,
                skills_context=skills_ctx,
            )
            logger.info(
                "Template applied",
                extra={
                    "template": body.template,
                    "input_msgs": len(body.messages),
                    "output_msgs": len(messages_raw),
                },
            )
        except FileNotFoundError as exc:
            logger.warning("Template not found, falling back to raw messages", extra={"error": str(exc)})
        except Exception as exc:
            logger.error("Template rendering failed, falling back to raw messages", extra={"error": str(exc)})

    # Inject system tools if none provided by client
    tools = body.tools or get_tool_definitions(is_pro=True)

    # Note: le suffixe [1m] pour le contexte 1M tokens est géré automatiquement
    # par l'API DeepSeek quand le modèle le supporte. Pas besoin d'ajout manuel.

    if body.stream:

        async def event_generator() -> AsyncGenerator[str, None]:
            try:
                async for chunk in _chat_with_fallback(
                    messages_raw,
                    preferred_model=body.model,
                    temperature=body.temperature,
                    reasoning_effort=body.reasoning_effort,
                ):
                    yield chunk
                yield "data: [DONE]\n\n"
            except Exception as exc:
                logger.error("Streaming error", extra={"error": str(exc)})
                yield f"data: {json.dumps({'error': str(exc)})}\n\n"

        return StreamingResponse(
            event_generator(),
            media_type="text/event-stream",
            headers={
                "Cache-Control": "no-cache",
                "Connection": "keep-alive",
                "X-Accel-Buffering": "no",
            },
        )

    # Non-streaming path (gather full response)
    full_content = ""
    async for chunk in _chat_with_fallback(
        messages_raw,
        preferred_model=body.model,
        temperature=body.temperature,
        reasoning_effort=body.reasoning_effort,
    ):
        prefix = "data: "
        if chunk.startswith(prefix):
            data_str = chunk[len(prefix):].strip()
            if data_str == "[DONE]":
                break
            try:
                data = json.loads(data_str)
            except json.JSONDecodeError:
                continue
            full_content += data.get("content", "")

    return ChatResponse(
        id=str(uuid.uuid4()),
        model=body.model or "fallback",
        message=Message(role=Role.ASSISTANT, content=full_content),
        created_at=datetime.now(timezone.utc),
    )
