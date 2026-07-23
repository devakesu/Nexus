FROM python:3.12.13-slim@sha256:57cd7c3a7a273101a6485ba99423ee568157882804b1124b4dd04266317710de

# Force deterministic Python byte compilation
ENV PYTHONDONTWRITEBYTECODE=1
ENV PYTHONUNBUFFERED=1
ENV SOURCE_DATE_EPOCH=1577836800 

WORKDIR /app

# Install dependencies and Infisical CLI, retaining curl and tar for system dependencies and health checks
COPY requirements.txt .
RUN apt-get update && apt-get install -y --no-install-recommends curl wget tar ca-certificates build-essential && \
    pip install --no-cache-dir --require-hashes -r requirements.txt && \
    wget -qO- https://github.com/Infisical/cli/releases/download/v0.43.84/cli_0.43.84_linux_amd64.tar.gz | tar -xz -C /usr/local/bin infisical && \
    apt-get purge -y --auto-remove wget build-essential && \
    rm -rf /var/lib/apt/lists/*

# Copy application source code (filtered by .dockerignore)
COPY . .

# Copy mock engine into the build image so that imports succeed, tests run, and compilation works.
# In production deployment, this mock file is dynamically overridden with a runtime volume mount.
COPY mocks/Nexus_Engine/engine.py /app/Nexus_Engine/engine.py

# Create a non-root user and set ownership
RUN chmod +x /app/entrypoint.sh && \
    groupadd -g 10001 appgroup && \
    useradd -u 10001 -g appgroup -s /sbin/nologin -c "Nexus User" appuser && \
    chown -R appuser:appgroup /app

USER appuser

EXPOSE 8000

HEALTHCHECK --interval=30s --timeout=10s --start-period=40s --retries=3 \
  CMD curl --fail --silent --show-error http://127.0.0.1:8000/health || exit 1

ENTRYPOINT ["/app/entrypoint.sh"]

# Wrap the start command with Infisical CLI to dynamically fetch runtime secrets into memory at boot time.
CMD ["sh", "-c", "exec infisical run --projectId \"${INFISICAL_PROJECT_ID}\" --path /runtime --env prod -- uvicorn app.main:app --host 0.0.0.0 --port 8000"]
