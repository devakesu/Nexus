#!/usr/bin/env bash
set -euo pipefail

# ==============================================================================
# Global Configuration & Tool Toggles (Set to 'false' to skip specific tools)
# ==============================================================================
UPDATE_ALL="${UPDATE_ALL:-false}"

ENABLE_ANDROID="${ENABLE_ANDROID:-true}"
ENABLE_FLUTTER="${ENABLE_FLUTTER:-true}"
ENABLE_DENO="${ENABLE_DENO:-false}"
ENABLE_SUPABASE="${ENABLE_SUPABASE:-true}"
ENABLE_GH="${ENABLE_GH:-true}"
ENABLE_FIREBASE="${ENABLE_FIREBASE:-true}"
ENABLE_INFISICAL="${ENABLE_INFISICAL:-true}"
ENABLE_PLAYWRIGHT="${ENABLE_PLAYWRIGHT:-false}"
ENABLE_SHELL_CONFIG="${ENABLE_SHELL_CONFIG:-true}"

DEV_HUB_ROOT="${HOME}/dev-hub"
SDKS_DIR="${DEV_HUB_ROOT}/sdks"
BIN_DIR="${DEV_HUB_ROOT}/bin"
CACHES_DIR="${DEV_HUB_ROOT}/caches"

# --- Guard 1: Automatic Temp Cleanup on Exit/Interrupt ---
TMP_WORK_DIR=$(mktemp -d -t dev_hub_tmp_XXXXXX)
cleanup() {
    rm -rf "${TMP_WORK_DIR}"
}
trap cleanup EXIT INT TERM

echo "🚀 Initializing Global Dev Hub at: ${DEV_HUB_ROOT}"

if [ -d "${HOME}/.gitconfig" ]; then
    echo "⚠️ Found ~/.gitconfig as a directory. Fixing..."
    rm -rf "${HOME}/.gitconfig"
    touch "${HOME}/.gitconfig"
fi

mkdir -p "${SDKS_DIR}" \
         "${BIN_DIR}" \
         "${CACHES_DIR}/gradle" \
         "${CACHES_DIR}/pub-cache" \
         "${CACHES_DIR}/npm" \
         "${CACHES_DIR}/pip" \
         "${CACHES_DIR}/playwright-browsers" \
         "${CACHES_DIR}/vscode-extensions" \
         "${CACHES_DIR}/antigravity-ide-server"s

export PATH="${BIN_DIR}:${PATH}"

# ==============================================================================
# 1. System Dependencies Check
# ==============================================================================
echo "📦 Verifying WSL host prerequisites..."
REQUIRED_TOOLS=("curl" "wget" "unzip" "tar" "jq" "git" "sha256sum")
MISSING_TOOLS=()

for tool in "${REQUIRED_TOOLS[@]}"; do
    if ! command -v "$tool" >/dev/null 2>&1; then
        MISSING_TOOLS+=("$tool")
    fi
done

if [ ${#MISSING_TOOLS[@]} -ne 0 ]; then
    echo "⚠️ Installing missing host tools: ${MISSING_TOOLS[*]}"
    sudo apt-get update && sudo apt-get install -y --no-install-recommends "${MISSING_TOOLS[@]}"
fi


# ==============================================================================
# 2. Android SDK Setup
# ==============================================================================
ANDROID_HOME="${SDKS_DIR}/android"
if [ "${ENABLE_ANDROID}" = "true" ]; then
    echo "🤖 Setting up Android SDK at: ${ANDROID_HOME}"

    # 1. Validate existing installation; purge if broken
    if [ -d "${ANDROID_HOME}/cmdline-tools/latest" ]; then
        if ! "${ANDROID_HOME}/cmdline-tools/latest/bin/sdkmanager" --version >/dev/null 2>&1; then
            echo "⚠️ Android cmdline-tools installation is corrupt. Re-installing..."
            rm -rf "${ANDROID_HOME}/cmdline-tools"
        fi
    fi

    # 2. Download and install commandline-tools if missing
    if [ ! -d "${ANDROID_HOME}/cmdline-tools/latest" ]; then
        mkdir -p "${ANDROID_HOME}/cmdline-tools"
        CMDLINE_URL="https://dl.google.com/android/repository/commandlinetools-linux-11076708_latest.zip"
        
        echo "  ⬇️ Downloading Android Commandline Tools..."
        wget -q "${CMDLINE_URL}" -O "${TMP_WORK_DIR}/cmdline-tools.zip"
        unzip -q "${TMP_WORK_DIR}/cmdline-tools.zip" -d "${TMP_WORK_DIR}/cmdline-tools"
        mv "${TMP_WORK_DIR}/cmdline-tools/cmdline-tools" "${ANDROID_HOME}/cmdline-tools/latest"
    fi

    # 3. Export PATH so sdkmanager is in environment
    export PATH="${ANDROID_HOME}/cmdline-tools/latest/bin:${ANDROID_HOME}/platform-tools:${PATH}"

    # 4. Accept Android licenses
    yes | sdkmanager --licenses >/dev/null 2>&1 || true

    # 5. Detect and install latest platform & build tools
    # 5. Detect and install latest STABLE platform & build tools
    echo "  🔄 Detecting latest stable Android Platform & Build Tools..."

    # Filter out previews, betas, and release candidates (-beta, -rc, preview, etc.)
    LATEST_PLATFORM=$(sdkmanager --list 2>/dev/null | grep -E '^\s*platforms;android-[0-9]+(\s|$)' | awk '{print $1}' | sort -V | tail -n 1)
    LATEST_BUILD_TOOLS=$(sdkmanager --list 2>/dev/null | grep -E '^\s*build-tools;[0-9]+\.[0-9]+\.[0-9]+(\s|$)' | awk '{print $1}' | sort -V | tail -n 1)

    # Fallback defaults if network list fails
    LATEST_PLATFORM="${LATEST_PLATFORM:-platforms;android-36}"
    LATEST_BUILD_TOOLS="${LATEST_BUILD_TOOLS:-build-tools;36.0.0}"

    echo "  📦 Installing: platform-tools, ${LATEST_PLATFORM}, ${LATEST_BUILD_TOOLS}, and build-tools;28.0.3"
    sdkmanager "platform-tools" "build-tools;28.0.3" "${LATEST_PLATFORM}" "${LATEST_BUILD_TOOLS}" >/dev/null
else
    echo "⏩ Skipping Android SDK (ENABLE_ANDROID=false)"
fi

# ==============================================================================
# 3. Flutter SDK Setup
# ==============================================================================
FLUTTER_HOME="${SDKS_DIR}/flutter"
if [ "${ENABLE_FLUTTER}" = "true" ]; then
    echo "🐦 Setting up Flutter SDK at: ${FLUTTER_HOME}"

    if [ -d "${FLUTTER_HOME}" ]; then
        if ! git -C "${FLUTTER_HOME}" rev-parse --git-dir >/dev/null 2>&1; then
            echo "⚠️ Found corrupted/interrupted Flutter directory. Cleaning up..."
            rm -rf "${FLUTTER_HOME}"
        fi
    fi

    if [ ! -d "${FLUTTER_HOME}" ]; then
        echo "  ⬇️ Cloning Flutter Stable Channel..."
        git clone https://github.com/flutter/flutter.git -b stable "${FLUTTER_HOME}"
    else
        echo "  🔄 Flutter SDK present. Pulling latest stable..."
        git -C "${FLUTTER_HOME}" pull --quiet || true
    fi

    export PATH="${FLUTTER_HOME}/bin:${PATH}"
    flutter config --no-analytics >/dev/null
    if [ "${ENABLE_ANDROID}" = "true" ]; then
        flutter config --android-sdk "${ANDROID_HOME}" >/dev/null
    fi
    echo "  ⚡ Pre-caching Flutter artifacts..."
    flutter precache --android >/dev/null
else
    echo "⏩ Skipping Flutter SDK (ENABLE_FLUTTER=false)"
fi

# ==============================================================================
# 4. Deno Setup
# ==============================================================================
DENO_HOME="${SDKS_DIR}/deno"
if [ "${ENABLE_DENO}" = "true" ]; then
    echo "🦕 Setting up Deno at: ${DENO_HOME}"

    IS_DENO_VALID=false
    if [ -x "${DENO_HOME}/bin/deno" ] && "${DENO_HOME}/bin/deno" --version >/dev/null 2>&1; then
        IS_DENO_VALID=true
    fi

    if [ "${IS_DENO_VALID}" = "false" ] || [ "${UPDATE_ALL}" = "true" ]; then
        mkdir -p "${DENO_HOME}/bin"
        echo "  ⬇️ Fetching Deno binary..."
        wget -q https://github.com/denoland/deno/releases/latest/download/deno-x86_64-unknown-linux-gnu.zip -O "${TMP_WORK_DIR}/deno.zip"
        unzip -q "${TMP_WORK_DIR}/deno.zip" -d "${TMP_WORK_DIR}/deno_bin"
        mv "${TMP_WORK_DIR}/deno_bin/deno" "${DENO_HOME}/bin/deno"
        chmod +x "${DENO_HOME}/bin/deno"
    fi
else
    echo "⏩ Skipping Deno (ENABLE_DENO=false)"
fi

# ==============================================================================
# 5. CLI Tools Setup
# ==============================================================================
echo "🛠️ Processing CLI tools in ${BIN_DIR} (UPDATE_ALL=${UPDATE_ALL})..."

is_valid_binary() {
    local bin_path="$1"
    [ -x "${bin_path}" ] && "${bin_path}" --version >/dev/null 2>&1
}

# --- Supabase CLI ---
if [ "${ENABLE_SUPABASE}" = "true" ]; then
    if ! is_valid_binary "${BIN_DIR}/supabase" || [ "${UPDATE_ALL}" = "true" ]; then
        echo "  ⬇️ Fetching Supabase CLI..."
        SUPABASE_URL=$(curl -s https://api.github.com/repos/supabase/cli/releases/latest | jq -r '.assets[] | select(.name | contains("linux_amd64.tar.gz")) | .browser_download_url' | head -n 1)
        if [ -n "${SUPABASE_URL}" ]; then
            curl -fSL "${SUPABASE_URL}" -o "${TMP_WORK_DIR}/supabase.tar.gz"
            tar -xzf "${TMP_WORK_DIR}/supabase.tar.gz" -C "${TMP_WORK_DIR}"
            mv "${TMP_WORK_DIR}/supabase" "${BIN_DIR}/supabase"
            chmod +x "${BIN_DIR}/supabase"
        fi
    fi
else
    echo "⏩ Skipping Supabase CLI (ENABLE_SUPABASE=false)"
fi

# --- GitHub CLI (gh) ---
if [ "${ENABLE_GH}" = "true" ]; then
    if ! is_valid_binary "${BIN_DIR}/gh" || [ "${UPDATE_ALL}" = "true" ]; then
        echo "  ⬇️ Fetching GitHub CLI..."
        GH_URL=$(curl -s https://api.github.com/repos/cli/cli/releases/latest | jq -r '.assets[] | select(.name | contains("linux_amd64.tar.gz")) | .browser_download_url' | head -n 1)
        if [ -n "${GH_URL}" ]; then
            curl -fSL "${GH_URL}" -o "${TMP_WORK_DIR}/gh.tar.gz"
            tar -xzf "${TMP_WORK_DIR}/gh.tar.gz" -C "${TMP_WORK_DIR}"
            find "${TMP_WORK_DIR}" -type f -name "gh" -exec mv {} "${BIN_DIR}/gh" \;
            chmod +x "${BIN_DIR}/gh"
        fi
    fi
else
    echo "⏩ Skipping GitHub CLI (ENABLE_GH=false)"
fi

# --- Firebase CLI ---
if [ "${ENABLE_FIREBASE}" = "true" ]; then
    if ! is_valid_binary "${BIN_DIR}/firebase" || [ "${UPDATE_ALL}" = "true" ]; then
        echo "  ⬇️ Fetching Standalone Firebase CLI..."
        wget -q https://firebase.tools/bin/linux/latest -O "${TMP_WORK_DIR}/firebase"
        chmod +x "${TMP_WORK_DIR}/firebase"
        mv "${TMP_WORK_DIR}/firebase" "${BIN_DIR}/firebase"
    fi
else
    echo "⏩ Skipping Firebase CLI (ENABLE_FIREBASE=false)"
fi

# --- Infisical CLI ---
if [ "${ENABLE_INFISICAL}" = "true" ]; then
    if ! is_valid_binary "${BIN_DIR}/infisical" || [ "${UPDATE_ALL}" = "true" ]; then
        echo "  ⬇️ Fetching Infisical CLI..."
        INFISICAL_URL=$(curl -s https://api.github.com/repos/Infisical/infisical/releases/latest | jq -r '.assets[] | select(.name | contains("linux_amd64.tar.gz")) | .browser_download_url' | head -n 1)
        if [ -n "${INFISICAL_URL}" ]; then
            curl -fSL "${INFISICAL_URL}" -o "${TMP_WORK_DIR}/infisical.tar.gz"
            tar -xzf "${TMP_WORK_DIR}/infisical.tar.gz" -C "${TMP_WORK_DIR}"
            find "${TMP_WORK_DIR}" -type f -name "infisical" -exec mv {} "${BIN_DIR}/infisical" \;
            chmod +x "${BIN_DIR}/infisical"
        fi
    fi
else
    echo "⏩ Skipping Infisical CLI (ENABLE_INFISICAL=false)"
fi

# ==============================================================================
# 6. Playwright Browser Binaries Pre-cache
# ==============================================================================
if [ "${ENABLE_PLAYWRIGHT}" = "true" ]; then
    echo "🎭 Setting up Playwright shared browser cache..."
    export PLAYWRIGHT_BROWSERS_PATH="${CACHES_DIR}/playwright-browsers"
    if command -v npx >/dev/null 2>&1; then
        npx playwright install chromium firefox webkit --with-deps >/dev/null 2>&1 || true
    fi
else
    echo "⏩ Skipping Playwright Browsers (ENABLE_PLAYWRIGHT=false)"
fi

# ==============================================================================
# 7. WSL Host Shell Integration
# ==============================================================================
if [ "${ENABLE_SHELL_CONFIG}" = "true" ]; then
    echo "🔗 Configuring WSL host shell environment paths..."

    ENV_MARKER="# --- Global Dev Hub Paths ---"
    ENV_BLOCK=$(cat << 'EOF'
# --- Global Dev Hub Paths ---
export DEV_HUB="${HOME}/dev-hub"
export FLUTTER_HOME="${DEV_HUB}/sdks/flutter"
export ANDROID_HOME="${DEV_HUB}/sdks/android"
export DENO_INSTALL="${DEV_HUB}/sdks/deno"
export PATH="${PATH}:${DEV_HUB}/bin:${FLUTTER_HOME}/bin:${ANDROID_HOME}/cmdline-tools/latest/bin:${ANDROID_HOME}/platform-tools:${DENO_INSTALL}/bin"
EOF
    )

    for RC_FILE in "${HOME}/.bashrc" "${HOME}/.zshrc"; do
        if [ -f "${RC_FILE}" ]; then
            if ! grep -qF "${ENV_MARKER}" "${RC_FILE}"; then
                echo "" >> "${RC_FILE}"
                echo "${ENV_BLOCK}" >> "${RC_FILE}"
                echo "  ✅ Configured paths in ${RC_FILE}"
            fi
        fi
    done
else
    echo "⏩ Skipping shell config integration (ENABLE_SHELL_CONFIG=false)"
fi

# ==============================================================================
# 8. Permissions Normalization
# ==============================================================================
echo "🔐 Setting permissions across ${DEV_HUB_ROOT}..."
chmod -R 777 "${CACHES_DIR}"
chmod -R 755 "${SDKS_DIR}" "${BIN_DIR}"

echo "=========================================================================="
echo "✨ Global Dev Hub Initialization Complete!"
echo "📁 Root Path: ${DEV_HUB_ROOT}"
echo "=========================================================================="