"""FastAPI application entry point."""

from contextlib import asynccontextmanager
from typing import Any, AsyncGenerator

import redis.asyncio as redis
from fastapi import Depends, FastAPI, Request, status
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
from slowapi import Limiter, _rate_limit_exceeded_handler
from slowapi.errors import RateLimitExceeded
from slowapi.util import get_remote_address

from backend.agents.agent_router import router as agent_router
from backend.agents.chat_router import router as chat_router
from backend.agents.config_agent import router as config_router
from backend.agents.data_insights import router as insights_router
from backend.agents.search_engine import search
from backend.core.auth import require_client_api_key, require_operator_key
from backend.core.config import settings
from backend.core.logging import get_logger, set_request_id
from backend.core.skills_discovery import discover_skills, load_skill
from backend.schemas.chat import SearchResponse, DownloadMediaRequest, DownloadMediaResponse, CrawlRequest, CrawlResponse, ScriptExecutionRequest, ScriptExecRequest, ApiFetchRequest, ScriptExecutionResponse

logger = get_logger(__name__)

# Rate limiter backed by Redis
_limiter = Limiter(
    key_func=get_remote_address,
    storage_uri=settings.redis_url,
    strategy="fixed-window",
)


@asynccontextmanager
async def lifespan(app: FastAPI) -> AsyncGenerator[None, None]:
    """Application lifespan handler."""
    logger.info("Starting up", extra={"app": settings.app_name, "env": settings.app_env})
    # Verify Redis connectivity on startup (skip for memory:// fallback)
    if not settings.redis_url.startswith('memory://'):
      try:
          r = redis.from_url(settings.redis_url)
          await r.ping()
          await r.close()
          logger.info("Redis connected")
      except Exception as exc:
          logger.warning("Redis not available; rate limiting may use memory fallback", extra={"error": str(exc)})
    else:
        logger.info("Rate limiting using in-memory fallback (no Redis)")
    yield
    logger.info("Shutting down")


app = FastAPI(
    title=settings.app_name,
    version="1.0.0",
    docs_url="/docs" if settings.debug else None,
    redoc_url="/redoc" if settings.debug else None,
    lifespan=lifespan,
)
app.state.limiter = _limiter
app.add_exception_handler(RateLimitExceeded, _rate_limit_exceeded_handler)

# CORS — wildcard origins + credentials is an invalid combo (browsers reject it
# and it widens the attack surface). Disable credentials only when the origin
# list is the wildcard "*"; tighten methods/headers to what clients actually use.
# In production docker-compose sets CORS_ORIGINS to explicit origins (non-wildcard),
# which re-enables credentials.
_is_wildcard_origin = "*" in settings.cors_origins_list
app.add_middleware(
    CORSMiddleware,
    allow_origins=settings.cors_origins_list,
    allow_credentials=not _is_wildcard_origin,
    allow_methods=["GET", "POST", "DELETE", "OPTIONS"],
    allow_headers=["Content-Type", "Authorization", "X-API-Key", "X-Request-ID"],
)


@app.middleware("http")
async def request_id_middleware(request: Request, call_next):  # type: ignore[no-untyped-def]
    """Attach a request ID to every incoming request for tracing."""
    import uuid as _uuid
    rid = request.headers.get("X-Request-ID") or str(_uuid.uuid4())
    set_request_id(rid)
    response = await call_next(request)
    response.headers["X-Request-ID"] = rid
    return response


@app.get("/health", status_code=status.HTTP_200_OK)
@_limiter.limit(settings.rate_limit)
async def health_check(request: Request) -> dict[str, str]:
    """Health check endpoint."""
    return {"status": "ok", "env": settings.app_env}


@app.get("/search", response_model=SearchResponse)
@_limiter.limit(settings.rate_limit)
async def search_endpoint(request: Request, q: str) -> SearchResponse:
    """Web search endpoint."""
    return await search(q, num_results=5)


@app.get("/scrape")
@_limiter.limit(settings.rate_limit)
async def scrape_endpoint(
    request: Request,
    url: str,
    selectors: str | None = None,
    _auth: str = Depends(require_client_api_key),
) -> dict[str, Any]:
    """Scrape a URL and return structured data.

    - url: target URL to scrape
    - selectors: optional JSON dict of CSS selectors, e.g. {"price": ".price"}
    """
    from backend.agents.search_engine import scrape_url

    parsed_selectors: dict[str, str] | None = None
    if selectors:
        import json as _json
        try:
            parsed_selectors = _json.loads(selectors)
        except Exception:
            pass

    return await scrape_url(url, selectors=parsed_selectors)


@app.get("/search_smart")
@_limiter.limit(settings.rate_limit)
async def search_smart_endpoint(
    request: Request,
    q: str,
    _auth: str = Depends(require_client_api_key),
) -> dict[str, Any]:
    """Unified smart search endpoint.

    Analyzes the natural-language query, classifies intent, scrapes
    multiple sources in parallel, and returns structured results.
    """
    from backend.agents.search_smart import search_smart
    return await search_smart(q)


@app.post("/download_media", response_model=DownloadMediaResponse)
@_limiter.limit(settings.rate_limit)
async def download_media_endpoint(
    request: Request,
    body: DownloadMediaRequest,
    _auth: str = Depends(require_client_api_key),
) -> DownloadMediaResponse:
    """Extract direct media URLs from a webpage or video site.

    - **Video sites** (YouTube, Vimeo, TikTok, etc.): uses yt-dlp to resolve
      direct stream URLs and available quality formats.
    - **Generic pages**: scrapes `<video>`, `<img>`, OpenGraph tags, JSON-LD,
      CSS backgrounds, and common gallery patterns for images and videos.
    """
    from backend.agents.download_service import DownloadService

    service = DownloadService()
    try:
        # ``extract_media`` is now async (yt-dlp runs in a subprocess sandbox,
        # page scraping uses httpx.AsyncClient) — awaited directly, no thread
        # pool. See ADR-031.
        result = await service.extract_media(body.url)
        return DownloadMediaResponse(success=True, **result)
    except Exception as exc:
        logger.error("download_media failed", extra={"url": body.url, "error": str(exc)})
        return DownloadMediaResponse(
            success=False,
            error=f"Extraction failed: {exc}",
        )


@app.post("/crawl", response_model=CrawlResponse)
@_limiter.limit(settings.rate_limit)
async def crawl_endpoint(
    request: Request,
    body: CrawlRequest,
    _auth: str = Depends(require_client_api_key),
) -> CrawlResponse:
    """Recursively crawl a website and extract media links.

    HTTrack-style crawler that follows links up to `max_depth` and
    collects videos, images, and direct media URLs.
    """
    from backend.agents.crawl_service import CrawlService

    service = CrawlService(
        max_depth=body.max_depth,
        max_pages=body.max_pages,
        same_domain=body.same_domain,
    )
    try:
        # ``CrawlService.crawl`` is now async (parallel BFS via httpx.AsyncClient
        # + asyncio.gather) — awaited directly, no thread pool. See ADR-031.
        result = await service.crawl(body.url)
        return CrawlResponse(success=True, **result)
    except Exception as exc:
        logger.error("crawl failed", extra={"url": body.url, "error": str(exc)})
        return CrawlResponse(
            success=False,
            errors=[f"Crawl failed: {exc}"],
        )


@app.post("/script/scrape", response_model=ScriptExecutionResponse)
@_limiter.limit(settings.rate_limit)
async def script_scrape_endpoint(
    request: Request,
    body: ScriptExecutionRequest,
    _auth: str = Depends(require_client_api_key),
) -> ScriptExecutionResponse:
    """Generate and execute a Python scraping script from natural language.

    - **url**: target URL to scrape
    - **instruction**: natural language description of what to extract

    The backend uses DeepSeek to generate a Python script that scrapes
    the URL, executes it in a sandbox, and returns structured JSON results.
    """
    from backend.agents.script_executor import scrape_with_script

    result = await scrape_with_script(body.url, body.instruction)
    return ScriptExecutionResponse(**result)


@app.post("/script/exec", response_model=ScriptExecutionResponse)
@_limiter.limit(settings.rate_limit)
async def script_exec_endpoint(
    request: Request,
    body: ScriptExecRequest,
    _auth: str = Depends(require_operator_key),
) -> ScriptExecutionResponse:
    """Generate and execute a Python script from natural-language instructions.

    Operator-only: arbitrary code execution on the server — gated by
    ``API_SECRET_KEY`` (never embedded in the APK/extension). The APK uses
    ``/script/scrape`` and ``/script/api-fetch`` (constrained to a URL), not this.
    """
    from backend.agents.script_executor import exec_with_instruction

    result = await exec_with_instruction(body.instruction)
    return ScriptExecutionResponse(**result)


@app.post("/script/api-fetch", response_model=ScriptExecutionResponse)
@_limiter.limit(settings.rate_limit)
async def script_api_fetch_endpoint(
    request: Request,
    body: ApiFetchRequest,
    _auth: str = Depends(require_client_api_key),
) -> ScriptExecutionResponse:
    """Fetch an API URL and transform JSON per natural-language instructions."""
    from backend.agents.script_executor import api_fetch_with_script

    result = await api_fetch_with_script(body.url, body.instruction)
    return ScriptExecutionResponse(**result)


# ── Skills ──────────────────────────────────────────────────────────────────

@app.get("/skills")
async def skills_list() -> dict[str, Any]:
    """Liste tous les skills disponibles (découverte runtime).

    Inspiré de DeepSeek-TUI / Deep Code — les skills sont des dossiers
    contenant un SKILL.md dans .github/skills/, .codewhale/skills/,
    ~/.agents/skills/, etc.
    """
    skills = discover_skills()
    return {"skills": skills, "total": len(skills)}


@app.get("/skills/{skill_id}")
async def skills_get(skill_id: str) -> dict[str, Any]:
    """Charge le contenu complet d'un skill."""
    skill = load_skill(skill_id)
    if not skill:
        from fastapi import HTTPException
        raise HTTPException(status_code=404, detail=f"Skill '{skill_id}' introuvable")
    return skill


# Include routers
app.include_router(agent_router)
app.include_router(config_router)
app.include_router(chat_router)
app.include_router(insights_router)
