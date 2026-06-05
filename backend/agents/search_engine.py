"""Search engine with DuckDuckGo primary and SerpAPI fallback."""

from typing import Any

import httpx
from bs4 import BeautifulSoup

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


async def scrape_url(url: str, selectors: dict[str, str] | None = None) -> dict[str, Any]:
    """Scrape a URL and extract structured data using CSS selectors.

    If no selectors are provided, attempts auto-extraction of common patterns
    (prices, titles, links) from the page.
    """
    async with httpx.AsyncClient(timeout=30.0, follow_redirects=True) as client:
        headers = {
            "User-Agent": (
                "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 "
                "(KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
            ),
            "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
            "Accept-Language": "fr-FR,fr;q=0.9,en-US;q=0.8,en;q=0.7",
        }
        response = await client.get(url, headers=headers)
        response.raise_for_status()
        html = response.text

    soup = BeautifulSoup(html, "html.parser")

    # Remove script/style tags
    for tag in soup(["script", "style", "nav", "footer", "header"]):
        tag.decompose()

    result: dict[str, Any] = {"url": url, "title": "", "data": []}
    title_tag = soup.find("title")
    if title_tag and isinstance(title_tag, BeautifulSoup):
        result["title"] = title_tag.get_text(strip=True)
    elif title_tag:
        result["title"] = str(title_tag)

    if selectors:
        # Extract using provided CSS selectors
        for key, selector in selectors.items():
            elements = soup.select(selector)
            result["data"].append({
                "field": key,
                "selector": selector,
                "values": [el.get_text(strip=True) for el in elements[:20]],
            })
    else:
        # Auto-extraction: metadata
        meta_tags: dict[str, str] = {}
        for meta in soup.find_all("meta"):
            name = meta.get("name", "") or meta.get("property", "")
            content = meta.get("content", "")
            if name and content:
                meta_tags[name] = content
        if meta_tags:
            result["data"].append({
                "field": "metadata",
                "values": [{"name": k, "content": v} for k, v in list(meta_tags.items())[:20]],
            })

        # Auto-extraction: look for common price patterns, product cards, etc.
        # Pattern 1: elements containing currency symbols
        price_patterns = [
            r"\d{1,3}(?:[\s \xa0]?\d{3})*[\.,]\d{2}\s?[€$£]",
            r"\d{1,3}(?:[\s \xa0]?\d{3})*\s?[€$£]",
        ]
        import re
        found_prices: list[str] = []
        for elem in soup.find_all(text=re.compile(price_patterns[0])):
            text = str(elem).strip()
            if len(text) < 200:  # Avoid huge text blocks
                matches = re.findall(price_patterns[0], text)
                found_prices.extend(matches)
        if found_prices:
            result["data"].append({
                "field": "prices",
                "values": list(dict.fromkeys(found_prices))[:10],  # dedup, max 10
            })

        # Pattern 2: common product/flight card classes
        card_selectors = [
            "[class*='result']", "[class*='item']", "[class*='card']",
            "[class*='offer']", "[class*='flight']", "[class*='hotel']",
            "[class*='product']", "[class*='deal']",
        ]
        cards: list[dict[str, str]] = []
        for selector in card_selectors:
            for elem in soup.select(selector)[:5]:
                text = elem.get_text(separator=" ", strip=True)
                if len(text) > 30 and len(text) < 500:
                    cards.append({"text": text[:400], "class": elem.get("class", [""])[0]})
        if cards:
            # Deduplicate by text
            seen = set()
            unique_cards = []
            for c in cards:
                if c["text"] not in seen:
                    seen.add(c["text"])
                    unique_cards.append(c)
            result["data"].append({
                "field": "cards",
                "values": unique_cards[:8],
            })

        # Pattern 3: all links with text
        links: list[dict[str, str]] = []
        for a in soup.find_all("a", href=True)[:20]:
            text = a.get_text(strip=True)
            href = a["href"]
            if text and len(text) > 5 and len(text) < 100 and href.startswith("http"):
                links.append({"text": text, "url": href})
        if links:
            result["data"].append({
                "field": "links",
                "values": links[:10],
            })

    return result
