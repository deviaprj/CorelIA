"""Streaming chat endpoint with provider fallback chain."""

import json
import uuid
from typing import Any, AsyncGenerator

import httpx
from fastapi import APIRouter, Depends, Request
from fastapi.responses import StreamingResponse

from backend.agents.tools import execute_tool, get_tool_definitions
from backend.core.auth import verify_firebase_token
from backend.core.config import settings
from backend.core.logging import get_logger
from backend.schemas.chat import ChatRequest, ChatResponse, Message, Role

logger = get_logger(__name__)
router = APIRouter(prefix="/chat", tags=["chat"])


async def _stream_deepseek(
    messages: list[dict[str, Any]],
    model: str = "deepseek-v4-flash",
) -> AsyncGenerator[str, None]:
    """Stream completions from DeepSeek API."""
    if not settings.deepseek_api_key:
        raise RuntimeError("DeepSeek API key not configured")

    url = "https://api.deepseek.com/v1/chat/completions"
    payload = {
        "model": model,
        "messages": messages,
        "stream": True,
        "temperature": 0.7,
    }
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
) -> AsyncGenerator[str, None]:
    """Stream completions from OpenRouter."""
    if not settings.openrouter_api_key:
        raise RuntimeError("OpenRouter API key not configured")

    url = "https://openrouter.ai/api/v1/chat/completions"
    payload = {
        "model": model,
        "messages": messages,
        "stream": True,
        "temperature": 0.7,
    }
    headers = {
        "Content-Type": "application/json",
        "Authorization": f"Bearer {settings.openrouter_api_key}",
        "HTTP-Referer": "https://aironbot.app",
        "X-Title": "AironBot",
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
) -> AsyncGenerator[str, None]:
    """Route chat request through fallback chain: DeepSeek -> OpenRouter."""

    providers: list[tuple[str, Any]] = []

    if preferred_model and preferred_model.startswith("deepseek/"):
        providers.append(("deepseek", lambda msgs: _stream_deepseek(msgs, model=preferred_model)))
    elif preferred_model and "/" in preferred_model:
        providers.append(("openrouter", lambda msgs: _stream_openrouter(msgs, model=preferred_model)))
    else:
        # Default fallback chain
        providers.append(("deepseek", lambda msgs: _stream_deepseek(msgs)))
        providers.append(
            ("openrouter", lambda msgs: _stream_openrouter(msgs, model="mistralai/mistral-7b-instruct"))
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

    # Inject system tools if none provided by client
    tools = body.tools or get_tool_definitions()

    if body.stream:

        async def event_generator() -> AsyncGenerator[str, None]:
            try:
                async for chunk in _chat_with_fallback(messages_raw, preferred_model=body.model):
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
    async for chunk in _chat_with_fallback(messages_raw, preferred_model=body.model):
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
        created_at=__import__("datetime").datetime.utcnow(),
    )
