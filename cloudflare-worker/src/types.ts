/** Bindings et variables d'environnement du Worker. */
export interface Env {
  /** Binding Workers AI (voir `ai` dans wrangler.jsonc). */
  AI?: Ai;

  /** Clé du fournisseur IA (secret : `wrangler secret put DEEPSEEK_API_KEY`). */
  DEEPSEEK_API_KEY?: string;

  /** Modèle DeepSeek multimodal (optionnel ; `deepseek-chat` par défaut). */
  DEEPSEEK_VISION_MODEL?: string;

  /** Clé publique de l'app mobile (secret : `wrangler secret put CLIENT_API_KEY`). */
  CLIENT_API_KEY?: string;

  /** Origines autorisées pour CORS, séparées par des virgules. */
  ALLOWED_ORIGINS?: string;

  /** Modèle Workers AI texte. */
  AI_TEXT_MODEL?: string;

  /** Modèle Workers AI vision. */
  AI_VISION_MODEL?: string;

  /** Limite de requêtes par minute et par IP. */
  RATE_LIMIT_PER_MINUTE?: string;
}

/** Message au format OpenAI (contenu texte ou multimodal). */
export interface ChatMessage {
  role: 'system' | 'user' | 'assistant';
  content: string | Array<Record<string, unknown>>;
}

export interface ChatRequest {
  messages?: ChatMessage[];
  model?: string;
  stream?: boolean;
  temperature?: number;
  max_tokens?: number;
}

/** Résultat de recherche web. */
export interface SearchResult {
  title: string;
  url: string;
  snippet: string;
}
