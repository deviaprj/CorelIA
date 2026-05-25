"""Firebase JWT verification middleware."""

import functools
from typing import Any, Callable

from fastapi import HTTPException, Request, status
from fastapi.security import HTTPBearer, HTTPAuthorizationCredentials

from backend.core.config import settings
from backend.core.logging import get_logger

logger = get_logger(__name__)

# Lazy-load firebase_admin to avoid import overhead when not configured
_firebase_app = None

def _get_firebase_app() -> Any:  # type: ignore[misc]
    global _firebase_app
    if _firebase_app is None:
        import firebase_admin
        from firebase_admin import credentials
        if not firebase_admin._apps:
            if settings.firebase_project_id:
                cred = credentials.ApplicationDefault()
                _firebase_app = firebase_admin.initialize_app(cred, {
                    "projectId": settings.firebase_project_id,
                })
            else:
                _firebase_app = firebase_admin.initialize_app()
        else:
            _firebase_app = firebase_admin.get_app()
    return _firebase_app


security = HTTPBearer(auto_error=False)


async def verify_firebase_token(request: Request) -> dict[str, Any]:
    """Verify the Firebase ID token from the Authorization header.

    Returns the decoded token payload. Raises HTTPException 401 on failure.
    """
    credentials: HTTPAuthorizationCredentials | None = await security(request)
    if not credentials:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Missing authorization header",
        )

    token = credentials.credentials
    try:
        from firebase_admin import auth as firebase_auth
        _get_firebase_app()
        decoded = firebase_auth.verify_id_token(token, check_revoked=True)
        return decoded  # type: ignore[no-any-return]
    except Exception as exc:
        logger.warning("Firebase token verification failed", extra={"error": str(exc)})
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid or expired token",
        ) from exc


RequireAuth = Callable[..., Any]


def require_auth(endpoint: Callable[..., Any]) -> Callable[..., Any]:
    """Decorator/FastAPI dependency wrapper to enforce Firebase auth on a route."""

    @functools.wraps(endpoint)
    async def wrapper(*args: Any, **kwargs: Any) -> Any:
        # FastAPI injects Request as a keyword arg or we can look for it
        request: Request | None = kwargs.get("request")
        if request is None:
            for arg in args:
                if isinstance(arg, Request):
                    request = arg
                    break
        if request is None:
            raise HTTPException(status_code=500, detail="Request object not found")
        user = await verify_firebase_token(request)
        kwargs["current_user"] = user
        return await endpoint(*args, **kwargs)

    return wrapper


async def require_api_key(request: Request) -> str:
    """FastAPI dependency that validates an API key from the X-API-Key header."""
    api_key = request.headers.get("X-API-Key") or request.query_params.get("api_key")
    if not api_key:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Missing API key",
        )
    # In development any non-empty key is accepted; production should check against DB/Redis
    if settings.app_env == "production":
        # TODO: validate against stored API keys in production
        pass
    return api_key
