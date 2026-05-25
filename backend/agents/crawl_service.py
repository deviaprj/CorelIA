"""Recursive web crawler with media extraction.

HTTrack-style crawling that discovers pages, extracts media links,
and reconstructs direct video URLs from embeds and players.
"""

from __future__ import annotations

import re
from collections import deque
from typing import Any
from urllib.parse import urljoin, urlparse

import httpx
from bs4 import BeautifulSoup


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

    def crawl(self, start_url: str) -> dict[str, Any]:
        """Crawl starting from a URL and return aggregated media."""
        self._visited.clear()
        self._results.clear()
        queue: deque[tuple[str, int]] = deque([(start_url, 0)])
        domain = urlparse(start_url).netloc

        with httpx.Client(timeout=15, follow_redirects=True, headers=self._headers) as client:
            while queue and len(self._visited) < self.max_pages:
                url, depth = queue.popleft()
                normalized = self._normalize(url)
                if normalized in self._visited:
                    continue
                self._visited.add(normalized)

                result = self._fetch_and_parse(client, url, depth)
                if result:
                    self._results.append(result)
                    if depth < self.max_depth:
                        for link in result.links:
                            parsed = urlparse(link)
                            if self.same_domain and parsed.netloc and parsed.netloc != domain:
                                continue
                            queue.append((link, depth + 1))

        return self._aggregate()

    def _fetch_and_parse(self, client: httpx.Client, url: str, depth: int) -> CrawlResult | None:
        result = CrawlResult(url)
        try:
            resp = client.get(url)
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
        import json
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
