"""Application configuration loaded from environment variables."""

from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    """Server settings read from environment variables."""

    model_config = SettingsConfigDict(
        env_file=".env",
        env_file_encoding="utf-8",
        extra="ignore",
    )

    app_name: str = "CorelIA Backend"
    app_env: str = "development"
    debug: bool = False

    # AI providers
    deepseek_api_key: str | None = None
    openrouter_api_key: str | None = None
    # Search
    serpapi_key: str | None = None

    # Firebase
    firebase_project_id: str | None = None

    # Backend API auth (see backend/core/auth.py).
    # CLIENT_API_KEY : clé partagée APK/extension (soft gate anti-abus sur les
    #   endpoints APK-facing : /scrape, /search_smart, /download_media, /crawl,
    #   /script/scrape, /script/api-fetch, /insights/*). Embarquée via
    #   --dart-define (extractable, comme DEEPSEEK_API_KEY). Vide = mode
    #   transition : endpoints OUVERTS pour ne pas casser un APK déployé sans
    #   la clé ; une fois renseignée, requêtes sans clé valide → 401.
    client_api_key: str = ""
    # API_SECRET_KEY : clé OPÉRATEUR (jamais embarquée dans l'APK). Gate les
    #   endpoints dangereux (/script/exec, /agent/*, /config/*, /insights/audit)
    #   + réutilisée par codewhale-agent. Vide = fail-closed (403).
    api_secret_key: str = ""

    # CORS — défaut wildcard SANS credentials (cf. main.py : allow_credentials
    # est désactivé quand l'origine est "*"). En production, docker-compose
    # surcharge via CORS_ORIGINS=https://zentic.fr,https://api.zentic.fr.
    cors_origins: str = "*"

    # Rate limiting
    redis_url: str = "memory://"
    rate_limit: str = "100/minute"

    @property
    def cors_origins_list(self) -> list[str]:
        """Return CORS origins as a list."""
        return [origin.strip() for origin in self.cors_origins.split(",")]


settings = Settings()
