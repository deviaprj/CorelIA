/**
 * CorelIA Cloudflare Worker — API REST pour le chatbot
 * 
 * Endpoints:
 *   POST /chat             — Chat streaming (SSE) via Workers AI / DeepSeek / OpenRouter
 *   GET  /search           — Recherche web (DuckDuckGo)
 *   GET  /scrape           — Extraction de contenu web (HTMLRewriter)
 *   GET  /health           — Health check
 * 
 * Sécurité:
 *   - Rate limiting (Cloudflare built-in + in-code fallback)
 *   - Input sanitization (prompt injection, XSS)
 *   - API key authentication (API_SECRET_KEY)
 *   - CORS configuré pour l'extension Chrome et le Flutter app
 * 
 * Déploiement:
 *   npm run deploy          → production (api.corelia.app)
 *   npm run deploy:staging  → staging
 *   npm run dev             → local (wrangler dev)
 */

import { Hono } from 'hono';
import { cors } from 'hono/cors';
import { sanitizeChatRequest, sanitizeField, escapeHtml } from './sanitize';
import { routeChatCompletion } from './llm';
import { scrapeUrl, searchWeb } from './scrape';
import { checkRateLimit, getRateLimitKey, cleanupRateLimits } from './rate_limit';

// ── Environment bindings ─────────────────────────────────────────────────

interface Env {
  AI: Ai;
  DEEPSEEK_API_KEY?: string;
  OPENROUTER_API_KEY?: string;
  API_SECRET_KEY?: string;
  ENVIRONMENT?: string;
  CORS_ORIGINS?: string;
}

// ── Application ──────────────────────────────────────────────────────────

const app = new Hono<{ Bindings: Env }>();

// ── CORS middleware ──────────────────────────────────────────────────────

app.use('*', cors({
  origin: (origin) => {
    // Allow Chrome extensions, localhost, and the main domain
    const allowed = [
      'chrome-extension://',
      'https://corelia.app',
      'http://localhost:',
    ];
    if (!origin) return '*';
    if (allowed.some(prefix => origin.startsWith(prefix))) return origin;
    return 'https://corelia.app';
  },
  allowMethods: ['GET', 'POST', 'OPTIONS'],
  allowHeaders: ['Content-Type', 'Authorization', 'X-Request-ID'],
  maxAge: 86400,
}));

// ── Authentication middleware ────────────────────────────────────────────

/**
 * Verify the API secret key from the Authorization header.
 * Uses constant-time comparison to prevent timing attacks.
 */
function verifyApiKey(request: Request, secret?: string): boolean {
  if (!secret) return true; // No secret configured — allow all (dev mode)
  
  const authHeader = request.headers.get('Authorization') || '';
  if (!authHeader.startsWith('Bearer ')) return false;
  
  const token = authHeader.slice(7);
  
  // Constant-time comparison
  const secretBytes = new TextEncoder().encode(secret);
  const tokenBytes = new TextEncoder().encode(token);
  
  if (secretBytes.length !== tokenBytes.length) return false;
  
  let result = 0;
  for (let i = 0; i < secretBytes.length; i++) {
    result |= secretBytes[i] ^ tokenBytes[i];
  }
  return result === 0;
}

// ── Structured logging ──────────────────────────────────────────────────

function log(level: 'info' | 'warn' | 'error', msg: string, extra?: Record<string, unknown>): void {
  const entry = {
    timestamp: new Date().toISOString(),
    level,
    message: msg,
    ...extra,
  };
  if (level === 'error') {
    console.error(JSON.stringify(entry));
  } else if (level === 'warn') {
    console.warn(JSON.stringify(entry));
  } else {
    console.log(JSON.stringify(entry));
  }
}

// ── Routes ───────────────────────────────────────────────────────────────

/**
 * GET /health
 * Health check — always available, no auth required.
 */
app.get('/health', (c) => {
  return c.json({
    status: 'ok',
    environment: c.env.ENVIRONMENT || 'production',
    timestamp: new Date().toISOString(),
    version: '1.0.0',
  });
});

/**
 * POST /chat
 * Streams chat completions via SSE (text/event-stream).
 * 
 * Body: { messages: [...], model?, stream?, temperature?, max_tokens? }
 * Headers: Authorization: Bearer <API_SECRET_KEY>
 */
app.post('/chat', async (c) => {
  const startTime = Date.now();

  // ── Rate limiting ──
  cleanupRateLimits();
  const rlKey = getRateLimitKey(c.req.raw);
  const rl = checkRateLimit(rlKey, 100, 60); // 100 req/min
  if (!rl.allowed) {
    log('warn', 'Rate limit exceeded', { ip: rlKey });
    return c.json({ error: 'Too many requests', retryAfter: Math.ceil((rl.resetAt - Date.now()) / 1000) }, 429);
  }

  // ── Auth ──
  if (!verifyApiKey(c.req.raw, c.env.API_SECRET_KEY)) {
    log('warn', 'Unauthorized request', { path: '/chat' });
    return c.json({ error: 'Unauthorized' }, 401);
  }

  // ── Parse & sanitize body ──
  let body: Record<string, unknown>;
  try {
    body = await c.req.json();
  } catch {
    return c.json({ error: 'Invalid JSON body' }, 400);
  }

  const { sanitized, warnings, error } = sanitizeChatRequest(body);
  if (error || !sanitized) {
    log('warn', 'Chat request blocked', { error, warnings });
    return c.json({ error: error || 'Invalid request' }, 400);
  }
  if (warnings.length > 0) {
    log('info', 'Chat request warnings', { warnings });
  }

  // ── Non-streaming path ──
  if (sanitized.stream === false) {
    try {
      const content = await collectStream(
        routeChatCompletion(
          sanitized.messages,
          {
            AI: c.env.AI,
            DEEPSEEK_API_KEY: c.env.DEEPSEEK_API_KEY,
            OPENROUTER_API_KEY: c.env.OPENROUTER_API_KEY,
          },
          {
            model: sanitized.model,
            temperature: sanitized.temperature,
            max_tokens: sanitized.max_tokens,
          }
        )
      );

      const duration = Date.now() - startTime;
      log('info', 'Chat completed (non-streaming)', { durationMs: duration, contentLength: content.length });

      return c.json({
        id: crypto.randomUUID(),
        model: sanitized.model || 'auto',
        message: { role: 'assistant', content },
        created_at: new Date().toISOString(),
        usage: { total_tokens: Math.ceil(content.length / 4) },
      });
    } catch (err: unknown) {
      const msg = err instanceof Error ? err.message : String(err);
      log('error', 'Chat completion failed', { error: msg });
      return c.json({ error: 'AI service unavailable. Please try again later.' }, 502);
    }
  }

  // ── Streaming path (SSE) ──
  const encoder = new TextEncoder();

  const stream = new ReadableStream({
    async start(controller) {
      try {
        const generator = routeChatCompletion(
          sanitized.messages,
          {
            AI: c.env.AI,
            DEEPSEEK_API_KEY: c.env.DEEPSEEK_API_KEY,
            OPENROUTER_API_KEY: c.env.OPENROUTER_API_KEY,
          },
          {
            model: sanitized.model,
            temperature: sanitized.temperature,
            max_tokens: sanitized.max_tokens,
          }
        );

        for await (const chunk of generator) {
          controller.enqueue(encoder.encode(chunk));
        }
        controller.enqueue(encoder.encode('data: [DONE]\n\n'));

        const duration = Date.now() - startTime;
        log('info', 'Chat stream completed', { durationMs: duration });
      } catch (err: unknown) {
        const msg = err instanceof Error ? err.message : String(err);
        log('error', 'Chat stream failed', { error: msg });
        controller.enqueue(
          encoder.encode(`data: ${JSON.stringify({ error: 'AI service unavailable' })}\n\n`)
        );
        controller.enqueue(encoder.encode('data: [DONE]\n\n'));
      } finally {
        controller.close();
      }
    },
  });

  return new Response(stream, {
    headers: {
      'Content-Type': 'text/event-stream',
      'Cache-Control': 'no-cache',
      'Connection': 'keep-alive',
      'X-Accel-Buffering': 'no',
      'X-Request-ID': crypto.randomUUID(),
    },
  });
});

/**
 * GET /search?q=...
 * Recherche web via DuckDuckGo (pas de clé API requise).
 */
app.get('/search', async (c) => {
  const q = c.req.query('q');
  if (!q) return c.json({ error: 'Missing query parameter: q' }, 400);

  const query = sanitizeField(q, 'text');
  if (!query) return c.json({ error: 'Invalid query' }, 400);

  try {
    const results = await searchWeb(query, 5);
    log('info', 'Search completed', { query, resultCount: results.length });
    return c.json({
      query,
      results: results.map(r => ({
        title: escapeHtml(r.title),
        url: r.url,
        snippet: escapeHtml(r.snippet),
        source: 'duckduckgo',
      })),
      total_results: results.length,
    });
  } catch (err: unknown) {
    const msg = err instanceof Error ? err.message : String(err);
    log('error', 'Search failed', { query, error: msg });
    return c.json({ error: 'Search service unavailable' }, 502);
  }
});

/**
 * GET /scrape?url=...&selectors=...
 * Extrait le contenu d'une page web.
 */
app.get('/scrape', async (c) => {
  const urlParam = c.req.query('url');
  const selectorsParam = c.req.query('selectors');

  if (!urlParam) return c.json({ error: 'Missing query parameter: url' }, 400);

  const url = sanitizeField(urlParam, 'url');
  if (!url) return c.json({ error: 'Invalid URL' }, 400);

  let selectors: Record<string, string> | undefined;
  if (selectorsParam) {
    try {
      selectors = JSON.parse(selectorsParam);
    } catch {
      return c.json({ error: 'Invalid selectors JSON' }, 400);
    }
  }

  try {
    const result = await scrapeUrl(url, selectors);
    log('info', 'Scrape completed', { url, hasContent: result.textContent.length > 0 });

    if (result.error) {
      return c.json({ error: result.error }, 502);
    }

    return c.json({
      title: result.title,
      url: result.url,
      data: [
        { field: 'metadata', values: [
          { name: 'title', content: result.title },
          { name: 'description', content: result.description || '' },
          { name: 'og:title', content: result.ogTitle || '' },
          { name: 'og:description', content: result.ogDescription || '' },
          { name: 'og:image', content: result.ogImage || '' },
          { name: 'author', content: result.author || '' },
          { name: 'language', content: result.language || '' },
        ]},
        { field: 'headings', values: result.headings.map(h => `${h.level}: ${h.text}`) },
        { field: 'links', values: result.links.map(l => ({ text: l.text, url: l.url })) },
        { field: 'prices', values: result.prices },
        { field: 'content', values: [result.textContent] },
      ],
    });
  } catch (err: unknown) {
    const msg = err instanceof Error ? err.message : String(err);
    log('error', 'Scrape failed', { url, error: msg });
    return c.json({ error: 'Scrape service unavailable' }, 502);
  }
});

/**
 * GET /search_smart?q=...
 * Alias pour compatibilité avec le client Flutter existant.
 * Retourne le même format que /search pour l'instant.
 * Pour la recherche enrichie (vols, hôtels, etc.), utiliser le backend Python.
 */
app.get('/search_smart', async (c) => {
  const q = c.req.query('q');
  if (!q) return c.json({ error: 'Missing query parameter: q' }, 400);

  const query = sanitizeField(q, 'text');
  if (!query) return c.json({ error: 'Invalid query' }, 400);

  try {
    const results = await searchWeb(query, 5);
    return c.json({
      intent: 'general',
      params: { query },
      query,
      results: results.map(r => ({
        type: 'link',
        title: escapeHtml(r.title),
        url: r.url,
        snippet: escapeHtml(r.snippet),
      })),
      sources: results.map(r => ({ url: r.url, title: escapeHtml(r.title) })),
    });
  } catch (err: unknown) {
    const msg = err instanceof Error ? err.message : String(err);
    log('error', 'Smart search failed', { query, error: msg });
    return c.json({ intent: 'general', params: {}, query, results: [], sources: [], error: msg });
  }
});

// ── 404 handler ──────────────────────────────────────────────────────────

app.notFound((c) => {
  return c.json({
    error: 'Not found',
    availableEndpoints: ['/health', '/chat', '/search', '/scrape', '/search_smart'],
  }, 404);
});

// ── Error handler ────────────────────────────────────────────────────────

app.onError((err, c) => {
  log('error', 'Unhandled error', { error: err.message, stack: err.stack });
  return c.json({ error: 'Internal server error' }, 500);
});

// ── Export ───────────────────────────────────────────────────────────────

export default app;

// ── Helpers ──────────────────────────────────────────────────────────────

/**
 * Collect an async generator into a single string.
 */
async function collectStream(generator: AsyncGenerator<string>): Promise<string> {
  let result = '';
  for await (const chunk of generator) {
    // Parse SSE chunks: "data: {\"content\":\"...\"}\n\n"
    if (chunk.startsWith('data: ')) {
      const dataStr = chunk.slice(6).trim();
      if (dataStr === '[DONE]') break;
      try {
        const data = JSON.parse(dataStr);
        result += data.content || '';
      } catch {
        // Skip unparseable chunks
      }
    }
  }
  return result;
}
