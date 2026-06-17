"""Tests pytest pour les templates ChatML multimodaux (vision_agent, deepseek_agent).

Remplace la couverture des anciens scripts manuels ``test_vision_template.py`` et
``test_commander_template.py`` (renommés ``scenario_*.py``). Ces scripts cassaient la
collection pytest : ils chargeaient les templates via un ``FileSystemLoader`` CWD-
relatif et exécutaient du code au top-level, donc pytest les collectait via le préfixe
``test_`` puis échouait à l'import quand il tournait depuis la racine du repo.

Ces tests utilisent le moteur de rendu production (``template_renderer.py``) qui
charge depuis le dossier absolu ``backend/templates/`` — indépendant du CWD.

Note sur les assertions : on vérifie des marqueurs texte (noms d'outil, arguments,
marqueurs visuels ``Picture N:`` / ``Video N:``) et des rôles parsés, en passant par
des booléens intermédiaires pour toute recherche de sous-chaîne dans le ChatML rendu.
Ainsi un échec n'affiche jamais le ChatML brut dans le traceback.
"""

from __future__ import annotations

import json

from backend.core.template_renderer import (
    list_templates,
    load_template,
    render_and_parse,
    render_template,
)

# Tokens ChatML pipe-délimités (stables : ne collisionnent pas avec les délimiteurs
# d'appel d'outil du format de fonction).
IM_START = "<|im_start|>"
IM_END = "<|im_end|>"
VISION_START = "<|vision_start|>"
IMAGE_PAD = "<|image_pad|>"
VISION_END = "<|vision_end|>"
VIDEO_PAD = "<|video_pad|>"


class _Msg:
    """Mini wrapper message pour ``template.render()`` (role / content / tool_calls).

    Reproduit l'interface attendue par les templates Jinja2 sans dépendre des
    internals de ``template_renderer``. ``content`` peut être une ``str`` (texte)
    ou une liste de parties multimodales (text/image_url/video).
    """

    def __init__(self, role: str, content: object, tool_calls: list | None = None) -> None:
        self.role = role
        self.content = content
        self.tool_calls = tool_calls or []


def _tool_call(name: str, arguments: object) -> dict:
    """Construit un tool_call au format ``{function: {name, arguments}}`` attendu par
    les templates (vision/deepseek reassignent ``tc = tc.function``)."""
    return {"function": {"name": name, "arguments": arguments}}


def _render_vision(
    messages: list[_Msg],
    *,
    add_generation_prompt: bool = False,
    add_vision_id: bool = False,
    tools: list | None = None,
) -> str:
    """Rend ``vision_agent`` en contrôlant ``add_vision_id`` (non transmis par
    ``render_template``) via ``load_template`` + le dossier absolu."""
    tmpl = load_template("vision_agent")
    return tmpl.render(
        messages=messages,
        tools=tools or [],
        add_generation_prompt=add_generation_prompt,
        add_vision_id=add_vision_id,
    )


# ── découverte ────────────────────────────────────────────────────────────────

def test_templates_listed() -> None:
    """Les trois templates ChatML sont listés."""
    names = list_templates()
    assert "vision_agent" in names, f"vision_agent manquant: {names}"
    assert "deepseek_agent" in names, f"deepseek_agent manquant: {names}"
    assert "commander_agent" in names, f"commander_agent manquant: {names}"


# ── vision_agent : message texte ─────────────────────────────────────────────

def test_vision_agent_text_message_renders_balises() -> None:
    """Un message texte rend une balise user + im_end, contenu préservé."""
    chatml = _render_vision([_Msg("user", "Décris cette image")])
    has_user = (IM_START + "user") in chatml
    has_text = "Décris cette image" in chatml
    has_end = IM_END in chatml
    assert has_user, "balise user absente"
    assert has_text, "contenu texte absent"
    assert has_end, "balise im_end absente"


def test_vision_agent_text_parse_to_api_message() -> None:
    """render_and_parse produit un message user valide (role/content str, sans ChatML résiduel)."""
    result = render_and_parse(
        name="vision_agent",
        messages=[{"role": "user", "content": "Bonjour"}],
    )
    assert isinstance(result, list) and len(result) >= 1
    msg = result[0]
    assert msg["role"] == "user"
    assert msg["content"] == "Bonjour"
    assert IM_START not in msg["content"]
    assert IM_END not in msg["content"]


# ── vision_agent : multimodal image ───────────────────────────────────────────

def test_vision_agent_image_with_vision_id() -> None:
    """Image + add_vision_id → marqueur 'Picture 1:' + tokens vision image."""
    chatml = _render_vision(
        [_Msg("user", [
            {"type": "text", "text": "Que vois-tu ?"},
            {"type": "image_url", "image_url": {"url": "data:image/jpeg;base64,/9j/4AAQ"}},
        ])],
        add_vision_id=True,
    )
    has_text = "Que vois-tu ?" in chatml
    has_picture = "Picture 1:" in chatml
    has_vstart = VISION_START in chatml
    has_ipad = IMAGE_PAD in chatml
    has_vend = VISION_END in chatml
    assert has_text, "texte multimodal absent"
    assert has_picture, "marqueur Picture 1: absent"
    assert has_vstart and has_ipad and has_vend, "tokens vision image absents"


def test_vision_agent_image_without_vision_id() -> None:
    """Image sans add_vision_id → pas de marqueur 'Picture N:' mais tokens vision présents."""
    chatml = _render_vision(
        [_Msg("user", [
            {"type": "image_url", "image_url": {"url": "data:image/png;base64,abc"}},
        ])],
        add_vision_id=False,
    )
    has_picture = "Picture" in chatml
    has_vstart = VISION_START in chatml
    has_ipad = IMAGE_PAD in chatml
    has_vend = VISION_END in chatml
    assert not has_picture, "marqueur Picture ne doit pas apparaître sans add_vision_id"
    assert has_vstart and has_ipad and has_vend, "tokens vision image absents"


# ── vision_agent : vidéo ──────────────────────────────────────────────────────

def test_vision_agent_video_token() -> None:
    """Contenu vidéo → tokens vidéo + texte préservé."""
    chatml = _render_vision(
        [_Msg("user", [
            {"type": "text", "text": "Analyse cette vidéo"},
            {"type": "video", "video_url": "https://exemple.com/video.mp4"},
        ])],
        add_vision_id=True,
    )
    has_text = "Analyse cette vidéo" in chatml
    has_vstart = VISION_START in chatml
    has_vpad = VIDEO_PAD in chatml
    has_vend = VISION_END in chatml
    assert has_text, "texte vidéo absent"
    assert has_vstart and has_vpad and has_vend, "tokens vision vidéo absents"


# ── vision_agent : appels d'outil ─────────────────────────────────────────────

def test_vision_agent_assistant_tool_calls_rendered() -> None:
    """Assistant avec tool_calls → nom d'outil + arguments rendus."""
    chatml = _render_vision([
        _Msg("user", "Quel temps fait-il ?"),
        _Msg("assistant", "Je consulte la météo...", tool_calls=[
            _tool_call("search_web", '{"query": "météo Paris"}'),
            _tool_call("get_weather", {"city": "Paris"}),
        ]),
    ])
    has_search = "search_web" in chatml
    has_weather = "get_weather" in chatml
    has_args_str = "météo Paris" in chatml
    has_args_dict = "Paris" in chatml
    assert has_search, "search_web absent du rendu tool_call"
    assert has_weather, "get_weather absent du rendu tool_call"
    assert has_args_str, "arguments (string) absents du rendu tool_call"
    assert has_args_dict, "arguments (dict) absents du rendu tool_call"


def test_vision_agent_tool_response_grouped_under_user() -> None:
    """Les messages tool sont wrappés sous une balise user, contenu préservé."""
    chatml = _render_vision([
        _Msg("user", "Météo ?"),
        _Msg("assistant", "", tool_calls=[_tool_call("search_web", "{}")]),
        _Msg("tool", "Il fait 22°C à Paris"),
    ])
    has_user_block = (IM_START + "user") in chatml
    has_content = "Il fait 22°C à Paris" in chatml
    assert has_user_block, "tool_response doit être wrappé sous un bloc user"
    assert has_content, "contenu tool absent du rendu"


def test_vision_agent_multiple_tool_responses_single_user_block() -> None:
    """Plusieurs messages tool consécutifs → un seul bloc user pour le groupe."""
    chatml = _render_vision([
        _Msg("user", "Recherche"),
        _Msg("assistant", "", tool_calls=[_tool_call("search_web", "{}")]),
        _Msg("tool", "Résultat 1"),
        _Msg("tool", "Résultat 2"),
        _Msg("tool", "Résultat 3"),
    ])
    user_count = chatml.count(IM_START + "user")
    assert user_count == 2, f"{user_count} blocs user au lieu de 2 (1 original + 1 groupe)"


# ── vision_agent : generation_prompt ──────────────────────────────────────────

def test_vision_agent_generation_prompt_appends_assistant() -> None:
    """add_generation_prompt=True → un bloc assistant est présent."""
    chatml = _render_vision([_Msg("user", "Test")], add_generation_prompt=True)
    has_assistant = (IM_START + "assistant") in chatml
    assert has_assistant, "add_generation_prompt doit ajouter un bloc assistant"


def test_vision_agent_no_generation_prompt_no_assistant() -> None:
    """add_generation_prompt=False + aucun message assistant → pas de bloc assistant."""
    chatml = _render_vision([_Msg("user", "Test")], add_generation_prompt=False)
    has_assistant = (IM_START + "assistant") in chatml
    assert not has_assistant, "aucun bloc assistant attendu sans generation_prompt"


# ── vision_agent : équilibre ChatML ──────────────────────────────────────────

def test_vision_agent_chatml_balanced_without_generation_prompt() -> None:
    """Sans generation_prompt, chaque balise im_start ouverte a un im_end."""
    scenarios = [
        [_Msg("user", "Décris cette image")],
        [_Msg("user", [
            {"type": "text", "text": "Que vois-tu ?"},
            {"type": "image_url", "image_url": {"url": "data:image/jpeg;base64,/9j/4AAQ"}},
        ])],
        [_Msg("user", "Analyse"), _Msg("assistant", "Voici l'analyse")],
    ]
    for messages in scenarios:
        chatml = _render_vision(messages, add_generation_prompt=False)
        starts = chatml.count(IM_START)
        ends = chatml.count(IM_END)
        assert starts == ends, f"Déséquilibre ChatML: {starts} starts != {ends} ends"


# ── deepseek_agent : persona + multimodal (production path) ───────────────────

def test_deepseek_agent_persona_system_prompt() -> None:
    """deepseek_agent rend un system prompt persona + un prefill assistant.

    Le template deepseek utilise le pré-remplissage assistant (assistant-prefill) plutôt
    qu'un tour user séparé : avec add_generation_prompt, le rendu est [system, assistant]
    où l'assistant acquiesce ("Oui Monsieur") et replie la demande utilisateur. Contrat
    différent de commander_agent, qui préserve le tour user.
    """
    result = render_and_parse(
        name="deepseek_agent",
        messages=[{"role": "user", "content": "Construis une app de chat"}],
        add_generation_prompt=True,
    )
    roles = [m["role"] for m in result]
    assert "system" in roles, f"Pas de system prompt: {roles}"
    assert "assistant" in roles, f"Pas de bloc assistant (prefill): {roles}"
    system_content = next(m["content"] for m in result if m["role"] == "system")
    assert "DeepSeek-V4" in system_content, "Persona DeepSeek-V4 absent"
    assert "PROTOCOLE DE CONFIRMATION" in system_content, "Protocole absent"
    assistant_content = next(m["content"] for m in result if m["role"] == "assistant")
    assert "Oui Monsieur" in assistant_content, "Acquittement 'Oui Monsieur' absent du prefill"
    assert "Construis" in assistant_content, "Demande utilisateur non repliée dans le prefill"


def test_deepseek_agent_multimodal_image_tokens() -> None:
    """deepseek_agent supporte le contenu multimodal image (tokens vision)."""
    chatml = render_template(
        name="deepseek_agent",
        messages=[{
            "role": "user",
            "content": [
                {"type": "text", "text": "Analyse cette capture"},
                {"type": "image_url", "image_url": {"url": "data:image/png;base64,abc"}},
            ],
        }],
        add_generation_prompt=False,
    )
    has_text = "Analyse cette capture" in chatml
    has_vstart = VISION_START in chatml
    has_ipad = IMAGE_PAD in chatml
    has_vend = VISION_END in chatml
    assert has_text, "texte multimodal absent"
    assert has_vstart and has_ipad and has_vend, "tokens vision image absents"


def test_deepseek_agent_auto_response_on_generation_prompt() -> None:
    """add_generation_prompt sur le dernier message user → auto-réponse 'Oui Monsieur'."""
    chatml = render_template(
        name="deepseek_agent",
        messages=[{"role": "user", "content": "Fais X"}],
        add_generation_prompt=True,
    )
    has_oui = "Oui Monsieur, c'est très clair." in chatml
    has_analyse = "ANALYSE PRÉLIMINAIRE" in chatml
    assert has_oui, "auto-réponse 'Oui Monsieur' absente"
    assert has_analyse, "section ANALYSE PRÉLIMINAIRE absente"


def test_deepseek_agent_no_auto_response_without_generation_prompt() -> None:
    """Sans generation_prompt sur un tour déjà fermé → pas de bloc auto-réponse."""
    chatml = render_template(
        name="deepseek_agent",
        messages=[
            {"role": "user", "content": "Question 1"},
            {"role": "assistant", "content": "Réponse 1"},
        ],
        add_generation_prompt=False,
    )
    has_analyse = "ANALYSE PRÉLIMINAIRE" in chatml
    assert not has_analyse, "aucune auto-réponse attendue sans generation_prompt"


def test_deepseek_agent_api_compatible_output() -> None:
    """render_and_parse produit des messages valides et JSON-sérialisables pour l'API."""
    result = render_and_parse(
        name="deepseek_agent",
        messages=[{"role": "user", "content": "Explique le projet"}],
        add_generation_prompt=True,
    )
    for i, m in enumerate(result):
        assert "role" in m, f"Message {i}: pas de role"
        assert "content" in m, f"Message {i}: pas de content"
        assert m["role"] in ("system", "user", "assistant", "tool"), (
            f"Message {i}: rôle invalide {m['role']!r}"
        )
        assert isinstance(m["content"], str), f"Message {i}: content n'est pas str"
    json.dumps(result)  # sérialisable → compatible API