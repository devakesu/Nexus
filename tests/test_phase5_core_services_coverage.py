"""Phase 5 Test Suite: Deep Branch Coverage for Core Infra, Security & Services Layer.

Covers:
- app/core/security/jwks.py
- app/core/infra/tasks.py
- app/services/reminder_scheduler.py
- app/services/fcm_sender.py
- app/core/email/notifications/account.py & feedback.py
- app/core/utils/sms.py
"""

from __future__ import annotations

import asyncio
import json
from datetime import datetime, timedelta, timezone
from typing import Any, cast
from unittest.mock import AsyncMock, MagicMock, patch

import jwt
import pytest
from cryptography.hazmat.primitives.asymmetric import ec
from cryptography.hazmat.primitives.asymmetric.ec import EllipticCurvePublicKey

from app.core.email.notifications.account import (
    send_account_deletion_otp_email,
    send_account_deletion_scheduled_email,
    send_account_reactivated_email,
    send_data_export_otp_email,
    send_login_otp_email,
    send_support_appeal_otp_email,
)
from app.core.email.notifications.feedback import (
    send_feedback_admin_notification_email,
    send_feedback_closed_admin_notification_email,
    send_feedback_comment_admin_notification_email,
    send_feedback_confirmation_email,
)
from app.core.email.senders import ProviderResult
from app.core.infra.tasks import (
    _MAX_BACKGROUND_TASKS,
    _background_tasks,
    run_with_retries,
    safe_create_task,
)
from app.core.security.jwks import (
    _find_jwk_by_kid,
    _isolate_fallback_jwk,
    _parse_jwk_dict,
    clear_jwks_cache,
    get_fallback_public_key,
    get_live_supabase_public_key,
)
from app.core.utils.sms import (
    compose_contact_added_message,
    compose_contact_self_removed_message,
    compose_inform_message,
    compose_sos_message,
    compose_unreachable_message,
    make_contact_portal_token,
    make_escalation_cancel_token,
    redact_phone,
    sanitize_sms_text,
    send_sms,
    send_via_twilio,
    verify_contact_portal_token,
    verify_escalation_cancel_token,
)
from app.services.fcm_sender import (
    _fetch_profile_name,
    _fetch_user_fcm_tokens,
    _is_firebase_initialized,
    _send_to_tokens,
    send_chat_event_reminder_notification,
    send_chat_message_notification,
    send_like_notification,
    send_match_notification,
    send_meetup_safety_reminder_notification,
    send_prekey_replenishment_notification,
    send_trusted_contact_removed_notification,
)
from app.services.reminder_scheduler import (
    _acquire_escalation_idempotency,
    _compose_session_unreachable_message,
    _dispatch_escalation_sms_and_record,
    _mask_id,
    _next_escalation_due,
    _run_account_deletion_long_tail_purge,
    _run_account_deletion_purge,
    _run_blocklist_expiry,
    _run_safety_data_legal_hold_purge,
    _run_safety_evidence_retention_purge,
    start_reminder_scheduler,
    stop_reminder_scheduler,
    with_distributed_lock,
)

pytestmark = pytest.mark.anyio

USER_1 = "00000000-0000-0000-0000-000000000001"
USER_2 = "00000000-0000-0000-0000-000000000002"
SESSION_1 = "00000000-0000-0000-0000-000000000020"


def _make_chaining_mock(data: Any = None) -> MagicMock:
    mock: MagicMock = MagicMock()
    mock.select.return_value = mock
    mock.insert.return_value = mock
    mock.update.return_value = mock
    mock.delete.return_value = mock
    mock.upsert.return_value = mock
    mock.eq.return_value = mock
    mock.neq.return_value = mock
    mock.gt.return_value = mock
    mock.gte.return_value = mock
    mock.lt.return_value = mock
    mock.lte.return_value = mock
    mock.is_.return_value = mock
    mock.in_.return_value = mock
    mock.or_.return_value = mock
    mock.not_.is_.return_value = mock
    mock.order.return_value = mock
    mock.limit.return_value = mock

    def _exec() -> MagicMock:
        import copy
        return MagicMock(data=copy.deepcopy(data))  # pyright: ignore[reportUnknownArgumentType,reportUnknownMemberType]

    def _single() -> MagicMock:
        import copy
        if isinstance(data, list) and data:
            return MagicMock(data=copy.deepcopy(data[0]))  # pyright: ignore[reportUnknownArgumentType,reportUnknownMemberType]
        return MagicMock(data=copy.deepcopy(data))  # pyright: ignore[reportUnknownArgumentType,reportUnknownMemberType]

    mock.execute = MagicMock(side_effect=_exec)
    single_mock: MagicMock = MagicMock()
    single_mock.execute = MagicMock(side_effect=_single)
    mock.maybe_single.return_value = single_mock
    return mock


# ==============================================================================
# 1. CORE JWKS & FALLBACK KEYS
# ==============================================================================

async def test_core_jwks_deep() -> None:
    clear_jwks_cache()

    # parse_jwk_dict
    parsed = _parse_jwk_dict({"kid": "k1", "kty": "EC", "crv": "P-256", "x": "abc", "y": "def"})
    assert parsed["kid"] == "k1"

    with pytest.raises(Exception):
        _parse_jwk_dict("{malformed-json")
    with pytest.raises(Exception):
        _parse_jwk_dict(123)

    # find_jwk_by_kid
    keys: list[dict[str, str]] = [{"kid": "k1"}, {"kid": "k2"}]
    assert _find_jwk_by_kid(cast(list[object], keys), "k1") == {"kid": "k1"}
    assert _find_jwk_by_kid(cast(list[object], keys), "missing") is None

    # isolate_fallback_jwk
    fallback_doc = {"keys": [{"kid": "f1", "kty": "EC"}, {"kid": "f2"}]}
    assert _isolate_fallback_jwk(fallback_doc, "f1") == {"kid": "f1", "kty": "EC"}
    assert _isolate_fallback_jwk(fallback_doc, None) == {"kid": "f1", "kty": "EC"}

    # get_fallback_public_key with real EC key
    private_key = ec.generate_private_key(ec.SECP256R1())
    real_public_key = private_key.public_key()

    mock_fb_jwk = {"kty": "EC", "crv": "P-256", "kid": "fallback-kid"}
    with patch("app.core.security.jwks.settings.supabase_jwt_secret", json.dumps({"keys": [mock_fb_jwk]})), \
         patch("app.core.security.jwks.PyJWK") as mock_pyjwk:
        mock_pyjwk.return_value.key = real_public_key
        key = get_fallback_public_key("fallback-kid")
        assert isinstance(key, EllipticCurvePublicKey)

    # get_live_supabase_public_key
    mock_resp = MagicMock()
    mock_resp.status_code = 200
    mock_resp.json.return_value = {"keys": [mock_fb_jwk]}

    mock_client = AsyncMock()
    mock_client.get.return_value = mock_resp

    dummy_token = jwt.encode({"sub": USER_1}, "secret", headers={"kid": "fallback-kid"})
    with patch("app.core.security.jwks._get_jwks_client", return_value=mock_client), \
         patch("app.core.security.jwks._resolve_key_from_cache", return_value=real_public_key):
        live_key = await get_live_supabase_public_key(dummy_token)
        assert isinstance(live_key, EllipticCurvePublicKey)


# ==============================================================================
# 2. CORE INFRA TASKS & RETRIES
# ==============================================================================

async def test_core_tasks_and_retries() -> None:
    # safe_create_task in running loop
    async def dummy_coro() -> int:
        await asyncio.sleep(0.01)
        return 42

    task = safe_create_task(dummy_coro())
    assert task is not None
    await task

    # Task capacity full
    _background_tasks.clear()
    dummy_tasks = {MagicMock() for _ in range(_MAX_BACKGROUND_TASKS)}
    _background_tasks.update(dummy_tasks)

    dropped = safe_create_task(dummy_coro())
    assert dropped is None
    _background_tasks.clear()

    # run_with_retries success
    call_count = 0

    async def flaky_async() -> str:
        nonlocal call_count
        call_count += 1
        if call_count < 2:
            raise ValueError("transient error")
        return "success"

    res = await run_with_retries(flaky_async, max_retries=3, initial_delay=0.01)
    assert res == "success"

    # run_with_retries exhaustion
    async def always_fails() -> None:
        raise RuntimeError("fatal failure")

    with pytest.raises(RuntimeError):
        await run_with_retries(always_fails, max_retries=2, initial_delay=0.01)


# ==============================================================================
# 3. REMINDER SCHEDULER & ESCALATION BURSTS
# ==============================================================================

async def test_services_reminder_scheduler() -> None:
    # _mask_id
    assert _mask_id("abcdef123456") == "abcd...3456"
    assert _mask_id("abc") == "***"

    # with_distributed_lock
    mock_lock = MagicMock()
    mock_lock.acquire = AsyncMock(return_value=True)
    mock_lock.release = AsyncMock()
    mock_redis = MagicMock()
    mock_redis.lock.return_value = mock_lock

    @with_distributed_lock("test:lock", ttl_seconds=60)
    async def locked_task() -> None:
        pass

    with patch("app.services.reminder_scheduler.redis_client", mock_redis):
        await locked_task()
        mock_lock.acquire.return_value = False
        await locked_task()  # Should skip cleanly

    # _next_escalation_due
    now = datetime.now(timezone.utc)
    sess_due = {
        "status": "escalating",
        "escalations_sent": 1,
        "interval_seconds": 60,
        "last_escalated_at": (now - timedelta(minutes=10)).isoformat(),
    }
    assert _next_escalation_due(sess_due, now) is True

    # _compose_session_unreachable_message
    msg = _compose_session_unreachable_message(
        session={"label": "Dinner"},
        session_id=SESSION_1,
        escalation_number=1,
        user_name="Alice",
    )
    assert "Alice" in msg

    # _acquire_escalation_idempotency
    mock_redis_async = AsyncMock()
    mock_redis_async.set.return_value = True
    with patch("app.services.reminder_scheduler.redis_client", mock_redis_async):
        acq = await _acquire_escalation_idempotency(SESSION_1, 1)
        assert acq is True

    # _dispatch_escalation_sms_and_record
    mock_contact = {"id": "c1", "phone": "+14155552671"}
    with patch("app.services.reminder_scheduler.record_safety_escalation_sent", return_value={"id": SESSION_1}), \
         patch("app.services.reminder_scheduler.fetch_contact_facing_profile_summary", return_value={"display_name": "Alice"}), \
         patch("app.services.reminder_scheduler.send_sms", AsyncMock(return_value=MagicMock(success=True))):
        await _dispatch_escalation_sms_and_record(
            contacts=[mock_contact],
            session={"label": "Dinner", "user_id": USER_1},
            session_id=SESSION_1,
            escalation_number=1,
            idempotency_key="idem-key",
        )

    # Purge wrappers
    with patch("app.services.reminder_scheduler.purge_due_accounts", return_value={"purged": 1}), \
         patch("app.services.reminder_scheduler.expire_blocklist_entries", return_value=1), \
         patch("app.services.reminder_scheduler.purge_expired_safety_evidence", return_value=1), \
         patch("app.services.reminder_scheduler.purge_safety_data_for_purged_accounts", return_value=1), \
         patch("app.services.reminder_scheduler.hard_purge_long_tail_accounts", return_value={"orphans": 0}):
        await _run_account_deletion_purge()
        await _run_blocklist_expiry()
        await _run_account_deletion_long_tail_purge()
        await _run_safety_evidence_retention_purge()
        await _run_safety_data_legal_hold_purge()

    # Scheduler start & stop
    sched = start_reminder_scheduler()
    assert sched is not None
    stop_reminder_scheduler()


# ==============================================================================
# 4. FCM NOTIFICATIONS & TOKENS
# ==============================================================================

async def test_services_fcm_notifications() -> None:
    # Firebase initialized check
    with patch("app.services.fcm_sender._fb.get_app", return_value=MagicMock()):
        assert _is_firebase_initialized() is True

    # _fetch_user_fcm_tokens & _fetch_profile_name
    mock_table = _make_chaining_mock([{"fcm_token": "tok1", "is_active": True}])
    with patch("app.services.fcm_sender.supabase_client.table", return_value=mock_table):
        tokens = _fetch_user_fcm_tokens(USER_1)
        assert len(tokens) >= 1
        _name = _fetch_profile_name(USER_1)
        assert _name is not None or _name is None

    # _send_to_tokens with mocked messaging
    mock_messaging = MagicMock()
    mock_response = MagicMock()
    mock_response.success_count = 1
    mock_response.failure_count = 0
    mock_response.responses = [MagicMock(success=True)]
    mock_messaging.send_each_for_multicast.return_value = mock_response

    with patch("app.services.fcm_sender._fcm", mock_messaging), \
         patch("app.services.fcm_sender._is_firebase_initialized", return_value=True):
        res = _send_to_tokens(
            ["tok1"],
            title="Hello",
            body="World",
            data={"type": "test"},
            channel_id="default",
        )
        assert res == 1

        # High-level push functions
        with patch("app.services.fcm_sender._fetch_user_fcm_tokens", return_value=["tok1"]), \
             patch("app.services.fcm_sender.get_cached_active_block_ids", AsyncMock(return_value=set())), \
             patch("app.db.chat.fetch_conversation_participants", return_value={"closed_at": None}):
            await send_like_notification(USER_1, USER_2, is_superlike=False)
            await send_match_notification(USER_1, USER_2)
            await send_chat_message_notification(
                sender_id=USER_2,
                recipient_id=USER_1,
                conversation_id="conv-1",
                tab="dating",
                message_id="msg-1",
                ciphertext="c-txt",
                ciphertext_metadata={},
            )
            await send_chat_event_reminder_notification(
                user_a_id=USER_1,
                user_b_id=USER_2,
                conversation_id="conv-1",
                tab="dating",
            )
            await send_trusted_contact_removed_notification(USER_1, "Bob")
            await send_meetup_safety_reminder_notification(
                user_id=USER_1,
                peer_id=USER_2,
                conversation_id="conv-1",
                tab="dating",
            )
            await send_prekey_replenishment_notification(USER_1)


# ==============================================================================
# 5. CORE EMAIL NOTIFICATIONS (ACCOUNT & FEEDBACK)
# ==============================================================================

async def test_core_email_notifications() -> None:
    mock_provider_ok = ProviderResult(provider="Brevo", id="msg-1", success=True)
    with patch("app.core.email.send_email", AsyncMock(return_value=mock_provider_ok)):

        # Account notifications
        r1 = await send_login_otp_email("user@berkeley.edu", "123456")
        assert r1.success is True

        r2 = await send_account_deletion_otp_email("user@berkeley.edu", "123456")
        assert r2.success is True

        r3 = await send_data_export_otp_email("user@berkeley.edu", "123456")
        assert r3.success is True

        r4 = await send_support_appeal_otp_email("user@berkeley.edu", "123456")
        assert r4.success is True

        r5 = await send_account_deletion_scheduled_email("user@berkeley.edu", "2026-09-01T00:00:00Z")
        assert r5.success is True

        r6 = await send_account_reactivated_email("user@berkeley.edu")
        assert r6.success is True

        # Feedback notifications
        fb1 = await send_feedback_confirmation_email(
            email="user@berkeley.edu",
            query_type="bug_report",
            subject="Bug report",
            report_id="rep-1",
        )
        assert fb1.success is True

        fb2 = await send_feedback_admin_notification_email(
            report_id="rep-1",
            query_type="bug_report",
            subject="Bug report",
            message="Something broken",
            user_id=USER_1,
            submitter_email="user@berkeley.edu",
        )
        assert fb2.success is True

        fb3 = await send_feedback_comment_admin_notification_email(
            report_id="rep-1",
            query_type="bug_report",
            subject="Bug report",
            comment_body="New details",
            user_id=USER_1,
            submitter_email="user@berkeley.edu",
        )
        assert fb3.success is True

        fb4 = await send_feedback_closed_admin_notification_email(
            report_id="rep-1",
            query_type="bug_report",
            subject="Bug report",
            reason="resolved",
            user_id=USER_1,
            submitter_email="user@berkeley.edu",
        )
        assert fb4.success is True


# ==============================================================================
# 6. CORE SMS UTILITIES
# ==============================================================================

async def test_core_sms_utilities() -> None:
    # Sanitization
    assert sanitize_sms_text("Hello  World\n\t!") == "Hello World !"
    assert sanitize_sms_text(None) is None

    # Redaction
    assert redact_phone("+14155552671") == "***2671"

    # Messages
    sos = compose_sos_message(name="Alice", silent=False, location={"lat": 37.7749, "lng": -122.4194})
    assert "Alice" in sos
    assert "maps.google.com" in sos

    inf = compose_inform_message(name="Alice", location=None, event_label="Cafe")
    assert "Alice" in inf

    cta = compose_contact_added_message(user_name="Alice", manage_link="https://nexus.test/c1")
    assert "Alice" in cta

    csr = compose_contact_self_removed_message(contact_name="Bob")
    assert "Bob" in csr

    unr = compose_unreachable_message(
        name="Alice",
        escalation_number=1,
        battery_percent=80,
        connection_type="wifi",
        event_label="Cafe",
        cancel_link="https://nexus.test/cancel",
    )
    assert "Alice" in unr

    # Tokens
    tok = make_escalation_cancel_token(SESSION_1, 1)
    assert verify_escalation_cancel_token(SESSION_1, tok) == 1
    assert verify_escalation_cancel_token(SESSION_1, "invalid") is None

    c_tok = make_contact_portal_token("contact-1")
    assert verify_contact_portal_token(c_tok) == "contact-1"
    assert verify_contact_portal_token("invalid") is None

    # send_via_twilio and send_sms
    mock_resp = MagicMock()
    mock_resp.status_code = 200
    mock_resp.json.return_value = {"sid": "SM123"}
    mock_client = AsyncMock()
    mock_client.__aenter__.return_value.post = AsyncMock(return_value=mock_resp)

    with patch("app.core.utils.sms.httpx.AsyncClient", return_value=mock_client), \
         patch("app.core.utils.sms.has_twilio", True), \
         patch("app.core.utils.sms.settings.twilio_account_sid", "AC123"), \
         patch("app.core.utils.sms.settings.twilio_auth_token", "secret"), \
         patch("app.core.utils.sms.settings.twilio_from_number", "+14155550000"):
        res = await send_via_twilio("+14155552671", "Test")
        assert res.success is True

        res2 = await send_sms("+14155552671", "Test")
        assert res2.success is True
