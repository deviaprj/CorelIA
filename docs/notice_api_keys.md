# Notice API Keys — Corely

## Introduction

Ce document recense **toutes les clés API, identifiants et comptes tiers** nécessaires au fonctionnement de **Corely** en production. Il détaille pour chaque service :

- Le rôle dans l'application
- Comment créer le compte
- Comment récupérer la clé API
- Comment valider le compte et la clé
- Comment l'intégrer au projet

> **Conseil** : Commencez par les clés marquées **Critique** (sans elles, l'app ne fonctionne pas). Les clés **Recommandé** et **Optionnel** peuvent être ajoutées ensuite.

---

## Table des matières

1. [Intelligence Artificielle (IA)](#1-intelligence-artificielle-ia)
2. [Recherche Web & Météo](#2-recherche-web--meteo)
3. [Monétisation Mobile](#3-monetisation-mobile)
4. [Abonnements Premium](#4-abonnements-premium)
5. [Paiements Web (Extension)](#5-paiements-web-extension)
6. [Firebase (Backend & Auth)](#6-firebase-backend--auth)
7. [Infrastructure Backend](#7-infrastructure-backend)
8. [Récapitulatif & Fichier .env](#8-recapitulatif--fichier-env)

---

## 1. Intelligence Artificielle (IA)

### 1.1 DeepSeek API — **Critique**

**Rôle** : Fournit le modèle de langage par défaut (`deepseek-v4-flash`) pour les utilisateurs gratuits. Gère le texte, le raisonnement et la vision (via `deepseek-chat`).

**Créer le compte**

1. Rendez-vous sur [https://platform.deepseek.com](https://platform.deepseek.com)
2. Cliquez sur **Sign Up** et créez un compte (email ou Google/GitHub)
3. Validez votre email via le lien reçu

**Récupérer la clé API**

1. Connectez-vous à [https://platform.deepseek.com](https://platform.deepseek.com)
2. Allez dans **API Keys** (menu en haut à droite)
3. Cliquez sur **Create API Key**
4. Nommez-la `Corely-Production` et copiez la clé (commence par `sk-`)

**Valider la clé**

```bash
curl -X POST https://api.deepseek.com/v1/chat/completions \
  -H "Authorization: Bearer sk-VOTRE_CLE" \
  -H "Content-Type: application/json" \
  -d '{"model":"deepseek-v4-flash","messages":[{"role":"user","content":"Hello"}]}'
```

Vous devez recevoir une réponse JSON avec `choices[0].message.content`.

**Intégration**

```bash
# .env (racine du projet Flutter)
DEEPSEEK_API_KEY=sk-votre_cle_ici
```

> Pour l'extension Chrome, la clé doit être compilée via `--dart-define=DEEPSEEK_API_KEY=sk-xxx` car l'extension ne peut pas lire `.env` à l'exécution.

---

### 1.2 OpenRouter API — **Recommandé**

**Rôle** : Fournit des modèles premium pour les utilisateurs Pro (Mistral-Large, GPT-4o-mini) et le TTS vocal haute qualité (`gpt-4o-mini-tts`). Fallback si DeepSeek est saturé.

**Créer le compte**

1. Rendez-vous sur [https://openrouter.ai](https://openrouter.ai)
2. Cliquez sur **Sign Up** (compte gratuit avec crédits initiaux)
3. Ajoutez un moyen de paiement si vous prévoyez un usage Pro

**Récupérer la clé API**

1. Allez dans **Settings** → **Keys**
2. Cliquez sur **Create Key**
3. Nommez-la `Corely-Production`
4. Copiez la clé (commence par `sk-or-v1-`)

**Valider la clé**

```bash
curl https://openrouter.ai/api/v1/models \
  -H "Authorization: Bearer sk-or-v1-VOTRE_CLE"
```

Vous devez recevoir une liste de modèles disponibles.

**Intégration**

```bash
# .env
OPENROUTER_API_KEY=sk-or-v1-votre_cle_ici
```

---

## 2. Recherche Web & Météo

### 2.1 SerpAPI — **Recommandé**

**Rôle** : Permet la recherche enrichie (Google Shopping, Google Hotels, Google Flights, événements, restaurants) avec des résultats structurés. Fallback sur DuckDuckGo scraping si non configuré.

**Créer le compte**

1. Rendez-vous sur [https://serpapi.com](https://serpapi.com)
2. Inscrivez-vous avec un email
3. Validez votre compte via l'email de confirmation
4. Vous recevez **100 requêtes gratuites/mois**

**Récupérer la clé API**

1. Allez dans **Your Account** → **API Key**
2. Copiez la clé affichée (hash alphanumérique)

**Valider la clé**

```bash
curl "https://serpapi.com/search?q=corely&engine=google&api_key=VOTRE_CLE"
```

**Intégration**

```bash
# .env (Flutter)
SERPAPI_API_KEY=votre_cle_ici

# backend/.env (FastAPI)
SERPAPI_KEY=votre_cle_ici
```

> **Note** : La variable s'appelle `SERPAPI_API_KEY` côté Flutter et `SERPAPI_KEY` côté backend.

---

### 2.2 OpenWeatherMap — **Optionnel**

**Rôle** : Fournit les prévisions météo détaillées (5 jours, 3h) avec icônes et données structurées. Fallback sur recherche web générique si non configuré.

**Créer le compte**

1. Rendez-vous sur [https://openweathermap.org](https://openweathermap.org)
2. Cliquez sur **Sign Up**
3. Validez votre email

**Récupérer la clé API**

1. Connectez-vous et allez dans **API Keys** (menu API)
2. La clé par défaut est affichée (32 caractères hexadécimaux)
3. Vous pouvez en générer une nouvelle nommée `corely`

**Valider la clé**

```bash
curl "https://api.openweathermap.org/data/2.5/weather?q=Paris&appid=VOTRE_CLE&units=metric"
```

**Intégration**

```bash
# .env (Flutter)
OPENWEATHERMAP_API_KEY=votre_cle_ici
```

---

## 3. Monétisation Mobile

### 3.1 Google AdMob — **Critique (si monétisation par pubs)**

**Rôle** : Affiche les bannières, interstitiels et vidéos récompensées sur Android et iOS. Génère du revenu sur l'offre gratuite.

**Créer le compte**

1. Rendez-vous sur [https://admob.google.com](https://admob.google.com)
2. Connectez-vous avec votre compte Google
3. Acceptez les conditions d'utilisation
4. Liez votre compte à un compte **Google AdSense** (obligatoire)

**Créer l'application et récupérer les IDs**

1. Dans AdMob, allez dans **Apps** → **Add App**
2. Sélectionnez **Android** puis **iOS** (créez deux apps séparées)
3. Nommez-les `Corely`
4. Une fois créées, récupérez les **App IDs** :
   - Format Android : `ca-app-pub-XXXXXXXX~XXXXXXXX`
   - Format iOS : `ca-app-pub-XXXXXXXX~XXXXXXXX`

**Créer les unités publicitaires**

Pour chaque plateforme, créez :

1. **Banner** : `Add Ad Unit` → Banner → Nommez `corely_banner`
2. **Interstitial** : `Add Ad Unit` → Interstitial → Nommez `corely_interstitial`
3. **Rewarded** : `Add Ad Unit` → Rewarded → Nommez `corely_rewarded`

Copiez les IDs d'unité (format `ca-app-pub-XXXX/XXXXXXXXXX`).

**Valider les IDs**

En mode debug, les IDs de test AdMob sont automatiquement utilisés (voir `.env.example`). Pour tester en production :

```bash
# Ajoutez votre device comme test device dans AdMob
# Settings → Test Devices → Add Test Device (récupérez l'ID depuis les logs Android/iOS)
```

**Intégration**

```bash
# .env
ADMOB_APP_ID_ANDROID=ca-app-pub-XXXXXXXX~XXXXXXXX
ADMOB_APP_ID_IOS=ca-app-pub-XXXXXXXX~XXXXXXXX
ADMOB_BANNER_ID_ANDROID=ca-app-pub-XXXX/XXXXXXXXXX
ADMOB_BANNER_ID_IOS=ca-app-pub-XXXX/XXXXXXXXXX
ADMOB_INTERSTITIAL_ID_ANDROID=ca-app-pub-XXXX/XXXXXXXXXX
ADMOB_INTERSTITIAL_ID_IOS=ca-app-pub-XXXX/XXXXXXXXXX
ADMOB_REWARDED_ID_ANDROID=ca-app-pub-XXXX/XXXXXXXXXX
ADMOB_REWARDED_ID_IOS=ca-app-pub-XXXX/XXXXXXXXXX
```

> **Important** : Sur Android, l'App ID doit aussi être ajouté dans `android/app/src/main/AndroidManifest.xml` :
> ```xml
> <meta-data android:name="com.google.android.gms.ads.APPLICATION_ID"
>            android:value="ca-app-pub-XXXXXXXX~XXXXXXXX"/>
> ```

---

## 4. Abonnements Premium

### 4.1 RevenueCat — **Recommandé (si abonnements)**

**Rôle** : Gère les abonnements Pro (in-app purchases) sur iOS (App Store) et Android (Google Play) avec un SDK unifié.

**Créer le compte**

1. Rendez-vous sur [https://www.revenuecat.com](https://www.revenuecat.com)
2. Inscrivez-vous avec un email
3. Créez une organisation et un projet nommé `Corely`

**Récupérer les clés API**

1. Dans RevenueCat, allez dans **Project Settings** → **API Keys**
2. Vous trouverez deux clés :
   - **Android** : commence par `goog_`
   - **iOS** : commence par `appl_`
3. Copiez-les toutes les deux

**Configurer les stores**

- **Google Play** : liez votre app RevenueCat à la console Play (clé de service JSON)
- **App Store** : liez votre app via l'App Store Connect Shared Secret

Ces étapes sont documentées dans le guide RevenueCat et sont nécessaires pour que les achats fonctionnent.

**Valider**

Testez un achat en sandbox sur un device réel. RevenueCat affiche les transactions dans le dashboard **Customers**.

**Intégration**

```bash
# .env
REVENUECAT_API_KEY_ANDROID=goog_xxxxxxxxxxxxxxxxxxxx
REVENUECAT_API_KEY_IOS=appl_xxxxxxxxxxxxxxxxxxxx
```

---

## 5. Paiements Web (Extension)

### 5.1 Stripe — **Recommandé (si paiements web)**

**Rôle** : Permet aux utilisateurs de l'extension Chrome/Web de payer l'abonnement Pro via carte bancaire.

**Créer le compte**

1. Rendez-vous sur [https://stripe.com](https://stripe.com)
2. Inscrivez-vous avec un email
3. Activez votre compte en complétant les informations professionnelles (KYC)

**Récupérer les clés**

1. Allez dans **Developers** → **API Keys**
2. Basculez en mode **Live** (en haut à droite)
3. Copiez :
   - **Publishable key** : commence par `pk_live_`
   - **Secret key** : commence par `sk_live_` (à stocker côté backend uniquement)
   - **Webhook secret** : dans **Webhooks** → **Add endpoint** → URL de votre backend (`https://api.zentic.fr/webhook`) → copiez le secret `whsec_`

**Valider**

```bash
curl https://api.stripe.com/v1/charges \
  -u sk_live_VOTRE_CLE:
```

Vous devez recevoir une liste (vide si pas encore de transactions).

**Intégration**

```bash
# .env (Flutter — clé publique uniquement)
STRIPE_PUBLIC_KEY=pk_live_xxxxxxxx

# backend/.env (clé secrète + webhook)
STRIPE_SECRET_KEY=sk_live_xxxxxxxx
STRIPE_WEBHOOK_SECRET=whsec_xxxxxxxx
```

> **Sécurité** : La clé secrète (`sk_live_`) ne doit **JAMAIS** être dans le code client. Elle reste côté backend uniquement.

---

## 6. Firebase (Backend & Auth)

### 6.1 Firebase Project — **Critique**

**Rôle** : Authentication (Email, Google, Apple), Firestore (base de données), Cloud Messaging (push), Analytics, et Hosting optionnel.

**Créer le compte**

1. Rendez-vous sur [https://console.firebase.google.com](https://console.firebase.google.com)
2. Connectez-vous avec votre compte Google
3. Cliquez sur **Create Project** → Nommez `corely-prod`
4. Acceptez les conditions et créez

**Configurer les applications**

Dans le projet Firebase :

1. **Android** :
   - Cliquez sur l'icône Android
   - Package name : `com.corelia.corely` (ou votre package)
   - Téléchargez `google-services.json` → placez-le dans `android/app/`

2. **iOS** :
   - Cliquez sur l'icône Apple
   - Bundle ID : `com.corelia.corely`
   - Téléchargez `GoogleService-Info.plist` → placez-le dans `ios/Runner/` via Xcode

3. **Web** :
   - Cliquez sur l'icône Web
   - Nommez l'app `Corely Web`
   - Copiez la configuration Firebase (sera utilisée pour `firebase_options.dart`)

**Générer le fichier `firebase_options.dart`**

```bash
# Installez FlutterFire CLI
npm install -g firebase-tools
dart pub global activate flutterfire_cli

# Connectez-vous
firebase login

# Générez le fichier
flutterfire configure --project=corely-prod --out=lib/firebase_options.dart
```

Ce fichier remplace le stub actuel et contient les vrais `apiKey`, `appId`, `projectId`, etc.

**Valider**

Lancez l'app en debug. Si Firebase s'initialise sans erreur dans les logs (`Firebase initialized successfully`), la configuration est correcte.

**Intégration**

Aucune variable `.env` nécessaire — tout est compilé dans `firebase_options.dart` et `google-services.json`.

---

## 7. Infrastructure Backend

### 7.1 Backend URL — **Optionnel**

**Rôle** : Le backend FastAPI déployé sur un serveur cloud (ex: `api.zentic.fr`). Fournit le scraping intelligent, le téléchargement média, le crawling, et la recherche avancée. L'APK et l'extension fonctionnent **100% hors-ligne** sans backend, mais certaines fonctionnalités avancées nécessitent ce endpoint.

**Créer le serveur**

1. Louez un VPS (Hetzner, DigitalOcean, AWS Lightsail) ou utilisez un PaaS (Railway, Render, Fly.io)
2. Déployez le backend Dockerisé : `bash scripts/deploy_backend.sh`
3. Assurez-vous d'avoir un nom de domaine pointant vers le serveur

**Récupérer l'URL**

Une fois déployé, l'URL sera par exemple :
```
https://api.zentic.fr
```

**Valider**

```bash
curl https://api.zentic.fr/health
```

Doit retourner `{"status": "ok"}`.

**Intégration**

```bash
# .env
BACKEND_URL=https://api.zentic.fr
```

---

### 7.2 Redis — **Optionnel (backend)**

**Rôle** : Rate limiting et cache distribué côté backend.

**Créer l'instance**

1. Inscrivez-vous sur [https://upstash.com](https://upstash.com) (Redis serverless gratuit)
2. Créez une base de données
3. Copiez l'URL Redis (format `rediss://default:password@host:port`)

**Intégration**

```bash
# backend/.env
REDIS_URL=rediss://default:xxx@host:6379
```

---

### 7.3 Ollama (Local / Cloud) — **Optionnel**

**Rôle** : Modèles locaux pour le STT (Whisper) et TTS (Piper). Nécessite un serveur Ollama local ou cloud.

**Installation locale**

```bash
# macOS/Linux
curl -fsSL https://ollama.com/install.sh | sh
ollama pull whisper
ollama pull piper
```

**Cloud**

Si vous avez un serveur Ollama distant, récupérez son URL et sa clé API.

**Intégration**

```bash
# backend/.env
OLLAMA_CLOUD_URL=https://ollama.votre-domaine.com
OLLAMA_CLOUD_API_KEY=votre_cle_ollama
OLLAMA_STT_MODEL=whisper
OLLAMA_TTS_MODEL=piper
```

---

## 8. Récapitulatif & Fichier .env

### 8.1 Récapitulatif des comptes

| Service | Priorité | Clé(s) | Coût estimé |
|---|---|---|---|
| DeepSeek API | Critique | `DEEPSEEK_API_KEY` | Gratuit (crédits limités) |
| OpenRouter API | Recommandé | `OPENROUTER_API_KEY` | Pay-as-you-go (crédits gratuits initiaux) |
| Google AdMob | Critique (pubs) | 8 IDs AdMob | Gratuit (revenu) |
| RevenueCat | Recommandé (subs) | 2 clés API | Gratuit jusqu'à $2.5k/mois |
| Stripe | Recommandé (web) | `pk_live_` + `sk_live_` | 1.5% + 0.25€/trans. |
| Firebase | Critique | Config compilée | Gratuit (limite généreuse) |
| SerpAPI | Recommandé | `SERPAPI_API_KEY` | 100 requêtes/mois gratuits |
| OpenWeatherMap | Optionnel | `OPENWEATHERMAP_API_KEY` | Gratuit (1M appels/mois) |
| Backend URL | Optionnel | `BACKEND_URL` | Dépend du provider |
| Redis | Optionnel | `REDIS_URL` | Gratuit (Upstash) |
| Ollama | Optionnel | `OLLAMA_*` | Gratuit (auto-hébergé) |

### 8.2 Fichier `.env.example`

Un fichier `.env.example` prêt à l'emploi est fourni dans le dossier `docs/`. Copiez-le en `.env` à la racine du projet et remplissez les valeurs.

### 8.3 Compilation avec `--dart-define` (Extension Chrome)

L'extension Chrome ne peut pas lire `.env` à l'exécution. Les clés doivent être compilées dans le binaire :

```bash
flutter build web \
  --dart-define=DEEPSEEK_API_KEY=sk-xxx \
  --dart-define=OPENROUTER_API_KEY=sk-or-v1-xxx \
  --dart-define=SERPAPI_API_KEY=xxx \
  --dart-define=OPENWEATHERMAP_API_KEY=xxx
```

Ou utilisez le script de build extension :

```bash
bash scripts/build_extension.sh \
  --deepseek sk-xxx \
  --openrouter sk-or-v1-xxx
```

### 8.4 Sécurité

- **Ne commitez JAMAIS `.env`** dans Git (il est déjà dans `.gitignore`)
- **Ne partagez jamais** les clés secrètes (`sk_live_`, `sk-or-v1-`, `sk-`)
- Les clés AdMob sont publiques par nature (embarquées dans l'APK), mais ne les diffusez pas
- Utilisez des variables d'environnement CI/CD pour les builds automatisés
- Faites tourner `flutter analyze` et les tests avant tout commit contenant des changements de config

---

## Checklist de validation finale

Avant de publier en production, vérifiez :

- [ ] DeepSeek API key validée (test curl OK)
- [ ] OpenRouter API key validée (test curl OK)
- [ ] Firebase `google-services.json` présent dans `android/app/`
- [ ] Firebase `GoogleService-Info.plist` présent dans `ios/Runner/`
- [ ] `firebase_options.dart` généré via `flutterfire configure`
- [ ] AdMob App ID dans `AndroidManifest.xml`
- [ ] AdMob IDs testés sur device physique
- [ ] RevenueCat configuré avec Google Play + App Store Connect
- [ ] Stripe webhook configuré et testé
- [ ] Backend URL accessible (test `/health`)
- [ ] Fichier `.env` présent à la racine (non commité)
- [ ] Extension Chrome build avec `--dart-define`

---

*Document généré pour Corely v1.1.0 — Dernière mise à jour : 2026-05-31*
