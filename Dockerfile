FROM python:3.12.13-slim@sha256:57cd7c3a7a273101a6485ba99423ee568157882804b1124b4dd04266317710de

# Force deterministic Python byte compilation
ENV PYTHONDONTWRITEBYTECODE=1
ENV PYTHONUNBUFFERED=1
ENV SOURCE_DATE_EPOCH=1577836800 

WORKDIR /app

# Build-Time Arguments & Public Configuration
ARG APP_VERSION="1.0.0"
ARG APP_COMMIT_SHA="dev"
ARG BUILD_TIMESTAMP=""
ARG GITHUB_RUN_ID=""
ARG GITHUB_RUN_NUMBER=""
ARG APP_NAME="Nexus Orbit"
ARG APP_DOMAIN=""
ARG DEBUG="false"
ARG EMAIL_DOMAIN=""
ARG ALLOWED_SIGNUP_DOMAINS="{}"
ARG ANDROID_SHA256_FINGERPRINT=""
ARG CURRENT_TERMS_VERSION="1"
ARG LEGAL_EFFECTIVE_DATE=""
ARG LEGAL_GOVERNING_LAW_CITY=""
ARG GRIEVANCE_OFFICER_NAME=""
ARG GRIEVANCE_OFFICER_EMAIL=""
ARG GRIEVANCE_OFFICER_PHONE=""
ARG GRIEVANCE_OFFICER_WEBSITE=""
ARG ACCOUNT_DELETION_GRACE_PERIOD_DAYS="14"
ARG ACCOUNT_DELETION_BLOCKLIST_COOLDOWN_DAYS="30"
ARG ACCOUNT_DELETION_LONG_TAIL_PURGE_DAYS="1095"
ARG SAFETY_EVIDENCE_ACTIVE_RETENTION_DAYS="365"
ARG SAFETY_DATA_LEGAL_HOLD_DAYS="180"
ARG SENTRY_ENVIRONMENT=""
ARG SPOTIFY_CLIENT_ID=""
ARG SPOTIFY_REDIRECT_URI=""
ARG SUPABASE_URL=""
ARG ENGINE_COMMIT_SHA=""

ENV APP_VERSION=$APP_VERSION \
    APP_COMMIT_SHA=$APP_COMMIT_SHA \
    BUILD_TIMESTAMP=$BUILD_TIMESTAMP \
    GITHUB_RUN_ID=$GITHUB_RUN_ID \
    GITHUB_RUN_NUMBER=$GITHUB_RUN_NUMBER \
    APP_NAME=$APP_NAME \
    APP_DOMAIN=$APP_DOMAIN \
    DEBUG=$DEBUG \
    EMAIL_DOMAIN=$EMAIL_DOMAIN \
    ALLOWED_SIGNUP_DOMAINS=$ALLOWED_SIGNUP_DOMAINS \
    ANDROID_SHA256_FINGERPRINT=$ANDROID_SHA256_FINGERPRINT \
    CURRENT_TERMS_VERSION=$CURRENT_TERMS_VERSION \
    LEGAL_EFFECTIVE_DATE=$LEGAL_EFFECTIVE_DATE \
    LEGAL_GOVERNING_LAW_CITY=$LEGAL_GOVERNING_LAW_CITY \
    GRIEVANCE_OFFICER_NAME=$GRIEVANCE_OFFICER_NAME \
    GRIEVANCE_OFFICER_EMAIL=$GRIEVANCE_OFFICER_EMAIL \
    GRIEVANCE_OFFICER_PHONE=$GRIEVANCE_OFFICER_PHONE \
    GRIEVANCE_OFFICER_WEBSITE=$GRIEVANCE_OFFICER_WEBSITE \
    ACCOUNT_DELETION_GRACE_PERIOD_DAYS=$ACCOUNT_DELETION_GRACE_PERIOD_DAYS \
    ACCOUNT_DELETION_BLOCKLIST_COOLDOWN_DAYS=$ACCOUNT_DELETION_BLOCKLIST_COOLDOWN_DAYS \
    ACCOUNT_DELETION_LONG_TAIL_PURGE_DAYS=$ACCOUNT_DELETION_LONG_TAIL_PURGE_DAYS \
    SAFETY_EVIDENCE_ACTIVE_RETENTION_DAYS=$SAFETY_EVIDENCE_ACTIVE_RETENTION_DAYS \
    SAFETY_DATA_LEGAL_HOLD_DAYS=$SAFETY_DATA_LEGAL_HOLD_DAYS \
    SENTRY_ENVIRONMENT=$SENTRY_ENVIRONMENT \
    SPOTIFY_CLIENT_ID=$SPOTIFY_CLIENT_ID \
    SPOTIFY_REDIRECT_URI=$SPOTIFY_REDIRECT_URI \
    SUPABASE_URL=$SUPABASE_URL \
    ENGINE_COMMIT_SHA=$ENGINE_COMMIT_SHA


# Install dependencies and Infisical CLI, retaining curl and tar for system dependencies and health checks
COPY requirements.txt .
RUN apt-get update && apt-get install -y --no-install-recommends curl wget tar ca-certificates build-essential && \
    pip install --no-cache-dir --require-hashes -r requirements.txt && \
    wget -qO /tmp/infisical.tar.gz https://github.com/Infisical/cli/releases/download/v0.43.84/cli_0.43.84_linux_amd64.tar.gz && \
    echo "64a47155083c7b8042de64e67eee5629bf894903c102f7239f69c7ed93fdbfc5  /tmp/infisical.tar.gz" | sha256sum -c - && \
    tar -xz -C /usr/local/bin -f /tmp/infisical.tar.gz infisical && \
    rm -f /tmp/infisical.tar.gz && \
    apt-get purge -y --auto-remove build-essential && \
    rm -rf /var/lib/apt/lists/*

# Copy application source code (filtered by .dockerignore)
COPY . .

# Copy mock engine into the build image so that imports succeed, tests run, and compilation works.
# In production deployment, this mock file is dynamically overridden with a runtime volume mount.
COPY mocks/Nexus_Engine/engine.py /app/Nexus_Engine/engine.py

# Create a non-root user, setup cache directories, and set ownership
RUN mkdir -p /app/cache/nexus_engine /app/Nexus_Engine && \
    chmod +x /app/entrypoint.sh && \
    groupadd -g 10001 appgroup && \
    useradd -u 10001 -g appgroup -m -s /sbin/nologin -c "Nexus User" appuser && \
    chown -R appuser:appgroup /app /home/appuser

USER appuser

EXPOSE 8000

HEALTHCHECK --interval=30s --timeout=10s --start-period=30s --retries=3 \
  CMD curl --fail --silent --show-error http://127.0.0.1:8000/health || exit 1

ENTRYPOINT ["/app/entrypoint.sh"]

# Wrap the start command with Infisical CLI to dynamically fetch runtime secrets into memory at boot time.
CMD ["sh", "-c", "exec infisical run --projectId \"${INFISICAL_PROJECT_ID}\" --path /runtime --env prod -- uvicorn app.main:app --host 0.0.0.0 --port 8000 --proxy-headers --forwarded-allow-ips='*'"]
