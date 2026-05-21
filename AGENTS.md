# AGENTS.md — Claude Code Agent Strategy

## Meta

- **Project**: Corely (ex-AironBot) — Flutter/Dart AI Chat + Chrome Extension
- **Branch**: `br-AironBot-V2` (target: beta-ready)
- **Agent**: Kimi-k2.6:cloud autonome, strict, zero-regression
- **Rule**: Aucune action sans lecture préalable de CLAUDE.md, MEMORY.md, TASKS.md, DECISIONS.md

---

## Mission

Rendre Corely **beta-ready** : tous les bugs critiques résolus, tests passants, documentation synchronisée, zéro régression.

---

## Golden Rules (infraction = échec)

1. **Zéro régression** : Avant chaque modification, écrire ou identifier le test/vérification qui prouve que l'ancien comportement reste intact.
2. **Solution globale** : Traiter les causes racines, jamais les symptômes. Si un bug vient d'un mauvais typage, réécrire le typage à la source.
3. **Mise à jour systématique** : Après CHAQUE correction/amélioration :
   - `CLAUDE.md` → nouveau contexte, limitations mises à jour
   - `MEMORY.md` → raisonnement retenu, liens entre mémoires
   - `TASKS.md` → avancement + nouvelles sous-tâches découvertes
   - `DECISIONS.md` → ADR si la solution implique un choix architectural
4. **API Keys** : Ne jamais générer de vraies clés. Documenter dans `docs/API_CONFIGURATION.md` : nom, source, commande d'injection.
5. **Flutter indisponible** : Si l'environnement n'a pas Flutter, se fier à l'analyse statique + tests unitaires écrits + `flutter analyze` si possible via CI.

---

## Redémarrage Agent Parfait

Lorsque tu reprends une session, exécute dans cet ordre EXACT :

```bash
# 1. État git
git status
git log --oneline -5

# 2. Fichiers de mémoire
cat TASKS.md | head -n 30
cat DECISIONS.md | tail -n 20
cat MEMORY.md | head -n 50

# 3. Lire les mémoires de session pertinentes
ls memory/*.md
```

Puis déduire les blocages actuels sans demander à l'utilisateur.

---

## Architecture Critique à Mémoriser

- **Pattern**: MVVM + Riverpod. Ne JAMAIS modifier `state` dans un `Notifier.build()`.
- **Autonomie**: APK Android et Extension Chrome doivent être 100% autonomes. Pas de backend local requis.
- **Conditional Imports**: `dart:io` (mobile) vs `dart:html` (web/extension). Vérifier que chaque fichier `_io` a son homologue `_web`.
- **Extension Chrome**: Manifest V3, pas de Service Worker Flutter, CanvasKit local, CSP strict.
- **AI Routing**: DeepSeek V4 Flash (free) → OpenRouter Mistral/GPT-4o-mini (Pro) → Vision → Vocal chains.
- **State Management**: `AsyncValue.valueOrNull` obligatoire, jamais `.value!`.

---

## Workflow de Correction

```
[PLAN D’ACTION]
- Objectif unique
- Fichiers impactés (minimum nécessaire)
- Preuve anti-régression (test existant ou nouveau)
- Résultat attendu

[EXECUTION]
- Lire fichier cible
- Écrire le fix
- Lire fichier test → ajouter/adapter test

[BILAN]
- Diff du changement
- Preuve (test passé, log, analyse statique)
- Mise à jour TASKS.md / CLAUDE.md / DECISIONS.md / MEMORY.md
```

---

## Contexte des Bugs Critiques Connus (Session V12+)

| Bug | Statut | Fichier clé |
|-----|--------|-------------|
| Recherche avancée (vols/hôtels/produits) | En cours | `enhanced_search_service.dart`, `chat_notifier.dart` |
| Extraction DOCX/XLSX/PPTX | En cours | `file_upload_service.dart` |
| DuckDuckGo HTML scraping fragile | En cours | `search_service.dart` |
| Commandes slash extension | Fixed V12 | `extension_bridge.js`, `chat_notifier.dart` |
| Images base64 Firestore | Fixed V12 | `message.dart`, `image_upload_service_*.dart` |
| PDF extraction FlateDecode | Fixed V12 | `file_upload_service.dart` |

---

## Interaction avec l'Utilisateur

- Ne JAMAIS demander « Que veux-tu faire ? »
- Déduire les priorités de TASKS.md
- Si ambiguity critique : proposer une décision avec trade-offs, pas une question ouverte
- Réponses concises, techniques, orientées résultat

---

## Commandes Fréquentes

```bash
# Tests
bash scripts/run_tests.sh all
flutter test path/to/test.dart

# Analyse
flutter analyze

# Build extension
bash scripts/build_extension.sh

# Build APK
flutter build apk
```

---

*Dernière mise à jour : 2026-05-21 — Session V12*
