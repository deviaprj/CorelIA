"""Voice endpoints: Whisper STT + ElevenLabs TTS proxy."""

import os
import tempfile
from typing import Any

import httpx
from fastapi import APIRouter, Depends, File, HTTPException, UploadFile, status
from fastapi.responses import StreamingResponse

from backend.core.auth import verify_firebase_token
from backend.core.config import settings
from backend.core.logging import get_logger

logger = get_logger(__name__)
router = APIRouter(prefix="/voice", tags=["voice"])

WHISPER_API_URL = "https://api.openai.com/v1/audio/transcriptions"
ELEVENLABS_API_URL = "https://api.elevenlabs.io/v1/text-to-speech"


@router.post("/stt", response_model=dict[str, Any])
async def speech_to_text(
    audio: UploadFile = File(...),
    current_user: dict[str, Any] = Depends(verify_firebase_token),
) -> dict[str, Any]:
    """Transcribe audio using OpenAI Whisper API."""
    if not settings.openai_api_key:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Whisper API not configured",
        )

    # Save uploaded file temporarily
    suffix = os.path.splitext(audio.filename or ".wav")[1] or ".wav"
    with tempfile.NamedTemporaryFile(delete=False, suffix=suffix) as tmp:
        content = await audio.read()
        tmp.write(content)
        tmp_path = tmp.name

    try:
        async with httpx.AsyncClient(timeout=60.0) as client:
            with open(tmp_path, "rb") as f:
                files = {"file": (audio.filename or "audio.wav", f, audio.content_type or "audio/wav")}
                data = {"model": "whisper-1", "language": "fr"}
                headers = {"Authorization": f"Bearer {settings.openai_api_key}"}
                response = await client.post(
                    WHISPER_API_URL,
                    files=files,
                    data=data,
                    headers=headers,
                )
                response.raise_for_status()
                return response.json()
    except httpx.HTTPStatusError as exc:
        logger.error("Whisper API error", extra={"status": exc.response.status_code})
        raise HTTPException(
            status_code=status.HTTP_502_BAD_GATEWAY,
            detail="Whisper API error",
        ) from exc
    except Exception as exc:
        logger.error("STT processing error", extra={"error": str(exc)})
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Speech-to-text processing failed",
        ) from exc
    finally:
        os.unlink(tmp_path)


@router.post("/tts")
async def text_to_speech(
    text: str,
    voice_id: str = "21m00Tcm4TlvDq8ikWAM",  # Default ElevenLabs voice (Rachel)
    model_id: str = "eleven_multilingual_v2",
    current_user: dict[str, Any] = Depends(verify_firebase_token),
) -> StreamingResponse:
    """Synthesize speech using ElevenLabs API."""
    if not settings.elevenlabs_api_key:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="ElevenLabs API not configured",
        )

    url = f"{ELEVENLABS_API_URL}/{voice_id}"
    payload = {
        "text": text,
        "model_id": model_id,
        "voice_settings": {"stability": 0.5, "similarity_boost": 0.75},
    }
    headers = {
        "xi-api-key": settings.elevenlabs_api_key,
        "Content-Type": "application/json",
        "Accept": "audio/mpeg",
    }

    try:
        async with httpx.AsyncClient(timeout=60.0) as client:
            response = await client.post(url, json=payload, headers=headers)
            response.raise_for_status()

            async def audio_stream():
                async for chunk in response.aiter_bytes():
                    yield chunk

            return StreamingResponse(
                audio_stream(),
                media_type="audio/mpeg",
                headers={"Content-Disposition": "attachment; filename=speech.mp3"},
            )
    except httpx.HTTPStatusError as exc:
        logger.error("ElevenLabs API error", extra={"status": exc.response.status_code})
        raise HTTPException(
            status_code=status.HTTP_502_BAD_GATEWAY,
            detail="ElevenLabs API error",
        ) from exc
    except Exception as exc:
        logger.error("TTS processing error", extra={"error": str(exc)})
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Text-to-speech processing failed",
        ) from exc
