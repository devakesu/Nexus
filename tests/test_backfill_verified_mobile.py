from datetime import datetime, timezone
from unittest.mock import MagicMock, patch

from scripts.backfill_verified_mobile import main


def test_backfill_verified_mobile_flow() -> None:
    user_with_dt = MagicMock()
    user_with_dt.id = "u1"
    user_with_dt.phone = "+15551234567"
    user_with_dt.phone_confirmed_at = datetime(
        2026, 7, 1, 12, 0, 0, tzinfo=timezone.utc,
    )

    user_with_str = MagicMock()
    user_with_str.id = "u2"
    user_with_str.phone = "+15559876543"
    user_with_str.phone_confirmed_at = "2026-07-02T12:00:00Z"

    user_unverified = MagicMock()
    user_unverified.id = "u3"
    user_unverified.phone = "+15550000000"
    user_unverified.phone_confirmed_at = None

    user_no_phone = MagicMock()
    user_no_phone.id = "u4"
    user_no_phone.phone = None
    user_no_phone.phone_confirmed_at = None

    mock_client = MagicMock()
    mock_query = MagicMock()
    mock_client.table.return_value = mock_query
    mock_query.update.return_value = mock_query
    mock_query.eq.return_value = mock_query
    mock_query.execute.return_value = MagicMock()

    # Pagination: page 1 returns 4 users, page 2 returns empty list
    mock_client.auth.admin.list_users.side_effect = [
        [user_with_dt, user_with_str, user_unverified, user_no_phone],
        [],
    ]

    with patch("scripts.backfill_verified_mobile.supabase_client", mock_client):
        main()

        assert mock_client.auth.admin.list_users.call_count == 2
        assert mock_query.update.call_count == 2
        assert mock_query.eq.call_count == 2


def test_backfill_verified_mobile_main_invocation() -> None:
    mock_client = MagicMock()
    mock_client.auth.admin.list_users.return_value = []
    with patch("app.db.client.supabase_client", mock_client):
        import runpy

        runpy.run_path("scripts/backfill_verified_mobile.py", run_name="__main__")
