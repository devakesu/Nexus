"""Phase 16 Deep Exceptions & Purge Edge Branches Suite.

Targeting error and fallback paths to reach 90%+ coverage:
1. app/db/users/account_deletion.py (APIError branches in _permanently_unmatch_all, _anonymize_profile_and_user, _purge_single_due_account, etc.)
2. app/db/safety/alerts.py (exceptions & APIErrors)
3. app/db/safety/contacts.py (exceptions & APIErrors)
"""

from __future__ import annotations

from datetime import datetime, timezone
from unittest.mock import MagicMock, patch

import pytest
from app.db.client import DatabaseAccessError
from postgrest.exceptions import APIError

pytestmark = pytest.mark.anyio

USER_1 = "00000000-0000-0000-0000-000000000001"
USER_2 = "00000000-0000-0000-0000-000000000002"
CONTACT_1 = "00000000-0000-0000-0000-000000000030"
SESSION_1 = "00000000-0000-0000-0000-000000000040"




# -----------------------------------------------------------------------------
# 1. DB ACCOUNT DELETION ERROR PATHS
# -----------------------------------------------------------------------------
def test_db_account_deletion_error_branches():
    from app.db.users.account_deletion import (
        _anonymize_profile_and_user,
        _ban_and_scrub_auth_user,
        _delete_no_retention_rows,
        _delete_user_media_objects,
        _permanently_unmatch_all,
        _purge_discovery_for_user,
        _purge_single_due_account,
        _purge_vector_profiles_for_user,
        compute_deletion_flag_reason,
        is_phone_blocklisted,
        purge_due_accounts,
    )

    err_table = MagicMock()
    err_table.select.return_value = err_table
    err_table.update.return_value = err_table
    err_table.delete.return_value = err_table
    err_table.eq.return_value = err_table
    err_table.limit.return_value = err_table
    err_table.in_.return_value = err_table
    err_table.or_.return_value = err_table
    err_table.gt.return_value = err_table
    err_table.is_.return_value = err_table
    err_table.execute.side_effect = APIError({"message": "DB Error", "code": "500"})

    mock_client = MagicMock()
    mock_client.table.return_value = err_table
    mock_client.auth.admin.update_user_by_id.side_effect = Exception("Auth Error")
    mock_client.auth.admin.sign_out.side_effect = Exception("Signout Error")
    mock_client.storage.from_.return_value.list.side_effect = Exception("Storage List Error")

    with patch("app.db.users.account_deletion.supabase_client", mock_client):
        # compute_deletion_flag_reason error
        with pytest.raises(DatabaseAccessError):
            compute_deletion_flag_reason(USER_1)

        # is_phone_blocklisted error
        with pytest.raises(DatabaseAccessError):
            is_phone_blocklisted("blind_index_123")

        # _permanently_unmatch_all error
        with pytest.raises(DatabaseAccessError):
            _permanently_unmatch_all(USER_1)

        # _anonymize_profile_and_user error
        with pytest.raises(DatabaseAccessError):
            _anonymize_profile_and_user(USER_1, datetime.now(timezone.utc))

        # private helpers log exceptions and suppress gracefully
        _purge_vector_profiles_for_user(USER_1)
        _purge_discovery_for_user(USER_1)
        _delete_no_retention_rows(USER_1)
        _delete_user_media_objects(USER_1)
        _ban_and_scrub_auth_user(USER_1)
        _purge_single_due_account({"id": USER_1}, datetime.now(timezone.utc))
        purge_due_accounts()


# -----------------------------------------------------------------------------
# 2. DB SAFETY CONTACTS & ALERTS ERROR PATHS
# -----------------------------------------------------------------------------
def test_db_safety_error_branches():
    from app.db.safety.alerts import (
        fetch_alerts_for_session,
        fetch_contact_facing_profile_summary,
        record_safety_alert,
    )
    from app.db.safety.contacts import (
        fetch_safety_contact_by_id,
        fetch_safety_contacts,
        fetch_safety_contacts_with_id,
        sync_safety_contacts,
    )

    err_table = MagicMock()
    err_table.select.return_value = err_table
    err_table.insert.return_value = err_table
    err_table.delete.return_value = err_table
    err_table.upsert.return_value = err_table
    err_table.eq.return_value = err_table
    err_table.order.return_value = err_table
    err_table.limit.return_value = err_table
    err_table.execute.side_effect = APIError({"message": "DB Error", "code": "500"})
    
    single_mock = MagicMock()
    single_mock.execute.side_effect = APIError({"message": "DB Single Error", "code": "500"})
    err_table.maybe_single.return_value = single_mock
    err_table.single.return_value = single_mock

    mock_client = MagicMock()
    mock_client.table.return_value = err_table
    mock_client.rpc.return_value.execute.side_effect = APIError({"message": "RPC Error", "code": "500"})

    with patch("app.db.safety.alerts.supabase_client", mock_client), \
         patch("app.db.safety.contacts.supabase_client", mock_client):
        with pytest.raises(DatabaseAccessError):
            fetch_contact_facing_profile_summary(USER_1)

        with pytest.raises(DatabaseAccessError):
            record_safety_alert(USER_1, "sos", {"lat": 1.0, "lng": 1.0})

        with pytest.raises(DatabaseAccessError):
            fetch_alerts_for_session(SESSION_1)

        with pytest.raises(DatabaseAccessError):
            sync_safety_contacts(USER_1, [{"name": "A", "phone": "+15550000000"}])

        with pytest.raises(DatabaseAccessError):
            fetch_safety_contacts(USER_1)

        with pytest.raises(DatabaseAccessError):
            fetch_safety_contacts_with_id(USER_1)

        with pytest.raises(DatabaseAccessError):
            fetch_safety_contact_by_id(CONTACT_1)
