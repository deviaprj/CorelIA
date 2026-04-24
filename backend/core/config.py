"""Application configuration loaded from environment variables."""

from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    """Server settings read from environment variables."""

    model_config = SettingsConfigDict(
        env_file=".env",
        env_file_encoding="utf-8",
        extra="ignore",
    )

    app_name: str = "AironBot Backend"
    app_env: str = "development"
    debug: bool = False

    # AI providers
    deepseek_api_key: str | None = None
    openrouter_api_key: str | None = None
    ollama_cloud_url: str | None = None
    ollama_cloud_api_key: str | None = None

    # Search
    serpapi_key: str | None = None

    # Firebase
    firebase_project_id: str | None = None

    # CORS
    cors_origins: str = "*"

    # Rate limiting
    redis_url: str = "redis://localhost:6379/0"
    rate_limit: str = "100/minute"

    @property
    def cors_origins_list(self) -> list[str]:
        """Return CORS origins as a list."""
        return [origin.strip() for origin in self.cors_origins.split(",")]


settings = Settings()
