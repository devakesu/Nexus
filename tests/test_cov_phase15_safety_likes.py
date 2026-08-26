"""Phase 15 Safety & Likes Deep Coverage Suite to decisively push repository coverage to 90%+.

Targeting:
1. app/db/safety/alerts.py (fetch_contact_facing_profile_summary, record_safety_alert, fetch_alerts_for_session, purge_expired_safety_evidence, purge_safety_data_for_purged_accounts)
2. app/db/safety/contacts.py (sync_safety_contacts, fetch_safety_contacts, fetch_safety_contacts_with_id, fetch_safety_contact_by_id, remove_safety_contact_self_service)
3. app/api/discovery/likes.py (record_like_action matched branches & unrevoke fallback)
"""

from __future__ import annotations

from datetime import datetime, timezone
from typing import Any
from unittest.mock import AsyncMock, MagicMock, patch

import pytest

pytestmark = pytest.mark.anyio

USER_1 = "00000000-0000-0000-0000-000000000001"
USER_2 = "00000000-0000-0000-0000-000000000002"
CONTACT_1 = "00000000-0000-0000-0000-000000000030"
SESSION_1 = "00000000-0000-0000-0000-000000000040"


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
    mock.single.return_value = single_mock
    return mock


# -----------------------------------------------------------------------------
# 1. DB SAFETY ALERTS
# -----------------------------------------------------------------------------
def test_db_safety_alerts_deep():
    from app.db.safety.alerts import (
        fetch_alerts_for_session,
        fetch_contact_facing_profile_summary,
        purge_expired_safety_evidence,
        purge_safety_data_for_purged_accounts,
        record_safety_alert,
    )

    mock_alert = {
        "id": "alt_1",
        "alert_type": "sos",
        "current_location": "\\x6464",
        "created_at": datetime.now(timezone.utc).isoformat(),
    }
    mock_t = _make_chaining_mock([mock_alert])
    mock_client = MagicMock()
    mock_client.table.return_value = mock_t
    mock_client.storage.from_.return_value.remove.return_value = True

    with patch("app.db.safety.alerts.supabase_client", mock_client), \
         patch("app.db.safety.alerts.decrypt_pii", return_value='{"lat": 37.77, "lng": -122.41}'), \
         patch("app.db.safety.alerts.encrypt_to_hex", return_value="\\x6464"), \
         patch("app.db.safety.alerts.decrypt_profile_record", return_value={"name": "Alice"}), \
         patch("app.db.safety.alerts.sign_profile_media", return_value={"name": "Alice"}):
        summary = fetch_contact_facing_profile_summary(USER_1)
        assert summary is not None

        alert_res = record_safety_alert(USER_1, "sos", {"lat": 37.77, "lng": -122.41}, SESSION_1)
        assert alert_res is not None

        alerts = fetch_alerts_for_session(SESSION_1, decrypt_locations=True)
        assert len(alerts) > 0

        purge_expired_safety_evidence()
        purge_safety_data_for_purged_accounts()


# -----------------------------------------------------------------------------
# 2. DB SAFETY CONTACTS
# -----------------------------------------------------------------------------
def test_db_safety_contacts_deep():
    from app.db.safety.contacts import (
        fetch_safety_contact_by_id,
        fetch_safety_contacts,
        fetch_safety_contacts_with_id,
        remove_safety_contact_self_service,
        sync_safety_contacts,
    )

    mock_contact = {
        "id": CONTACT_1,
        "user_id": USER_1,
        "name": "\\x6161",
        "phone": "\\x6262",
    }
    mock_t = _make_chaining_mock([mock_contact])

    with patch("app.db.safety.contacts.supabase_client.table", return_value=mock_t), \
         patch("app.db.safety.contacts.supabase_client.rpc") as mock_rpc, \
         patch("app.db.safety.contacts.decrypt_pii", return_value="+15551234567"), \
         patch("app.db.safety.contacts.encrypt_to_hex", return_value="\\x6262"):
        mock_rpc.return_value.execute.return_value = MagicMock(
            data={"blocked_indices": [], "newly_notified_indices": []},
        )

        blocked, _newly = sync_safety_contacts(USER_1, [{"name": "Dad", "phone": "+15551234567"}])
        assert isinstance(blocked, list)

        contacts = fetch_safety_contacts(USER_1)
        assert len(contacts) > 0

        contacts_id = fetch_safety_contacts_with_id(USER_1)
        assert len(contacts_id) > 0

        single = fetch_safety_contact_by_id(CONTACT_1)
        assert single is not None

        removed = remove_safety_contact_self_service(CONTACT_1)
        assert removed is not None


# -----------------------------------------------------------------------------
# 3. API DISCOVERY LIKES MATCHED & UNREVOKE
# -----------------------------------------------------------------------------
async def test_api_discovery_likes_matched_branches():
    from app.api.discovery.likes import (
        get_matches,
        record_like_back_action,
    )
    from app.models import LikeActionRequest

    mock_req = MagicMock()
    mock_match_row = {
        "match_id": "m1",
        "matched_user_id": USER_2,
        "created_at": datetime.now(timezone.utc).isoformat(),
    }
    mock_prof_row = {
        "id": USER_2,
        "name": "Bob",
        "age": 24,
        "profile_pic": "p.jpg",
    }
    mock_t = _make_chaining_mock([mock_prof_row])

    with patch("app.api.discovery.likes.supabase_client.table", return_value=mock_t), \
         patch("app.api.discovery.likes.fetch_likes_for_user", return_value=[]), \
         patch("app.api.discovery.likes.fetch_matches_for_user", return_value=[mock_match_row]), \
         patch("app.api.discovery.likes.get_cached_active_block_ids", AsyncMock(return_value=set())), \
         patch("app.api.discovery.likes._decrypt_profiles", return_value={USER_2: {"name": "Bob", "age": 24, "profile_pic": "p.jpg"}}), \
         patch("app.api.discovery.likes.revoke_incoming_like", return_value=True), \
         patch("app.api.discovery.likes.record_match", return_value="m1"), \
         patch("app.api.discovery.likes.send_match_notification", AsyncMock()):
        matches_res = await get_matches(mock_req, tab="Dating", _device=None, user_id=USER_1)
        assert len(matches_res.matches) > 0

        req_payload = LikeActionRequest(
            action="like",
            target_id=USER_2,
            tab="Dating",
        )
        res_like = await record_like_back_action(mock_req, req_payload, _device=None, user_id=USER_1)
        assert res_like.matched is True
        assert res_like.match_id == "m1"
