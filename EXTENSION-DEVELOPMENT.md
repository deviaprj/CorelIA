# EXTENSION-DEVELOPMENT.md — Développement Extension Chrome AironBot

> Guide exhaustif de développement de l'extension Chrome Flutter.  
> Stack : Flutter Web · Firebase · DeepSeek-V3 · Manifest V3 · RevenueCat/Stripe

---

## Table des Matières

1. [Principe Cross-Platform](#1-principe-cross-platform)
2. [Architecture Extension Chrome](#2-architecture-extension-chrome)
3. [Manifest V3 — Configuration Complète](#3-manifest-v3--configuration-complète)
4. [Build Flutter Web → Extension](#4-build-flutter-web--extension)
5. [Différences vs App Mobile](#5-différences-vs-app-mobile)
6. [Fonctionnalité : Auth dans l'Extension](#6-fonctionnalité--auth-dans-lextension)
7. [Fonctionnalité : Chat Texte + IA Streaming](#7-fonctionnalité--chat-texte--ia-streaming)
8. [Fonctionnalité : Chat Voix (Web)](#8-fonctionnalité--chat-voix-web)
9. [Fonctionnalité : Quotas & Pubs Web](#9-fonctionnalité--quotas--pubs-web)
10. [Fonctionnalité : Abonnements (Stripe Web)](#10-fonctionnalité--abonnements-stripe-web)
11. [Fonctionnalité : Capture de Texte de Page](#11-fonctionnalité--capture-de-texte-de-page)
12. [Fonctionnalité : Sync Realtime avec App Mobile](#12-fonctionnalité--sync-realtime-avec-app-mobile)
13. [Fonctionnalité : Side Panel (Chrome 114+)](#13-fonctionnalité--side-panel-chrome-114)
14. [Stockage Sécurisé dans l'Extension](#14-stockage-sécurisé-dans-lextension)
15. [CSP & Limitations Techniques](#15-csp--limitations-techniques)
16. [Tests Extension](#16-tests-extension)
17. [Publication Chrome Web Store](#17-publication-chrome-web-store)
18. [CI/CD Extension](#18-cicd-extension)
19. [Liste Exhaustive des Fonctions Extension](#19-liste-exhaustive-des-fonctions-extension)

---

## 1. Principe Cross-Platform

L'extension Chrome est construite à partir du **même codebase Flutter** que l'application mobile. 95 % du code est partagé :

```
lib/features/chat/        → identique mobile + extension
lib/features/auth/        → identique (FirebaseAuth fonctionne sur web)
lib/features/monetization → adaptation : RevenueCat web + Stripe
lib/core/                 → identique

Spécifique Extension :
web/manifest.json         → Manifest V3
web/background.js         → Service Worker extension
lib/core/platform/        → Abstractions plateforme
```

### Détection Plateforme

```dart
// lib/core/platform/platform_service.dart
import 'package:flutter/foundation.dart';

enum AppPlatform { mobileAndroid, mobileIos, chromeExtension, web }

class PlatformService {
  static AppPlatform get current {
    if (kIsWeb) {
      // Détecter si c'est une extension Chrome
      return _isChromeExtension ? AppPlatform.chromeExtension : AppPlatform.web;
    }
    if (defaultTargetPlatform == TargetPlatform.android) return AppPlatform.mobileAndroid;
    return AppPlatform.mobileIos;
  }

  static bool get _isChromeExtension {
    // Vérifie si l'URL commence par chrome-extension://
    return Uri.base.scheme == 'chrome-extension';
  }
}
```

---

## 2. Architecture Extension Chrome

```
web/
├── manifest.json           # Manifest V3 (obligatoire)
├── background.js           # Service Worker (remplace background page)
├── content_script.js       # Script injecté dans les pages web
└── icons/
    ├── icon-16.png
    ├── icon-32.png
    ├── icon-48.png
    └── icon-128.png

build/web/                  # Sortie Flutter build web
├── index.html              # L'UI Flutter (popup / side panel)
├── main.dart.js
├── flutter.js
└── assets/
```

### Flux de Données

```
[Page Web]
  ↓ content_script.js (lecture texte sélectionné)
  ↓ chrome.runtime.sendMessage()
[background.js Service Worker]
  ↓ chrome.runtime.onMessage
[Flutter App (index.html)]
  ↓ JS Interop
[ChatFeature]
  ↓ DeepSeek API    ↕ Firebase Firestore
[UI Mise à jour]
```

---

## 3. Manifest V3 — Configuration Complète

```json
{
  "manifest_version": 3,
  "name": "AironBot — AI Chat Assistant",
  "short_name": "AironBot",
  "version": "1.0.0",
  "description": "Assistant IA gratuit basé sur DeepSeek. Chat, résumé, traduction directement dans Chrome.",
  "author": "AironBot Team",

  "action": {
    "default_popup": "index.html",
    "default_title": "AironBot",
    "default_icon": {
      "16": "icons/icon-16.png",
      "32": "icons/icon-32.png",
      "48": "icons/icon-48.png",
      "128": "icons/icon-128.png"
    }
  },

  "side_panel": {
    "default_path": "index.html"
  },

  "background": {
    "service_worker": "background.js",
    "type": "module"
  },

  "content_scripts": [
    {
      "matches": ["<all_urls>"],
      "js": ["content_script.js"],
      "run_at": "document_idle"
    }
  ],

  "permissions": [
    "storage",
    "activeTab",
    "scripting",
    "sidePanel",
    "contextMenus",
    "notifications"
  ],

  "host_permissions": [
    "https://api.deepseek.com/*",
    "https://api.anthropic.com/*",
    "https://openrouter.ai/*",
    "https://*.firebaseio.com/*",
    "https://identitytoolkit.googleapis.com/*",
    "https://securetoken.googleapis.com/*"
  ],

  "content_security_policy": {
    "extension_pages": "script-src 'self' 'wasm-unsafe-eval'; object-src 'self'; connect-src https: wss:"
  },

  "web_accessible_resources": [
    {
      "resources": ["icons/*", "assets/*"],
      "matches": ["<all_urls>"]
    }
  ],

  "commands": {
    "_execute_action": {
      "suggested_key": {
        "default": "Ctrl+Shift+A",
        "mac": "Command+Shift+A"
      }
    },
    "open_side_panel": {
      "suggested_key": {
        "default": "Ctrl+Shift+S"
      },
      "description": "Ouvrir AironBot en Side Panel"
    }
  },

  "icons": {
    "16": "icons/icon-16.png",
    "32": "icons/icon-32.png",
    "48": "icons/icon-48.png",
    "128": "icons/icon-128.png"
  }
}
```

---

## 4. Build Flutter Web → Extension

### Script de Build

```bash
#!/bin/bash
# scripts/build_extension.sh

set -e

echo "🔨 Building Flutter Web for Chrome Extension..."

flutter build web \
  --web-renderer canvaskit \
  --release \
  --dart-define=PLATFORM=chrome_extension \
  --base-href "/"

echo "📦 Copying extension manifest and scripts..."

cp web/manifest.json build/web/manifest.json
cp web/background.js build/web/background.js
cp web/content_script.js build/web/content_script.js
cp -r web/icons build/web/icons

echo "🗜️ Creating ZIP for Chrome Web Store..."

cd build/web
zip -r ../../airon_bot_extension_$(date +%Y%m%d_%H%M%S).zip . \
  --exclude "*.DS_Store" \
  --exclude "*__pycache__*"
cd ../..

echo "✅ Extension ZIP ready!"
```

### Résolution des Conflits Flutter Web vs Extension

```javascript
// web/background.js — Service Worker Manifest V3
// Écoute les messages entre content_script et Flutter
chrome.runtime.onMessage.addListener((message, sender, sendResponse) => {
  if (message.type === 'SELECTED_TEXT') {
    // Stocker le texte sélectionné pour Flutter
    chrome.storage.session.set({ selectedText: message.text });
    sendResponse({ success: true });
  }
  if (message.type === 'OPEN_SIDE_PANEL') {
    chrome.sidePanel.open({ tabId: sender.tab.id });
    sendResponse({ success: true });
  }
  return true; // Async response
});

// Context menu "Analyser avec AironBot"
chrome.runtime.onInstalled.addListener(() => {
  chrome.contextMenus.create({
    id: 'analyze-with-aironbot',
    title: 'Analyser avec AironBot',
    contexts: ['selection'],
  });
});

chrome.contextMenus.onClicked.addListener((info, tab) => {
  if (info.menuItemId === 'analyze-with-aironbot') {
    chrome.storage.session.set({ selectedText: info.selectionText });
    chrome.sidePanel.open({ tabId: tab.id });
  }
});
```

```javascript
// web/content_script.js
// Capture du texte sélectionné + raccourci clavier
document.addEventListener('mouseup', () => {
  const selected = window.getSelection()?.toString().trim();
  if (selected && selected.length > 10) {
    chrome.runtime.sendMessage({
      type: 'SELECTED_TEXT',
      text: selected,
    });
  }
});
```

---

## 5. Différences vs App Mobile

| Aspect | App Mobile | Extension Chrome |
|---|---|---|
| Taille UI | Plein écran | Popup 400×600 ou Side Panel |
| Stockage sécurisé | flutter_secure_storage | `chrome.storage.local` (chiffré) |
| Publicités | AdMob | Google Ad Manager Web ou sponsor |
| Abonnements | RevenueCat (IAP) | Stripe Web (checkout) |
| Voix | speech_to_text natif | Web Speech API (JS interop) |
| Notifications | FCM push natif | `chrome.notifications` |
| Démarrage | cold start ~1 s | popup load ~500 ms |
| Offline | SharedPreferences + cache | `chrome.storage` + Service Worker |

---

## 6. Fonctionnalité : Auth dans l'Extension

Firebase Auth fonctionne nativement dans Flutter Web. Ajouter dans `web/index.html` :

```html
<!-- web/index.html — Avant </head> -->
<script src="https://www.gstatic.com/firebasejs/10.x.x/firebase-app-compat.js"></script>
<script src="https://www.gstatic.com/firebasejs/10.x.x/firebase-auth-compat.js"></script>
```

### Popup Auth dans Extension

```dart
// SignIn avec Google dans une extension → utiliser launchUrl (popup OAuth)
// Ne PAS utiliser signInWithPopup (bloqué par CSP extensions)
Future<void> signInWithGoogleExtension() async {
  // Méthode 1 : redirect (recommandé)
  await FirebaseAuth.instance.signInWithRedirect(GoogleAuthProvider());
  
  // Méthode 2 : ouvrir une page dédiée dans un onglet Chrome
  // chrome.tabs.create({ url: 'https://yourapp.com/auth?platform=extension' });
}
```

---

## 7. Fonctionnalité : Chat Texte + IA Streaming

Identique à l'app mobile. Le même `DeepSeekClient` fonctionne sur Flutter Web via `http` (CORS autorisé par `host_permissions` dans le manifest).

### Taille de Popup Adaptée

```dart
// lib/app/extension_app.dart
class ExtensionApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      builder: (context, child) {
        // Contraindre la taille pour le popup
        if (PlatformService.current == AppPlatform.chromeExtension) {
          return SizedBox(
            width: 420,
            height: 600,
            child: child,
          );
        }
        return child!;
      },
    );
  }
}
```

---

## 8. Fonctionnalité : Chat Voix (Web)

Sur extension Chrome, `speech_to_text` utilise la Web Speech API via `dart:js_interop`.

```dart
// lib/core/platform/web_speech_service.dart
import 'dart:js_interop';

@JS('window.startWebSpeech')
external void startWebSpeech(JSFunction callback);

// web/speech_bridge.js (inclure dans index.html)
window.startWebSpeech = function(callback) {
  const recognition = new webkitSpeechRecognition();
  recognition.lang = 'fr-FR';
  recognition.interimResults = true;
  recognition.onresult = (event) => {
    const text = event.results[event.results.length-1][0].transcript;
    callback(text);
  };
  recognition.start();
};
```

---

## 9. Fonctionnalité : Quotas & Pubs Web

### Quotas
Identique à l'app mobile — vérification server-side via Cloud Function `checkQuota`.

### Publicités Web dans Extension
AdMob **ne fonctionne pas** dans les extensions Chrome. Alternatives :

| Solution | Implémentation |
|---|---|
| Google Ad Manager (Display) | Iframe dans zone dédiée hors popup |
| Sponsorships directs | Bannières statiques "Propulsé par X" |
| Pubs désactivées en extension | Modèle quota uniquement |

**Recommandé** : Désactiver les pubs dans l'extension, se concentrer sur la conversion Pro via quota.

```dart
Widget buildAdZone() {
  if (PlatformService.current == AppPlatform.chromeExtension) {
    return const SizedBox.shrink(); // Pas de pub en extension
  }
  return BannerAdWidget(); // App mobile uniquement
}
```

---

## 10. Fonctionnalité : Abonnements (Stripe Web)

RevenueCat ne gère pas le web via extension. Utiliser **Stripe** directement.

### Flux Abonnement Extension

```
[Bouton "Passer Pro"]
  → Ouvrir onglet Chrome : https://aironbot.app/checkout?uid={uid}&plan=pro_monthly
  → Page web Stripe Checkout (hébergée sur Firebase Hosting)
  → Paiement confirmé → Stripe Webhook → Cloud Function
  → Cloud Function met à jour users/{uid}.plan = "pro" dans Firestore
  → Extension écoute Firestore → UI mise à jour automatiquement
```

### Cloud Function — Stripe Webhook

```typescript
// functions/src/stripe-webhooks.ts
export const stripeWebhook = functions.https.onRequest(async (req, res) => {
  const sig = req.headers['stripe-signature']!;
  let event: Stripe.Event;
  
  try {
    event = stripe.webhooks.constructEvent(req.rawBody, sig, webhookSecret);
  } catch (err) {
    return res.status(400).send(`Webhook Error: ${err}`);
  }

  if (event.type === 'checkout.session.completed') {
    const session = event.data.object as Stripe.CheckoutSession;
    const uid = session.metadata?.uid;
    if (uid) {
      await admin.firestore().doc(`users/${uid}`).update({ plan: 'pro' });
    }
  }

  res.json({ received: true });
});
```

---

## 11. Fonctionnalité : Capture de Texte de Page

### Contexte Menu "Analyser avec AironBot"

Quand l'utilisateur sélectionne du texte sur une page web et clique droit :

```
[Texte sélectionné]
  → Clic droit → "Analyser avec AironBot"
  → background.js récupère info.selectionText
  → Stocke dans chrome.storage.session
  → Ouvre Side Panel
  → Flutter lit le texte via JS interop
  → Pré-remplit InputBar avec prompt contextuel
```

### JS Interop Flutter ↔ Chrome Storage

```dart
// lib/core/platform/chrome_storage_service.dart
import 'dart:js_interop';
import 'package:web/web.dart' as web;

@JS('chrome.storage.session.get')
external void _chromeStorageGet(JSAny keys, JSFunction callback);

class ChromeStorageService {
  static Future<String?> getSelectedText() async {
    final completer = Completer<String?>();
    _chromeStorageGet(
      'selectedText'.toJS,
      (JSAny result) {
        final text = (result as JSObject).getProperty('selectedText'.toJS) as JSString?;
        completer.complete(text?.toDart);
      }.toJS,
    );
    return completer.future;
  }
}
```

---

## 12. Fonctionnalité : Sync Realtime avec App Mobile

Grâce à Firestore, toute conversation créée sur l'extension apparaît instantanément sur l'app mobile (et vice versa).

```dart
// Stream Firestore — identique mobile/extension
@riverpod
Stream<List<Conversation>> conversationsStream(ref, String userId) {
  return FirebaseFirestore.instance
      .collection('conversations')
      .where('userId', isEqualTo: userId)
      .orderBy('updatedAt', descending: true)
      .snapshots()
      .map((s) => s.docs.map(Conversation.fromFirestore).toList());
}
```

### Indicateur Visuel de Sync

```dart
// Badge "Synchronisé" avec horodatage
StreamBuilder<DocumentSnapshot>(
  stream: userDocStream,
  builder: (ctx, snap) {
    final lastSync = (snap.data?.data() as Map?)?['lastSyncAt'];
    return lastSync != null
        ? Text('Sync · ${timeAgo(lastSync)}', style: TextStyles.caption)
        : const SizedBox.shrink();
  },
)
```

---

## 13. Fonctionnalité : Side Panel (Chrome 114+)

Le Side Panel offre bien plus d'espace qu'un popup (toute la hauteur du navigateur).

### Activation

1. Permission dans manifest : `"sidePanel"` ✓ (déjà incluse)
2. Ouvrir depuis toolbar ou raccourci `Ctrl+Shift+S`

### Adapter l'UI pour Side Panel

```dart
// Largeur adaptative
class ExtensionLayout extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final isSidePanel = width > 400; // Side Panel = ~320-450px, popup = 420px fixe

    return Scaffold(
      appBar: AironBotAppBar(compact: !isSidePanel),
      body: ChatScreen(
        showSidebar: isSidePanel, // Afficher historique si assez large
      ),
    );
  }
}
```

---

## 14. Stockage Sécurisé dans l'Extension

`flutter_secure_storage` utilise `localStorage` sur le web, qui n'est **pas chiffré**. Utiliser `chrome.storage.local` via JS interop pour les données sensibles.

```dart
// lib/core/secure_storage.dart
import 'package:flutter/foundation.dart';
import 'chrome_storage_service.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

abstract class SecureStorageService {
  Future<void> write(String key, String value);
  Future<String?> read(String key);
  Future<void> delete(String key);

  factory SecureStorageService() {
    if (kIsWeb) return ChromeSecureStorage();
    return NativeSecureStorage();
  }
}

class NativeSecureStorage implements SecureStorageService {
  final _storage = const FlutterSecureStorage();
  @override Future<void> write(String k, String v) => _storage.write(key: k, value: v);
  @override Future<String?> read(String k) => _storage.read(key: k);
  @override Future<void> delete(String k) => _storage.delete(key: k);
}

class ChromeSecureStorage implements SecureStorageService {
  // Utilise chrome.storage.local (chiffré par Chrome OS)
  @override
  Future<void> write(String key, String value) async {
    // JS interop → chrome.storage.local.set({key: value})
  }
  // ... idem read/delete
}
```

---

## 15. CSP & Limitations Techniques

### Problèmes CSP Courants

| Erreur | Cause | Solution |
|---|---|---|
| `Refused to evaluate a string as JavaScript` | `eval()` dans Flutter web | Utiliser `canvaskit` renderer |
| `Refused to load script from 'chrome-extension://'` | CSP manquante | Ajouter `'self'` dans CSP |
| `Cross-Origin Request Blocked` | API sans CORS | Requêtes uniquement vers `host_permissions` listées |
| `localStorage access denied` | Extension sandboxée | Utiliser `chrome.storage.local` |
| Popup taille incorrecte | Flutter web plein écran | Fixer width/height dans CSS + Dart |

### Configuration `web/index.html` Optimisée

```html
<!DOCTYPE html>
<html>
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=420">
  <title>AironBot</title>
  <!-- Désactiver le viewport adaptatif pour popup fixe -->
  <style>
    body { margin: 0; width: 420px; height: 600px; overflow: hidden; }
    #loading { display: flex; align-items: center; justify-content: center; height: 100%; }
  </style>
  <script>
    // Supprimer le ServiceWorker Flutter (conflit avec SW Extension)
    if ('serviceWorker' in navigator) {
      navigator.serviceWorker.getRegistrations().then(regs => {
        for (let reg of regs) reg.unregister();
      });
    }
  </script>
</head>
<body>
  <div id="loading">Chargement...</div>
  <script src="speech_bridge.js"></script>
  <script src="flutter_bootstrap.js" async></script>
</body>
</html>
```

---

## 16. Tests Extension

### Tests Manuels Essentiels

```bash
# Charger l'extension en mode dev
# Chrome → chrome://extensions → Mode développeur ON
# → "Charger l'extension non empaquetée" → sélectionner build/web/

# Vérifier :
# [ ] Popup s'ouvre sans erreur console
# [ ] Auth Firebase fonctionne (Google)
# [ ] Chat envoie et reçoit (streaming)
# [ ] Texte sélectionné pré-remplit le chat
# [ ] Context menu "Analyser avec AironBot" visible
# [ ] Side panel s'ouvre avec Ctrl+Shift+S
# [ ] Sync avec app mobile visible
```

### Tests Automatisés (Playwright)

```typescript
// tests/extension.spec.ts
import { test, expect, chromium } from '@playwright/test';
import path from 'path';

test.use({
  contextOptions: {
    args: [
      `--load-extension=${path.join(__dirname, '../build/web')}`,
      '--disable-extensions-except=' + path.join(__dirname, '../build/web'),
    ],
  },
});

test('extension popup ouvre correctement', async ({ context }) => {
  const page = await context.newPage();
  await page.goto('chrome://extensions');
  // ... test popup
});
```

---

## 17. Publication Chrome Web Store

### Prérequis

1. Compte Chrome Web Store Developer (frais unique 5 USD)
2. ZIP de `build/web/` (max 128 Mo)
3. Screenshots : 1280×800 ou 640×400 (min 1, max 5)
4. Icône promo : 440×280 px
5. Description courte (max 132 chars) et longue

### Processus de Publication

```bash
# 1. Build ZIP
./scripts/build_extension.sh

# 2. Valider le manifest (outil officiel)
npx @crxjs/vite-plugin validate web/manifest.json

# 3. Upload via API Chrome Web Store (CI/CD)
# Utiliser chrome-webstore-upload-cli :
npm install -g chrome-webstore-upload-cli

chrome-webstore-upload upload \
  --source airon_bot_extension.zip \
  --extension-id $EXTENSION_ID \
  --client-id $OAUTH_CLIENT_ID \
  --client-secret $OAUTH_CLIENT_SECRET \
  --refresh-token $OAUTH_REFRESH_TOKEN

chrome-webstore-upload publish \
  --extension-id $EXTENSION_ID \
  --client-id $OAUTH_CLIENT_ID \
  --client-secret $OAUTH_CLIENT_SECRET \
  --refresh-token $OAUTH_REFRESH_TOKEN
```

### Politique Chrome Store — Points Critiques

- **Privacy Policy** requise (Firebase, DeepSeek API, données utilisateur)
- **Permissions minimales** : ne demander que ce qui est utilisé
- **Déclaration des clés API** : ne jamais inclure dans le ZIP

---

## 18. CI/CD Extension

### `.github/workflows/extension.yml`

```yaml
name: Extension Chrome Build & Deploy

on:
  push:
    tags: ['v*']
  workflow_dispatch:

jobs:
  build-extension:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - uses: subosito/flutter-action@v2
        with:
          flutter-version: '3.24.0'

      - run: flutter pub get

      - name: Inject Secrets
        run: |
          sed -i "s/DEEPSEEK_API_KEY_PLACEHOLDER/${{ secrets.DEEPSEEK_API_KEY }}/g" \
            lib/core/constants.dart

      - name: Build Flutter Web
        run: |
          flutter build web \
            --web-renderer canvaskit \
            --release \
            --dart-define=PLATFORM=chrome_extension

      - name: Package Extension
        run: |
          cp web/manifest.json build/web/
          cp web/background.js build/web/
          cp web/content_script.js build/web/
          cp -r web/icons build/web/
          cd build/web && zip -r ../../extension.zip .

      - name: Upload to Chrome Web Store
        run: |
          npx chrome-webstore-upload-cli upload \
            --source extension.zip \
            --extension-id ${{ secrets.EXTENSION_ID }}
        env:
          OAUTH_CLIENT_ID: ${{ secrets.CHROME_OAUTH_CLIENT_ID }}
          OAUTH_CLIENT_SECRET: ${{ secrets.CHROME_OAUTH_CLIENT_SECRET }}
          OAUTH_REFRESH_TOKEN: ${{ secrets.CHROME_OAUTH_REFRESH_TOKEN }}
```

---

## 19. Liste Exhaustive des Fonctions Extension

### Spécifiques Extension (en plus des fonctions mobile partagées)

#### Manifest & Background
- `initializeExtension()` — setup context menus, raccourcis
- `handleContextMenuClick(info, tab)` — texte sélectionné → chat
- `openSidePanel(tabId)` — ouvrir side panel Chrome
- `openPopup()` — ouvrir popup standard
- `sendMessageToFlutter(type, data)` — background → Flutter

#### Content Script
- `captureSelectedText()` — texte sélectionné sur la page
- `injectQuickChatButton()` — bouton flottant sur la page (optionnel)
- `getPageContent()` — résumer la page courante
- `getPageTitle()` — titre de l'onglet actif

#### Stockage Extension
- `chromeStorageGet(key)` — lire chrome.storage.local
- `chromeStorageSet(key, value)` — écrire chrome.storage.local
- `chromeStorageRemove(key)` — supprimer une clé
- `chromeStorageClear()` — vider tout le stockage

#### UI Extension
- `setPopupSize(width, height)` — dimensionner le popup
- `initSidePanel()` — initialiser le side panel
- `showExtensionNotification(title, message)` — chrome.notifications
- `updateBadge(text, color)` — badge sur l'icône extension (nb requêtes restantes)

#### Intégration Page Web
- `analyzeSelectedText(text)` — analyser texte sélectionné
- `summarizeCurrentPage()` — résumer la page active
- `translateSelection(text, targetLang)` — traduire texte sélectionné
- `explainCode(code)` — expliquer du code sélectionné

#### Auth Web
- `signInWithGoogleTab()` — Auth Google via nouvel onglet
- `handleAuthRedirectCallback()` — traiter retour OAuth
- `syncAuthStateExtension()` — sync state auth cross-onglets

#### Performance Extension
- `preloadFlutterAssets()` — précharger assets au démarrage Chrome
- `cacheLastConversation()` — mémoriser dernière conv pour ouverture rapide
- `trackExtensionUsage(event)` — Firebase Analytics events
