# CorelIA — Cloudflare Worker (`api.zentic.fr`)

Passerelle IA pour l'application mobile CorelIA. Elle garde les clés des
fournisseurs côté serveur, route les modèles, limite le débit et expose la
recherche web.

## Endpoints

| Méthode | Route | Description |
|---|---|---|
| `POST` | `/chat` | Réponse IA en streaming SSE (format OpenAI) |
| `GET` | `/search?q=…&limit=5` | Recherche web DuckDuckGo |
| `GET` | `/health` | État du service et fournisseur actif |

Auth : en-tête `X-API-Key` si le secret `CLIENT_API_KEY` est défini.
Rate limiting : 100 requêtes/minute/IP (variable `RATE_LIMIT_PER_MINUTE`).

## Déploiement

Prérequis : un compte Cloudflare avec la zone **zentic.fr** (DNS déjà délégué à
Cloudflare via `jasmine.ns.cloudflare.com` / `dax.ns.cloudflare.com`).

```bash
cd cloudflare-worker
npm install

# Secrets (jamais dans le dépôt)
npx wrangler secret put DEEPSEEK_API_KEY   # clé du fournisseur IA
npx wrangler secret put CLIENT_API_KEY     # clé publique de l'app (openssl rand -hex 32)

# Déploiement
npx wrangler deploy
```

`wrangler.jsonc` déclare une **route** :
`routes: [{ pattern: "api.zentic.fr/*", zone_name: "zentic.fr" }]`.
Elle rattache le Worker au hostname sans créer d'enregistrement DNS (le
hostname est déjà couvert par la zone, qui héberge d'autres routes comme
`nei.zentic.fr`). Aucun VPS, aucune modification des enregistrements
existants (`MX`, `SPF`, `DKIM`, `DMARC`, `mail`, `www`…) n'est nécessaire.

> Prérequis : le token wrangler doit avoir `workers_routes:write` et la zone
> `zentic.fr` dans le compte. Le déploiement crée aussi une URL de secours
> `https://corelia-api.<sous-domaine>.workers.dev`.
>
> Si `deploy` échoue avec `A request to ... /domains/records failed`
> (code API `10405`), c'est que le token ne permet pas les **domaines
> personnalisés** : la route ci-dessus fonctionne sans ce droit.
>
> Autre piège : si `esbuild` ou `workerd` ne sont pas exécutables
> (`EACCES`), exécuter `chmod +x node_modules/.bin/* node_modules/@esbuild/*/bin/* node_modules/workerd/bin/*`.

## Développement local

```bash
cp .dev.vars.example .dev.vars   # renseigner les clés
npx wrangler dev                 # http://localhost:8787
```

## Vérification

```bash
curl https://api.zentic.fr/health

curl -N https://api.zentic.fr/chat \
  -H 'Content-Type: application/json' \
  -H 'X-API-Key: <CLIENT_API_KEY>' \
  -d '{"messages":[{"role":"user","content":"Bonjour"}],"stream":true}'

curl 'https://api.zentic.fr/search?q=météo%20Paris' \
  -H 'X-API-Key: <CLIENT_API_KEY>'
```

## Côté application Flutter

```bash
flutter build apk \
  --dart-define=CLOUDFLARE_WORKER_URL=https://api.zentic.fr \
  --dart-define=CLIENT_API_KEY=<CLIENT_API_KEY>
```

## Fournisseurs IA

1. **DeepSeek** si `DEEPSEEK_API_KEY` est défini (texte et raisonnement).
2. **Workers AI** (binding `AI`, sans clé) en repli et pour la **vision**
   (traitement des images).

Variables optionnelles dans `wrangler.jsonc` :

- `AI_TEXT_MODEL` — défaut `@cf/meta/llama-3.3-70b-instruct-fp8-fast`
- `AI_VISION_MODEL` — défaut `@cf/meta/llama-3.2-11b-vision-instruct`

> Les identifiants de modèles Workers AI évoluent : vérifiez la liste disponible
> dans le tableau de bord Cloudflare (Workers AI → Models) et ajustez ces
> variables si un identifiant n'est plus servi.
