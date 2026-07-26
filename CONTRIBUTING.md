# Contributing to Nexus

Thank you for your interest in contributing to Nexus! This guide will help you understand our development workflow and contribution process.

## Table of Contents

- [Getting Started](#getting-started)
- [Dev Container Setup (WSL2 / Windows)](#dev-container-setup-wsl2--windows)
- [Secret Management & Database Initialization](#secret-management--database-initialization)
- [Development Workflow](#development-workflow)
- [Versioning System](#versioning-system)
- [Pull Request Process](#pull-request-process)
- [Code Quality & Testing](#code-quality--testing)
- [Build Performance Tips](#build-performance-tips)
- [Commit Messages](#commit-messages)
- [For Maintainers Only](#for-maintainers-only)

## Getting Started

### Prerequisites

- **Docker Desktop** (with WSL2 integration enabled)
- **WSL2** (Linux distribution such as Ubuntu/Debian)
- **VS Code or Antigravity IDE** (with Dev Containers extension)

> **Note**: All language runtime SDKs (Python 3.12, Flutter 3.44, Node 24, Deno 2.9, Pyright, Ruff, Supabase CLI, Firebase Tools) are pre-installed inside the Dev Container image. External contributors do not need GPG keys, PAT tokens, or manual local SDK installations!

### Dev Container Setup (WSL2 / Windows)

For an isolated, reproducible development environment with pre-configured SDKs (Python 3.12, Flutter 3.44, Node 24, Deno 2.9, CLI tools, and automatic IDE extension syncing), follow these steps to build and run the dev container:

#### 1. Enable SSH Agent in Windows PowerShell

Ensure your SSH and commit-signing keys are loaded into the Windows SSH Agent:

```powershell
Set-Service -Name ssh-agent -StartupType Automatic
Start-Service ssh-agent
ssh-add $env:USERPROFILE\.ssh\id_ed25519
```

#### 2. Bridge SSH Agent to WSL2

In WSL2, install `socat`, download `npiperelay`, and bridge the Windows SSH pipe to Linux:

```bash
sudo apt update && sudo apt install -y socat

# Download npiperelay to bridge Windows named pipes to Linux sockets
curl -s https://api.github.com/repos/jstarks/npiperelay/releases/latest \
| grep "browser_download_url.*zip" \
| cut -d : -f 2,3 \
| tr -d \" \
| wget -qi - -O /tmp/npiperelay.zip

sudo unzip -o /tmp/npiperelay.zip npiperelay.exe -d /usr/local/bin/
sudo chmod +x /usr/local/bin/npiperelay.exe
rm /tmp/npiperelay.zip

# Self-healing SSH relay script to your ~/.bashrc
cat << 'EOF' >> ~/.bashrc
# --- SSH AGENT RELAY ---
export SSH_AUTH_SOCK="$HOME/.ssh/agent.sock"

# Test if SSH agent is actually responding end-to-end
ssh-add -l >/dev/null 2>&1
if [ $? -eq 2 ]; then
    # Kill stale relay processes and clean up socket/directory glitches
    pkill -f "npiperelay.exe" 2>/dev/null || true
    pkill -f "$SSH_AUTH_SOCK" 2>/dev/null || true
    rm -rf "$SSH_AUTH_SOCK"
    mkdir -p "$HOME/.ssh"

    # Spawn fresh relay
    if command -v npiperelay.exe >/dev/null 2>&1; then
        (nohup socat UNIX-LISTEN:"$SSH_AUTH_SOCK",fork EXEC:"npiperelay.exe -ei -s //./pipe/openssh-ssh-agent",nofork >/dev/null 2>&1 &)
    fi
fi
EOF

# Clean up potential Docker dummy directories & init socket
rm -rf ~/.ssh/agent.sock
source ~/.bashrc
```

#### 3. Clone Repository in WSL2

Clone the repository in your WSL2 home or projects directory:

```bash
git clone https://github.com/devakesu/Nexus.git
cd Nexus
```

#### 4. Build & Run Sandbox Container

Build the dev container image and launch the sandbox container with mapped ports and volume mounts:

```bash
# 1. Verify SSH agent connection (must return your keys, not an error)
ssh-add -l

# 2. Build dev container image
docker build -t nexus-sandbox -f .devcontainer/Dockerfile .

# 3. Launch sandbox container
docker run -d --name Nexus_Sandbox \
  --restart unless-stopped \
  -v "$(pwd):/nexus" \
  -v /var/run/docker.sock:/var/run/docker.sock \
  -v "$HOME/.ssh/agent.sock:/run/host-services/ssh-auth.sock" \
  -e SSH_AUTH_SOCK="/run/host-services/ssh-auth.sock" \
  -p 3000:3000 -p 8000:8000 -p 8080:8080 -p 4000:4000 -p 5001:5001 \
  -p 8081:8081 -p 8085:8085 -p 9099:9099 \
  -p 54321:54321 -p 54322:54322 -p 54323:54323 \
  nexus-sandbox
```

#### 5. Attach IDE & Initialize Workspace

1. Open **VS Code** or **Antigravity IDE**.
2. Press `Ctrl+Shift+P` (or `Cmd+Shift+P`) and choose **Attach to Running Container** $\rightarrow$ select **`Nexus_Sandbox`**.
3. Open folder **`/nexus`** inside the attached container.
4. Run workspace initialization script in the container terminal:

   ```bash
   ~/init_workspace.sh
   ```

   *(Enter Git Name and Email when prompted to configure local commit identity and SSH key signing).*
5. Run **`Developer: Reload Window`** in VS Code / Antigravity to refresh environment variables, PATH, and extension integrations.

#### 6. Android Emulator Setup & Subsequent Development Startups

To run and debug the mobile application using an Android Emulator:

1. **Android Emulator Configuration**:
   - Create an Android Virtual Device (AVD) named **`Pixel_10_Pro_XL`** in Android Studio's AVD Manager.
   - *(Note: If using a different AVD name, edit line 67 in [.devcontainer/Start.ps1](file:///.devcontainer/Start.ps1) to match your custom AVD name).*

2. **Subsequent Starts via `Start.ps1` (Windows Host)**:
   - On subsequent development startups (after initial `docker run` setup), execute the environment launcher script from Windows PowerShell on the host:

     ```powershell
     .\.devcontainer\Start.ps1
     ```

   - Choose **`[1] Emulator`** (or pass `-Mode Emulator`).
   - The script will automatically verify Docker Desktop, start the `Nexus_Sandbox` container if stopped, launch the `Pixel_10_Pro_XL` host emulator, bridge Windows ADB (`5555`) to Docker network (`host.docker.internal:5555`), and open Dart VM service port (`8181`).
   - When finished, press `ENTER` in the PowerShell window to cleanly tear down the emulator and remove port proxies.

#### 7. Create Feature Branch

Inside the container terminal (or repository root), create and checkout your working feature branch:

```bash
git checkout -b feature/your-feature-name
```

#### Automated Features of `~/init_workspace.sh`

- **SSH Key & Signature Verification**: Configures `git config --global gpg.format ssh` using forwarded SSH keys and sets up `~/.ssh/allowed_signers` for local signature verification.
- **Git Identity**: Prompts for Name and Email if not set, storing them safely in `~/.gitconfig_local`.
- **Python Environment**: Automatically creates `/nexus/.venv` (Python 3.12), installs dependencies from `requirements.txt`, and configures auto-activation in `/home/vscode/.bashrc`.
- **NPM & Flutter Dependencies**: Automatically synchronizes Node packages (`npm ci`) and Flutter packages (`flutter pub get`).
- **Universal Extension Installer**: Automatically detects active IDE server binaries (VS Code, Antigravity IDE, Cursor) and installs required extensions (Python, Pyright, Ruff, Flutter, Dart, Prettier, Tailwind, ESLint, ErrorLens, Deno, etc.).

### Secret Management & Database Initialization

Before starting local development or testing, authenticate with Infisical CLI and link your Supabase instance:

#### 1. Infisical Authentication

```bash
infisical login
```

#### 2. Supabase Initialization & Linking

```bash
# Log in to Supabase CLI
supabase login

# Link repository workspace to remote Supabase project
supabase link --project-ref <your-supabase-project-ref>

# Apply local schema migrations
supabase db push
```

**That's all you need to start developing!** For advanced maintainer setup (Infisical, deployment), see [For Maintainers Only](#for-maintainers-only) at the bottom of this guide.

## Development Workflow

### Available Commands

#### Backend Application (Python/FastAPI)

```bash
# Install dependencies
pip install --require-hashes -r requirements.txt

# Start local development server
infisical run --env=dev --projectId=xxxx --path /public --path /runtime -- .venv/bin/uvicorn app.main:app --reload --reload-dir app --host 0.0.0.0 --port 8000 --ssl-certfile .certificates/localhost.pem --ssl-keyfile .certificates/localhost-key.pem

# Run backend test suite
.venv/bin/pytest

# Lint backend code
ruff check .

# Format backend code
ruff format .
```

#### Mobile Application (Flutter/Dart)

```bash
cd mobile

# Install dependencies
flutter pub get

# Run on device/emulator
infisical run --env=prod --projectId=xxxx --path /public -- sh -c '
  export DART_VM_OPTIONS="--bind-address=0.0.0.0"
  flutter run \
    --flavor nexus \
    --host-vmservice-port=8181 \
    --dart-define=APP_DOMAIN="$APP_DOMAIN" \
    --dart-define=BACKEND_URL="$BACKEND_URL" \
    --dart-define=GOOGLE_IOS_CLIENT_ID_NEXUS="$GOOGLE_IOS_CLIENT_ID_NEXUS" \
    --dart-define=GOOGLE_IOS_CLIENT_ID_NEXUS_MEC="$GOOGLE_IOS_CLIENT_ID_NEXUS_MEC" \
    --dart-define=SUPABASE_URL="$SUPABASE_URL" \
    --dart-define=SUPABASE_PUBLISHABLE_KEY="$SUPABASE_PUBLISHABLE_KEY" \
    --dart-define=GOOGLE_WEB_CLIENT_ID="$GOOGLE_WEB_CLIENT_ID" \
    --dart-define=SPOTIFY_CLIENT_ID="$SPOTIFY_CLIENT_ID" \
    --dart-define=SPOTIFY_REDIRECT_URI_NEXUS="$SPOTIFY_REDIRECT_URI_NEXUS" \
    --dart-define=GOOGLE_PLACES_API_KEY="$GOOGLE_PLACES_API_KEY"
'

# Run Flutter tests
flutter test

# Verify formatting
dart format .

# Run static analysis
flutter analyze
```

### Making Changes

1. Create a feature branch from `main`
2. Make your changes
3. Write or update tests
4. Ensure checks pass locally:
   - For backend: `pytest && ruff check .`
   - For mobile: `flutter test && flutter analyze`
5. Commit with clear messages (see [Commit Messages](#commit-messages))
6. Push and create a Pull Request

**Important**: Centralized version values apply automatically via our pre-commit and post-checkout Git hooks.

## Versioning System

Nexus manages its mobile app versioning automatically via Git branch names and the [`scripts/sync-version.py`](scripts/sync-version.py) script:

- **Release Branches:** When you create or checkout a release branch named `release/X.Y.Z` or `vX.Y.Z`, the version in [`mobile/pubspec.yaml`](mobile/pubspec.yaml) is automatically bumped to `X.Y.Z+1`.
- **Validation:** The local pre-commit hook guarantees that your branch version is greater than or equal to the current pubspec version and follows correct semantic formatting.

## Pull Request Process

### Creating a PR

1. Push your branch to GitHub
2. Open a Pull Request against `main`
3. Fill in the PR template:
   - Description of changes
   - Related issue numbers
   - Testing notes
4. Request review from maintainers

### PR Checklist

- [ ] Backend tests pass (`pytest`)
- [ ] Mobile tests pass (`flutter test`)
- [ ] Code styles & formatting check out
- [ ] Documentation updated (if needed)
- [ ] Commit messages follow conventions

### Review & Merge

1. Automated checks run on your PR (Backend pytest + Mobile static analysis & coverage)
2. Maintainers review your code
3. Address feedback or requested changes
4. Once approved, the maintainer merges the PR

## Code Quality & Testing

### Linting & Static Analysis

```bash
# Backend (ruff & pyright)
ruff check .
pyright

# Mobile (dart format & flutter analyze)
dart format --output=none --set-exit-if-changed .
flutter analyze
```

### Code Style Guidelines

- Follow existing Python patterns in the `app/` folder.
- Use explicit type annotations for Python and Dart functions.
- Add comments for complex logic and safety-sensitive workflows.
- Keep functions small and focused.
- Test edge cases, error conditions, and user-privacy features (like safety dials, meetup safety sessions, etc.).

## Build Performance Tips

Our Docker builds are optimized with multi-stage builds, runtime secret injection, and caching layers.

### Local Docker Testing

```bash
# Build Docker image locally
docker build -t nexus:test .
```

## Commit Messages

Follow conventional commit format:

```text
<type>(<scope>): <subject>
```

### Types

- `feat`: New feature
- `fix`: Bug fix
- `docs`: Documentation only
- `style`: Code style (formatting, no logic change)
- `refactor`: Code restructuring
- `test`: Adding/updating tests
- `chore`: Maintenance (deps, version bumps)
- `perf`: Performance improvement
- `ci`: CI/CD changes

### Examples

```bash
feat(spotify): add custom playlist matching signal
fix(auth): handle expired campus email domains on NEXUS_MEC
docs: update meetup-safety guidelines
chore: bump dependencies
```

## Getting Help

- **Bug Reports & Features:** Submit via the templates in `.github/ISSUE_TEMPLATE`
- **Questions & Ideas:** Reach out to the maintainers or open an issue
- **Contact:** Find direct channels on [nexus.devakesu.com/contact](https://nexus.devakesu.co/contact)

---

## For Maintainers Only

> **⚠️ This section is for repository maintainers with write access only.**  
> External contributors can skip this section entirely.

### Secret Management (Infisical)

- Centralized management via the Infisical Dashboard acts as the single source of truth, organized into `/public`, `/runtime`, and `/ci` folders.
- Production environments inject secrets dynamically at boot time using the Infisical CLI wrapper.
- External contributors don't need access to Infisical to run and develop the app locally.

### Licensing

By contributing, you agree that your contributions will be licensed under the project's GNU Affero General Public License v3 (AGPL-3.0).

---

Thank you for contributing to Nexus! 🚀
