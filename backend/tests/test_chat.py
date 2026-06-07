"""Basic pytest tests for the chat backend."""

from unittest.mock import AsyncMock, patch

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
@patch("firebase_admin.auth.verify_id_token", new_callable=AsyncMock)
def test_chat_streaming_mock(
    mock_verify: AsyncMock,
    mock_get_app: object,
    client: TestClient,
    mock_firebase_user: dict[str, str],
) -> None:
    """Chat streaming endpoint returns SSE data with mocked auth and provider."""
    mock_verify.return_value = mock_firebase_user

    chat_request = ChatRequest(
        messages=[Message(role=Role.USER, content="Hello")],
        stream=True,
    )

    with patch(
        "backend.agents.chat_router._chat_with_fallback",
        new_callable=lambda: AsyncMock,
    ) as mock_chat:
        mock_chat.return_value = iter(
            [
                'data: {"content": "Hello"}\n\n',
                'data: {"content": " world"}\n\n',
            ]
        )

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
@patch("firebase_admin.auth.verify_id_token", new_callable=AsyncMock)
def test_chat_non_streaming_mock(
    mock_verify: AsyncMock,
    mock_get_app: object,
    client: TestClient,
    mock_firebase_user: dict[str, str],
) -> None:
    """Chat non-streaming endpoint returns a JSON response."""
    mock_verify.return_value = mock_firebase_user

    chat_request = ChatRequest(
        messages=[Message(role=Role.USER, content="Hello")],
        stream=False,
    )

    with patch(
        "backend.agents.chat_router._chat_with_fallback",
        new_callable=lambda: AsyncMock,
    ) as mock_chat:
        mock_chat.return_value = iter(
            [
                'data: {"content": "Hi"}\n\n',
                "data: [DONE]\n\n",
            ]
        )

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
