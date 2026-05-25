"""Universal media download service.

Supports 1000+ video sites via yt-dlp and generic page scraping for
videos, images, and galleries on any website.
"""

from __future__ import annotations

import json
import re
from typing import Any
from urllib.parse import urljoin

import httpx
from bs4 import BeautifulSoup

# yt-dlp is optional — if not installed, we fall back to page scraping
try:
    import yt_dlp
    _YTDLP_AVAILABLE = True
except ImportError:  # pragma: no cover
    yt_dlp = None  # type: ignore[assignment]
    _YTDLP_AVAILABLE = False


class MediaFormat:
    """A single downloadable media format."""

    def __init__(self, data: dict[str, Any]) -> None:
        self.format_id = data.get("format_id", "")
        self.ext = data.get("ext", "")
        self.quality = data.get("quality_label") or data.get("format_note", "")
        self.filesize = data.get("filesize")
        self.url = data.get("url", "")
        self.has_audio = data.get("acodec") != "none"
        self.has_video = data.get("vcodec") != "none"
        self.resolution = data.get("resolution", "")

    def to_dict(self) -> dict[str, Any]:
        return {
            "format_id": self.format_id,
            "ext": self.ext,
            "quality": self.quality,
            "filesize": self.filesize,
            "url": self.url,
            "has_audio": self.has_audio,
            "has_video": self.has_video,
            "resolution": self.resolution,
        }


class DownloadService:
    """Extract direct media URLs from video sites and web pages."""

    # Sites that yt-dlp handles natively (includes YouTube, Vimeo, TikTok, Twitch, etc.)
    _YTDLP_HOSTS = re.compile(
        r"(youtube\.com|youtu\.be|vimeo\.com|dailymotion\.com|tiktok\.com|"
        r"twitch\.tv|facebook\.com/watch|instagram\.com/reel|x\.com/twitter\.com|"
        r"soundcloud\.com|bandcamp\.com|pornhub\.com|xvideos\.com|reddit\.com|"
        r"twitter\.com|t\.co|streamable\.com|odysee\.com|rumble\.com|bitchute\.com|"
        r"peertube|vid\.li|coub\.com|gfycat\.com|imgur\.com|giphy\.com|"
        r"mediafire\.com|mega\.nz|drive\.google\.com|docs\.google\.com)",
        re.IGNORECASE,
    )

    def __init__(self) -> None:
        self._ydl_opts: dict[str, Any] = {
            "quiet": True,
            "no_warnings": True,
            "skip_download": True,
            "simulate": True,
        }

    # ── Public API ────────────────────────────────────────────────────────────

    def extract_media(self, url: str) -> dict[str, Any]:
        """Main entry point — returns video info or page media depending on URL."""
        if _YTDLP_AVAILABLE and self._is_ytdlp_site(url):
            return self._extract_via_ytdlp(url)
        return self._extract_page_media(url)

    def extract_gallery(self, url: str) -> dict[str, Any]:
        """Focus on images — returns every image found on the page."""
        return self._extract_page_media(url, video_focus=False)

    # ── yt-dlp extraction (1000+ sites) ─────────────────────────────────────────

    def _is_ytdlp_site(self, url: str) -> bool:
        return bool(self._YTDLP_HOSTS.search(url))

    def _extract_via_ytdlp(self, url: str) -> dict[str, Any]:
        if not _YTDLP_AVAILABLE or yt_dlp is None:
            raise RuntimeError("yt-dlp not installed")

        with yt_dlp.YoutubeDL(self._ydl_opts) as ydl:
            info = ydl.extract_info(url, download=False)

        formats: list[dict[str, Any]] = []
        for f in info.get("formats", []):
            if not f.get("url"):
                continue
            mf = MediaFormat(f)
            # Skip audio-only or video-only fragments unless they have a sensible size
            if not mf.has_audio and not mf.has_video:
                continue
            formats.append(mf.to_dict())

        # Also include the "best" pre-merged format if available
        direct_url = info.get("url") or ""
        if not direct_url and formats:
            # Prefer format that has both audio and video
            merged = next(
                (f for f in formats if f["has_audio"] and f["has_video"]),
                None,
            )
            if merged:
                direct_url = merged["url"]
            else:
                direct_url = formats[0]["url"]

        return {
            "type": "video",
            "title": info.get("title", ""),
            "thumbnail": info.get("thumbnail", ""),
            "duration": info.get("duration"),
            "uploader": info.get("uploader", ""),
            "webpage_url": info.get("webpage_url", url),
            "direct_url": direct_url,
            "formats": formats,
        }

    # ── Universal page scraper ─────────────────────────────────────────────────

    def _extract_page_media(
        self,
        url: str,
        video_focus: bool = True,
    ) -> dict[str, Any]:
        headers = {
            "User-Agent": (
                "Mozilla/5.0 (Windows NT 10.0; Win64; x64) "
                "AppleWebKit/537.36 (KHTML, like Gecko) "
                "Chrome/124.0.0.0 Safari/537.36"
            ),
            "Accept": (
                "text/html,application/xhtml+xml,application/xml;"
                "q=0.9,image/avif,image/webp,*/*;q=0.8"
            ),
            "Accept-Language": "en-US,en;q=0.5",
        }

        with httpx.Client(timeout=30, follow_redirects=True, headers=headers) as client:
            resp = client.get(url)
            resp.raise_for_status()
            soup = BeautifulSoup(resp.text, "html.parser")

        videos: list[dict[str, Any]] = []
        images: list[dict[str, Any]] = []

        # ── Videos ──
        if video_focus:
            videos.extend(self._find_video_tags(soup, url))
            videos.extend(self._find_video_meta(soup, url))
            videos.extend(self._find_jsonld_videos(soup, url))
            videos.extend(self._find_iframe_videos(soup, url))

        # ── Images ──
        images.extend(self._find_img_tags(soup, url))
        images.extend(self._find_image_meta(soup, url))
        images.extend(self._find_gallery_patterns(soup, url))
        images.extend(self._find_css_background_images(soup, url))

        # Deduplicate by URL
        videos = self._dedupe(videos, key="url")
        images = self._dedupe(images, key="url")

        # Filter out tiny images (tracking pixels, icons)
        images = [
            img
            for img in images
            if not self._is_tracking_pixel(img.get("url", ""))
        ]

        return {
            "type": "page_media",
            "url": url,
            "title": self._get_page_title(soup),
            "videos": videos,
            "images": images,
        }

    # ── Video finders ────────────────────────────────────────────────────────────

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
                results.append({
                    "url": self._abs(base_url, tag["content"]),
                    "tag": prop,
                })
        for name in ("twitter:player", "twitter:player:stream"):
            tag = soup.find("meta", attrs={"name": name})
            if tag and tag.get("content"):
                results.append({
                    "url": self._abs(base_url, tag["content"]),
                    "tag": name,
                })
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
                    if item.get("@type") == "MediaObject":
                        enc = item.get("encoding") or item.get("contentUrl")
                        if enc and isinstance(enc, str):
                            results.append({"url": self._abs(base_url, enc), "tag": "jsonld"})
            except Exception:
                continue
        return results

    def _find_iframe_videos(self, soup: BeautifulSoup, base_url: str) -> list[dict[str, Any]]:
        results: list[dict[str, Any]] = []
        for iframe in soup.find_all("iframe"):
            src = iframe.get("src", "")
            if src and any(
                h in src.lower()
                for h in ("youtube", "youtu.be", "vimeo", "dailymotion", "tiktok")
            ):
                results.append({"url": self._abs(base_url, src), "tag": "iframe"})
        return results

    # ── Image finders ───────────────────────────────────────────────────────────

    def _find_img_tags(self, soup: BeautifulSoup, base_url: str) -> list[dict[str, Any]]:
        results: list[dict[str, Any]] = []
        for img in soup.find_all("img"):
            src = (
                img.get("src")
                or img.get("data-src")
                or img.get("data-lazy-src")
                or img.get("data-original")
                or img.get("data-srcset", "").split(",")[0].strip().split(" ")[0]
                or ""
            )
            if src:
                results.append({
                    "url": self._abs(base_url, src),
                    "alt": img.get("alt", ""),
                    "width": img.get("width"),
                    "height": img.get("height"),
                    "tag": "img",
                })
        return results

    def _find_image_meta(self, soup: BeautifulSoup, base_url: str) -> list[dict[str, Any]]:
        results: list[dict[str, Any]] = []
        for prop in ("og:image", "og:image:secure_url", "og:image:url", "twitter:image"):
            tag = soup.find("meta", property=prop) or soup.find("meta", attrs={"name": prop})
            if tag and tag.get("content"):
                results.append({
                    "url": self._abs(base_url, tag["content"]),
                    "alt": tag.get("alt", prop),
                    "tag": "meta",
                })
        return results

    def _find_gallery_patterns(self, soup: BeautifulSoup, base_url: str) -> list[dict[str, Any]]:
        results: list[dict[str, Any]] = []
        # Common gallery wrappers
        for sel in (".gallery", ".gallery-item", ".album", ".album-item",
                    ".slideshow", ".carousel", ".lightbox", ".photo-gallery"):
            for el in soup.select(sel):
                img = el.find("img")
                if img:
                    src = img.get("src") or img.get("data-src") or ""
                    if src:
                        results.append({
                            "url": self._abs(base_url, src),
                            "alt": img.get("alt", ""),
                            "tag": "gallery",
                        })
        # JSON image arrays in script tags (common in modern galleries)
        for script in soup.find_all("script"):
            text = script.string or ""
            if not text:
                continue
            for pattern in (
                r'"(?:image|photo|picture|thumb|src)[_\s]*"\s*:\s*"([^"]+\.(?:jpg|jpeg|png|webp|gif))"',
                r"'(?:image|photo|picture|thumb|src)[_\s]*'\s*:\s*'([^']+\.(?:jpg|jpeg|png|webp|gif))'",
            ):
                for match in re.finditer(pattern, text, re.IGNORECASE):
                    src = match.group(1).replace("\\", "")
                    if src.startswith("http"):
                        results.append({"url": src, "alt": "", "tag": "json-script"})
        return results

    def _find_css_background_images(
        self, soup: BeautifulSoup, base_url: str
    ) -> list[dict[str, Any]]:
        results: list[dict[str, Any]] = []
        for style in soup.find_all(style=True):
            css = style.get("style", "")
            for match in re.finditer(r'url\(["\']?([^"\')]+)["\']?\)', css):
                src = match.group(1)
                if src.endswith((".jpg", ".jpeg", ".png", ".webp", ".gif")):
                    results.append({"url": self._abs(base_url, src), "alt": "", "tag": "css-bg"})
        for tag in soup.find_all(["div", "section", "article", "span"]):
            style = tag.get("style", "")
            for match in re.finditer(r'url\(["\']?([^"\')]+)["\']?\)', style):
                src = match.group(1)
                if src.endswith((".jpg", ".jpeg", ".png", ".webp", ".gif")):
                    results.append({"url": self._abs(base_url, src), "alt": "", "tag": "css-bg"})
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
    def _get_page_title(soup: BeautifulSoup) -> str:
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
    def _dedupe(items: list[dict[str, Any]], key: str) -> list[dict[str, Any]]:
        seen: set[str] = set()
        out: list[dict[str, Any]] = []
        for item in items:
            val = str(item.get(key, ""))
            if val and val not in seen:
                seen.add(val)
                out.append(item)
        return out

    @staticmethod
    def _is_tracking_pixel(url: str) -> bool:
        tiny = re.search(r"\b(\d{1,2}x\d{1,2}|1x1|pixel|beacon|tracking|spacer)\b", url, re.I)
        if tiny:
            return True
        # Data URIs are usually tiny icons
        if url.startswith("data:image"):
            return True
        # SVG icons
        if url.endswith(".svg") and ("icon" in url.lower() or "logo" in url.lower()):
            return True
        return False
