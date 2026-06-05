#!/usr/bin/env bash
# =============================================================================
# build_extension.sh — Build Flutter Web + package extension Chrome
# =============================================================================
# Usage :
#   bash scripts/build_extension.sh [--dart-define=KEY=VAL ...]
#
# Prérequis :
#   - Flutter SDK installé et dans le PATH
#   - Être dans la racine du projet
#
# Ce script :
#   1. Compile Flutter Web (release, pwa-strategy=none)
#   2. Copie les fichiers d'extension dans build/extension/
#   3. Supprime le ServiceWorker Flutter (incompatible avec Manifest V3)
#   4. Patch index.html : base href + SW registration
#   5. Patch flutter_bootstrap.js : SW retiré + CanvasKit local (pas CDN)
#   6. Patch manifest.json : remove "type": "module", fix CSP, fix web_accessible_resources
#   7. Crée corely-extension.zip prêt à uploader sur le Chrome Web Store
# =============================================================================

set -euo pipefail

# Ensure Flutter is in PATH
export PATH="$HOME/flutter/bin:$PATH"

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_WEB="$PROJECT_ROOT/build/web"
BUILD_EXT="$PROJECT_ROOT/build/extension"
WEB_SRC="$PROJECT_ROOT/web"

# ── 1. Charger le fichier .env si présent ─────────────────────────────────────
ENV_FILE="$PROJECT_ROOT/.env"
DART_DEFINES=""
if [[ -f "$ENV_FILE" ]]; then
  echo "📄 Chargement de .env..."
  while IFS='=' read -r key value; do
    [[ "$key" =~ ^#.*$ || -z "$key" ]] && continue
    DART_DEFINES="$DART_DEFINES --dart-define=$key=$value"
  done < "$ENV_FILE"
fi

# Ajouter les args supplémentaires passés au script
EXTRA_DEFINES="${*:-}"

# ── 2. Build Flutter Web ──────────────────────────────────────────────────────
echo "⚙️  Build Flutter Web (release)..."
cd "$PROJECT_ROOT"
flutter build web \
  --release \
  --pwa-strategy=none \
  --base-href=/ \
  $DART_DEFINES \
  $EXTRA_DEFINES

echo "✅ Flutter build web terminé."

# ── 3. Préparer le dossier extension ─────────────────────────────────────────
echo "📂 Préparation de build/extension/..."
rm -rf "$BUILD_EXT"
cp -r "$BUILD_WEB" "$BUILD_EXT"

# Copier les fichiers spécifiques à l'extension
cp_files() { local f; for f in "$@"; do [[ -f "$WEB_SRC/$f" ]] && cp "$WEB_SRC/$f" "$BUILD_EXT/$f" || echo "⚠️  $f non trouvé, ignoré."; done; }
cp_files manifest.json background.js content_script.js speech_bridge.js extension_bridge.js dom_actions.js corely_init.js

# Créer le dossier icons si absent
mkdir -p "$BUILD_EXT/icons"
if [[ -d "$WEB_SRC/icons" ]]; then
  cp -r "$WEB_SRC/icons/." "$BUILD_EXT/icons/"
else
  echo "⚠️  Aucun dossier web/icons/ trouvé. Ajouter les icônes manuellement."
fi

# ── 4. Supprimer le Service Worker Flutter ─────────────────────────────────────
SW_FILE="$BUILD_EXT/flutter_service_worker.js"
if [[ -f "$SW_FILE" ]]; then
  rm "$SW_FILE"
  echo "🗑️  flutter_service_worker.js supprimé."
fi

# ── 5. Patch index.html ──────────────────────────────────────────────────────
INDEX="$BUILD_EXT/index.html"
if [[ -f "$INDEX" ]]; then
  # 5a. Corriger <base href="/"> → <base href="./">
  sed -i 's|<base href="/">|<base href="./">|g' "$INDEX"
  echo "🩹  base href corrigé : / → ./"

  # 5b. Retirer toute référence au Service Worker Flutter
  sed -i '/serviceWorker/d' "$INDEX"
  sed -i '/flutter_service_worker/d' "$INDEX"
  echo "🩹  ServiceWorker Flutter retiré de index.html."

  # 5c. Pas de nonce dans index.html — Manifest V3 ne supporte pas les nonces.
  #     Les scripts inline de Flutter sont interceptés par corely_init.js
  #     et exécutés via new Function() au lieu d'être injectés dans le DOM.
fi

# ── 6. Patch flutter_bootstrap.js ─────────────────────────────────────────────
BOOTSTRAP="$BUILD_EXT/flutter_bootstrap.js"
if [[ -f "$BOOTSTRAP" ]]; then
  python3 -c "
import re, sys
with open('$BOOTSTRAP', 'r') as f:
    content = f.read()

# 6a. Supprimer complètement serviceWorkerSettings du loader.load() call.
content = re.sub(r'serviceWorkerSettings:\s*\{[^}]*\}\s*,?\s*', '', content)
content = re.sub(r'\.load\(\{\s*\}\)', '.load()', content)

# 6b. Forcer CanvasKit local (pas CDN).
content = re.sub(
    r'(_flutter\.buildConfig\s*=\s*\{)',
    r'\1\"useLocalCanvasKit\":true,',
    content
)
print('useLocalCanvasKit:true ajouté à _flutter.buildConfig')

# 6c. Neutraliser la fonction loadServiceWorker
content = re.sub(
    r'loadServiceWorker\(t\)\{',
    'loadServiceWorker(t){if(1)return Promise.resolve();',
    content
)

with open('$BOOTSTRAP', 'w') as f:
    f.write(content)
print('flutter_bootstrap.js patché (SW retiré + CanvasKit local)')
" 2>&1
  echo "🩹  Bootstrap patché : SW retiré + CanvasKit local forcé."
fi

# ── 7. Patch manifest.json ───────────────────────────────────────────────────
MANIFEST="$BUILD_EXT/manifest.json"
if [[ -f "$MANIFEST" ]]; then
  python3 -c "
import json, re, sys
with open('$MANIFEST', 'r') as f:
    m = json.load(f)
if 'background' in m and 'type' in m['background']:
    del m['background']['type']
    print('Retiré type:module du background')
# Corriger CSP : retirer blob: et worker-src (Manifest V3 interdit)
# Manifest V3 n'accepte PAS les nonces dans script-src.
# Les scripts inline Flutter sont interceptés par corely_init.js.
if 'content_security_policy' in m and 'extension_pages' in m['content_security_policy']:
    csp = m['content_security_policy']['extension_pages']
    csp = csp.replace(' blob:', '')
    csp = csp.replace(\"; worker-src 'self'\", '')
    # Retirer tout nonce eventuel (Manifest V3 ne les supporte pas)
    csp = re.sub(r\"\\s*'nonce-[^']+'\", '', csp)
    m['content_security_policy']['extension_pages'] = csp
    print('CSP vérifié (blob: retiré, nonce retiré si présent)')
# Ajouter *.wasm aux web_accessible_resources
if 'web_accessible_resources' in m:
    for group in m['web_accessible_resources']:
        if 'canvaskit/**' in group.get('resources', []) or '*.js' in group.get('resources', []):
            if '*.wasm' not in group['resources']:
                group['resources'].append('*.wasm')
                print('Ajouté *.wasm aux web_accessible_resources')
with open('$MANIFEST', 'w') as f:
    json.dump(m, f, indent=2)
    f.write('\n')
" 2>&1
  echo "🩹  Manifest.json patché."
fi

# ── 8. Créer le ZIP ───────────────────────────────────────────────────────────
ZIP_PATH="$PROJECT_ROOT/corely-extension.zip"
rm -f "$ZIP_PATH"
cd "$BUILD_EXT"
zip -r "$ZIP_PATH" . --exclude "*.DS_Store" --exclude "__MACOSX/*"
cd "$PROJECT_ROOT"

echo ""
echo "🎉 Extension prête !"
echo "   → build/extension/     (dossier non compressé — idéal pour test)"
echo "   → corely-extension.zip (prêt pour le Chrome Web Store)"
echo ""
echo "Pour tester :"
echo "  1. Ouvrez chrome://extensions"
echo "  2. Activez le Mode développeur"
echo "  3. Cliquez sur 'Charger l'extension non empaquetée'"
echo "  4. Sélectionnez build/extension/"