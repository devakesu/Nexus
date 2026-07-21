# Contributing to Nexus

Thank you for your interest in contributing to Nexus! This guide will help you understand our development workflow and contribution process.

> **👋 For External Contributors**: You do not need GPG keys, PAT tokens, or any special setup! Just fork, code, and submit a PR. The Git version hooks will automatically validate and sync your branch versions. See [Quick Setup](#quick-setup) below.

## Table of Contents

- [Getting Started](#getting-started)
- [Development Workflow](#development-workflow)
- [Versioning System](#versioning-system)
- [Pull Request Process](#pull-request-process)
- [Code Quality & Testing](#code-quality--testing)
- [Build Performance Tips](#build-performance-tips)
- [Commit Messages](#commit-messages)
- [For Maintainers Only](#for-maintainers-only)

## Getting Started

### Prerequisites

- **Python**: 3.14+
- **Flutter SDK**: 3.12+ (for mobile development)
- **Dart SDK**: ^3.12.1 (bundled with Flutter)
- **Git**: Latest version

**That's it!** External contributors don't need GPG keys, GitHub PAT tokens, or access to secrets.

### Quick Setup

```bash
# 1. Fork and clone
git clone https://github.com/YOUR_USERNAME/Nexus.git
cd Nexus

# 2. Configure local git hooks for auto-formatting and version checking
git config core.hooksPath .githooks

# 3. Create feature branch
git checkout -b feature/your-feature-name
```

**That's all you need to start developing!** For advanced maintainer setup (Infisical, deployment), see [For Maintainers Only](#for-maintainers-only) at the bottom of this guide.

## Development Workflow

### Available Commands

#### Backend Application (Python/FastAPI)

```bash
# Install dependencies
pip install -r requirements.txt

# Start local development server
uvicorn app.main:app --reload --reload-dir app

# Run backend test suite
pytest

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
flutter run

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

- Centralized management via the Infisical Dashboard acts as the single source of truth, organized into `/build-time`, `/runtime`, and `/ci` folders.
- Production environments inject secrets dynamically at boot time using the Infisical CLI wrapper.
- External contributors don't need access to Infisical to run and develop the app locally.

### Licensing

By contributing, you agree that your contributions will be licensed under the project's GNU Affero General Public License v3 (AGPL-3.0).

---

Thank you for contributing to Nexus! 🚀
