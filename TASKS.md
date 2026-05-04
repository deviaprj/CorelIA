# TASKS.md — Suivi AironBot

Dernière mise à jour : 2026-05-04 — Session correctifs majeurs (commits `420b07ba`, `1512d607`)

## Terminé

- [x] **Microphone** — Instance STT fraîche par `startListening()`, `ListenMode.dictation`, deadlock `_speakResponseAndLoop()` corrigé
- [x] **TTS vitesse** — Réduite à 0.65 (multiple itérations), pitch 1.10
- [x] **Vision / Images** — Routage prioritaire AVANT Pro/Free, fallback `deepseek-chat`, erreurs formatées, limite 1 MB
- [x] **Pièces jointes UX** — `AttachmentData` + `SendCallback`, chip preview + ✕, envoi simultané texte + fichier
- [x] **Web Search** — `useSearch: true` par défaut, `enable_search: true` dans body DeepSeek
- [x] **Chat bloqué** — `isStreaming: false` forcé dans tous les blocs catch
- [x] **Analyse fichiers** — BOM UTF-8/UTF-16 dans `_decodeTextFile()`, nom du fichier dans le contexte système
- [x] **Documentation** — CLAUDE.md (routage, vocal, pièces jointes, erreurs), MEMORY.md, TASKS.md

## En cours

- [ ] **Vérification `deepseek-chat` vision** — Test live pour confirmer que le modèle supporte bien `image_url`
- [ ] **Persistance contexte fichier** — Le contenu extrait est injecté en système mais pas persisté entre les messages

## Backlog

- [ ] **Persistance imageBase64** — Les images ne survivent pas au rechargement Firestore (trop volumineuses)
- [ ] **Upload Firebase Storage** — Remplacer base64 par URL Storage pour les images
- [ ] **Tests UI mode vocal** — Pas de tests automatisés pour le flux vocal complet
- [ ] **Analytique Crashlytics** — Brancher Firebase Crashlytics
