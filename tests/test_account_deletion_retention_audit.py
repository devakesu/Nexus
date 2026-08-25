"""Unit tests for account deletion defense-in-depth retention & purge audit."""

from unittest.mock import MagicMock, patch

from app.db.users.account_deletion import _delete_no_retention_rows, purge_due_accounts


def test_delete_no_retention_rows_explicitly_deletes_vector_profiles_and_viewer_session_items() -> None:
    """_delete_no_retention_rows must explicitly delete vector_profiles and viewer discovery_session_items."""
    user_id = "00000000-0000-0000-0000-000000000001"
    pseudo_id = "pseudo-999"
    sess_ids = ["sess-1", "sess-2"]

    deleted_tables: list[tuple[str, str, str]] = []

    def mock_table(table_name: str) -> MagicMock:
        builder = MagicMock()
        builder.select.return_value = builder
        builder.eq.return_value = builder
        builder.in_.return_value = builder
        builder.or_.return_value = builder

        if table_name == "profile_pseudonym_map":
            builder.execute.return_value = MagicMock(data=[{"pseudonym_id": pseudo_id}])
        elif table_name == "discovery_sessions":
            builder.execute.return_value = MagicMock(data=[{"id": s} for s in sess_ids])
        else:
            builder.execute.return_value = MagicMock(data=[])

        # Track deletes
        def track_delete() -> MagicMock:
            del_builder = MagicMock()
            def track_eq(col: str, val: str) -> MagicMock:
                deleted_tables.append((table_name, col, val))
                return del_builder
            def track_in(col: str, vals: list[str]) -> MagicMock:
                deleted_tables.append((table_name, col, ",".join(vals)))
                return del_builder
            del_builder.eq.side_effect = track_eq
            del_builder.in_.side_effect = track_in
            del_builder.or_.return_value = del_builder
            del_builder.execute.return_value = MagicMock(data=[])
            return del_builder

        builder.delete.side_effect = track_delete
        return builder

    with patch("app.db.users.account_deletion.supabase_client.table", side_effect=mock_table):
        _delete_no_retention_rows(user_id)

    # 1. Verify vector_profiles was explicitly deleted by pseudonym_id
    assert ("vector_profiles", "pseudonym_id", pseudo_id) in deleted_tables

    # 2. Verify viewer discovery_session_items was explicitly deleted by session_id
    assert ("discovery_session_items", "session_id", "sess-1,sess-2") in deleted_tables


def test_purge_due_accounts_dynamic_flag_reevaluation() -> None:
    """purge_due_accounts must dynamically re-evaluate flag reason at purge execution time."""
    user_id = "00000000-0000-0000-0000-000000000002"
    due_accounts = [
        {
            "id": user_id,
            "mobile_blind_index": "blind_idx_1234567890abcdef",
            "deletion_flagged_reason_code": None,  # was clean at request time
        },
    ]

    mock_table = MagicMock()
    mock_builder = MagicMock()
    mock_builder.upsert.return_value = mock_builder
    mock_builder.execute.return_value = MagicMock(data=[])
    mock_table.return_value = mock_builder

    with patch("app.db.users.account_deletion._fetch_accounts_due_for_purge", return_value=due_accounts), \
         patch("app.db.users.account_deletion.compute_deletion_flag_reason", return_value="banned"), \
         patch("app.db.users.account_deletion._permanently_unmatch_all"), \
         patch("app.db.users.account_deletion._anonymize_profile_and_user"), \
         patch("app.db.users.account_deletion._delete_no_retention_rows"), \
         patch("app.db.users.account_deletion._delete_user_media_objects"), \
         patch("app.db.users.account_deletion._ban_and_scrub_auth_user"), \
         patch("app.db.users.account_deletion.supabase_client.table", mock_table):

        purge_due_accounts()

        # Verify blocklist was upserted with reason_code="banned" (re-evaluated dynamically)
        mock_table.assert_any_call("deleted_account_blocklist")
        upsert_payload = mock_builder.upsert.call_args[0][0]
        assert upsert_payload["reason_code"] == "banned"
        assert upsert_payload["phone_blind_index"] == "blind_idx_1234567890abcdef"
