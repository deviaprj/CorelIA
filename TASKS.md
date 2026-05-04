# TASKS.md — Suivi AironBot

Dernière mise à jour : 2026-05-04 — Session correctifs majeurs (commit `420b07ba`)

## Terminé

- [x] **Microphone** — Instance STT fraîche par `startListening()`, `ListenMode.dictation`, deadlock `_speakResponseAndLoop()` corrigé
- [x] **TTS vitesse** — Réduite à 0.65 (multiple itérations), pitch 1.10
- [x] **Vision / Images** — Routage prioritaire AVANT Pro/Free, fallback `deepseek-chat`, erreurs formatées, limite 1 MB
- [x] **Pièces jointes UX** — `AttachmentData` + `SendCallback`, chip preview + ✕, envoi simultané texte + fichier
- [x] **Web Search** — `useSearch: true` par défaut, `enable_search: true` dans body DeepSeek
- [x] **Chat bloqué** — `isStreaming: false` forcé dans tous les blocs catch
- [x] **CLAUDE.md / MEMORY.md** — Documentation architecture vocale, vision, pièces jointes

## En cours

- [ ] **Analyse fichiers TXT/MD** — Test live de l'extraction et injection contexte pour fichiers texte
- [ ] **Vérification `deepseek-chat` vision** — Test live pour confirmer que le modèle supporte bien `image_url`
- [ ] **Gestion fichiers conversation** — Améliorer la persistance du contexte fichier entre les messages

## Backlog

- [ ] **Persistance imageBase64** — Les images ne survivent pas au rechargement Firestore (trop volumineuses)
- [ ] **Upload Firebase Storage** — Remplacer base64 par URL Storage pour les images
- [ ] **Tests UI mode vocal** — Pas de tests automatisés pour le flux vocal complet
- [ ] **Analytique Crashlytics** — Brancher Firebase Crashlytics
