"""Email provider send implementations and failover logic.

Contains the SendPulse and Brevo send implementations, provider selection,
and failover execution logic.
"""

import base64
import logging
from typing import Any, Literal

import httpx
import sentry_sdk

from app.core.config import settings
from app.core.email.config import (
    ProviderFn,
    ProviderResult,
    ProvidersConfig,
    SendEmailProps,
    get_sender_email,
    get_sender_name,
    has_brevo,
    has_sendpulse,
    redact,
    should_use_sendpulse,
    strip_tags,
)

logger = logging.getLogger(__name__)


async def get_sendpulse_token() -> str:
    """Executes get sendpulse token operation.

        Returns:
            str: Response payload or result."""
    if not has_sendpulse:
        raise ValueError("SendPulse credentials not configured")

    auth_url = "https://api.sendpulse.com/oauth/access_token"
    payload = {
        "grant_type": "client_credentials",
        "client_id": settings.sendpulse_client_id,
        "client_secret": settings.sendpulse_client_secret,
    }

    async with httpx.AsyncClient() as client:
        try:
            res = await client.post(auth_url, json=payload, timeout=10.0)
            if res.status_code != 200:
                raise httpx.HTTPStatusError(
                    f"SendPulse auth HTTP {res.status_code}",
                    request=res.request,
                    response=res,
                )
            data = res.json()
            return data["access_token"]
        except Exception as error:
            wrapped = RuntimeError(f"SendPulse Auth Failed: {error!s}")
            raise wrapped from error


async def send_via_sendpulse(props: SendEmailProps) -> ProviderResult:
    """Executes send via sendpulse operation.

        Args:
            props: Input props parameter.

        Returns:
            ProviderResult: Response payload or result."""
    if not has_sendpulse:
        raise ValueError("SendPulse not configured")

    token = await get_sendpulse_token()
    email_url = "https://api.sendpulse.com/smtp/emails"

    stripped_text = props.text or strip_tags(props.html)
    sender_email = props.sender_email or get_sender_email()
    sender_name = get_sender_name(props.from_name)

    html_base64 = base64.b64encode(props.html.encode("utf-8")).decode("utf-8")

    payload = {
        "email": {
            "html": html_base64,
            "text": stripped_text,
            "subject": props.subject,
            "from": {
                "email": sender_email,
                "name": sender_name,
            },
            "to": [
                {
                    "email": props.to,
                    "name": props.to_name or "User",
                },
            ],
        },
    }

    if props.reply_to:
        payload["email"]["reply_to"] = {"email": props.reply_to}

    async with httpx.AsyncClient() as client:
        res = await client.post(
            email_url,
            json=payload,
            headers={"Authorization": f"Bearer {token}"},
            timeout=15.0,
        )
        if res.status_code != 200:
            try:
                err_data = res.json()
                err_msg = err_data.get(
                    "message",
                    f"SendPulse error: {res.status_code}",
                )
            except Exception:  # noqa: BLE001
                err_msg = f"SendPulse error: {res.status_code}"
            raise RuntimeError(err_msg)

        try:
            data = res.json()
            message_id = str(data.get("id", ""))
        except Exception:  # noqa: BLE001
            message_id = ""

        return ProviderResult(success=True, provider="SendPulse", id=message_id)


async def send_via_brevo(props: SendEmailProps) -> ProviderResult:
    """Executes send via brevo operation.

        Args:
            props: Input props parameter.

        Returns:
            ProviderResult: Response payload or result."""
    if not has_brevo:
        raise ValueError("Brevo not configured")

    url = "https://api.brevo.com/v3/smtp/email"
    sender_email = props.sender_email or get_sender_email()
    sender_name = get_sender_name(props.from_name)
    stripped_text = props.text or strip_tags(props.html)

    payload: dict[str, Any] = {
        "sender": {
            "email": sender_email,
            "name": sender_name,
        },
        "to": [{"email": props.to}],
        "subject": props.subject,
        "htmlContent": props.html,
        "textContent": stripped_text,
    }

    if props.to_name:
        payload["to"][0]["name"] = props.to_name

    if props.reply_to:
        payload["replyTo"] = {"email": props.reply_to}

    async with httpx.AsyncClient() as client:
        res = await client.post(
            url,
            json=payload,
            headers={
                "api-key": settings.brevo_api_key or "",
                "content-type": "application/json",
                "accept": "application/json",
            },
            timeout=15.0,
        )
        if res.status_code not in (200, 201, 202):
            try:
                err_data = res.json()
                err_msg = err_data.get(
                    "message",
                    f"Brevo error: {res.status_code}",
                )
            except Exception:  # noqa: BLE001
                err_msg = f"Brevo error: {res.status_code}"
            raise RuntimeError(err_msg)

        try:
            data = res.json()
            message_id = str(data.get("messageId", ""))
        except Exception:  # noqa: BLE001
            message_id = ""

        return ProviderResult(success=True, provider="Brevo", id=message_id)


def get_providers(use_sp: bool) -> ProvidersConfig:
    """Executes get providers operation.

        Args:
            use_sp: Input use sp parameter.

        Returns:
            ProvidersConfig: Response payload or result."""
    if use_sp:
        return ProvidersConfig(
            primary=send_via_sendpulse,
            secondary=send_via_brevo if has_brevo else None,
            p_name="SendPulse",
            s_name="Brevo",
        )
    return ProvidersConfig(
        primary=send_via_brevo,
        secondary=send_via_sendpulse if has_sendpulse else None,
        p_name="Brevo",
        s_name="SendPulse",
    )


async def execute_failover(
    secondary: ProviderFn,
    props: SendEmailProps,
    s_name: Literal["Brevo", "SendPulse"],
    err: Exception,
) -> ProviderResult:
    """Executes execute failover operation.

        Args:
            secondary: Input secondary parameter.
            props: Input props parameter.
            s_name: Input s name parameter.
            err: Input err parameter.

        Returns:
            ProviderResult: Response payload or result."""
    err_msg = str(err)
    try:
        return await secondary(props)
    except Exception as err2:  # noqa: BLE001
        err2_msg = str(err2)
        msg = f"All providers failed. P: {err_msg} | S: {err2_msg}"
        logger.error(msg)
        sentry_sdk.capture_exception(
            err2,
            tags={"type": "email_critical"},
            extras={
                "to": redact("email", props.to),
                "primary_error": err_msg,
                "secondary_error": err2_msg,
            },
        )
        return ProviderResult(success=False, provider=s_name, error=msg)


async def send_email(props: SendEmailProps) -> ProviderResult:
    """Executes send email operation.

        Args:
            props: Input props parameter.

        Returns:
            ProviderResult: Response payload or result."""
    if not has_brevo and not has_sendpulse:
        err = RuntimeError("No provider configured")
        sentry_sdk.capture_exception(err, tags={"location": "send_email"})
        raise err

    use_sp = should_use_sendpulse(props.to)
    config = get_providers(use_sp)

    try:
        return await config.primary(props)
    except Exception as err:
        err_msg = str(err)
        logger.warning(
            f"{config.p_name} failed: {err_msg}",
            exc_info=True,
        )
        sentry_sdk.capture_message(
            f"Failover: {config.p_name} failed",
            level="warning",
            tags={"provider": config.p_name, "location": "send_email"},
        )

        if config.secondary:
            return await execute_failover(
                config.secondary,
                props,
                config.s_name,
                err,
            )
        return ProviderResult(success=False, provider=config.p_name, error=err_msg)
