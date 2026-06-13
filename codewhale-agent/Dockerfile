# ============================================================================
# CodeWhale Agent — Dockerfile
# Image légère Python 3.12 pour le microservice agent autonome
# ============================================================================

FROM python:3.12-slim

WORKDIR /app

# Install system dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    curl \
    && rm -rf /var/lib/apt/lists/*

# Copy requirements first (layer caching)
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy app code
COPY main.py .

# Port
EXPOSE 8001

# Health check
HEALTHCHECK --interval=30s --timeout=10s --retries=3 \
    CMD curl -sf http://localhost:8001/health || exit 1

# Run
ENV AGENT_PORT=8001
CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8001"]
