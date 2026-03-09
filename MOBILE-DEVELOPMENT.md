# MOBILE-DEVELOPMENT.md — Développement App Mobile AironBot

> Guide exhaustif de développement de l'application Android/iOS Flutter.  
> Stack : Flutter 3.24 · Firebase · DeepSeek-V3 · RevenueCat · AdMob

---

## Table des Matières

1. [Environnement de Développement](#1-environnement-de-développement)
2. [Scaffold Projet Flutter](#2-scaffold-projet-flutter)
3. [Firebase Setup](#3-firebase-setup)
4. [Architecture MVVM + Riverpod](#4-architecture-mvvm--riverpod)
5. [Fonctionnalité : Authentification](#5-fonctionnalité--authentification)
6. [Fonctionnalité : Chat Texte + IA Streaming](#6-fonctionnalité--chat-texte--ia-streaming)
7. [Fonctionnalité : Chat Voix](#7-fonctionnalité--chat-voix)
8. [Fonctionnalité : Quotas & File d'attente](#8-fonctionnalité--quotas--file-dattente)
9. [Fonctionnalité : Publicités (AdMob)](#9-fonctionnalité--publicités-admob)
10. [Fonctionnalité : Abonnements Pro (RevenueCat)](#10-fonctionnalité--abonnements-pro-revenuecat)
11. [Fonctionnalité : Upload Fichiers & PDF](#11-fonctionnalité--upload-fichiers--pdf)
12. [Fonctionnalité : Projets & Dossiers (Pro)](#12-fonctionnalité--projets--dossiers-pro)
13. [Synchronisation App ↔ Extension](#13-synchronisation-app--extension)
14. [Onboarding & Viral Features](#14-onboarding--viral-features)
15. [Tests (Unit / Widget / Integration)](#15-tests-unit--widget--integration)
16. [CI/CD — GitHub Actions + Fastlane](#16-cicd--github-actions--fastlane)
17. [Liste Exhaustive des Fonctions](#17-liste-exhaustive-des-fonctions)

---

## 1. Environnement de Développement

### Prérequis

| Outil | Version minimale | Commande de vérification |
|---|---|---|
| Flutter SDK | 3.24.0+ | `flutter --version` |
| Dart SDK | 3.5.0+ | `dart --version` |
| Android Studio | Hedgehog+ | `studio.sh --version` |
| Xcode | 15+ (macOS requis iOS) | `xcode-select --version` |
| Firebase CLI | 13+ | `firebase --version` |
| Node.js | 20 LTS | `node --version` |
| FlutterFire CLI | latest | `flutterfire --version` |

```bash
# Installation Flutter
git clone https://github.com/flutter/flutter.git -b stable
export PATH="$PATH:$PWD/flutter/bin"
flutter doctor -v   # Vérifier que tout est vert

# Firebase CLI
npm install -g firebase-tools
firebase login

# FlutterFire CLI
dart pub global activate flutterfire_cli
```

### Émulateurs Recommandés

```bash
# Android — créer AVD via Android Studio ou SDK Manager
flutter emulators --launch Pixel_8_API_34

# iOS (macOS uniquement)
open -a Simulator

# Chrome (extension dev)
flutter run -d chrome --web-port 5000
```

---

## 2. Scaffold Projet Flutter

```bash
flutter create airon_bot \
  --org com.aironbot \
  --platforms android,ios,web \
  --description "AI Chat App powered by DeepSeek"

cd airon_bot
```

### `pubspec.yaml` — Dépendances Complètes

```yaml
name: airon_bot
description: AI Chat App - Flutter Cross-Platform
version: 1.0.0+1

environment:
  sdk: ">=3.5.0 <4.0.0"

dependencies:
  flutter:
    sdk: flutter

  # State management
  flutter_riverpod: ^2.5.1
  riverpod_annotation: ^2.3.5

  # Firebase
  firebase_core: ^3.3.0
  firebase_auth: ^5.1.4
  cloud_firestore: ^5.2.1
  firebase_storage: ^12.1.3
  firebase_messaging: ^15.1.0
  firebase_analytics: ^11.2.1

  # Navigation
  go_router: ^13.2.2

  # HTTP / IA
  http: ^1.2.1

  # UI
  flutter_markdown: ^0.7.1
  shimmer: ^3.0.0
  cached_network_image: ^3.3.1
  lottie: ^3.1.0

  # Voix
  speech_to_text: ^6.6.2
  flutter_tts: ^4.0.2

  # Fichiers
  file_picker: ^8.0.3
  image_picker: ^1.1.2

  # PDF
  pdf: ^3.11.0
  printing: ^5.13.1

  # Sécurité
  flutter_secure_storage: ^9.2.2
  crypto: ^3.0.3

  # Monétisation
  google_mobile_ads: ^5.1.0
  purchases_flutter: ^7.4.0   # RevenueCat

  # Utilitaires
  uuid: ^4.4.2
  intl: ^0.19.0
  shared_preferences: ^2.3.2
  connectivity_plus: ^6.0.3
  package_info_plus: ^8.0.2
  share_plus: ^9.0.0

dev_dependencies:
  flutter_test:
    sdk: flutter
  build_runner: ^2.4.11
  riverpod_generator: ^2.4.3
  integration_test:
    sdk: flutter
  mockito: ^5.4.4
  very_good_analysis: ^6.0.0
  flutter_launcher_icons: ^0.13.1
```

---

## 3. Firebase Setup

### 3.1 Créer le Projet Firebase

```bash
firebase projects:create airon-bot-prod
firebase use airon-bot-prod
```

### 3.2 FlutterFire Configure

```bash
flutterfire configure \
  --project=airon-bot-prod \
  --platforms=android,ios,web
# Génère lib/core/firebase_options.dart automatiquement
```

### 3.3 Règles Firestore

```javascript
// firestore.rules
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {

    // Utilisateurs — lecture/écriture uniquement en self
    match /users/{userId} {
      allow read, write: if request.auth != null && request.auth.uid == userId;
    }

    // Conversations — owned by user
    match /conversations/{convId} {
      allow read, write: if request.auth != null 
        && resource.data.userId == request.auth.uid;
    }

    // Messages dans une conversation
    match /conversations/{convId}/messages/{msgId} {
      allow read, write: if request.auth != null
        && get(/databases/$(database)/documents/conversations/$(convId)).data.userId 
           == request.auth.uid;
    }

    // Projets (Pro uniquement)
    match /projects/{projectId} {
      allow read, write: if request.auth != null
        && resource.data.userId == request.auth.uid;
    }
  }
}
```

### 3.4 Index Firestore

```json
// firestore.indexes.json
{
  "indexes": [
    {
      "collectionGroup": "conversations",
      "queryScope": "COLLECTION",
      "fields": [
        {"fieldPath": "userId", "order": "ASCENDING"},
        {"fieldPath": "updatedAt", "order": "DESCENDING"}
      ]
    }
  ]
}
```

---

## 4. Architecture MVVM + Riverpod

```
Couche Présentation (UI)
  └── Screens & Widgets
        ↓ observe
Couche ViewModel (Notifiers Riverpod)
  └── StateNotifier / AsyncNotifier
        ↓ appelle
Couche Domaine (Use Cases / Models)
  └── Message, Conversation, User
        ↓ implémenté par
Couche Data (Repositories)
  └── Firestore, AI Client, SecureStorage
```

### Provider de base — `core/providers/`

```dart
// lib/core/providers/firebase_providers.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final firebaseAuthProvider = Provider((ref) => FirebaseAuth.instance);
final firestoreProvider = Provider((ref) => FirebaseFirestore.instance);
```

---

## 5. Fonctionnalité : Authentification

### Écrans
- `LoginScreen` : email/password + Google + Apple + mode anonyme
- `RegisterScreen` : inscription email
- `OnboardingScreen` : 3 slides → skip possible

### Repository

```dart
// lib/features/auth/data/auth_repository.dart
abstract class AuthRepository {
  Stream<User?> get authStateChanges;
  Future<void> signInWithEmail(String email, String password);
  Future<void> signInWithGoogle();
  Future<void> signInWithApple();
  Future<void> signInAnonymously();
  Future<void> signOut();
  Future<void> deleteAccount();
}
```

### Notifier

```dart
@riverpod
class AuthNotifier extends _$AuthNotifier {
  @override
  Stream<User?> build() => ref.watch(authRepositoryProvider).authStateChanges;
}
```

### Document Firestore Utilisateur (`/users/{uid}`)

```json
{
  "uid": "abc123",
  "email": "user@example.com",
  "displayName": "Alice",
  "photoURL": null,
  "plan": "free",              // "free" | "pro"
  "dailyRequests": 3,
  "dailyRequestsDate": "2026-03-09",
  "totalRequests": 47,
  "createdAt": "timestamp",
  "referralCode": "ALICE42",
  "referredBy": null
}
```

---

## 6. Fonctionnalité : Chat Texte + IA Streaming

### Client DeepSeek-V3

```dart
// lib/features/chat/data/ai_client.dart
class DeepSeekClient {
  static const _baseUrl = 'https://api.deepseek.com/v1/chat/completions';
  static const _model = 'deepseek-chat';  // deepseek-V3
  final String apiKey;

  Stream<String> streamChat({
    required List<Map<String, dynamic>> messages,
    String? systemPrompt,
    int maxTokens = 4096,
  }) async* {
    final body = {
      'model': _model,
      'max_tokens': maxTokens,
      'stream': true,
      'messages': [
        if (systemPrompt != null) {'role': 'system', 'content': systemPrompt},
        ...messages,
      ],
    };

    final request = http.Request('POST', Uri.parse(_baseUrl))
      ..headers.addAll({
        'Authorization': 'Bearer $apiKey',
        'Content-Type': 'application/json',
      })
      ..body = jsonEncode(body);

    final response = await http.Client().send(request);
    if (response.statusCode != 200) {
      final err = await response.stream.bytesToString();
      throw AiException('DeepSeek error ${response.statusCode}: $err');
    }

    await for (final line in response.stream
        .transform(utf8.decoder)
        .transform(const LineSplitter())) {
      if (!line.startsWith('data: ')) continue;
      final data = line.substring(6);
      if (data == '[DONE]') break;
      try {
        final json = jsonDecode(data) as Map<String, dynamic>;
        final content = (json['choices'] as List?)
            ?.firstOrNull?['delta']?['content'] as String?;
        if (content != null) yield content;
      } catch (_) {}
    }
  }
}
```

### Document `/conversations/{id}`

```json
{
  "id": "conv_uuid",
  "userId": "user_uid",
  "title": "Comment apprendre Flutter?",
  "modelUsed": "deepseek-chat",
  "messageCount": 12,
  "projectId": null,
  "createdAt": "timestamp",
  "updatedAt": "timestamp",
  "isPinned": false
}
```

### Document `/conversations/{id}/messages/{id}`

```json
{
  "id": "msg_uuid",
  "role": "user",         // "user" | "assistant" | "system"
  "content": "Bonjour!",
  "tokens": 5,
  "model": null,          // rempli pour assistant
  "isStreaming": false,
  "createdAt": "timestamp"
}
```

### ChatNotifier (Riverpod)

```dart
@riverpod
class ChatNotifier extends _$ChatNotifier {
  @override
  Future<List<Message>> build(String conversationId) async {
    return ref.watch(chatRepositoryProvider).getMessages(conversationId);
  }

  Future<void> sendMessage(String text) async {
    // 1. Vérifier quota
    await ref.read(quotaServiceProvider).checkAndDecrement();

    // 2. Sauvegarder message user → Firestore
    final userMsg = await ref.read(chatRepositoryProvider).addMessage(
      conversationId: state.value!.first.conversationId,
      role: Role.user,
      content: text,
    );

    // 3. Streamer réponse IA
    final buffer = StringBuffer();
    await for (final token in ref.read(aiClientProvider).streamChat(
      messages: state.value!.map((m) => m.toApiMap()).toList(),
    )) {
      buffer.write(token);
      // Mise à jour UI temps réel
      state = AsyncData([...state.value!, userMsg.copyWith(streamingContent: buffer.toString())]);
    }

    // 4. Sauvegarder réponse finale
    await ref.read(chatRepositoryProvider).addMessage(
      conversationId: userMsg.conversationId,
      role: Role.assistant,
      content: buffer.toString(),
    );
  }
}
```

---

## 7. Fonctionnalité : Chat Voix

### Packages
- `speech_to_text` : micro → texte
- `flutter_tts` : texte → synthèse vocale
- `permission_handler` : permissions micro

### Workflow Voix

```
[Appui bouton micro]
  → Demander permission RECORD_AUDIO
  → SpeechToText.listen()
  → Texte transcrit → remplir InputBar
  → [Envoi auto ou manuel]
  → Réponse IA → FlutterTts.speak(response)
```

```dart
// lib/features/chat/presentation/voice_service.dart
class VoiceService {
  final SpeechToText _stt = SpeechToText();
  final FlutterTts _tts = FlutterTts();

  Future<void> initialize() async {
    await _stt.initialize(onError: (e) => debugPrint('STT error: $e'));
    await _tts.setLanguage('fr-FR');
    await _tts.setSpeechRate(0.9);
  }

  Stream<String> listenLive() async* {
    // Retourne les mots reconnus au fur et à mesure
  }

  Future<void> speak(String text) => _tts.speak(text);
  Future<void> stop() => _tts.stop();
}
```

---

## 8. Fonctionnalité : Quotas & File d'Attente

### Logique Quota (Firestore + Cloud Functions)

```
Quota gratuit : 20 req/jour
├── À chaque requête IA :
│   1. Lire users/{uid}.dailyRequests et dailyRequestsDate
│   2. Si date ≠ aujourd'hui → reset à 0
│   3. Si requests >= 20 → throw QuotaExceededException
│   4. Incrémenter dailyRequests + 1
│   5. Appeler API IA
└── Cloud Function `checkQuota` (server-side pour éviter contournement)
```

### Cloud Function — `functions/src/quotas.ts`

```typescript
import * as functions from 'firebase-functions';
import * as admin from 'firebase-admin';

export const checkQuota = functions.https.onCall(async (data, context) => {
  if (!context.auth) throw new functions.https.HttpsError('unauthenticated', 'Login required');
  
  const uid = context.auth.uid;
  const userRef = admin.firestore().doc(`users/${uid}`);
  
  return admin.firestore().runTransaction(async (tx) => {
    const user = (await tx.get(userRef)).data()!;
    const today = new Date().toISOString().split('T')[0];
    
    let dailyCount = user.dailyRequestsDate === today ? user.dailyRequests : 0;
    
    if (user.plan === 'free' && dailyCount >= 20) {
      throw new functions.https.HttpsError('resource-exhausted', 'Daily quota exceeded');
    }
    
    tx.update(userRef, {
      dailyRequests: dailyCount + 1,
      dailyRequestsDate: today,
    });
    
    return { remaining: Math.max(0, 20 - dailyCount - 1) };
  });
});
```

### Gestion des Erreurs Quota (UI)

```dart
on QuotaExceededException {
  showModalBottomSheet(
    context: context,
    builder: (_) => QuotaUpgradeSheet(),  // → PaywallScreen ou vidéo rewarded
  );
}
```

---

## 9. Fonctionnalité : Publicités (AdMob)

### Types de pubs

| Type | Placement | Fréquence |
|---|---|---|
| Banner | Bas du ChatScreen | Permanent (gratuit) |
| Interstitiel | Entre les sessions de chat | Max 1/5 min |
| Rewarded Video | Bouton "+ 5 requêtes" | À la demande |

### Initialisation

```dart
// lib/features/monetization/ads/ad_service.dart
class AdService {
  static Future<void> initialize() async {
    await MobileAds.instance.initialize();
  }

  static BannerAd createBanner() => BannerAd(
    adUnitId: Platform.isAndroid
        ? 'ca-app-pub-XXXXX/banner_android'
        : 'ca-app-pub-XXXXX/banner_ios',
    size: AdSize.banner,
    request: const AdRequest(),
    listener: BannerAdListener(
      onAdFailedToLoad: (ad, err) => ad.dispose(),
    ),
  )..load();

  static Future<bool> showRewarded({
    required VoidCallback onRewarded,
  }) async {
    // Charge + affiche une rewarded ad, appelle onRewarded si succès
    // ...
    return true;
  }
}
```

---

## 10. Fonctionnalité : Abonnements Pro (RevenueCat)

### Setup

```dart
// lib/main.dart
await Purchases.setLogLevel(LogLevel.debug);
await Purchases.configure(
  PurchasesConfiguration(
    Platform.isAndroid ? 'gplay_api_key' : 'apple_api_key',
  )..appUserID = FirebaseAuth.instance.currentUser?.uid,
);
```

### PaywallScreen

```
PaywallScreen
├── Hero "Débloquez le plein potentiel"
├── Liste avantages Pro (icônes + texte)
├── Plans tarifaires (mensuel / annuel avec badge "Meilleure valeur")
├── CTA "Commencer l'essai gratuit 7 jours"
├── "Déjà abonné ? Restaurer les achats"
└── Liens CGU / Politique de confidentialité
```

### Vérification Plan

```dart
@riverpod
Future<bool> isPro(IsPro ref) async {
  final customerInfo = await Purchases.getCustomerInfo();
  return customerInfo.entitlements.active.containsKey('pro');
}
```

---

## 11. Fonctionnalité : Upload Fichiers & PDF

### Formats Supportés
- PDF, DOCX, TXT, MD → extraction texte + envoi au contexte IA
- Images (JPG/PNG) → description via vision model (si Pro)

### Génération PDF (export réponse)

```dart
Future<Uint8List> exportToPdf(String content, String title) async {
  final doc = pw.Document();
  doc.addPage(pw.Page(
    build: (ctx) => pw.Column(children: [
      pw.Text(title, style: pw.TextStyle(fontSize: 24, fontWeight: pw.FontWeight.bold)),
      pw.SizedBox(height: 16),
      pw.Text(content),
    ]),
  ));
  return doc.save();
}
```

---

## 12. Fonctionnalité : Projets & Dossiers (Pro)

### Structure Firestore

```
/projects/{projectId}
  ├── id, title, description, userId
  ├── conversationIds: [...]
  └── updatedAt

/conversations/{convId}
  └── projectId: "proj_uuid" | null
```

### ProjectsScreen (Pro Gate)

```dart
Widget build(BuildContext context) {
  final proAsync = ref.watch(isProProvider);
  return proAsync.when(
    data: (isPro) => isPro ? ProjectsListView() : ProFeatureGate(),
    loading: () => const CircularProgressIndicator(),
    error: (e, _) => ErrorView(error: e),
  );
}
```

---

## 13. Synchronisation App ↔ Extension

### Firestore Realtime Listeners

```dart
// Écouter les nouvelles conversations depuis n'importe quel appareil
ref.watch(conversationsStreamProvider(userId));

// Provider
@riverpod
Stream<List<Conversation>> conversationsStream(ConversationsStreamRef ref, String userId) {
  return FirebaseFirestore.instance
      .collection('conversations')
      .where('userId', isEqualTo: userId)
      .orderBy('updatedAt', descending: true)
      .limit(50)
      .snapshots()
      .map((snap) => snap.docs.map(Conversation.fromFirestore).toList());
}
```

### FCM Push Notifications

```dart
// Notification quand un chat est mis à jour depuis l'extension
FirebaseMessaging.onMessage.listen((RemoteMessage message) {
  if (message.data['type'] == 'chat_update') {
    ref.invalidate(conversationsStreamProvider);
  }
});
```

---

## 14. Onboarding & Viral Features

### Onboarding Flow (3 écrans, 30 s)

```
Slide 1 : "Ton assistant IA personnel" + illustration
Slide 2 : "Répond en secondes, en voix ou en texte" + démo animée
Slide 3 : "Gratuit pour toujours, Pro pour aller plus loin"
  → [Commencer gratuitement] + [Me connecter]
```

### Partage Viral

```dart
// Bouton partage sur chaque réponse IA
Future<void> shareResponse(String text) async {
  final preview = text.length > 200 ? '${text.substring(0, 200)}...' : text;
  await Share.share(
    '💡 "$preview"\n\n— Généré par AironBot\nhttps://aironbot.app',
    subject: 'Découvre AironBot — Chat IA gratuit',
  );
}
```

### Referral Program

```
Parrainage : /users/{uid}.referralCode = "ABC123"
→ Lien : https://aironbot.app?ref=ABC123
→ Nouvel utilisateur s'inscrit avec ce code
→ Cloud Function crédite +5 requêtes à chacun
```

---

## 15. Tests (Unit / Widget / Integration)

### Unit Tests

```bash
flutter test test/features/chat/
flutter test test/core/
```

```dart
// test/features/chat/quota_service_test.dart
void main() {
  group('QuotaService', () {
    test('allows request when under limit', () async { ... });
    test('throws when daily limit reached', () async { ... });
    test('resets quota on new day', () async { ... });
  });
}
```

### Widget Tests

```dart
void main() {
  testWidgets('ChatBubble renders markdown', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: ChatBubble(message: Message(content: '**Hello**', role: Role.assistant)),
    ));
    expect(find.text('Hello'), findsOneWidget);
  });
}
```

### Integration Tests (Émulateurs)

```bash
flutter drive \
  --driver=test_driver/integration_driver.dart \
  --target=integration_test/auth_flow_test.dart \
  -d emulator-5554
```

---

## 16. CI/CD — GitHub Actions + Fastlane

### `.github/workflows/ci.yml`

```yaml
name: CI/CD Mobile

on:
  push:
    branches: [main, develop]
  pull_request:

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: subosito/flutter-action@v2
        with:
          flutter-version: '3.24.0'
      - run: flutter pub get
      - run: flutter analyze
      - run: flutter test --coverage

  build-android:
    needs: test
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: subosito/flutter-action@v2
      - run: flutter build apk --release
      - uses: actions/upload-artifact@v4
        with:
          name: android-apk
          path: build/app/outputs/flutter-apk/app-release.apk

  build-ios:
    needs: test
    runs-on: macos-latest
    steps:
      - uses: actions/checkout@v4
      - uses: subosito/flutter-action@v2
      - run: flutter build ios --release --no-codesign

  deploy-staging:
    needs: [build-android, build-ios]
    if: github.ref == 'refs/heads/develop'
    runs-on: ubuntu-latest
    steps:
      - run: bundle exec fastlane android staging
```

---

## 17. Liste Exhaustive des Fonctions

### Auth
- `signInWithEmail(email, password)` — connexion email
- `signInWithGoogle()` — OAuth Google
- `signInWithApple()` — OAuth Apple (iOS/Web)
- `signInAnonymously()` — mode invité
- `signOut()` — déconnexion + clear cache
- `deleteAccount()` — suppression RGPD

### Chat
- `sendMessage(text, conversationId)` — envoi + streaming
- `sendVoiceMessage()` — micro → STT → envoi
- `streamAiResponse(messages)` — DeepSeek-V3 SSE
- `stopStreaming()` — annuler requête en cours
- `retryLastMessage()` — renvoyer dernier message
- `deleteMessage(messageId)` — supprimer un message
- `copyMessage(content)` — copier dans presse-papier
- `shareMessage(content)` — partager réponse

### Conversations
- `createConversation(title?)` — nouvelle conversation
- `getConversations(userId)` — liste paginated
- `deleteConversation(id)` — supprimer + messages
- `renameConversation(id, title)` — renommer
- `pinConversation(id)` — épingler en haut
- `searchConversations(query)` — recherche full-text
- `exportConversationToPdf(id)` — export PDF

### Quotas
- `checkQuota(uid)` — vérifie + décremente (server)
- `getRemainingRequests(uid)` — requêtes restantes
- `resetDailyQuota(uid)` — reset journalier (cron)
- `addBonusRequests(uid, count)` — ajouter requêtes (rewarded)

### Publicités
- `initializeAds()` — SDK AdMob
- `loadBannerAd()` — charger bannière
- `showInterstitialAd()` — afficher interstitiel
- `showRewardedAd(onRewarded)` — vidéo bonus requêtes
- `disposeBannerAd()` — libérer ressources

### Abonnements
- `getCustomerInfo()` — état abonnement RevenueCat
- `purchasePackage(package)` — acheter plan
- `restorePurchases()` — restaurer achats
- `isPro(uid)` — vérifier statut Pro
- `getOfferings()` — récupérer les plans disponibles

### Voix
- `initializeSpeech()` — permission + init STT
- `startListening()` — écoute micro
- `stopListening()` — fin écoute
- `speak(text)` — TTS synthèse
- `stopSpeaking()` — arrêter TTS

### Fichiers
- `pickFile()` — sélecteur fichier système
- `uploadFileToStorage(file)` — Firebase Storage
- `extractTextFromPdf(bytes)` — extraction texte
- `generatePdf(content, title)` — création PDF

### Projets (Pro)
- `createProject(title, description?)` — nouveau projet
- `addConversationToProject(convId, projectId)` — rattacher
- `getProjectConversations(projectId)` — liste
- `deleteProject(id)` — supprimer projet + unlink

### Utilisateur
- `updateDisplayName(name)` — modifier prénom
- `updateProfilePhoto(image)` — changer avatar
- `getUserStats()` — stats perso (total req, plan, etc.)
- `generateReferralCode()` — code parrainage
- `applyReferralCode(code)` — appliquer parrainage

### Sync / Notifications
- `subscribeToConversations(userId)` — stream Firestore
- `listenToPushNotifications()` — FCM
- `syncUserPlan()` — synchroniser plan entre appareils
