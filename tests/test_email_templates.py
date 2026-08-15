import html
from unittest.mock import AsyncMock, patch

import pytest

from app.core.email.config import ProviderResult
from app.core.email.notifications.feedback import (
    send_feedback_admin_notification_email,
    send_feedback_closed_admin_notification_email,
    send_feedback_comment_admin_notification_email,
    send_feedback_confirmation_email,
)
from app.core.email.notifications.helpers import extract_user_name, short_report_id
from app.core.email.notifications.safety import send_trusted_contact_removed_email
from app.core.email.notifications.welcome import send_bootstrap_welcome_email
from app.core.email.templates import render_cta_button_row, render_email_template


def test_render_email_template_escapes_headers() -> None:
    subject = "<script>alert('XSS')</script> Hello"
    preheader_cat = "<img src=x onerror=alert(1)>"
    preheader_act = "ACT & <TEST>"

    rendered = render_email_template(
        rows_html="<tr><td>Content</td></tr>",
        subject=subject,
        preheader_category=preheader_cat,
        preheader_action=preheader_act,
    )

    assert "<script>" not in rendered
    assert html.escape(subject) in rendered
    assert "<img src=x" not in rendered
    assert html.escape(preheader_cat) in rendered
    assert html.escape(preheader_act) in rendered


def test_render_cta_button_row_escapes_text_and_url() -> None:
    cta_text = "<Click & Win!>"
    cta_url = 'https://example.com/login?foo="><script>'

    rendered = render_cta_button_row(cta_text=cta_text, cta_url=cta_url)

    assert "<Click & Win!>" not in rendered
    assert html.escape(cta_text) in rendered
    assert 'href="https://example.com/login?foo=&quot;&gt;&lt;script&gt;"' in rendered


def test_extract_user_name_sanitizes_html() -> None:
    # Metadata with malicious HTML
    user_with_xss = {
        "user_metadata": {
            "name": "<script>alert(1)</script>John",
        },
    }
    extracted = extract_user_name("john@example.com", user_with_xss)
    assert "<script>" not in extracted
    assert extracted == "&lt;script&gt;alert(1)&lt;/script&gt;John"

    # Email prefix with special characters
    extracted_email = extract_user_name("<test>@example.com", None)
    assert "<" not in extracted_email
    assert "&lt;test&gt;" in extracted_email


def test_short_report_id_escapes_html() -> None:
    malicious_id = "<script>-1234"
    assert short_report_id(malicious_id) == "&lt;SCRIPT&gt;"


@pytest.mark.anyio
async def test_welcome_email_escapes_user_name() -> None:
    mock_send = AsyncMock(return_value=ProviderResult(success=True, provider="Brevo"))
    with patch("app.core.email.send_email", mock_send):
        auth_user = {"user_metadata": {"name": "<b>Attacker</b>"}}
        result = await send_bootstrap_welcome_email("test@example.com", auth_user)
        assert result.success is True

        props = mock_send.call_args[0][0]
        assert "<b>Attacker</b>" not in props.html
        assert "&lt;b&gt;Attacker&lt;/b&gt;" in props.html


@pytest.mark.anyio
async def test_feedback_confirmation_escapes_subject() -> None:
    mock_send = AsyncMock(return_value=ProviderResult(success=True, provider="Brevo"))
    with patch("app.core.email.send_email", mock_send):
        result = await send_feedback_confirmation_email(
            email="user@example.com",
            query_type="bug_report",
            subject="<img src=x onerror=alert(1)>",
            report_id="rep-12345",
            auth_user={"user_metadata": {"name": "Normal User"}},
        )
        assert result.success is True
        props = mock_send.call_args[0][0]
        assert "<img src=x" not in props.html
        assert "&lt;img src=x onerror=alert(1)&gt;" in props.html


@pytest.mark.anyio
async def test_feedback_admin_notification_escapes_user_input() -> None:
    mock_send = AsyncMock(return_value=ProviderResult(success=True, provider="Brevo"))
    with patch("app.core.email.send_email", mock_send):
        result = await send_feedback_admin_notification_email(
            report_id="rep-12345",
            query_type="help",
            subject="<script>evil</script>",
            message="Line 1\n<script>alert(2)</script>",
            user_id="<bad_user_id>",
            submitter_email="hacker@example.com",
            submitter_name="<Hacker>",
            account_id_or_phone="<12345>",
            platform="<Android>",
            app_version="<v1.0>",
            attachment_names=["<evil.png>"],
        )
        assert result.success is True
        props = mock_send.call_args[0][0]
        assert "<script>" not in props.html
        assert "<bad_user_id>" not in props.html
        assert "<Hacker>" not in props.html
        assert "<evil.png>" not in props.html
        assert "&lt;script&gt;evil&lt;/script&gt;" in props.html
        assert "&lt;bad_user_id&gt;" in props.html
        assert "&lt;Hacker&gt;" in props.html
        assert "&lt;evil.png&gt;" in props.html


@pytest.mark.anyio
async def test_feedback_comment_and_closed_notifications_escape_input() -> None:
    mock_send = AsyncMock(return_value=ProviderResult(success=True, provider="Brevo"))
    with patch("app.core.email.send_email", mock_send):
        # Test comment notification
        res_comment = await send_feedback_comment_admin_notification_email(
            report_id="rep-comment",
            query_type="feedback",
            subject="<script>subj</script>",
            comment_body="<script>comment</script>",
            user_id="<user_123>",
            submitter_email="user@example.com",
        )
        assert res_comment.success is True
        props_comment = mock_send.call_args[0][0]
        assert "<script>" not in props_comment.html
        assert "&lt;script&gt;subj&lt;/script&gt;" in props_comment.html
        assert "&lt;script&gt;comment&lt;/script&gt;" in props_comment.html

        # Test closed notification
        res_closed = await send_feedback_closed_admin_notification_email(
            report_id="rep-closed",
            query_type="bug_report",
            subject="<script>closed_subj</script>",
            reason="<script>fixed</script>",
            user_id="<user_456>",
            submitter_email="user@example.com",
        )
        assert res_closed.success is True
        props_closed = mock_send.call_args[0][0]
        assert "<script>" not in props_closed.html
        assert "&lt;script&gt;closed_subj&lt;/script&gt;" in props_closed.html
        assert "&lt;script&gt;fixed&lt;/script&gt;" in props_closed.html


@pytest.mark.anyio
async def test_trusted_contact_removed_escapes_names() -> None:
    mock_send = AsyncMock(return_value=ProviderResult(success=True, provider="Brevo"))
    with patch("app.core.email.send_email", mock_send):
        result = await send_trusted_contact_removed_email(
            email="victim@example.com",
            user_name="<Alice>",
            contact_name="<Bob>",
        )
        assert result.success is True
        props = mock_send.call_args[0][0]
        assert "<Alice>" not in props.html
        assert "<Bob>" not in props.html
        assert "&lt;Alice&gt;" in props.html
        assert "&lt;Bob&gt;" in props.html
