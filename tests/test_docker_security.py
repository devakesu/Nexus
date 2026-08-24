import fnmatch
from pathlib import Path

import yaml


def _load_dockerignore_patterns() -> list[str]:
    dockerignore_path = Path(".dockerignore")
    assert dockerignore_path.exists(), ".dockerignore file must exist"

    patterns: list[str] = []
    for raw_line in dockerignore_path.read_text(encoding="utf-8").splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#"):
            continue
        patterns.append(line)
    return patterns


def _pattern_matches_path(pattern: str, normalized_path: str, parts: list[str], filename: str) -> bool:
    is_negated = pattern.startswith("!")
    raw_pat = pattern[1:] if is_negated else pattern
    pat_has_slash = "/" in raw_pat.rstrip("/")
    clean_pat = raw_pat.strip("/")

    if pat_has_slash or raw_pat.endswith("/"):
        return (
            fnmatch.fnmatch(normalized_path, clean_pat)
            or fnmatch.fnmatch(normalized_path, f"{clean_pat}/*")
            or normalized_path.startswith(f"{clean_pat}/")
        )

    return (
        fnmatch.fnmatch(filename, clean_pat)
        or any(fnmatch.fnmatch(part, clean_pat) for part in parts)
        or fnmatch.fnmatch(normalized_path, clean_pat)
    )


def _matches_dockerignore(path_str: str, patterns: list[str]) -> bool:
    """Matches a file path against dockerignore patterns using Docker's standard rules.

    In Docker:
    - If pattern has no slash (e.g. *.pyc, .env, secrets.json): matches basename or any directory component.
    - If pattern has a slash (e.g. Nexus_Engine/, app/api/dev_temp.py): matches from root.
    """
    normalized_path = path_str.replace("\\", "/").strip("/")
    parts = normalized_path.split("/")
    filename = parts[-1]

    ignored = False
    for pattern in patterns:
        if _pattern_matches_path(pattern, normalized_path, parts, filename):
            ignored = not pattern.startswith("!")

    return ignored


def test_dockerignore_blocks_secrets_and_env_files():
    patterns = _load_dockerignore_patterns()

    critical_secret_files = [
        ".env",
        ".env.local",
        ".env.production",
        ".env.prod",
        ".env.test",
        ".env.dev",
        ".env.staging",
        "nested/path/.env",
        "nested/path/.env.local",
        "local.env",
        "production.env",
        "secrets.json",
        "nested/secrets.json",
        "server.pem",
        "private.key",
        "cert.key",
        "jwt_rsa.key",
        "ssl.pem",
        ".infisical.json",
        ".certificates/server.crt",
        ".certificates/ca.pem",
        "app/api/dev_temp.py",
        ".github/workflows/release.yml",
        ".github/workflows/deploy.yml",
        "tests/test_docker_security.py",
        "mobile/pubspec.yaml",
        "supabase/config.toml",
        "Nexus_Engine/secret_engine.py",
    ]

    for secret_path in critical_secret_files:
        assert _matches_dockerignore(secret_path, patterns), (
            f"Expected '{secret_path}' to be ignored by .dockerignore, but it was not."
        )


def test_dockerignore_allows_necessary_backend_files():
    patterns = _load_dockerignore_patterns()

    allowed_backend_files = [
        "app/main.py",
        "app/core/config.py",
        "app/api/auth.py",
        "app/templates/pages/landing.html",
        "entrypoint.sh",
        "requirements.txt",
        "mocks/Nexus_Engine/engine.py",
    ]

    for app_path in allowed_backend_files:
        assert not _matches_dockerignore(app_path, patterns), (
            f"Expected '{app_path}' to NOT be ignored by .dockerignore, but it was matched."
        )


def test_release_workflow_does_not_write_env_in_backend_build():
    release_path = Path(".github/workflows/release.yml")
    assert release_path.exists(), "release.yml workflow file must exist"

    content = release_path.read_text(encoding="utf-8")
    workflow = yaml.safe_load(content)

    backend_job = workflow.get("jobs", {}).get("build-and-release", {})
    assert backend_job, "build-and-release job must exist in release.yml"

    steps = backend_job.get("steps", [])
    for step in steps:
        step_name = step.get("name", "")
        step_env = step.get("env", {})
        step_run = step.get("run", "")

        # Check step names, env vars, and run scripts
        assert "to .env" not in step_name.lower(), (
            f"Found forbidden step creating .env: {step_name}"
        )
        assert step_env.get("OUTPUT_FILE") != ".env", (
            f"Step '{step_name}' sets OUTPUT_FILE: '.env'"
        )
        if step_run:
            assert ">> .env" not in step_run, (
                f"Step '{step_name}' writes to .env file: {step_run}"
            )
            assert "> .env" not in step_run, (
                f"Step '{step_name}' writes to .env file: {step_run}"
            )


def test_release_workflow_passes_safe_build_args():
    release_path = Path(".github/workflows/release.yml")
    content = release_path.read_text(encoding="utf-8")
    workflow = yaml.safe_load(content)

    backend_job = workflow.get("jobs", {}).get("build-and-release", {})
    steps = backend_job.get("steps", [])

    build_step = next((s for s in steps if s.get("id") == "build-push"), None)
    assert build_step is not None, "build-push step must exist in build-and-release"

    build_args = build_step.get("with", {}).get("build-args", "")
    assert "APP_VERSION=" in build_args
    assert "APP_COMMIT_SHA=" in build_args
    assert "APP_DOMAIN=" in build_args

    # 1. Ensure client-only keys from /public are NOT passed in backend Docker build args
    client_only_public_keys = [
        "FIREBASE_ANDROID_API_KEY",
        "FIREBASE_ANDROID_APP_ID_NEXUS",
        "FIREBASE_ANDROID_APP_ID_NEXUS_MEC",
        "FIREBASE_IOS_API_KEY",
        "FIREBASE_IOS_APP_ID_NEXUS",
        "FIREBASE_IOS_APP_ID_NEXUS_MEC",
        "FIREBASE_IOS_BUNDLE_ID_NEXUS",
        "FIREBASE_IOS_BUNDLE_ID_NEXUS_MEC",
        "FIREBASE_MESSAGING_SENDER_ID",
        "FIREBASE_PROJECT_ID",
        "FIREBASE_STORAGE_BUCKET",
        "GOOGLE_IOS_CLIENT_ID_NEXUS",
        "GOOGLE_IOS_CLIENT_ID_NEXUS_MEC",
        "GOOGLE_PLACES_API_KEY",
        "GOOGLE_WEB_CLIENT_ID",
        "SENTRY_FLUTTER_DSN",
        "SPOTIFY_REDIRECT_URI_NEXUS",
        "SPOTIFY_REDIRECT_URI_NEXUS_MEC",
        "SUPABASE_PUBLISHABLE_KEY",
    ]
    for key in client_only_public_keys:
        assert f"{key}=" not in build_args, f"Client-only key '{key}' found in Docker build-args."

    # 2. Ensure backend private runtime secrets (/runtime) are never baked via build-args
    private_runtime_secrets = [
        "BLIND_INDEX_KEY",
        "BREVO_API_KEY",
        "ENABLE_RATE_LIMITING",
        "ENABLE_REPLAY_PROTECTION",
        "ENFORCE_APP_CHECK",
        "FIREBASE_SERVICE_ACCOUNT",
        "HMAC_SIGNING_KEY",
        "PII_ENCRYPTION_KEY",
        "RATE_LIMIT_ACCOUNT_DELETION",
        "RATE_LIMIT_ACCOUNT_DELETION_OTP",
        "RATE_LIMIT_ACCOUNT_PHONE_OTP",
        "RATE_LIMIT_AUTH",
        "RATE_LIMIT_DATA_EXPORT",
        "RATE_LIMIT_DATA_EXPORT_OTP",
        "RATE_LIMIT_DISCOVER",
        "RATE_LIMIT_FEEDBACK",
        "RATE_LIMIT_HEALTH",
        "RATE_LIMIT_LOGIN_BY_PHONE",
        "RATE_LIMIT_SAFETY",
        "RATE_LIMIT_SAFETY_PORTAL",
        "RATE_LIMIT_SPOTIFY",
        "RATE_LIMIT_SPOTIFY_RESYNC",
        "REDIS_URL",
        "SENTRY_BACKEND_DSN",
        "SPOTIFY_CLIENT_SECRET",
        "SUPABASE_JWT_SECRET",
        "SUPABASE_SERVICE_ROLE_KEY",
        "TWILIO_ACCOUNT_SID",
        "TWILIO_AUTH_TOKEN",
        "TWILIO_FROM_NUMBER",
    ]
    for key in private_runtime_secrets:
        assert f"{key}=" not in build_args, f"Private runtime secret '{key}' found in Docker build-args."

    # 3. Ensure CI and deployment secrets (/ci) are never baked via build-args
    ci_and_release_secrets = [
        "ANDROID_KEYSTORE_BASE64",
        "ANDROID_KEYSTORE_PASSWORD",
        "ANDROID_KEY_ALIAS",
        "ANDROID_KEY_PASSWORD",
        "AWS_ACCESS_KEY_ID",
        "AWS_S3_PRIVATE_BUCKET",
        "AWS_SECRET_ACCESS_KEY",
        "CODECOV_TOKEN",
        "COOLIFY_API_TOKEN",
        "COOLIFY_APP_ID",
        "COOLIFY_BASE_URL",
        "GOOGLE_SERVICES_JSON_BASE64",
        "INFISICAL_CLIENT_ID",
        "INFISICAL_CLIENT_SECRET",
        "INFISICAL_PROJECT_ID",
        "SENTRY_AUTH_TOKEN",
        "SUPABASE_ACCESS_TOKEN",
        "SUPABASE_DB_PASSWORD",
        "SUPABASE_PROJECT_ID",
    ]
    for key in ci_and_release_secrets:
        assert f"{key}=" not in build_args, f"CI/Release secret '{key}' found in Docker build-args."

    # 4. Verify public configuration and engine commit SHA are passed in build-args
    assert "ENGINE_COMMIT_SHA=" in build_args


def test_entrypoint_supports_commit_sha_and_cache():
    entrypoint_path = Path("entrypoint.sh")
    assert entrypoint_path.exists(), "entrypoint.sh must exist"

    content = entrypoint_path.read_text(encoding="utf-8")
    assert "ENGINE_COMMIT_SHA" in content, "entrypoint.sh must reference ENGINE_COMMIT_SHA"
    assert "cache/nexus_engine" in content, "entrypoint.sh must implement caching directory"
    assert "Cache hit for Nexus_Engine" in content, "entrypoint.sh must implement cache hit path"
    assert "tarball/${TARGET_SHA}" in content, "entrypoint.sh must fetch target SHA rather than hardcoded main"
    assert 'TARGET_SHA="main"' not in content, "entrypoint.sh must not fallback to main"
    assert 'floating \'main\' is required' not in content or 'error' in content.lower()


def test_entrypoint_strictly_enforces_pinned_commit_sha():
    entrypoint_path = Path("entrypoint.sh")
    content = entrypoint_path.read_text(encoding="utf-8")
    # Verify strict check: if [ -z "$TARGET_SHA" ] || [ "$TARGET_SHA" = "main" ]
    assert '[ -z "$TARGET_SHA" ] || [ "$TARGET_SHA" = "main" ]' in content


def test_entrypoint_and_dockerfile_do_not_echo_secrets():
    entrypoint_path = Path("entrypoint.sh")
    content = entrypoint_path.read_text(encoding="utf-8")

    # 1. Verify set -x (bash debug execution echo) is strictly absent
    assert "set -x" not in content, "entrypoint.sh must not enable bash debug tracing (set -x)"

    # 2. Verify secrets and tokens are never echoed to stdout or stderr
    assert "echo $ENGINE_PAT" not in content
    assert 'echo "$ENGINE_PAT"' not in content
    assert "echo $INFISICAL" not in content
    assert "printenv" not in content

    # 3. Verify Infisical CLI calls redirect stderr to /dev/null
    assert "infisical secrets get ENGINE_PAT" in content
    assert "2>/dev/null" in content

    # 4. Verify Dockerfile CMD executes infisical run directly without intermediate echo
    dockerfile_content = Path("Dockerfile").read_text(encoding="utf-8")
    assert 'exec infisical run' in dockerfile_content
    assert 'echo' not in dockerfile_content.split('CMD')[1]



def test_fetch_build_time_vars_validates_public_variables():
    script_path = Path("scripts/fetch-build-time-vars.js")
    assert script_path.exists(), "fetch-build-time-vars.js must exist"

    content = script_path.read_text(encoding="utf-8")
    assert "validatePublicVariables" in content
    assert "APP_DOMAIN" in content
    assert "SUPABASE_URL" in content
    assert "ALLOWED_SIGNUP_DOMAINS" in content


def test_pubspec_lock_is_tracked_and_enforced():
    # 1. Ensure pubspec.lock exists in mobile/
    lock_file = Path("mobile/pubspec.lock")
    assert lock_file.exists(), "mobile/pubspec.lock must exist and be committed to source control"
    assert lock_file.stat().st_size > 0, "mobile/pubspec.lock must not be empty"

    # 2. Ensure pubspec.lock is NOT ignored in .gitignore
    gitignore = Path(".gitignore").read_text(encoding="utf-8")
    for line in gitignore.splitlines():
        clean = line.strip()
        if not clean or clean.startswith("#"):
            continue
        assert "pubspec.lock" not in clean, f".gitignore must not ignore pubspec.lock: found '{clean}'"

    # 3. Ensure CI workflows use --enforce-lockfile
    for wf in ["tests.yml", "release.yml", "codeql.yml"]:
        wf_path = Path(f".github/workflows/{wf}")
        assert wf_path.exists(), f"{wf} must exist"
        wf_content = wf_path.read_text(encoding="utf-8")
        if "flutter pub get" in wf_content:
            assert "flutter pub get --enforce-lockfile" in wf_content, (
                f"Workflow {wf} must use 'flutter pub get --enforce-lockfile'"
            )


def test_android_debug_signing_uses_default_keystore():
    gradle_path = Path("mobile/android/app/build.gradle.kts")
    assert gradle_path.exists(), "build.gradle.kts must exist"

    content = gradle_path.read_text(encoding="utf-8")
    assert 'getByName("debug")' not in content, (
        "debug signingConfig must not be customized with production keystoreProperties"
    )
    assert 'create("release")' in content, "release signingConfig must be defined"


def test_android_manifest_disables_backup():
    manifest_path = Path("mobile/android/app/src/main/AndroidManifest.xml")
    assert manifest_path.exists(), "AndroidManifest.xml must exist"

    content = manifest_path.read_text(encoding="utf-8")
    assert 'android:allowBackup="false"' in content, (
        "AndroidManifest.xml must explicitly set android:allowBackup='false'"
    )
    assert 'android:fullBackupContent="false"' in content, (
        "AndroidManifest.xml must explicitly set android:fullBackupContent='false'"
    )


def test_encrypted_string_uses_cryptography_and_encrypt_package_removed():
    pubspec_path = Path("mobile/pubspec.yaml")
    assert pubspec_path.exists(), "pubspec.yaml must exist"

    pubspec_content = pubspec_path.read_text(encoding="utf-8")
    assert "encrypt:" not in pubspec_content, "package:encrypt must be removed from pubspec.yaml"
    assert "cryptography:" in pubspec_content, "package:cryptography must be present in pubspec.yaml"

    enc_string_path = Path("mobile/lib/core/utils/encrypted_string.dart")
    assert enc_string_path.exists(), "encrypted_string.dart must exist"

    enc_string_content = enc_string_path.read_text(encoding="utf-8")
    assert "package:cryptography" in enc_string_content, (
        "EncryptedString must use package:cryptography"
    )
    assert "package:encrypt" not in enc_string_content, (
        "EncryptedString must not use package:encrypt"
    )


def test_centralized_secure_storage_options():
    storage_options_path = Path("mobile/lib/core/utils/secure_storage_options.dart")
    assert storage_options_path.exists(), "secure_storage_options.dart must exist"

    options_content = storage_options_path.read_text(encoding="utf-8")
    assert "class AppSecureStorage" in options_content
    assert "AndroidOptions.defaultOptions" in options_content
    assert "KeychainAccessibility.first_unlock_this_device" in options_content

    # Ensure no other dart file in mobile/lib instantiates FlutterSecureStorage directly
    mobile_lib = Path("mobile/lib")
    direct_instances: list[str] = []
    for dart_file in mobile_lib.rglob("*.dart"):
        if dart_file == storage_options_path:
            continue
        content = dart_file.read_text(encoding="utf-8")
        if "FlutterSecureStorage(" in content:
            direct_instances.append(str(dart_file))

    assert not direct_instances, (
        f"Found direct FlutterSecureStorage instantiations in {direct_instances}. "
        "Use AppSecureStorage.instance instead."
    )








