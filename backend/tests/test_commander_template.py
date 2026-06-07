#!/usr/bin/env python3
"""Test de rendu du template commander_agent.jinja2 dans différents scénarios."""

import json
import sys
sys.path.insert(0, ".")

try:
    from jinja2 import Environment, FileSystemLoader, TemplateSyntaxError
except ImportError:
    print("❌ Jinja2 non installé. Lancez: pip install jinja2")
    sys.exit(1)

env = Environment(loader=FileSystemLoader("templates"))
template = env.get_template("commander_agent.jinja2")

# --- Messages simulés ---
class Msg:
    def __init__(self, role, content, tool_calls=None):
        self.role = role
        self.content = content
        self.tool_calls = tool_calls or []

class ToolCall:
    def __init__(self, name, arguments):
        self.function = type("F", (), {"name": name, "arguments": arguments})()

# --- Scénario 1: Premier message utilisateur (add_generation_prompt=True) ---
print("=" * 70)
print("SCÉNARIO 1: Premier message utilisateur avec tools et generation_prompt")
print("=" * 70)
output1 = template.render(
    messages=[
        Msg("user", "Construis-moi une application de chat IA")
    ],
    tools=[{"name": "agent_open", "description": "Ouvrir un sous-agent"}],
    add_generation_prompt=True,
)
print(output1[:2000])
print("... (tronqué)")

# Vérifications
assert "Oui Monsieur, c'est très clair." in output1, "❌ Auto-réponse absente"
assert "Construis-moi une application de chat IA" in output1, "❌ Message utilisateur absent"
assert "ANALYSE PRÉLIMINAIRE" in output1, "❌ Analyse absente"
assert "DEMANDE DE VALIDATION FINALE" in output1, "❌ Validation absente"
assert "OUTILS DISPONIBLES" in output1, "❌ Section outils absente"
# Vérifier que le système prompt est présent même avec tools
assert "<|im_start|>system" in output1, "❌ System prompt absent"
print("✅ Scénario 1 OK\n")

# --- Scénario 2: Sans outils (tools=None) ---
print("=" * 70)
print("SCÉNARIO 2: Sans outils (tools=None)")
print("=" * 70)
output2 = template.render(
    messages=[Msg("user", "Bonjour")],
    tools=None,
    add_generation_prompt=True,
)
assert "OUTILS DISPONIBLES" not in output2, "❌ Section outils présente alors que tools=None"
assert "<|im_start|>system" in output2, "❌ System prompt absent (tools=None)"
assert "Bonjour" in output2, "❌ Message utilisateur absent"
assert "Oui Monsieur" in output2, "❌ Auto-réponse absente"
print("✅ Scénario 2 OK (system prompt présent, outils absents)\n")

# --- Scénario 3: Multi-tour (historique) ---
print("=" * 70)
print("SCÉNARIO 3: Conversation multi-tour")
print("=" * 70)
output3 = template.render(
    messages=[
        Msg("user", "Première question"),
        Msg("assistant", "Première réponse"),
        Msg("user", "Deuxième question"),
    ],
    tools=[{"name": "read_file"}],
    add_generation_prompt=True,
)
# Le system prompt contient la phrase 1x, l'auto-réponse 1x = 2 au total
count_oui = output3.count("Oui Monsieur, c'est très clair.")
assert count_oui == 2, f"❌ {count_oui} occurences au lieu de 2 (1 system + 1 auto-réponse)"
assert "Première question" in output3, "❌ Premier msg absent"
assert "Première réponse" in output3, "❌ Réponse assistant absente"
assert "Deuxième question" in output3, "❌ Deuxième msg absent"
print(f"✅ Scénario 3 OK (1 seule auto-réponse pour {count_oui} occurences)\n")

# --- Scénario 4: Sans generation_prompt (lecture historique seule) ---
print("=" * 70)
print("SCÉNARIO 4: Historique seul (add_generation_prompt=False)")
print("=" * 70)
output4 = template.render(
    messages=[
        Msg("user", "Question"),
        Msg("assistant", "Réponse"),
    ],
    tools=None,
    add_generation_prompt=False,
)
# "Oui Monsieur" est dans le system prompt, on vérifie l'absence du bloc auto-réponse
assert "**Reformulation :**" not in output4, "❌ Auto-réponse présente alors que generation_prompt=False"
assert "**ANALYSE PRÉLIMINAIRE :**" not in output4, "❌ Analyse présente alors que generation_prompt=False"
assert "Question" in output4, "❌ Message utilisateur absent"
assert "Réponse" in output4, "❌ Réponse assistant absente"
print("✅ Scénario 4 OK (pas d'auto-réponse)\n")

# --- Scénario 5: Tool calls dans l'historique assistant ---
print("=" * 70)
print("SCÉNARIO 5: Assistant avec tool_calls")
print("=" * 70)
output5 = template.render(
    messages=[
        Msg("user", "Lis le fichier"),
        Msg("assistant", "Je vais lire le fichier", tool_calls=[
            ToolCall("read_file", {"path": "/tmp/test.txt"})
        ]),
        Msg("tool", "contenu du fichier"),
        Msg("assistant", "Voici le contenu"),
    ],
    tools=[{"name": "read_file"}],
    add_generation_prompt=True,
)
# Le dernier message est assistant, donc generation_prompt ajoute un <|im_start|>assistant final
assert "read_file" in output5, "❌ Tool call absent"
assert "contenu du fichier" in output5, "❌ Tool response absent"
# Vérifier que le tool a le bon format
assert '<tool_call>' in output5, "❌ Format tool_call absent"
print("✅ Scénario 5 OK\n")

# --- Scénario 6: Messages système dans l'historique ---
print("=" * 70)
print("SCÉNARIO 6: Message système dans l'historique")
print("=" * 70)
output6 = template.render(
    messages=[
        Msg("system", "Instruction système additionnelle"),
        Msg("user", "OK"),
    ],
    tools=None,
    add_generation_prompt=True,
)
assert "Instruction système additionnelle" in output6, "❌ System msg absent"
print("✅ Scénario 6 OK\n")

print("=" * 70)
print("🎉 TOUS LES SCÉNARIOS SONT VALIDES")
print("=" * 70)
