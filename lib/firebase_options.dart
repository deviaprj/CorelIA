// Stub Firebase options for compilation.
// In production, generate with: flutterfire configure
// This file is gitignored and should be replaced with real Firebase config.

import 'package:firebase_core/firebase_core.dart';

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    return const FirebaseOptions(
      apiKey: 'stub-api-key',
      appId: '1:stub:web:stub',
      messagingSenderId: '000000000000',
      projectId: 'stub-project',
      storageBucket: 'stub-project.appspot.com',
    );
  }
}