#!/usr/bin/env python3
"""Test du template vision_agent.jinja2 — multimodal (texte, image, vidéo, tool calls)."""

import json
import sys
sys.path.insert(0, ".")

from jinja2 import Environment, FileSystemLoader

env = Environment(
    loader=FileSystemLoader("templates"),
    trim_blocks=True,
    lstrip_blocks=True,
)
template = env.get_template("vision_agent.jinja2")


class Msg:
    def __init__(self, role, content, tool_calls=None):
        self.role = role
        self.content = content
        self.tool_calls = tool_calls or []


def render(messages, tools=None, add_generation_prompt=True, add_vision_id=False):
    return template.render(
        messages=messages,
        tools=tools or [],
        add_generation_prompt=add_generation_prompt,
        add_vision_id=add_vision_id,
    )


# --- Scénario 1: Message texte simple ---
print("=" * 60)
print("SCÉNARIO 1: Message texte simple")
print("=" * 60)
out1 = render([Msg("user", "Décris cette image")])
assert "<|im_start|>user" in out1, "❌ Balise user absente"
assert "Décris cette image" in out1, "❌ Contenu texte absent"
assert "<|im_end|>" in out1, "❌ Balise fermeture absente"
print("✅ OK\n")

# --- Scénario 2: Message multimodal (texte + image) ---
print("=" * 60)
print("SCÉNARIO 2: Message multimodal (texte + image)")
print("=" * 60)
out2 = render([
    Msg("user", [
        {"type": "text", "text": "Que vois-tu ?"},
        {"type": "image_url", "image_url": {"url": "data:image/jpeg;base64,/9j/..."}},
    ])
], add_vision_id=True)
assert "<|im_start|>user" in out2, "❌ Balise user absente"
assert "Que vois-tu ?" in out2, "❌ Texte absent"
assert "Picture 1:" in out2, "❌ Vision ID absent"
assert "<|vision_start|><|image_pad|><|vision_end|>" in out2, "❌ Token vision absent"
print("✅ OK\n")

# --- Scénario 3: Image sans add_vision_id ---
print("=" * 60)
print("SCÉNARIO 3: Image sans add_vision_id (pas de 'Picture N:')")
print("=" * 60)
out3 = render([
    Msg("user", [
        {"type": "image_url", "image_url": {"url": "data:image/png;base64,abc"}},
    ])
], add_vision_id=False)
assert "Picture" not in out3, "❌ Vision ID présent alors que add_vision_id=False"
assert "<|vision_start|><|image_pad|><|vision_end|>" in out3, "❌ Token vision absent"
print("✅ OK\n")

# --- Scénario 4: Tool calls assistant ---
print("=" * 60)
print("SCÉNARIO 4: Message assistant avec tool_calls")
print("=" * 60)
tc = type("TC", (), {"name": "search_web", "arguments": '{"query": "météo Paris"}'})
tc2 = type("TC2", (), {"name": "get_weather", "arguments": {"city": "Paris"}})
out4 = render([
    Msg("user", "Quel temps fait-il ?"),
    Msg("assistant", "Je consulte la météo...", tool_calls=[tc, tc2]),
])
assert '<tool_call>' in out4, "❌ tool_call absent"
assert 'search_web' in out4, "❌ Nom outil absent"
assert 'get_weather' in out4, "❌ Deuxième outil absent"
assert '"query": "météo Paris"' in out4, "❌ Arguments string absents"
assert '"city": "Paris"' in out4, "❌ Arguments dict absents"
print("✅ OK\n")

# --- Scénario 5: Tool response ---
print("=" * 60)
print("SCÉNARIO 5: Message tool (tool_response)")
print("=" * 60)
out5 = render([
    Msg("user", "Météo ?"),
    Msg("assistant", "", tool_calls=[tc]),
    Msg("tool", "Il fait 22°C à Paris"),
])
assert '<tool_response>' in out5, "❌ tool_response absent"
assert '22°C' in out5, "❌ Contenu tool absent"
# Les tool responses sont wrappées dans <|im_start|>user
assert '<|im_start|>user' in out5, "❌ Tool response: user tag absent"
print("✅ OK\n")

# --- Scénario 6: Plusieurs tools consécutifs (groupés) ---
print("=" * 60)
print("SCÉNARIO 6: Plusieurs tools consécutifs groupés sous un seul user")
print("=" * 60)
out6 = render([
    Msg("user", "Recherche"),
    Msg("assistant", "", tool_calls=[tc]),
    Msg("tool", "Résultat 1"),
    Msg("tool", "Résultat 2"),
    Msg("tool", "Résultat 3"),
])
# Vérifier qu'il n'y a qu'UN seul <|im_start|>user pour les 3 tools
user_start_count = out6.count("<|im_start|>user")
# Il y a le message user original + 1 pour le groupe de tools = 2
assert user_start_count == 2, f"❌ {user_start_count} <|im_start|>user au lieu de 2"
print(f"✅ OK ({user_start_count} blocs user)\n")

# --- Scénario 7: add_generation_prompt ---
print("=" * 60)
print("SCÉNARIO 7: add_generation_prompt = True")
print("=" * 60)
out7a = render([Msg("user", "Test")], add_generation_prompt=True)
assert out7a.rstrip().endswith("<|im_start|>assistant"), f"❌ Fin inattendue: {out7a[-80:]}"

out7b = render([Msg("user", "Test")], add_generation_prompt=False)
assert not out7b.rstrip().endswith("<|im_start|>assistant"), "❌ generation_prompt présent alors que False"
print("✅ OK\n")

# --- Scénario 8: Message user avec content string ---
print("=" * 60)
print("SCÉNARIO 8: Content string (pas de liste)")
print("=" * 60)
out8 = render([Msg("user", "Bonjour")])
assert "<|im_start|>user" in out8, "❌ Balise user absente"
assert "Bonjour" in out8, "❌ Contenu absent"
assert "<|im_end|>" in out8, "❌ Balise fin absente"
print("✅ OK\n")

# --- Scénario 9: Video content ---
print("=" * 60)
print("SCÉNARIO 9: Contenu vidéo")
print("=" * 60)
out9 = render([
    Msg("user", [
        {"type": "text", "text": "Analyse cette vidéo"},
        {"type": "video", "video_url": "https://exemple.com/video.mp4"},
    ])
], add_vision_id=True)
assert "<|vision_start|><|video_pad|><|vision_end|>" in out9, "❌ Token vidéo absent"
assert "Video 1:" in out9, "❌ Video ID absent"
assert "Analyse cette vidéo" in out9, "❌ Texte absent"
print("✅ OK\n")

# --- Vérifications globales ---
print("=" * 60)
print("🔍 VÉRIFICATIONS GLOBALES")
print("=" * 60)

# Vérifier qu'aucun ChatML n'est cassé
all_outputs = [out1, out2, out3, out4, out5, out6, out7a, out7b, out8, out9]
for i, out in enumerate(all_outputs):
    # Vérifier que chaque <|im_start|> a un <|im_end|> correspondant
    starts = out.count("<|im_start|>")
    ends = out.count("<|im_end|>")
    # Le dernier peut être ouvert (generation_prompt)
    if out.rstrip().endswith("<|im_start|>assistant"):
        starts -= 1  # Le dernier <|im_start|> est volontairement non fermé
    assert starts == ends, f"Scénario {i+1}: {starts} starts != {ends} ends"
print(f"✅ Tous les ChatML sont équilibrés")

# Vérifier que le template fonctionne sans outils
assert all("<tools>" not in out for out in all_outputs), "❌ <tools> présent"
print("✅ Aucun <tools> résiduel")

print()
print("=" * 60)
print("🎉 TOUS LES TESTS SONT VALIDES")
print("=" * 60)
