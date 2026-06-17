"""Universal media download service.

Supports 1000+ video sites via yt-dlp and generic page scraping for
videos, images, and galleries on any website.

Async I/O (ADR-031 follow-up): yt-dlp extraction runs in a subprocess sandbox
(``asyncio.create_subprocess_exec`` + ``wait_for`` timeout + kill/reap on
timeout) so it can never freeze the event loop; page scraping uses
``httpx.AsyncClient`` + ``safe_get`` (async SSRF-guarded fetch). The route
handlers no longer need an ``asyncio.to_thread`` stopgap.
"""

from __future__ import annotations

import asyncio
import json
import re
import sys
import textwrap
from typing import Any
from urllib.parse import urljoin

import httpx
from bs4 import BeautifulSoup

from backend.core.net_guard import UnsafeUrlError, assert_safe_url, safe_get

# yt-dlp is optional — if not installed, we fall back to page scraping. The
# library itself is only imported to probe availability; extraction runs in a
# subprocess (see ``_YTDLP_HELPER``) so the parent never calls yt-dlp directly.
try:
    import yt_dlp  # noqa: F401
    _YTDLP_AVAILABLE = True
except ImportError:  # pragma: no cover
    yt_dlp = None  # type: ignore[assignment]
    _YTDLP_AVAILABLE = False


# Subprocess helper that performs the yt-dlp extraction. Takes the URL as
# ``sys.argv[1]`` and the mode ("flat" for channels/playlists, "normal" for a
# single video) as ``sys.argv[2]``. Prints a JSON result on stdout matching the
# shapes the parent used to build in-process. On an internal yt-dlp failure it
# prints ``{"_error": "<message>"}`` and exits 0 so the parent can surface the
# error as an exception (preserving the pre-async success=False behaviour).
#
# Spawned via ``asyncio.create_subprocess_exec`` (no shell) with a hard timeout
# — see ``DownloadService._extract_via_ytdlp``. Reaped on timeout so no zombie
# outlives the request (pattern proven in script_executor.execute_script).
_YTDLP_HELPER = textwrap.dedent("""\
    import json, sys
    import yt_dlp

    def main():
        url = sys.argv[1]
        mode = sys.argv[2] if len(sys.argv) > 2 else "normal"
        opts = {
            "quiet": True,
            "no_warnings": True,
            "skip_download": True,
            "simulate": True,
        }
        if mode == "flat":
            opts["extract_flat"] = True
            opts["playlistend"] = 50
        try:
            with yt_dlp.YoutubeDL(opts) as ydl:
                info = ydl.extract_info(url, download=False)
        except Exception as exc:  # noqa: BLE001 — surface any yt-dlp failure
            print(json.dumps({"_error": str(exc)}))
            return

        if mode == "flat":
            entries = []
            for e in (info.get("entries") or []):
                if not e:
                    continue
                entry_url = e.get("webpage_url") or e.get("url") or ""
                if not entry_url and e.get("id"):
                    entry_url = f"https://www.youtube.com/watch?v={e['id']}"
                entries.append({
                    "title": e.get("title", ""),
                    "url": entry_url,
                    "duration": e.get("duration"),
                })
            print(json.dumps({
                "type": "playlist",
                "title": info.get("title", ""),
                "uploader": info.get("uploader", ""),
                "webpage_url": info.get("webpage_url", url),
                "entries": entries,
            }))
            return

        formats = []
        for f in info.get("formats", []):
            if not f.get("url"):
                continue
            has_audio = f.get("acodec") != "none"
            has_video = f.get("vcodec") != "none"
            if not has_audio and not has_video:
                continue
            formats.append({
                "format_id": f.get("format_id", ""),
                "ext": f.get("ext", ""),
                "quality": f.get("quality_label") or f.get("format_note", ""),
                "filesize": f.get("filesize"),
                "url": f.get("url", ""),
                "has_audio": has_audio,
                "has_video": has_video,
                "resolution": f.get("resolution", ""),
            })

        direct_url = info.get("url") or ""
        if not direct_url and formats:
            merged = next(
                (x for x in formats if x["has_audio"] and x["has_video"]),
                None,
            )
            direct_url = merged["url"] if merged else formats[0]["url"]

        print(json.dumps({
            "type": "video",
            "title": info.get("title", ""),
            "thumbnail": info.get("thumbnail", ""),
            "duration": info.get("duration"),
            "uploader": info.get("uploader", ""),
            "webpage_url": info.get("webpage_url", url),
            "direct_url": direct_url,
            "formats": formats,
        }))

    main()
    """)


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

    # YouTube channel / playlist / user URLs that should use flat extraction
    _YOUTUBE_CHANNEL_PATTERNS = re.compile(
        r"youtube\.com/(@|channel/|c/|user/|playlist\?)",
        re.IGNORECASE,
    )

    # Hard cap on a single yt-dlp extraction (seconds). Video-site extraction
    # can take 10-30s; bounding it prevents a hung subprocess from pinning a
    # worker indefinitely. On timeout the child is killed + reaped.
    _YTDLP_TIMEOUT = 30

    def __init__(self) -> None:
        # Opts are baked into the subprocess helper now — nothing to hold here.
        pass

    # ── Public API ────────────────────────────────────────────────────────────

    async def extract_media(self, url: str) -> dict[str, Any]:
        """Main entry point — returns video info or page media depending on URL."""
        try:
            assert_safe_url(url)
        except UnsafeUrlError as exc:
            return {"type": "error", "url": url, "error": f"URL not allowed: {exc}"}
        if _YTDLP_AVAILABLE and self._is_ytdlp_site(url):
            return await self._extract_via_ytdlp(url)
        return await self._extract_page_media(url)

    async def extract_gallery(self, url: str) -> dict[str, Any]:
        """Focus on images — returns every image found on the page."""
        try:
            assert_safe_url(url)
        except UnsafeUrlError as exc:
            return {"type": "error", "url": url, "error": f"URL not allowed: {exc}"}
        return await self._extract_page_media(url, video_focus=False)

    # ── yt-dlp extraction (1000+ sites, subprocess sandbox) ────────────────────

    def _is_ytdlp_site(self, url: str) -> bool:
        return bool(self._YTDLP_HOSTS.search(url))

    def _is_youtube_channel_or_playlist(self, url: str) -> bool:
        return bool(self._YOUTUBE_CHANNEL_PATTERNS.search(url))

    async def _extract_via_ytdlp(self, url: str) -> dict[str, Any]:
        """Run yt-dlp in an isolated subprocess with a hard timeout.

        The SSRF guard on ``url`` was already performed by the caller
        (``extract_media``). yt-dlp does its own fetching downstream, so — as in
        the sync version — we rely on that single up-front ``assert_safe_url``.
        """
        if not _YTDLP_AVAILABLE:
            raise RuntimeError("yt-dlp not installed")

        mode = "flat" if self._is_youtube_channel_or_playlist(url) else "normal"

        # Spawn the extraction subprocess WITHOUT a shell (argv form) so the
        # event loop keeps serving concurrent requests while yt-dlp runs. This
        # mirrors the proven pattern in ``script_executor.execute_script``.
        # ``sys.executable`` (not bare ``"python3"``) is required: yt-dlp is
        # installed in the backend's venv, so the subprocess must run under the
        # same interpreter to have access to it.
        proc = await asyncio.create_subprocess_exec(
            sys.executable,
            "-c",
            _YTDLP_HELPER,
            url,
            mode,
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.PIPE,
        )
        try:
            stdout_b, stderr_b = await asyncio.wait_for(
                proc.communicate(), timeout=self._YTDLP_TIMEOUT
            )
        except asyncio.TimeoutError:
            # ``wait_for`` raises ``asyncio.TimeoutError`` (the builtin
            # ``TimeoutError`` alias) — NOT ``subprocess.TimeoutExpired``. It
            # cancels ``communicate()`` but does NOT kill the child, so reap it
            # explicitly to avoid a zombie pinning CPU past the deadline. Guard
            # ``proc.kill()`` for the race where the child exited on its own in
            # the window between the timeout firing and the kill.
            try:
                proc.kill()
            except ProcessLookupError:
                pass  # already exited — nothing to signal
            await proc.wait()
            raise RuntimeError(
                f"yt-dlp extraction timed out after {self._YTDLP_TIMEOUT}s"
            )

        stdout = (stdout_b or b"").decode("utf-8", errors="replace").strip()
        stderr = (stderr_b or b"").decode("utf-8", errors="replace").strip()

        if proc.returncode != 0 or not stdout:
            # Nonzero exit (e.g. yt-dlp crashed) or no output → surface as an
            # exception so the route handler returns success=False, matching
            # the pre-async behaviour where a yt-dlp exception propagated.
            raise RuntimeError(
                stderr or "yt-dlp extraction produced no output"
            )

        try:
            data = json.loads(stdout)
        except json.JSONDecodeError as exc:
            raise RuntimeError(f"yt-dlp returned non-JSON output: {exc}") from exc

        # The helper signals an internal yt-dlp failure via ``_error``. Surface
        # it as an exception (→ success=False), matching the sync version where
        # yt-dlp raised ``DownloadError`` and the route handler caught it.
        if isinstance(data, dict) and "_error" in data:
            raise RuntimeError(str(data["_error"]))

        return data

    # ── Universal page scraper ─────────────────────────────────────────────────

    async def _extract_page_media(
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

        # SSRF guard: ``safe_get`` (async) re-validates each redirect hop.
        # ``httpx.AsyncClient`` lets the event loop keep serving other requests
        # while this fetch awaits network I/O.
        async with httpx.AsyncClient(timeout=30, headers=headers) as client:
            resp = await safe_get(client, url)
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