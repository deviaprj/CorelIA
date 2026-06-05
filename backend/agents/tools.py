"""Tool definitions for function calling."""

from datetime import datetime
from typing import Any


def get_tool_definitions() -> list[dict[str, Any]]:
    """Return OpenAI-compatible tool definitions."""
    return [
        {
            "type": "function",
            "function": {
                "name": "search_web",
                "description": (
                    "Search the web for current information. "
                    "Use when the user asks about recent events, facts, or data "
                    "that may be outside the model's training cutoff."
                ),
                "parameters": {
                    "type": "object",
                    "properties": {
                        "query": {
                            "type": "string",
                            "description": "The search query string",
                        },
                        "num_results": {
                            "type": "integer",
                            "description": "Number of results to retrieve",
                            "default": 5,
                        },
                    },
                    "required": ["query"],
                },
            },
        },
        {
            "type": "function",
            "function": {
                "name": "get_datetime",
                "description": (
                    "Get the current date and time in ISO 8601 format. "
                    "Use when the user asks about the current date or time."
                ),
                "parameters": {
                    "type": "object",
                    "properties": {
                        "timezone": {
                            "type": "string",
                            "description": "Optional IANA timezone (e.g., 'Europe/Paris')",
                        },
                    },
                    "required": [],
                },
            },
        },
        {
            "type": "function",
            "function": {
                "name": "get_weather",
                "description": (
                    "Get the current weather for a given location. "
                    "Use when the user asks about weather conditions."
                ),
                "parameters": {
                    "type": "object",
                    "properties": {
                        "location": {
                            "type": "string",
                            "description": "City name or coordinates",
                        },
                        "units": {
                            "type": "string",
                            "enum": ["metric", "imperial"],
                            "default": "metric",
                        },
                    },
                    "required": ["location"],
                },
            },
        },
    ]


async def execute_tool(name: str, arguments: dict[str, Any]) -> str:
    """Execute a tool by name and return a JSON-serializable result string."""
    if name == "get_datetime":
        tz = arguments.get("timezone")
        if tz:
            from zoneinfo import ZoneInfo
            now = datetime.now(ZoneInfo(tz))
        else:
            now = datetime.utcnow()
        return now.isoformat()

    if name == "get_weather":
        location = arguments.get("location", "unknown")
        units = arguments.get("units", "metric")
        # Placeholder: in production, call a weather API here
        return f'{{"location": "{location}", "temperature": null, "units": "{units}", "note": "Weather API not configured"}}'

    if name == "search_web":
        query = arguments.get("query", "")
        num_results = arguments.get("num_results", 5)
        from backend.agents.search_engine import search_duckduckgo
        results = await search_duckduckgo(query, num_results=num_results)
        import json
        return json.dumps([r.model_dump() for r in results.results], default=str)

    raise ValueError(f"Unknown tool: {name}")
