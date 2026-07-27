"""User privacy and email notification settings endpoints."""

import logging
from typing import Any, cast

from fastapi import APIRouter, Body, Depends, HTTPException

from app.api.dependencies import get_active_user_id
from app.db.client import supabase_client
from app.models import (
    ALLOWED_HIDDEN_FIELDS,
    EmailNotificationSettingsResponse,
    EmailNotificationSettingsUpdate,
    PrivacySettingsResponse,
    PrivacySettingsUpdate,
)

logger = logging.getLogger(__name__)

router = APIRouter()

_EMAIL_NOTIFICATION_COLUMNS = (
    "email_notify_matches, email_notify_messages, email_notify_digest, "
    "email_notify_product_updates, email_notify_promotions"
)


def _to_privacy_settings_response(data: dict[str, Any]) -> PrivacySettingsResponse:
    raw: list[str] = list(data.get("hidden_profile_fields") or [])
    hidden: list[str] = [f for f in raw if f in ALLOWED_HIDDEN_FIELDS]
    return PrivacySettingsResponse(
        hidden_fields=hidden,
        share_active_status=bool(data.get("share_active_status", True)),
        share_read_receipts=bool(data.get("share_read_receipts", True)),
    )


@router.get(
    "/api/v1/profile/privacy-settings",
    response_model=PrivacySettingsResponse,
)
def get_privacy_settings(
    user_id: str = Depends(get_active_user_id),
) -> PrivacySettingsResponse:
    """Executes get privacy settings operation."""
    try:
        res = (
            supabase_client.table("profiles")
            .select("hidden_profile_fields, share_active_status, share_read_receipts")
            .eq("id", user_id)
            .maybe_single()
            .execute()
        )
        data = getattr(res, "data", None)
        if data is None:
            raise HTTPException(status_code=404, detail="Profile not found")
        return _to_privacy_settings_response(data)
    except HTTPException:
        raise
    except Exception as e:
        logger.exception("Failed to fetch privacy settings for user %s", user_id)
        raise HTTPException(status_code=500, detail="Internal server error.") from e


@router.patch(
    "/api/v1/profile/privacy-settings",
    response_model=PrivacySettingsResponse,
)
def update_privacy_settings(
    payload: PrivacySettingsUpdate = Body(...),
    user_id: str = Depends(get_active_user_id),
) -> PrivacySettingsResponse:
    """Executes update privacy settings operation."""
    update_data: dict[str, Any] = {}
    if payload.hidden_fields is not None:
        update_data["hidden_profile_fields"] = payload.hidden_fields
    if payload.share_active_status is not None:
        update_data["share_active_status"] = payload.share_active_status
    if payload.share_read_receipts is not None:
        update_data["share_read_receipts"] = payload.share_read_receipts
    if not update_data:
        raise HTTPException(status_code=400, detail="No fields to update.")

    try:
        res = (
            supabase_client.table("profiles")
            .update(update_data)
            .eq("id", user_id)
            .select("hidden_profile_fields, share_active_status, share_read_receipts")
            .execute()
        )
        rows = cast(list[dict[str, Any]], getattr(res, "data", None) or [])
        if not rows:
            raise HTTPException(status_code=404, detail="Profile not found")
        return _to_privacy_settings_response(rows[0])
    except HTTPException:
        raise
    except Exception as e:
        logger.exception("Failed to update privacy settings for user %s", user_id)
        raise HTTPException(status_code=500, detail="Internal server error.") from e


def _to_email_notification_settings_response(
    data: dict[str, Any],
) -> EmailNotificationSettingsResponse:
    return EmailNotificationSettingsResponse(
        email_notify_matches=bool(data.get("email_notify_matches", True)),
        email_notify_messages=bool(data.get("email_notify_messages", True)),
        email_notify_digest=bool(data.get("email_notify_digest", True)),
        email_notify_product_updates=bool(
            data.get("email_notify_product_updates", True),
        ),
        email_notify_promotions=bool(data.get("email_notify_promotions", True)),
    )


@router.get(
    "/api/v1/profile/email-notification-settings",
    response_model=EmailNotificationSettingsResponse,
)
def get_email_notification_settings(
    user_id: str = Depends(get_active_user_id),
) -> EmailNotificationSettingsResponse:
    """Executes get email notification settings operation."""
    try:
        res = (
            supabase_client.table("profiles")
            .select(_EMAIL_NOTIFICATION_COLUMNS)
            .eq("id", user_id)
            .maybe_single()
            .execute()
        )
        data = getattr(res, "data", None)
        if data is None:
            raise HTTPException(status_code=404, detail="Profile not found")
        return _to_email_notification_settings_response(data)
    except HTTPException:
        raise
    except Exception as e:
        logger.exception(
            "Failed to fetch email notification settings for user %s",
            user_id,
        )
        raise HTTPException(status_code=500, detail="Internal server error.") from e


@router.patch(
    "/api/v1/profile/email-notification-settings",
    response_model=EmailNotificationSettingsResponse,
)
def update_email_notification_settings(
    payload: EmailNotificationSettingsUpdate = Body(...),
    user_id: str = Depends(get_active_user_id),
) -> EmailNotificationSettingsResponse:
    """Executes update email notification settings operation."""
    update_data = payload.model_dump(exclude_none=True)
    if not update_data:
        raise HTTPException(status_code=400, detail="No fields to update.")

    try:
        res = (
            supabase_client.table("profiles")
            .update(update_data)
            .eq("id", user_id)
            .select(_EMAIL_NOTIFICATION_COLUMNS)
            .execute()
        )
        rows = cast(list[dict[str, Any]], getattr(res, "data", None) or [])
        if not rows:
            raise HTTPException(status_code=404, detail="Profile not found")
        return _to_email_notification_settings_response(rows[0])
    except HTTPException:
        raise
    except Exception as e:
        logger.exception(
            "Failed to update email notification settings for user %s",
            user_id,
        )
        raise HTTPException(status_code=500, detail="Internal server error.") from e
