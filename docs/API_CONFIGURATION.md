# API Configuration Guide — Corely

Ce document liste toutes les clés API requises par le projet, leur source, et comment les injecter dans l'environnement.

---

## Table des matières

1. [Clés IA](#clés-ia)
2. [Clés Publicité (AdMob)](#clés-admob)
3. [Clés Monetisation (RevenueCat + Stripe)](#clés-monetisation)
4. [Clés Recherche (SerpAPI + OpenWeatherMap)](#clés-recherche)
5. [Injection dans l'environnement](#injection)
6. [Fichier `.env` de référence](#fichier-env)

---

## Clés IA

### DEEPSEEK_API_KEY
- **Usage** : Tier gratuit, modèle `deepseek-v4-flash` (texte) et `deepseek-chat` (vision)
- **Où créer** : [platform.deepseek.com](https://platform.deepseek.com) → API Keys → Create
- **Coût** : Gratuit avec rate limits (environ 1 req/sec, burst limit)
- **Injection local** :
  ```bash
  echo "DEEPSEEK_API_KEY=sk-xxx" >> .env
  ```
- **Injection build extension** :
  ```bash
  flutter build web --dart-define=DEEPSEEK_API_KEY=sk-xxx
  ```

### OPENROUTER_API_KEY
- **Usage** : Tier Pro, modèles Mistral-Large, GPT-4o-mini, TTS gpt-4o-mini-tts
- **Où créer** : [openrouter.ai/keys](https://openrouter.ai/keys)
- **Coût** : Pay-as-you-go, crédits OpenRouter
- **Injection local** :
  ```bash
  echo "OPENROUTER_API_KEY=sk-or-xxx" >> .env
  ```
- **Headers obligatoires** : `HTTP-Referer`, `X-Title` (déjà dans `ai_client.dart`)

### OLLAMA_API_KEY
- **Usage** : Fallback vision local (mobile uniquement)
- **Où créer** : Local — [ollama.ai/download](https://ollama.ai/download)
- **Coût** : Gratuit (modèle local)
- **Injection local** :
  ```bash
  echo "OLLAMA_API_KEY=" >> .env  # Optionnel, Ollama n'a pas de clé par défaut
  ```

---

## Clés AdMob

### Android
- **ADMOB_APP_ID_ANDROID** : ID d'application (format `ca-app-pub-XXXXXXXX~XXXXXXXXXX`)
- **ADMOB_BANNER_ID_ANDROID** : ID unité bannière
- **ADMOB_INTERSTITIAL_ID_ANDROID** : ID unité interstitiel
- **ADMOB_REWARDED_ID_ANDROID** : ID unité récompensé

### iOS
- **ADMOB_APP_ID_IOS** : ID d'application iOS
- **ADMOB_BANNER_ID_IOS** : ID unité bannière iOS
- **ADMOB_INTERSTITIAL_ID_IOS** : ID unité interstitiel iOS
- **ADMOB_REWARDED_ID_IOS** : ID unité récompensé iOS

- **Où créer** : [admob.google.com](https://admob.google.com) → Apps → Add app
- **IDs de test** (en dev) :
  ```
  Banner Android     : ca-app-pub-3940256099942544/6300978111
  Rewarded Android   : ca-app-pub-3940256099942544/5224354917
  Banner iOS         : ca-app-pub-3940256099942544/2934735716
  Rewarded iOS       : ca-app-pub-3940256099942544/1712485313
  ```
- **Injection** : via `.env` uniquement (mobile). Pas nécessaire pour extension web.

---

## Clés Monetisation

### REVENUECAT_API_KEY_ANDROID
- **Usage** : Abonnements Pro sur Android (via Google Play Billing)
- **Où créer** : [app.revenuecat.com](https://app.revenuecat.com) → Projects → API Keys
- **Format** : `goog_xxxxxxxxxxxxxxxxxxxx`

### REVENUECAT_API_KEY_IOS
- **Usage** : Abonnements Pro sur iOS (via StoreKit)
- **Où créer** : Même console RevenueCat
- **Format** : `appl_xxxxxxxxxxxxxxxxxxxx`

### STRIPE_PUBLIC_KEY
- **Usage** : Paiements web/extension Chrome
- **Où créer** : [dashboard.stripe.com/apikeys](https://dashboard.stripe.com/apikeys)
- **Format** : `pk_live_xxxx` ou `pk_test_xxxx`

### STRIPE_WEBHOOK_SECRET
- **Usage** : Validation des événements Stripe côté backend cloud
- **Où créer** : Stripe Dashboard → Developers → Webhooks
- **Format** : `whsec_xxxx`
- **Note** : Requis uniquement pour le backend FastAPI (`backend/`)

---

## Clés Recherche

### SERPAPI_API_KEY (optionnel mais recommandé)
- **Usage** : Résultats structurés vols/hôtels/produits (EnhancedSearchService)
- **Où créer** : [serpapi.com/manage-api-key](https://serpapi.com/manage-api-key)
- **Coût** : 100 requêtes gratuites/mois, puis plans payants
- **Sans clé** : Fallback automatique vers liens directs comparateurs (DuckDuckGo scraping pour recherche générale)
- **Injection** :
  ```bash
  echo "SERPAPI_API_KEY=xxx" >> .env
  ```

### OPENWEATHERMAP_API_KEY (optionnel)
- **Usage** : Prévisions météo précises (WeatherService)
- **Où créer** : [home.openweathermap.org/api_keys](https://home.openweathermap.org/api_keys)
- **Coût** : 1000 appels/jour gratuits
- **Sans clé** : Recherche web générale comme fallback
- **Injection** :
  ```bash
  echo "OPENWEATHERMAP_API_KEY=xxx" >> .env
  ```

---

## Injection dans l'environnement

### Local Development

1. Copier le template :
   ```bash
   cp .env.example .env
   ```

2. Éditer `.env` avec les clés

3. Le fichier `.env` est dans `.gitignore` (ne JAMAIS le committer)

### Chrome Extension Build

Les clés sont compilées dans le JS via `--dart-define` :

```bash
flutter build web \
  --dart-define=DEEPSEEK_API_KEY=sk-xxx \
  --dart-define=OPENROUTER_API_KEY=sk-or-xxx \
  --dart-define=SERPAPI_API_KEY=xxx \
  --pwa-strategy=none
```

### CI/CD / Docker

```bash
# Dockerfile
ARG DEEPSEEK_API_KEY
ARG OPENROUTER_API_KEY
ENV DEEPSEEK_API_KEY=${DEEPSEEK_API_KEY}
ENV OPENROUTER_API_KEY=${OPENROUTER_API_KEY}
```

### Firebase / Cloud Functions

Les clés API backend sont stockées dans les **Firebase Environment Variables** :

```bash
firebase functions:config:set deepseek.key="sk-xxx" openrouter.key="sk-or-xxx"
```

---

## Fichier `.env` de Référence

```bash
# === IA ===
DEEPSEEK_API_KEY=sk-xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
OPENROUTER_API_KEY=sk-or-xxxxxxxxxxxxxxxxxxxxxxxxxx
OLLAMA_API_KEY=

# === AdMob ===
ADMOB_APP_ID_ANDROID=ca-app-pub-XXXXXX~XXXXXXXX
ADMOB_APP_ID_IOS=ca-app-pub-XXXXXX~XXXXXXXX
ADMOB_BANNER_ID_ANDROID=ca-app-pub-XXXXXX/XXXXXXXXXX
ADMOB_BANNER_ID_IOS=ca-app-pub-XXXXXX/XXXXXXXXXX
ADMOB_INTERSTITIAL_ID_ANDROID=ca-app-pub-XXXXXX/XXXXXXXXXX
ADMOB_INTERSTITIAL_ID_IOS=ca-app-pub-XXXXXX/XXXXXXXXXX
ADMOB_REWARDED_ID_ANDROID=ca-app-pub-XXXXXX/XXXXXXXXXX
ADMOB_REWARDED_ID_IOS=ca-app-pub-XXXXXX/XXXXXXXXXX

# === RevenueCat ===
REVENUECAT_API_KEY_ANDROID=goog_xxxxxxxxxxxxxxxxxxxx
REVENUECAT_API_KEY_IOS=appl_xxxxxxxxxxxxxxxxxxxx

# === Stripe (Web/Extension) ===
STRIPE_PUBLIC_KEY=pk_live_xxxx
STRIPE_WEBHOOK_SECRET=whsec_xxxx

# === Recherche (optionnel) ===
SERPAPI_API_KEY=xxx
OPENWEATHERMAP_API_KEY=xxx

# === Environnement ===
APP_ENV=development
```

---

## Vérification

Pour vérifier que les clés sont bien lues par l'application :

```dart
// Dans un test ou du code temporaire
import 'package:flutter_dotenv/flutter_dotenv.dart';

void checkKeys() {
  assert(dotenv.env['DEEPSEEK_API_KEY']?.isNotEmpty == true, 'DEEPSEEK_API_KEY manquante');
  assert(dotenv.env['OPENROUTER_API_KEY']?.isNotEmpty == true, 'OPENROUTER_API_KEY manquante');
  print('Toutes les clés obligatoires sont présentes');
}
```

---

*Document généré le 2026-05-21 — Session V12*
