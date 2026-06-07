"""Moteur de rendu des templates Jinja2 pour le formatage des conversations.

Charge un template depuis backend/templates/, le rend avec les messages/tools,
et retourne une liste de messages structurés pour l'API LLM.
"""

from __future__ import annotations

from pathlib import Path
from typing import Any

from backend.core.logging import get_logger

# Jinja2 est optionnel — chargement paresseux pour éviter crash au démarrage
# si la dépendance n'est pas installée et que les templates ne sont pas utilisés.
_JINJA2_AVAILABLE = False
try:
    from jinja2 import Environment, FileSystemLoader, Template, TemplateNotFound  # noqa: F401
    _JINJA2_AVAILABLE = True
except ImportError:
    pass

logger = get_logger(__name__)

# Cache des templates compilés (évite de re-parser Jinja2 à chaque requête)
_template_cache: dict[str, Template] = {}

# Dossier racine des templates
_TEMPLATES_DIR = Path(__file__).resolve().parent.parent / "templates"


def _require_jinja2() -> None:
    """Vérifie que Jinja2 est disponible, lève une erreur claire sinon."""
    if not _JINJA2_AVAILABLE:
        raise ImportError(
            "Jinja2 n'est pas installé. Lancez : pip install jinja2>=3.1.0"
        )


def _get_env() -> Environment:
    """Retourne l'environnement Jinja2 configuré."""
    _require_jinja2()
    if not _TEMPLATES_DIR.is_dir():
        logger.warning("Templates directory not found", extra={"dir": str(_TEMPLATES_DIR)})
    return Environment(
        loader=FileSystemLoader(str(_TEMPLATES_DIR)),
        autoescape=False,  # On génère du ChatML, pas du HTML
        trim_blocks=True,
        lstrip_blocks=True,
    )


def list_templates() -> list[str]:
    """Liste les templates disponibles."""
    if not _TEMPLATES_DIR.is_dir():
        return []
    return sorted(
        p.stem for p in _TEMPLATES_DIR.glob("*.jinja2")
    )


def load_template(name: str) -> Template:
    """Charge un template Jinja2 par son nom (sans l'extension .jinja2).

    Utilise un cache pour éviter de recompiler à chaque appel.
    """
    cache_key = name
    if cache_key in _template_cache:
        return _template_cache[cache_key]

    env = _get_env()
    try:
        tmpl = env.get_template(f"{name}.jinja2")
    except TemplateNotFound:
        available = list_templates()
        raise FileNotFoundError(
            f"Template '{name}.jinja2' introuvable dans {_TEMPLATES_DIR}. "
            f"Disponibles: {', '.join(available) or 'aucun'}"
        ) from None

    _template_cache[cache_key] = tmpl
    logger.info("Template loaded", extra={"template": name})
    return tmpl


def render_template(
    name: str,
    messages: list[dict[str, Any]],
    tools: list[dict[str, Any]] | None = None,
    add_generation_prompt: bool = False,
    skills_context: str = "",
) -> str:
    """Rend un template Jinja2 en chaîne ChatML.

    Args:
        name: Nom du template (ex: 'commander_agent')
        messages: Liste de messages {'role': 'user', 'content': '...'}
        tools: Liste optionnelle de définitions d'outils
        add_generation_prompt: Si True, ajoute le priming assistant
        skills_context: Résumé des skills disponibles (injecté dans le template)

    Returns:
        Chaîne ChatML complète prête à être parsée.
    """
    tmpl = load_template(name)

    # Convertir les messages en objets pour le template
    class Msg:
        def __init__(self, d):
            self.role = d.get("role", "user")
            self.content = d.get("content", "")
            self.tool_calls = d.get("tool_calls")

    template_messages = [Msg(m) for m in messages]

    rendered = tmpl.render(
        messages=template_messages,
        tools=tools or [],
        add_generation_prompt=add_generation_prompt,
        skills_context=skills_context,
    )

    return rendered


def render_and_parse(
    name: str,
    messages: list[dict[str, Any]],
    tools: list[dict[str, Any]] | None = None,
    add_generation_prompt: bool = False,
    skills_context: str = "",
) -> list[dict[str, Any]]:
    """Rend un template ET le convertit en messages API.

    C'est la fonction principale à appeler depuis le router.
    """
    from backend.core.chatml_parser import parse_chatml

    chatml = render_template(
        name=name,
        messages=messages,
        tools=tools,
        add_generation_prompt=add_generation_prompt,
        skills_context=skills_context,
    )

    parsed = parse_chatml(chatml)

    if not parsed:
        logger.warning(
            "Template rendered but produced no parseable messages",
            extra={"template": name, "chatml_len": len(chatml)},
        )
        # Fallback : retourner les messages bruts
        return messages

    logger.info(
        "Template rendered and parsed",
        extra={
            "template": name,
            "input_msgs": len(messages),
            "output_msgs": len(parsed),
        },
    )
    return parsed
