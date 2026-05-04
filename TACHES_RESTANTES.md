# TACHES RESTANTES — Sprint 2 Finalisation

> Date : 2026-04-24
> Branche : `br-AironBot-V2`

---

## ✅ DEJA FAITS (Phase 3)
- [x] Backend FastAPI (chat, search, auth, rate limiting)
- [x] Couche réseau Dio + JWT intercepteur
- [x] Ollama local client (détection auto)
- [x] Deep links parrainage (`deep_link_service.dart`)
- [x] Voice advanced service (`record` + `just_audio`)
- [x] Suppression services vocaux payants (100% Ollama)
- [x] Fix bypass paywall debug

---

## ⏳ A FAIRE — Priorités

### 🔴 CRITIQUE — Recherche Web Intégrée
- [ ] **UI résultats recherche** : Afficher les sources web trouvées dans une bannière/bubble au-dessus de la réponse IA (badge "Recherche web", liste des sources cliquables).
- [ ] **Fallback search** : S'assurer que SerpAPI n'est utilisé que si `SERPAPI_KEY` est configuré, sinon DuckDuckGo uniquement.

### 🔴 CRITIQUE — Voix Mains-Libres
- [ ] **Mode conversation continue** : Bouton "Conversation vocale" qui boucle écoute → STT → chat → TTS → écoute automatiquement.
- [ ] **UI état vocal** : Afficher clairement les états (écoute, traitement, réponse vocale) avec animations.
- [ ] **Fallback STT/TTS** : Si Ollama local indisponible, bascule vers `speech_to_text` + `flutter_tts` natifs

### 🟠 HAUTE — Chat Longue Mémoire
- [ ] **Pagination messages** : Lazy loading de l'historique (pas de limite 50 côté UI).
- [ ] **Contexte intelligent** : Résumer l'historique ancien via Ollama local pour ne pas perdre le contexte au-delà de 20 messages.

### 🟠 HAUTE — Monétisation Pro
- [ ] **Système crédits** : `CreditService` qui décrémente un compteur Firestore/local. Recharge via RevenueCat.
- [ ] **Bandeau GDPR** : S'assurer que le consentement AdMob est demandé (UE).

### 🟡 MOYENNE — Optimisations & Bugs
- [ ] **Migration http → dio** : Vérifier qu'aucun `http.Client` n'est utilisé directement (remplacer par Dio).
- [ ] **Debounce saisie** : Ajouter un debounce sur le champ de texte.
- [ ] **Optimisation allocations** : Buffer mutable dans `chat_notifier.dart` avant `List.unmodifiable`.
- [ ] **Reconnexion SSE** : Gérer les déconnexions/réconnections du streaming chat.

### 🟢 BASSE — Extension Chrome & Tests
- [ ] **Extension** : Polir le side-panel et la sync cross-device.
- [ ] **Tests** : Ajouter des tests E2E backend voice, tests Flutter voice.

---

## 🚀 BUILD & DEPLOIEMENT
- [ ] Vérifier `.env` build production
- [ ] `flutter build apk --release --dart-define-from-file=.env`
- [ ] `adb install` sur appareil connecté
- [ ] Tests fonctionnels sur mobile
