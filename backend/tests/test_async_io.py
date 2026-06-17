"""Tests for the async-I/O fixes (Bloc 5, ADR-031).

Covers the blocking-I/O sites that were moved off the event loop:

- ``script_executor.execute_script`` — now spawns the sandbox subprocess via
  ``asyncio.create_subprocess_exec`` (was the synchronous ``subprocess.run``
  that froze the loop for up to 15s).
- ``search_engine._extract_scrape_data`` / ``scrape_url`` — the CPU-bound
  BeautifulSoup parse is offloaded to a worker thread.
- ``search_smart._parse_scraped_page`` / ``_scrape_page`` — same offload.

The pure parse helpers are tested directly (no network); ``execute_script`` is
exercised end-to-end with a real subprocess; and a concurrency test proves the
async subprocess no longer freezes the event loop (the decisive regression
guard for the ``subprocess.run`` → ``create_subprocess_exec`` change).
"""

from __future__ import annotations

import asyncio
import contextlib
import inspect
import time as _time

import pytest

from backend.agents.script_executor import execute_script
from backend.agents.search_engine import _extract_scrape_data, scrape_url
from backend.agents.search_smart import _parse_scraped_page, _scrape_page


# ── Pure parse helpers (no I/O, no network) ───────────────────────────────


def test_extract_scrape_data_metadata_and_title() -> None:
    """Title + meta tags are extracted from raw HTML."""
    html = (
        "<html><head><title>CorelIA — Accueil</title>"
        '<meta name="description" content="Assistant IA"></head>'
        "<body><p>bonjour</p></body></html>"
    )
    result = _extract_scrape_data(html, "https://example.com")
    assert result["url"] == "https://example.com"
    assert result["title"] == "CorelIA — Accueil"
    fields = {d["field"] for d in result["data"]}
    assert "metadata" in fields


def test_extract_scrape_data_links_filters_non_http() -> None:
    """External http(s) links are captured; relative links are dropped."""
    html = (
        "<html><body>"
        '<a href="https://foo.com/page">Foo Page</a>'
        '<a href="https://bar.com">Bar Site</a>'
        '<a href="/relative">Rel</a>'
        "</body></html>"
    )
    result = _extract_scrape_data(html, "https://example.com")
    links = next((d for d in result["data"] if d["field"] == "links"), None)
    assert links is not None
    urls = [link["url"] for link in links["values"]]
    assert "https://foo.com/page" in urls
    assert "https://bar.com" in urls
    assert "/relative" not in urls


def test_extract_scrape_data_custom_selectors() -> None:
    """Caller-provided CSS selectors drive the extraction."""
    html = (
        "<html><body>"
        '<h1 class="title">Titre produit</h1>'
        '<span class="price">29,99 €</span>'
        "</body></html>"
    )
    result = _extract_scrape_data(
        html,
        "https://shop.example.com",
        selectors={"titre": "h1.title", "prix": ".price"},
    )
    by_field = {d["field"]: d["values"] for d in result["data"]}
    assert by_field["titre"] == ["Titre produit"]
    assert by_field["prix"] == ["29,99 €"]


def test_parse_scraped_page_prices_and_title() -> None:
    """_parse_scraped_page extracts the title and detects currency prices.

    Uses ``domain_key=None`` to exercise the auto-detect price-regex path (the
    learned-selector path is domain-specific and covered by the Skyscanner
    entry in ``_LEARNED_SELECTORS``).
    """
    html = (
        "<html><head><title>Vols Paris-Londres</title></head><body>"
        '<div class="result">Paris - Londres 89,50 €</div>'
        '<div class="result">Paris - Londres 102,00 €</div>'
        "</body></html>"
    )
    result = _parse_scraped_page(html, "https://skyscanner.fr")
    assert result["title"] == "Vols Paris-Londres"
    prices = next((d for d in result["data"] if d["field"] == "prices"), None)
    assert prices is not None
    assert any("89,50" in p for p in prices["values"])


def test_parse_scraped_page_links() -> None:
    """External links are extracted from the parsed page."""
    html = (
        "<html><body>"
        '<a href="https://foo.com/article">Article intéressant</a>'
        "</body></html>"
    )
    result = _parse_scraped_page(html, "https://example.com")
    links = next((d for d in result["data"] if d["field"] == "links"), None)
    assert links is not None
    assert any(link["url"] == "https://foo.com/article" for link in links["values"])


# ── Public async entry points still awaitable ─────────────────────────────


def test_async_signatures_preserved() -> None:
    """The refactor keeps the public entry points as coroutines."""
    assert inspect.iscoroutinefunction(scrape_url)
    assert inspect.iscoroutinefunction(_scrape_page)
    assert inspect.iscoroutinefunction(execute_script)


# ── execute_script end-to-end (real subprocess, sandboxed) ────────────────
#
# Scripts use ONLY allow-listed modules (json + builtins) or pure-Python
# constructs — the AST validator (see script_executor._ALLOWED_MODULES)
# rejects os/sys/time/subprocess before any subprocess is spawned, so the
# timeout/hang cases use a bare ``while True: pass`` busy-loop (no imports).


@pytest.mark.asyncio
async def test_execute_script_happy_path() -> None:
    result = await execute_script('import json\nprint(json.dumps({"hello": "corelia"}))')
    assert result["success"] is True
    assert result["data"] == {"hello": "corelia"}


@pytest.mark.asyncio
async def test_execute_script_nonzero_return_is_error() -> None:
    # Unhandled exception → nonzero returncode + traceback on stderr.
    result = await execute_script('raise RuntimeError("boom")')
    assert result["success"] is False
    assert "boom" in result["error"]


@pytest.mark.asyncio
async def test_execute_script_invalid_json_is_reported() -> None:
    result = await execute_script('print("not json")')
    assert result["success"] is False
    assert "not valid JSON" in result["error"]
    assert result.get("raw_output") == "not json"


@pytest.mark.asyncio
async def test_execute_script_ast_rejects_blocked_import() -> None:
    # `os` is denied by the AST validator — rejected before any subprocess.
    result = await execute_script('import os\nprint("ok")')
    assert result["success"] is False
    assert "not allowed" in result["error"].lower()


@pytest.mark.asyncio
async def test_execute_script_timeout_reaps_child_fast() -> None:
    """A hanging script must time out AND be reaped quickly (no 30s wait)."""
    start = _time.monotonic()
    result = await execute_script("while True: pass", timeout=1)
    elapsed = _time.monotonic() - start
    assert result["success"] is False
    assert "timed out" in result["error"].lower()
    # Returns soon after the 1s deadline — proves the timeout is respected
    # and the child is reaped (not left to run the busy-loop indefinitely).
    assert elapsed < 4.0, f"timeout not respected: {elapsed:.1f}s"


@pytest.mark.asyncio
async def test_execute_script_does_not_block_event_loop() -> None:
    """The async subprocess must NOT freeze the event loop while the sandbox runs.

    A concurrent ticker advances during the (timeout-bounded) execution —
    impossible with the old blocking ``subprocess.run`` (which froze the loop
    for the whole timeout and let the ticker advance 0 times). This is the
    decisive regression guard for the Bloc 5 fix.
    """
    ticks = 0

    async def ticker() -> None:
        nonlocal ticks
        while True:
            await asyncio.sleep(0.02)
            ticks += 1

    task = asyncio.create_task(ticker())
    try:
        result = await execute_script("while True: pass", timeout=1)
        assert result["success"] is False
    finally:
        task.cancel()
        with contextlib.suppress(asyncio.CancelledError):
            await task
    # ~1s at 0.02s cadence → ~50 ticks; >10 robustly proves the loop kept
    # running while the subprocess was alive (old blocking call → 0 ticks).
    assert ticks > 10, f"event loop was blocked: only {ticks} ticks advanced"