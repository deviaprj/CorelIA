"""
OmniVoice TTS service — state-of-the-art multilingual zero-shot TTS.

Supports 646 languages (French: 23 675h training), voice cloning, voice design,
non-verbal tags ([laughter], [sigh], ...), and fine-grained generation control.

GPU auto-detection: CUDA → MPS → XPU → CPU fallback.
Model is lazy-loaded on first use to avoid blocking startup.
"""

from __future__ import annotations

import io
import logging
from dataclasses import dataclass, field
from enum import Enum
from pathlib import Path
from typing import Optional

import numpy as np
import soundfile as sf
import torch

logger = logging.getLogger(__name__)

# ── Constants from OmniVoice docs ────────────────────────────────────────────

# Optimal params (from docs/generation-parameters.md)
DEFAULT_NUM_STEPS = 32       # Quality mode (Pro, GPU)
FAST_NUM_STEPS = 12          # Speed mode (free, CPU — 2.5x faster than 32)
ULTRA_FAST_NUM_STEPS = 8     # Ultra-fast for CPU-only (emergency fallback)
DEFAULT_GUIDANCE_SCALE = 2.0
DEFAULT_T_SHIFT = 0.1
DEFAULT_SPEED = 1.0
SAMPLE_RATE = 24000          # OmniVoice native sample rate

# Emotional voice design mapping (CorelIA emotion → OmniVoice instruct)
EMOTION_INSTRUCT_MAP: dict[str, str] = {
    "neutral":  "moderate pitch",
    "joyful":   "female, young adult, high pitch",
    "sad":      "low pitch",
    "serious":  "male, middle-aged, moderate pitch",
    "excited":  "female, young adult, very high pitch",
    "cheerful": "female, young adult, high pitch",
    "friendly": "female, young adult, moderate pitch",
}


class TtsMode(str, Enum):
    """TTS generation mode."""
    auto = "auto"            # Random voice
    design = "design"        # Voice design via instruct
    clone = "clone"          # Voice cloning via ref_audio


@dataclass
class TtsRequest:
    """Request to synthesize speech."""
    text: str
    mode: TtsMode = TtsMode.auto
    # Voice design
    instruct: Optional[str] = None       # e.g. "female, young adult, high pitch"
    # Voice cloning
    ref_audio_path: Optional[str] = None  # Path to reference WAV
    ref_text: Optional[str] = None        # Transcript of reference audio
    # Emotion mapping (CorelIA TtsEmotion → OmniVoice instruct)
    emotion: Optional[str] = None
    # Generation params
    num_steps: int = DEFAULT_NUM_STEPS
    speed: float = DEFAULT_SPEED
    duration: Optional[float] = None      # Fixed output duration (seconds)
    guidance_scale: float = DEFAULT_GUIDANCE_SCALE
    denoise: bool = True
    # Processing
    postprocess_output: bool = True       # Remove trailing silence
    # Pro status (quality mode for subscribers)
    is_pro: bool = False


@dataclass  
class TtsResponse:
    """Synthesized speech response."""
    audio_bytes: bytes                    # WAV file bytes
    sample_rate: int = SAMPLE_RATE
    duration_seconds: float = 0.0
    mode_used: TtsMode = TtsMode.auto
    instruct_used: Optional[str] = None


class OmniVoiceTTSEngine:
    """
    OmniVoice TTS engine with lazy model loading and GPU auto-detection.
    
    Thread-safe singleton — model is loaded once, inference is serialized
    (OmniVoice is not thread-safe for concurrent generation).
    """

    _instance: Optional["OmniVoiceTTSEngine"] = None
    _model: Optional[object] = None       # OmniVoice model instance
    _device: str = "cpu"
    _dtype: torch.dtype = torch.float32
    _model_loading: bool = False
    _model_available: bool = False
    _load_error: Optional[str] = None

    def __new__(cls) -> "OmniVoiceTTSEngine":
        if cls._instance is None:
            cls._instance = super().__new__(cls)
        return cls._instance

    @classmethod
    def detect_device(cls) -> tuple[str, torch.dtype]:
        """Auto-detect best available GPU backend (CUDA > MPS > XPU > CPU)."""
        if torch.cuda.is_available():
            return "cuda:0", torch.float16
        if hasattr(torch.backends, "mps") and torch.backends.mps.is_available():
            return "mps", torch.float16
        if hasattr(torch, "xpu") and torch.xpu.is_available():
            return "xpu:0", torch.float16
        return "cpu", torch.float32

    @classmethod
    def is_available(cls) -> bool:
        """Check if OmniVoice package is installed."""
        if cls._model_available:
            return True
        try:
            import omnivoice  # noqa: F401
            return True
        except ImportError:
            return False

    @classmethod
    def load_model(cls, force_reload: bool = False) -> bool:
        """
        Lazy-load the OmniVoice model. Non-blocking on import.
        
        Returns True if model loaded successfully, False otherwise.
        """
        if cls._model_available and not force_reload:
            return True
        
        if cls._model_loading:
            return False  # Already loading in another thread
        
        cls._model_loading = True
        try:
            from omnivoice import OmniVoice
            
            device, dtype = cls.detect_device()
            cls._device = device
            cls._dtype = dtype
            
            logger.info(
                "Loading OmniVoice model on %s (dtype=%s)...",
                device,
                str(dtype).replace("torch.", ""),
            )
            
            cls._model = OmniVoice.from_pretrained(
                "k2-fsa/OmniVoice",
                device_map=device,
                dtype=dtype,
                load_asr=True,  # Whisper ASR for auto-transcribing ref_audio
            )
            cls._model_available = True
            cls._load_error = None
            logger.info("OmniVoice model loaded successfully on %s", device)
            return True
            
        except ImportError:
            cls._load_error = "OmniVoice package not installed. Run: pip install omnivoice"
            logger.warning(cls._load_error)
            return False
        except Exception as e:
            cls._load_error = f"Failed to load OmniVoice model: {e}"
            logger.error(cls._load_error)
            return False
        finally:
            cls._model_loading = False

    @classmethod
    def synthesize(cls, request: TtsRequest) -> TtsResponse:
        """
        Synthesize speech from text using OmniVoice.
        
        Args:
            request: TtsRequest with text, mode, and generation params.
            
        Returns:
            TtsResponse with WAV bytes and metadata.
            
        Raises:
            RuntimeError: If model is not available.
        """
        if not cls._model_available:
            if not cls.load_model():
                raise RuntimeError(cls._load_error or "OmniVoice model unavailable")

        assert cls._model is not None

        # ── Resolve mode ──────────────────────────────────────────────────
        # NOTE: Voice Design (instruct) is trained on English + Chinese only.
        # For French and other languages, Auto Voice is the most reliable mode.
        # We only use design mode when the user explicitly requests it with
        # a valid instruct string AND the text is likely English.
        instruct: Optional[str] = None
        ref_audio = None
        ref_text = None
        mode = request.mode

        # Only attempt voice design for explicit instruct requests
        if request.instruct:
            instruct = request.instruct
            if mode == TtsMode.auto:
                mode = TtsMode.design
        # Emotion is logged but NOT forced to design mode (unreliable for FR)
        elif request.emotion:
            instruct = EMOTION_INSTRUCT_MAP.get(request.emotion)
            # Keep auto mode — don't force design for non-English languages

        # Voice cloning (most reliable for any language)
        if mode == TtsMode.clone and request.ref_audio_path:
            ref_audio = request.ref_audio_path
            ref_text = request.ref_text

        # ── Generation params ─────────────────────────────────────────────
        # CPU-optimized: use ULTRA_FAST for non-Pro on CPU devices
        steps = request.num_steps
        if not request.is_pro:
            if cls._device == "cpu":
                steps = ULTRA_FAST_NUM_STEPS  # 8 steps for CPU
            else:
                steps = FAST_NUM_STEPS       # 12 steps for GPU
        
        gen_kwargs: dict = {
            "text": request.text,
            "num_step": steps,
            "guidance_scale": request.guidance_scale,
            "denoise": request.denoise,
            "postprocess_output": request.postprocess_output,
        }

        if ref_audio is not None:
            gen_kwargs["ref_audio"] = ref_audio
            if ref_text is not None:
                gen_kwargs["ref_text"] = ref_text

        if instruct is not None and mode == TtsMode.design:
            gen_kwargs["instruct"] = instruct

        if request.duration is not None:
            gen_kwargs["duration"] = request.duration
        elif request.speed != 1.0:
            gen_kwargs["speed"] = request.speed

        # ── Generate ────────────────────────────────────────────────────────
        logger.debug(
            "OmniVoice synthesize: mode=%s, text_len=%d, instruct=%s, steps=%d, device=%s",
            mode.value, len(request.text), instruct, gen_kwargs["num_step"], cls._device,
        )

        try:
            audio_list = cls._model.generate(**gen_kwargs)
            audio = audio_list[0]  # First (only) item
            
            # Ensure float32 for WAV export
            if audio.dtype != np.float32:
                audio = audio.astype(np.float32)
            
            # Clamp to [-1, 1] to avoid clipping
            audio = np.clip(audio, -1.0, 1.0)
            
            # Encode as WAV in memory
            buffer = io.BytesIO()
            sf.write(buffer, audio, SAMPLE_RATE, format="WAV", subtype="PCM_16")
            audio_bytes = buffer.getvalue()
            
            duration = len(audio) / SAMPLE_RATE
            
            logger.info(
                "OmniVoice synthesized: %.1fs audio, %d bytes, mode=%s",
                duration, len(audio_bytes), mode.value,
            )
            
            return TtsResponse(
                audio_bytes=audio_bytes,
                sample_rate=SAMPLE_RATE,
                duration_seconds=round(duration, 2),
                mode_used=mode,
                instruct_used=instruct,
            )
            
        except Exception as e:
            logger.error("OmniVoice synthesis failed: %s", e)
            raise RuntimeError(f"TTS synthesis failed: {e}") from e

    @classmethod
    def get_status(cls) -> dict:
        """Return engine status for health checks."""
        return {
            "available": cls._model_available,
            "device": cls._device,
            "dtype": str(cls._dtype).replace("torch.", ""),
            "error": cls._load_error,
            "package_installed": cls.is_available(),
        }
