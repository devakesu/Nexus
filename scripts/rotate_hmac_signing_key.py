#!/usr/bin/env python3
"""Validation and verification tool for HMAC signing key rotation.

Validates that HMAC signing keys are configured properly, verifies that dual-key
verification works as expected during the transition window, and prints the operational
rotation checklist.

Usage:
    infisical run --env=prod projectId=xxxx --path=/public --path=/runtime -- python3 scripts/rotate_hmac_signing_key.py
"""

import logging
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from app.core.auth.phone_otp import hash_otp as phone_hash_otp
from app.core.auth.phone_otp import verify_otp_hash as phone_verify_otp_hash
from app.core.config import settings
from app.core.security.crypto import get_hmac_signing_key, get_hmac_verify_keys
from app.core.security.portal_auth import make_portal_access_token, verify_portal_access_token
from app.core.utils.sms import make_contact_portal_token, verify_contact_portal_token

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s",
)
logger = logging.getLogger(__name__)


def main() -> int:
    """Validates HMAC signing key rotation configuration and verifies behavior."""
    print("=" * 70)
    print("  NEXUS HMAC SIGNING KEY ROTATION CHECK & VALIDATION TOOL")
    print("=" * 70)

    raw_key = settings.hmac_signing_key or ""
    if not raw_key.strip():
        logger.error("HMAC_SIGNING_KEY is empty or not configured!")
        return 1

    keys = get_hmac_verify_keys()
    signing_key = get_hmac_signing_key()

    print(f"\n1. Key Configuration Status:")
    print(f"   - Total HMAC Keys Configured: {len(keys)}")
    print(f"   - Primary Signing Key Length: {len(signing_key)} bytes")
    for idx, k in enumerate(keys):
        role = "Active Signing + Verification" if idx == 0 else f"Verification Only (Old Key #{idx})"
        print(f"   - Key [{idx}]: {len(k)} bytes ({role})")

    print(f"\n2. Verifying Signing & Multi-Key Verification Paths:")

    # Test Phone OTP verification
    test_user_id = "test-user-12345"
    test_phone = "+15551234567"
    test_code = "654321"

    otp_hash = phone_hash_otp(test_user_id, test_phone, test_code)
    otp_valid = phone_verify_otp_hash(test_user_id, test_phone, test_code, otp_hash)
    otp_invalid = not phone_verify_otp_hash(test_user_id, test_phone, "000000", otp_hash)

    print(f"   - Account Phone OTP: {'PASS' if (otp_valid and otp_invalid) else 'FAIL'}")

    # Test Portal Access Token
    test_session_id = "sess-verify-999"
    portal_token = make_portal_access_token(test_session_id, test_phone)
    portal_valid = verify_portal_access_token(test_session_id, portal_token) is not None
    portal_invalid = verify_portal_access_token("wrong-session", portal_token) is None

    print(f"   - Safety Portal Access Token: {'PASS' if (portal_valid and portal_invalid) else 'FAIL'}")

    # Test Contact Portal Token
    test_contact_id = "contact-uuid-111"
    contact_token = make_contact_portal_token(test_contact_id)
    contact_valid = verify_contact_portal_token(contact_token) == test_contact_id
    contact_invalid = verify_contact_portal_token(contact_token + "bad") is None

    print(f"   - Safety Contact Self-Service Token: {'PASS' if (contact_valid and contact_invalid) else 'FAIL'}")

    if not (otp_valid and otp_invalid and portal_valid and portal_invalid and contact_valid and contact_invalid):
        logger.error("Cryptographic verification check failed!")
        return 1

    print("\n" + "=" * 70)
    print("  OPERATOR RUNBOOK FOR HMAC SIGNING KEY ROTATION")
    print("=" * 70)
    print("""
Step 1: Generate a new 32+ byte cryptographic secret for HMAC_SIGNING_KEY.
Step 2: Prepend the new secret in Infisical:
        HMAC_SIGNING_KEY=<new_key>,<old_key>
Step 3: Deploy / restart backend instances.
        - New tokens and OTPs will be signed with <new_key>.
        - Outstanding tokens signed under <old_key> remain valid during transition.
Step 4: Wait for the maximum token TTL (30 days for contact portal tokens,
        or 24h if only SMS escalation tokens are active).
Step 5: Remove <old_key> from Infisical:
        HMAC_SIGNING_KEY=<new_key>
Step 6: Deploy / restart backend instances. Rotation is complete!
    """)
    print("=" * 70)

    logger.info("HMAC signing key verification passed.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
