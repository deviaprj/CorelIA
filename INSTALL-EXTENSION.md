# INSTALL-EXTENSION.md — Guide d'Installation Extension Chrome AironBot

> Guide complet pour builder, installer et publier l'extension Chrome Flutter.

---

## Prérequis

Les mêmes prérequis que pour l'app mobile, plus :

| Outil | Version | Note |
|---|---|---|
| Chrome / Chromium | 114+ | Pour Side Panel + Manifest V3 |
| Node.js | 20 LTS | Pour les scripts de packaging |
| chrome-webstore-upload-cli | latest | Pour la publication automatisée |

```bash
# Installer l'outil de publication Chrome
npm install -g chrome-webstore-upload-cli
```

---

## Étape 1 — Préparer l'Environnement

Suivre d'abord les étapes 1 à 4 de [INSTALL-MOBILE.md](./INSTALL-MOBILE.md) pour :
- Cloner le projet
- Installer les dépendances Flutter
- Configurer Firebase
- Configurer les clés API

L'extension utilise le même `lib/` que l'app mobile.

---

## Étape 2 — Vérifier la Configuration Web Flutter

```bash
# Vérifier que la cible web est activée
flutter config --enable-web
flutter devices
# Doit afficher : Chrome (web-javascript)
```

---

## Étape 3 — Préparer les Assets Extension

### Icônes Requises

Créer les icônes dans `web/icons/` :

```
web/icons/
├── icon-16.png    (16×16 px)
├── icon-32.png    (32×32 px)
├── icon-48.png    (48×48 px)
└── icon-128.png   (128×128 px)
```

Outil recommandé pour redimensionner :

```bash
# Avec ImageMagick
convert logo.png -resize 128x128 web/icons/icon-128.png
convert logo.png -resize 48x48  web/icons/icon-48.png
convert logo.png -resize 32x32  web/icons/icon-32.png
convert logo.png -resize 16x16  web/icons/icon-16.png
```

### Vérifier les Fichiers Extension

```
web/
├── manifest.json        ✅ Manifest V3
├── background.js        ✅ Service Worker
├── content_script.js    ✅ Injection pages
├── speech_bridge.js     ✅ Web Speech API
└── icons/
    ├── icon-16.png      ✅
    ├── icon-32.png      ✅
    ├── icon-48.png      ✅
    └── icon-128.png     ✅
```

---

## Étape 4 — Build Flutter Web pour Extension

### Build Manuel

```bash
flutter build web \
  --web-renderer canvaskit \
  --release \
  --dart-define=PLATFORM=chrome_extension \
  --dart-define-from-file=.env
```

### Copier les Fichiers Extension

```bash
cp web/manifest.json      build/web/manifest.json
cp web/background.js      build/web/background.js
cp web/content_script.js  build/web/content_script.js
cp web/speech_bridge.js   build/web/speech_bridge.js
cp -r web/icons           build/web/icons
```

### Script de Build Complet

```bash
# Rendre le script exécutable une seule fois
chmod +x scripts/build_extension.sh

# Lancer le build
./scripts/build_extension.sh
```

Le script génère :
- `build/web/` — dossier chargeable dans Chrome
- `airon_bot_extension_YYYYMMDD.zip` — ZIP pour le Chrome Web Store

---

## Étape 5 — Charger l'Extension en Mode Développement (Sideloading)

1. Ouvrir Chrome et aller sur : `chrome://extensions`

2. Activer le **Mode développeur** (toggle en haut à droite)

3. Cliquer **"Charger l'extension non empaquetée"**

4. Sélectionner le dossier : `<chemin-projet>/build/web/`

5. L'extension apparaît dans la liste avec son icône

6. Épingler l'extension dans la barre Chrome :
   - Cliquer l'icône puzzle (extensions) dans Chrome
   - Trouver "AironBot" → cliquer l'épingle

### Vérifier que ça Fonctionne

```
✅ L'icône AironBot apparaît dans la barre Chrome
✅ Clic sur l'icône → popup s'ouvre (420×600)
✅ Console (F12 → Service Worker) → pas d'erreurs
✅ Raccourci Ctrl+Shift+S → Side Panel s'ouvre
✅ Clic droit sur texte sélectionné → "Analyser avec AironBot" visible
```

---

## Étape 6 — Développement avec Rechargement Rapide

En développement, pour voir les changements sans rebuilder tout à chaque fois :

```bash
# Terminal 1 : build web en mode watch (si disponible)
flutter build web --web-renderer canvaskit \
  --dart-define=PLATFORM=chrome_extension

# Alternativement : flutter run -d chrome pour dev rapide
flutter run -d chrome --web-port 5000
# NB : flutter run -d chrome ne charge pas le manifest extension
#      Pour tester les fonctionnalités extension, utiliser le build complet
```

### Rechargement de l'Extension après Build

```bash
# Script de rebuild rapide
./scripts/build_extension.sh

# Dans chrome://extensions :
# Cliquer l'icône ↺ (Recharger) sur la carte AironBot
# OU utiliser le raccourci clavier sur la page extensions
```

---

## Étape 7 — Déboguer l'Extension

### Console de la Popup

```
Clic droit sur l'icône AironBot → "Inspecter l'élément popup"
→ DevTools s'ouvre → onglet Console
```

### Console du Service Worker (background.js)

```
chrome://extensions → AironBot → "Service Worker" (lien)
→ DevTools du Service Worker
```

### Console du Content Script

```
F12 sur n'importe quelle page → Console
→ Chercher les messages préfixés "[AironBot CS]"
```

### Logs Firebase dans Extension

```dart
// Activer les logs debug Firebase
await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
FirebaseFirestore.instance.settings = const Settings(
  persistenceEnabled: true,
  cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED,
);
```

---

## Étape 8 — Tester les Fonctionnalités Clés

### Checklist de Test Complète

```
[ ] Auth
    [ ] Connexion Google → popup OAuth s'ouvre dans nouvel onglet
    [ ] Connexion email/mdp
    [ ] Déconnexion → état UI reset

[ ] Chat
    [ ] Envoyer un message → réponse en streaming
    [ ] Historique chargé au démarrage
    [ ] Scroll to bottom sur nouvelle réponse

[ ] Voix
    [ ] Bouton micro → demande permission navigateur
    [ ] Reconnaissance vocale → texte dans input
    [ ] TTS → réponse lue à voix haute

[ ] Texte de Page
    [ ] Sélectionner texte → context menu visible
    [ ] "Analyser avec AironBot" → side panel avec texte pré-rempli

[ ] Sync
    [ ] Créer conv dans extension → visible dans app mobile (Firestore)
    [ ] Modifier conv dans app → mise à jour extension (realtime)

[ ] Quotas
    [ ] Gratuit : compteur affiché
    [ ] À 20 req → modal upsell ou rewarded

[ ] Pro
    [ ] Bouton upgrade → ouverture page Stripe dans onglet
    [ ] Après paiement → plan "Pro" affiché sans rechargement

[ ] Performances
    [ ] Popup s'ouvre en < 1 seconde
    [ ] Aucune erreur dans la console Chrome
    [ ] Pas de fuite mémoire (tester DevTools Memory)
```

---

## Étape 9 — Créer le ZIP pour le Chrome Web Store

```bash
./scripts/build_extension.sh
# Génère : airon_bot_extension_YYYYMMDD_HHMMSS.zip
```

### Vérifier le Contenu du ZIP

```bash
unzip -l airon_bot_extension_*.zip | head -30
# Vérifier la présence de :
# - manifest.json
# - index.html
# - main.dart.js
# - background.js
# - icons/icon-128.png
```

### Taille Limite

Le ZIP doit faire **moins de 128 Mo**. Vérifier :

```bash
du -sh airon_bot_extension_*.zip
```

Si trop lourd :

```bash
# Optimiser le build Flutter Web
flutter build web \
  --web-renderer canvaskit \
  --release \
  --pwa-strategy none \
  --no-tree-shake-icons
```

---

## Étape 10 — Publier sur le Chrome Web Store

### 10.1 Préparer les Assets Marketing

| Asset | Dimensions | Format |
|---|---|---|
| Icône | 128×128 px | PNG |
| Screenshot | 1280×800 ou 640×400 | PNG/JPG (min 1, max 5) |
| Image promo petite | 440×280 px | PNG/JPG |
| Image promo grande | 920×680 px | PNG/JPG (optionnel) |
| Vidéo | YouTube URL | Optionnel |

### 10.2 Publication Manuelle

1. Aller sur [chrome.google.com/webstore/devconsole](https://chrome.google.com/webstore/devconsole)
2. Cliquer **"Nouvel article"**
3. Uploader le ZIP
4. Remplir les métadonnées :
   - **Nom** : "AironBot — AI Chat Assistant"
   - **Description courte** (132 chars max) : "Assistant IA gratuit basé sur DeepSeek. Chat, résumé, traduction dans Chrome."
   - **Description longue** : Copier depuis README.md
5. Uploader les screenshots et icônes
6. Remplir la politique de confidentialité (URL requise)
7. Déclarer les permissions justifiées
8. Soumettre pour review (2-7 jours ouvrés)

### 10.3 Publication Automatisée (CI/CD)

Obtenir les credentials OAuth Chrome Web Store :

```bash
# 1. Créer un projet Google Cloud
# 2. Activer Chrome Web Store API
# 3. Créer credentials OAuth 2.0 → Application Bureau
# 4. Obtenir refresh_token via :
npx chrome-webstore-upload-cli login \
  --client-id YOUR_CLIENT_ID \
  --client-secret YOUR_CLIENT_SECRET
# → Ouvre navigateur → Autoriser → Copier le refresh_token
```

Stocker dans GitHub Secrets :
- `EXTENSION_ID` — ID de l'extension (dans l'URL du store)
- `CHROME_OAUTH_CLIENT_ID`
- `CHROME_OAUTH_CLIENT_SECRET`
- `CHROME_OAUTH_REFRESH_TOKEN`

Le workflow `.github/workflows/extension.yml` gère le reste automatiquement.

---

## Mises à Jour de l'Extension

### Version Bump

```bash
# android/build.gradle, ios/Runner/Info.plist, pubspec.yaml, web/manifest.json
# Mettre à jour "version" partout
# Convention : 1.0.0 → 1.0.1 (patch), 1.1.0 (feature), 2.0.0 (majeur)
```

### Déploiement Mise à Jour

```bash
# Créer un tag Git pour déclencher le CI/CD
git tag v1.0.1
git push origin v1.0.1
# Le workflow GitHub Actions build + upload + publie automatiquement
```

Les utilisateurs reçoivent la mise à jour automatiquement sous 1-24 h.

---

## Dépannage Courant

| Problème | Cause | Solution |
|---|---|---|
| Popup blanc au chargement | Build Flutter pas copié | Relancer `./scripts/build_extension.sh` |
| `Refused to load script` | CSP manquante dans manifest | Vérifier `content_security_policy` |
| Firebase Auth échoue | `chrome-extension://` non autorisé dans Firebase | Ajouter `chrome-extension://EXTENSION_ID` dans Authorized domains Firebase |
| `chrome.storage is not defined` | `chrome` namespace non disponible dans Flutter web | Utiliser JS interop + vérifier `host_permissions` |
| Extension non visible dans chrome://extensions | Dossier build invalide | Vérifier que `manifest.json` est au niveau racine de `build/web/` |
| Service Worker crash | Erreur JS dans background.js | Ouvrir DevTools SW dans chrome://extensions → réparer |
| Taille popup incorrecte | CSS Flutter override | Ajouter `body { width: 420px; height: 600px; }` dans `web/index.html` |
| Quota Firebase dépassé | Trop de listeners Firestore | Utiliser `onSnapshot` une seule fois + unsubscribe au démontage |

### Erreur : Domaine Non Autorisé Firebase Auth

Dans Firebase Console → Authentication → Settings → Authorized domains :

```
Ajouter : chrome-extension://VOTRE_EXTENSION_ID
```

Récupérer l'ID de l'extension : `chrome://extensions` → ID sous le nom de l'extension.

---

## Variables GitHub Secrets Requises pour CI/CD Extension

```
DEEPSEEK_API_KEY           → Clé DeepSeek V3
FIREBASE_PROJECT_ID        → ID projet Firebase
EXTENSION_ID               → ID Chrome Web Store
CHROME_OAUTH_CLIENT_ID     → OAuth Client ID
CHROME_OAUTH_CLIENT_SECRET → OAuth Client Secret
CHROME_OAUTH_REFRESH_TOKEN → Refresh token obtenu via CLI
```
