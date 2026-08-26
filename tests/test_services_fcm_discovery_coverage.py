"""Test coverage suite for FCM Push Notification and Discovery Session orchestration services.

Covers:
- app/services/fcm_sender.py
- app/services/discovery.py
"""

from __future__ import annotations

from datetime import datetime, timedelta, timezone
from unittest.mock import AsyncMock, MagicMock, patch

import pytest
from fastapi import HTTPException

from app.core.security.crypto import encrypt_to_hex
from app.models import DiscoveryFilters
from app.services.discovery import (
    create_new_discovery_session,
    get_or_validate_session,
)
from app.services.fcm_sender import (
    _deactivate_fcm_token,
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

pytestmark = pytest.mark.anyio

USER_1 = "00000000-0000-0000-0000-000000000001"
USER_2 = "00000000-0000-0000-0000-000000000002"
SESSION_1 = "00000000-0000-0000-0000-000000000011"


# ==============================================================================
# 1. FCM SENDER INTERNAL HELPERS & MULTICAST DISPATCH
# ==============================================================================

def test_fcm_sender_internals_and_multicast():
    # _is_firebase_initialized
    with patch("app.services.fcm_sender._fb.get_app", return_value=MagicMock()):
        assert _is_firebase_initialized() is True

    with patch("app.services.fcm_sender._fb.get_app", side_effect=ValueError("No app")):
        assert _is_firebase_initialized() is False

    # _fetch_user_fcm_tokens
    mock_table = MagicMock()
    mock_table.select.return_value.eq.return_value.limit.return_value.execute.return_value = MagicMock(
        data=[{"is_deactivated": False}]
    )
    mock_table.select.return_value.eq.return_value.eq.return_value.execute.return_value = MagicMock(
        data=[{"fcm_token": "token_1"}, {"fcm_token": "token_2"}]
    )
    with patch("app.services.fcm_sender.supabase_client.table", return_value=mock_table):
        tokens = _fetch_user_fcm_tokens(USER_1)
        assert tokens == ["token_1", "token_2"]

    # _fetch_profile_name
    mock_table.select.return_value.eq.return_value.limit.return_value.execute.return_value = MagicMock(
        data=[{"name": encrypt_to_hex("Alice"), "is_deactivated": False}]
    )
    with patch("app.services.fcm_sender.supabase_client.table", return_value=mock_table):
        name = _fetch_profile_name(USER_1)
        assert name == "Alice"

    # _deactivate_fcm_token
    mock_table.update.return_value.eq.return_value.execute.return_value = MagicMock(data=[])
    with patch("app.services.fcm_sender.supabase_client.table", return_value=mock_table):
        _deactivate_fcm_token("fcm_token_stale_12345678")

    # _send_to_tokens success & error handling
    assert _send_to_tokens([], "title", "body", {}, "ch1") == 0

    mock_err = Exception("NotRegistered")
    setattr(mock_err, "code", "NOT_FOUND")
    mock_multicast_response = MagicMock(
        failure_count=1,
        success_count=1,
        responses=[
            MagicMock(success=True),
            MagicMock(success=False, exception=mock_err),
        ],
    )
    with patch("app.services.fcm_sender._fcm.send_each_for_multicast", return_value=mock_multicast_response), \
         patch("app.services.fcm_sender._deactivate_fcm_token") as mock_deact:
        cnt = _send_to_tokens(
            ["tok1", "tok2"],
            title="Hello",
            body="World",
            data={"k": "v"},
            channel_id="ch1",
            is_safety_critical=True,
        )
        assert cnt == 1
        mock_deact.assert_called_once_with("tok2")


# ==============================================================================
# 2. FCM NOTIFICATION DISPATCH METHODS
# ==============================================================================

async def test_fcm_notification_dispatch_methods():
    with patch("app.services.fcm_sender._is_firebase_initialized", return_value=True), \
         patch("app.services.fcm_sender.get_cached_active_block_ids", new_callable=AsyncMock, return_value=set()), \
         patch("app.services.fcm_sender._fetch_user_fcm_tokens", return_value=["tok1"]), \
         patch("app.services.fcm_sender._fetch_profile_name", return_value="Alice"), \
         patch("app.services.fcm_sender.redis_client.set", new_callable=AsyncMock, return_value=True), \
         patch("app.db.chat.fetch_conversation_participants", return_value={"id": "conv_1", "closed_at": None}), \
         patch("app.services.fcm_sender._send_to_tokens", return_value=1) as mock_send:

        # send_like_notification
        await send_like_notification(USER_1, USER_2, is_superlike=True)
        assert mock_send.call_count == 1

        await send_like_notification(USER_1, USER_2, is_superlike=False)
        assert mock_send.call_count == 2

        # send_match_notification
        await send_match_notification(USER_1, USER_2)
        assert mock_send.call_count == 4  # sends to user A and user B

        # send_chat_message_notification
        await send_chat_message_notification(
            sender_id=USER_1,
            recipient_id=USER_2,
            conversation_id="conv_1",
            tab="Dating",
            message_id="msg_1",
            ciphertext="cipher123",
            ciphertext_metadata={"iv": "iv123"},
        )
        assert mock_send.call_count == 5

        # send_chat_event_reminder_notification
        await send_chat_event_reminder_notification(
            user_a_id=USER_1,
            user_b_id=USER_2,
            conversation_id="conv_1",
            tab="Dating",
            location_label="Coffee Shop",
        )
        assert mock_send.call_count == 7  # sends to both participants

        # send_trusted_contact_removed_notification
        await send_trusted_contact_removed_notification(
            user_id=USER_1,
            contact_name="Dad",
        )
        assert mock_send.call_count == 8

        # send_meetup_safety_reminder_notification
        await send_meetup_safety_reminder_notification(
            user_id=USER_1,
            peer_id=USER_2,
            conversation_id="conv_1",
            tab="Dating",
        )
        assert mock_send.call_count == 9

        # send_prekey_replenishment_notification
        await send_prekey_replenishment_notification(USER_1)
        assert mock_send.call_count == 10


# ==============================================================================
# 3. DISCOVERY SESSION VALIDATION & CREATION
# ==============================================================================

def test_discovery_session_validation_and_creation():
    now = datetime.now(timezone.utc)

    # 1. get_or_validate_session - valid
    mock_session = {
        "id": SESSION_1,
        "viewer_id": USER_1,
        "tab": "Dating",
        "expires_at": (now + timedelta(hours=1)).isoformat(),
    }
    with patch("app.services.discovery.get_discovery_session", return_value=mock_session):
        s_id, exp = get_or_validate_session(SESSION_1, USER_1, "Dating")
        assert s_id == SESSION_1

    # Missing session -> 404
    with patch("app.services.discovery.get_discovery_session", return_value=None):
        with pytest.raises(HTTPException) as exc_info:
            get_or_validate_session(SESSION_1, USER_1, "Dating")
        assert exc_info.value.status_code == 404

    # Expired session -> 410
    mock_expired = {
        "id": SESSION_1,
        "viewer_id": USER_1,
        "tab": "Dating",
        "expires_at": (now - timedelta(hours=1)).isoformat(),
    }
    with patch("app.services.discovery.get_discovery_session", return_value=mock_expired):
        with pytest.raises(HTTPException) as exc_info:
            get_or_validate_session(SESSION_1, USER_1, "Dating")
        assert exc_info.value.status_code == 410

    # 2. create_new_discovery_session - valid flow
    mock_viewer = {
        "id": USER_1,
        "age": 22,
        "is_dating_active": True,
        "dating_target_buckets": ["all"],
    }
    mock_candidates = [
        {"id": USER_2, "age": 23, "is_dating_active": True},
    ]
    mock_ranked = [
        {"profile": {"id": USER_2}, "score": 0.88, "orbit_tier": 1},
    ]

    with patch("app.services.discovery.sync_redis_client.incr", return_value=1), \
         patch("app.services.discovery.sync_redis_client.get", return_value=None), \
         patch("app.services.discovery.fetch_stage_1_candidates", return_value=(mock_viewer, mock_candidates)), \
         patch("app.services.discovery.engine.discover_orbit", return_value=mock_ranked), \
         patch("app.services.discovery.fetch_expired_pass_candidates", return_value={USER_2: now - timedelta(days=5)}), \
         patch("app.services.discovery.create_discovery_session", return_value=(SESSION_1, now + timedelta(hours=1))):
        s_id, exp = create_new_discovery_session(
            user_id=USER_1,
            active_tab="Dating",
            filters=DiscoveryFilters(),
        )
        assert s_id == SESSION_1
        assert exp is not None

    # Underage viewer -> 403
    mock_underage_viewer = {
        "id": USER_1,
        "age": 17,
        "is_dating_active": True,
    }
    with patch("app.services.discovery.sync_redis_client.incr", return_value=1), \
         patch("app.services.discovery.fetch_stage_1_candidates", return_value=(mock_underage_viewer, [])):
        with pytest.raises(HTTPException) as exc_info:
            create_new_discovery_session(USER_1, "Dating", DiscoveryFilters())
        assert exc_info.value.status_code == 403
