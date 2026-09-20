import { corsHeaders, json } from './http';
import type { ChatMessage, ChatRequest, Env } from './types';

const DEEPSEEK_URL = 'https://api.deepseek.com/v1/chat/completions';
const DEEPSEEK_DEFAULT_MODEL = 'deepseek-v4-flash';

/**
 * Modèle multimodal DeepSeek (analyse d'image).
 *
 * DeepSeek accepte nativement les parties `image_url` au format OpenAI : la
 * même passerelle sert le texte et la vision, sans traduction de schéma ni
 * dépendance à un modèle Workers AI qui peut être déprécié.
 */
const DEEPSEEK_VISION_MODEL = 'deepseek-chat';

const DEFAULT_TEXT_MODEL = '@cf/meta/llama-3.3-70b-instruct-fp8-fast';

/**
 * Modèle multimodal de repli sur Workers AI (aucune clé DeepSeek configurée).
 *
 * Mistral Small 3.1 (Apache-2.0) accepte le format `messages` d'OpenAI avec
 * parties `image_url`. On écarte `@cf/llava-hf/llava-1.5-7b-hf` (déprécié : la
 * requête ne répond plus) et les modèles Meta (licence interdisant l'Union
 * européenne).
 */
const DEFAULT_VISION_MODEL = '@cf/mistralai/mistral-small-3.1-24b-instruct';

const MAX_MESSAGES = 30;
const DEFAULT_MAX_TOKENS = 4096;
const DEFAULT_TEMPERATURE = 0.7;
const MAX_VISION_PROMPT_CHARS = 2000;

type Provider =
  | { kind: 'deepseek'; model: string }
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
      ? await deepSeekChat(request, env, provider.model, options, stream)
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

  const wantsVision = hasImage(messages);

  // Vision : DeepSeek accepte nativement les parties `image_url` (format
  // OpenAI). C'est la voie primaire — pas de traduction de schéma, pas de
  // modèle Workers AI susceptible d'être déprécié.
  if (wantsVision && env.DEEPSEEK_API_KEY) {
    return {
      kind: 'deepseek',
      model: env.DEEPSEEK_VISION_MODEL ?? DEEPSEEK_VISION_MODEL,
    };
  }

  if (env.DEEPSEEK_API_KEY) {
    return { kind: 'deepseek', model: DEEPSEEK_DEFAULT_MODEL };
  }

  // Repli Workers AI, en texte comme en vision.
  if (env.AI) {
    return {
      kind: 'workers-ai',
      model: wantsVision
        ? (env.AI_VISION_MODEL ?? DEFAULT_VISION_MODEL)
        : (env.AI_TEXT_MODEL ?? DEFAULT_TEXT_MODEL),
    };
  }
  return null;
}

async function deepSeekChat(
  request: Request,
  env: Env,
  model: string,
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
      model,
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

  const image = extractImage(options.messages);
  if (image) {
    // Modèles multimodaux récents (Mistral Small 3.1, Llama 3.2 Vision) : ils
    // acceptent le format `messages` d'OpenAI, comme DeepSeek.
    try {
      return await workersAiVision(request, env, model, options, stream);
    } catch (error) {
      const detail = error instanceof Error ? error.message : String(error);
      console.warn(`[chat] vision « messages » (${model}) a échoué : ${detail}`);
      // Repli sur les modèles image→texte historiques (`{image, prompt}`).
      return await visionChat(request, env, model, options, image);
    }
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

  return json(request, env, {
    message: { role: 'assistant', content: chatTextFrom(result) },
  });
}

/**
 * Vision via un modèle multimodal Workers AI (format `messages` OpenAI).
 *
 * Ces modèles ne streament pas : la réponse complète est renvoyée sous forme
 * d'un unique événement SSE, format que l'application sait déjà lire.
 */
async function workersAiVision(
  request: Request,
  env: Env,
  model: string,
  options: ChatOptions,
  stream: boolean,
): Promise<Response> {
  const ai = env.AI;
  if (!ai) throw new Error('Binding Workers AI indisponible.');

  const result = (await ai.run(model as never, {
    messages: options.messages,
    max_tokens: options.max_tokens,
    temperature: options.temperature,
  } as never)) as unknown;

  const text = chatTextFrom(result);
  if (!text) throw new Error('Réponse vide du modèle vision.');

  if (stream) {
    return new Response(textToOpenAiSse(text), {
      headers: sseHeaders(request, env),
    });
  }
  return json(request, env, { message: { role: 'assistant', content: text } });
}

/** Texte renvoyé par un modèle Workers AI (`choices[].message` ou `response`). */
function chatTextFrom(result: unknown): string {
  if (typeof result === 'string') return result.trim();
  if (result && typeof result === 'object') {
    const data = result as Record<string, unknown>;
    const choices = data['choices'] as
      | Array<{ message?: { content?: string } }>
      | undefined;
    const content = choices?.[0]?.message?.content;
    if (typeof content === 'string' && content.trim()) return content.trim();
    const response = data['response'];
    if (typeof response === 'string' && response.trim()) return response.trim();
  }
  return '';
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
  const cleaned = input.filter((message): message is ChatMessage => {
    if (!message || typeof message !== 'object') return false;
    const role = (message as ChatMessage).role;
    const content = (message as ChatMessage).content;
    const validRole = role === 'system' || role === 'user' || role === 'assistant';
    const validContent = typeof content === 'string' || Array.isArray(content);
    return validRole && validContent;
  });

  if (cleaned.length <= MAX_MESSAGES) return cleaned;

  // Les messages système portent la personnalité et le contexte documentaire :
  // les tronquer ferait « oublier » le document fourni. On ne rogne donc que
  // l'historique conversationnel.
  const system = cleaned.filter((message) => message.role === 'system');
  const rest = cleaned.filter((message) => message.role !== 'system');
  const keep = Math.max(0, MAX_MESSAGES - system.length);
  return [...system, ...(keep > 0 ? rest.slice(-keep) : [])];
}
