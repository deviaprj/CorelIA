"""Voice endpoints — 100% Ollama local, zero external paid services."""

import base64
import json
import os
import tempfile
from typing import Any

import httpx
from fastapi import APIRouter, Depends, File, HTTPException, UploadFile, status

from backend.core.auth import verify_firebase_token
from backend.core.config import settings
from backend.core.logging import get_logger

logger = get_logger(__name__)
router = APIRouter(prefix="/voice", tags=["voice"])

OLLAMA_LOCAL_URL = "http://localhost:11434"


@router.post("/stt", response_model=dict[str, Any])
async def speech_to_text(
    audio: UploadFile = File(...),
    model: str = "whisper",
    current_user: dict[str, Any] = Depends(verify_firebase_token),
) -> dict[str, Any]:
    """Transcribe audio using an Ollama-compatible local model.

    Requires a speech-to-text model available in the local Ollama instance
    (e.g. a custom model wrapping `openai/whisper` or ` Systran/faster-whisper`).
    If Ollama is unavailable or the model is missing, returns 503 so the
    Flutter client can fall back to the native `speech_to_text` package.
    """
    ollama_url = settings.ollama_cloud_url or OLLAMA_LOCAL_URL

    # Save uploaded audio temporarily
    suffix = os.path.splitext(audio.filename or ".wav")[1] or ".wav"
    with tempfile.NamedTemporaryFile(delete=False, suffix=suffix) as tmp:
        content = await audio.read()
        tmp.write(content)
        tmp_path = tmp.name

    try:
        # Encode audio to base64 for multimodal Ollama models
        with open(tmp_path, "rb") as f:
            audio_b64 = base64.b64encode(f.read()).decode("utf-8")

        payload = {
            "model": model,
            "prompt": f"Transcribe the following audio data (base64): {audio_b64}",
            "stream": False,
        }

        async with httpx.AsyncClient(timeout=120.0) as client:
            response = await client.post(
                f"{ollama_url}/api/generate",
                json=payload,
                headers={"Content-Type": "application/json"},
            )

        if response.status_code == 404:
            raise HTTPException(
                status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
                detail="Ollama STT model not found. Please run `ollama pull {model}` or use native speech_to_text.",
            )
        response.raise_for_status()

        data = response.json()
        transcription = data.get("response", "").strip()
        return {"text": transcription, "model": model, "source": "ollama"}

    except httpx.ConnectError as exc:
        logger.warning("Ollama local unreachable for STT", extra={"error": str(exc)})
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Ollama local unreachable. Fallback to native speech_to_text.",
        ) from exc
    except HTTPException:
        raise
    except Exception as exc:
        logger.error("STT processing error", extra={"error": str(exc)})
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Speech-to-text processing failed. Fallback to native speech_to_text.",
        ) from exc
    finally:
        os.unlink(tmp_path)


@router.post("/tts")
async def text_to_speech(
    text: str,
    model: str = "piper",
    voice: str = "default",
    current_user: dict[str, Any] = Depends(verify_firebase_token),
) -> dict[str, Any]:
    """Synthesize speech using an Ollama-compatible local TTS model.

    Requires a text-to-speech model available in the local Ollama instance
    (e.g. a custom model wrapping `rhasspy/piper` or `coqui/XTTS-v2`).
    If Ollama is unavailable or the model is missing, returns 503 so the
    Flutter client can fall back to the native `flutter_tts` package.

    Note: Ollama currently returns text responses. True audio generation via
    Ollama will become possible when Ollama adds native audio output support.
    Until then, this endpoint returns the phonetic/SSML guidance generated
    by the Ollama TTS model, which the client can pass to `flutter_tts`.
    """
    ollama_url = settings.ollama_cloud_url or OLLAMA_LOCAL_URL

    try:
        payload = {
            "model": model,
            "prompt": f"Synthesize the following text into speech phonemes/SSML. Voice={voice}: {text}",
            "stream": False,
        }

        async with httpx.AsyncClient(timeout=60.0) as client:
            response = await client.post(
                f"{ollama_url}/api/generate",
                json=payload,
                headers={"Content-Type": "application/json"},
            )

        if response.status_code == 404:
            raise HTTPException(
                status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
                detail="Ollama TTS model not found. Please run `ollama pull {model}` or use native flutter_tts.",
            )
        response.raise_for_status()

        data = response.json()
        guidance = data.get("response", "").strip()
        return {
            "text": text,
            "guidance": guidance,
            "model": model,
            "voice": voice,
            "source": "ollama",
            "note": "Audio output from Ollama requires a TTS-capable model. Fallback to flutter_tts if no audio returned.",
        }

    except httpx.ConnectError as exc:
        logger.warning("Ollama local unreachable for TTS", extra={"error": str(exc)})
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Ollama local unreachable. Fallback to native flutter_tts.",
        ) from exc
    except HTTPException:
        raise
    except Exception as exc:
        logger.error("TTS processing error", extra={"error": str(exc)})
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Text-to-speech processing failed. Fallback to native flutter_tts.",
        ) from exc
