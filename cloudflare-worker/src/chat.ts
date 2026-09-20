import { corsHeaders, json } from './http';
import type { ChatMessage, ChatRequest, Env } from './types';

const DEEPSEEK_URL = 'https://api.deepseek.com/v1/chat/completions';
const DEEPSEEK_DEFAULT_MODEL = 'deepseek-v4-flash';
const MAX_MESSAGES = 30;
const DEFAULT_MAX_TOKENS = 4096;
const DEFAULT_TEMPERATURE = 0.7;
const MAX_VISION_PROMPT_CHARS = 2000;

/**
 * Modèle image→texte par défaut.
 *
 * LLaVA est retenu plutôt que `@cf/meta/llama-3.2-11b-vision-instruct` : ce
 * dernier exige d'accepter une licence Meta interdisant explicitement les
 * personnes et entreprises domiciliées dans l'Union européenne, ce qui est le
 * cas de ce déploiement.
 */
const DEFAULT_VISION_MODEL = '@cf/llava-hf/llava-1.5-7b-hf';

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
    return { kind: 'workers-ai', model: env.AI_VISION_MODEL ?? DEFAULT_VISION_MODEL };
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

  // Les modèles image→texte (Moondream, LLaVA) attendent `{image, prompt}` et
  // non le format messages : on les traite à part.
  const image = extractImage(options.messages);
  if (image) return visionChat(request, env, model, options, image);

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

/** Image extraite d'un message multimodal. */
interface InlineImage {
  bytes: number[];
}

/**
 * Analyse d'image via un modèle image→texte de Workers AI.
 *
 * Ces modèles attendent `{ image, prompt }` et ne streament pas : la réponse
 * est renvoyée sous forme d'un unique événement SSE, format que l'application
 * sait déjà lire.
 */
async function visionChat(
  request: Request,
  env: Env,
  model: string,
  options: ChatOptions,
  image: InlineImage,
): Promise<Response> {
  if (!env.AI) {
    return json(request, env, { error: 'Binding Workers AI indisponible.' }, 503);
  }

  const result = (await env.AI.run(model as never, {
    image: image.bytes,
    prompt: conversationPrompt(options.messages),
  } as never)) as unknown;

  const text = visionTextFrom(result);
  if (!text) {
    return json(
      request,
      env,
      { error: "Le modèle n'a pas pu analyser cette image." },
      502,
    );
  }

  return new Response(textToOpenAiSse(text), { headers: sseHeaders(request, env) });
}

/** Récupère le texte renvoyé par un modèle image→texte, quel que soit le champ. */
function visionTextFrom(result: unknown): string {
  if (typeof result === 'string') return result.trim();
  if (result && typeof result === 'object') {
    const data = result as Record<string, unknown>;
    for (const key of ['response', 'description', 'caption', 'text', 'answer']) {
      const value = data[key];
      if (typeof value === 'string' && value.trim()) return value.trim();
    }
  }
  return '';
}

/** Première image trouvée dans les messages (parcours du plus récent). */
function extractImage(messages: ChatMessage[]): InlineImage | null {
  for (let i = messages.length - 1; i >= 0; i--) {
    const content = messages[i].content;
    if (!Array.isArray(content)) continue;

    for (const part of content) {
      if (part['type'] !== 'image_url') continue;
      const url = (part['image_url'] as { url?: string } | undefined)?.url;
      if (typeof url !== 'string') continue;

      const match = /^data:([^;]+);base64,(.+)$/s.exec(url);
      if (!match || !match[1].startsWith('image/')) continue;

      try {
        const binary = atob(match[2]);
        const bytes = Array.from(binary, (char) => char.charCodeAt(0));
        if (bytes.length > 0) return { bytes };
      } catch {
        // Image illisible : on ignore cette partie.
      }
    }
  }
  return null;
}

/** Réduit la conversation à une consigne texte pour un modèle image→texte. */
function conversationPrompt(messages: ChatMessage[]): string {
  const lines: string[] = [];

  for (const message of messages) {
    const content = message.content;
    const text = typeof content === 'string'
      ? content
      : content
          .filter((part) => part['type'] === 'text')
          .map((part) => String(part['text'] ?? ''))
          .join(' ');

    const trimmed = text.trim();
    if (!trimmed) continue;

    lines.push(message.role === 'assistant' ? `Assistant : ${trimmed}` : trimmed);
  }

  const prompt = lines.join('\n').trim();
  return prompt.length > MAX_VISION_PROMPT_CHARS
    ? prompt.slice(-MAX_VISION_PROMPT_CHARS)
    : prompt;
}

/** Emballe un texte complet dans un flux SSE au format OpenAI. */
function textToOpenAiSse(text: string): string {
  return `${toSseChunk(text)}\ndata: [DONE]\n\n`;
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
