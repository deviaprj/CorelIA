#!/usr/bin/env python3
"""Génère lib/firebase_options.dart depuis android/app/google-services.json.

Évite d'installer Node + flutterfire_cli pour une cible Android : les valeurs de
`FirebaseOptions` (android) sont exactement celles du fichier de configuration
téléchargé depuis la console Firebase.

Usage :
    python3 scripts/gen_firebase_options.py

À relancer chaque fois que google-services.json change — notamment après avoir
ajouté une empreinte SHA-1, car la console régénère alors les clients OAuth.
"""

from __future__ import annotations

import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SOURCE = ROOT / 'android' / 'app' / 'google-services.json'
TARGET = ROOT / 'lib' / 'firebase_options.dart'


def main() -> int:
    if not SOURCE.exists():
        print(f'Erreur : {SOURCE} introuvable.', file=sys.stderr)
        print(
            'Télécharge-le depuis la console Firebase '
            '(Paramètres du projet → Tes applications → Android).',
            file=sys.stderr,
        )
        return 1

    data = json.loads(SOURCE.read_text(encoding='utf-8'))
    info = data['project_info']
    client = data['client'][0]
    client_info = client['client_info']

    project_id = info['project_id']
    if project_id.startswith('corelia-demo'):
        print(
            'Erreur : google-services.json est encore le stub de démonstration '
            '(pas de vrai projet Firebase).',
            file=sys.stderr,
        )
        return 1

    options = {
        'apiKey': client['api_key'][0]['current_key'],
        'appId': client_info['mobilesdk_app_id'],
        'messagingSenderId': info['project_number'],
        'projectId': project_id,
        'storageBucket': info['storage_bucket'],
    }
    body = '\n'.join(f"    {key}: '{value}'," for key, value in options.items())

    TARGET.write_text(
        f"""// Fichier généré depuis android/app/google-services.json — projet {project_id}.
// Ne pas éditer à la main : relancer `python3 scripts/gen_firebase_options.py`
// après toute modification du JSON.
//
// Pour ajouter d'autres plateformes (iOS, Web, macOS) :
//   dart pub global activate flutterfire_cli && flutterfire configure

import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;

/// Options Firebase de chaque plateforme.
class DefaultFirebaseOptions {{
  static FirebaseOptions get currentPlatform {{
    if (kIsWeb) throw UnsupportedError(_missing('Web'));
    switch (defaultTargetPlatform) {{
      case TargetPlatform.android:
        return android;
      default:
        throw UnsupportedError(_missing(defaultTargetPlatform.name));
    }}
  }}

  static String _missing(String platform) =>
      'Plateforme « $platform » non configurée dans ce build. Exécute '
      'flutterfire configure pour ajouter sa configuration Firebase.';

  static const FirebaseOptions android = FirebaseOptions(
{body}
  );
}}
""",
        encoding='utf-8',
    )

    oauth_clients = len(client.get('oauth_client') or [])
    print(f'écrit : {TARGET}')
    print(f'projet : {project_id}')
    if oauth_clients == 0:
        print(
            'ATTENTION : aucun client OAuth dans ce google-services.json. '
            'La connexion Google échouera (erreur DEVELOPER_ERROR). '
            'Ajoute l’empreinte SHA-1 de ta clé de signature dans la console '
            'Firebase, puis retélécharge le fichier.',
            file=sys.stderr,
        )
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
