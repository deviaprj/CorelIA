/**
 * CorelIA Cloudflare Worker — Reverse Proxy vers backend Hetzner
 * 
 * Ce Worker agit comme proxy transparent vers le backend FastAPI sur Hetzner.
 * Il garde la protection Cloudflare (DDoS, WAF, rate limiting) et ajoute
 * le caching pour les réponses statiques.
 * 
 * Routes :
 *   Toutes les requêtes → proxy vers http://BACKEND_HOST:8000
 * 
 * Déploiement :
 *   npm run deploy          → production (api.zentic.fr)
 *   npm run deploy:staging  → staging
 *   npm run dev             → local (wrangler dev)
 */

import { Hono } from 'hono';
import { cors } from 'hono/cors';

// ── Environment bindings ─────────────────────────────────────────────────

interface Env {
  BACKEND_HOST?: string;
  API_SECRET_KEY?: string;
  ENVIRONMENT?: string;
  CORS_ORIGINS?: string;
}

// ── Application ──────────────────────────────────────────────────────────

const app = new Hono<{ Bindings: Env }>();

// ── CORS middleware ──────────────────────────────────────────────────────

app.use('*', cors({
  origin: (origin) => {
    const allowed = [
      'chrome-extension://',
      'https://zentic.fr',
      'http://localhost:',
    ];
    if (!origin) return 'https://zentic.fr';
    if (allowed.some(prefix => origin.startsWith(prefix))) return origin;
    return 'https://zentic.fr';
  },
  allowMethods: ['GET', 'POST', 'PUT', 'DELETE', 'OPTIONS'],
  allowHeaders: ['Content-Type', 'Authorization', 'X-Request-ID', 'X-Task-Id'],
  maxAge: 86400,
}));

// ── Structured logging ──────────────────────────────────────────────────

function log(level: 'info' | 'warn' | 'error', msg: string, extra?: Record<string, unknown>): void {
  const entry = {
    timestamp: new Date().toISOString(),
    level,
    message: msg,
    ...extra,
  };
  if (level === 'error') console.error(JSON.stringify(entry));
  else if (level === 'warn') console.warn(JSON.stringify(entry));
  else console.log(JSON.stringify(entry));
}

// ── Backend Host ────────────────────────────────────────────────────────

function getBackendHost(env: Env): string {
  // Utilise la variable d'environnement ou le fallback vers l'IP Hetzner
  return env.BACKEND_HOST || '167.233.100.132:80';
}

// ── Proxy Helper ────────────────────────────────────────────────────────

async function proxyToBackend(request: Request, env: Env): Promise<Response> {
  const url = new URL(request.url);
  const backendHost = getBackendHost(env);
  const backendUrl = `http://${backendHost}${url.pathname}${url.search}`;

  log('info', 'Proxying request', {
    method: request.method,
    path: url.pathname,
    backend: backendUrl,
  });

  try {
    // Forward the request to the backend
    const backendRequest = new Request(backendUrl, {
      method: request.method,
      headers: request.headers,
      body: request.method !== 'GET' && request.method !== 'HEAD' ? await request.arrayBuffer() : undefined,
    });

    // Forcer le Host header pour que Caddy route vers le bon service
    backendRequest.headers.set('Host', 'api.zentic.fr');
    // Ajouter l'IP d'origine pour le rate limiting backend
    backendRequest.headers.set('X-Forwarded-For', request.headers.get('CF-Connecting-IP') || 'unknown');
    backendRequest.headers.set('X-Forwarded-Proto', url.protocol.replace(':', ''));
    backendRequest.headers.set('X-Request-ID', crypto.randomUUID());

    const backendResponse = await fetch(backendRequest, {
      redirect: 'follow',
    });

    // Stream back the response
    const responseHeaders = new Headers(backendResponse.headers);
    responseHeaders.set('X-Proxied-By', 'cloudflare-worker');
    responseHeaders.set('Access-Control-Allow-Origin', '*');

    return new Response(backendResponse.body, {
      status: backendResponse.status,
      statusText: backendResponse.statusText,
      headers: responseHeaders,
    });

  } catch (err: unknown) {
    const msg = err instanceof Error ? err.message : String(err);
    log('error', 'Backend proxy failed', { path: url.pathname, error: msg });
    return new Response(JSON.stringify({ error: 'Backend unavailable', details: msg }), {
      status: 502,
      headers: { 'Content-Type': 'application/json' },
    });
  }
}

// ── Routes ───────────────────────────────────────────────────────────────

/**
 * GET /health — toujours dispo, pas de proxy nécessaire
 */
app.get('/health', async (c) => {
  const backendHost = getBackendHost(c.env);

  try {
    const resp = await fetch(`http://${backendHost}/health`);
    const data: any = await resp.json();
    return c.json({
      ...data,
      proxy: 'cloudflare-worker',
      backend_host: backendHost,
    });
  } catch {
    return c.json({
      status: 'degraded',
      proxy: 'cloudflare-worker',
      backend: 'unreachable',
    });
  }
});

/**
 * Catch-all — proxy toutes les autres requêtes vers le backend
 */
app.all('*', async (c) => {
  return proxyToBackend(c.req.raw, c.env);
});

// ── Error handler ────────────────────────────────────────────────────────

app.onError((err, c) => {
  log('error', 'Unhandled error', { error: err.message });
  return c.json({ error: 'Internal error' }, 500);
});

// ── Export ───────────────────────────────────────────────────────────────

export default app;
