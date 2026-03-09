# INSTALL-MOBILE.md — Guide d'Installation & Démarrage App Mobile AironBot

> Guide pas-à-pas pour installer, configurer et lancer l'application Android/iOS en développement.

---

## Prérequis Système

| Outil | Version | Installation |
|---|---|---|
| Flutter SDK | 3.24.0+ | [flutter.dev/docs/get-started/install](https://flutter.dev/docs/get-started/install) |
| Dart | 3.5.0+ | Inclus avec Flutter |
| Android Studio | Hedgehog (2023.1.1)+ | [developer.android.com/studio](https://developer.android.com/studio) |
| Xcode | 15+ *(macOS seulement)* | App Store |
| Firebase CLI | 13+ | `npm install -g firebase-tools` |
| FlutterFire CLI | latest | `dart pub global activate flutterfire_cli` |
| Node.js | 20 LTS | [nodejs.org](https://nodejs.org) |
| Git | 2.40+ | `apt install git` / `brew install git` |

---

## Étape 1 — Cloner le Projet

```bash
git clone https://github.com/votre-org/airon-bot.git
cd airon_bot
```

---

## Étape 2 — Installer les Dépendances Flutter

```bash
flutter pub get
```

Vérifier qu'il n'y a pas d'erreurs :

```bash
flutter analyze
```

> Si des warnings `very_good_analysis` apparaissent sur du code généré, c'est normal. Ignorer les warnings dans `*.g.dart`.

---

## Étape 3 — Configurer Firebase

### 3.1 Créer le Projet Firebase

1. Aller sur [console.firebase.google.com](https://console.firebase.google.com)
2. Cliquer **Ajouter un projet** → Nom : `airon-bot-prod`
3. Activer Google Analytics (recommandé)
4. Dans le projet créé, activer :
   - **Authentication** → Email/Mot de passe + Google + Apple
   - **Firestore Database** → Démarrer en mode production
   - **Storage** → Démarrer en mode production
   - **Cloud Messaging** (FCM)

### 3.2 Configurer avec FlutterFire CLI

```bash
firebase login
flutterfire configure \
  --project=airon-bot-prod \
  --platforms=android,ios,web
```

Cela génère automatiquement : `lib/core/firebase_options.dart`

### 3.3 Déployer les Règles Firestore

```bash
firebase deploy --only firestore:rules
firebase deploy --only firestore:indexes
```

### 3.4 Déployer les Cloud Functions

```bash
cd functions
npm install
npm run build
cd ..
firebase deploy --only functions
```

---

## Étape 4 — Configurer les Clés API

### 4.1 Clé API DeepSeek

1. S'inscrire sur [platform.deepseek.com](https://platform.deepseek.com)
2. Créer une clé API dans le tableau de bord
3. Copier la clé

### 4.2 Stocker la Clé (Développement)

Créer un fichier `.env` à la racine du projet (non versionné) :

```bash
cp .env.example .env
```

Éditer `.env` :

```dotenv
DEEPSEEK_API_KEY=sk-xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
OPENROUTER_API_KEY=sk-or-xxxxxxxxxxxxxxxxxxxxxxxxxx  # Pour Mistral/Groq Pro
ADMOB_APP_ID_ANDROID=ca-app-pub-XXXXXX~XXXXXXXX
ADMOB_APP_ID_IOS=ca-app-pub-XXXXXX~XXXXXXXX
REVENUECAT_API_KEY_ANDROID=goog_xxxxxxxxxxxxxxxxxxxx
REVENUECAT_API_KEY_IOS=appl_xxxxxxxxxxxxxxxxxxxx
```

> **Sécurité** : Le fichier `.env` est dans `.gitignore`. Ne jamais le committer.

### 4.3 Injecter les Clés au Build

```bash
# Android
flutter run --dart-define-from-file=.env

# Pour la production, utiliser GitHub Actions Secrets (voir CI/CD)
```

### 4.4 Configuration Android — `android/app/src/main/AndroidManifest.xml`

Ajouter l'ID AdMob :

```xml
<application>
  <!-- AdMob App ID -->
  <meta-data
    android:name="com.google.android.gms.ads.APPLICATION_ID"
    android:value="ca-app-pub-XXXXXX~XXXXXXXX"/>
  <!-- ... -->
</application>
```

### 4.5 Configuration iOS — `ios/Runner/Info.plist`

```xml
<!-- AdMob -->
<key>GADApplicationIdentifier</key>
<string>ca-app-pub-XXXXXX~XXXXXXXX</string>

<!-- Permissions voix -->
<key>NSMicrophoneUsageDescription</key>
<string>AironBot utilise le micro pour le chat vocal</string>
<key>NSSpeechRecognitionUsageDescription</key>
<string>AironBot reconnaît votre voix pour le chat</string>
```

---

## Étape 5 — Configurer les Émulateurs

### Android

```bash
# Lister les émulateurs disponibles
flutter emulators

# Créer un émulateur Pixel 8 (via Android Studio ou avdmanager)
avdmanager create avd \
  -n "Pixel_8_API_34" \
  -k "system-images;android-34;google_apis;x86_64" \
  -d "pixel_8"

# Lancer l'émulateur
flutter emulators --launch Pixel_8_API_34
```

### iOS (macOS uniquement)

```bash
# Ouvrir le Simulateur
open -a Simulator

# Changer de device dans Simulator → File → Open Simulator → iOS 17 → iPhone 15 Pro
```

### Vérifier les Appareils Détectés

```bash
flutter devices
# Doit afficher : Android emulator, iOS simulator, Chrome
```

---

## Étape 6 — Lancer l'Application

### Android

```bash
flutter run -d android
# ou avec dart-define
flutter run -d android --dart-define-from-file=.env
```

### iOS

```bash
flutter run -d ios
```

### Chrome (Test extension)

```bash
flutter run -d chrome --web-port 5000
```

### Tous les Appareils Simultanément

```bash
flutter run -d all
```

---

## Étape 7 — Build de Production

### APK Android (débogage rapide)

```bash
flutter build apk \
  --release \
  --dart-define-from-file=.env
# Sortie : build/app/outputs/flutter-apk/app-release.apk
```

### App Bundle Android (Play Store)

```bash
flutter build appbundle \
  --release \
  --dart-define-from-file=.env
# Sortie : build/app/outputs/bundle/release/app-release.aab
```

### iOS (Archive pour App Store)

```bash
flutter build ios \
  --release \
  --dart-define-from-file=.env
# Puis ouvrir Xcode → Product → Archive
```

---

## Étape 8 — Configurer RevenueCat (Abonnements)

1. Créer un compte sur [app.revenuecat.com](https://app.revenuecat.com)
2. Créer un nouveau projet "AironBot"
3. Connecter Google Play Console + App Store Connect
4. Créer les produits d'abonnement :
   - `pro_monthly` — 9,99 €/mois
   - `pro_yearly` — 99 €/an
   - `credits_50` — 2,99 € (one-time)
5. Créer une Offering "default" avec les packages ci-dessus
6. Récupérer les API Keys dans Settings → API Keys

---

## Étape 9 — Configurer AdMob

1. Créer un compte [admob.google.com](https://admob.google.com)
2. Ajouter les apps Android + iOS
3. Créer les unités publicitaires :
   - `banner_chat_top` — Banner
   - `interstitiel_session` — Interstitial
   - `rewarded_bonus_requests` — Rewarded
4. Copier les IDs dans `.env`

> **En développement** : Utiliser les IDs de test AdMob (pas de revenus, mais pas de risque de bannissement) :
> - Android Banner test : `ca-app-pub-3940256099942544/6300978111`
> - Android Rewarded test : `ca-app-pub-3940256099942544/5224354917`

---

## Étape 10 — Vérification Finale

```bash
# Analyse du code
flutter analyze --no-fatal-infos

# Tous les tests
flutter test

# Test integration (avec émulateur lancé)
flutter drive \
  --driver=test_driver/integration_driver.dart \
  --target=integration_test/app_test.dart \
  -d emulator-5554

# Vérifier couverture tests
flutter test --coverage
genhtml coverage/lcov.info -o coverage/html
open coverage/html/index.html
```

---

## Dépannage Courant

| Problème | Solution |
|---|---|
| `flutter doctor` affiche ✗ Android toolchain | Accepter licences : `flutter doctor --android-licenses` |
| Gradle build échoue | `cd android && ./gradlew clean && cd ..` |
| Firebase `google-services.json` manquant | Relancer `flutterfire configure` |
| `CocoaPods not installed` (iOS) | `sudo gem install cocoapods && pod setup` |
| Émulateur lent / freeze | Activer virtualisation BIOS + HAXM Intel ou Hyper-V |
| Hot reload ne fonctionne pas | Utiliser `r` dans le terminal, pas Ctrl+S |
| API DeepSeek 401 | Vérifier la clé dans `.env`, éviter espaces/guillemets |
| `MissingPluginException` | Arrêter l'app, `flutter clean`, `flutter pub get`, relancer |

---

## Variables d'Environnement — Référence Complète

```dotenv
# === IA ===
DEEPSEEK_API_KEY=                    # Requis - gratuit sur platform.deepseek.com
OPENROUTER_API_KEY=                  # Optionnel - pour modèles Pro (Mistral/Groq)

# === Firebase ===
FIREBASE_PROJECT_ID=airon-bot-prod   # Généré par flutterfire configure
# NB : firebase_options.dart contient déjà les autres clés Firebase

# === AdMob ===
ADMOB_APP_ID_ANDROID=               # Format : ca-app-pub-XXXXXX~XXXXXXXX
ADMOB_APP_ID_IOS=                   # Format : ca-app-pub-XXXXXX~XXXXXXXX
ADMOB_BANNER_ID_ANDROID=
ADMOB_BANNER_ID_IOS=
ADMOB_INTERSTITIAL_ID_ANDROID=
ADMOB_INTERSTITIAL_ID_IOS=
ADMOB_REWARDED_ID_ANDROID=
ADMOB_REWARDED_ID_IOS=

# === RevenueCat ===
REVENUECAT_API_KEY_ANDROID=         # Format : goog_xxxx
REVENUECAT_API_KEY_IOS=             # Format : appl_xxxx

# === Stripe (Web/Extension) ===
STRIPE_PUBLIC_KEY=pk_live_xxxx

# === Environnement ===
APP_ENV=development                  # development | staging | production
```
