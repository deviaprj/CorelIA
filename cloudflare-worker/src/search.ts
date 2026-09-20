import { json } from './http';
import type { Env, SearchResult } from './types';

const ENDPOINTS = [
  'https://html.duckduckgo.com/html/',
  'https://lite.duckduckgo.com/lite/',
];

const USER_AGENT =
  'Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 (KHTML, like Gecko) ' +
  'Chrome/124.0 Mobile Safari/537.36';

const MAX_HTML_BYTES = 500_000;
const DEFAULT_LIMIT = 5;
const CACHE_TTL_SECONDS = 900;

/** GET /search?q=…&limit=… — recherche web côté serveur (sans CORS navigateur). */
export async function handleSearch(request: Request, env: Env): Promise<Response> {
  const url = new URL(request.url);
  const query = (url.searchParams.get('q') ?? '').trim();
  if (!query) {
    return json(request, env, { error: 'Paramètre "q" requis.' }, 400);
  }

  const limit = clamp(Number.parseInt(url.searchParams.get('limit') ?? '', 10) || DEFAULT_LIMIT, 1, 10);

  for (const endpoint of ENDPOINTS) {
    try {
      const target = `${endpoint}?q=${encodeURIComponent(query)}`;
      const response = await fetch(target, {
        headers: {
          'User-Agent': USER_AGENT,
          Accept: 'text/html,application/xhtml+xml',
        },
        // Le cache Cloudflare absorbe les requêtes identiques.
        cf: { cacheTtl: CACHE_TTL_SECONDS, cacheEverything: true },
      } as RequestInit);

      if (!response.ok) continue;
      const html = (await response.text()).slice(0, MAX_HTML_BYTES);
      const results = parseResults(html, limit);
      if (results.length > 0) return json(request, env, { query, results });
    } catch {
      // Endpoint indisponible : on tente le suivant.
    }
  }

  return json(request, env, { query, results: [] });
}

function parseResults(html: string, limit: number): SearchResult[] {
  const results: SearchResult[] = [];

  const withSnippet = RegExp(
    '<a[^>]*class="result__a"[^>]*href="([^"]+)"[^>]*>(.*?)</a>.*?' +
      '<a[^>]*class="result__snippet"[^>]*>(.*?)</a>',
    'gis',
  );
  for (const match of html.matchAll(withSnippet)) {
    if (results.length >= limit) break;
    results.push({
      title: clean(match[2] ?? 'Sans titre'),
      url: decodeDdgUrl(match[1] ?? '') ?? (match[1] ?? ''),
      snippet: clean(match[3] ?? ''),
    });
  }

  if (results.length === 0) {
    const withoutSnippet = RegExp(
      '<a[^>]*class="result__a"[^>]*href="(https?://[^"]+)"[^>]*>(.*?)</a>',
      'gis',
    );
    for (const match of html.matchAll(withoutSnippet)) {
      if (results.length >= limit) break;
      const url = match[1] ?? '';
      if (!url || url.includes('duckduckgo.com')) continue;
      results.push({ title: clean(match[2] ?? 'Sans titre'), url, snippet: '' });
    }
  }

  return results;
}

/** Décode une URL de redirection DuckDuckGo (`/l/?uddg=…`). */
function decodeDdgUrl(raw: string): string | null {
  if (!raw) return null;
  if (raw.startsWith('http')) return raw;

  for (const pattern of [/\?uddg=([^&]+)/, /[?&]u=([^&]+)/]) {
    const match = raw.match(pattern);
    if (match?.[1]) {
      try {
        return decodeURIComponent(match[1]);
      } catch {
        // Valeur mal encodée : on ignore.
      }
    }
  }

  if (raw.startsWith('//')) return decodeDdgUrl(`/${raw.slice(2)}`);
  return null;
}

function clean(html: string): string {
  return html
    .replace(/<[^>]+>/g, '')
    .replace(/&nbsp;/g, ' ')
    .replace(/&amp;/g, '&')
    .replace(/&lt;/g, '<')
    .replace(/&gt;/g, '>')
    .replace(/&quot;/g, '"')
    .replace(/&#39;/g, "'")
    .replace(/\s+/g, ' ')
    .trim();
}

function clamp(value: number, min: number, max: number): number {
  return Math.min(Math.max(value, min), max);
}
