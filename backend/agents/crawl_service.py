"""Recursive web crawler with media extraction.

HTTrack-style crawling that discovers pages, extracts media links,
and reconstructs direct video URLs from embeds and players.

Async I/O (ADR-031 follow-up): BFS now fetches pages in parallel batches via
``httpx.AsyncClient`` + ``asyncio.gather`` (was a sequential sync ``httpx.Client``
loop that pinned a thread-pool worker for the whole multi-page crawl). The SSRF
guard (``safe_get``, async) is preserved on every fetch with per-redirect
re-validation; every discovered link is re-checked with ``assert_safe_url`` and
the optional same-domain filter before enqueueing.
"""

from __future__ import annotations

import asyncio
import json
import re
from typing import Any
from urllib.parse import urljoin, urlparse

import httpx
from bs4 import BeautifulSoup

from backend.core.net_guard import UnsafeUrlError, assert_safe_url, safe_get


class CrawlResult:
    """Result of crawling a single page."""

    def __init__(self, url: str) -> None:
        self.url = url
        self.title = ""
        self.links: list[str] = []
        self.videos: list[dict[str, Any]] = []
        self.images: list[str] = []
        self.errors: list[str] = []

    def to_dict(self) -> dict[str, Any]:
        return {
            "url": self.url,
            "title": self.title,
            "links": self.links,
            "videos": self.videos,
            "images": self.images,
            "errors": self.errors,
        }


class CrawlService:
    """Crawl a site recursively and extract all media."""

    # File extensions we consider as direct media
    VIDEO_EXTS = (".mp4", ".webm", ".mkv", ".avi", ".mov", ".m3u8", ".ts")
    IMAGE_EXTS = (".jpg", ".jpeg", ".png", ".webp", ".gif", ".bmp", ".svg")

    # Hosts where we should also run yt-dlp for extraction
    YTDLP_HOSTS = re.compile(
        r"(youtube\.com|youtu\.be|vimeo\.com|dailymotion\.com|tiktok\.com|"
        r"twitch\.tv|facebook\.com/watch|instagram\.com/reel|soundcloud\.com|"
        r"reddit\.com|twitter\.com|x\.com|streamable\.com|rumble\.com)",
        re.IGNORECASE,
    )

    # Max pages fetched in parallel per BFS batch. Bounds concurrent
    # connections so a 20-page crawl issues ~5 requests at a time rather than
    # 20 (gentler on the target host and on our connection pool).
    _MAX_CONCURRENT = 5

    def __init__(self, max_depth: int = 2, max_pages: int = 20, same_domain: bool = True) -> None:
        self.max_depth = max_depth
        self.max_pages = max_pages
        self.same_domain = same_domain
        self._visited: set[str] = set()
        self._results: list[CrawlResult] = []
        self._headers = {
            "User-Agent": (
                "Mozilla/5.0 (Windows NT 10.0; Win64; x64) "
                "AppleWebKit/537.36 (KHTML, like Gecko) "
                "Chrome/124.0.0.0 Safari/537.36"
            ),
            "Accept": (
                "text/html,application/xhtml+xml,application/xml;"
                "q=0.9,image/avif,image/webp,*/*;q=0.8"
            ),
        }

    async def crawl(self, start_url: str) -> dict[str, Any]:
        """Crawl starting from a URL and return aggregated media.

        BFS with parallel page fetching: each batch of up to
        ``_MAX_CONCURRENT`` unvisited URLs is fetched concurrently via
        ``asyncio.gather``, then discovered links are enqueued for the next
        batch. The ``max_pages`` budget is enforced when forming a batch
        (visited URLs are marked up-front), so the crawl never overshoots.
        """
        # SSRF guard on the seed URL (also covers yt-dlp paths downstream).
        try:
            assert_safe_url(start_url)
        except UnsafeUrlError as exc:
            return {
                "pages_crawled": 0,
                "total_links_found": 0,
                "videos": [],
                "images": [],
                "errors": [f"URL not allowed: {exc}"],
                "pages": [],
            }
        self._visited.clear()
        self._results.clear()
        queue: list[tuple[str, int]] = [(start_url, 0)]
        domain = urlparse(start_url).netloc

        async with httpx.AsyncClient(timeout=15, headers=self._headers) as client:
            while queue and len(self._visited) < self.max_pages:
                # Collect the next batch of unvisited URLs (up to the
                # concurrency cap and the remaining page budget). Marking them
                # visited here (rather than after the fetch) both deduplicates
                # queue entries and prevents the batch from exceeding the
                # ``max_pages`` budget.
                batch: list[tuple[str, int]] = []
                while (
                    queue
                    and len(self._visited) < self.max_pages
                    and len(batch) < self._MAX_CONCURRENT
                ):
                    url, depth = queue.pop(0)
                    normalized = self._normalize(url)
                    if normalized in self._visited:
                        continue
                    self._visited.add(normalized)
                    batch.append((url, depth))

                if not batch:
                    continue

                # Fetch + parse the batch in parallel. ``_fetch_and_parse``
                # returns a CrawlResult (or None for non-HTML) and never
                # mutates shared state, so the gather is race-free.
                results = await asyncio.gather(
                    *(self._fetch_and_parse(client, url, depth) for url, depth in batch)
                )

                for result, (url, depth) in zip(results, batch):
                    if result is None:
                        continue
                    self._results.append(result)
                    if depth < self.max_depth:
                        for link in result.links:
                            # Re-validate every discovered link before
                            # enqueueing — a same-domain page can still link to
                            # internal hosts (SSRF / redirect traps).
                            try:
                                assert_safe_url(link)
                            except UnsafeUrlError:
                                continue
                            parsed = urlparse(link)
                            if self.same_domain and parsed.netloc and parsed.netloc != domain:
                                continue
                            queue.append((link, depth + 1))

        return self._aggregate()

    async def _fetch_and_parse(
        self, client: httpx.AsyncClient, url: str, depth: int
    ) -> CrawlResult | None:
        result = CrawlResult(url)
        try:
            resp = await safe_get(client, url)
            resp.raise_for_status()
            # Skip non-HTML
            content_type = resp.headers.get("content-type", "").lower()
            if "text/html" not in content_type and "application/xhtml" not in content_type:
                return None

            soup = BeautifulSoup(resp.text, "html.parser")
            result.title = self._get_title(soup)

            # Extract all anchor links for further crawling
            for a in soup.find_all("a", href=True):
                href = urljoin(url, a["href"])
                if href.startswith(("http://", "https://")):
                    result.links.append(href)

            # Extract videos
            result.videos.extend(self._find_video_tags(soup, url))
            result.videos.extend(self._find_video_meta(soup, url))
            result.videos.extend(self._find_iframe_videos(soup, url))
            result.videos.extend(self._find_jsonld_videos(soup, url))
            result.videos.extend(self._find_direct_media_links(result.links, "video"))

            # Extract images
            result.images.extend(self._find_img_tags(soup, url))
            result.images.extend(self._find_css_background_images(soup, url))
            result.images.extend(self._find_direct_media_links(result.links, "image"))

            # Deduplicate
            result.links = list(dict.fromkeys(result.links))
            result.images = list(dict.fromkeys(result.images))
            result.videos = self._dedupe_videos(result.videos)

        except Exception as exc:
            result.errors.append(str(exc))

        return result

    def _aggregate(self) -> dict[str, Any]:
        all_videos: list[dict[str, Any]] = []
        all_images: list[str] = []
        all_links: list[str] = []
        all_errors: list[str] = []

        for r in self._results:
            all_videos.extend(r.videos)
            all_images.extend(r.images)
            all_links.extend(r.links)
            all_errors.extend(r.errors)

        # Deduplicate globally
        all_videos = self._dedupe_videos(all_videos)
        all_images = list(dict.fromkeys(all_images))
        all_links = list(dict.fromkeys(all_links))

        return {
            "pages_crawled": len(self._results),
            "total_links_found": len(all_links),
            "videos": all_videos,
            "images": all_images,
            "errors": all_errors[:10],  # cap errors
            "pages": [r.to_dict() for r in self._results],
        }

    # ── Extractors ──────────────────────────────────────────────────────────────

    def _find_video_tags(self, soup: BeautifulSoup, base_url: str) -> list[dict[str, Any]]:
        results: list[dict[str, Any]] = []
        for video in soup.find_all("video"):
            src = video.get("src") or ""
            if not src:
                for source in video.find_all("source"):
                    src = source.get("src", "")
                    if src:
                        break
            if src:
                results.append({
                    "url": self._abs(base_url, src),
                    "tag": "video",
                    "poster": self._abs(base_url, video.get("poster", "")),
                })
        return results

    def _find_video_meta(self, soup: BeautifulSoup, base_url: str) -> list[dict[str, Any]]:
        results: list[dict[str, Any]] = []
        for prop in ("og:video", "og:video:secure_url", "og:video:url"):
            tag = soup.find("meta", property=prop)
            if tag and tag.get("content"):
                results.append({"url": self._abs(base_url, tag["content"]), "tag": "meta"})
        return results

    def _find_iframe_videos(self, soup: BeautifulSoup, base_url: str) -> list[dict[str, Any]]:
        results: list[dict[str, Any]] = []
        for iframe in soup.find_all("iframe"):
            src = iframe.get("src", "")
            if src and any(
                h in src.lower() for h in ("youtube", "youtu.be", "vimeo", "dailymotion", "tiktok")
            ):
                results.append({"url": self._abs(base_url, src), "tag": "iframe"})
        return results

    def _find_jsonld_videos(self, soup: BeautifulSoup, base_url: str) -> list[dict[str, Any]]:
        results: list[dict[str, Any]] = []
        for script in soup.find_all("script", type="application/ld+json"):
            try:
                data = json.loads(script.string or "")
                items = data if isinstance(data, list) else [data]
                for item in items:
                    if item.get("@type") == "VideoObject":
                        for key in ("contentUrl", "embedUrl", "url"):
                            val = item.get(key)
                            if val and isinstance(val, str):
                                results.append({"url": self._abs(base_url, val), "tag": "jsonld"})
            except Exception:
                continue
        return results

    def _find_img_tags(self, soup: BeautifulSoup, base_url: str) -> list[str]:
        results: list[str] = []
        for img in soup.find_all("img"):
            src = (
                img.get("src")
                or img.get("data-src")
                or img.get("data-lazy-src")
                or img.get("data-original")
                or ""
            )
            if src:
                results.append(self._abs(base_url, src))
        return results

    def _find_css_background_images(self, soup: BeautifulSoup, base_url: str) -> list[str]:
        results: list[str] = []
        for tag in soup.find_all(style=True):
            css = tag.get("style", "")
            for match in re.finditer(r'url\(["\']?([^"\')]+)["\']?\)', css):
                src = match.group(1)
                if src.endswith(self.IMAGE_EXTS):
                    results.append(self._abs(base_url, src))
        return results

    def _find_direct_media_links(
        self, links: list[str], media_type: str
    ) -> list[dict[str, Any]] | list[str]:
        if media_type == "video":
            results: list[dict[str, Any]] = []
            for link in links:
                if link.endswith(self.VIDEO_EXTS):
                    results.append({"url": link, "tag": "direct"})
            return results
        else:
            results: list[str] = []
            for link in links:
                if link.endswith(self.IMAGE_EXTS):
                    results.append(link)
            return results

    # ── Utilities ───────────────────────────────────────────────────────────────

    @staticmethod
    def _abs(base: str, rel: str) -> str:
        if not rel:
            return ""
        if rel.startswith(("http://", "https://", "//")):
            if rel.startswith("//"):
                return "https:" + rel
            return rel
        return urljoin(base, rel)

    @staticmethod
    def _get_title(soup: BeautifulSoup) -> str:
        og = soup.find("meta", property="og:title")
        if og and og.get("content"):
            return og["content"]
        tw = soup.find("meta", attrs={"name": "twitter:title"})
        if tw and tw.get("content"):
            return tw["content"]
        title_tag = soup.find("title")
        if title_tag:
            return title_tag.get_text(strip=True)
        return ""

    @staticmethod
    def _normalize(url: str) -> str:
        # Remove fragment and trailing slash for deduplication
        parsed = urlparse(url)
        return f"{parsed.scheme}://{parsed.netloc}{parsed.path.rstrip('/')}"

    @staticmethod
    def _dedupe_videos(videos: list[dict[str, Any]]) -> list[dict[str, Any]]:
        seen: set[str] = set()
        out: list[dict[str, Any]] = []
        for v in videos:
            u = v.get("url", "")
            if u and u not in seen:
                seen.add(u)
                out.append(v)
        return out