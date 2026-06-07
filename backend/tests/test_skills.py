#!/usr/bin/env python3
"""Test rapide de la découverte de skills."""
import sys
sys.path.insert(0, ".")

from backend.core.skills_discovery import discover_skills, get_skills_context, load_skill

s = discover_skills()
print(f"Skills trouvés: {len(s)}")
for k, v in s.items():
    print(f"  - {k}: {v['name']} ({v['source']})")

print()
ctx = get_skills_context()
if ctx:
    print(f"Contexte skills: {len(ctx)} chars")
    print(ctx[:500])
else:
    print("Contexte skills: (vide)")

print()
sk = load_skill("mobile-ai-chat")
if sk:
    print(f"Skill chargé: {sk['name']}")
    print(f"Files: {sk['files']}")
    print(f"Content: {len(sk['content'])} chars")
else:
    print("Skill NON TROUVÉ")
