# syntax=docker/dockerfile:1.4@sha256:9ba7531bd80fb0a858632727cf7a112fbfd19b17e94c4e84ced81e24ef1a0dbc

# Main Base Image (Ubuntu 24.04 GLIBC compatible)
FROM mcr.microsoft.com/devcontainers/base:2.1.7-ubuntu24.04@sha256:4bcb1b466771b1ba1ea110e2a27daea2f6093f9527fb75ee59703ec89b5561cb

USER root

# 1. Native System Runtimes & Dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    acl \
    adb \
    ca-certificates \
    curl \
    git \
    gnupg \
    jq \
    openjdk-21-jdk-headless \
    python3 \
    python3-pip \
    python3-venv \
    socat \
    unzip \
    wget \
    zlib1g \
    && install -m 0755 -d /etc/apt/keyrings \
    # NodeSource Setup (Node 24)
    && curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key | gpg --dearmor -o /etc/apt/keyrings/nodesource.gpg \
    && chmod 644 /etc/apt/keyrings/nodesource.gpg \
    && echo "deb [signed-by=/etc/apt/keyrings/nodesource.gpg] https://deb.nodesource.com/node_24.x nodistro main" > /etc/apt/sources.list.d/nodesource.list \
    # Docker CE Setup
    && curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg \
    && chmod 644 /etc/apt/keyrings/docker.gpg \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu noble stable" > /etc/apt/sources.list.d/docker.list \
    # Final package install
    && apt-get update && apt-get install -y --no-install-recommends \
    docker-buildx-plugin \
    docker-ce-cli \
    docker-compose-plugin \
    nodejs \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# Symlink system python3 to python/pip globally
RUN ln -sf /usr/bin/python3 /usr/local/bin/python \
    && ln -sf /usr/bin/pip3 /usr/local/bin/pip

RUN npm install -g npm@latest

# 2. Configure Paths for Shared Host Mounts
USER vscode
ENV HOME="/home/vscode"
ENV FLUTTER_HOME="$HOME/sdk-mounts/flutter"
ENV ANDROID_HOME="$HOME/sdk-mounts/android"
ENV DENO_INSTALL="$HOME/sdk-mounts/deno"
ENV PUB_CACHE="$HOME/.pub-cache"
ENV PLAYWRIGHT_BROWSERS_PATH="$HOME/.cache/ms-playwright"
ENV NODE_OPTIONS="--max-old-space-size=9216"
ENV PATH="$PATH:$HOME/sdk-mounts/bin:$FLUTTER_HOME/bin:$ANDROID_HOME/cmdline-tools/latest/bin:$ANDROID_HOME/platform-tools:$DENO_INSTALL/bin:$PUB_CACHE/bin"

# 3. Bake IDE Settings & Cross-IDE Extension Symlinks
RUN mkdir -p $HOME/.antigravity-server/data/Machine \
             $HOME/.antigravity-ide-server/data/Machine \
             $HOME/.vscode-server/data/Machine \
             $HOME/.vscode-server/extensions \
    && ln -s $HOME/.vscode-server/extensions $HOME/.antigravity-server/extensions \
    && ln -s $HOME/.vscode-server/extensions $HOME/.antigravity-ide-server/extensions \
    && SETTINGS='{ \
        "remote.forwardAgent": false, \
        "python.defaultInterpreterPath": "/nexus/.venv/bin/python", \
        "python.analysis.diagnosticMode": "workspace", \
        "python.analysis.typeCheckingMode": "strict", \
        "python.analysis.inlayHints.variableTypes": true, \
        "python.analysis.inlayHints.functionReturnTypes": true, \
        "python.analysis.diagnosticSeverityOverrides": { \
            "reportMissingTypeStubs": "warning", \
            "reportUnknownMemberType": "warning", \
            "reportUnknownVariableType": "warning", \
            "reportUnknownArgumentType": "warning", \
            "reportUnknownReturnType": "warning", \
            "reportUnusedImport": "error", \
            "reportUnusedVariable": "error", \
            "reportDuplicateImport": "error", \
            "reportImplicitGenericAny": "warning" \
        }, \
        "ruff.enable": true, \
        "ruff.organizeImports": true, \
        "ruff.fixAll": true, \
        "dart.flutterSdkPath": "/home/vscode/sdk-mounts/flutter" \
    }' \
    && echo "$SETTINGS" > $HOME/.antigravity-server/data/Machine/settings.json \
    && echo "$SETTINGS" > $HOME/.antigravity-ide-server/data/Machine/settings.json \
    && echo "$SETTINGS" > $HOME/.vscode-server/data/Machine/settings.json

# 4. Initialization Script Creation
USER root
COPY --chown=vscode:vscode --chmod=755 <<"EOF" /home/vscode/init_workspace.sh
#!/bin/bash
echo "🚀 Starting Fullstack Workspace Setup..."

# --- 1. GIT CONFIG DIVERSION ---
if [ ! -L "/home/vscode/.gitconfig" ]; then
    if [ -f "/home/vscode/.gitconfig" ]; then
        mv /home/vscode/.gitconfig /home/vscode/.gitconfig_local
    else
        touch /home/vscode/.gitconfig_local
    fi
    ln -sf /home/vscode/.gitconfig_local /home/vscode/.gitconfig
fi
chmod 644 /home/vscode/.gitconfig_local 2>/dev/null || true

# --- 2. SSH AGENT & SIGNING SETUP ---
echo "🔑 Checking SSH Agent Forwarding..."
HAS_SSH_KEY=false
if [ -S "$SSH_AUTH_SOCK" ] && ssh-add -L >/dev/null 2>&1; then
    CLEAN_KEY=$(ssh-add -L 2>/dev/null | tr -d '\r' | grep -i "ghost" | head -n 1)
    if [ -z "$CLEAN_KEY" ]; then
        CLEAN_KEY=$(ssh-add -L 2>/dev/null | tr -d '\r' | head -n 1)
    fi

    if [ -n "$CLEAN_KEY" ]; then
        HAS_SSH_KEY=true
        git config --global user.signingkey "$CLEAN_KEY"
        git config --global gpg.format ssh
        git config --global commit.gpgsign true
        echo "✅ SSH signing enabled."
    fi
else
    echo "⚠️ SSH Agent is not active or has no keys loaded."
fi

# --- 3. GIT IDENTITY ---
CURRENT_NAME=$(git config --global user.name 2>/dev/null)
CURRENT_EMAIL=$(git config --global user.email 2>/dev/null)

if [ -z "$CURRENT_NAME" ] || [ -z "$CURRENT_EMAIL" ]; then
    if [ -t 0 ]; then
        echo "👤 Setting up Git identity..."
        [ -z "$CURRENT_NAME" ] && read -rp "Enter Git Name: " CURRENT_NAME && git config --global user.name "$CURRENT_NAME"
        [ -z "$CURRENT_EMAIL" ] && read -rp "Enter Git Email: " CURRENT_EMAIL && git config --global user.email "$CURRENT_EMAIL"
    else
        AUTO_EMAIL=$(ssh-add -L 2>/dev/null | awk '{print $3}' | grep "@" | head -n 1)
        [ -z "$CURRENT_NAME" ] && git config --global user.name "${GIT_NAME:-User}"
        [ -z "$CURRENT_EMAIL" ] && git config --global user.email "${GIT_EMAIL:-${AUTO_EMAIL:-dev@example.com}}"
        echo "ℹ️ Auto-configured Git identity: $(git config --global user.name) <$(git config --global user.email)>"
    fi
fi

# --- 4. POPULATE ALLOWED SIGNERS ---
if [ "$HAS_SSH_KEY" = true ]; then
    FINAL_EMAIL=$(git config --global user.email)
    ALLOWED_SIGNERS_FILE="/home/vscode/.ssh/allowed_signers"
    
    mkdir -p /home/vscode/.ssh && chmod 700 /home/vscode/.ssh
    echo "${FINAL_EMAIL:-*} ${CLEAN_KEY}" > "$ALLOWED_SIGNERS_FILE"
    chmod 600 "$ALLOWED_SIGNERS_FILE"
    
    git config --global gpg.ssh.allowedSignersFile "$ALLOWED_SIGNERS_FILE"
    echo "✅ Local SSH signature verification configured for ${FINAL_EMAIL:-*}"
fi

TARGET_DIR="${WORKSPACE_DIR:-/nexus}"
if [ ! -d "$TARGET_DIR" ] && [ -d "$PWD" ]; then
    TARGET_DIR="$PWD"
fi
git config --global --add safe.directory "$TARGET_DIR"

# --- 5. PYTHON ENVIRONMENT ---
if [ -d "$TARGET_DIR" ]; then
    echo "🐍 Checking Python Environment in $TARGET_DIR..."

    if [ ! -d "$TARGET_DIR/.venv" ] || ! "$TARGET_DIR/.venv/bin/python" --version >/dev/null 2>&1; then
        echo "♻️ Creating Python virtual environment..."
        rm -rf "$TARGET_DIR/.venv"
        python3 -m venv "$TARGET_DIR/.venv"
    fi

    if [ -x "$TARGET_DIR/.venv/bin/pip" ]; then
        echo "📦 Synchronizing Python packages..."
        "$TARGET_DIR/.venv/bin/pip" install --upgrade pip --quiet
        "$TARGET_DIR/.venv/bin/pip" install pyright firebase-admin supabase --quiet
        if [ -f "$TARGET_DIR/requirements.txt" ]; then
            "$TARGET_DIR/.venv/bin/pip" install -r "$TARGET_DIR/requirements.txt"
        fi
        echo "✅ Python virtual environment ready."

        BASHRC="/home/vscode/.bashrc"
        if ! grep -qF "$TARGET_DIR/.venv/bin/activate" "$BASHRC" 2>/dev/null; then
            echo "" >> "$BASHRC"
            echo "# Auto-activate venv on interactive terminal launch" >> "$BASHRC"
            echo "if [ -f $TARGET_DIR/.venv/bin/activate ]; then source $TARGET_DIR/.venv/bin/activate; fi" >> "$BASHRC"
            echo "⚡ Added venv auto-activation to $BASHRC"
        fi
    else
        echo "⚠️ Failed to create virtual environment or pip binary missing."
    fi
fi

# --- 6. NPM & FLUTTER SETUP ---
if [ -f "$TARGET_DIR/package.json" ]; then 
    echo "📦 Synchronizing NPM packages..."
    cd "$TARGET_DIR" && npm ci --legacy-peer-deps
fi
if [ -d "$TARGET_DIR/mobile" ] && command -v flutter >/dev/null 2>&1; then 
    echo "🐦 Fetching Flutter dependencies..."
    cd "$TARGET_DIR/mobile" && flutter pub get
fi

# --- 7. EXTENSION SYNC ---
EXTENSIONS=(
  "ms-python.python" "ms-pyright.pyright" "ms-python.debugpy" 
  "ms-python.vscode-python-envs" "kevinrose.vsc-python-indent"
  "charliermarsh.ruff"
  "Dart-Code.flutter" "Dart-Code.dart-code"
  "esbenp.prettier-vscode" "formulahendry.auto-rename-tag"
  "christian-kohler.path-intellisense" "davidanson.vscode-markdownlint"
  "oderwat.indent-rainbow" "usernamehw.errorlens"
)

echo "🔍 Searching for primary IDE server binary..."
PRIMARY_CLI=""

while IFS= read -r binary_path; do
    if [ -n "$binary_path" ] && "$binary_path" --version >/dev/null 2>&1; then
        PRIMARY_CLI="$binary_path"
        break  # Found one valid CLI, stop searching!
    fi
done < <(find ~/.vscode-server ~/.antigravity-server ~/.antigravity-ide-server ~/.cursor-server -type f -executable \( -name "code-server" -o -name "antigravity-server" -o -name "antigravity-ide-server" -o -name "cursor-server" \) 2>/dev/null || true)

if [ -n "$PRIMARY_CLI" ]; then
    echo "🔧 Synchronizing extensions via primary binary: $PRIMARY_CLI"
    INSTALLED_EXTS=$("$PRIMARY_CLI" --list-extensions 2>/dev/null | tr '[:upper:]' '[:lower:]')

    for ext in "${EXTENSIONS[@]}"; do
        EXT_LOWER=$(echo "$ext" | tr '[:upper:]' '[:lower:]')
        if ! echo "$INSTALLED_EXTS" | grep -q "^${EXT_LOWER}$"; then
            echo "  ⬇️ Installing extension: $ext"
            "$PRIMARY_CLI" --install-extension "$ext" --force >/dev/null 2>&1 || true
        fi
    done
else
    echo "ℹ️ No active IDE server binaries running yet. Extensions will auto-install when IDE connects."
fi

echo "🎯 Initialization Complete!"
EOF

RUN sed -i 's/\r$//' /home/vscode/init_workspace.sh

# 5. User Environment Defaults & Entrypoint
USER vscode
WORKDIR /nexus
EXPOSE 3000 8000 8080 4000 5001 8081 8085 9099 54321 54322 54323
CMD ["sleep", "infinity"]