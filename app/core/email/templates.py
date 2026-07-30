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
      background-color: #050510;
      color: #FFFFFF;
      font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif;
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
      font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif;
    }}

    .body-wrapper {{
      background: #050510 radial-gradient(ellipse at center, #1b2735 0%, #080a18 50%, #03030a 100%);
      position: relative;
      overflow: hidden;
    }}
    
    /* Dense Multi-Layer Starfield */
    .stars-bg {{
      position: absolute;
      top: 0; left: 0; right: 0; bottom: 0;
      background-image:
        radial-gradient(2px 2px at 20px 30px, #ffffff, rgba(0,0,0,0)),
        radial-gradient(2px 2px at 80px 170px, #e0e0ff, rgba(0,0,0,0)),
        radial-gradient(1.5px 1.5px at 150px 60px, #ffffff, rgba(0,0,0,0)),
        radial-gradient(3px 3px at 250px 190px, #d4d4ff, rgba(0,0,0,0)),
        radial-gradient(2px 2px at 340px 110px, #ffffff, rgba(0,0,0,0)),
        radial-gradient(2px 2px at 90px 340px, #4ecca3, rgba(0,0,0,0)),
        radial-gradient(2.5px 2.5px at 420px 220px, #60a5fa, rgba(0,0,0,0)),
        radial-gradient(2px 2px at 490px 80px, #a78bfa, rgba(0,0,0,0)),
        radial-gradient(1.5px 1.5px at 530px 310px, #ffffff, rgba(0,0,0,0)),
        radial-gradient(2px 2px at 30px 280px, #cbd5e1, rgba(0,0,0,0));
      background-repeat: repeat;
      background-size: 550px 550px;
      animation: twinkle 6s infinite alternate;
      z-index: 1;
    }}

    /* Constellation Vector Lines SVG Pattern */
    .constellations-bg {{
      position: absolute;
      top: 0; left: 0; right: 0; bottom: 0;
      background-image: url("data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' width='400' height='400' viewBox='0 0 400 400'%3E%3Cg fill='none' stroke='rgba(255, 255, 255, 0.12)' stroke-width='0.75'%3E%3C!-- Ursa Major --%3E%3Cpath d='M30 40 L70 55 L110 50 L140 80 L180 110 L160 140 L120 130 Z'/%3E%3C!-- Orion --%3E%3Cpath d='M280 220 L310 200 L340 220 L320 260 L290 260 Z M300 235 L320 235 L330 235'/%3E%3C!-- Cassiopeia --%3E%3Cpath d='M220 30 L245 50 L270 35 L300 60 L330 40'/%3E%3C!-- Pegasus Triangle --%3E%3Cpath d='M60 260 L120 230 L100 310 Z' stroke-dasharray='2,2'/%3E%3C/g%3E%3Cg fill='%23ffffff' opacity='0.7'%3E%3Ccircle cx='30' cy='40' r='2'/%3E%3Ccircle cx='70' cy='55' r='1.5'/%3E%3Ccircle cx='110' cy='50' r='2'/%3E%3Ccircle cx='140' cy='80' r='2.5'/%3E%3Ccircle cx='180' cy='110' r='2'/%3E%3Ccircle cx='160' cy='140' r='1.5'/%3E%3Ccircle cx='120' cy='130' r='2'/%3E%3Ccircle cx='280' cy='220' r='2'/%3E%3Ccircle cx='310' cy='200' r='2'/%3E%3Ccircle cx='340' cy='220' r='2.5'/%3E%3Ccircle cx='320' cy='260' r='1.5'/%3E%3Ccircle cx='290' cy='260' r='2'/%3E%3Ccircle cx='220' cy='30' r='2'/%3E%3Ccircle cx='245' cy='50' r='1.5'/%3E%3Ccircle cx='270' cy='35' r='2'/%3E%3Ccircle cx='300' cy='60' r='2'/%3E%3Ccircle cx='330' cy='40' r='2.5'/%3E%3Ccircle cx='60' cy='260' r='2'/%3E%3Ccircle cx='120' cy='230' r='1.5'/%3E%3Ccircle cx='100' cy='310' r='2'/%3E%3C/g%3E%3C/svg%3E");
      background-repeat: repeat;
      background-size: 400px 400px;
      opacity: 0.85;
      z-index: 2;
    }}

    /* Animated Comets */
    .comet {{
      position: absolute;
      top: -50px;
      left: 75%;
      width: 4px;
      height: 4px;
      background: #ffffff;
      border-radius: 50%;
      box-shadow: 0 0 15px 4px #ffffff, 0 0 30px 8px #60a5fa;
      animation: comet-fall-1 7s infinite linear;
      z-index: 3;
    }}
    .comet::before {{
      content: '';
      position: absolute;
      top: 50%;
      right: 100%;
      width: 140px;
      height: 1.5px;
      background: linear-gradient(to right, rgba(255,255,255,0), rgba(255,255,255,0.9), rgba(96,165,250,1));
      transform: translateY(-50%);
    }}

    .comet-2 {{
      position: absolute;
      top: -50px;
      left: 35%;
      width: 3px;
      height: 3px;
      background: #ffffff;
      border-radius: 50%;
      box-shadow: 0 0 12px 3px #ffffff, 0 0 25px 6px #4ecca3;
      animation: comet-fall-2 11s infinite linear 3.5s;
      z-index: 3;
    }}
    .comet-2::before {{
      content: '';
      position: absolute;
      top: 50%;
      right: 100%;
      width: 110px;
      height: 1px;
      background: linear-gradient(to right, rgba(255,255,255,0), rgba(78,204,163,0.9), rgba(255,255,255,1));
      transform: translateY(-50%);
    }}

    .comet-3 {{
      position: absolute;
      top: -50px;
      left: 90%;
      width: 3px;
      height: 3px;
      background: #ffffff;
      border-radius: 50%;
      box-shadow: 0 0 10px 3px #ffffff, 0 0 20px 5px #a78bfa;
      animation: comet-fall-3 9s infinite linear 6s;
      z-index: 3;
    }}
    .comet-3::before {{
      content: '';
      position: absolute;
      top: 50%;
      right: 100%;
      width: 90px;
      height: 1px;
      background: linear-gradient(to right, rgba(255,255,255,0), rgba(167,139,250,0.9), rgba(255,255,255,1));
      transform: translateY(-50%);
    }}

    .main-card {{
      position: relative;
      z-index: 10;
      /* Made slightly transparent so the universe bleeds through */
      background-color: rgba(13, 14, 18, 0.85) !important;
      backdrop-filter: blur(10px);
    }}

    @keyframes twinkle {{
      0% {{ opacity: 0.35; transform: scale(0.98); }}
      50% {{ opacity: 0.85; transform: scale(1); }}
      100% {{ opacity: 1; transform: scale(1.02); }}
    }}
    
    @keyframes comet-fall-1 {{
      0% {{ transform: translate(0, 0) rotate(45deg); opacity: 1; }}
      70% {{ opacity: 1; }}
      100% {{ transform: translate(-1100px, 1100px) rotate(45deg); opacity: 0; }}
    }}

    @keyframes comet-fall-2 {{
      0% {{ transform: translate(0, 0) rotate(50deg); opacity: 1; }}
      70% {{ opacity: 1; }}
      100% {{ transform: translate(-900px, 900px) rotate(50deg); opacity: 0; }}
    }}

    @keyframes comet-fall-3 {{
      0% {{ transform: translate(0, 0) rotate(40deg); opacity: 1; }}
      70% {{ opacity: 1; }}
      100% {{ transform: translate(-850px, 850px) rotate(40deg); opacity: 0; }}
    }}

    @media (prefers-color-scheme: dark) {{
      .body-wrapper {{ background-color: #050510 !important; }}
    }}
  </style>
</head>
<body style="margin: 0; padding: 0; background-color: #050510; color: #FFFFFF;">

  <table width="100%" border="0" cellspacing="0" cellpadding="0"
         class="body-wrapper" style="background-color: #050510; table-layout: fixed;">
    <tr>
      <td align="center" style="padding: 40px 16px 60px 16px; position: relative;">
        
        <div class="stars-bg"></div>
        <div class="constellations-bg"></div>
        <div class="comet"></div>
        <div class="comet-2"></div>
        <div class="comet-3"></div>

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
