"""Pydantic models for chat and search endpoints."""

from datetime import datetime
from enum import Enum
from typing import Any, Literal

from pydantic import BaseModel, Field


class Role(str, Enum):
    """Message role enumeration."""

    SYSTEM = "system"
    USER = "user"
    ASSISTANT = "assistant"
    TOOL = "tool"


class Message(BaseModel):
    """A single chat message."""

    role: Role
    content: str
    name: str | None = None
    tool_calls: list[dict[str, Any]] | None = None


class ChatRequest(BaseModel):
    """Request body for the chat endpoint."""

    messages: list[Message] = Field(..., min_length=1)
    model: str | None = Field(default=None, description="Preferred model identifier")
    stream: bool = Field(default=True, description="Enable SSE streaming")
    temperature: float = Field(default=0.7, ge=0.0, le=2.0)
    max_tokens: int | None = Field(default=None, ge=1, le=8192)
    tools: list[dict[str, Any]] | None = None
    template: str | None = Field(
        default=None,
        description="Template Jinja2 à appliquer (ex: 'commander_agent'). "
        "Si null, les messages sont envoyés bruts.",
    )
    reasoning_effort: str | None = Field(
        default=None,
        description="DeepSeek reasoning effort: 'off', 'high', or 'max'. "
        "Controls thinking token budget. Null = provider default.",
    )


class ChatResponse(BaseModel):
    """Non-streaming chat response."""

    id: str
    model: str
    message: Message
    created_at: datetime
    usage: dict[str, int] | None = None


class SearchResult(BaseModel):
    """A single web search result."""

    title: str
    url: str
    snippet: str
    source: Literal["duckduckgo", "serpapi"]


class SearchResponse(BaseModel):
    """Response from the search engine."""

    query: str
    results: list[SearchResult]
    total_results: int


class ToolCall(BaseModel):
    """Function call emitted by the model."""

    id: str
    name: str
    arguments: dict[str, Any]


class DownloadMediaRequest(BaseModel):
    """Request body for the /download_media endpoint."""

    url: str = Field(..., description="Target URL to extract media from")
    media_type: str = Field(default="auto", description="auto, video, or gallery")


class DownloadMediaResponse(BaseModel):
    """Response from the media download endpoint."""

    success: bool
    type: str = Field(default="", description="video | page_media | playlist")
    title: str | None = None
    thumbnail: str | None = None
    duration: int | None = None
    uploader: str | None = None
    webpage_url: str | None = None
    direct_url: str | None = None
    formats: list[dict[str, Any]] | None = None
    videos: list[dict[str, Any]] | None = None
    images: list[dict[str, Any]] | None = None
    entries: list[dict[str, Any]] | None = None
    error: str | None = None


class CrawlRequest(BaseModel):
    """Request body for the /crawl endpoint."""

    url: str = Field(..., description="Starting URL to crawl")
    max_depth: int = Field(default=2, ge=1, le=5, description="How many link hops deep")
    max_pages: int = Field(default=20, ge=1, le=50, description="Max pages to fetch")
    same_domain: bool = Field(default=True, description="Stay within the same domain")


class CrawlResponse(BaseModel):
    """Response from the crawl endpoint."""

    success: bool
    pages_crawled: int = 0
    total_links_found: int = 0
    videos: list[dict[str, Any]] = Field(default_factory=list)
    images: list[str] = Field(default_factory=list)
    errors: list[str] = Field(default_factory=list)
    pages: list[dict[str, Any]] = Field(default_factory=list)


class ScriptExecutionRequest(BaseModel):
    """Request body for the /script/scrape endpoint."""

    url: str = Field(..., description="Target URL to scrape")
    instruction: str = Field(
        ..., description="Natural language instruction for what to extract"
    )


class ScriptExecRequest(BaseModel):
    """Request body for the /script/exec endpoint."""

    instruction: str = Field(..., description="Natural language task description")


class ApiFetchRequest(BaseModel):
    """Request body for the /script/api-fetch endpoint."""

    url: str = Field(..., description="API endpoint URL")
    instruction: str = Field(
        ..., description="How to transform or filter the API response"
    )


class ScriptExecutionResponse(BaseModel):
    """Response from the script execution endpoints."""

    success: bool
    data: Any | None = None
    error: str | None = None
    script: str | None = None
    stdout: str | None = None
    raw_output: str | None = None
