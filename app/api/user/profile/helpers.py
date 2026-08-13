"""Helper functions for profile validation, decryption assertions, and change windows."""

import logging
from datetime import datetime, timedelta, timezone
from typing import Any, cast

from fastapi import HTTPException, status

from app.db.client import parse_utc_datetime, supabase_client
from app.models import ProfileDetailsUpdate

logger = logging.getLogger(__name__)

_VALUE_DIMENSION_TRIGGER_FIELDS = frozenset(
    {
        "interests",
        "sub_interests",
        "causes_supported",
        "tech_skills",
        "activities",
        "lifestyle",
    },
)

_AGE_CHANGE_WINDOW_DAYS = 365
_AGE_CHANGE_MAX_PER_WINDOW = 2
_NAME_CHANGE_WINDOW_DAYS = 365
_NAME_CHANGE_MAX_PER_WINDOW = 2

_SPECIAL_CATEGORY_OPT_OUT_VALUES = {
    "display_sexuality": "Prefer not to say",
    "religious_beliefs": "Prefer not to say",
}


def assert_no_decryption_failures(profile: dict[str, Any]) -> None:
    for val in profile.values():
        if (
            val == "__DECRYPTION_FAILED__"
            or val == ["__DECRYPTION_FAILED__"]
            or val == {"__DECRYPTION_FAILED__": True}
        ):
            raise HTTPException(
                status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
                detail=(
                    "Profile decryption failed due to data corruption or key mismatch."
                ),
            )


_assert_no_decryption_failures = assert_no_decryption_failures


def rolling_change_window_status(
    table: str,
    user_id: str,
    window_days: int,
    max_changes: int,
) -> tuple[int, bool, datetime | None]:
    cutoff = datetime.now(timezone.utc) - timedelta(days=window_days)
    try:
        res = (
            supabase_client.table(table)
            .select("changed_at")
            .eq("user_id", user_id)
            .gte("changed_at", cutoff.isoformat())
            .order("changed_at")
            .execute()
        )
    except Exception as e:
        logger.exception(
            "Failed to check rolling change-window eligibility",
            extra={"user_id": user_id, "table": table},
        )
        raise HTTPException(
            status_code=500,
            detail="Internal server error.",
        ) from e

    rows = cast("list[dict[str, Any]]", getattr(res, "data", None) or [])
    used = len(rows)
    eligible = used < max_changes
    next_eligible = (
        parse_utc_datetime(rows[0]["changed_at"]) + timedelta(days=window_days)
        if not eligible
        else None
    )
    return used, eligible, next_eligible


_rolling_change_window_status = rolling_change_window_status


def build_ordered_images(profile: dict[str, Any]) -> list[str]:
    profile_pic = profile.get("profile_pic")
    normal_pics = profile.get("normal_pics")
    ordered_images: list[str] = []
    if profile_pic and isinstance(profile_pic, str) and profile_pic.strip():
        ordered_images.append(profile_pic)
    if isinstance(normal_pics, list):
        for p in cast(list[object], normal_pics):
            if isinstance(p, str) and p.strip():
                ordered_images.append(p)
    return ordered_images


_build_ordered_images = build_ordered_images


def sets_special_category_data(payload: ProfileDetailsUpdate) -> bool:
    return any(
        (val := getattr(payload, field, None)) is not None and val != opt_out
        for field, opt_out in _SPECIAL_CATEGORY_OPT_OUT_VALUES.items()
    )


_sets_special_category_data = sets_special_category_data


def _resolve_field(
    profile: dict[str, Any],
    payload: ProfileDetailsUpdate,
    field_name: str,
) -> Any:
    payload_val = getattr(payload, field_name, None)
    return payload_val if payload_val is not None else profile.get(field_name)


def _validate_common_activation(
    profile: dict[str, Any],
    payload: ProfileDetailsUpdate,
    missing: list[str],
) -> None:
    val_name = _resolve_field(profile, payload, "name")
    val_age = _resolve_field(profile, payload, "age")
    val_sub_interests = _resolve_field(profile, payload, "sub_interests")
    val_profile_pic = _resolve_field(profile, payload, "profile_pic")
    val_normal_pics = _resolve_field(profile, payload, "normal_pics")
    val_bio = _resolve_field(profile, payload, "bio")

    if not isinstance(val_name, str) or not val_name.strip():
        missing.append("name")
    if val_age is None:
        missing.append("age")

    sub_count = (
        sum(len(v) for v in cast(dict[str, list[str]], val_sub_interests).values())
        if isinstance(val_sub_interests, dict)
        else 0
    )
    if val_sub_interests != {"__DECRYPTION_FAILED__": True} and sub_count < 2:
        missing.append("interests")
    if (
        not isinstance(val_profile_pic, str)
        or not val_profile_pic.strip()
        or val_profile_pic == "__DECRYPTION_FAILED__"
    ):
        missing.append("profile_pic")
    if (
        not isinstance(val_normal_pics, list)
        or len(cast(list[Any], val_normal_pics)) < 1
        or val_normal_pics == ["__DECRYPTION_FAILED__"]
        or any(p == "__DECRYPTION_FAILED__" for p in cast(list[object], val_normal_pics))
    ):
        missing.append("normal_pics")
    if val_bio == "__DECRYPTION_FAILED__":
        pass
    else:
        if not isinstance(val_bio, str) or sum(c.isalpha() for c in val_bio) < 3:
            missing.append("bio")


def _validate_dating_activation(
    profile: dict[str, Any],
    payload: ProfileDetailsUpdate,
    missing: list[str],
) -> None:
    val_drinking = _resolve_field(profile, payload, "drinking")
    val_smoking = _resolve_field(profile, payload, "smoking")
    val_dating_target_buckets = _resolve_field(
        profile,
        payload,
        "dating_target_buckets",
    )
    val_dating_for = _resolve_field(profile, payload, "dating_for")
    val_partner_values = _resolve_field(profile, payload, "partner_values")

    if not isinstance(val_drinking, str) or not val_drinking.strip():
        missing.append("drinking")
    if not isinstance(val_smoking, str) or not val_smoking.strip():
        missing.append("smoking")
    if (
        not isinstance(val_dating_target_buckets, list)
        or len(cast(list[Any], val_dating_target_buckets)) < 1
    ):
        missing.append("dating_target_buckets")
    if not isinstance(val_dating_for, list) or len(cast(list[Any], val_dating_for)) < 1:
        missing.append("dating_for")
    if (
        not isinstance(val_partner_values, list)
        or len(cast(list[Any], val_partner_values)) < 1
    ):
        missing.append("partner_values")


def _validate_friends_activation(
    profile: dict[str, Any],
    payload: ProfileDetailsUpdate,
    missing: list[str],
) -> None:
    val_causes = _resolve_field(profile, payload, "causes_supported")
    val_friends_target = _resolve_field(profile, payload, "friends_target_buckets")

    if (
        not isinstance(val_causes, list)
        or len(cast(list[Any], val_causes)) < 1
    ):
        missing.append("causes_supported")
    if (
        not isinstance(val_friends_target, list)
        or len(cast(list[Any], val_friends_target)) < 1
    ):
        missing.append("friends_target_buckets")


def _validate_professional_activation(
    profile: dict[str, Any],
    payload: ProfileDetailsUpdate,
    missing: list[str],
) -> None:
    val_role = _resolve_field(profile, payload, "role_at")
    val_looking = _resolve_field(profile, payload, "looking_for")
    val_tech = _resolve_field(profile, payload, "tech_skills")
    val_prof_target = _resolve_field(profile, payload, "professional_target_buckets")

    if not isinstance(val_role, str) or not val_role.strip():
        missing.append("role_at")
    if (
        not isinstance(val_looking, list)
        or len(cast(list[Any], val_looking)) < 1
    ):
        missing.append("looking_for")
    if (
        not isinstance(val_tech, list)
        or len(cast(list[Any], val_tech)) < 1
    ):
        missing.append("tech_skills")
    if (
        not isinstance(val_prof_target, list)
        or len(cast(list[Any], val_prof_target)) < 1
    ):
        missing.append("professional_target_buckets")


def calculate_activation_statuses(
    profile: dict[str, Any],
    payload: ProfileDetailsUpdate,
) -> dict[str, bool]:
    missing_common: list[str] = []
    _validate_common_activation(profile, payload, missing_common)
    if missing_common:
        return {
            "is_dating_active": False,
            "is_friends_active": False,
            "is_professional_active": False,
        }

    missing_dating: list[str] = []
    _validate_dating_activation(profile, payload, missing_dating)

    missing_friends: list[str] = []
    _validate_friends_activation(profile, payload, missing_friends)

    missing_prof: list[str] = []
    _validate_professional_activation(profile, payload, missing_prof)

    return {
        "is_dating_active": len(missing_dating) == 0,
        "is_friends_active": len(missing_friends) == 0,
        "is_professional_active": len(missing_prof) == 0,
    }


_calculate_activation_statuses = calculate_activation_statuses
