# Nexus

![Nexus](mobile/assets/nexus.png)

[![Version](https://img.shields.io/github/v/release/devakesu/Nexus?label=Version)](https://github.com/devakesu/Nexus/releases/latest)
[![License: AGPL v3](https://img.shields.io/badge/License-AGPLv3-blue.svg)](https://www.gnu.org/licenses/agpl-3.0)
[![OpenSSF Scorecard](https://api.scorecard.dev/projects/github.com/devakesu/Nexus/badge)](https://scorecard.dev/viewer/?uri=github.com/devakesu/Nexus)
[![CodeQL](https://github.com/devakesu/Nexus/actions/workflows/codeql.yml/badge.svg)](https://github.com/devakesu/Nexus/actions/workflows/codeql.yml)
[![SLSA Level 3](https://slsa.dev/images/gh-badge-level3.svg)](https://slsa.dev)
[![Attestations](https://img.shields.io/badge/Attestations-View-brightgreen?logo=github)](https://github.com/devakesu/Nexus/attestations)
[![OpenSSF Best Practices](https://www.bestpractices.dev/projects/11930/badge)](https://www.bestpractices.dev/projects/11930)
[![Security Scan: Trivy](https://img.shields.io/badge/Security-Trivy%20Scanned-blue)](.github/workflows/release.yml)

<!-- markdownlint-disable MD033 -->
<p align="center">
  <img src="https://img.shields.io/badge/FastAPI-0.136.6-009688?style=for-the-badge&logo=fastapi&logoColor=white" alt="FastAPI" />
  <img src="https://img.shields.io/badge/Python-3.11+-3776AB?style=for-the-badge&logo=python&logoColor=white" alt="Python" />
  <img src="https://img.shields.io/badge/Supabase-2.30.1-3ECF8E?style=for-the-badge&logo=supabase&logoColor=white" alt="Supabase" />
  <img src="https://img.shields.io/badge/Pydantic-2.13.4-E92063?style=for-the-badge&logo=pydantic&logoColor=white" alt="Pydantic" />
</p>
<p align="center">
  <img src="https://img.shields.io/badge/Flutter-3.12+-02569B?style=for-the-badge&logo=flutter&logoColor=white" alt="Flutter" />
  <img src="https://img.shields.io/badge/Android-10+-3DDC84?style=for-the-badge&logo=android&logoColor=black" alt="Android" />
  <img src="https://img.shields.io/badge/iOS-13+-000000?style=for-the-badge&logo=apple&logoColor=white" alt="iOS" />
</p>
<p align="center">
  <img src="https://img.shields.io/badge/Pytest-8.4.1-0A9EDC?style=for-the-badge&logo=pytest&logoColor=white" alt="Pytest" />
  <img src="https://img.shields.io/badge/Docker-Reproducible-2496ED?style=for-the-badge&logo=docker&logoColor=white" alt="Docker" />
  <img src="https://img.shields.io/badge/Cosign-Signed-FF6B6B?style=for-the-badge&logo=sigstore&logoColor=white" alt="Cosign" />
</p>
<!-- markdownlint-enable MD033 -->

## Overview

**Nexus** is a cosmic-themed, authentic social discovery app built for young adults looking to discover and connect with new people nearby in real-world moments. Unlike conventional swipe-card dating apps, Nexus emphasizes spontaneous, in-the-moment human connections across multiple social dimensions—whether you are looking for new friends, professional connections, or romance.

Nexus ships in two distinct product flavors from a single unified codebase:

- **`nexus` (General Audience)**: Open to any email domain for general social discovery.
- **`nexus_mec` (Campus-Gated)**: Gated strictly to verified campus email domains (`@mec.ac.in`), creating a trusted, student-only community experience.

Engineered with a BeReal-style authentic and spontaneous brand personality, Nexus pairs vector-based similarity algorithms (`Nexus_Engine`) with real-time Spotify audio taste matching. Crucially, **safety is built as a first-class product surface**, featuring a complete Safety Center, active meetup safety check-in alerts, and Signal Protocol end-to-end encrypted (E2EE) chats.

## 📲 Get the Mobile App

<!-- markdownlint-disable MD033 -->
<p align="center">
  <a href="https://play.google.com/store/apps/details?id=com.devakesu.apps.nexus" target="_blank" rel="noopener noreferrer">
    <img src="https://play.google.com/intl/en_us/badges/static/images/badges/en_badge_web_generic.png" alt="Get it on Google Play" width="260" />
  </a>
</p>
<!-- markdownlint-enable MD033 -->

## 🎯 Key Vibes

- **Orbit Social Discovery 🌌**: An intuitive visual discovery space ("the Orbit screen") connecting nearby people with mode-specific signal colors: **Dating** (`#FF4F81`), **Friends** (`#A45E00`), and **Professional** (`#007E6D`).
- **Spotify Taste Signal 🎵**: Express your personality through shared musical vibes with real-time Spotify top tracks and artists, securely encrypted at rest via AES-256-GCM.
- **Signal Protocol E2EE Chat 🔐**: Industry-standard Double Ratchet end-to-end encryption (`libsignal_protocol_dart`) ensuring messaging conversations remain strictly confidential between sender and receiver.
- **First-Class Safety Center 🛡️**: Comprehensive safety tools including active meetup check-in alerts, emergency contact notifications, crisis helplines, transparent report/block controls, and account deletion flows.
- **Dual Community Flavors 🏫**: One codebase powering both general-audience (`nexus`) and campus-restricted (`nexus_mec`) experiences under the cohesive **Constellation Social** design system.
- **Anti-Tapjacking & Hardware Protection 📱**: Android `FLAG_SECURE` integration prevents screen recording, unauthorized overlays, and screenshots during sensitive safety workflows.
- **Offline-First & Local Sync ⚡**: High-performance local caching with Drift (SQLite), reactive Flutter Riverpod 3 state management, and seamless background notification schedulers.

### 🔐 Security & Reliability

- **App Check Attestation**: Firebase App Check with Play Integrity (Android) and DeviceCheck (iOS) blocks unauthorized bot traffic and API tampering.
- **Zero-Trust Bridge**: Signal Protocol E2EE key exchange and double-ratchet encrypted messaging payloads.
- **AES-256-GCM Encryption**: OAuth tokens and sensitive credentials stored with hardware-backed encryption at rest.
- **Row Level Security (RLS)**: Database-level tenant isolation policy enforced across PostgreSQL tables in Supabase.
- **Rate Limiting & Protection**: Per-IP and per-user rate limiting via SlowAPI backed by Redis caching.
- **Supply Chain Transparency**: Signed Docker images using Sigstore Cosign (keyless OIDC), SLSA Level 3 provenance attestations, SBOM generation (CycloneDX), and continuous Trivy security scans.

## 🛠️ Tech Stack

### Backend & API Framework

- **FastAPI 0.136.3** - High-performance Python web framework with async support
- **Uvicorn 0.48.0** - Lightning-fast ASGI server implementation
- **Python 3.11+** - Modern Python with strict typing and bytecode determinism
- **Pydantic 2.13.4** - Data validation and settings management using Python type annotations
- **PyJWT 2.13.0** - Secure JSON Web Token handling
- **SlowAPI 0.1.9** - IP/user-based rate limiting middleware
- **APScheduler 3.11.3** - Background notification and reminder scheduler
- **Sentry SDK 2.5.1** - Real-time error tracking and telemetry with PII scrubbing

### Database & Auth

- **Supabase (PostgreSQL 15+)** - Database backend with Row Level Security (RLS) and pgvector
- **Supabase Auth** - JWT authentication system
- **Redis / Upstash 8.0.0** - Fast in-memory caching and rate-limiting storage

### Mobile Framework & State

- **Flutter SDK ^3.12.1** - Cross-platform mobile development for Android & iOS
- **Flutter Riverpod v3.3.1** - Reactive state management with code generation (`riverpod_annotation`)
- **GoRouter v17.1.0** - Declarative routing engine
- **Drift v2.34.0** - Reactive persistence library for SQLite in Flutter
- **Flutter Secure Storage v10.0.0** - Hardware-backed secret storage (Android Keystore / iOS Keychain)

### UI & Aesthetics

- **Constellation Social Design System** - Cosmic design language with curated color system
- **Google Fonts** - *Orbitron* (Display), *Manrope* (Headlines/Titles), *Inter* (Body), *JetBrains Mono* (Technical labels)
- **Lucide Icons Flutter v3.1.14** - Modern, cohesive icon system
- **Flutter Animate v4.5.2** - Micro-animations and subtle visual state transitions

### Security & Native Integrations

- **Firebase App Check v0.4.3** - Play Integrity & DeviceCheck device attestation
- **`libsignal_protocol_dart` 0.8.2** - Signal Protocol end-to-end encryption for chat
- **Cryptography & Encrypt** - Native cryptographic primitives and AES-256-GCM encryption
- **Google ML Kit Image Labeling** - On-device AI image detection and tagging
- **Geolocator & Google Maps** - Location Services & interactive map rendering
- **Just Audio & Record** - High-fidelity audio playback and voice recordings

### DevOps & Build Pipeline

- **Docker** - Deterministic reproducible container builds with `SOURCE_DATE_EPOCH`
- **Infisical CLI v0.43.84** - Two-tier secret management fetching secrets into memory at runtime
- **Sigstore Cosign** - Keyless OIDC container image signing
- **SLSA Level 3** - Supply chain security with provenance attestation
- **Trivy Scanner** - Container image vulnerability scanning
- **CodeQL & OpenSSF Scorecard** - Continuous security and code quality analysis
- **Pytest 8.4.1** - Automated unit and integration test suite

## 📁 Project Structure

```text
app/                   # FastAPI Backend Application
├── api/               # REST API endpoints (discovery, chats, safety, spotify, likes, sync)
├── core/              # Config, security, rate limiter, cache, Sentry scrubbing
├── db/                # Supabase client, chat key handlers, database queries
└── services/          # Business logic, notification dispatchers, reminder schedulers
mobile/                # Native Flutter Mobile Application
├── android/           # Native Android configuration (App Check, FLAG_SECURE)
├── assets/            # App icons, soundscapes, ML Kit TensorFlow models
├── ios/               # Native iOS configuration (DeviceCheck, Keychain)
├── lib/               # Dart application logic
│   ├── config/        # Environment configurations & constants
│   ├── features/      # Feature-specific modules (Profile, Spotify signals)
│   ├── navigation/    # GoRouter declarative routing setup
│   ├── providers/     # Riverpod reactive state providers
│   ├── screens/       # Application views (Orbit, Safety Center, Meetup Safety, Chats)
│   ├── services/      # Signal E2EE, local Drift DB, API client, SecureStorage
│   └── theme/         # Constellation Social design tokens and typography
└── test/              # Flutter unit and widget test suite
mocks/                 # Mock engine for reproducible containerized testing
Nexus_Engine/          # Submodule vector similarity matching & social engine
scripts/               # Maintenance, database migration, and release scripts
supabase/              # Database schema migrations, pgvector indexes, & RLS policies
tests/                 # Pytest suite for API endpoints, security, and moderation
```

## 🌌 Constellation Social Design System

Nexus features a cosmic design system called **Constellation Social** built around relationship modes and high-legibility safety surfaces.

### Core Color Palette

| Token | Hex | Usage |
| :--- | :--- | :--- |
| **Primary Teal** | `#0891B2` | Brand identity, primary interactive elements |
| **Pulsar Pink** | `#FF7597` | Hero call-to-actions, accent highlights |
| **Mode Dating** | `#FF4F81` | Dating mode navigation, chat indicators, filter tags |
| **Mode Friends** | `#A45E00` | Friends mode navigation, chat indicators, filter tags |
| **Mode Professional** | `#007E6D` | Professional mode navigation, chat indicators, filter tags |
| **Safety Blue** | `#0284C7` | Safety Center, check-in alerts, verified badges |
| **Safety Teal** | `#0D9488` | Meetup-safety guidance, crisis helpline surfaces |

### Typography Hierarchy

- **Display**: *Orbitron* (Weight 900) - Used for major brand headlines and cosmic accents.
- **Headline / Title**: *Manrope* (Weight 800 / 700) - Section headers and card titles.
- **Body**: *Inter* (Weight 400) - Readable body copy, chat messages, and guidance notes.
- **Mono**: *JetBrains Mono* (Weight 500) - System status codes, safety verification IDs, and timestamps.

## 🚀 Getting Started

### Prerequisites

- **Python** - 3.11 or higher
- **Flutter SDK** - 3.12.1+ (Dart 3.12+)
- **Docker** - For containerized deployments
- **Infisical CLI** - For secret management

### Quick Start (Backend API)

1. **Clone Repository**:

   ```bash
   git clone https://github.com/devakesu/Nexus.git
   cd Nexus
   ```

2. **Setup Environment**:

   ```bash
   python -m venv .venv
   source .venv/bin/activate
   pip install -r requirements.txt
   ```

3. **Inject Secrets & Run API**:

   ```bash
   infisical login
   infisical run --path /runtime --env prod -- uvicorn app.main:app --reload --port 8000
   ```

   Visit `http://localhost:8000/docs` for the interactive Swagger documentation.

### Quick Start (Mobile App)

1. **Navigate to Mobile Directory**:

   ```bash
   cd mobile
   flutter pub get
   ```

2. **Run General Audience Flavor (`nexus`)**:

   ```bash
   flutter run --flavor nexus -t lib/main.dart
   ```

3. **Run Campus-Gated Flavor (`nexus_mec`)**:

   ```bash
   flutter run --flavor nexus_mec -t lib/main.dart
   ```

## ⚡ Performance & Security Optimizations

- **Bytecode Determinism**: Container builds enforce `PYTHONDONTWRITEBYTECODE=1` and `SOURCE_DATE_EPOCH` for 100% reproducible artifacts.
- **In-Memory Secret Injection**: Secrets are injected directly into process memory at launch via Infisical, preventing credentials from touching the filesystem.
- **Local Persistence with Drift**: Offloads user profile reads and chat logs to an encrypted local SQLite database, resulting in sub-millisecond screen transitions.
- **Anti-Tapjacking Hardware Guard**: Prevents malicious Android apps from drawing overlays or capturing touch events over Safety Center and Check-in verification screens.

## 🧪 Testing & Quality

Nexus enforces strict testing and code analysis standards across both backend and mobile codebases.

### 🐍 Backend Testing (Pytest)

Run the backend unit, integration, and security test suite:

```bash
pytest tests/
```

Tests cover vector orbit calculations, moderation security, campus email validation, and chat key exchanges.

### 📱 Mobile Testing (Flutter)

Run mobile unit and widget tests:

```bash
cd mobile
flutter test
```

Enforces code style and best practices using `very_good_analysis`.

### 🛡️ Security Scans

- **CodeQL**: Automated SAST workflow detecting potential security flaws.
- **Trivy**: Vulnerability scanning on container base layers and dependencies.
- **OpenSSF Scorecard**: Continuous automated monitoring of repository security posture.

## 🔒 Security Policy

Security is fundamental to Nexus. If you discover a vulnerability, please disclose it responsibly by contacting **[admin@nexus.devakesu.com](mailto:admin@nexus.devakesu.com)**.

For complete details on encryption standards, hardware attestation, and script injection protection, read **[SECURITY.md](SECURITY.md)**.

## 🚀 Deployment

### 🐳 Docker Backend Deployment

Nexus features a reproducible Docker build setup with multi-stage security checks:

```bash
docker build -t nexus-api .
docker run -p 8000:8000 -e INFISICAL_PROJECT_ID="your_project_id" nexus-api
```

Release builds are automatically signed with Sigstore Cosign and submitted with SLSA Level 3 provenance attestations.

### 📱 Mobile App Releases

Build signed production release packages:

```bash
# Android APK / App Bundle
cd mobile
flutter build appbundle --flavor nexus -t lib/main.dart
flutter build appbundle --flavor nexus_mec -t lib/main.dart

# iOS IPA
flutter build ipa --flavor nexus -t lib/main.dart
```

Direct Google Play Link: [Nexus on Google Play](https://play.google.com/store/apps/details?id=com.devakesu.apps.nexus)

## ❓ Frequently Asked Questions

**What is the difference between `nexus` and `nexus_mec` flavors?**
Both flavors share 100% of the codebase and visual design language. The `nexus` flavor is open for general social discovery across any email domain, whereas the `nexus_mec` flavor gates registration strictly to `@mec.ac.in` student email addresses.

**How does End-to-End Encryption (E2EE) work in chats?**
Nexus uses the Signal Protocol (`libsignal_protocol_dart`). Public identity keys and pre-keys are registered on the backend via `/chat-keys`, while conversation session keys are negotiated directly on-device using a double ratchet algorithm. Messages are encrypted before leaving your phone and can only be decrypted by the intended recipient.

**How does Nexus protect user safety during real-world meetups?**
Nexus includes a dedicated Safety Center with active Meetup Check-in alerts. Users can set up safety timers when meeting someone in person; if the timer expires without check-in, an emergency alert can be dispatched to pre-selected trusted contacts.

## 🤝 Contributing

Contributions are welcome! Please review **[CONTRIBUTING.md](CONTRIBUTING.md)** for detailed instructions on code conventions, commit messages, and workflow rules.

## 👥 Maintained by

- **[Devanarayanan](https://github.com/devakesu/)**

## 📄 License

This project is licensed under the **[GNU Affero General Public License v3.0](LICENSE)**.

***Thank you for checking out Nexus! Stay safe, connect authentically, and explore your constellation! 🌌✨***
