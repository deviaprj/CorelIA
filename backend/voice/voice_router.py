"""
Voice API router — OmniVoice TTS endpoints.

Endpoints:
  GET  /voice/status          — Engine health & GPU status
  POST /voice/omnivoice       — Synthesize speech (returns WAV)
  POST /voice/omnivoice/stream — Streaming audio chunks (SSE)
  POST /voice/design           — Voice design preview
  POST /voice/clone            — Voice cloning from reference audio
"""

from __future__ import annotations

import asyncio
import io
import logging
from typing import Optional

import soundfile as sf
from fastapi import APIRouter, Depends, HTTPException, Request, UploadFile, File, Form
from fastapi.responses import Response, StreamingResponse
from pydantic import BaseModel, Field

from backend.core.auth import require_client_api_key
from backend.voice.omnivoice_tts import (
    OmniVoiceTTSEngine,
    TtsMode,
    TtsRequest,
    FAST_NUM_STEPS,
    DEFAULT_NUM_STEPS,
    DEFAULT_SPEED,
)

logger = logging.getLogger(__name__)
router = APIRouter(prefix="/voice", tags=["voice"])


# ── Pydantic models ──────────────────────────────────────────────────────────

class VoiceStatusResponse(BaseModel):
    """Engine status."""
    available: bool
    device: str
    dtype: str
    package_installed: bool
    error: Optional[str] = None


class OmniVoiceTtsRequest(BaseModel):
    """Synthesize speech from text."""
    text: str = Field(..., min_length=1, max_length=5000, description="Text to synthesize")
    mode: str = Field("auto", description="Generation mode: auto, design, clone")
    # Voice design
    instruct: Optional[str] = Field(None, description='Voice design: e.g. "female, young adult, high pitch"')
    # Emotion mapping (CorelIA TtsEmotion)
    emotion: Optional[str] = Field(None, description="CorelIA emotion: neutral, joyful, sad, serious, excited, cheerful, friendly")
    # Generation params
    quality: str = Field("fast", description="Quality mode: fast (num_step=16) or hq (num_step=32)")
    speed: float = Field(DEFAULT_SPEED, ge=0.5, le=2.0, description="Speed factor")
    duration: Optional[float] = Field(None, ge=1.0, le=60.0, description="Fixed duration in seconds")
    denoise: bool = Field(True, description="Prepend denoise token for cleaner speech")
    # Pro status
    is_pro: bool = Field(False, description="Whether user has Pro subscription")


class OmniVoiceTtsResponse(BaseModel):
    """TTS response metadata (audio returned as WAV bytes in Response body)."""
    duration_seconds: float
    mode_used: str
    instruct_used: Optional[str] = None
    sample_rate: int = 24000


class VoiceDesignPreviewRequest(BaseModel):
    """Preview a voice design combination."""
    text: str = Field(..., min_length=1, max_length=500)
    gender: Optional[str] = Field(None, description="male, female")
    age: Optional[str] = Field(None, description="child, teenager, young adult, middle-aged, elderly")
    pitch: Optional[str] = Field(None, description="very low pitch, low pitch, moderate pitch, high pitch, very high pitch")
    accent: Optional[str] = Field(None, description="american accent, british accent, french accent, etc.")
    style: Optional[str] = Field(None, description="whisper")


# ── Endpoints ────────────────────────────────────────────────────────────────

@router.get("/status", response_model=VoiceStatusResponse)
async def voice_status(_auth: str = Depends(require_client_api_key)) -> VoiceStatusResponse:
    """Return OmniVoice engine status (GPU, availability, etc.)."""
    status = OmniVoiceTTSEngine.get_status()
    return VoiceStatusResponse(**status)


@router.post("/omnivoice")
async def omnivoice_tts(
    request: Request,
    body: OmniVoiceTtsRequest,
    _auth: str = Depends(require_client_api_key),
) -> Response:
    """
    Synthesize speech from text using OmniVoice.
    
    Returns WAV audio bytes (Content-Type: audio/wav).
    """
    # Resolve mode
    try:
        mode = TtsMode(body.mode)
    except ValueError:
        raise HTTPException(status_code=400, detail=f"Invalid mode: {body.mode}. Use: auto, design, clone")

    # Resolve quality
    num_steps = DEFAULT_NUM_STEPS if body.quality == "hq" else FAST_NUM_STEPS
    
    tts_request = TtsRequest(
        text=body.text,
        mode=mode,
        instruct=body.instruct,
        emotion=body.emotion,
        num_steps=num_steps,
        speed=body.speed,
        duration=body.duration,
        denoise=body.denoise,
        is_pro=body.is_pro,
    )

    try:
        # Run CPU-bound TTS in thread pool to avoid blocking async event loop
        loop = asyncio.get_event_loop()
        response = await loop.run_in_executor(
            None, OmniVoiceTTSEngine.synthesize, tts_request
        )
    except RuntimeError as e:
        raise HTTPException(status_code=503, detail=str(e))
    except Exception as e:
        logger.exception("OmniVoice TTS failed")
        raise HTTPException(status_code=500, detail=f"TTS synthesis failed: {e}")

    return Response(
        content=response.audio_bytes,
        media_type="audio/wav",
        headers={
            "X-Audio-Duration": str(response.duration_seconds),
            "X-Tts-Mode": response.mode_used.value,
            "X-Tts-Instruct": response.instruct_used or "",
            "X-Sample-Rate": str(response.sample_rate),
        },
    )


@router.post("/omnivoice/stream")
async def omnivoice_tts_stream(
    request: Request,
    body: OmniVoiceTtsRequest,
    _auth: str = Depends(require_client_api_key),
) -> StreamingResponse:
    """
    Stream audio chunks via SSE (Server-Sent Events).
    
    Each chunk is a base64-encoded WAV segment.
    Events:
      - `data: {"type": "chunk", "index": 0, "audio": "<base64>"}`
      - `data: {"type": "done", "total_duration": 5.2}`
      - `data: {"type": "error", "message": "..."}`
    
    Useful for reducing Time-To-First-Audio on mobile.
    """
    try:
        mode = TtsMode(body.mode)
    except ValueError:
        raise HTTPException(status_code=400, detail=f"Invalid mode: {body.mode}")

    num_steps = DEFAULT_NUM_STEPS if body.quality == "hq" else FAST_NUM_STEPS
    
    tts_request = TtsRequest(
        text=body.text,
        mode=mode,
        instruct=body.instruct,
        emotion=body.emotion,
        num_steps=num_steps,
        speed=body.speed,
        duration=body.duration,
        denoise=body.denoise,
        is_pro=body.is_pro,
    )

    async def event_stream():
        import json, base64
        try:
            loop = asyncio.get_event_loop()
            tts_response = await loop.run_in_executor(
                None, OmniVoiceTTSEngine.synthesize, tts_request
            )
            # For now, send as single chunk (OmniVoice generates full audio, 
            # not incremental). Future: use audio_chunk_duration for streaming.
            audio_b64 = base64.b64encode(tts_response.audio_bytes).decode("ascii")
            yield f"data: {json.dumps({'type': 'chunk', 'index': 0, 'audio': audio_b64})}\n\n"
            yield f"data: {json.dumps({'type': 'done', 'total_duration': tts_response.duration_seconds})}\n\n"
        except Exception as e:
            yield f"data: {json.dumps({'type': 'error', 'message': str(e)})}\n\n"

    return StreamingResponse(
        event_stream(),
        media_type="text/event-stream",
        headers={
            "Cache-Control": "no-cache",
            "Connection": "keep-alive",
        },
    )


@router.post("/design")
async def voice_design_preview(
    request: Request,
    body: VoiceDesignPreviewRequest,
    _auth: str = Depends(require_client_api_key),
) -> Response:
    """
    Preview a voice design combination.
    
    Builds an `instruct` string from individual attributes and returns WAV.
    """
    parts = []
    if body.gender:
        parts.append(body.gender)
    if body.age:
        parts.append(body.age)
    if body.pitch:
        parts.append(body.pitch)
    if body.accent:
        parts.append(body.accent)
    if body.style:
        parts.append(body.style)
    
    if not parts:
        raise HTTPException(status_code=400, detail="At least one design attribute required")
    
    instruct = ", ".join(parts)
    
    tts_request = TtsRequest(
        text=body.text,
        mode=TtsMode.design,
        instruct=instruct,
        num_steps=FAST_NUM_STEPS,  # Preview = fast mode
    )

    try:
        loop = asyncio.get_event_loop()
        response = await loop.run_in_executor(
            None, OmniVoiceTTSEngine.synthesize, tts_request
        )
    except RuntimeError as e:
        raise HTTPException(status_code=503, detail=str(e))

    return Response(
        content=response.audio_bytes,
        media_type="audio/wav",
        headers={
            "X-Audio-Duration": str(response.duration_seconds),
            "X-Tts-Instruct": instruct,
        },
    )


@router.post("/clone")
async def voice_clone(
    request: Request,
    text: str = Form(..., min_length=1, max_length=5000),
    ref_audio: UploadFile = File(..., description="Reference audio (WAV, 3-10s)"),
    ref_text: Optional[str] = Form(None, description="Transcript of reference audio"),
    quality: str = Form("fast"),
    _auth: str = Depends(require_client_api_key),
) -> Response:
    """
    Clone a voice from reference audio and synthesize new speech.
    
    Upload a 3-10 second reference WAV file. OmniVoice will clone the
    speaker's voice and synthesize the provided text.
    """
    import tempfile, os
    
    # Save uploaded audio to temp file
    suffix = ".wav"
    if ref_audio.filename and ref_audio.filename.lower().endswith(".mp3"):
        suffix = ".mp3"
    
    try:
        audio_data = await ref_audio.read()
        with tempfile.NamedTemporaryFile(suffix=suffix, delete=False) as tmp:
            tmp.write(audio_data)
            tmp_path = tmp.name
        
        num_steps = DEFAULT_NUM_STEPS if quality == "hq" else FAST_NUM_STEPS
        
        tts_request = TtsRequest(
            text=text,
            mode=TtsMode.clone,
            ref_audio_path=tmp_path,
            ref_text=ref_text,
            num_steps=num_steps,
        )

        loop = asyncio.get_event_loop()
        response = await loop.run_in_executor(
            None, OmniVoiceTTSEngine.synthesize, tts_request
        )
        
        return Response(
            content=response.audio_bytes,
            media_type="audio/wav",
            headers={
                "X-Audio-Duration": str(response.duration_seconds),
                "X-Tts-Mode": "clone",
            },
        )
    except RuntimeError as e:
        raise HTTPException(status_code=503, detail=str(e))
    finally:
        try:
            os.unlink(tmp_path)
        except Exception:
            pass
