# ============================================================================
# CodeWhale Agent — Dockerfile
# Image légère Python 3.12 pour le microservice agent autonome
# ============================================================================

FROM python:3.12-slim

# Non-root runtime (uid 10002) + no .pyc + unbuffered logs. The agent runs shell
# tools (run_command) autonomously, so running unprivileged is the last line of
# defense against a prompt-injection-driven destructive command: as `agent` it
# cannot rm -rf system paths, bind privileged ports, or write to /etc.
ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1

WORKDIR /app

# Install system dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    curl \
    && rm -rf /var/lib/apt/lists/*

# Copy requirements first (layer caching)
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Non-root user (uid 10002). /workspace + /app are chowned to `agent` so the
# named volume `codewhale-workspace` inherits `agent` ownership on first mount
# (otherwise it defaults to root and the agent cannot write its task outputs).
RUN useradd -r -u 10002 -m -d /home/agent agent \
    && mkdir -p /workspace \
    && chown -R agent:agent /workspace /app

# Copy app code
COPY --chown=agent:agent main.py .
USER agent

# Port
EXPOSE 8001

# Health check
HEALTHCHECK --interval=30s --timeout=10s --retries=3 \
    CMD curl -sf http://localhost:8001/health || exit 1

# Run
ENV AGENT_PORT=8001
CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8001"]
