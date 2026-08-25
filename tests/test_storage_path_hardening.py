"""Unit tests verifying storage path percent-encoding hardening and sender-scoped chat media deletion."""

from unittest.mock import MagicMock, patch

from app.db.chat.chat import delete_user_chat_media
from app.db.profiles.media import _is_safe_media_path


def test_is_safe_media_path_rejects_percent_encoding_and_traversal() -> None:
    """_is_safe_media_path must reject percent-encoded strings, directory traversal, leading slashes, and null bytes."""
    # Valid path
    assert _is_safe_media_path("11111111-1111-1111-1111-111111111111/photo.jpg") is True

    # Percent encoding (including encoded traversal)
    assert _is_safe_media_path("11111111-1111-1111-1111-111111111111/%2e%2e/secret.jpg") is False
    assert _is_safe_media_path("11111111-1111-1111-1111-111111111111/%2fetc%2fpasswd") is False
    assert _is_safe_media_path("11111111-1111-1111-1111-111111111111/photo%20name.jpg") is False

    # Plain traversal and invalid separators
    assert _is_safe_media_path("../other_user/photo.jpg") is False
    assert _is_safe_media_path("11111111-1111-1111-1111-111111111111/../photo.jpg") is False
    assert _is_safe_media_path("/11111111-1111-1111-1111-111111111111/photo.jpg") is False
    assert _is_safe_media_path("11111111-1111-1111-1111-111111111111\\photo.jpg") is False
    assert _is_safe_media_path("11111111-1111-1111-1111-111111111111/\x00photo.jpg") is False
    assert _is_safe_media_path("") is False


def test_delete_user_chat_media_purges_only_sender_prefixed_blobs() -> None:
    """delete_user_chat_media must only list and remove blobs under {conv_id}/{user_id}/*."""
    user_id = "11111111-1111-1111-1111-111111111111"
    conv_ids = ["conv-aaa", "conv-bbb"]

    mock_storage = MagicMock()

    def mock_list(prefix: str) -> list[dict[str, str]]:
        if prefix == f"conv-aaa/{user_id}":
            return [{"name": "image1.enc"}, {"name": "voice1.enc"}]
        if prefix == f"conv-bbb/{user_id}":
            return [{"name": "image2.enc"}]
        return []

    mock_storage.list.side_effect = mock_list

    with patch("app.db.chat.chat.supabase_client.storage.from_", return_value=mock_storage):
        delete_user_chat_media(user_id, conv_ids)

    # Verify storage.list was called with user-scoped prefixes
    mock_storage.list.assert_any_call(f"conv-aaa/{user_id}")
    mock_storage.list.assert_any_call(f"conv-bbb/{user_id}")
    assert mock_storage.list.call_count == 2

    # Verify remove was called with only this user's paths
    mock_storage.remove.assert_called_once_with([
        f"conv-aaa/{user_id}/image1.enc",
        f"conv-aaa/{user_id}/voice1.enc",
        f"conv-bbb/{user_id}/image2.enc",
    ])


def test_delete_user_chat_media_noop_on_empty() -> None:
    """delete_user_chat_media does nothing if user_id or conversation_ids is empty."""
    mock_storage = MagicMock()
    with patch("app.db.chat.chat.supabase_client.storage.from_", return_value=mock_storage):
        delete_user_chat_media("", ["conv-1"])
        delete_user_chat_media("11111111-1111-1111-1111-111111111111", [])

    mock_storage.list.assert_not_called()
    mock_storage.remove.assert_not_called()
