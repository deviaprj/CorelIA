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
#   5. Patch manifest.json : remove "type": "module", fix CSP, fix web_accessible_resources
#   6. Crée aironbot-extension.zip prêt à uploader sur le Chrome Web Store
# =============================================================================

set -euo pipefail

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
cp "$WEB_SRC/manifest.json"     "$BUILD_EXT/manifest.json"
cp "$WEB_SRC/background.js"     "$BUILD_EXT/background.js"
cp "$WEB_SRC/content_script.js" "$BUILD_EXT/content_script.js"
cp "$WEB_SRC/speech_bridge.js"  "$BUILD_EXT/speech_bridge.js"

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
  #     Dans chrome-extension://, "/" résout contre la racine de l'extension,
  #     mais "./" résout relativement au répertoire de index.html (plus sûr).
  sed -i 's|<base href="/">|<base href="./">|g' "$INDEX"
  echo "🩹  base href corrigé : / → ./"

  # 5b. Retirer toute référence au Service Worker Flutter
  sed -i '/serviceWorker/d' "$INDEX"
  sed -i '/flutter_service_worker/d' "$INDEX"
  echo "🩹  ServiceWorker Flutter retiré de index.html."
fi

# ── 6. Patch flutter_bootstrap.js ─────────────────────────────────────────────
BOOTSTRAP="$BUILD_EXT/flutter_bootstrap.js"
if [[ -f "$BOOTSTRAP" ]]; then
  # Remplacer l'enregistrement du SW par un no-op
  # Chercher la fonction loadServiceWorker et la court-circuiter
  # Alternative simple : remplacer flutter_service_worker.js par une chaîne vide
  # pour que URL() resolution échoue gracieusement (déjà catchée par Flutter)
  sed -i 's/flutter_service_worker\.js/flutter_service_worker_disabled.js/g' "$BOOTSTRAP"
  echo "🩹  Référence SW neutralisée dans flutter_bootstrap.js."
fi

# ── 7. Patch manifest.json ───────────────────────────────────────────────────
MANIFEST="$BUILD_EXT/manifest.json"
if [[ -f "$MANIFEST" ]]; then
  # 7a. Retirer "type": "module" du background (background.js n'est pas un ES module)
  #     Utiliser python pour manipuler le JSON proprement
  python3 -c "
import json, sys
with open('$MANIFEST', 'r') as f:
    m = json.load(f)
if 'background' in m and 'type' in m['background']:
    del m['background']['type']
    print('Retiré type:module du background')
# 7b. Corriger CSP : autoriser blob: URLs pour les workers Skwasm
#     NOTE: blob: dans script-src est interdit par Manifest V3
#     On l'ajoute uniquement dans worker-src
if 'content_security_policy' in m and 'extension_pages' in m['content_security_policy']:
    csp = m['content_security_policy']['extension_pages']
    if 'blob:' not in csp:
        csp = csp.replace('worker-src \'self\'', 'worker-src \'self\' blob:')
        m['content_security_policy']['extension_pages'] = csp
        print('CSP mis à jour avec blob: dans worker-src')
# 7c. Ajouter *.wasm aux web_accessible_resources
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
ZIP_PATH="$PROJECT_ROOT/aironbot-extension.zip"
rm -f "$ZIP_PATH"
cd "$BUILD_EXT"
zip -r "$ZIP_PATH" . --exclude "*.DS_Store" --exclude "__MACOSX/*"
cd "$PROJECT_ROOT"

echo ""
echo "🎉 Extension prête !"
echo "   → build/extension/     (dossier non compressé — idéal pour test)"
echo "   → aironbot-extension.zip (prêt pour le Chrome Web Store)"
echo ""
echo "Pour tester :"
echo "  1. Ouvrez chrome://extensions"
echo "  2. Activez le Mode développeur"
echo "  3. Cliquez sur 'Charger l'extension non empaquetée'"
echo "  4. Sélectionnez build/extension/"