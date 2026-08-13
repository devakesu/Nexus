from unittest.mock import MagicMock, patch

from app.db.chat.chat import reopen_conversations_for_reactivation


@patch("app.db.discovery.exclusions.fetch_active_block_ids")
@patch("app.db.chat.chat.supabase_client.table")
def test_reopen_conversations_skips_blocked_participants(
    mock_table: MagicMock,
    mock_fetch_blocks: MagicMock,
) -> None:
    user_id = "11111111-1111-1111-1111-111111111111"
    user_blocked = "22222222-2222-2222-2222-222222222222"
    user_clean = "33333333-3333-3333-3333-333333333333"

    mock_fetch_blocks.return_value = {user_blocked}

    conversations_data = [
        {"id": "conv-1", "user_a_id": user_id, "user_b_id": user_blocked},
        {"id": "conv-2", "user_a_id": user_clean, "user_b_id": user_id},
    ]

    select_builder = MagicMock()
    select_builder.select.return_value = select_builder
    select_builder.or_.return_value = select_builder
    select_builder.eq.return_value = select_builder
    select_builder.execute.return_value = MagicMock(data=conversations_data)

    update_builder = MagicMock()
    update_builder.update.return_value = update_builder
    update_builder.in_.return_value = update_builder
    update_builder.execute.return_value = MagicMock(data=[])

    mock_table.side_effect = [select_builder, update_builder, update_builder]

    reopen_conversations_for_reactivation(user_id)

    mock_fetch_blocks.assert_called_once_with(user_id)

    # 1. First update call: Reopen conv-2 (user_clean)
    update_builder.update.assert_any_call({"closed_at": None, "closed_reason": None})
    update_builder.in_.assert_any_call("id", ["conv-2"])

    # 2. Second update call: Keep conv-1 closed, mark closed_reason as "block"
    update_builder.update.assert_any_call({"closed_reason": "block"})
    update_builder.in_.assert_any_call("id", ["conv-1"])


@patch("app.db.discovery.exclusions.fetch_active_block_ids")
@patch("app.db.chat.chat.supabase_client.table")
def test_reopen_conversations_all_clean(
    mock_table: MagicMock,
    mock_fetch_blocks: MagicMock,
) -> None:
    user_id = "11111111-1111-1111-1111-111111111111"
    user_clean = "33333333-3333-3333-3333-333333333333"

    mock_fetch_blocks.return_value = set()

    conversations_data = [
        {"id": "conv-2", "user_a_id": user_clean, "user_b_id": user_id},
    ]

    select_builder = MagicMock()
    select_builder.select.return_value = select_builder
    select_builder.or_.return_value = select_builder
    select_builder.eq.return_value = select_builder
    select_builder.execute.return_value = MagicMock(data=conversations_data)

    update_builder = MagicMock()
    update_builder.update.return_value = update_builder
    update_builder.in_.return_value = update_builder
    update_builder.execute.return_value = MagicMock(data=[])

    mock_table.side_effect = [select_builder, update_builder]

    reopen_conversations_for_reactivation(user_id)

    mock_fetch_blocks.assert_called_once_with(user_id)
    update_builder.update.assert_called_once_with({"closed_at": None, "closed_reason": None})
    update_builder.in_.assert_called_once_with("id", ["conv-2"])


@patch("app.db.discovery.exclusions.fetch_active_block_ids")
@patch("app.db.chat.chat.supabase_client.table")
def test_reopen_conversations_no_conversations_to_reopen(
    mock_table: MagicMock,
    mock_fetch_blocks: MagicMock,
) -> None:
    user_id = "11111111-1111-1111-1111-111111111111"

    select_builder = MagicMock()
    select_builder.select.return_value = select_builder
    select_builder.or_.return_value = select_builder
    select_builder.eq.return_value = select_builder
    select_builder.execute.return_value = MagicMock(data=[])

    mock_table.return_value = select_builder

    reopen_conversations_for_reactivation(user_id)

    mock_fetch_blocks.assert_not_called()
    select_builder.update.assert_not_called()
