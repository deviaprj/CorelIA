#!/usr/bin/env bash
#
# Compile l'APK Android avec la configuration client injectée via --dart-define.
#
# Pourquoi ce script : le fichier `.env` n'est JAMAIS embarqué dans l'APK (il
# contient des secrets opérateur). Sans les --dart-define ci-dessous, l'APK ne
# connaît pas l'URL du Worker : l'appli retombe sur l'accès direct au fournisseur
# IA, ne trouve aucune clé (elle vit dans le Worker) et échoue.
#
# Usage :
#   bash scripts/build_apk.sh --release
#   bash scripts/build_apk.sh --debug --target-platform android-arm64
#
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="$ROOT_DIR/.env"

if [ ! -f "$ENV_FILE" ]; then
  echo "Erreur : $ENV_FILE introuvable (copier .env.example)." >&2
  exit 1
fi

read_env() {
  grep -E "^$1=" "$ENV_FILE" 2>/dev/null | head -1 | cut -d= -f2- \
    | tr -d '"' | tr -d '\r' | sed 's/^[[:space:]]*//; s/[[:space:]]*$//'
}

WORKER_URL="$(read_env CLOUDFLARE_WORKER_URL)"
CLIENT_KEY="$(read_env CLIENT_API_KEY)"

if [ -z "$WORKER_URL" ]; then
  echo "Erreur : CLOUDFLARE_WORKER_URL absent de .env." >&2
  echo "L'APK doit passer par le Worker : les clés des fournisseurs IA restent" >&2
  echo "côté serveur et ne doivent jamais être embarquées." >&2
  exit 1
fi

if [ -z "$CLIENT_KEY" ]; then
  echo "Attention : CLIENT_API_KEY vide — le Worker refusera probablement les requêtes." >&2
fi

DEFINES=(
  "--dart-define=CLOUDFLARE_WORKER_URL=$WORKER_URL"
  "--dart-define=CLIENT_API_KEY=$CLIENT_KEY"
)

RC_ANDROID="$(read_env REVENUECAT_API_KEY_ANDROID)"
if [ -n "$RC_ANDROID" ]; then
  DEFINES+=("--dart-define=REVENUECAT_API_KEY_ANDROID=$RC_ANDROID")
fi

RC_IOS="$(read_env REVENUECAT_API_KEY_IOS)"
if [ -n "$RC_IOS" ]; then
  DEFINES+=("--dart-define=REVENUECAT_API_KEY_IOS=$RC_IOS")
fi

# DEEPSEEK_API_KEY n'est jamais transmis : secret opérateur, détenu par le Worker.

cd "$ROOT_DIR"
echo "Build APK — Worker : $WORKER_URL — CLIENT_API_KEY : ${#CLIENT_KEY} caractères"
exec flutter build apk "${DEFINES[@]}" "$@"
