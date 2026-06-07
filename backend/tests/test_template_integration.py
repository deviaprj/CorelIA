#!/usr/bin/env python3
"""Test d'intégration: render_and_parse → messages API valides.

Valide le pipeline complet :
1. Template Jinja2 (commander_agent.jinja2)
2. Rendu ChatML
3. Parsing en messages structurés
4. Vérification que les messages sont acceptables par une API LLM
"""

import json
import sys
sys.path.insert(0, ".")

from backend.core.template_renderer import render_and_parse, list_templates, render_template
from backend.core.chatml_parser import parse_chatml, messages_to_chatml


def test_template_list():
    """Vérifie que le template est listé."""
    templates = list_templates()
    assert "commander_agent" in templates, f"Template non listé: {templates}"
    print(f"✅ Templates disponibles: {templates}")


def test_render_and_parse_simple():
    """Scénario simple: 1 message user → messages API."""
    messages = [{"role": "user", "content": "Crée une application de chat"}]
    result = render_and_parse(
        name="commander_agent",
        messages=messages,
        tools=[{"name": "read_file", "description": "Lire un fichier"}],
        add_generation_prompt=True,
    )

    # Vérifications structurelles
    assert isinstance(result, list), f"Type inattendu: {type(result)}"
    assert len(result) >= 2, f"Pas assez de messages: {len(result)}"

    # Vérifier qu'il y a un system prompt
    roles = [m["role"] for m in result]
    assert "system" in roles, f"Pas de system prompt. Rôles: {roles}"
    assert "user" in roles, f"Pas de message user. Rôles: {roles}"

    # Vérifier le contenu
    system_msgs = [m for m in result if m["role"] == "system"]
    user_msgs = [m for m in result if m["role"] == "user"]
    assistant_msgs = [m for m in result if m["role"] == "assistant"]

    assert len(system_msgs) >= 1, f"Expected >=1 system msg, got {len(system_msgs)}"
    assert len(user_msgs) >= 1, f"Expected >=1 user msg, got {len(user_msgs)}"
    assert len(assistant_msgs) >= 1, f"Expected >=1 assistant msg (auto-response), got {len(assistant_msgs)}"

    # Vérifier que le system prompt contient le persona
    system_content = system_msgs[0]["content"]
    assert "agent d'intelligence artificielle" in system_content, "System prompt incomplet"
    assert "PROTOCOLE DE CONFIRMATION" in system_content, "Protocole absent"

    # Vérifier que l'auto-réponse contient l'analyse
    auto_response = assistant_msgs[0]["content"]
    assert "Oui Monsieur" in auto_response, "Auto-réponse absente"
    assert "ANALYSE PRÉLIMINAIRE" in auto_response, "Analyse absente"
    assert "DEMANDE DE VALIDATION FINALE" in auto_response, "Validation absente"

    # Vérifier que le message utilisateur est préservé
    user_content = user_msgs[0]["content"]
    assert "Crée une application de chat" in user_content, "Message utilisateur perdu"

    print(f"✅ Render+parse simple: {len(result)} messages générés")
    print(f"   Rôles: {roles}")


def test_render_and_parse_no_tools():
    """Sans outils: le template doit fonctionner quand même."""
    messages = [{"role": "user", "content": "Bonjour"}]
    result = render_and_parse(
        name="commander_agent",
        messages=messages,
        tools=None,
        add_generation_prompt=True,
    )

    assert len(result) >= 2, f"Pas assez de messages sans outils: {len(result)}"
    # Vérifier qu'il n'y a PAS de bloc <tools> dans le contenu
    for m in result:
        assert "<tools>" not in m["content"], f"Bloc <tools> présent dans {m['role']}: {m['content'][:200]}"

    print(f"✅ Render+parse sans outils: {len(result)} messages")


def test_render_and_parse_no_generation_prompt():
    """Sans generation_prompt: pas d'auto-réponse."""
    messages = [
        {"role": "user", "content": "Question 1"},
        {"role": "assistant", "content": "Réponse 1"},
    ]
    result = render_and_parse(
        name="commander_agent",
        messages=messages,
        tools=None,
        add_generation_prompt=False,
    )

    # Vérifier qu'aucun message assistant ne contient "ANALYSE PRÉLIMINAIRE"
    for m in result:
        if m["role"] == "assistant":
            assert "ANALYSE PRÉLIMINAIRE" not in m["content"], (
                f"Auto-réponse présente alors que generation_prompt=False: {m['content'][:200]}"
            )

    print(f"✅ Render+parse sans generation_prompt: {len(result)} messages")


def test_chatml_roundtrip():
    """Vérifie que le ChatML produit est parsable."""
    messages = [{"role": "user", "content": "Test"}]
    chatml = render_template(
        name="commander_agent",
        messages=messages,
        tools=None,
        add_generation_prompt=True,
    )

    # Vérifier que la sortie est du ChatML valide
    assert "<|im_start|>" in chatml, "Pas de balise im_start"
    assert "<|im_end|>" in chatml, "Pas de balise im_end"

    # Parser et vérifier
    parsed = parse_chatml(chatml)
    assert len(parsed) >= 2, f"Parsing a produit {len(parsed)} messages"

    # Roundtrip: ChatML → messages → ChatML
    regenerated = messages_to_chatml(parsed)
    assert "<|im_start|>system" in regenerated, "Roundtrip: system perdu"
    assert "<|im_start|>user" in regenerated, "Roundtrip: user perdu"

    print(f"✅ ChatML roundtrip: {len(chatml)} chars → {len(parsed)} messages → {len(regenerated)} chars")


def test_output_is_api_compatible():
    """Vérifie que la sortie est compatible avec l'API DeepSeek/OpenRouter."""
    messages = [{"role": "user", "content": "Explique le projet CorelIA"}]
    result = render_and_parse(
        name="commander_agent",
        messages=messages,
        tools=None,
        add_generation_prompt=True,
    )

    for i, m in enumerate(result):
        # Chaque message doit avoir 'role' et 'content'
        assert "role" in m, f"Message {i}: pas de 'role'"
        assert "content" in m, f"Message {i}: pas de 'content'"
        assert m["role"] in ("system", "user", "assistant", "tool"), (
            f"Message {i}: rôle invalide '{m['role']}'"
        )
        assert isinstance(m["content"], str), f"Message {i}: content n'est pas str"
        assert len(m["content"]) > 0, f"Message {i}: content vide"

        # Vérifier que le contenu ne contient pas de ChatML résiduel
        assert "<|im_start|>" not in m["content"], (
            f"Message {i}: ChatML résiduel dans le contenu"
        )
        assert "<|im_end|>" not in m["content"], (
            f"Message {i}: ChatML résiduel dans le contenu"
        )

    # Sérialisable en JSON (compatible API)
    json.dumps(result)  # ne doit pas lever d'exception

    print(f"✅ Sortie API-compatible: {len(result)} messages valides")


if __name__ == "__main__":
    print("=" * 60)
    print("🧪 TEST D'INTÉGRATION — Template Commander Agent")
    print("=" * 60)
    print()

    tests = [
        test_template_list,
        test_render_and_parse_simple,
        test_render_and_parse_no_tools,
        test_render_and_parse_no_generation_prompt,
        test_chatml_roundtrip,
        test_output_is_api_compatible,
    ]

    passed = 0
    failed = 0
    for test in tests:
        try:
            test()
            passed += 1
        except Exception as e:
            print(f"❌ {test.__name__}: {e}")
            import traceback
            traceback.print_exc()
            failed += 1

    print()
    print("=" * 60)
    print(f"🎉 {passed}/{passed+failed} tests réussis" if not failed else f"❌ {passed}/{passed+failed} tests réussis, {failed} échecs")
    print("=" * 60)
