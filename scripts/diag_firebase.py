#!/usr/bin/env python3
"""Diagnostic du projet Firebase : fournisseurs d'auth activés + base Firestore.

Interroge les API publiques avec la clé d'API du client (celle du JSON), donc
sans identifiants d'administration. Le compte de test créé est supprimé aussitôt.

Usage :
    python3 scripts/diag_firebase.py
"""

import json
import pathlib
import secrets
import urllib.error
import urllib.request

ROOT = pathlib.Path(__file__).resolve().parent.parent
with open(ROOT / 'android' / 'app' / 'google-services.json', encoding='utf-8') as fh:
    cfg = json.load(fh)

PROJECT = cfg['project_info']['project_id']
KEY = cfg['client'][0]['api_key'][0]['current_key']
IDENTITY = 'https://identitytoolkit.googleapis.com/v1'


def call(url, payload):
    data = json.dumps(payload).encode()
    req = urllib.request.Request(
        url, data=data, headers={'Content-Type': 'application/json'}
    )
    try:
        with urllib.request.urlopen(req, timeout=20) as resp:
            return resp.status, json.loads(resp.read() or b'{}')
    except urllib.error.HTTPError as err:
        body = err.read().decode()
        try:
            return err.code, json.loads(body)
        except json.JSONDecodeError:
            return err.code, {'raw': body[:200]}


def error_code(body):
    return (body.get('error') or {}).get('message', '')


print(f'Projet : {PROJECT}\n')

# ── E-mail / mot de passe ────────────────────────────────────────────────────
email = f'diag-{secrets.token_hex(6)}@example.com'
password = 'Diagnostic123'
status, body = call(
    f'{IDENTITY}/accounts:signUp?key={KEY}',
    {'email': email, 'password': password, 'returnSecureToken': True},
)
code = error_code(body)

if status == 200:
    print('[OK]   E-mail / mot de passe : ACTIVÉ')
    token = body.get('idToken')
    if token:
        st, _ = call(f'{IDENTITY}/accounts:delete?key={KEY}', {'idToken': token})
        print(f'       (compte de test supprimé : {st})')
elif 'OPERATION_NOT_ALLOWED' in code:
    print('[KO]   E-mail / mot de passe : DÉSACTIVÉ — à activer dans '
          'Authentication → Sign-in method')
elif 'CONFIGURATION_NOT_FOUND' in code:
    print('[KO]   E-mail / mot de passe : Authentification non initialisée — '
          'ouvre Authentication puis « Commencer », et ajoute le fournisseur '
          'E-mail/Mot de passe')
else:
    print(f'[??]   E-mail / mot de passe : réponse inattendue {status} {code}')

# ── Google ───────────────────────────────────────────────────────────────────
status, body = call(
    f'{IDENTITY}/accounts:createAuthUri?key={KEY}',
    {'providerId': 'google.com', 'continueUri': 'http://localhost'},
)
code = error_code(body)
if 'OPERATION_NOT_ALLOWED' in code:
    print('[KO]   Google : DÉSACTIVÉ — à activer dans Authentication → '
          'Sign-in method')
elif 'CONFIGURATION_NOT_FOUND' in code:
    print('[KO]   Google : Authentification non initialisée (voir ci-dessus)')
elif status == 200:
    print('[OK]   Google : ACTIVÉ')
else:
    print(f'[??]   Google : réponse inattendue {status} {code}')

# ── Firestore ────────────────────────────────────────────────────────────────
url = f'https://firestore.googleapis.com/v1/projects/{PROJECT}/databases/(default)'
try:
    with urllib.request.urlopen(url, timeout=20) as resp:
        print(f'[OK]   Firestore : base accessible ({resp.status})')
except urllib.error.HTTPError as err:
    body = err.read().decode()
    if err.code == 404:
        print('[KO]   Firestore : base absente — crée-la dans '
              'Firestore Database → Créer une base de données')
    elif err.code == 403:
        print('[OK]   Firestore : base présente (403 sans authentification, '
              'c\'est attendu)')
    else:
        print(f'[??]   Firestore : {err.code} {body[:120]}')
except Exception as exc:  # noqa: BLE001
    print(f'[??]   Firestore : {exc}')
