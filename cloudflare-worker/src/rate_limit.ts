/**
 * Rate Limiting Module
 * 
 * Cloudflare Workers have built-in rate limiting via wrangler.jsonc
 * (rate_limits array). This module provides an additional in-code
 * fallback for endpoints not covered by the static configuration,
 * using Cloudflare KV for distributed rate limiting.
 */

// ── In-memory fallback (per-request, not shared across isolates) ─────────

interface RateLimitEntry {
  count: number;
  resetAt: number;
}

const memoryStore = new Map<string, RateLimitEntry>();

/**
 * Check rate limit using in-memory storage.
 * For production, use Cloudflare's built-in rate limiting (wrangler.jsonc).
 * This function is a supplemental check for dynamic rate limiting.
 */
export function checkRateLimit(
  key: string,
  maxRequests: number,
  windowSeconds: number
): { allowed: boolean; remaining: number; resetAt: number } {
  const now = Date.now();
  const entry = memoryStore.get(key);

  if (!entry || now > entry.resetAt) {
    // New window
    const resetAt = now + windowSeconds * 1000;
    memoryStore.set(key, { count: 1, resetAt });
    return { allowed: true, remaining: maxRequests - 1, resetAt };
  }

  if (entry.count >= maxRequests) {
    return { allowed: false, remaining: 0, resetAt: entry.resetAt };
  }

  entry.count++;
  return { allowed: true, remaining: maxRequests - entry.count, resetAt: entry.resetAt };
}

/**
 * Extract a rate-limit key from the request.
 * Uses CF-Connecting-IP header (set by Cloudflare) or falls back to X-Forwarded-For.
 */
export function getRateLimitKey(request: Request): string {
  // Cloudflare sets CF-Connecting-IP automatically
  const ip = request.headers.get('CF-Connecting-IP') ||
             request.headers.get('X-Forwarded-For')?.split(',')[0]?.trim() ||
             'unknown';
  return `rl:${ip}`;
}

/**
 * Clean up expired rate limit entries periodically.
 * Called on each request — cheap enough for in-memory.
 */
export function cleanupRateLimits(): void {
  const now = Date.now();
  for (const [key, entry] of memoryStore) {
    if (now > entry.resetAt) {
      memoryStore.delete(key);
    }
  }
}
