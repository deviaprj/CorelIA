/**
 * Input Sanitization Module
 * 
 * Protects against prompt injection, XSS, and malformed input.
 * All user-provided strings pass through these sanitizers before
 * being used in LLM prompts, stored, or returned in responses.
 */

// ── XSS / HTML injection ─────────────────────────────────────────────────

const HTML_ESCAPE_MAP: Record<string, string> = {
  '&': '&amp;',
  '<': '&lt;',
  '>': '&gt;',
  '"': '&quot;',
  "'": '&#x27;',
};

/** Escape HTML entities to prevent XSS in rendered output. */
export function escapeHtml(str: string): string {
  return str.replace(/[&<>"']/g, (ch) => HTML_ESCAPE_MAP[ch] || ch);
}

// ── Prompt injection protection ──────────────────────────────────────────

/**
 * Patterns that indicate a prompt injection attempt.
 * Based on OWASP LLM Top 10 and common jailbreak patterns.
 */
const PROMPT_INJECTION_PATTERNS: Array<{ pattern: RegExp; severity: 'high' | 'medium' }> = [
  // System prompt override attempts
  { pattern: /ignore\s+(all\s+)?(previous|above|prior)\s+(instructions?|prompts?|rules?|directives?)/i, severity: 'high' },
  { pattern: /forget\s+(all\s+)?(previous|above|prior)\s+(instructions?|prompts?|rules?)/i, severity: 'high' },
  { pattern: /you\s+are\s+now\s+(DAN|jailbroken|uncensored|unfiltered)/i, severity: 'high' },
  { pattern: /pretend\s+(you\s+are|to\s+be|that\s+you)/i, severity: 'high' },
  { pattern: /act\s+as\s+(if\s+you|a\s+different)/i, severity: 'medium' },
  { pattern: /new\s+system\s+(prompt|message|instruction)/i, severity: 'high' },
  
  // Role-play jailbreaks
  { pattern: /from\s+now\s+on\s+(you|your)\s+(are|will\s+be|role\s+is)/i, severity: 'medium' },
  { pattern: /do\s+not\s+(refuse|reject|decline|follow\s+(your|the)\s+(guidelines?|rules?|policy))/i, severity: 'medium' },
  
  // Token smuggling attempts
  { pattern: /<\|im_start\|>/i, severity: 'high' },
  { pattern: /<\|im_end\|>/i, severity: 'high' },
  { pattern: /<\/?system>/, severity: 'high' },
  { pattern: /\[INST\].*\[\/INST\]/is, severity: 'medium' },
  
  // Code injection via markdown
  { pattern: /```(system|instruction|prompt)/i, severity: 'medium' },
];

/** Maximum length for user messages (prevents DoS). */
const MAX_MESSAGE_LENGTH = 32000;

/** Maximum length for a single user input field. */
const MAX_INPUT_LENGTH = 16000;

/**
 * Sanitize a user message for LLM consumption.
 * 
 * - Truncates overly long messages
 * - Detects prompt injection patterns
 * - Strips control characters
 * - Returns the sanitized message and a list of warnings
 */
export function sanitizeUserMessage(raw: string): { 
  sanitized: string; 
  warnings: string[];
  blocked: boolean;
} {
  if (!raw || typeof raw !== 'string') {
    return { sanitized: '', warnings: ['Empty or invalid input'], blocked: true };
  }

  const warnings: string[] = [];
  let sanitized = raw;

  // 1. Strip null bytes and other control characters (keep newlines, tabs)
  sanitized = sanitized.replace(/[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]/g, '');

  // 2. Truncate to max length
  if (sanitized.length > MAX_MESSAGE_LENGTH) {
    warnings.push(`Message truncated from ${sanitized.length} to ${MAX_MESSAGE_LENGTH} characters`);
    sanitized = sanitized.substring(0, MAX_MESSAGE_LENGTH);
  }

  // 3. Check for prompt injection patterns
  for (const { pattern, severity } of PROMPT_INJECTION_PATTERNS) {
    if (pattern.test(sanitized)) {
      warnings.push(`Potential prompt injection detected (${severity} severity)`);
      if (severity === 'high') {
        return { sanitized, warnings, blocked: true };
      }
    }
  }

  return { sanitized, warnings, blocked: false };
}

/**
 * Sanitize a single field value (URL, filename, CSS selector, etc.).
 */
export function sanitizeField(value: string, fieldType: 'url' | 'filename' | 'selector' | 'text'): string {
  if (!value) return '';

  let sanitized = value.trim();

  switch (fieldType) {
    case 'url':
      // Validate URL format; block javascript: and data: schemes
      try {
        const url = new URL(sanitized);
        if (url.protocol === 'javascript:' || url.protocol === 'data:') {
          return '';
        }
        return url.toString();
      } catch {
        // Not a valid URL — try prepending https://
        if (/^[\w.-]+\.[a-z]{2,}/i.test(sanitized)) {
          return `https://${sanitized}`;
        }
        return '';
      }

    case 'filename':
      // Strip path traversal and dangerous characters
      sanitized = sanitized.replace(/\.\./g, '').replace(/[\/\\:*?"<>|]/g, '_');
      if (sanitized.length > 255) sanitized = sanitized.substring(0, 255);
      return sanitized || 'untitled';

    case 'selector':
      // Basic CSS selector sanitization: strip script-like content  
      sanitized = sanitized.replace(/<\/?script[^>]*>/gi, '');
      if (sanitized.length > 512) sanitized = sanitized.substring(0, 512);
      return sanitized;

    case 'text':
    default:
      // General text: strip HTML tags, limit length
      sanitized = sanitized.replace(/<[^>]*>/g, '');
      if (sanitized.length > MAX_INPUT_LENGTH) {
        sanitized = sanitized.substring(0, MAX_INPUT_LENGTH);
      }
      return sanitized;
  }
}

/**
 * Sanitize a complete chat request body.
 */
export interface SanitizedChatRequest {
  messages: Array<{ role: string; content: string }>;
  model?: string;
  stream?: boolean;
  temperature?: number;
  max_tokens?: number;
}

export function sanitizeChatRequest(body: Record<string, unknown>): {
  sanitized: SanitizedChatRequest | null;
  warnings: string[];
  error?: string;
} {
  const warnings: string[] = [];
  
  if (!body.messages || !Array.isArray(body.messages)) {
    return { sanitized: null, warnings, error: 'Missing or invalid "messages" field' };
  }

  if (body.messages.length === 0) {
    return { sanitized: null, warnings, error: 'Messages array cannot be empty' };
  }

  if (body.messages.length > 100) {
    return { sanitized: null, warnings, error: 'Too many messages (max 100)' };
  }

  const messages: Array<{ role: string; content: string }> = [];
  for (let i = 0; i < body.messages.length; i++) {
    const msg = body.messages[i] as Record<string, unknown>;
    
    if (!msg.role || typeof msg.role !== 'string') {
      return { sanitized: null, warnings, error: `Message ${i}: missing or invalid "role"` };
    }
    const role = msg.role.toLowerCase();
    if (!['system', 'user', 'assistant', 'tool'].includes(role)) {
      return { sanitized: null, warnings, error: `Message ${i}: invalid role "${msg.role}"` };
    }

    if (msg.content === undefined || msg.content === null) {
      return { sanitized: null, warnings, error: `Message ${i}: missing "content"` };
    }

    let content: string;
    if (typeof msg.content === 'string') {
      // Sanitize user messages more strictly
      if (role === 'user') {
        const result = sanitizeUserMessage(msg.content);
        if (result.blocked) {
          return { sanitized: null, warnings: result.warnings, error: 'Message blocked by content filter' };
        }
        content = result.sanitized;
        warnings.push(...result.warnings);
      } else {
        content = msg.content.substring(0, MAX_MESSAGE_LENGTH);
      }
    } else if (Array.isArray(msg.content)) {
      // Vision content array — validate structure
      const parts: Array<Record<string, unknown>> = [];
      for (const part of msg.content as Array<Record<string, unknown>>) {
        if (part.type === 'text' && typeof part.text === 'string') {
          parts.push({ type: 'text', text: part.text.substring(0, MAX_INPUT_LENGTH) });
        } else if (part.type === 'image_url' && typeof part.image_url === 'object') {
          parts.push(part);
        }
      }
      content = JSON.stringify(parts);
    } else {
      return { sanitized: null, warnings, error: `Message ${i}: invalid content type` };
    }

    messages.push({ role, content });
  }

  // Validate and clamp optional fields
  const model = typeof body.model === 'string' ? body.model.substring(0, 100) : undefined;
  const stream = typeof body.stream === 'boolean' ? body.stream : true;
  let temperature = typeof body.temperature === 'number' ? body.temperature : 0.7;
  temperature = Math.max(0, Math.min(2, temperature));
  let max_tokens = typeof body.max_tokens === 'number' ? body.max_tokens : undefined;
  if (max_tokens !== undefined) {
    max_tokens = Math.max(1, Math.min(8192, Math.floor(max_tokens)));
  }

  return {
    sanitized: { messages, model, stream, temperature, max_tokens },
    warnings,
  };
}
