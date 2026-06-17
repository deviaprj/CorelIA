# Dockerfile for CorelIA backend
FROM python:3.12-slim

# Non-root runtime (uid 10001) + no .pyc + unbuffered logs. Running as a
# dedicated unprivileged user limits the blast radius if a request-handling
# bug or a sandboxed LLM-generated script escapes its constraints: the
# process cannot write to the image filesystem, bind privileged host ports,
# or reach root-owned paths.
ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1

WORKDIR /app

# Install system dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    gcc \
    libxml2-dev \
    libxslt1-dev \
    && rm -rf /var/lib/apt/lists/*

# Copy requirements and install Python dependencies
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Non-root user (uid 10001). Created before the code copy so the whole /app
# tree is owned by `app`; the sandbox writes temp dirs under /tmp (world-writable).
RUN useradd -r -u 10001 -m -d /home/app app

# Copy application code
COPY --chown=app:app . .
USER app

# Expose port
EXPOSE 8000

# Run with uvicorn
CMD ["uvicorn", "backend.main:app", "--host", "0.0.0.0", "--port", "8000", "--workers", "4"]
