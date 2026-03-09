// Ce fichier est GÉNÉRÉ automatiquement par FlutterFire CLI.
// Commande : flutterfire configure
// Ne pas modifier manuellement.

import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) return web;
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        return ios;
      default:
        // Linux / macOS / Windows → utilise la config Web
        return web;
    }
  }

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyCGs7rX4TMDZyvYZ1_f1PGCFSwr1HBG8Ig',
    appId: '1:258079343012:web:4075e2d10e0ad1c38a4131',
    messagingSenderId: '258079343012',
    projectId: 'aironbot-1773058753',
    authDomain: 'aironbot-1773058753.firebaseapp.com',
    storageBucket: 'aironbot-1773058753.firebasestorage.app',
  );

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyBuPfTEFYNG69oxaQtDXDpC64OzjRmd7fU',
    appId: '1:258079343012:android:b9cdc370a20302dc8a4131',
    messagingSenderId: '258079343012',
    projectId: 'aironbot-1773058753',
    storageBucket: 'aironbot-1773058753.firebasestorage.app',
  );

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'AIzaSyD8Wsqh2O4JNDPb1TjxibAEzDEQwLvQgU4',
    appId: '1:258079343012:ios:654df762bbdd488b8a4131',
    messagingSenderId: '258079343012',
    projectId: 'aironbot-1773058753',
    storageBucket: 'aironbot-1773058753.firebasestorage.app',
    iosBundleId: 'com.aironbot.aironBot',
  );
}
