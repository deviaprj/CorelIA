import { handleChat } from './chat';
import { checkRateLimit, corsHeaders, isAuthorized, json } from './http';
import { handleSearch } from './search';
import type { Env } from './types';

/**
 * Passerelle IA CorelIA — `api.zentic.fr`
 *
 *   POST /chat    réponse IA en streaming SSE (format OpenAI)
 *   GET  /search  recherche web DuckDuckGo
 *   GET  /health  état du service
 *
 * Les clés des fournisseurs IA restent ici (secrets Wrangler) : l'application
 * mobile n'embarque qu'une clé publique de garde (`CLIENT_API_KEY`).
 */
export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    const url = new URL(request.url);

    if (request.method === 'OPTIONS') {
      return new Response(null, { status: 204, headers: corsHeaders(request, env) });
    }

    if (url.pathname === '/health') {
      return json(request, env, {
        status: 'ok',
        service: 'corelia-api',
        provider: env.DEEPSEEK_API_KEY
          ? 'deepseek'
          : env.AI
            ? 'workers-ai'
            : 'none',
      });
    }

    if (!isAuthorized(request, env)) {
      return json(request, env, { error: 'Clé API invalide.' }, 401);
    }

    const rate = checkRateLimit(request, env);
    if (!rate.allowed) {
      return new Response(JSON.stringify({ error: 'Trop de requêtes.' }), {
        status: 429,
        headers: {
          'Content-Type': 'application/json; charset=utf-8',
          'Retry-After': String(rate.retryAfter),
          ...corsHeaders(request, env),
        },
      });
    }

    if (url.pathname === '/chat' && request.method === 'POST') {
      return handleChat(request, env);
    }

    if (url.pathname === '/search' && request.method === 'GET') {
      return handleSearch(request, env);
    }

    return json(request, env, { error: 'Route inconnue.' }, 404);
  },
} satisfies ExportedHandler<Env>;
