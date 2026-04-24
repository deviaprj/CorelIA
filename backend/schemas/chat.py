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
