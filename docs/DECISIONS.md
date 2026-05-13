# DECISIONS.md — Corely

Dernière mise à jour : 2026-05-13

## Décisions techniques

### 2026-05-13 : ConsentBanner utilise rootNavigatorKey
- **Décision** : `ConsentBanner.showIfNeeded()` utilise `rootNavigatorKey.currentContext` (du GoRouter) au lieu du context de `CorelyApp.build()`
- **Pourquoi** : `showModalBottomSheet` appelle `Navigator.of(context)` avec un `!` null check. Le context de `CorelyApp` est au-dessus du `MaterialApp.router` → pas de `Navigator` ancêtre → crash.
- **Implémentation** : `GlobalKey<NavigatorState> rootNavigatorKey` dans `router.dart`, passé à `GoRouter(navigatorKey:)`

### 2026-05-13 : VoiceServiceNotifier retourne l'état initial au lieu de le modifier
- **Décision** : `VoiceServiceNotifier.build()` retourne `VoiceState(isAvailable: _webBridge!.isAvailable)` au lieu de `state = state.copyWith(isAvailable: true)`
- **Pourquoi** : Riverpod interdit la modification de `state` pendant `build()`. Modifier `state` provoque une réinitialisation immédiate du provider → cascade "uninitialized provider".
- **Général** : Tout `Notifier.build()` doit retourner l'état initial directement, jamais modifier `state` dans `build()`.

### 2026-05-13 : AsyncValue.value! remplacé par valueOrNull
- **Décision** : Remplacer tous les `next.value!` par `next.valueOrNull` avec null checks
- **Pourquoi** : Les transitions d'état Riverpod (AsyncLoading → AsyncData) peuvent temporairement rendre `value` null même quand `hasValue` est true.
- **Pattern** : `final messages = next.valueOrNull; if (messages == null) return;`

### 2026-05-13 : Commandes slash ne fonctionnent pas sur l'extension
- **Statut** : Problème connu, à corriger dans une prochaine session
- **Détail** : `/download`, `/pdf`, `/links`, `/summarize`, `/extract`, `/scroll`, `/open`, `/click`, `/fill`, `/screenshot`, `/back`, `/forward` envoient l'action via `ExtensionBridge.executeAction()` mais le résultat ne revient jamais au chat. Le système BrowserActions côté JS ne retourne pas de réponse au callback Dart.
- **Piste de correction** : Vérifier le flux `browser_actions.js` → `background.js` → `content_script.js` → réponse asynchrone. Le callback `chrome.runtime.sendMessage` ne reçoit probablement pas la réponse du content script.

## À faire lors de la prochaine session

1. **Corriger les commandes slash sur l'extension** — Le flux complet de réponse ne fonctionne pas : `ChatNotifier._handleSlashCommand()` → `ExtensionBridge.executeAction()` → `browser_actions.js` → `background.js` → `content_script.js` → retour. Le `_pendingActions` Completer ne reçoit jamais de réponse.
2. **Tester le flux complet de l'extension** — Charger l'extension, vérifier que le chat fonctionne, envoyer un message à l'IA, vérifier les commandes slash.
3. **Vérifier les autres providers Riverpod** — Chercher d'autres `state = state.copyWith(...)` dans des méthodes `build()` qui pourraient causer des réentrances.
4. **Vérifier le mode mobile** — Tester l'APK sur le Xiaomi pour s'assurer que les corrections (ConsentBanner, VoiceServiceNotifier) ne cassent pas le flux mobile.