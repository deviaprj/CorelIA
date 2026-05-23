"""FastAPI application entry point."""

from contextlib import asynccontextmanager
from typing import Any, AsyncGenerator

import redis.asyncio as redis
from fastapi import FastAPI, Request, status
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
from slowapi import Limiter, _rate_limit_exceeded_handler
from slowapi.errors import RateLimitExceeded
from slowapi.util import get_remote_address

from backend.agents.chat_router import router as chat_router
from backend.agents.search_engine import search
from backend.core.config import settings
from backend.core.logging import get_logger, set_request_id
from backend.schemas.chat import SearchResponse

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

# CORS
app.add_middleware(
    CORSMiddleware,
    allow_origins=settings.cors_origins_list,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


@app.middleware("http")
async def request_id_middleware(request: Request, call_next):  # type: ignore[no-untyped-def]
    """Attach a request ID to every incoming request for tracing."""
    rid = request.headers.get("X-Request-ID") or str(__import__("uuid").uuid4())
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
async def search_smart_endpoint(request: Request, q: str) -> dict[str, Any]:
    """Unified smart search endpoint.

    Analyzes the natural-language query, classifies intent, scrapes
    multiple sources in parallel, and returns structured results.
    """
    from backend.agents.search_smart import search_smart
    return await search_smart(q)


# Include routers
app.include_router(chat_router)
