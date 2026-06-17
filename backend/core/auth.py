"""Firebase JWT verification + API-key gating middleware."""

import functools
import hmac
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


def _extract_api_key(request: Request) -> str | None:
    """Read the API key from the X-API-Key header or ?api_key= query param."""
    return request.headers.get("X-API-Key") or request.query_params.get("api_key")


def _constant_time_eq(a: str | None, b: str | None) -> bool:
    """Constant-time comparison (avoids timing side-channels on the secret)."""
    return hmac.compare_digest(a or "", b or "")


async def require_client_api_key(request: Request) -> str:
    """Gate APK/extension-facing endpoints (/scrape, /search_smart,
    /download_media, /crawl, /script/scrape, /script/api-fetch, /insights/*).

    Compared against ``settings.client_api_key``. Transition-safe: if no
    client key is configured (empty), the gate is OPEN so an already-deployed
    APK keeps working until an APK embedding the matching key ships. Once
    ``CLIENT_API_KEY`` is set, requests without a valid key get 401.
    """
    api_key = _extract_api_key(request)
    configured = settings.client_api_key
    if not configured:
        # Transition mode — the gate stays open until the operator ships an
        # APK with the key. Logged so the open state is visible (not silent).
        logger.warning("CLIENT_API_KEY not set — client endpoints are OPEN (transition)")
        return api_key or "transition"
    if not api_key or not _constant_time_eq(api_key, configured):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Missing or invalid API key",
        )
    return api_key


async def require_operator_key(request: Request) -> str:
    """Gate dangerous operator endpoints (/script/exec, /agent/*, /config/*,
    /insights/audit).

    Compared against ``settings.api_secret_key`` (OPERATOR secret — never
    embedded in the APK). Fail-closed: if no operator key is configured, every
    request is rejected with 403 (endpoint effectively disabled until the
    operator sets ``API_SECRET_KEY``).
    """
    configured = settings.api_secret_key
    api_key = _extract_api_key(request)
    if not configured:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Operator key not configured on the server",
        )
    if not api_key or not _constant_time_eq(api_key, configured):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Missing or invalid operator key",
        )
    return api_key


# Back-compat alias — data_insights.py still uses ``Depends(require_api_key)``.
# Repurposed from a no-op stub (any non-empty key accepted, even in production)
# to the real client gate: transition-open until CLIENT_API_KEY is set, then
# enforced. Strictly tighter than the previous behavior.
require_api_key = require_client_api_key
