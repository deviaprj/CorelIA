"""Search engine with DuckDuckGo primary and SerpAPI fallback."""

from typing import Any

import httpx

from backend.core.config import settings
from backend.core.logging import get_logger
from backend.schemas.chat import SearchResponse, SearchResult

logger = get_logger(__name__)


async def search_duckduckgo(query: str, num_results: int = 5) -> SearchResponse:
    """Search using DuckDuckGo (primary)."""
    from duckduckgo_search import DDGS

    results: list[SearchResult] = []
    try:
        with DDGS() as ddgs:
            ddg_results = ddgs.text(query, max_results=num_results)
            for item in ddg_results:
                results.append(
                    SearchResult(
                        title=item.get("title", ""),
                        url=item.get("href", ""),
                        snippet=item.get("body", ""),
                        source="duckduckgo",
                    )
                )
    except Exception as exc:
        logger.warning("DuckDuckGo search failed", extra={"error": str(exc)})
        raise

    return SearchResponse(
        query=query,
        results=results,
        total_results=len(results),
    )


async def search_serpapi(query: str, num_results: int = 5) -> SearchResponse:
    """Search using SerpAPI (fallback)."""
    if not settings.serpapi_key:
        raise RuntimeError("SerpAPI key not configured")

    url = "https://serpapi.com/search"
    params: dict[str, Any] = {
        "q": query,
        "engine": "google",
        "api_key": settings.serpapi_key,
        "num": num_results,
    }

    async with httpx.AsyncClient(timeout=30.0) as client:
        response = await client.get(url, params=params)
        response.raise_for_status()
        data = response.json()

    organic = data.get("organic_results", [])
    results: list[SearchResult] = []
    for item in organic[:num_results]:
        results.append(
            SearchResult(
                title=item.get("title", ""),
                url=item.get("link", ""),
                snippet=item.get("snippet", ""),
                source="serpapi",
            )
        )

    return SearchResponse(
        query=query,
        results=results,
        total_results=len(results),
    )


async def search(query: str, num_results: int = 5) -> SearchResponse:
    """Search with DuckDuckGo, fallback to SerpAPI."""
    try:
        return await search_duckduckgo(query, num_results)
    except Exception:
        logger.info("Falling back to SerpAPI")
        return await search_serpapi(query, num_results)
