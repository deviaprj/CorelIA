# Evaluation des Modeles TTS Avances pour Corely

## Objectif
Documenter et comparer les options TTS (Text-to-Speech) pour le mode conversation vocal de Corely, avec un focus sur la latence (<300ms target), la qualite audio, et la complexite d'integration.

---

## Modeles Evalues

### 1. OpenRouter TTS (gpt-4o-mini-tts) — Actuellement primaire

| Critere | Valeur |
|---|---|
| **Latence first-audio** | 800ms - 2500ms (HTTP round-trip + generation) |
| **Cout** | ~$0.015 / 1M chars (variable selon le modele) |
| **Qualite (MOS est.)** | 4.2 — Voix tres naturelle, bonne prosodie, emotions |
| **Integration** | Faible — HTTP POST simple, retour MP3 complet |
| **Plateforme** | Mobile uniquement (fichier MP3) |
| **Streaming** | Non — full-buffer uniquement |
| **Hesitations** | Non supporte natively (modele ne genere pas "euh") |

**Verdict** : Excellent en qualite mais latence trop elevee pour le turn-taking fluide. Reste en fallback premium.

---

### 2. Edge TTS (Microsoft Bing Speech API) — Inutilise mais code existant

| Critere | Valeur |
|---|---|
| **Latence first-audio** | 150ms - 400ms (WebSocket, streaming incremental) |
| **Cout** | Gratuit |
| **Qualite (MOS est.)** | 3.8 — Voix neurales correctes, moins nuancees qu'OpenRouter |
| **Integration** | Moyenne — WebSocket + ecriture fichier incremental |
| **Plateforme** | Mobile uniquement (dart:io + WebSocket) |
| **Streaming** | Oui — `synthesizeStream()` existe et emet fichier des ~4KB |
| **Hesitations** | Non — mais post-processing par `VocalHesitationInjector` possible |

**Verdict** : **Choix immediat** pour le streaming TTS a faible latence. Le code existe deja (`EdgeTtsService.synthesizeStream()`). Activation recommandee comme moteur primaire en mode conversation.

---

### 3. flutter_tts (Web Speech API / moteurs natifs) — Fallback universel

| Critere | Valeur |
|---|---|
| **Latence first-audio** | 50ms - 200ms (local) |
| **Cout** | Gratuit |
| **Qualite (MOS est.)** | 2.5 — Variable selon le moteur systeme (pico = bas, Google Neural = correct) |
| **Integration** | Tres faible — Package Flutter mature |
| **Plateforme** | Toutes (Android/iOS/Web/Extension) |
| **Streaming** | Non — parle par chunks de 120 chars |
| **Hesitations** | Supporte via post-processing |

**Verdict** : Indispensable comme fallback universel, surtout sur web/extension ou Edge/OpenRouter ne fonctionnent pas.

---

### 4. ElevenLabs (API Cloud)

| Critere | Valeur |
|---|---|
| **Latence first-audio** | 300ms - 800ms (HTTP streaming possible avec `stream: true`) |
| **Cout** | ~$0.18 / 1K chars (5$/mois starter) |
| **Qualite (MOS est.)** | 4.5 — Leader du marche, emotions integrees, voix clones |
| **Integration** | Faible — HTTP POST, retour audio streaming ou fichier |
| **Plateforme** | Toutes (API cloud) |
| **Streaming** | Oui — via `output_format=mp3_22050_32` + stream=true |
| **Hesitations** | Partiel — certains modeles ajoutent des pauses naturelles |

**Verdict** : **Option premium ideale** si les couts sont acceptables. Qualite superieure, latence raisonnable avec streaming, multi-plateforme. A evaluer comme tier "Pro+".

---

### 5. StyleTTS 2 (Open-Source, Self-Hosted)

| Critere | Valeur |
|---|---|
| **Latence first-audio** | 200ms - 500ms (inference locale GPU) |
| **Cout** | Gratuit (infrastructure self-hosted) |
| **Qualite (MOS est.)** | 4.0 — Tres bonne, controle fin du style/prosodie |
| **Integration** | Elevee — Modele PyTorch (~200MB), necessite ONNX/CoreML conversion |
| **Plateforme** | Server-side ou desktop (trop lourd pour mobile) |
| **Streaming** | Non — inference par phrase complete |
| **Hesitations** | Possible via controle prosodique dans le modele |

**Verdict** : **Rejete pour mobile** — modele trop lourd, complexite d'integration elevee. Option interessante pour un backend cloud dedie a la synthese vocale (`api.corelia.app/tts`).

---

### 6. kokoro-82m (Open-Source, via OpenRouter)

| Critere | Valeur |
|---|---|
| **Latence first-audio** | 600ms - 1500ms (via OpenRouter) |
| **Cout** | Gratuit (via OpenRouter) ou self-hosted |
| **Qualite (MOS est.)** | 3.5 — Correct, legerement robotique |
| **Integration** | Faible (via OpenRouter) ou Moyenne (self-hosted) |
| **Plateforme** | Mobile (via OpenRouter) |
| **Streaming** | Non |
| **Hesitations** | Non |

**Verdict** : Fallback OpenRouter existant. Qualite inferieure a gpt-4o-mini-tts.

---

## Recommandations

### Court terme (cette session)
1. **Activer Edge TTS streaming** comme moteur primaire en mode conversation vocal sur mobile.
2. **Conserver OpenRouter TTS** comme fallback qualite pour les phrases courtes ou les reponses importantes.
3. **Conserver flutter_tts** comme fallback universel (web/extension).

### Moyen terme
1. **Evaluer ElevenLabs** pour un tier "Pro+" — integration simple via HTTP, qualite superieure, streaming supporte.
2. **Mettre en place** un endpoint `/tts` sur le backend cloud pour heberger StyleTTS 2 ou ElevenLabs cote serveur (reduit la latence cote client, centralise les cles API).

### Long terme
1. **Hybrid streaming** : commencer avec Edge TTS des les premiers tokens, basculer vers ElevenLabs pour la fin de la reponse si la qualite est critique.
2. **Voix personnalisee** : fine-tuning ElevenLabs avec la voix "Corely" pour une identite sonore unique.

---

## Tableau Recapitulatif

| Moteur | Latence | Cout | Qualite | Integration | Streaming | Plateforme |
|---|---|---|---|---|---|---|
| **Edge TTS** | 150-400ms | Gratuit | 3.8 | Moyenne | Oui (fichier) | Mobile |
| **OpenRouter TTS** | 800-2500ms | $/chars | 4.2 | Faible | Non | Mobile |
| **flutter_tts** | 50-200ms | Gratuit | 2.5 | Tres faible | Non | Toutes |
| **ElevenLabs** | 300-800ms | $$/chars | 4.5 | Faible | Oui (HTTP) | Toutes |
| **StyleTTS 2** | 200-500ms* | Gratuit | 4.0 | Elevee | Non | Server |
| **kokoro-82m** | 600-1500ms | Gratuit | 3.5 | Faible | Non | Mobile |

*Latence StyleTTS 2 depend fortement du hardware (GPU local).

---

*Document genere le 2026-05-22 — Session Vocal Turn-Taking V15*
