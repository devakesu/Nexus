"""Phase 10 High Impact API & DB Coverage Suite to push total coverage beyond 90%.

Targeting remaining high-miss files:
1. app/api/feedback/contact.py (73 lines missing)
2. app/api/feedback/tickets.py (33 lines missing)
3. app/api/safety/endpoints.py (41 lines missing)
4. app/api/chat/keys.py & app/api/chat/presence.py
5. app/db/discovery/exclusions.py & app/db/discovery/matches.py
6. app/db/safety/alerts.py & app/db/safety/contacts.py
7. app/db/users/account_deletion.py & app/db/users/export.py
"""

from __future__ import annotations

import io
from datetime import datetime, timezone
from typing import Any
from unittest.mock import AsyncMock, MagicMock, patch

import pytest
from fastapi import HTTPException, UploadFile
from PIL import Image

pytestmark = pytest.mark.anyio

USER_1 = "00000000-0000-0000-0000-000000000001"
USER_2 = "00000000-0000-0000-0000-000000000002"
ALERT_1 = "00000000-0000-0000-0000-000000000030"
REPORT_1 = "00000000-0000-0000-0000-000000000050"


# -----------------------------------------------------------------------------
# 0. API FEEDBACK TICKETS DEEP
# -----------------------------------------------------------------------------
async def test_api_feedback_tickets_deep():
    from app.api.feedback.tickets import (
        add_feedback_comment,
        assemble_ticket_detail,
        close_feedback_ticket,
        get_feedback_ticket,
        list_my_feedback_tickets,
        submit_feedback,
    )
    from app.models import (
        FeedbackCloseRequest,
        FeedbackCommentRequest,
        FeedbackSubmitRequest,
    )

    mock_req = MagicMock()
    bg = MagicMock()
    now_iso = datetime.now(timezone.utc).isoformat()

    mock_report: dict[str, Any] = {
        "id": REPORT_1,
        "user_id": USER_1,
        "query_type": "help",
        "subject": "Need assistance",
        "status": "open",
        "created_at": now_iso,
        "updated_at": now_iso,
        "message": "Message body here",
        "attachment_paths": [],
    }

    mock_history = [{"id": "h1", "report_id": REPORT_1, "status": "open", "changed_by": USER_1, "created_at": now_iso}]
    mock_comments = [{"id": "c1", "report_id": REPORT_1, "author_id": USER_1, "body": "Comment body", "created_at": now_iso}]

    with patch("app.api.feedback.tickets.feedback_module.record_feedback_submission", return_value=mock_report), \
         patch("app.api.feedback.tickets.feedback_module.fetch_user_email", return_value="a@b.com"), \
         patch("app.api.feedback.tickets.fetch_user_tickets", return_value=[mock_report]), \
         patch("app.api.feedback.tickets.feedback_module.fetch_ticket_report", return_value=mock_report), \
         patch("app.api.feedback.tickets.fetch_ticket_status_history", return_value=mock_history), \
         patch("app.api.feedback.tickets.fetch_ticket_comments", return_value=mock_comments), \
         patch("app.api.feedback.tickets.feedback_module.add_ticket_comment", return_value=mock_comments[0]), \
         patch("app.api.feedback.tickets.feedback_module.close_ticket", return_value=mock_report), \
         patch("app.api.feedback.tickets.feedback_module._assemble_ticket_detail", AsyncMock(return_value=MagicMock())):
        # submit
        sub_req = FeedbackSubmitRequest(query_type="help", subject="Help", message="Help message long enough")
        sub_res = await submit_feedback(mock_req, bg, sub_req, _device=None, user_id=USER_1)
        assert sub_res.id == REPORT_1

        # list & get
        my_t = await list_my_feedback_tickets(mock_req, 10, 0, _device=None, user_id=USER_1)
        assert len(my_t) == 1

        await get_feedback_ticket(mock_req, REPORT_1, _device=None, user_id=USER_1)

        # comment & close
        await add_feedback_comment(mock_req, REPORT_1, bg, FeedbackCommentRequest(body="Comment text"), _device=None, user_id=USER_1)
        await close_feedback_ticket(mock_req, REPORT_1, bg, FeedbackCloseRequest(reason="Resolved"), _device=None, user_id=USER_1)

        # assemble detail
        detail = await assemble_ticket_detail(USER_1, mock_report)
        assert detail.id == REPORT_1


# -----------------------------------------------------------------------------
# 1. API FEEDBACK CONTACT DEEP
# -----------------------------------------------------------------------------
async def test_api_feedback_contact_exhaustive():
    from app.api.feedback.contact import (
        _parse_attachment_path,
        _strip_exif_metadata,
        _validate_uploaded_image,
        create_error_session,
        delete_contact_attachments,
        get_error_session,
        send_contact_otp,
        submit_contact_ticket,
        upload_contact_attachment,
        verify_turnstile_token,
    )
    from app.api.feedback.models import (
        ContactOtpRequest,
        ContactSubmitRequest,
        ErrorSessionCreateRequest,
    )

    mock_req = MagicMock()
    mock_req.client.host = "127.0.0.1"
    bg = MagicMock()

    # Image validation
    img_buf = io.BytesIO()
    Image.new("RGB", (100, 100)).save(img_buf, format="JPEG")
    valid_bytes = img_buf.getvalue()
    valid_upload = UploadFile(filename="pic.jpg", file=io.BytesIO(valid_bytes))

    ext = _validate_uploaded_image(valid_upload, valid_bytes)
    assert ext == ".jpg"
    stripped = _strip_exif_metadata(valid_bytes, ".jpg")
    assert len(stripped) > 0

    assert _parse_attachment_path("web_contact/sess1/pic.jpg") == ("sess1", "pic.jpg")
    with pytest.raises(HTTPException):
        _parse_attachment_path("invalid/path")

    with patch("app.api.feedback.contact.settings.turnstile_secret_key", ""):
        assert await verify_turnstile_token("tok", "127.0.0.1") is True

    # Contact OTP & Sessions
    with patch("app.api.feedback.contact.feedback_module.redis_client") as mock_r, \
         patch("app.api.feedback.contact.feedback_module.send_support_appeal_otp_email", AsyncMock(return_value=MagicMock(success=True))), \
         patch("app.api.feedback.contact.feedback_module.supabase_client.storage.from_") as mock_storage, \
         patch("app.api.feedback.contact.feedback_module.record_feedback_submission", return_value={"id": "1", "status": "open"}), \
         patch("app.api.feedback.contact._verify_and_consume_otp", AsyncMock()), \
         patch("app.api.feedback.contact._validate_contact_attachments", AsyncMock()), \
         patch("app.api.feedback.contact._get_user_id_by_email", AsyncMock(return_value=USER_1)):
        mock_r.get = AsyncMock(return_value='{"query_type":"help","subject":"hi"}')
        mock_r.set = AsyncMock(return_value=True)
        mock_r.delete = AsyncMock(return_value=True)
        mock_storage.return_value.list.return_value = []
        mock_storage.return_value.upload.return_value = None
        mock_storage.return_value.remove.return_value = None

        # send otp
        otp_res = await send_contact_otp(mock_req, ContactOtpRequest(email="a@b.com"))
        assert otp_res["success"] is True

        # submit ticket
        sub_res = await submit_contact_ticket(
            mock_req,
            bg,
            ContactSubmitRequest(
                email="a@b.com",
                otp_code="123456",
                query_type="bug_report",
                subject="Crash",
                message="Detailed crash message here",
            ),
        )
        assert sub_res["success"] is True

        # upload & delete attachment
        up_res = await upload_contact_attachment(mock_req, valid_upload, session_id="sess1")
        assert "storage_path" in up_res

        del_res = await delete_contact_attachments(mock_req, session_id="sess1", paths=["web_contact/sess1/pic.jpg"])
        assert del_res["success"] is True

        # error sessions
        err_res = await create_error_session(
            mock_req,
            ErrorSessionCreateRequest(
                query_type="bug_report",
                subject="Error",
                message="Error details",
            ),
        )
        assert "session_id" in err_res

        get_err = await get_error_session(mock_req, err_res["session_id"])
        assert get_err["query_type"] == "help"


# -----------------------------------------------------------------------------
# 2. API SAFETY ENDPOINTS & PORTAL ENDPOINTS DEEP
# -----------------------------------------------------------------------------
async def test_api_safety_endpoints_exhaustive():
    from datetime import timedelta

    from app.api.safety.endpoints import (
        checkin_session,
        end_session,
        put_safety_contacts,
        send_safety_alert,
        start_session,
    )
    from app.models import (
        SafetyAlertRequest,
        SafetyContactIn,
        SafetyContactsSyncRequest,
        SafetyLocation,
        SafetySessionCheckinRequest,
        SafetySessionEndRequest,
        SafetySessionStartRequest,
    )

    mock_req = MagicMock()
    mock_req.client.host = "127.0.0.1"

    with patch("app.api.safety.endpoints.record_safety_alert", return_value={"id": ALERT_1, "created_at": datetime.now(timezone.utc).isoformat()}), \
         patch("app.api.safety.endpoints.update_alert_contacts_notified"), \
         patch("app.api.safety.endpoints.fetch_safety_contacts", return_value=[{"name": "Bob", "phone": "+15555555555"}]), \
         patch("app.api.safety.endpoints.fetch_contact_facing_profile_summary", return_value={"name": "Alice"}), \
         patch("app.api.safety.endpoints.sync_safety_contacts", return_value=([], [])), \
         patch("app.api.safety.endpoints.start_safety_session", return_value={"id": "s1", "status": "active"}), \
         patch("app.api.safety.endpoints.heartbeat_safety_session", return_value={"id": "s1", "status": "active"}), \
         patch("app.api.safety.endpoints.end_safety_session"), \
         patch("app.api.safety.endpoints.fetch_recent_safety_alert", return_value=None), \
         patch("app.api.safety.endpoints.send_sms", AsyncMock(return_value=MagicMock(success=True))), \
         patch("app.api.safety.endpoints.redis_client") as mock_r:
        mock_r.get = AsyncMock(return_value=None)
        mock_r.set = AsyncMock(return_value=True)
        mock_r.incr = AsyncMock(return_value=1)
        mock_r.expire = AsyncMock(return_value=True)

        # 1. Alert
        alert_req = SafetyAlertRequest(
            alert_type="sos_silent",
            current_location=SafetyLocation(lat=37.7, lng=-122.4),
        )
        a_res = await send_safety_alert(mock_req, alert_req, _device=None, user_id=USER_1)
        assert a_res.id == ALERT_1

        # 2. Sync contacts
        c_res = await put_safety_contacts(
            mock_req,
            SafetyContactsSyncRequest(contacts=[SafetyContactIn(name="Bob", phone="+15555555555")]),
            _device=None,
            user_id=USER_1,
        )
        assert c_res is not None

        # 3. Start, heartbeat, end safety session
        future_time = datetime.now(timezone.utc) + timedelta(minutes=15)
        s_start = SafetySessionStartRequest(
            interval_seconds=1800,
            next_checkin_at=future_time,
            event_label="Dinner",
        )
        s_res = await start_session(mock_req, s_start, _device=None, user_id=USER_1)
        assert s_res is not None

        hb_req = SafetySessionCheckinRequest(session_id="00000000-0000-0000-0000-000000000040", next_checkin_at=future_time + timedelta(minutes=15), battery_percent=85, connection_type="wifi")
        hb_res = await checkin_session(mock_req, hb_req, _device=None, user_id=USER_1)
        assert hb_res is not None

        end_res = await end_session(mock_req, SafetySessionEndRequest(session_id="00000000-0000-0000-0000-000000000040"), _device=None, user_id=USER_1)
        assert end_res is not None


# -----------------------------------------------------------------------------
# 3. API CHAT KEYS & PRESENCE DEEP
# -----------------------------------------------------------------------------
async def test_api_chat_keys_and_presence_deep():
    from app.api.chat.keys import (
        get_key_bundle,
        get_one_time_prekey_count,
        upload_identity_key,
        upload_one_time_prekeys,
        upload_signed_prekey,
    )
    from app.api.chat.presence import (
        batch_get_presence,
        get_presence,
        send_presence_heartbeat,
    )
    from app.models import (
        BatchPresenceRequest,
        OneTimePrekeyItem,
        PresenceHeartbeatRequest,
        UploadIdentityKeyRequest,
        UploadOneTimePrekeysRequest,
        UploadSignedPrekeyRequest,
    )

    mock_req = MagicMock()

    with patch("app.api.chat.keys.upsert_identity_key"), \
         patch("app.api.chat.keys.fetch_identity_key", return_value={"identity_public_key": b"x" * 32}), \
         patch("app.api.chat.keys.verify_signed_prekey_signature", return_value=True), \
         patch("app.api.chat.keys.upsert_signed_prekey"), \
         patch("app.api.chat.keys.bulk_insert_one_time_prekeys"), \
         patch("app.api.chat.keys.count_unused_one_time_prekeys", return_value=50), \
         patch("app.api.chat.keys.fetch_x3dh_key_bundle_unified", return_value=({"identity_public_key": b"x" * 32, "registration_id": 1, "signed_prekey_id": 1, "signed_prekey_public": b"y" * 32, "signed_prekey_signature": b"s" * 64, "one_time_prekey_id": None, "one_time_prekey_public": None, "one_time_prekey_used": False}, None)):
        # Keys
        id_req = UploadIdentityKeyRequest(
            identity_public_key=b"x" * 32,
            registration_id=12345,
        )
        await upload_identity_key(mock_req, id_req, _device=None, user_id=USER_1)

        spk_req = UploadSignedPrekeyRequest(
            key_id=1,
            public_key=b"x" * 32,
            signature=b"s" * 64,
        )
        await upload_signed_prekey(mock_req, spk_req, _device=None, user_id=USER_1)

        otpk_req = UploadOneTimePrekeysRequest(
            prekeys=[OneTimePrekeyItem(key_id=1, public_key=b"x" * 32)],
        )
        await upload_one_time_prekeys(mock_req, otpk_req, _device=None, user_id=USER_1)

        cnt_res = await get_one_time_prekey_count(mock_req, _device=None, user_id=USER_1)
        assert cnt_res.count == 50

        kb_res = await get_key_bundle(mock_req, USER_2, _device=None, user_id=USER_1)
        assert kb_res.identity_public_key is not None

    with patch("app.api.chat.presence.upsert_presence_heartbeat"), \
         patch("app.api.chat.presence.fetch_active_matches_for_targets", return_value={USER_2}), \
         patch("app.api.chat.presence.batch_fetch_presence_from_db", return_value={USER_2: {"is_online": True, "last_active_at": datetime.now(timezone.utc).isoformat()}}), \
         patch("app.api.chat.presence.batch_fetch_user_share_flags", return_value={USER_2: {"share_active_status": True, "share_read_receipts": True}}), \
         patch("app.api.chat.presence._resolve_batch_presence", AsyncMock(return_value={USER_2: MagicMock(is_online=True)})), \
         patch("app.api.chat.presence._resolve_single_presence", AsyncMock(return_value=MagicMock(is_online=True))):
        hb = await send_presence_heartbeat(mock_req, PresenceHeartbeatRequest(is_online=True), _device=None, user_id=USER_1)
        assert hb["success"] is True

        batch_p = await batch_get_presence(mock_req, BatchPresenceRequest(user_ids=[USER_2]), _device=None, user_id=USER_1)
        assert len(batch_p) > 0

        single_p = await get_presence(mock_req, USER_2, _device=None, user_id=USER_1)
        assert single_p is not None


# -----------------------------------------------------------------------------
# 4. DB USERS ACCOUNT DELETION & EXCLUSIONS DEEP
# -----------------------------------------------------------------------------
def test_db_account_deletion_and_exclusions_deep():
    from app.db.discovery.exclusions import (
        fetch_active_block_ids,
        fetch_active_discovery_excluded_ids,
    )
    from app.db.discovery.matches import (
        fetch_matches_for_user,
        record_match,
    )
    from app.db.safety.alerts import (
        fetch_contact_facing_profile_summary,
        fetch_recent_safety_alert,
        fetch_safety_alert,
        record_safety_alert,
    )
    from app.db.safety.contacts import (
        fetch_safety_contacts,
        sync_safety_contacts,
    )
    from app.db.users.account_deletion import (
        cancel_deletion,
        compute_deletion_flag_reason,
        fetch_deletion_status,
        is_phone_blocklisted,
        request_deletion,
    )

    mock_row = {
        "id": "1",
        "user_id": USER_1,
        "moderation_status": "active",
        "is_suspended": False,
        "phone_blind_index": "blind1",
        "cooldown_expires_at": (datetime.now(timezone.utc)).isoformat(),
        "deletion_requested_at": (datetime.now(timezone.utc)).isoformat(),
        "scheduled_purge_at": (datetime.now(timezone.utc)).isoformat(),
        "actor_id": USER_1,
        "target_id": USER_2,
        "action": "block",
        "tab": "Dating",
        "liker_id": USER_1,
        "liked_back_id": USER_2,
        "created_at": (datetime.now(timezone.utc)).isoformat(),
    }
    mock_ok: MagicMock = MagicMock()
    mock_ok.select.return_value = mock_ok
    mock_ok.insert.return_value = mock_ok
    mock_ok.update.return_value = mock_ok
    mock_ok.delete.return_value = mock_ok
    mock_ok.upsert.return_value = mock_ok
    mock_ok.eq.return_value = mock_ok
    mock_ok.gt.return_value = mock_ok
    mock_ok.lt.return_value = mock_ok
    mock_ok.in_.return_value = mock_ok
    mock_ok.or_.return_value = mock_ok
    mock_ok.is_.return_value = mock_ok
    mock_ok.not_.is_.return_value = mock_ok
    mock_ok.order.return_value = mock_ok
    mock_ok.limit.return_value = mock_ok
    mock_ok.execute.return_value = MagicMock(data=[mock_row])
    single_mock: MagicMock = MagicMock()
    single_mock.execute.return_value = MagicMock(data=mock_row)
    mock_ok.maybe_single.return_value = single_mock
    mock_ok.single.return_value = single_mock

    # 1. DB Account deletion
    with patch("app.db.users.account_deletion.supabase_client.table", return_value=mock_ok), \
         patch("app.db.users.account_deletion.invalidate_user_status_cache"), \
         patch("app.db.users.account_deletion._close_all_conversations"), \
         patch("app.db.users.account_deletion.reopen_conversations_for_reactivation"):
        compute_deletion_flag_reason(USER_1)
        is_phone_blocklisted("blind_idx_12345678")
        fetch_deletion_status(USER_1)
        request_deletion(USER_1, None)
        cancel_deletion(USER_1)

    # 2. DB Exclusions & Matches
    with patch("app.db.discovery.exclusions.supabase_client.table", return_value=mock_ok), \
         patch("app.db.discovery.matches.supabase_client.table", return_value=mock_ok):
        fetch_active_block_ids(USER_1)
        fetch_active_discovery_excluded_ids(USER_1, "Dating")
        record_match(USER_1, USER_2, "Dating")
        fetch_matches_for_user(USER_1, "Dating")

    # 3. DB Safety alerts & Contacts
    with patch("app.db.safety.alerts.supabase_client.table", return_value=mock_ok), \
         patch("app.db.safety.contacts.supabase_client.table", return_value=mock_ok), \
         patch("app.db.safety.contacts.supabase_client.rpc") as mock_rpc:
        mock_rpc.return_value.execute.return_value = MagicMock(data={"blocked_indices": [], "newly_notified_indices": []})
        record_safety_alert(USER_1, "sos_silent", {"lat": 37.7, "lng": -122.4})
        fetch_safety_alert(ALERT_1)
        fetch_recent_safety_alert(USER_1, "sos_silent")
        fetch_contact_facing_profile_summary(USER_1)
        fetch_safety_contacts(USER_1)
        sync_safety_contacts(USER_1, [{"name": "Bob", "phone": "+15555555555"}])
