/**
 * LLM Proxy Module
 * 
 * Routes chat requests through the provider chain:
 * 1. DeepSeek API (deepseek-v4-flash) — primary, highest quality
 * 2. Workers AI (@cf/meta/llama-3.2-11b-vision-instruct) — cheap fallback
 * 
 * Supports SSE streaming (text/event-stream) and non-streaming responses.
 */

// ── Types ─────────────────────────────────────────────────────────────────

interface ChatMessage {
  role: string;
  content: string;
}

interface LlmOptions {
  model?: string;
  temperature?: number;
  max_tokens?: number;
}

// ── Workers AI ───────────────────────────────────────────────────────────

/**
 * Stream a chat completion using Cloudflare Workers AI.
 * Uses @cf/meta/llama-3.2-11b-vision-instruct by default.
 */
async function* streamWorkersAI(
  messages: ChatMessage[],
  ai: Ai,
  options: LlmOptions = {}
): AsyncGenerator<string> {
  const model = options.model || '@cf/meta/llama-3.2-11b-vision-instruct';
  
  const stream = (await ai.run(model as any, {
    messages: messages.map(m => ({
      role: m.role as any,
      content: m.content,
    })),
    temperature: options.temperature ?? 0.7,
    max_tokens: options.max_tokens ?? 4096,
    stream: true,
  })) as ReadableStream;

  const reader = stream.getReader();
  const decoder = new TextDecoder();
  
  try {
    while (true) {
      const { done, value } = await reader.read();
      if (done) break;
      const text = decoder.decode(value, { stream: true });
      for (const line of text.split('\n')) {
        const trimmed = line.trim();
        if (trimmed.startsWith('data: ')) {
          try {
            const data = JSON.parse(trimmed.slice(6));
            if (data.response) {
              yield `data: ${JSON.stringify({ content: data.response })}\n\n`;
            }
          } catch {
            // Skip unparseable lines
          }
        }
      }
    }
  } finally {
    reader.releaseLock();
  }
}

/**
 * Non-streaming Workers AI completion.
 */
async function completeWorkersAI(
  messages: ChatMessage[],
  ai: Ai,
  options: LlmOptions = {}
): Promise<string> {
  const model = options.model || '@cf/meta/llama-3.2-11b-vision-instruct';
  
  const result = (await ai.run(model as any, {
    messages: messages.map(m => ({
      role: m.role as any,
      content: m.content,
    })),
    temperature: options.temperature ?? 0.7,
    max_tokens: options.max_tokens ?? 4096,
  })) as { response?: string };

  return result.response || '';
}

// ── DeepSeek API ─────────────────────────────────────────────────────────

/**
 * Stream a chat completion using the DeepSeek API.
 * Uses deepseek-v4-flash by default (free tier).
 */
async function* streamDeepSeek(
  messages: ChatMessage[],
  apiKey: string,
  options: LlmOptions = {}
): AsyncGenerator<string> {
  const model = options.model || 'deepseek-v4-pro';
  
  const response = await fetch('https://api.deepseek.com/v1/chat/completions', {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      'Authorization': `Bearer ${apiKey}`,
    },
    body: JSON.stringify({
      model,
      messages,
      temperature: options.temperature ?? 0.7,
      max_tokens: options.max_tokens ?? 4096,
      stream: true,
    }),
  });

  if (!response.ok) {
    const errorBody = await response.text().catch(() => '');
    throw new Error(`DeepSeek API error ${response.status}: ${errorBody}`);
  }

  const reader = response.body?.getReader();
  if (!reader) throw new Error('No response body');

  const decoder = new TextDecoder();
  let buffer = '';

  try {
    while (true) {
      const { done, value } = await reader.read();
      if (done) break;
      
      buffer += decoder.decode(value, { stream: true });
      const lines = buffer.split('\n');
      buffer = lines.pop() || '';

      for (const line of lines) {
        if (line.startsWith('data: ')) {
          const chunk = line.slice(6).trim();
          if (chunk === '[DONE]') return;
          yield `data: ${chunk}\n\n`;
        }
      }
    }
  } finally {
    reader.releaseLock();
  }
}

/**
 * Non-streaming DeepSeek completion.
 */
async function completeDeepSeek(
  messages: ChatMessage[],
  apiKey: string,
  options: LlmOptions = {}
): Promise<string> {
  const model = options.model || 'deepseek-v4-pro';

  const response = await fetch('https://api.deepseek.com/v1/chat/completions', {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      'Authorization': `Bearer ${apiKey}`,
    },
    body: JSON.stringify({
      model,
      messages,
      temperature: options.temperature ?? 0.7,
      max_tokens: options.max_tokens ?? 4096,
      stream: false,
    }),
  });

  if (!response.ok) {
    throw new Error(`DeepSeek API error ${response.status}`);
  }

  const data = await response.json() as { choices?: Array<{ message?: { content?: string } }> };
  return data.choices?.[0]?.message?.content || '';
}

// ── OpenRouter API (ultimate fallback, free models) ─────────────────────

/**
 * Stream via OpenRouter using a free model as last resort.
 * Uses deepseek/deepseek-r1:free by default (free tier).
 */
async function* streamOpenRouter(
  messages: ChatMessage[],
  apiKey: string,
  options: LlmOptions = {}
): AsyncGenerator<string> {
  const model = options.model || 'deepseek/deepseek-r1:free';

  const response = await fetch('https://openrouter.ai/api/v1/chat/completions', {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      'Authorization': `Bearer ${apiKey}`,
      'HTTP-Referer': 'https://zentic.fr',
      'X-Title': 'CorelIA API',
    },
    body: JSON.stringify({
      model,
      messages,
      temperature: options.temperature ?? 0.7,
      max_tokens: options.max_tokens ?? 4096,
      stream: true,
    }),
  });

  if (!response.ok) {
    throw new Error(`OpenRouter API error ${response.status}`);
  }

  const reader = response.body?.getReader();
  if (!reader) throw new Error('No response body');

  const decoder = new TextDecoder();
  let buffer = '';

  try {
    while (true) {
      const { done, value } = await reader.read();
      if (done) break;
      buffer += decoder.decode(value, { stream: true });
      const lines = buffer.split('\n');
      buffer = lines.pop() || '';
      for (const line of lines) {
        if (line.startsWith('data: ')) {
          const chunk = line.slice(6).trim();
          if (chunk === '[DONE]') return;
          yield `data: ${chunk}\n\n`;
        }
      }
    }
  } finally {
    reader.releaseLock();
  }
}

// ── Main routing logic ───────────────────────────────────────────────────

/**
 * Intelligent routing: each model goes to its best provider.
 * 
 * - deepseek-* → DeepSeek API directly
 * - at-cf models → Workers AI directly  
 * - openrouter models (with slash) → OpenRouter directly
 * - auto / unspecified → try DeepSeek, then Workers AI, then OpenRouter
 */
export async function* routeChatCompletion(
  messages: ChatMessage[],
  env: {
    AI: Ai;
    DEEPSEEK_API_KEY?: string;
    OPENROUTER_API_KEY?: string;
  },
  options: LlmOptions = {}
): AsyncGenerator<string> {
  const model = options.model || '';

  // ── Direct routing: respect the client's model choice ──
  if (model.startsWith('deepseek-') && env.DEEPSEEK_API_KEY) {
    yield* streamDeepSeek(messages, env.DEEPSEEK_API_KEY, options);
    return;
  }
  if (model.startsWith('@cf/')) {
    yield* streamWorkersAI(messages, env.AI, options);
    return;
  }
  if (model.includes('/') && env.OPENROUTER_API_KEY) {
    yield* streamOpenRouter(messages, env.OPENROUTER_API_KEY, options);
    return;
  }

  // ── Auto mode: intelligent fallback chain ──
  const errors: string[] = [];

  // 1. DeepSeek — best general text quality
  if (env.DEEPSEEK_API_KEY) {
    try {
      yield* streamDeepSeek(messages, env.DEEPSEEK_API_KEY, options);
      return;
    } catch (e: unknown) {
      const msg = e instanceof Error ? e.message : String(e);
      errors.push(`DeepSeek: ${msg}`);
    }
  }

  // 2. Workers AI — vision, cheap fallback
  try {
    yield* streamWorkersAI(messages, env.AI, options);
    return;
  } catch (e: unknown) {
    const msg = e instanceof Error ? e.message : String(e);
    errors.push(`Workers AI: ${msg}`);
  }

  // 3. OpenRouter — ultimate safety net
  if (env.OPENROUTER_API_KEY) {
    try {
      yield* streamOpenRouter(messages, env.OPENROUTER_API_KEY, options);
      return;
    } catch (e: unknown) {
      const msg = e instanceof Error ? e.message : String(e);
      errors.push(`OpenRouter: ${msg}`);
    }
  }

  throw new Error(`All providers exhausted: ${errors.join('; ')}`);
}

/**
 * Non-streaming version of the routed completion.
 */
export async function routeChatCompletionSync(
  messages: ChatMessage[],
  env: {
    AI: Ai;
    DEEPSEEK_API_KEY?: string;
    OPENROUTER_API_KEY?: string;
  },
  options: LlmOptions = {}
): Promise<string> {
  // 1. DeepSeek
  if (env.DEEPSEEK_API_KEY) {
    try {
      return await completeDeepSeek(messages, env.DEEPSEEK_API_KEY, options);
    } catch { /* fall through */ }
  }

  // 2. Workers AI
  try {
    return await completeWorkersAI(messages, env.AI, options);
  } catch { /* fall through */ }

  // 3. OpenRouter (free models)
  if (env.OPENROUTER_API_KEY) {
    try {
      const response = await fetch('https://openrouter.ai/api/v1/chat/completions', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'Authorization': `Bearer ${env.OPENROUTER_API_KEY}`,
          'HTTP-Referer': 'https://zentic.fr',
          'X-Title': 'CorelIA API',
        },
        body: JSON.stringify({
          model: options.model || 'deepseek/deepseek-r1:free',
          messages,
          temperature: options.temperature ?? 0.7,
          max_tokens: options.max_tokens ?? 4096,
        }),
      });
      if (response.ok) {
        const data = await response.json() as { choices?: Array<{ message?: { content?: string } }> };
        return data.choices?.[0]?.message?.content || '';
      }
    } catch { /* fall through */ }
  }

  throw new Error('All LLM providers failed');
}
