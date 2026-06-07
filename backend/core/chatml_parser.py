"""Parseur ChatML : convertit une chaîne <|im_start|>role...<|im_end|> en liste de messages structurés."""

import re
from typing import Any

# Tokens ChatML standard
IM_START = "<|im_start|>"
IM_END = "<|im_end|>"

# Regex robuste : capture le rôle (mot simple) puis le contenu jusqu'au prochain <|im_end|>
_CHATML_PATTERN = re.compile(
    re.escape(IM_START) + r"(\w+)\s*\n"   # <|im_start|>role\n
    r"(.*?)"                               # contenu (non-greedy)
    + re.escape(IM_END),                   # <|im_end|>
    re.DOTALL,
)


def parse_chatml(raw: str) -> list[dict[str, Any]]:
    """Parse une chaîne ChatML en liste de messages pour l'API LLM.

    Args:
        raw: Chaîne au format ChatML (ex: '<|im_start|>system\\nBonjour<|im_end|>')

    Returns:
        Liste de dicts {'role': str, 'content': str} prêts pour l'API.
    """
    messages: list[dict[str, Any]] = []

    for match in _CHATML_PATTERN.finditer(raw):
        role = match.group(1).strip()
        content = match.group(2).strip()

        # Ignorer les blocs vides
        if not content:
            continue

        # Normaliser les rôles
        role_map = {
            "system": "system",
            "user": "user",
            "assistant": "assistant",
            "tool": "tool",
            "tool_response": "tool",
        }
        role = role_map.get(role, role)

        # Ignorer les blocs d'outils internes (ils sont pour le formatage, pas pour l'API)
        if role == "system" and "<tools>" in content:
            # Extraire uniquement les instructions, pas les définitions d'outils
            # On garde le bloc system mais on nettoie la section <tools>
            content = _clean_tools_section(content)

        messages.append({"role": role, "content": content})

    return messages


def _clean_tools_section(content: str) -> str:
    """Nettoie la section <tools>...</tools> d'un bloc system tout en gardant les instructions."""
    # Supprime le bloc <tools>...</tools> mais garde le texte avant et après
    cleaned = re.sub(r"<tools>.*?</tools>\s*", "", content, flags=re.DOTALL)
    # Supprime aussi les instructions de formatage tool_call
    cleaned = re.sub(
        r"Pour chaque appel d'outil.*?</tool_call>\s*",
        "",
        cleaned,
        flags=re.DOTALL,
    )
    return cleaned.strip()


def messages_to_chatml(messages: list[dict[str, Any]]) -> str:
    """Convertit une liste de messages en chaîne ChatML (pour debug/affichage)."""
    parts: list[str] = []
    for msg in messages:
        role = msg.get("role", "user")
        content = msg.get("content", "")
        parts.append(f"{IM_START}{role}\n{content}{IM_END}")
    return "\n".join(parts)
