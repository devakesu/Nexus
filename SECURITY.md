# Security Policy

## Reporting Security Vulnerabilities

If you discover a security vulnerability in Nexus, please report it responsibly:

- **GitHub Private Vulnerability Reporting**: Submit a report privately via [GitHub Security Advisories](https://github.com/devakesu/Nexus/security/advisories/new)
- **Email**: [admin@nexus.devakesu.com](mailto:admin@nexus.devakesu.com)

Please include:

- Description of the vulnerability
- Steps to reproduce
- Potential impact
- Any suggested fixes (optional)

We take security seriously and will respond to reports as quickly as possible.

## Security Features

Nexus implements multiple layers of security:

### Authentication & Authorization

- **Supabase Auth** - Industry-standard authentication with JWT tokens
- **Row Level Security (RLS)** - Database-level access control ensuring users only access their data
- **Session Management** - Secure session handling with automatic expiration
- **OTP Rate Limiting** - Multi-tiered protection:
  - *Client-side*: 60-second UI countdown timer in auth screens for user feedback, persisted across app restarts via secure storage to prevent simple UI bypass.
  - *Server-side*: Enforced via Supabase Auth `over_email_send_rate_limit` to block automated resend spam across app restarts or direct API requests.

### Data Protection

- **Secure Headers** - HSTS, X-Frame-Options, X-Content-Type-Options, Referrer-Policy
- **Input Validation** - Pydantic schemas validate all user input on the API backend
- **Origin Validation** - Strict CORS and origin checking in production
- **AES-256-GCM Encryption** - Secure Spotify token encryption at rest

### API & Mobile Security

- **Rate Limiting** - SlowAPI rate limiting per IP/user on sensitive endpoints
- **App Check Attestation (Mobile)** - Firebase App Check with Play Integrity (Android) and DeviceCheck (iOS) to prevent unauthorized API requests to backend endpoints.
- **Supabase Realtime Trust Boundary & Column Filtering** - Supabase Realtime WebSocket connections connect directly to Supabase and are gated at the PostgreSQL Row-Level Security (RLS) layer via authenticated user JWTs (`chat_messages_select_participant`, `chat_conversations_select_participant`, `chat_events_select_participant`). To prevent message type and communication pattern analysis by WebSocket listeners, PostgreSQL column-level publication filtering (`supabase_realtime`) strips `ciphertext_metadata` and `message_type` from Realtime replication payloads.
- **Server-Mediated Database Access & Field-Level Encryption (FLE)** - Direct client database mutation (`INSERT`, `UPDATE`, `DELETE`) is completely prohibited across all `public` tables via PostgreSQL Row Level Security (RLS). All CRUD operations are strictly mediated through the FastAPI backend (`service_role`) to enforce Field-Level Encryption (PII encryption with AES/Fernet keys), deterministic HMAC-SHA256 blind indexing, App Check attestation, and data invariants. Database triggers checking `auth.role() != 'service_role'` serve as an additional defense-in-depth barrier against direct PostgREST user connections, while backend mutation integrity is enforced via strict Pydantic input schemas and targeted column updates.
- **Anti-Tapjacking & Hardware Protection (Mobile)** - Native Android touch obscuration detection (`MotionEvent.FLAG_WINDOW_IS_OBSCURED`) and `FLAG_SECURE` window hardware protection (blocking screenshots and screen recording) enabled across all sensitive user flows: Login & Phone/Email OTP, OTP Re-authentication, Check-in & Alert screens, Safety Center & Meetup Safety screens, Account Deletion flow, Data Export flow, and Sign Out confirmation modal.
- **Debugger Detection & Fail-Closed Protection (Mobile)** - Early process-level debugger detection (`SecurityService.checkDebugger()`). If a debugger is detected, hardware secure storage keys are instantly wiped and temporary local evidence files are purged prior to terminating process execution via `exit(0)` without making network calls (failing closed).

### Supply Chain Security

- **Signed Docker Images** - All backend images signed with Sigstore cosign (keyless OIDC)
- **SLSA Level 3 Provenance** - Build provenance attestations
- **GitHub Attestations** - Native GitHub artifact attestations
- **SBOM (CycloneDX)** - Software Bill of Materials for all releases
- **Reproducible Builds** - Deterministic builds with SOURCE_DATE_EPOCH
- **Vulnerability Scanning** - Trivy scanning on every build

### CI/CD Security

- **Script Injection Prevention** - Environment variables used for all untrusted GitHub Actions inputs
- **Least Privilege Permissions** - Workflows use minimum required permissions with explicit grants
- **GPG Signing** - Commits and tags cryptographically signed
- **Secret Management** - GitHub secrets isolated per workflow with no cross-contamination

### Environment Security

- **Environment Variable Validation** - Runtime validation of required secrets
- **Two-Tier Secret Management** - Separate build-time and runtime secrets (managed via Infisical)
- **Production Safety Checks** - Strict validation in production mode

## GitHub Actions Security

### Script Injection Prevention

Nexus workflows are hardened against script injection attacks using environment variables for all untrusted inputs.

#### Vulnerable Pattern (❌ DO NOT USE)

```yaml
run: |
  VERSION_TAG="${{ github.event.inputs.version_tag }}"
  git checkout "refs/tags/${VERSION_TAG}"
```

**Risk**: Attacker-controlled inputs like branch names, tag names, or workflow inputs can contain shell metacharacters (`;`, `|`, `$()`, etc.) that execute arbitrary commands.

#### Secure Pattern (✅ ALWAYS USE)

```env
env:
  INPUT_VERSION_TAG: ${{ github.event.inputs.version_tag }}
run: |
  VERSION_TAG="$INPUT_VERSION_TAG"
  git checkout "refs/tags/${VERSION_TAG}"
```

**Protection**: Environment variables treat the entire input as literal data, preventing command injection.

#### Protected Workflows

##### release.yml

- Dynamic versions injected from Infisical are processed via intermediate environment mapping (`env.VERSION_TAG`, `env.VERSION`) during markdown verification and release generation loops.
- `github.repository` and `github.repository_owner` are passed via localized `env:` blocks to prevent repository name manipulation during container image publishing and artifact attestation steps.

#### References

- [GitHub Security Lab: Preventing pwn requests](https://securitylab.github.com/research/github-actions-preventing-pwn-requests/)
- [GitHub Actions Security Hardening](https://docs.github.com/en/actions/security-guides/security-hardening-for-github-actions#using-an-intermediate-environment-variable)
- [OpenSSF Scorecard: Token Permissions Check](https://github.com/ossf/scorecard/blob/main/docs/checks.md#token-permissions)

## Verifying Docker Image Signatures

All Docker images are signed using Sigstore cosign with keyless (OIDC) signing.

### Prerequisites

Install cosign:

```bash
# macOS
brew install cosign

# Linux
COSIGN_VERSION="3.0.6"
wget "https://github.com/sigstore/cosign/releases/download/v${COSIGN_VERSION}/cosign-linux-amd64"
chmod +x cosign-linux-amd64
sudo mv cosign-linux-amd64 /usr/local/bin/cosign

# Windows
scoop install cosign
```

### Quick Verification

Verify an image using regex pattern via tag or digest (recommended):

```bash
# Verify by image tag
cosign verify \
  --certificate-identity-regexp="^https://github.com/devakesu/Nexus/.github/workflows/" \
  --certificate-oidc-issuer="https://token.actions.githubusercontent.com" \
  ghcr.io/devakesu/nexus:latest

# Verify by exact SHA256 image digest (recommended)
cosign verify \
  --certificate-identity-regexp="^https://github.com/devakesu/Nexus/.github/workflows/" \
  --certificate-oidc-issuer="https://token.actions.githubusercontent.com" \
  ghcr.io/devakesu/nexus@sha256:IMAGE_SHA256_DIGEST
```

### Strict Verification

For maximum security, verify against specific workflow:

```bash
# Latest release (release.yml) by tag
cosign verify \
  --certificate-identity="https://github.com/devakesu/Nexus/.github/workflows/release.yml@refs/heads/main" \
  --certificate-oidc-issuer="https://token.actions.githubusercontent.com" \
  ghcr.io/devakesu/nexus:latest

# Specific version release by exact image digest
cosign verify \
  --certificate-identity="https://github.com/devakesu/Nexus/.github/workflows/release.yml@refs/heads/main" \
  --certificate-oidc-issuer="https://token.actions.githubusercontent.com" \
  ghcr.io/devakesu/nexus@sha256:IMAGE_SHA256_DIGEST
```

> **Note**: Container signatures are signed directly against the manifest digest. If `ghcr.io/devakesu/nexus:vX.Y.Z` returns `MANIFEST_UNKNOWN`, use the container digest (`ghcr.io/devakesu/nexus@sha256:<digest>`) listed in the release notes.

### GitHub Attestations

View build attestations:

```bash
# View provenance by image tag or digest
gh attestation verify oci://ghcr.io/devakesu/nexus:latest \
  --owner devakesu

gh attestation verify oci://ghcr.io/devakesu/nexus@sha256:IMAGE_SHA256_DIGEST \
  --owner devakesu

# View SBOM
gh attestation verify oci://ghcr.io/devakesu/nexus@sha256:IMAGE_SHA256_DIGEST \
  --owner devakesu \
  --signer-repo devakesu/Nexus
```

Or browse attestations on GitHub:

[https://github.com/devakesu/Nexus/attestations](https://github.com/devakesu/Nexus/attestations)

## Deployment Security Checklist

Before deploying to production:

### Required Configuration

- [ ] All required environment variables are set (Infisical secrets synced)
- [ ] Database RLS policies are enabled on all tables
- [ ] Docker image signature verified
- [ ] HTTPS is enforced
- [ ] Secure headers configured

### Security Controls

- [ ] Origin validation enabled for CORS
- [ ] Rate limiting configured on FastAPI
- [ ] Firebase App Check configured on Google Cloud / Firebase Console

### Monitoring & Logging

- [ ] Sentry error tracking configured
- [ ] Security event logging enabled
- [ ] Health check endpoint accessible
- [ ] Vulnerability scanning in CI/CD (Trivy + CodeQL)

### Network Security

- [ ] Container behind reverse proxy/firewall
- [ ] No direct external access to database container
- [ ] Internal network isolation
- [ ] TLS certificates valid

## Security Best Practices

### For Contributors

- Never commit secrets or API keys
- Use environment variables for sensitive data
- Follow secure coding practices
- Report security issues privately
- Keep dependencies updated

### For Deployers

- Use verified Docker images only
- Keep container runtime updated
- Monitor security advisories
- Implement proper network segmentation
- Enable all security features before production

## Security Monitoring

Nexus participates in:

- **OpenSSF Scorecard** - Automated security best practices checking
- **Dependabot** - Automated dependency vulnerability scanning
- **Trivy** - Container image vulnerability scanning
- **Sentry** - Real-time error tracking and monitoring

View our score: [![OpenSSF Scorecard](https://api.scorecard.dev/projects/github.com/devakesu/Nexus/badge)](https://scorecard.dev/viewer/?uri=github.com/devakesu/Nexus)

## Additional Resources

- **SLSA Framework**: [https://slsa.dev](https://slsa.dev)
- **Sigstore Project**: [https://sigstore.dev](https://sigstore.dev)
- **OpenSSF Scorecard**: [https://scorecard.dev](https://scorecard.dev)
- **GitHub Security**: [https://docs.github.com/en/code-security](https://docs.github.com/en/code-security)

---

For development setup and contribution guidelines, see [CONTRIBUTING.md](CONTRIBUTING.md).
