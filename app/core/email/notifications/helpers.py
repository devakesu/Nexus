from typing import Any, cast


def short_report_id(report_id: str) -> str:
    """Short report id.

        Args:
            report_id: Input report id parameter.

        Returns:
            str: Response payload or result."""
    return report_id.split("-")[0].upper()


def extract_user_name(email: str, auth_user: dict[str, Any] | None = None) -> str:
    """
    Tries to extract the name of the user from auth_user metadata, or falls back to
    formatting the prefix of their email address.
    """
    if auth_user:
        metadata = auth_user.get("user_metadata")
        if isinstance(metadata, dict):
            metadata_dict: dict[str, Any] = cast(dict[str, Any], metadata)
            for key in ("name", "full_name", "given_name", "display_name"):
                name_val = metadata_dict.get(key)
                if isinstance(name_val, str) and name_val.strip():
                    return name_val.strip()

    if email and "@" in email:
        prefix = email.split("@")[0]
        parts = [
            p.capitalize()
            for p in prefix.replace(".", " ")
            .replace("_", " ")
            .replace("-", " ")
            .split()
        ]
        if parts:
            return " ".join(parts)
    return "User"
