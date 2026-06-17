"""SSRF guard — centralised defence for every outbound fetch the backend makes.

Applied at each fetch site (search_engine, search_smart, download_service,
crawl_service, script_executor) so a user/LLM-supplied URL can never reach the
server's internal network (loopback, private ranges, link-local incl. cloud
metadata 169.254.169.254) or a non-http(s) scheme.

Two entry points:
- ``assert_safe_url(url)`` — validate scheme + host + DNS-resolve + reject
  private/blocked targets. Use this when you only need to validate a URL before
  passing it to a library that does its own fetching (e.g. yt-dlp).
- ``safe_get(client, url, ...)`` / ``safe_get_sync(...)`` — fetch with redirects
  disabled, re-validating each Location hop. Use this when you control the
  httpx call. Redirects can cross into private space even when the start URL is
  public, so per-hop re-validation is required.
"""

import ipaddress
import socket
from typing import Any
from urllib.parse import urljoin, urlsplit

import httpx

_ALLOWED_SCHEMES = {"http", "https"}
# Hostnames that resolve to the host itself or to cloud metadata endpoints.
_BLOCKED_HOSTS = {
    "localhost",
    "ip6-localhost",
    "ip6-loopback",
    "metadata.google.internal",
}
_MAX_REDIRECTS = 4
_REDIRECT_STATUSES = {301, 302, 303, 307, 308}


class UnsafeUrlError(ValueError):
    """Raised when a URL targets a private/blocked/invalid host or scheme."""


def _is_private_ip(ip) -> bool:
    """True for loopback, private, link-local (incl. 169.254.169.254), reserved."""
    return (
        ip.is_private
        or ip.is_loopback
        or ip.is_link_local
        or ip.is_reserved
        or ip.is_multicast
        or ip.is_unspecified
    )


def assert_safe_url(url: str) -> str:
    """Validate ``url`` and resolve its host, rejecting private/blocked targets.

    Returns ``url`` unchanged if safe; raises ``UnsafeUrlError`` otherwise.
    Resolution is done eagerly so a public-looking host that DNS-maps to a
    private address (DNS rebinding) is still caught.
    """
    if not url or not isinstance(url, str):
        raise UnsafeUrlError("Empty URL")
    parts = urlsplit(url)
    scheme = parts.scheme.lower()
    if scheme not in _ALLOWED_SCHEMES:
        raise UnsafeUrlError(f"Scheme not allowed: {parts.scheme!r} (only http/https)")
    host = parts.hostname
    if not host:
        raise UnsafeUrlError("URL has no host")
    if host.lower() in _BLOCKED_HOSTS:
        raise UnsafeUrlError(f"Blocked host: {host}")

    # Resolve and inspect every address (a host may have several, incl. IPv6).
    try:
        infos = socket.getaddrinfo(host, None)
    except socket.gaierror as exc:
        raise UnsafeUrlError(f"Cannot resolve host {host!r}: {exc}") from exc
    addrs = {info[4][0] for info in infos}
    if not addrs:
        raise UnsafeUrlError(f"No address resolved for host {host!r}")
    for addr in addrs:
        try:
            ip = ipaddress.ip_address(addr)
        except ValueError:
            continue
        if _is_private_ip(ip):
            raise UnsafeUrlError(f"Host {host!r} resolves to private address {addr}")
    return url


async def safe_get(
    client: httpx.AsyncClient,
    url: str,
    *,
    headers: dict[str, str] | None = None,
    params: Any | None = None,
) -> httpx.Response:
    """Async GET with redirects disabled + per-hop SSRF re-validation.

    ``follow_redirects=False`` is passed per-request so this works even if the
    client was constructed with ``follow_redirects=True``. Each Location header
    is re-checked with ``assert_safe_url`` before following, up to
    ``_MAX_REDIRECTS`` hops.
    """
    current = assert_safe_url(url)
    req_params = params
    for _ in range(_MAX_REDIRECTS + 1):
        response = await client.get(
            current, headers=headers, params=req_params, follow_redirects=False
        )
        if response.status_code not in _REDIRECT_STATUSES:
            return response
        location = response.headers.get("location")
        if not location:
            return response
        current = assert_safe_url(urljoin(current, location))
        req_params = None  # query params only apply to the first hop
    raise UnsafeUrlError(f"Too many redirects (> {_MAX_REDIRECTS})")


def safe_get_sync(
    client: httpx.Client,
    url: str,
    *,
    headers: dict[str, str] | None = None,
    params: Any | None = None,
) -> httpx.Response:
    """Sync variant of ``safe_get``."""
    current = assert_safe_url(url)
    req_params = params
    for _ in range(_MAX_REDIRECTS + 1):
        response = client.get(
            current, headers=headers, params=req_params, follow_redirects=False
        )
        if response.status_code not in _REDIRECT_STATUSES:
            return response
        location = response.headers.get("location")
        if not location:
            return response
        current = assert_safe_url(urljoin(current, location))
        req_params = None
    raise UnsafeUrlError(f"Too many redirects (> {_MAX_REDIRECTS})")