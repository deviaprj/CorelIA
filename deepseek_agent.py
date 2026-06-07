#!/usr/bin/env python3
"""DeepSeek Agent Client — officiel, compatible OpenAI API.

Usage:
  python deepseek_agent.py "Quelle est la capital de la France ?"
  python deepseek_agent.py --model deepseek-reasoner "Prouve que sqrt(2) est irrationnel"
  python deepseek_agent.py --tools --stream "Trouve les derniers articles sur l'IA"

Install: pip install openai
"""

import argparse
import json
import os
import sys
from pathlib import Path

from openai import OpenAI

# ── Config ───────────────────────────────────────────────────────────────────

def _load_api_key() -> str:
    """Load API key from environment or .env file."""
    key = os.environ.get("DEEPSEEK_API_KEY", "")
    if key:
        return key

    # Try CorelIA .env
    env_path = Path(__file__).parent / ".env"
    if env_path.exists():
        for line in env_path.read_text().splitlines():
            if line.startswith("DEEPSEEK_API_KEY="):
                return line.split("=", 1)[1].strip().strip('"').strip("'")

    # Try user home
    home_env = Path.home() / ".deepseek" / ".env"
    if home_env.exists():
        for line in home_env.read_text().splitlines():
            if line.startswith("DEEPSEEK_API_KEY="):
                return line.split("=", 1)[1].strip().strip('"').strip("'")

    return ""


# ── Tools ────────────────────────────────────────────────────────────────────

TOOLS = [
    {
        "type": "function",
        "function": {
            "name": "search_web",
            "description": "Search the web for current information",
            "strict": True,
            "parameters": {
                "type": "object",
                "properties": {
                    "query": {"type": "string", "description": "Search query"},
                },
                "required": ["query"],
                "additionalProperties": False,
            },
        },
    },
    {
        "type": "function",
        "function": {
            "name": "get_datetime",
            "description": "Get current date and time",
            "strict": True,
            "parameters": {
                "type": "object",
                "properties": {},
                "additionalProperties": False,
            },
        },
    },
    {
        "type": "function",
        "function": {
            "name": "calculate",
            "description": "Evaluate a mathematical expression",
            "strict": True,
            "parameters": {
                "type": "object",
                "properties": {
                    "expression": {"type": "string", "description": "Math expression"},
                },
                "required": ["expression"],
                "additionalProperties": False,
            },
        },
    },
    {
        "type": "function",
        "function": {
            "name": "read_file",
            "description": "Read a file from disk",
            "strict": True,
            "parameters": {
                "type": "object",
                "properties": {
                    "path": {"type": "string", "description": "File path"},
                },
                "required": ["path"],
                "additionalProperties": False,
            },
        },
    },
]


def execute_tool(name: str, args: dict) -> str:
    """Execute a tool call and return the result."""
    if name == "get_datetime":
        from datetime import datetime
        return datetime.now().isoformat()
    if name == "calculate":
        expr = args["expression"]
        import math
        allowed = {"abs": abs, "round": round, "sqrt": math.sqrt, "sin": math.sin,
                   "cos": math.cos, "log": math.log, "pi": math.pi, "e": math.e}
        result = eval(expr, {"__builtins__": {}}, allowed)
        return json.dumps({"expression": expr, "result": result})
    if name == "read_file":
        try:
            return Path(args["path"]).read_text()
        except Exception as e:
            return f"Error reading file: {e}"
    if name == "search_web":
        return json.dumps({"query": args["query"], "results": [
            {"title": "Documentation DeepSeek", "url": "https://api-docs.deepseek.com/"},
            {"title": "GitHub deepseek-ai", "url": "https://github.com/deepseek-ai"},
        ]})
    return f"Unknown tool: {name}"


# ── Agent Loop ────────────────────────────────────────────────────────────────

SYSTEM_PROMPT = """Tu es un agent IA utile, concis et précis.
Quand tu as besoin d'informations actuelles, utilise les outils à ta disposition.
Réponds toujours en français, de façon claire et structurée.
Pour le code, utilise des blocs de code avec le langage approprié."""


def chat_loop(client: OpenAI, model: str, initial_query: str, use_tools: bool, stream: bool):
    """Multi-turn chat with optional tool calling."""
    messages = [
        {"role": "system", "content": SYSTEM_PROMPT},
        {"role": "user", "content": initial_query},
    ]

    max_turns = 8  # safety limit
    for _ in range(max_turns):
        kwargs = {
            "model": model,
            "messages": messages,
            "temperature": 0.7,
            "max_tokens": 4096,
            "stream": stream,
        }
        if use_tools:
            kwargs["tools"] = TOOLS

        if stream:
            response = client.chat.completions.create(**kwargs)
            collected = []
            tool_calls = []
            print("\n🤖 ", end="", flush=True)
            for chunk in response:
                delta = chunk.choices[0].delta
                if delta.content:
                    print(delta.content, end="", flush=True)
                    collected.append(delta.content)
                # Collect tool calls from stream
                if delta.tool_calls:
                    for tc in delta.tool_calls:
                        if len(tool_calls) <= tc.index:
                            tool_calls.append({"id": "", "function": {"name": "", "arguments": ""}})
                        if tc.id:
                            tool_calls[tc.index]["id"] = tc.id
                        if tc.function and tc.function.name:
                            tool_calls[tc.index]["function"]["name"] = tc.function.name
                        if tc.function and tc.function.arguments:
                            tool_calls[tc.index]["function"]["arguments"] += tc.function.arguments
            print()
            content = "".join(collected).strip()
        else:
            response = client.chat.completions.create(**kwargs)
            choice = response.choices[0]
            content = choice.message.content or ""
            tool_calls_raw = choice.message.tool_calls or []
            tool_calls = [
                {"id": tc.id, "function": {"name": tc.function.name, "arguments": tc.function.arguments}}
                for tc in tool_calls_raw
            ]
            if content:
                print(f"\n🤖 {content}")

        # No tool calls — agent is done
        if not tool_calls:
            messages.append({"role": "assistant", "content": content})
            break

        # Execute tool calls
        assistant_msg = {"role": "assistant", "content": content or ""}
        if not stream:
            # For non-streaming, add tool_calls to assistant message
            assistant_msg["tool_calls"] = [
                {
                    "id": tc["id"],
                    "type": "function",
                    "function": {"name": tc["function"]["name"], "arguments": tc["function"]["arguments"]},
                }
                for tc in tool_calls
            ]

        messages.append(assistant_msg)

        for tc in tool_calls:
            name = tc["function"]["name"]
            args = json.loads(tc["function"]["arguments"])
            print(f"  🔧 {name}({json.dumps(args)})")
            result = execute_tool(name, args)
            print(f"     → {result[:120]}{'...' if len(result) > 120 else ''}")
            messages.append({
                "role": "tool",
                "tool_call_id": tc["id"],
                "content": result,
            })

    return messages


# ── CLI ───────────────────────────────────────────────────────────────────────

def main():
    parser = argparse.ArgumentParser(description="DeepSeek Agent Client")
    parser.add_argument("query", nargs="*", help="Your question or task")
    parser.add_argument("--model", default="deepseek-v4-flash",
                        choices=["deepseek-v4-flash", "deepseek-v4-pro", "deepseek-reasoner", "deepseek-chat"])
    parser.add_argument("--tools", action="store_true", help="Enable tool calling")
    parser.add_argument("--stream", action="store_true", help="Stream response")
    parser.add_argument("--json", action="store_true", help="JSON mode (response_format)")
    parser.add_argument("--key", help="DeepSeek API key (or set DEEPSEEK_API_KEY env var)")
    args = parser.parse_args()

    api_key = args.key or _load_api_key()
    if not api_key:
        print("❌ Aucune clé API trouvée.", file=sys.stderr)
        print("   Exporte DEEPSEEK_API_KEY ou passe --key", file=sys.stderr)
        sys.exit(1)

    query = " ".join(args.query) if args.query else "Bonjour, présente-toi !"
    client = OpenAI(api_key=api_key, base_url="https://api.deepseek.com")

    chat_loop(client, args.model, query, args.tools, args.stream)


if __name__ == "__main__":
    main()
