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
#   4. Crée aironbot-extension.zip prêt à uploader sur le Chrome Web Store
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

# ── 4. Supprimer le Service Worker Flutter (conflits avec background.js) ──────
SW_FILE="$BUILD_EXT/flutter_service_worker.js"
if [[ -f "$SW_FILE" ]]; then
  rm "$SW_FILE"
  echo "🗑️  flutter_service_worker.js supprimé."
fi

# Patch index.html : retirer l'enregistrement du SW Flutter
INDEX="$BUILD_EXT/index.html"
if [[ -f "$INDEX" ]]; then
  # Supprimer les lignes d'enregistrement du SW Flutter
  sed -i '/serviceWorker/d' "$INDEX"
  sed -i '/flutter_service_worker/d' "$INDEX"
  echo "🩹  ServiceWorker Flutter retiré de index.html."
fi

# ── 5. Créer le ZIP ───────────────────────────────────────────────────────────
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
echo "  3. Cliquez sur 'Charger l\'extension non empaquetée'"
echo "  4. Sélectionnez build/extension/"
