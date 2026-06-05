# syntax=docker/dockerfile:1.4

# Base Image
FROM mcr.microsoft.com/devcontainers/base:ubuntu-22.04@sha256:81380e4c9c14e8a629ff39029639e4b7893e67400246fa7782a0fe7dc193a02a

USER root

# Copy pinned artifacts if available
COPY pinned-artifacts.json /tmp/pinned-artifacts.json

# 1. System Dependencies, Java 17, Python 3, and Bulletproof SSH Setup
RUN apt-get update && apt-get install -y \
    openssh-server curl git unzip wget adb openjdk-17-jdk-headless apt-transport-https jq \
    python3 python3-pip python3-venv python-is-python3 \
    && mkdir /var/run/sshd \
    && echo 'vscode:root' | chpasswd \
    && echo 'root:root' | chpasswd \
    && sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin yes/' /etc/ssh/sshd_config \
    && sed -i 's/PasswordAuthentication no/PasswordAuthentication yes/' /etc/ssh/sshd_config \
    && echo "PubkeyAuthentication yes" >> /etc/ssh/sshd_config \
    && echo "StrictModes no" >> /etc/ssh/sshd_config

# 2. Node.js 24.14.1 + npm 11.11.0
ARG NPM_TARBALL_URL
ARG NPM_SHASUM

RUN mkdir -p /etc/apt/keyrings \
    && curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key | gpg --dearmor -o /etc/apt/keyrings/nodesource.gpg \
    && echo "deb [signed-by=/etc/apt/keyrings/nodesource.gpg] https://deb.nodesource.com/node_24.x nodistro main" > /etc/apt/sources.list.d/nodesource.list \
    && apt-get update && apt-get install -y nodejs \
    && if [ -f /tmp/pinned-artifacts.json ]; then \
        NPM_TARBALL_URL=${NPM_TARBALL_URL:-$(jq -r '.npm.url' /tmp/pinned-artifacts.json)}; \
        NPM_SHASUM=${NPM_SHASUM:-$(jq -r '.npm.shasum' /tmp/pinned-artifacts.json)}; \
    fi \
    && if [ -z "$NPM_TARBALL_URL" ] || [ -z "$NPM_SHASUM" ]; then echo "Missing URL or SHASUM for npm" >&2; exit 1; fi \
    && curl -fSL "$NPM_TARBALL_URL" -o /tmp/npm.tgz \
    && rm -rf /usr/lib/node_modules/npm \
    && mkdir -p /usr/lib/node_modules/npm \
    && tar -xz --strip-components=1 -C /usr/lib/node_modules/npm -f /tmp/npm.tgz \
    && rm -f /tmp/npm.tgz

# 3. Docker CLI, Supabase CLI, Playwright, Firebase CLI, and Infisical CLI
ARG PLAYWRIGHT_TARBALL_URL
ARG PLAYWRIGHT_SHASUM
ARG FIREBASE_TARBALL_URL
ARG FIREBASE_SHASUM
ARG INFISICAL_TARBALL_URL
ARG INFISICAL_SHASUM
ARG SUPABASE_TARBALL_URL
ARG SUPABASE_SHA256

RUN apt-get update && apt-get install -y ca-certificates gnupg \
     && install -m 0755 -d /etc/apt/keyrings \
     && curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg \
     && chmod a+r /etc/apt/keyrings/docker.gpg \
     && echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu jammy stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null \
     && apt-get update && apt-get install -y docker-ce-cli docker-buildx-plugin docker-compose-plugin \
     && if [ -f /tmp/pinned-artifacts.json ]; then \
            PLAYWRIGHT_TARBALL_URL=${PLAYWRIGHT_TARBALL_URL:-$(jq -r '.playwright.url' /tmp/pinned-artifacts.json)}; \
            PLAYWRIGHT_SHASUM=${PLAYWRIGHT_SHASUM:-$(jq -r '.playwright.shasum' /tmp/pinned-artifacts.json)}; \
            FIREBASE_TARBALL_URL=${FIREBASE_TARBALL_URL:-$(jq -r '.firebase.url' /tmp/pinned-artifacts.json)}; \
            FIREBASE_SHASUM=${FIREBASE_SHASUM:-$(jq -r '.firebase.shasum' /tmp/pinned-artifacts.json)}; \
            INFISICAL_TARBALL_URL=${INFISICAL_TARBALL_URL:-$(jq -r '.infisical.url' /tmp/pinned-artifacts.json)}; \
            INFISICAL_SHASUM=${INFISICAL_SHASUM:-$(jq -r '.infisical.shasum' /tmp/pinned-artifacts.json)}; \
            SUPABASE_TARBALL_URL=${SUPABASE_TARBALL_URL:-$(jq -r '.supabase.url' /tmp/pinned-artifacts.json)}; \
            SUPABASE_SHA256=${SUPABASE_SHA256:-$(jq -r '.supabase.sha256' /tmp/pinned-artifacts.json)}; \
        fi \
     && curl -fSL "$SUPABASE_TARBALL_URL" -o /tmp/supabase.tar.gz \
     && tar -xzf /tmp/supabase.tar.gz -C /tmp \
     && mv /tmp/supabase /usr/local/bin/ && chmod +x /usr/local/bin/supabase && rm -f /tmp/supabase.tar.gz \
     && for NAME in "playwright" "firebase-tools" "infisical"; do \
            case "$NAME" in \
                playwright) URL="$PLAYWRIGHT_TARBALL_URL"; SUM="$PLAYWRIGHT_SHASUM";; \
                firebase-tools) URL="$FIREBASE_TARBALL_URL"; SUM="$FIREBASE_SHASUM";; \
                infisical) URL="$INFISICAL_TARBALL_URL"; SUM="$INFISICAL_SHASUM";; \
            esac; \
            curl -fSL "$URL" -o /tmp/$NAME.tgz; \
            node /usr/lib/node_modules/npm/bin/npm-cli.js install -g /tmp/$NAME.tgz; \
            rm -f /tmp/$NAME.tgz; \
        done \
     && playwright install-deps

# Switch to vscode user for user-space SDKs
USER vscode
ENV HOME="/home/vscode"
ENV FLUTTER_HOME="$HOME/flutter-sdk"
ENV ANDROID_HOME="$HOME/android-sdk"
ENV DENO_INSTALL="$HOME/.deno"
ENV NODE_OPTIONS="--max-old-space-size=9216"
ENV PATH="$PATH:$FLUTTER_HOME/bin:$ANDROID_HOME/cmdline-tools/latest/bin:$ANDROID_HOME/platform-tools:$DENO_INSTALL/bin:$HOME/.pub-cache/bin"

# 4. Bake IDE Settings using Adaptive Relative Paths
RUN mkdir -p $HOME/.antigravity-server/data/Machine $HOME/.vscode-server/data/Machine \
    && SETTINGS='{"python.defaultInterpreterPath": "./.venv/bin/python", "python.analysis.diagnosticMode": "workspace", "dart.flutterSdkPath": "/home/vscode/flutter-sdk", "deno.enable": true, "deno.path": "/home/vscode/.deno/bin/deno"}' \
    && echo "$SETTINGS" > $HOME/.antigravity-server/data/Machine/settings.json \
    && echo "$SETTINGS" > $HOME/.vscode-server/data/Machine/settings.json

# 5. Deno Setup
RUN mkdir -p /tmp/deno_install \
    && wget -q https://github.com/denoland/deno/releases/latest/download/deno-x86_64-unknown-linux-gnu.zip -O /tmp/deno_install/deno.zip \
    && unzip -q /tmp/deno_install/deno.zip -d /tmp/deno_install \
    && mkdir -p $DENO_INSTALL/bin \
    && mv /tmp/deno_install/deno $DENO_INSTALL/bin/deno \
    && chmod +x $DENO_INSTALL/bin/deno \
    && rm -rf /tmp/deno_install

# 6. Android SDK Setup
RUN mkdir -p $ANDROID_HOME/cmdline-tools \
    && wget https://dl.google.com/android/repository/commandlinetools-linux-11076708_latest.zip -O /tmp/cmdline-tools.zip \
    && unzip -q /tmp/cmdline-tools.zip -d $ANDROID_HOME/cmdline-tools \
    && mv $ANDROID_HOME/cmdline-tools/cmdline-tools $ANDROID_HOME/cmdline-tools/latest \
    && rm /tmp/cmdline-tools.zip \
    && yes | $ANDROID_HOME/cmdline-tools/latest/bin/sdkmanager --licenses \
    && $ANDROID_HOME/cmdline-tools/latest/bin/sdkmanager "platform-tools" "platforms;android-34" "build-tools;34.0.0"

# 7. Flutter SDK Pre-cache
RUN git clone https://github.com/flutter/flutter.git -b stable $FLUTTER_HOME \
    && $FLUTTER_HOME/bin/flutter precache \
    && flutter config --android-sdk $ANDROID_HOME

# 8. Initialization Script (With Robust Diagnostics)
USER root
COPY --chown=vscode:vscode <<"EOF" /home/vscode/init_workspace.sh
#!/bin/bash
echo "🚀 Starting Fullstack Workspace Setup..."

# Git config global diversion
export GIT_CONFIG_GLOBAL="/home/vscode/.gitconfig_local"
if [ -f "/home/vscode/.gitconfig" ] && [ ! -f "$GIT_CONFIG_GLOBAL" ]; then
    cp /home/vscode/.gitconfig "$GIT_CONFIG_GLOBAL"
fi
chmod 644 "$GIT_CONFIG_GLOBAL" 2>/dev/null || true

# Secure SSH Setup
if [ -f "/tmp/mounted_ssh/id_ed25519" ]; then
    cp "/tmp/mounted_ssh/id_ed25519" "/home/vscode/.ssh/id_ed25519"
    chmod 700 /home/vscode/.ssh
    chmod 600 /home/vscode/.ssh/id_ed25519
    chown -R vscode:vscode /home/vscode/.ssh
    
    git config --global user.signingkey "/home/vscode/.ssh/id_ed25519"
    git config --global gpg.format ssh
    git config --global commit.gpgsign true
else
    echo "⚠️ Mounted key template missing from /tmp/mounted_ssh/id_ed25519"
fi

git config --global --add safe.directory /nexus

# --- DIAGNOSTIC PYTHON ENVIRONMENT MANAGER ---
echo "🔍 Scanning /nexus workspace configuration..."
if [ -d "/nexus" ]; then
    # Force purge any ghost links or files matching '.venv' that aren't real directories
    if [ -e "/nexus/.venv" ] && [ ! -d "/nexus/.venv" ]; then
        echo "⚠️ Detected a corrupted .venv node type. Cleaning file block..."
        rm -rf /nexus/.venv
    fi

    if [ ! -d "/nexus/.venv" ]; then
        echo "🐍 Compiling pristine Python Environment inside /nexus..."
        python3 -m venv /nexus/.venv
        /nexus/.venv/bin/pip install --upgrade pip
        /nexus/.venv/bin/pip install firebase-admin supabase
        if [ -f "/nexus/requirements.txt" ]; then
            echo "📄 Installing requirements.txt libraries..."
            /nexus/.venv/bin/pip install -r /nexus/requirements.txt
        fi
    else
        echo "✅ Python Environment (.venv) verified and ready."
    fi
else
    echo "❌ Error: Destination directory /nexus is unreachable by this script context!"
fi

# NPM & Flutter Workspace Setup
if [ -f "/nexus/package.json" ]; then 
    echo "📦 Synchronizing NPM packages..."
    cd /nexus && npm ci --legacy-peer-deps
fi
if [ -d "/nexus/mobile" ]; then 
    echo "🐦 Fetching Flutter dependencies..."
    cd /nexus/mobile && flutter pub get
fi

# --- UNIVERSAL IDE & ANTIGRAVITY EXTENSION INSTALLER ---
echo "📦 Insulating Extension Folders..."
mkdir -p ~/.vscode-server/extensions
mkdir -p ~/.antigravity-server/extensions
mkdir -p ~/.antigravity-ide-server/extensions
mkdir -p ~/.cursor-server/extensions

EXTENSIONS=(
  "ms-python.python" "ms-python.vscode-pylance" "ms-python.debugpy" 
  "ms-python.vscode-python-envs" "kevinrose.vsc-python-indent"
  "Dart-Code.flutter" "Dart-Code.dart-code" "dsznajder.es7-react-js-snippets"
  "esbenp.prettier-vscode" "bradlc.vscode-tailwindcss" "formulahendry.auto-rename-tag"
  "christian-kohler.path-intellisense" "christian-kohler.npm-intellisense" "vitest.explorer"
  "ms-playwright.playwright" "davidanson.vscode-markdownlint"
  "meezilla.json" "ms-vscode.vscode-typescript-next" "oderwat.indent-rainbow"
  "dbaeumer.vscode-eslint" "usernamehw.errorlens" "supabase.vscode-supabase-extension"
  "denoland.vscode-deno"
)

echo "🔍 Scanning for active server binaries..."
CLI_PATHS=()

# A. Standard wrapper profile checks
command -v code >/dev/null 2>&1 && CLI_PATHS+=("code")
command -v antigravity >/dev/null 2>&1 && CLI_PATHS+=("antigravity")

# B. UNRESTRICTED DEEP SEARCH FOR NESTED HASH RUNNERS
while IFS= read -r binary_path; do
    if [ -n "$binary_path" ]; then
        CLI_PATHS+=("$binary_path")
    fi
done < <(find ~ -type f -executable \( -name "code-server" -o -name "antigravity-server" -o -name "cursor-server" \) -not -path "*/.venv/*" -not -path "*/node_modules/*" 2>/dev/null || true)

if [ ${#CLI_PATHS[@]} -eq 0 ]; then
    echo "⚠️ Command wrappers not caught via search loop. Falling back to symlink cluster..."
else
    UNIQUE_CLIS=($(echo "${CLI_PATHS[@]}" | tr ' ' '\n' | sort -u | tr '\n' ' '))
    for CLI in "${UNIQUE_CLIS[@]}"; do
        echo "🔧 Executing forced toolchain delivery via: $CLI"
        for ext in "${EXTENSIONS[@]}"; do
            "$CLI" --install-extension "$ext" --force || true
        done
    done
fi

# C. THE EXTENSION REGISTRY SYMLINK MATRIX (Locks in compatibility)
# This forces all possible Antigravity and Cursor setups to share VS Code's extensions cache
echo "🔗 Hard-linking cross-platform extension targets..."
for TARGET_DIR in "$HOME/.antigravity-server" "$HOME/.antigravity-ide-server" "$HOME/.cursor-server"; do
    if [ -d "$TARGET_DIR" ]; then
        rm -rf "$TARGET_DIR/extensions"
        ln -s "$HOME/.vscode-server/extensions" "$TARGET_DIR/extensions" 2>/dev/null || true
        echo "✅ Linked $TARGET_DIR/extensions -> .vscode-server/extensions"
    fi
done

echo "🎯 Initialization Complete!"
EOF

RUN chmod +x /home/vscode/init_workspace.sh && chown vscode:vscode /home/vscode/init_workspace.sh

# 9. Auto-Trigger Script on First Terminal Open & Map Writable Git Config
USER vscode
RUN echo 'export GIT_CONFIG_GLOBAL="/home/vscode/.gitconfig_local"' >> ~/.bashrc \
    && echo "if [ ! -f ~/.workspace_initialized ]; then ~/init_workspace.sh && touch ~/.workspace_initialized; fi" >> ~/.bashrc

# 10. Ultimate Cross-User Keys-Sync Orchestrator
USER root
WORKDIR /nexus
EXPOSE 22 3000 8000 8080 4000 5001 8081 8085 9099 54321 54322 54323
CMD bash -c "\
sed -i 's/\r$//' /home/vscode/init_workspace.sh && \
mkdir -p /home/vscode/.ssh /root/.ssh && \
chmod 700 /home/vscode/.ssh /root/.ssh && \
if [ -f '/tmp/mounted_ssh/id_ed25519' ]; then \
    ssh-keygen -y -f /tmp/mounted_ssh/id_ed25519 > /tmp/keys_tmp && \
    cat /tmp/keys_tmp > /home/vscode/.ssh/authorized_keys && \
    cat /tmp/keys_tmp > /root/.ssh/authorized_keys && \
    rm -f /tmp/keys_tmp && \
    chmod 600 /home/vscode/.ssh/authorized_keys /root/.ssh/authorized_keys && \
    chown -R vscode:vscode /home/vscode/.ssh; \
fi && \
exec /usr/sbin/sshd -D"