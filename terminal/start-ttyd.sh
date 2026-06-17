#!/bin/sh
# Garde-fou : refuser de démarrer avec un mot de passe vide ou par défaut.
# ttyd expose un shell web — un mot de passe "changeme"/vide = porte ouverte.
# On échoue fermé (exit 1) plutôt que d'exposer un terminal non sécurisé.
TTYD_PASS="${TTYD_PASS:-}"
if [ -z "$TTYD_PASS" ] || [ "$TTYD_PASS" = "changeme" ]; then
  echo "FATAL: TTYD_PASS est vide ou encore à 'changeme'." >&2
  echo "       Définis un TTYD_PASS fort dans .env avant de lancer le service terminal." >&2
  exit 1
fi
exec ttyd -p 7681 -c "${TTYD_USER:-corelia}:${TTYD_PASS}" su - corelia
