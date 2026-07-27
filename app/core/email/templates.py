"""Email HTML template renderers.

Provides the core branded Nexus email wrapper template and CTA button row helper.
"""

from app.core.config import settings


def render_email_template(
    rows_html: str,
    subject: str,
    preheader_category: str = "SYSTEM",
    preheader_action: str = "VERIFIED",
    footer_html: str | None = None,
) -> str:
    """Renders a unified HTML wrapper using standard Nexus branding.

        Args:
            rows_html: Input rows html parameter.
            subject: Input subject parameter.
            preheader_category: Input preheader category parameter.
            preheader_action: Input preheader action parameter.
            footer_html: Input footer html parameter.

        Returns:
            str: Response payload or result."""
    app_domain = settings.app_domain
    email_domain = settings.email_domain
    if footer_html is None:
        footer_html = f"""
              You are receiving this mandatory service-related communication
              because a Nexus account was created using this
              email address. If you did not initiate this action, please contact
              support at <a href="mailto:support@{email_domain}" style="color: pink;">
              support@{email_domain}</a>
              <br>
              <a href="https://{app_domain}/legal" target="_blank"
                 style="color: white">Privacy, Terms &amp; Legal</a>
        """
    footer_row = (
        f"""
          <tr>
            <td style="padding: 24px 32px; background-color: #0A0B0E;
                       border-top: 1px solid #1A1C20;
                       font-family: ui-monospace, SFMono-Regular,
                       Menlo, Monaco, Consolas, monospace;
                       font-size: 10px; color: white; line-height: 1.5;
                       text-align: center;">
              {footer_html}
            </td>
          </tr>
        """
        if footer_html.strip()
        else ""
    )
    return f"""<!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.0 Transitional//EN" "http://www.w3.org/TR/xhtml1/DTD/xhtml1-transitional.dtd">
<html xmlns="http://www.w3.org/1999/xhtml" lang="en">
<head>
  <meta http-equiv="Content-Type" content="text/html; charset=UTF-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1.0"/>
  <title>{subject}</title>
  <style type="text/css">
    body {{
      margin: 0;
      padding: 0;
      min-width: 100%;
      -webkit-text-size-adjust: 100%;
      -ms-text-size-adjust: 100%;
      background-color: #0B0C10;
      color: #FFFFFF;
      font-family: -apple-system, BlinkMacSystemFont,
        "Segoe UI", Roboto, Helvetica, Arial, sans-serif;
    }}
    img {{
      line-height: 100%;
      outline: none;
      text-decoration: none;
      -ms-interpolation-mode: bicubic;
      border: 0;
    }}
    table {{
      border-collapse: collapse !important;
      mso-table-lspace: 0pt;
      mso-table-rspace: 0pt;
    }}
    td {{
      font-family: -apple-system, BlinkMacSystemFont,
        "Segoe UI", Roboto, Helvetica, Arial, sans-serif;
    }}

    /* Reveal real dark mode properties for compliant clients */
    @media (prefers-color-scheme: dark) {{
      .body-wrapper {{ background-color: #0B0C10 !important; }}
      .main-card {{ background-color: #0D0E12 !important; }}
    }}
  </style>
</head>
<body style="margin: 0; padding: 0; background-color: #0B0C10; color: #FFFFFF;">

  <table width="100%" border="0" cellspacing="0" cellpadding="0"
         class="body-wrapper" style="background-color: #0B0C10; table-layout: fixed;">
    <tr>
      <td align="center" style="padding: 40px 16px 60px 16px;">

        <table width="100%" border="0" cellspacing="0" cellpadding="0"
               class="main-card" style="max-width: 580px; background-color: #0D0E12;
               border: 1px solid #22252A; text-align: left;">

          <tr>
            <td style="padding: 16px 24px; border-bottom: 1px solid #22252A;
                       font-family: ui-monospace, SFMono-Regular,
                       Menlo, Monaco, Consolas, 'Liberation Mono',
                       'Courier New', monospace; font-size: 11px;
                       color: #6B7280; letter-spacing: 0.05em;">
              [ {preheader_category}: // {preheader_action} ]
            </td>
          </tr>

          {rows_html}

          {footer_row}
        </table>

      </td>
    </tr>
  </table>

</body>
</html>
"""


def render_cta_button_row(cta_text: str, cta_url: str) -> str:
    """
    Renders a standard CTA button row.
    """
    return f"""
          <tr>
            <td align="center" style="padding: 0 32px 48px 32px;">
              <table border="0" cellspacing="0" cellpadding="0" width="100%">
                <tr>
                  <td align="center">
                    <a href="{cta_url}" target="_blank"
                       style="display: block; width: 100%; max-width: 280px;
                       background-color: #00ADB5; border: 1px solid #00ADB5;
                       color: #FFFFFF; font-family: -apple-system,
                       BlinkMacSystemFont, sans-serif; font-size: 13px;
                       font-weight: 600; letter-spacing: 0.08em;
                       text-transform: uppercase; text-decoration: none;
                       padding: 15px 0; text-align: center;
                       transition: background-color 0.2s, border-color 0.2s;">
                      {cta_text}
                    </a>
                  </td>
                </tr>
              </table>
            </td>
          </tr>
    """
