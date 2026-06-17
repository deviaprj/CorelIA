"""Basic pytest tests for the chat backend."""

from unittest.mock import AsyncMock, MagicMock, patch

import pytest
from fastapi.testclient import TestClient

from backend.main import app
from backend.schemas.chat import ChatRequest, Message, Role


@pytest.fixture
def client() -> TestClient:
    """FastAPI test client fixture."""
    return TestClient(app)


@pytest.fixture
def mock_firebase_user() -> dict[str, str]:
    """Mock Firebase decoded token."""
    return {"uid": "test-user-123", "email": "test@example.com"}


def test_health_check(client: TestClient) -> None:
    """Health check returns 200."""
    response = client.get("/health")
    assert response.status_code == 200
    data = response.json()
    assert data["status"] == "ok"


@patch("backend.core.auth._get_firebase_app", new_callable=lambda: lambda: None)
@patch("firebase_admin.auth.verify_id_token", new_callable=MagicMock)
def test_chat_streaming_mock(
    mock_verify: MagicMock,
    mock_get_app: object,
    client: TestClient,
    mock_firebase_user: dict[str, str],
) -> None:
    """Chat streaming endpoint returns SSE data with mocked auth and provider.

    Auth mock: ``firebase_admin.auth.verify_id_token`` is **synchronous** in the
    real SDK (it does blocking JWT verification), and ``auth.verify_firebase_token``
    calls it without ``await`` (``auth.py:55``). Mocking it with ``AsyncMock`` made
    the call return an un-awaited coroutine (``current_user`` = coroutine, not the
    user dict) + a ``RuntimeWarning: coroutine never awaited``. Use ``MagicMock``
    (sync) so ``decoded = verify_id_token(...)`` returns the dict directly.

    Provider mock: ``_chat_with_fallback`` is an **async generator** (``async def``
    + ``yield``). The old mock used ``AsyncMock`` with ``return_value=iter([...])``
    (a *sync* iterator) via ``new_callable=lambda: AsyncMock`` — that returns the
    AsyncMock *class*, so the endpoint's ``_chat_with_fallback(messages_raw, ...)``
    invoked ``AsyncMock(messages_raw, ...)`` as a **constructor** with the messages
    list as ``spec``, crashing in ``_mock_set_magics`` with ``TypeError: unhashable
    type: 'dict'``. Replace it with a real async-generator function matching the
    signature — ``async for chunk in fake_chat(...)`` then yields the SSE chunks.
    """
    mock_verify.return_value = mock_firebase_user

    chat_request = ChatRequest(
        messages=[Message(role=Role.USER, content="Hello")],
        stream=True,
    )

    async def fake_chat(messages, *args, **kwargs):
        yield 'data: {"content": "Hello"}\n\n'
        yield 'data: {"content": " world"}\n\n'

    with patch("backend.agents.chat_router._chat_with_fallback", new=fake_chat):
        response = client.post(
            "/chat/completions",
            json=chat_request.model_dump(),
            headers={"Authorization": "Bearer fake-token"},
        )

        assert response.status_code == 200
        assert response.headers["content-type"].startswith("text/event-stream")
        body = response.text
        assert "Hello" in body


@patch("backend.core.auth._get_firebase_app", new_callable=lambda: lambda: None)
@patch("firebase_admin.auth.verify_id_token", new_callable=MagicMock)
def test_chat_non_streaming_mock(
    mock_verify: MagicMock,
    mock_get_app: object,
    client: TestClient,
    mock_firebase_user: dict[str, str],
) -> None:
    """Chat non-streaming endpoint returns a JSON response.

    Same mock fixes as ``test_chat_streaming_mock``: ``verify_id_token`` is sync
    (``MagicMock``), and ``_chat_with_fallback`` is an async generator patched with
    a real ``async def`` function (see the streaming test's docstring for the full
    rationale on why ``AsyncMock`` + ``return_value=iter([])`` crashed with
    ``TypeError: unhashable type: 'dict'``).
    """
    mock_verify.return_value = mock_firebase_user

    chat_request = ChatRequest(
        messages=[Message(role=Role.USER, content="Hello")],
        stream=False,
    )

    async def fake_chat(messages, *args, **kwargs):
        yield 'data: {"content": "Hi"}\n\n'
        yield "data: [DONE]\n\n"

    with patch("backend.agents.chat_router._chat_with_fallback", new=fake_chat):
        response = client.post(
            "/chat/completions",
            json=chat_request.model_dump(),
            headers={"Authorization": "Bearer fake-token"},
        )

        assert response.status_code == 200
        data = response.json()
        assert "message" in data
        assert data["message"]["content"] == "Hi"


def test_chat_unauthorized(client: TestClient) -> None:
    """Chat endpoint without token returns 401."""
    chat_request = ChatRequest(
        messages=[Message(role=Role.USER, content="Hello")],
    )
    response = client.post("/chat/completions", json=chat_request.model_dump())
    assert response.status_code == 401
