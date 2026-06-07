"""Tool definitions for function calling — Corely Agent Pro.

Expanded from 3 to 14 tools:
- Free tier (8): search_web, get_datetime, get_weather, scrape_url, calculate,
                   translate_text, get_news, execute_python
- Pro tier (4):  search_flights, search_hotels, generate_image, agent_remember/recall
- Voice (2):    get_datetime, get_weather (always available)
"""

import json
import math as _math
from datetime import datetime, timezone
from typing import Any

# ── Tool definitions ─────────────────────────────────────────────────────────

def get_tool_definitions(is_pro: bool = False) -> list[dict[str, Any]]:
    """Return OpenAI-compatible tool definitions. Pro users get more tools."""
    tools = _FREE_TOOLS.copy()
    if is_pro:
        tools.extend(_PRO_TOOLS)
    # DeepSeek strict mode: guarantee valid JSON for tool calls
    for tool in tools:
        tool["function"]["strict"] = True
        params = tool["function"].get("parameters", {})
        if "properties" in params:
            params["additionalProperties"] = False
    return tools


_FREE_TOOLS: list[dict[str, Any]] = [
    {
        "type": "function",
        "function": {
            "name": "search_web",
            "description": (
                "Search the web for current information. "
                "Use when the user asks about recent events, facts, or data "
                "that may be outside your training cutoff."
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
                        "description": "Number of results (1-10)",
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
                "Get the current date and time. "
                "Use when the user asks about the current date, time, or day."
            ),
            "parameters": {
                "type": "object",
                "properties": {
                    "timezone": {
                        "type": "string",
                        "description": "IANA timezone, e.g. 'Europe/Paris'",
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
                "Get current weather for a location. "
                "Use when the user asks about weather, temperature, or climate."
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
    {
        "type": "function",
        "function": {
            "name": "scrape_url",
            "description": (
                "Scrape and extract content from a webpage. "
                "Use when you need to read or analyze the text content of a specific URL."
            ),
            "parameters": {
                "type": "object",
                "properties": {
                    "url": {
                        "type": "string",
                        "description": "The URL to scrape",
                    },
                    "selector": {
                        "type": "string",
                        "description": "Optional CSS selector to extract specific elements",
                    },
                },
                "required": ["url"],
            },
        },
    },
    {
        "type": "function",
        "function": {
            "name": "calculate",
            "description": (
                "Evaluate a mathematical expression safely. "
                "Use for arithmetic, percentages, unit conversions. "
                "Supports: + - * / ** sqrt() abs() round() sin() cos() log() pi e."
            ),
            "parameters": {
                "type": "object",
                "properties": {
                    "expression": {
                        "type": "string",
                        "description": "Mathematical expression to evaluate, e.g. 'sqrt(144) * 2.5'",
                    },
                },
                "required": ["expression"],
            },
        },
    },
    {
        "type": "function",
        "function": {
            "name": "translate_text",
            "description": (
                "Translate text between languages using DeepSeek. "
                "Use when the user needs translation."
            ),
            "parameters": {
                "type": "object",
                "properties": {
                    "text": {
                        "type": "string",
                        "description": "Text to translate",
                    },
                    "target_language": {
                        "type": "string",
                        "description": "Target language, e.g. 'French', 'English', 'Spanish'",
                    },
                    "source_language": {
                        "type": "string",
                        "description": "Source language (auto-detect if omitted)",
                    },
                },
                "required": ["text", "target_language"],
            },
        },
    },
    {
        "type": "function",
        "function": {
            "name": "get_news",
            "description": (
                "Get recent news headlines about a topic. "
                "Use when the user asks about current news or events."
            ),
            "parameters": {
                "type": "object",
                "properties": {
                    "query": {
                        "type": "string",
                        "description": "News search query, e.g. 'AI technology'",
                    },
                    "max_results": {
                        "type": "integer",
                        "description": "Max headlines (1-10)",
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
            "name": "execute_python",
            "description": (
                "Execute Python code in a sandbox. "
                "Use for custom calculations, data processing, or automation. "
                "Max 30s timeout. Allowed imports: json, re, math, datetime, collections, itertools. "
                "The code must print() a JSON result."
            ),
            "parameters": {
                "type": "object",
                "properties": {
                    "code": {
                        "type": "string",
                        "description": "Python code to execute. Must print JSON result.",
                    },
                },
                "required": ["code"],
            },
        },
    },
]

_PRO_TOOLS: list[dict[str, Any]] = [
    {
        "type": "function",
        "function": {
            "name": "search_flights",
            "description": (
                "Search for flight options between two cities on given dates. "
                "Returns links to flight comparison sites with pre-filled parameters. "
                "Pro feature."
            ),
            "parameters": {
                "type": "object",
                "properties": {
                    "from_city": {
                        "type": "string",
                        "description": "Departure city name",
                    },
                    "to_city": {
                        "type": "string",
                        "description": "Arrival city name",
                    },
                    "departure_date": {
                        "type": "string",
                        "description": "Departure date (YYYY-MM-DD)",
                    },
                    "return_date": {
                        "type": "string",
                        "description": "Optional return date (YYYY-MM-DD)",
                    },
                },
                "required": ["from_city", "to_city", "departure_date"],
            },
        },
    },
    {
        "type": "function",
        "function": {
            "name": "search_hotels",
            "description": (
                "Search for hotels in a city for given dates. "
                "Returns links to hotel booking sites. Pro feature."
            ),
            "parameters": {
                "type": "object",
                "properties": {
                    "city": {
                        "type": "string",
                        "description": "City name",
                    },
                    "check_in": {
                        "type": "string",
                        "description": "Check-in date (YYYY-MM-DD)",
                    },
                    "check_out": {
                        "type": "string",
                        "description": "Check-out date (YYYY-MM-DD)",
                    },
                    "guests": {
                        "type": "integer",
                        "description": "Number of guests",
                        "default": 2,
                    },
                },
                "required": ["city", "check_in", "check_out"],
            },
        },
    },
    {
        "type": "function",
        "function": {
            "name": "generate_image",
            "description": (
                "Generate an AI image from a text description using Pollinations.ai. "
                "Use when the user asks to create, draw, or visualize something. "
                "Pro feature."
            ),
            "parameters": {
                "type": "object",
                "properties": {
                    "prompt": {
                        "type": "string",
                        "description": "Detailed image description in English",
                    },
                    "width": {
                        "type": "integer",
                        "description": "Image width (default 1024)",
                        "default": 1024,
                    },
                    "height": {
                        "type": "integer",
                        "description": "Image height (default 1024)",
                        "default": 1024,
                    },
                },
                "required": ["prompt"],
            },
        },
    },
    {
        "type": "function",
        "function": {
            "name": "agent_remember",
            "description": (
                "Store information in the agent's persistent memory for future conversations. "
                "Use when the user explicitly asks to remember something, or shares "
                "personal preferences/facts they want recalled later. "
                "Pro feature."
            ),
            "parameters": {
                "type": "object",
                "properties": {
                    "key": {
                        "type": "string",
                        "description": "Memory key/topic, e.g. 'user_name', 'preferred_language'",
                    },
                    "value": {
                        "type": "string",
                        "description": "The information to remember",
                    },
                },
                "required": ["key", "value"],
            },
        },
    },
    {
        "type": "function",
        "function": {
            "name": "agent_recall",
            "description": (
                "Recall information from the agent's persistent memory. "
                "Use when the user asks about something they previously shared "
                "or when relevant past context would help answer. "
                "Pro feature."
            ),
            "parameters": {
                "type": "object",
                "properties": {
                    "query": {
                        "type": "string",
                        "description": "What to search for in memory, e.g. 'name', 'preferences', 'last topic'",
                    },
                },
                "required": ["query"],
            },
        },
    },
]

# ── Tool execution ───────────────────────────────────────────────────────────

# In-memory memory store (reset on server restart; migrate to Redis/DB for prod)
_agent_memory: dict[str, str] = {}


async def execute_tool(name: str, arguments: dict[str, Any]) -> str:
    """Execute a tool by name and return a JSON-serializable result string."""

    # ── Free tools ────────────────────────────────────────────────────────

    if name == "get_datetime":
        tz = arguments.get("timezone")
        if tz:
            from zoneinfo import ZoneInfo
            now = datetime.now(ZoneInfo(tz))
        else:
            now = datetime.now(timezone.utc)
        return now.isoformat()

    if name == "get_weather":
        location = arguments.get("location", "unknown")
        units = arguments.get("units", "metric")
        try:
            from backend.agents.search_engine import get_weather as _get_weather
            result = await _get_weather(location, units)
            return json.dumps(result)
        except Exception:
            return json.dumps({
                "location": location, "temperature": None, "units": units,
                "note": "Weather API not configured. Consider setting OPENWEATHERMAP_API_KEY."
            })

    if name == "search_web":
        query = arguments.get("query", "")
        num_results = min(arguments.get("num_results", 5), 10)
        from backend.agents.search_engine import search_duckduckgo
        results = await search_duckduckgo(query, num_results=num_results)
        return json.dumps([r.model_dump() for r in results.results], default=str)

    if name == "scrape_url":
        url = arguments["url"]
        selector = arguments.get("selector")
        from backend.agents.search_engine import scrape_url
        selectors = {"content": selector} if selector else None
        result = await scrape_url(url, selectors=selectors)
        return json.dumps(result, default=str)

    if name == "calculate":
        expr = arguments["expression"]
        allowed = {
            "abs": abs, "round": round, "min": min, "max": max,
            "sqrt": _math.sqrt, "sin": _math.sin, "cos": _math.cos,
            "log": _math.log, "log10": _math.log10, "pow": pow,
            "pi": _math.pi, "e": _math.e, "ceil": _math.ceil,
            "floor": _math.floor, "sum": sum, "len": len,
        }
        try:
            result = eval(expr, {"__builtins__": {}}, allowed)
            return json.dumps({"expression": expr, "result": result})
        except Exception as e:
            return json.dumps({"expression": expr, "error": str(e)})

    if name == "translate_text":
        text = arguments["text"]
        target = arguments["target_language"]
        source = arguments.get("source_language", "auto")
        from backend.core.config import settings
        import httpx
        if not settings.deepseek_api_key:
            return json.dumps({"error": "Translation unavailable: no API key"})
        payload = {
            "model": "deepseek-v4-flash",
            "messages": [{
                "role": "system",
                "content": (
                    f"Translate the following text from {source} to {target}. "
                    "Return ONLY the translated text, nothing else."
                ),
            }, {
                "role": "user", "content": text,
            }],
            "temperature": 0.3, "max_tokens": 2048,
        }
        async with httpx.AsyncClient(timeout=20) as client:
            resp = await client.post(
                "https://api.deepseek.com/v1/chat/completions",
                headers={"Authorization": f"Bearer {settings.deepseek_api_key}"},
                json=payload,
            )
            resp.raise_for_status()
            data = resp.json()
            translated = data["choices"][0]["message"]["content"].strip()
        return json.dumps({"source": source, "target": target, "translation": translated})

    if name == "get_news":
        query = arguments["query"]
        max_results = min(arguments.get("max_results", 5), 10)
        from backend.agents.search_engine import search_duckduckgo
        results = await search_duckduckgo(f"{query} news", num_results=max_results)
        headlines = [{"title": r.title, "url": r.url, "snippet": r.snippet}
                      for r in results.results[:max_results]]
        return json.dumps({"query": query, "headlines": headlines}, default=str)

    if name == "execute_python":
        code = arguments["code"]
        from backend.agents.script_executor import execute_script
        result = await execute_script(code, timeout=30)
        return json.dumps(result, default=str)

    # ── Pro tools ──────────────────────────────────────────────────────────

    if name == "search_flights":
        from_city = arguments["from_city"]
        to_city = arguments["to_city"]
        dep_date = arguments["departure_date"]
        ret_date = arguments.get("return_date", "")
        ret_param = f"&returnDate={ret_date}" if ret_date else ""
        links = [
            {"name": "Google Flights", "url": (
                f"https://www.google.com/travel/flights?q=Flights+to+{to_city}"
                f"+from+{from_city}+on+{dep_date}{ret_param}"
            )},
            {"name": "Skyscanner", "url": (
                f"https://www.skyscanner.fr/transport/flights/"
                f"{from_city.lower()}/{to_city.lower()}/"
                f"{dep_date.replace('-','')}/{ret_date.replace('-','') if ret_date else ''}"
            )},
            {"name": "Kayak", "url": (
                f"https://www.kayak.fr/flights/{from_city}-{to_city}/{dep_date}"
                f"{'/' + ret_date if ret_date else ''}"
            )},
        ]
        return json.dumps({"from": from_city, "to": to_city, "links": links})

    if name == "search_hotels":
        city = arguments["city"]
        check_in = arguments["check_in"]
        check_out = arguments["check_out"]
        guests = arguments.get("guests", 2)
        links = [
            {"name": "Booking.com", "url": (
                f"https://www.booking.com/searchresults.html?"
                f"ss={city}&checkin={check_in}&checkout={check_out}&group_adults={guests}"
            )},
            {"name": "Hotels.com", "url": (
                f"https://fr.hotels.com/Hotel-Search?"
                f"destination={city}&checkin={check_in}&checkout={check_out}&adults={guests}"
            )},
        ]
        return json.dumps({"city": city, "check_in": check_in, "check_out": check_out, "links": links})

    if name == "generate_image":
        prompt = arguments["prompt"]
        width = arguments.get("width", 1024)
        height = arguments.get("height", 1024)
        import httpx
        url = (
            f"https://image.pollinations.ai/prompt/"
            f"{prompt.replace(' ', '%20')}?width={width}&height={height}&nologo=true"
        )
        return json.dumps({"prompt": prompt, "image_url": url, "width": width, "height": height})

    if name == "agent_remember":
        key = arguments["key"]
        value = arguments["value"]
        _agent_memory[key] = value
        return json.dumps({"status": "stored", "key": key})

    if name == "agent_recall":
        query = arguments["query"].lower()
        matches = {}
        for k, v in _agent_memory.items():
            if query in k.lower() or query in v.lower():
                matches[k] = v
        if not matches:
            return json.dumps({"status": "no_matches", "query": query, "memory_keys": list(_agent_memory.keys())})
        return json.dumps({"status": "found", "matches": matches})

    raise ValueError(f"Unknown tool: {name}")
