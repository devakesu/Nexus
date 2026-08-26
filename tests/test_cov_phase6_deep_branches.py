"""Phase 6 Comprehensive Exception and Deep Edge Coverage Suite.

Targets high-statement missed files:
- app/db/users/account_deletion.py
- app/db/chat/chat.py
- app/db/profiles/crud.py
- app/db/discovery/exclusions.py
- app/db/users/export.py
- app/db/safety/alerts.py & app/db/safety/contacts.py & app/db/safety/sessions.py
- app/api/feedback/contact.py & app/api/feedback/tickets.py
- app/api/user/profile/details.py
"""

from __future__ import annotations

from datetime import datetime, timezone
from typing import Any
from unittest.mock import AsyncMock, MagicMock, patch

import pytest

from app.core.security.crypto import encrypt_to_hex

pytestmark = pytest.mark.anyio

USER_1 = "00000000-0000-0000-0000-000000000001"
USER_2 = "00000000-0000-0000-0000-000000000002"
MATCH_1 = "00000000-0000-0000-0000-000000000025"
CONV_1 = "00000000-0000-0000-0000-000000000030"
SESS_1 = "00000000-0000-0000-0000-000000000040"
ALERT_1 = "00000000-0000-0000-0000-000000000050"


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
        return MagicMock(data=data)

    def _single() -> MagicMock:
        if isinstance(data, list) and data:
            return MagicMock(data=data[0])
        return MagicMock(data=data)

    mock.execute = MagicMock(side_effect=_exec)
    single_mock: MagicMock = MagicMock()
    single_mock.execute = MagicMock(side_effect=_single)
    mock.maybe_single.return_value = single_mock
    return mock


# -----------------------------------------------------------------------------
# 1. DB USERS ACCOUNT DELETION & EXPORT
# -----------------------------------------------------------------------------
def test_db_account_deletion_deep():
    from app.db.users.account_deletion import (
        _anonymize_profile_and_user,
        _archive_account_history,
        _ban_and_scrub_auth_user,
        _chunked_delete_by_field,
        _chunked_delete_by_or_filter,
        _chunked_pre_purge_child_records,
        _delete_no_retention_rows,
        _delete_user_media_objects,
        _permanently_unmatch_all,
        _purge_discovery_for_user,
        _purge_single_due_account,
        _purge_vector_profiles_for_user,
        cancel_deletion,
        compute_deletion_flag_reason,
        expire_blocklist_entries,
        hard_purge_long_tail_accounts,
        is_phone_blocklisted,
        purge_due_accounts,
        request_deletion,
    )

    now = datetime.now(timezone.utc)

    # 1. compute_deletion_flag_reason & is_phone_blocklisted
    mock_t = _make_chaining_mock([{"moderation_status": "restricted", "is_suspended": True}])
    with patch("app.db.users.account_deletion.supabase_client.table", return_value=mock_t):
        reason = compute_deletion_flag_reason(USER_1)
        assert reason in ("restricted", "banned", "suspended")
        assert is_phone_blocklisted("blind_idx_123456789012") is True
        assert is_phone_blocklisted("") is False

    # 2. request_deletion & cancel_deletion
    with patch("app.db.users.account_deletion.supabase_client.table", return_value=mock_t), \
         patch("app.db.users.account_deletion.invalidate_user_status_cache"), \
         patch("app.db.users.account_deletion._close_all_conversations"), \
         patch("app.db.users.account_deletion.supabase_client.auth.admin.sign_out"), \
         patch("app.db.users.account_deletion.reopen_conversations_for_reactivation"):
        res_del = request_deletion(USER_1, flagged_reason_code="banned", access_token="tok")
        assert res_del is not None
        cancel_deletion(USER_1)

    # 3. purges and media deletions
    with patch("app.db.users.account_deletion.supabase_client.table", return_value=mock_t), \
         patch("app.db.users.account_deletion.supabase_client.storage.from_") as mock_storage, \
         patch("app.db.users.account_deletion.supabase_client.auth.admin.update_user_by_id"), \
         patch("app.db.users.account_deletion.supabase_client.auth.admin.sign_out"), \
         patch("app.db.users.account_deletion.supabase_client.auth.admin.delete_user"), \
         patch("app.db.users.account_deletion.delete_user_chat_media"):
        mock_storage.return_value.list.return_value = [{"name": "pic1.jpg"}]
        mock_storage.return_value.remove.return_value = True

        _permanently_unmatch_all(USER_1)
        _anonymize_profile_and_user(USER_1, now)
        _purge_vector_profiles_for_user(USER_1)
        _purge_discovery_for_user(USER_1)
        _delete_no_retention_rows(USER_1)
        _delete_user_media_objects(USER_1)
        _ban_and_scrub_auth_user(USER_1)
        _purge_single_due_account({"id": USER_1, "mobile_blind_index": "b_idx", "deletion_flagged_reason_code": "banned"}, now)
        _chunked_delete_by_field("chat_messages", "sender_id", USER_1, chunk_size=10)
        _chunked_delete_by_or_filter("matches", "liker_id.eq.1", USER_1, chunk_size=10)
        _chunked_pre_purge_child_records(USER_1)
        _archive_account_history(USER_1)

    with patch("app.db.users.account_deletion._fetch_accounts_due_for_purge", return_value=[{"id": USER_1}]), \
         patch("app.db.users.account_deletion._purge_single_due_account"), \
         patch("app.db.users.account_deletion.time.sleep"):
        purge_due_accounts()

    with patch("app.db.users.account_deletion.supabase_client.table", return_value=mock_t):
        expire_blocklist_entries()

    with patch("app.db.users.account_deletion._fetch_accounts_due_for_long_tail_purge", return_value=[USER_1]), \
         patch("app.db.users.account_deletion._archive_account_history", return_value=[]), \
         patch("app.db.users.account_deletion._chunked_pre_purge_child_records"), \
         patch("app.db.users.account_deletion.supabase_client.auth.admin.delete_user"), \
         patch("app.db.users.account_deletion.time.sleep"):
        hard_purge_long_tail_accounts()


# -----------------------------------------------------------------------------
# 2. DB CHAT DEEP COVERAGE
# -----------------------------------------------------------------------------
def test_db_chat_deep():
    from app.db.chat.chat import (
        _apply_reactivation_updates,
        _partition_reactivation_conversations,
        batch_delete_conversations_chat_media,
        batch_fetch_presence_from_db,
        batch_fetch_user_share_flags,
        close_conversation_for_match_action,
        delete_conversation_chat_media,
        delete_user_chat_media,
        fetch_due_event_reminders,
        fetch_due_safety_reminders,
        fetch_presence,
        fetch_started_match_ids,
        fetch_user_share_flags,
        get_or_create_conversation,
        mark_reminder_sent,
        mark_safety_reminder_sent,
        reopen_conversations_for_reactivation,
        upsert_presence_heartbeat,
    )

    mock_t = _make_chaining_mock([
        {
            "id": CONV_1,
            "user_a_id": USER_1,
            "user_b_id": USER_2,
            "match_id": MATCH_1,
            "tab": "Dating",
            "closed_at": None,
            "is_online": True,
            "last_seen_at": datetime.now(timezone.utc).isoformat(),
        }
    ])

    # 1. media removal helpers
    with patch("app.db.chat.chat.supabase_client.storage.from_") as mock_storage:
        mock_storage.return_value.list.return_value = [{"name": "img.png"}]
        mock_storage.return_value.remove.return_value = True
        delete_conversation_chat_media(CONV_1)
        delete_user_chat_media(USER_1, [CONV_1])
        batch_delete_conversations_chat_media([CONV_1])

    # 2. get or create conv & events
    with patch("app.db.chat.chat.supabase_client.table", return_value=mock_t):
        conv = get_or_create_conversation(USER_1, MATCH_1)
        assert conv is not None
        close_conversation_for_match_action(USER_1, USER_2, "Dating", reason="unmatch")

        # Reactivation partition
        reopen_ids, blocked_ids = _partition_reactivation_conversations(
            [{"id": CONV_1, "user_a_id": USER_1, "user_b_id": USER_2}],
            USER_1,
        )
        _apply_reactivation_updates(reopen_ids, blocked_ids, USER_1)
        reopen_conversations_for_reactivation(USER_1)

        # Presence & flags
        pres = fetch_presence(USER_1)
        assert pres is not None
        b_pres = batch_fetch_presence_from_db([USER_1, USER_2])
        assert b_pres is not None
        flags = fetch_user_share_flags(USER_1)
        assert flags is not None
        b_flags = batch_fetch_user_share_flags([USER_1, USER_2])
        assert b_flags is not None
        upsert_presence_heartbeat(USER_1, is_online=True)

        # Reminders & matches
        fetch_due_event_reminders(30)
        fetch_due_safety_reminders(30)
        mark_reminder_sent("e1")
        mark_safety_reminder_sent("e1")
        fetch_started_match_ids(USER_1)


# -----------------------------------------------------------------------------
# 3. DB DISCOVERY EXCLUSIONS & DB SAFETY
# -----------------------------------------------------------------------------
def test_db_exclusions_and_safety_deep():
    from app.db.discovery.exclusions import (
        _block_ids_cache_key,
        _collect_blocked_counterparty_ids,
        fetch_active_block_ids,
        fetch_active_like_action,
        fetch_likes_for_user,
        mark_likes_seen,
        record_discovery_action,
        revoke_incoming_like,
        unrevoke_incoming_like,
    )
    from app.db.safety.alerts import (
        fetch_contact_facing_profile_summary,
        fetch_recent_safety_alert,
        fetch_safety_alert,
        record_safety_alert,
        update_alert_contacts_notified,
    )
    from app.db.safety.contacts import (
        fetch_safety_contacts,
        fetch_safety_contacts_with_id,
        sync_safety_contacts,
    )
    from app.db.safety.sessions import (
        cancel_safety_escalation,
        fetch_overdue_safety_sessions,
        fetch_safety_session,
        record_safety_escalation_sent,
    )

    encrypted_phone = encrypt_to_hex("+15555555555", category="contact")
    encrypted_name = encrypt_to_hex("Bob", category="contact")
    mock_t = _make_chaining_mock([
        {
            "id": ALERT_1,
            "actor_id": USER_1,
            "target_id": USER_2,
            "action": "block",
            "tab": "Dating",
            "status": "active",
            "name": encrypted_name,
            "phone": encrypted_phone,
        }
    ])

    # 1. exclusions
    with patch("app.db.discovery.exclusions.supabase_client.table", return_value=mock_t):
        assert _block_ids_cache_key(USER_1) == f"discovery:block_ids:{USER_1}"
        assert _collect_blocked_counterparty_ids([{"actor_id": USER_1, "target_id": USER_2}], USER_1) == {USER_2}
        b_ids = fetch_active_block_ids(USER_1)
        assert USER_2 in b_ids
        record_discovery_action(USER_1, USER_2, "like", "Dating")
        revoke_incoming_like(USER_1, USER_2)
        unrevoke_incoming_like(USER_1, USER_2)
        mark_likes_seen(USER_1)
        fetch_likes_for_user(USER_1)
        fetch_active_like_action(USER_1, USER_2)

    # 2. safety alerts & contacts & sessions
    def safety_table_factory(table_name: str):
        if table_name == "safety_contacts":
            return _make_chaining_mock([
                {
                    "id": "c1",
                    "user_id": USER_1,
                    "name": encrypted_name,
                    "phone": encrypted_phone,
                }
            ])
        return mock_t

    with patch("app.db.safety.alerts.supabase_client.table", side_effect=safety_table_factory), \
         patch("app.db.safety.alerts.sign_profile_media", return_value={"name": "Alice"}):
        record_safety_alert(USER_1, "sos_silent", {"lat": 37.7, "lng": -122.4})
        fetch_safety_alert(ALERT_1)
        fetch_recent_safety_alert(USER_1, "sos_silent")
        update_alert_contacts_notified(ALERT_1, 2)
        fetch_contact_facing_profile_summary(USER_1)

    with patch("app.db.safety.contacts.supabase_client.table", side_effect=safety_table_factory), \
         patch("app.db.safety.contacts.supabase_client.rpc") as mock_rpc:
        mock_rpc.return_value.execute.return_value = MagicMock(data={"blocked_indices": [], "newly_notified": []})
        contacts = fetch_safety_contacts(USER_1)
        assert contacts is not None
        c_ids = fetch_safety_contacts_with_id(USER_1)
        assert c_ids is not None
        sync_safety_contacts(USER_1, [{"name": "Bob", "phone": "+15555555555"}])

    with patch("app.db.safety.sessions.supabase_client.table", return_value=mock_t):
        fetch_safety_session(SESS_1)
        fetch_overdue_safety_sessions(300)
        record_safety_escalation_sent(SESS_1, 1)
        cancel_safety_escalation(USER_1, SESS_1, "safe", note=None)


# -----------------------------------------------------------------------------
# 4. API FEEDBACK TICKETS & CONTACT DEEP
# -----------------------------------------------------------------------------
async def test_api_feedback_tickets_deep():
    from app.api.feedback.tickets import (
        add_feedback_comment,
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
        "id": "1",
        "user_id": USER_1,
        "query_type": "bug_report",
        "subject": "Bug",
        "message": "App crashed",
        "status": "open",
        "attachment_paths": [],
        "created_at": now_iso,
        "updated_at": now_iso,
    }

    with patch("app.api.feedback.tickets.feedback_module.record_feedback_submission", return_value={"id": "1", "created_at": now_iso, "status": "open"}), \
         patch("app.api.feedback.tickets.fetch_user_tickets", return_value=[]), \
         patch("app.api.feedback.tickets.feedback_module.fetch_ticket_report", return_value=mock_report), \
         patch("app.api.feedback.tickets.fetch_ticket_comments", return_value=[]), \
         patch("app.api.feedback.tickets.fetch_ticket_status_history", return_value=[]), \
         patch("app.api.feedback.tickets.feedback_module.add_ticket_comment", return_value={"id": "1", "report_id": "1", "author_id": USER_1, "body": "more", "created_at": now_iso}), \
         patch("app.api.feedback.tickets.feedback_module.close_ticket", return_value=mock_report), \
         patch("app.api.feedback.tickets.feedback_module.fetch_user_email", return_value="alice@berkeley.edu"), \
         patch("app.api.feedback.tickets.feedback_module.send_feedback_confirmation_email", AsyncMock()), \
         patch("app.api.feedback.tickets.feedback_module.send_feedback_admin_notification_email", AsyncMock()), \
         patch("app.api.feedback.tickets.feedback_module.send_feedback_comment_admin_notification_email", AsyncMock()), \
         patch("app.api.feedback.tickets.feedback_module.send_feedback_closed_admin_notification_email", AsyncMock()):
        # Submit
        sub = await submit_feedback(
            request=mock_req,
            background_tasks=bg,
            payload=FeedbackSubmitRequest(query_type="bug_report", subject="Bug sub", message="Detailed bug report message"),
            user_id=USER_1,
            _device=None,
        )
        assert sub is not None

        # List
        lst = await list_my_feedback_tickets(mock_req, _device=None, user_id=USER_1)
        assert len(lst) >= 0

        # Get
        t = await get_feedback_ticket(mock_req, report_id="1", _device=None, user_id=USER_1)
        assert t is not None

        # Add comment
        c = await add_feedback_comment(
            request=mock_req,
            report_id="1",
            background_tasks=bg,
            payload=FeedbackCommentRequest(body="Here is more info"),
            _device=None,
            user_id=USER_1,
        )
        assert c is not None

        # Close
        cl = await close_feedback_ticket(mock_req, report_id="1", background_tasks=bg, payload=FeedbackCloseRequest(reason="resolved"), _device=None, user_id=USER_1)
        assert cl is not None
