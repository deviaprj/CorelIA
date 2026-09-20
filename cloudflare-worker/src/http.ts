import type { Env } from './types';

/**
 * En-têtes CORS.
 *
 * Les applications mobiles n'envoient pas d'en-tête `Origin` (autorisé).
 * Pour le web, seules les origines listées dans `ALLOWED_ORIGINS` sont admises.
 */
export function corsHeaders(request: Request, env: Env): Record<string, string> {
  const origin = request.headers.get('Origin');
  const allowed = (env.ALLOWED_ORIGINS ?? '')
    .split(',')
    .map((value) => value.trim())
    .filter(Boolean);

  const headers: Record<string, string> = {
    'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
    'Access-Control-Allow-Headers': 'Content-Type, X-API-Key, Accept',
    'Access-Control-Max-Age': '86400',
    Vary: 'Origin',
  };

  if (!origin) return headers;
  if (allowed.includes(origin) || allowed.includes('*')) {
    headers['Access-Control-Allow-Origin'] = origin;
  }
  return headers;
}

/** Réponse JSON avec CORS. */
export function json(
  request: Request,
  env: Env,
  body: unknown,
  status = 200,
): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      'Content-Type': 'application/json; charset=utf-8',
      ...corsHeaders(request, env),
    },
  });
}

/** Étiquette l'utilisateur (IP) pour le rate limiting. */
export function clientKey(request: Request): string {
  return request.headers.get('CF-Connecting-IP') ?? 'unknown';
}

/**
 * Rate limiting simple : fenêtre fixe en mémoire, par isolate.
 *
 * Approximatif (chaque isolate Cloudflare a son propre compteur) mais suffisant
 * comme garde-fou applicatif. Pour une limite globale, ajouter une règle
 * « Rate limiting » sur la zone dans le tableau de bord Cloudflare.
 */
const buckets = new Map<string, { count: number; resetAt: number }>();

export function checkRateLimit(
  request: Request,
  env: Env,
): { allowed: true } | { allowed: false; retryAfter: number } {
  const limit = Number.parseInt(env.RATE_LIMIT_PER_MINUTE ?? '100', 10);
  if (!Number.isFinite(limit) || limit <= 0) return { allowed: true };

  const key = clientKey(request);
  const now = Date.now();
  const bucket = buckets.get(key);

  if (!bucket || bucket.resetAt <= now) {
    buckets.set(key, { count: 1, resetAt: now + 60_000 });
    return { allowed: true };
  }

  bucket.count += 1;
  if (bucket.count > limit) {
    return { allowed: false, retryAfter: Math.ceil((bucket.resetAt - now) / 1000) };
  }
  return { allowed: true };
}

/**
 * Vérifie la clé publique (soft gate).
 *
 * Si `CLIENT_API_KEY` n'est pas configurée, le Worker reste ouvert (rollout) :
 * c'est la clé du fournisseur IA, côté secret, qui protège réellement le service.
 */
export function isAuthorized(request: Request, env: Env): boolean {
  const expected = env.CLIENT_API_KEY;
  if (!expected) return true;
  return request.headers.get('X-API-Key') === expected;
}
