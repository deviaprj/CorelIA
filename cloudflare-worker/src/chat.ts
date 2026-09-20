import { corsHeaders, json } from './http';
import type { ChatMessage, ChatRequest, Env } from './types';

const DEEPSEEK_URL = 'https://api.deepseek.com/v1/chat/completions';
const DEEPSEEK_DEFAULT_MODEL = 'deepseek-v4-flash';
const MAX_MESSAGES = 30;
const DEFAULT_MAX_TOKENS = 4096;
const DEFAULT_TEMPERATURE = 0.7;

type Provider =
  | { kind: 'deepseek' }
  | { kind: 'workers-ai'; model: string };

/** POST /chat — réponse IA en streaming SSE (format OpenAI). */
export async function handleChat(request: Request, env: Env): Promise<Response> {
  let payload: ChatRequest;
  try {
    payload = (await request.json()) as ChatRequest;
  } catch {
    return json(request, env, { error: 'Corps JSON invalide.' }, 400);
  }

  const messages = sanitizeMessages(payload.messages);
  if (messages.length === 0) {
    return json(request, env, { error: 'Le champ "messages" est requis.' }, 400);
  }

  const provider = pickProvider(messages, payload, env);
  if (!provider) {
    return json(
      request,
      env,
      { error: 'Aucun fournisseur IA disponible (secret ou binding manquant).' },
      503,
    );
  }

  const stream = payload.stream !== false;
  const options = {
    messages,
    max_tokens: payload.max_tokens ?? DEFAULT_MAX_TOKENS,
    temperature: payload.temperature ?? DEFAULT_TEMPERATURE,
  };

  try {
    return provider.kind === 'deepseek'
      ? await deepSeekChat(request, env, options, stream)
      : await workersAiChat(request, env, provider.model, options, stream);
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    return json(request, env, { error: `Erreur fournisseur IA : ${message}` }, 502);
  }
}

interface ChatOptions {
  messages: ChatMessage[];
  max_tokens: number;
  temperature: number;
}

function pickProvider(
  messages: ChatMessage[],
  payload: ChatRequest,
  env: Env,
): Provider | null {
  const requested = (payload.model ?? '').trim();
  if (requested.startsWith('@cf/')) return { kind: 'workers-ai', model: requested };

  // Vision : Workers AI si disponible (les modèles texte ne lisent pas les images).
  if (hasImage(messages) && env.AI) {
    return { kind: 'workers-ai', model: env.AI_VISION_MODEL ?? '@cf/meta/llama-3.2-11b-vision-instruct' };
  }

  if (env.DEEPSEEK_API_KEY) return { kind: 'deepseek' };
  if (env.AI) {
    return { kind: 'workers-ai', model: env.AI_TEXT_MODEL ?? '@cf/meta/llama-3.3-70b-instruct-fp8-fast' };
  }
  return null;
}

async function deepSeekChat(
  request: Request,
  env: Env,
  options: ChatOptions,
  stream: boolean,
): Promise<Response> {
  const upstream = await fetch(DEEPSEEK_URL, {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${env.DEEPSEEK_API_KEY}`,
      'Content-Type': 'application/json',
      Accept: stream ? 'text/event-stream' : 'application/json',
    },
    body: JSON.stringify({
      model: DEEPSEEK_DEFAULT_MODEL,
      messages: options.messages,
      max_tokens: options.max_tokens,
      temperature: options.temperature,
      stream,
    }),
  });

  if (!upstream.ok) {
    const detail = await upstream.text();
    return json(request, env, { error: `DeepSeek ${upstream.status}: ${detail}` }, 502);
  }

  if (stream) {
    return new Response(upstream.body, { headers: sseHeaders(request, env) });
  }

  const data = (await upstream.json()) as {
    choices?: Array<{ message?: { content?: string } }>;
  };
  return json(request, env, {
    message: { role: 'assistant', content: data.choices?.[0]?.message?.content ?? '' },
  });
}

async function workersAiChat(
  request: Request,
  env: Env,
  model: string,
  options: ChatOptions,
  stream: boolean,
): Promise<Response> {
  if (!env.AI) {
    return json(request, env, { error: 'Binding Workers AI indisponible.' }, 503);
  }

  const result = (await env.AI.run(model as never, {
    messages: options.messages,
    max_tokens: options.max_tokens,
    temperature: options.temperature,
    stream,
  } as never)) as unknown;

  if (stream) {
    return new Response(toOpenAiSse(result as ReadableStream), {
      headers: sseHeaders(request, env),
    });
  }

  const data = result as { response?: string; choices?: Array<{ message?: { content?: string } }> };
  return json(request, env, {
    message: {
      role: 'assistant',
      content: data.response ?? data.choices?.[0]?.message?.content ?? '',
    },
  });
}

/**
 * Normalise le flux Workers AI (`data: {"response":"…"}`) vers le format
 * OpenAI (`data: {"choices":[{"delta":{"content":"…"}}]}`) attendu par l'app.
 */
function toOpenAiSse(upstream: ReadableStream): ReadableStream<Uint8Array> {
  const encoder = new TextEncoder();
  const decoder = new TextDecoder();
  let buffer = '';

  return upstream.pipeThrough(
    new TransformStream<Uint8Array, Uint8Array>({
      transform(chunk, controller) {
        buffer += decoder.decode(chunk, { stream: true });
        const lines = buffer.split('\n');
        buffer = lines.pop() ?? '';
        for (const line of lines) {
          const text = extractDelta(line);
          if (text) controller.enqueue(encoder.encode(toSseChunk(text)));
        }
      },
      flush(controller) {
        const text = extractDelta(buffer);
        if (text) controller.enqueue(encoder.encode(toSseChunk(text)));
        controller.enqueue(encoder.encode('data: [DONE]\n\n'));
      },
    }),
  );
}

function extractDelta(line: string): string {
  if (!line.startsWith('data:')) return '';
  const payload = line.slice(5).trim();
  if (!payload || payload === '[DONE]') return '';
  try {
    const json = JSON.parse(payload) as {
      response?: string;
      content?: string;
      choices?: Array<{ delta?: { content?: string }; message?: { content?: string } }>;
    };
    return (
      json.response ??
      json.content ??
      json.choices?.[0]?.delta?.content ??
      json.choices?.[0]?.message?.content ??
      ''
    );
  } catch {
    return '';
  }
}

function toSseChunk(content: string): string {
  return `data: ${JSON.stringify({ choices: [{ delta: { content } }] })}\n\n`;
}

function sseHeaders(request: Request, env: Env): Record<string, string> {
  return {
    'Content-Type': 'text/event-stream; charset=utf-8',
    'Cache-Control': 'no-cache',
    Connection: 'keep-alive',
    ...corsHeaders(request, env),
  };
}

function hasImage(messages: ChatMessage[]): boolean {
  return messages.some(
    (message) =>
      Array.isArray(message.content) &&
      message.content.some((part) => part['type'] === 'image_url'),
  );
}

function sanitizeMessages(input: ChatMessage[] | undefined): ChatMessage[] {
  if (!Array.isArray(input)) return [];
  return input
    .filter((message): message is ChatMessage => {
      if (!message || typeof message !== 'object') return false;
      const role = (message as ChatMessage).role;
      const content = (message as ChatMessage).content;
      const validRole = role === 'system' || role === 'user' || role === 'assistant';
      const validContent = typeof content === 'string' || Array.isArray(content);
      return validRole && validContent;
    })
    .slice(-MAX_MESSAGES);
}
