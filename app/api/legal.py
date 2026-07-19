import logging

from fastapi import APIRouter, Request
from fastapi.responses import HTMLResponse, RedirectResponse

from app.core.config import settings
from app.core.limiter import limiter

logger = logging.getLogger(__name__)

router = APIRouter()


def _field_or(value: str | None, missing_label: str) -> str:
    """Renders a real config value verbatim, or a visibly-flagged
    placeholder chip if it hasn't been set yet - so this page ships honest
    about what's still outstanding rather than silently printing nothing.
    """
    if value:
        return value
    return f'<span class="field">{missing_label}</span>'


def _placeholder_banner(missing: list[str]) -> str:
    """Only rendered when something is actually still unset - once every
    launch-readiness value below has a real value, this whole block
    disappears from the page on its own, no manual edit needed.
    """
    if not missing:
        return ""
    items = "; ".join(missing)
    return f"""
    <div class="placeholder-banner">
      <span class="tag">Before publish</span>
      <span>Still needs a real value: {items}.</span>
    </div>
    """


def render_legal_page() -> str:
    """Builds the combined Terms of Service + Privacy Policy page served at
    /legal and /legal/privacy (see routes below). Single template,
    single source of truth - the two routes render the exact same HTML and
    differ only in which section the browser lands on, via URL fragment.
    Interpolates live settings (grievance officer contact, app domain,
    terms version, governing-law city, effective date) so this page never
    drifts from what the backend/app actually enforce.
    """
    domain = settings.app_domain
    terms_version = settings.current_terms_version.strip()

    missing: list[str] = []
    if not settings.legal_effective_date:
        missing.append("effective date (LEGAL_EFFECTIVE_DATE)")
    if not settings.legal_governing_law_city:
        missing.append("governing-law city (LEGAL_GOVERNING_LAW_CITY)")
    if not settings.grievance_officer_name:
        missing.append(
            "Grievance Officer name/contact (grievance_officer_* settings)",
        )

    html = _LEGAL_PAGE_TEMPLATE
    html = html.replace("__DOMAIN__", domain)
    html = html.replace("__TERMS_VERSION__", terms_version)
    html = html.replace(
        "__EFFECTIVE_DATE__",
        _field_or(settings.legal_effective_date, "not yet set"),
    )
    html = html.replace(
        "__CITY__",
        _field_or(settings.legal_governing_law_city, "not yet set"),
    )
    html = html.replace(
        "__GRIEVANCE_NAME__",
        _field_or(settings.grievance_officer_name, "not yet designated"),
    )
    html = html.replace(
        "__GRIEVANCE_EMAIL__",
        _field_or(settings.grievance_officer_email, "not yet set"),
    )
    html = html.replace(
        "__GRIEVANCE_PHONE__",
        _field_or(settings.grievance_officer_phone, "not yet set"),
    )
    html = html.replace(
        "__GRIEVANCE_WEBSITE__",
        _field_or(settings.grievance_officer_website, "not yet set"),
    )
    return html.replace("__PLACEHOLDER_BANNER__", _placeholder_banner(missing))


@router.get("/legal")
@limiter.limit(settings.rate_limit_health)
def legal_terms_page(request: Request) -> HTMLResponse:
    """Public, unauthenticated - reachable before signup/login, and this is
    the URL the Flutter app's WebView (legal_terms_page.dart) points at, so
    the in-app copy and the web copy are always the exact same render.
    Not under /api/v1 (unlike every other route in this backend) -
    deliberately a clean, human-browsable path suitable for app-store
    Terms/Privacy URL fields.
    """
    _ = request
    return HTMLResponse(render_legal_page())


@router.get("/legal/privacy")
@limiter.limit(settings.rate_limit_health)
def legal_privacy_page(request: Request) -> RedirectResponse:
    """Privacy Policy gets its own canonical URL (app-store submission forms
    ask for one specifically), but there's exactly one document, not two -
    this redirects into the same page served by legal_terms_page, landing
    on the Privacy Policy section via URL fragment instead of duplicating
    the content.
    """
    _ = request
    return RedirectResponse(url="/legal#privacy", status_code=302)


_LEGAL_PAGE_TEMPLATE = r"""<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Nexus - Terms of Service &amp; Privacy Policy</title>
<style>
  :root {
    --ink: #0F172A;
    --ink-muted: #64748B;
    --ink-faint: #94A3B8;
    --border: #E2E8F0;
    --surface: #FFFFFF;
    --canvas: #F4F6FA;
    --pink: #FF7597;
    --pink-soft: #FF759714;
    --teal: #0891B2;
    --teal-soft: #0891B214;
    --safety-blue: #0284C7;
    --safety-teal: #0D9488;
    --safety-soft: #0284C712;
    --warn: #F59E0B;
    --warn-soft: #F59E0B14;
    --error: #EF4444;
    --error-soft: #EF444414;
    --shadow: 0 1px 2px rgba(15,23,42,.04), 0 10px 28px -14px rgba(15,23,42,.14);
    color-scheme: light;
  }
  @media (prefers-color-scheme: dark) {
    :root {
      --ink: #EDEFF4; --ink-muted: #9AA3B5; --ink-faint: #6B7385;
      --border: #232838; --surface: #161B26; --canvas: #0B0D13;
      --pink: #FF89A5; --pink-soft: #FF89A51c; --teal: #4FD1E0; --teal-soft: #4FD1E01c;
      --safety-blue: #5EC2F0; --safety-teal: #5EEAD4; --safety-soft: #5EC2F01c;
      --warn: #FBBF24; --warn-soft: #FBBF241c; --error: #F87171; --error-soft: #F871711c;
      color-scheme: dark;
    }
  }
  * { box-sizing: border-box; }
  html, body { margin: 0; padding: 0; }
  body {
    background: var(--canvas); color: var(--ink);
    font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", "Helvetica Neue", Arial, sans-serif;
    font-size: 16px; line-height: 1.65; -webkit-font-smoothing: antialiased;
  }
  ::selection { background: var(--pink-soft); }
  a { color: var(--teal); text-decoration-thickness: 1px; text-underline-offset: 2px; }
  a:focus-visible, button:focus-visible, summary:focus-visible { outline: 2px solid var(--teal); outline-offset: 2px; border-radius: 3px; }
  h1, h2, h3 { font-family: "Iowan Old Style", "Palatino Linotype", Georgia, serif; font-weight: 600; text-wrap: balance; color: var(--ink); }
  code, .mono { font-family: "SF Mono", "JetBrains Mono", Consolas, monospace; font-size: 0.85em; background: var(--canvas); border: 1px solid var(--border); border-radius: 3px; padding: 0.05em 0.4em; }

  .wrap { max-width: 1160px; margin: 0 auto; padding: 0 28px 100px; }

  header.masthead { border-bottom: 1px solid var(--border); background: var(--surface); }
  .masthead-inner { max-width: 1160px; margin: 0 auto; padding: 44px 28px 30px; display: flex; flex-direction: column; gap: 12px; }
  .eyebrow { font-family: "SF Mono", monospace; font-size: 0.72rem; letter-spacing: .12em; text-transform: uppercase; color: var(--pink); font-weight: 700; }
  .eyebrow-links { font-family: "SF Mono", monospace; font-size: 0.72rem; }
  .eyebrow-links a { color: var(--ink-muted); }
  h1.title { font-size: 2.1rem; line-height: 1.15; margin: 0; max-width: 26ch; }
  .subtitle { color: var(--ink-muted); font-size: 1.02rem; max-width: 68ch; margin: 0; }
  .meta-row { display: flex; flex-wrap: wrap; gap: 8px 20px; margin-top: 4px; font-size: 0.84rem; color: var(--ink-muted); }
  .meta-row strong { color: var(--ink); font-weight: 600; }
  .placeholder-banner {
    margin-top: 16px; display: flex; gap: 10px; align-items: flex-start;
    background: var(--warn-soft); border: 1px solid var(--warn); border-radius: 8px; padding: 12px 16px; font-size: 0.86rem;
  }
  .placeholder-banner .tag { font-weight: 800; color: var(--warn); flex: none; font-family: "SF Mono", monospace; font-size: 0.7rem; letter-spacing: .05em; text-transform: uppercase; padding-top: 2px; }

  .layout { display: grid; grid-template-columns: 240px minmax(0,1fr); gap: 56px; margin-top: 40px; }
  @media (max-width: 900px) { .layout { grid-template-columns: 1fr; } .toc { position: static !important; order: 2; } }
  nav.toc { position: sticky; top: 24px; align-self: start; font-size: 0.85rem; display: flex; flex-direction: column; gap: 14px; max-height: calc(100vh - 48px); overflow-y: auto; }
  nav.toc .toc-group { border-left: 2px solid var(--border); padding-left: 14px; display: flex; flex-direction: column; gap: 7px; }
  nav.toc .toc-h { font-size: .72rem; text-transform: uppercase; letter-spacing: .08em; color: var(--pink); margin-bottom: 2px; font-weight: 700; }
  nav.toc a { color: var(--ink-muted); display: block; }
  nav.toc a:hover { color: var(--ink); }

  main { min-width: 0; }
  .doc-part { margin-bottom: 20px; }
  .doc-part-head { display: flex; align-items: baseline; gap: 12px; margin: 64px 0 6px; }
  .doc-part-head h2 { font-size: 1.9rem; margin: 0; }
  .doc-part-head .part-eyebrow { font-family: "SF Mono", monospace; font-size: 0.72rem; color: var(--ink-faint); letter-spacing: .08em; text-transform: uppercase; }
  .doc-part-intro { color: var(--ink-muted); max-width: 70ch; margin: 0 0 8px; font-size: 0.95rem; }

  section.clause { scroll-margin-top: 20px; margin: 28px 0; }
  section.clause h3 { font-size: 1.18rem; margin: 0 0 10px; display: flex; align-items: baseline; gap: 10px; }
  section.clause h3 .num { font-family: "SF Mono", monospace; font-size: 0.8rem; color: var(--ink-faint); font-weight: 500; }
  .prose { max-width: 72ch; font-size: 0.98rem; }
  .prose p { margin: 0 0 13px; }
  .prose ul, .prose ol { margin: 0 0 13px; padding-left: 22px; }
  .prose li { margin-bottom: 7px; }
  .prose strong { color: var(--ink); }

  .callout { border-radius: 10px; padding: 18px 20px; margin: 18px 0; font-size: 0.94rem; max-width: 72ch; box-shadow: var(--shadow); }
  .callout-head { display: flex; align-items: center; gap: 8px; font-weight: 700; margin-bottom: 8px; font-size: 0.9rem; }
  .callout-head .dot { width: 8px; height: 8px; border-radius: 50%; flex: none; }
  .callout.safety { background: var(--safety-soft); border: 1px solid var(--safety-blue); }
  .callout.safety .callout-head { color: var(--safety-blue); }
  .callout.safety .callout-head .dot { background: var(--safety-blue); }
  .callout.consent { background: var(--pink-soft); border: 1px solid var(--pink); }
  .callout.consent .callout-head { color: var(--pink); }
  .callout.consent .callout-head .dot { background: var(--pink); }
  .callout.license { background: var(--teal-soft); border: 1px solid var(--teal); }
  .callout.license .callout-head { color: var(--teal); }
  .callout.license .callout-head .dot { background: var(--teal); }
  .callout p, .callout ul { margin: 0 0 10px; }
  .callout p:last-child, .callout ul:last-child { margin-bottom: 0; }
  .callout ul { padding-left: 20px; }
  .callout li { margin-bottom: 6px; }

  .field { display: inline-block; background: var(--error-soft); border: 1px dashed var(--error); color: var(--error); border-radius: 4px; padding: 0 6px; font-family: "SF Mono", monospace; font-size: 0.82em; }

  .subproc-grid { display: grid; grid-template-columns: repeat(auto-fill, minmax(300px,1fr)); gap: 14px; margin: 18px 0; }
  .subproc-card { border: 1px solid var(--border); background: var(--surface); border-radius: 10px; padding: 16px 18px; box-shadow: var(--shadow); }
  .subproc-card h4 { margin: 0 0 8px; font-size: 0.98rem; font-family: -apple-system, sans-serif; font-weight: 700; }
  .subproc-card .row { font-size: 0.83rem; color: var(--ink-muted); margin-bottom: 5px; }
  .subproc-card .row b { color: var(--ink); font-weight: 600; }
  .subproc-card a { font-size: 0.8rem; }

  .data-table-wrap { overflow-x: auto; border: 1px solid var(--border); border-radius: 8px; margin: 16px 0; box-shadow: var(--shadow); }
  table.data-table { width: 100%; border-collapse: collapse; min-width: 560px; background: var(--surface); font-size: 0.86rem; }
  table.data-table th { text-align: left; font-size: 0.7rem; text-transform: uppercase; letter-spacing: .05em; color: var(--ink-muted); padding: 10px 14px; border-bottom: 1px solid var(--border); background: var(--canvas); }
  table.data-table td { padding: 10px 14px; border-bottom: 1px solid var(--border); vertical-align: top; }
  table.data-table tr:last-child td { border-bottom: none; }

  footer.colophon { max-width: 1160px; margin: 40px auto 0; padding: 28px 28px 60px; color: var(--ink-faint); font-size: 0.8rem; border-top: 1px solid var(--border); }
  hr.rule { border: none; border-top: 1px solid var(--border); margin: 48px 0; }
</style>
</head>
<body>

<header class="masthead">
  <div class="masthead-inner">
    <div class="eyebrow">Legal · Nexus &amp; Nexus MEC</div>
    <h1 class="title">Terms of Service &amp; Privacy Policy</h1>
    <p class="subtitle">Covers both app flavors - the general-audience <code>nexus</code> app and the campus-gated <code>nexus_mec</code> app - one backend, one privacy/security architecture. Content is derived directly from the live application code and database schema.</p>
    <div class="eyebrow-links"><a href="#terms">Jump to Terms of Service</a> &nbsp;·&nbsp; <a href="#privacy">Jump to Privacy Policy</a></div>
    <div class="meta-row">
      <span><strong>Effective date:</strong> __EFFECTIVE_DATE__</span>
      <span><strong>Terms version:</strong> __TERMS_VERSION__</span>
      <span><strong>Prepared under:</strong> India's DPDP Act 2023, with GDPR coverage where it asks for more</span>
    </div>
    __PLACEHOLDER_BANNER__
  </div>
</header>

<div class="wrap">
  <div class="layout">
    <nav class="toc" aria-label="Table of contents">
      <div class="toc-group">
        <div class="toc-h">Terms of Service</div>
        <a href="#tos-1">1. Acceptance</a>
        <a href="#tos-2">2. Eligibility</a>
        <a href="#tos-3">3. Two flavors</a>
        <a href="#tos-4">4. How you sign in</a>
        <a href="#tos-5">5. AGPLv3 license</a>
        <a href="#tos-6">6. Acceptable use</a>
        <a href="#tos-7">7. Meetup Safety disclaimer</a>
        <a href="#tos-8">8. Your content</a>
        <a href="#tos-9">9. Termination &amp; deletion</a>
        <a href="#tos-10">10. Third-party services</a>
        <a href="#tos-11">11. Warranty disclaimer</a>
        <a href="#tos-12">12. Limitation of liability</a>
        <a href="#tos-13">13. Indemnification</a>
        <a href="#tos-14">14. Changes to these terms</a>
        <a href="#tos-15">15. Governing law</a>
        <a href="#tos-16">16. Contact</a>
      </div>
      <div class="toc-group">
        <div class="toc-h">Privacy Policy</div>
        <a href="#pp-1">1. Who we are</a>
        <a href="#pp-2">2. Information we collect</a>
        <a href="#pp-3">3. What we never collect</a>
        <a href="#pp-4">4. Non-user trusted contacts</a>
        <a href="#pp-5">5. How we use your data</a>
        <a href="#pp-6">6. Consent</a>
        <a href="#pp-7">7. How we protect data</a>
        <a href="#pp-8">8. Automated matching</a>
        <a href="#pp-9">9. Sub-processors</a>
        <a href="#pp-10">10. International transfers</a>
        <a href="#pp-11">11. Retention &amp; deletion</a>
        <a href="#pp-12">12. Your rights</a>
        <a href="#pp-13">13. Children's privacy</a>
        <a href="#pp-14">14. Marketing email</a>
        <a href="#pp-15">15. Policy changes</a>
        <a href="#pp-16">16. Grievance Officer</a>
      </div>
    </nav>

    <main>
      <!-- =================== TERMS OF SERVICE =================== -->
      <div class="doc-part" id="terms">
        <div class="doc-part-head"><span class="part-eyebrow">Part One</span></div>
        <h2>Terms of Service</h2>
        <p class="doc-part-intro">Applies to the <code>nexus</code> app and the <code>nexus_mec</code> campus flavor together, unless a section says otherwise.</p>

        <section class="clause" id="tos-1">
          <h3><span class="num">1</span>Acceptance of Terms</h3>
          <div class="prose"><p>By creating an account, browsing, or otherwise using Nexus - the mobile app, its backend APIs, the trusted-contact web portal, and related services - you agree to be bound by these Terms of Service and by our <a href="#privacy">Privacy Policy</a>, incorporated by reference. If you don't agree, don't use the Service.</p></div>
        </section>

        <section class="clause" id="tos-2">
          <h3><span class="num">2</span>Eligibility</h3>
          <div class="prose">
            <p>You must be <strong>at least 18 years old</strong> to use Nexus, in either flavor. There's no upper age limit on the main <code>nexus</code> app; <code>nexus_mec</code> is additionally capped at 27, matching its campus scope. Age is <strong>self-attested</strong> at signup - a slider, not an ID check - and enforced server-side against your variant's range at every layer (API validation plus a database trigger as a backstop), but we do not verify identity or run age-estimation on photos. If you're aware of an account misrepresenting its age, report it in-app (Report → "Underage"); we act on that the same way we act on any other Trust &amp; Safety report.</p>
            <p><code>nexus_mec</code> additionally requires a verified email address on that flavor's configured campus domain - the main <code>nexus</code> app has no email-domain restriction.</p>
          </div>
        </section>

        <section class="clause" id="tos-3">
          <h3><span class="num">3</span>Two Flavors, One Service</h3>
          <div class="prose"><p><code>nexus</code> and <code>nexus_mec</code> share one backend and one privacy/security architecture. A <code>nexus_mec</code> account can generate a one-time export code to migrate into the main <code>nexus</code> app; the reverse isn't supported. Your flavor determines which age range, email-domain rule, and Spotify OAuth redirect apply - it never changes how your data is stored, encrypted, or protected.</p></div>
        </section>

        <section class="clause" id="tos-4">
          <h3><span class="num">4</span>No Passwords - How You Sign In</h3>
          <div class="prose">
            <p>Nexus has no password-based login. You sign in with <strong>Google Sign-In</strong> or a <strong>passwordless one-time email code</strong>. We never ask for, store, or have access to a password for your account.</p>
            <p><strong>A phone number is required to complete signup</strong> - the app verifies it by SMS one-time code before it will finish creating your profile. This exists specifically to make it harder to spin up large numbers of duplicate accounts off disposable email addresses alone; it is not a login credential by itself, and sign-in itself remains Google/email-OTP only.</p>
          </div>
        </section>

        <section class="clause" id="tos-5">
          <h3><span class="num">5</span>Open-Source License</h3>
          <div class="callout license">
            <div class="callout-head"><span class="dot"></span>AGPLv3 - not the more common GPL or MIT</div>
            <p>Nexus's source is free software under the <strong>GNU Affero General Public License v3</strong>, published at <a href="https://github.com/devakesu/Nexus" target="_blank" rel="noopener">github.com/devakesu/Nexus</a>.</p>
            <ul>
              <li><strong>Your freedoms:</strong> run, study, redistribute, and modify the software.</li>
              <li><strong>Copyleft, including network use:</strong> AGPLv3 closes the "hosted SaaS" loophole plain GPL leaves open - modify this software and let others use your modified version <em>over a network</em>, and you must make that modified source available to them too (AGPLv3 §13). You can't fold this code into a closed-source product, hosted or not.</li>
              <li><strong>"AS IS," no warranty:</strong> because the program is licensed free of charge, there is no warranty for the program to the extent permitted by law. It's provided without warranty of any kind, express or implied, including merchantability and fitness for a particular purpose. The entire risk as to quality and performance is with you.</li>
            </ul>
          </div>
        </section>

        <section class="clause" id="tos-6">
          <h3><span class="num">6</span>Hosted Service - Acceptable Use</h3>
          <div class="prose">
            <p>The <em>source</em> is free; using <em>our</em> hosted instance is a privilege - one that comes with real people's intimate profile data and emergency-safety information riding on it. You agree <strong>not</strong> to:</p>
            <ul>
              <li><strong>Abuse the API</strong> - script, scrape, or bot past normal usage patterns, or send more requests than a human could reasonably generate.</li>
              <li><strong>Attack device/security integrity</strong> - bypass, spoof, or reverse-engineer App Check, Play Integrity, App Attest, or any anti-abuse control.</li>
              <li><strong>Attack encryption</strong> - attempt to decrypt other users' encrypted profile fields, Signal-Protocol-encrypted chat messages (we can't read them either), or Meetup Safety evidence.</li>
              <li><strong>Weaponize Meetup Safety</strong> - file a false SOS/inform alert or harass a trusted contact through the escalation/portal flow. This notifies real people who believe someone may be in danger.</li>
              <li><strong>Evade moderation</strong> - create a new account to route around a suspension, ban, or block.</li>
              <li><strong>Harass, impersonate, or endanger</strong> other users, via profile, chat, or the discovery system.</li>
              <li><strong>Upload malware</strong> or attempt to compromise our infrastructure.</li>
              <li><strong>Misrepresent your identity, age, or campus affiliation</strong> (<code>nexus_mec</code>).</li>
            </ul>
            <p>We may suspend, restrict, or terminate access for any violation, with or without notice, per §9.</p>
          </div>
        </section>

        <section class="clause" id="tos-7">
          <h3><span class="num">7</span>Meetup Safety - Read This Before You Rely On It</h3>
          <div class="callout safety">
            <div class="callout-head"><span class="dot"></span>Not a substitute for emergency services</div>
            <p>Trusted contacts, scheduled check-ins, Silent/Loud SOS, Digital Witness recording, and the dead-man's-switch escalation are designed to make in-person meetups safer - they cannot guarantee it. You understand and agree:</p>
            <ul>
              <li><strong>We are not a security or emergency-response company.</strong> In immediate danger, call your local emergency number first. Nexus notifying a trusted contact is not the same as dispatching help, and there's no guaranteed response time.</li>
              <li><strong>Delivery isn't guaranteed.</strong> Alerts go out via SMS and depend on the contact's phone being reachable, Twilio's delivery, and network conditions outside our control.</li>
              <li><strong>Trusted contacts are not our agents.</strong> They're third parties you chose, not Nexus staff, and under no obligation to respond. You're responsible for choosing people who'll actually see and act on an alert.</li>
              <li><strong>Trusted contacts have their own rights.</strong> Each is notified once, with a link to a self-service, identity-verified portal to see who listed them and remove themselves permanently, any time. If they do, you're notified - check Safety Center for coverage gaps.</li>
              <li><strong>Digital Witness isn't forensic-grade evidence.</strong> Recordings are encrypted and time-stamped, but this is a personal-safety feature, not a chain-of-custody system - we make no representation about evidentiary admissibility.</li>
              <li><strong>Location accuracy depends on your device's</strong> GPS/network positioning at the time.</li>
            </ul>
          </div>
        </section>

        <section class="clause" id="tos-8">
          <h3><span class="num">8</span>Your Content</h3>
          <div class="prose"><p>You retain ownership of what you post. By posting it, you grant Nexus a license to store, display, and process it as needed to run the Service - e.g. showing your photo to a match, running it through discovery/matching. You're responsible for having the rights to anything you upload and for it not violating §6 or applicable law.</p></div>
        </section>

        <section class="clause" id="tos-9">
          <h3><span class="num">9</span>Suspension, Termination &amp; Account Deletion</h3>
          <div class="prose"><p>We may suspend or terminate access for a Terms violation, at our discretion, with or without notice. You may delete your own account any time from Settings → Delete Account - see Privacy Policy §11 for exactly what happens to your data, including the recoverable grace window and what's retained under a time-boxed legal hold for safety-incident records.</p></div>
        </section>

        <section class="clause" id="tos-10">
          <h3><span class="num">10</span>Third-Party Services</h3>
          <div class="prose"><p>Nexus integrates Google Sign-In, optional Spotify music-taste sync, and the other services in Privacy Policy §9. Your use of those is also subject to that provider's own terms - we're not responsible for their availability, changes, or any enforcement action against your account with them.</p></div>
        </section>

        <section class="clause" id="tos-11">
          <h3><span class="num">11</span>Disclaimer of Warranties</h3>
          <div class="prose"><p>Beyond the AGPLv3 disclaimer in §5, the hosted Service is provided "as is" and "as available." We don't guarantee discovery/matching will produce compatible matches, that the Service will be uninterrupted or error-free, or that any safety feature will prevent harm. Your use of the Service - including any decision to meet another user in person - is at your own risk and judgment.</p></div>
        </section>

        <section class="clause" id="tos-12">
          <h3><span class="num">12</span>Limitation of Liability</h3>
          <div class="prose"><p>To the maximum extent permitted by law, Nexus and its creators, maintainers, and contributors are not liable for indirect, incidental, special, consequential, or punitive damages arising from your use of the Service - including harm arising from an in-person meetup, a failed or delayed safety alert, or reliance on another user's profile information.</p></div>
        </section>

        <section class="clause" id="tos-13">
          <h3><span class="num">13</span>Indemnification</h3>
          <div class="prose"><p>You agree to defend, indemnify, and hold harmless Nexus's creators, maintainers, and contributors from claims, damages, and reasonable legal fees arising from (i) your use of the Service, (ii) your breach of these Terms, or (iii) your violation of any law or a third party's rights (including a campus's own policies, for <code>nexus_mec</code> users).</p></div>
        </section>

        <section class="clause" id="tos-14">
          <h3><span class="num">14</span>Changes to These Terms</h3>
          <div class="prose"><p>We version these Terms (current version: <code>__TERMS_VERSION__</code>). When we ship a materially updated version, you'll see a full-page re-consent screen the next time you open the app - accept the update or delete your account; there's no silent-continue path. Every acceptance and decline is logged with a timestamp, visible in your own data export.</p></div>
        </section>

        <section class="clause" id="tos-15">
          <h3><span class="num">15</span>Governing Law</h3>
          <div class="prose"><p>These Terms are governed by the laws of <strong>India</strong>, without regard to conflict-of-law principles. Disputes are subject to the exclusive jurisdiction of the courts at __CITY__, India.</p></div>
        </section>

        <section class="clause" id="tos-16">
          <h3><span class="num">16</span>Contact &amp; Grievance Officer</h3>
          <div class="prose"><p>For legal inquiries, Terms violations, or data requests: <strong>legal@__DOMAIN__</strong>. Per DPDP §13, our Grievance Officer is named in Privacy Policy §16.</p></div>
        </section>
      </div>

      <hr class="rule" />

      <!-- =================== PRIVACY POLICY =================== -->
      <div class="doc-part" id="privacy">
        <div class="doc-part-head"><span class="part-eyebrow">Part Two</span></div>
        <h2>Privacy Policy</h2>
        <p class="doc-part-intro">Prepared with reference to India's DPDP Act 2023 and, where it asks for more, GDPR. Every table/column name below is the literal name in our live database schema - this document can be checked against the code, not just trusted.</p>

        <section class="clause" id="pp-1">
          <h3><span class="num">1</span>Who We Are</h3>
          <div class="prose"><p>Nexus is a social-discovery app - browse, like, match, and chat, with real in-person meetups as the point, which is why intimate profile data and physical-safety data are both first-class here, not footnotes. Under DPDP, Nexus is the "Data Fiduciary" for the data described below; you - and, in one specific case (§4), the people you list as trusted contacts - are the "Data Principal(s)."</p></div>
        </section>

        <section class="clause" id="pp-2">
          <h3><span class="num">2</span>Information We Collect</h3>
          <div class="prose">
            <p><strong>Account &amp; identity</strong> - sign-in via Google or passwordless email OTP (never a password); a phone number, <strong>verified by SMS one-time code as part of completing signup</strong> - an anti-abuse measure so duplicate accounts can't be created off disposable emails alone, encrypted at rest and never a login credential itself; name and self-attested age (range-checked per flavor); campus year/branch/institute name on <code>nexus_mec</code> (encrypted); which flavor your account is on.</p>
          </div>

          <div class="callout consent">
            <div class="callout-head"><span class="dot"></span>Special-category data - sexual orientation &amp; religious belief (optional)</div>
            <p>Your profile can include pronouns, bio, hometown, current place, sexual orientation, gender, religious beliefs, lifestyle (drinking/smoking), children plans, partner values, interests, causes, pets, languages, tech skills, career context, on-device AI-generated aesthetic "vibe tags" (below), and up to 5 photos - every field <strong>encrypted at rest</strong>, and every one of them, including sexual orientation and religious belief, is optional and individually hideable from other users.</p>
            <p>Because GDPR names both explicitly as special-category data and DPDP expects genuinely specific consent, we ask for this category <strong>separately</strong> from general Terms acceptance - its own screen, its own checkbox. Unlike general consent, <strong>this one is optional</strong>: declining it doesn't touch your account or any other feature, it just keeps those two fields locked (no real value selectable) until you turn it on - any time, from an inline prompt right where you'd fill them in. Choosing "Prefer not to say" / "Not specified" never needs this consent. See §6.</p>
            <p><strong>On-device AI photo tagging:</strong> your uploaded photos are analyzed on your device - never sent to a server for this - to generate aesthetic "vibe tags" (style descriptors like <em>analog</em>, <em>organic</em>, <em>celestial</em>) that feed matching. This is local aesthetic-style classification, not facial recognition or biometric identification, and only the resulting tags reach our servers.</p>
          </div>

          <div class="prose">
            <p><strong>Music taste (Spotify, optional)</strong> - read-only access (<code>user-top-read</code>, <code>playlist-read-private</code>, <code>playlist-read-collaborative</code>). We store top artists and, from playlists, track/artist <em>names only</em> - never album art, previews, popularity, or audio-feature analysis, per Spotify's Developer Policy. Feeds a matching-only "artist affinity" score, never shown to other users. Your refresh token is encrypted; we never see your Spotify password.</p>
            <p><strong>Discovery, likes, matches, reports</strong> - every pass/like/superlike/hide/block is recorded (passes auto-expire in 14 days); mutual likes become a match; reports carry a structured reason, and if you file one, your identity is stripped from what the reported user's own data export could ever surface.</p>
            <p><strong>Chat</strong> - end-to-end encrypted via the Signal Protocol; see the dedicated breakdown below.</p>
            <p><strong>Meetup Safety &amp; emergency data</strong> - trusted contacts (name/phone, encrypted, likely non-users - see §4), SOS/check-in alerts with encrypted location, Digital Witness audio/video evidence with an encrypted decryption key, and check-in session state (battery/connection readings, escalation history).</p>
            <p><strong>Device &amp; technical data</strong> - push token and platform, Play Integrity/App Attest device-attestation tokens (via Firebase App Check), and standard request metadata (IP, app version).</p>
            <p><strong>Support communications</strong> - your message, category, optional screenshots, and (bug reports) app version/device info.</p>
            <p><strong>Consent records</strong> - every accept/decline of general, special-category, or safety-data consent, with version and timestamp - included in your own data export.</p>
          </div>

          <div class="data-table-wrap">
            <table class="data-table">
              <thead><tr><th>What we see in chat</th><th>Server-readable?</th></tr></thead>
              <tbody>
                <tr><td>Message content</td><td>Never - Signal Protocol ciphertext only</td></tr>
                <tr><td>Chat media attachments</td><td>Never - stored as ciphertext in a private bucket</td></tr>
                <tr><td>Who's talking to whom, when</td><td>Yes - conversation participants &amp; timestamps</td></tr>
                <tr><td>Read receipts / online status</td><td>Yes, if you leave those toggles on (default: on)</td></tr>
                <tr><td>Proposed-meetup date/time/location</td><td>Encrypted at rest, operationally decryptable - needed for reminders &amp; safety auto-configuration</td></tr>
                <tr><td>Proposed-meetup title/notes</td><td>Never - stays inside the linked message's ciphertext</td></tr>
              </tbody>
            </table>
          </div>
        </section>

        <section class="clause" id="pp-3">
          <h3><span class="num">3</span>What We Never Collect</h3>
          <div class="prose"><p>No <strong>server-side</strong> AI/ML content moderation, image scanning, or biometric/facial-recognition analysis on your photos - the only AI processing your photos ever undergo is the on-device aesthetic vibe-tagging in §2, which runs locally on your phone, never on our servers. No advertising trackers or third-party analytics SDKs. We do not sell your data, to anyone, for any reason.</p></div>
        </section>

        <section class="clause" id="pp-4">
          <h3><span class="num">4</span>Non-Users: Your Trusted Contacts' Data</h3>
          <div class="callout safety">
            <div class="callout-head"><span class="dot"></span>They never signed up - here's what we still owe them</div>
            <p>Your trusted contacts almost certainly never saw this policy or consented to anything with us directly - their name and phone number reach us because <em>you</em> entered them. So:</p>
            <ul>
              <li><strong>One-time notice</strong> - the first time a phone number is added, we SMS it a one-time explanation and a link to manage that.</li>
              <li><strong>Self-service portal, real identity check</strong> - that link leads to an OTP-verified page showing who listed them (your name, photo, hometown, current place - enough to confirm it's really you, nothing more) with an option to remove themselves.</li>
              <li><strong>Removal is permanent and enforced</strong> - a removed phone number is durably blocked from silent re-addition on a future sync, even though your device is otherwise the source of truth for your contact list.</li>
              <li><strong>You're told if it happens</strong> - push, SMS, and email, so you're never left thinking you have coverage you don't.</li>
              <li><strong>What they receive if an alert fires</strong> - an SOS/check-in text naming you and, only then, your last-known location. Nothing otherwise.</li>
              <li><strong>Retention</strong> - deleted with your account; never kept for anything beyond delivering alerts on your behalf.</li>
            </ul>
          </div>
        </section>

        <section class="clause" id="pp-5">
          <h3><span class="num">5</span>How We Use Your Information</h3>
          <div class="prose">
            <ul>
              <li><strong>Discovery &amp; matching</strong> - the core service; see §8 for exactly what drives it.</li>
              <li><strong>Delivering Meetup Safety</strong> - composing/sending alerts, running escalation, decrypting evidence for an authenticated trusted contact.</li>
              <li><strong>Trust &amp; Safety</strong> - reviewing reports, enforcing Acceptable Use, maintaining the re-signup blocklist for accounts removed for cause.</li>
              <li><strong>Notifications</strong> - push and, per your preferences, email.</li>
              <li><strong>Legal compliance</strong> - lawful requests, Terms enforcement, retention/legal-hold handling (§11).</li>
              <li><strong>Operating the service</strong> - error monitoring (PII scrubbed before it reaches our tooling), abuse rate-limiting.</li>
            </ul>
            <p>We do not use your data for third-party advertising, and we do not sell it.</p>
          </div>
        </section>

        <section class="clause" id="pp-6">
          <h3><span class="num">6</span>Consent - What's Mandatory, What's Optional</h3>
          <div class="prose"><p>Not one bundled checkbox. The first time you use Nexus, and again whenever a consent version changes, you're shown three separate choices:</p></div>
          <div class="data-table-wrap">
            <table class="data-table">
              <thead><tr><th>Consent category</th><th>Required?</th><th>Declining does</th></tr></thead>
              <tbody>
                <tr><td>General Terms of Service &amp; Privacy Policy</td><td>Mandatory</td><td>Routes to account deletion</td></tr>
                <tr><td>Special-category data (orientation, religion)</td><td><strong>Optional</strong>, asked separately</td><td>Locks those two profile fields (no real value selectable) until turned on later - nothing else affected. "Prefer not to say" never needs it.</td></tr>
                <tr><td>Meetup Safety data</td><td><strong>Optional</strong></td><td>Gates only the Safety Center meetup-safety features &amp; chat check-in toggle - nothing else. Grantable later, any time.</td></tr>
              </tbody>
            </table>
          </div>
          <div class="prose"><p>Every accept and decline is logged and exportable.</p></div>
        </section>

        <section class="clause" id="pp-7">
          <h3><span class="num">7</span>How We Protect Your Information</h3>
          <div class="prose">
            <ul>
              <li><strong>Encryption at rest</strong> - sensitive fields (profile attributes, phone numbers, chat-event scheduling data, Spotify tokens, safety contacts/alerts/evidence keys) Fernet-encrypted with rotation support - an old key can be retired without a hard cutover.</li>
              <li><strong>Blind indexing</strong> - fields we need to query for exact matches (e.g. the deletion blocklist) use a deterministic HMAC-SHA256 index rather than ever running equality search against decrypted values.</li>
              <li><strong>End-to-end chat encryption</strong> - Signal Protocol (X3DH + Double Ratchet). Your device holds the only copy of your private key material.</li>
              <li><strong>Pseudonymized matching embeddings</strong> - semantic vectors for bio/career/identity similarity are stored keyed by a random pseudonym id, not your real profile id; the mapping lives in a separate, deny-all table. A raw leak of the embeddings table alone can't be trivially traced back to you.</li>
              <li><strong>Transport security</strong> - TLS for everything in transit.</li>
              <li><strong>Device attestation</strong> - Firebase App Check (Play Integrity / App Attest) distinguishes real app traffic from scripted abuse.</li>
              <li><strong>Access control</strong> - row-level security scoping every table to its owner; internal tables (embeddings, pseudonym map, audit logs) deny <em>all</em> client-side access.</li>
              <li><strong>Rate limiting</strong> - per-endpoint limits on auth, discovery, safety actions, OTP requests, and more.</li>
              <li><strong>Error monitoring</strong> - redacts emails and token/secret-shaped strings before anything is sent; never receives message content.</li>
              <li><strong>Authentication audit logging</strong> - our auth provider keeps a security audit log of sign-in events (timestamps, event type) for detecting account-takeover attempts and unusual sign-in patterns - a standard, retained security control, not a feature we turn off to save storage.</li>
            </ul>
          </div>
        </section>

        <section class="clause" id="pp-8">
          <h3><span class="num">8</span>Automated Matching - What Drives It</h3>
          <div class="prose">
            <p>Discovery across Dating, Friends, and Professional is powered by a scoring engine we can describe, not a black box. It blends structured profile fields (values, interests, lifestyle, career/identity signal, location, age) with AI-derived semantic similarity on your bio/career/identity text (pseudonymized, §7), weighted differently per tab. Two hard exclusion rules exist on Dating (drinking/smoking mismatches), applied before scoring, not learned.</p>
          </div>
          <div class="callout consent">
            <div class="callout-head"><span class="dot"></span>Sexual orientation &amp; religious belief are not scoring inputs today</div>
            <p>Both are collected and shown on your profile (§2) as core parts of how you present yourself, but the matching engine does not currently read either field to weight or rank candidates - no orientation- or religion-aware scoring logic is live in the ranking pipeline. We still ask for separate, explicit consent to collect this data at all (§6), independent of whether it's algorithmically used, since GDPR's special-category protections cover collection and storage, not only automated use. If that changes, this section gets updated before it ships. Matching never makes a binding decision about you with legal or similarly significant effect - it ranks and surfaces candidates; a match only forms if both people like each other.</p>
          </div>
        </section>

        <section class="clause" id="pp-9">
          <h3><span class="num">9</span>Who Else Sees Your Data - Sub-processors</h3>
          <div class="prose"><p>None of the providers below see your data for anything beyond the specific job listed.</p></div>
          <div class="subproc-grid">
            <div class="subproc-card">
              <h4>Supabase</h4>
              <div class="row"><b>Purpose:</b> database, auth, file storage</div>
              <div class="row"><b>Data:</b> essentially everything in §2, encrypted as described in §7</div>
              <div class="row"><b>Location:</b> Mumbai, India (AWS ap-south-1)</div>
              <a href="https://supabase.com/privacy" target="_blank" rel="noopener">Privacy Policy →</a>
            </div>
            <div class="subproc-card">
              <h4>Twilio</h4>
              <div class="row"><b>Purpose:</b> SMS - OTP, Meetup Safety alerts, trusted-contact notices</div>
              <div class="row"><b>Data:</b> phone number &amp; message body at send time</div>
              <div class="row"><b>Location:</b> Global</div>
              <a href="https://www.twilio.com/en-us/privacy" target="_blank" rel="noopener">Privacy Policy →</a>
            </div>
            <div class="subproc-card">
              <h4>Brevo</h4>
              <div class="row"><b>Purpose:</b> transactional email (also marketing/promotional if allowed in settings)</div>
              <div class="row"><b>Data:</b> your email &amp; the message being sent</div>
              <div class="row"><b>Location:</b> EU (France)</div>
              <a href="https://www.brevo.com/legal/privacypolicy/" target="_blank" rel="noopener">Privacy Policy →</a>
            </div>
            <div class="subproc-card">
              <h4>Hetzner</h4>
              <div class="row"><b>Purpose:</b> compute hosting for our application servers</div>
              <div class="row"><b>Data:</b> ephemeral request processing; Supabase is the durable data store, not the server itself</div>
              <div class="row"><b>Location:</b> Germany / Finland (EU)</div>
              <a href="https://www.hetzner.com/legal/privacy-policy" target="_blank" rel="noopener">Privacy Policy →</a>
            </div>
            <div class="subproc-card">
              <h4>Cloudflare</h4>
              <div class="row"><b>Purpose:</b> DNS, edge network, DDoS/WAF in front of our backend &amp; the trusted-contact portal</div>
              <div class="row"><b>Data:</b> connection metadata (IP, headers) inherent to routing traffic - never profile/message content</div>
              <div class="row"><b>Location:</b> Global (edge)</div>
              <a href="https://www.cloudflare.com/privacypolicy/" target="_blank" rel="noopener">Privacy Policy →</a>
            </div>
            <div class="subproc-card">
              <h4>Google - Sign-In, App Check, FCM</h4>
              <div class="row"><b>Purpose:</b> auth, device attestation, push delivery</div>
              <div class="row"><b>Data:</b> Google account id (if used), Play Integrity tokens, push token</div>
              <div class="row"><b>Location:</b> Global</div>
              <a href="https://policies.google.com/privacy" target="_blank" rel="noopener">Privacy Policy →</a>
            </div>
            <div class="subproc-card">
              <h4>Apple - App Attest</h4>
              <div class="row"><b>Purpose:</b> iOS device-integrity attestation</div>
              <div class="row"><b>Data:</b> attestation tokens, device integrity signals</div>
              <div class="row"><b>Location:</b> Global</div>
              <a href="https://www.apple.com/legal/privacy/" target="_blank" rel="noopener">Privacy Policy →</a>
            </div>
            <div class="subproc-card">
              <h4>Spotify (optional)</h4>
              <div class="row"><b>Purpose:</b> music-taste sync, only if connected</div>
              <div class="row"><b>Data:</b> top artists, playlist track/artist names - read-only</div>
              <div class="row"><b>Location:</b> Global (EU-HQ)</div>
              <a href="https://www.spotify.com/legal/privacy-policy/" target="_blank" rel="noopener">Privacy Policy →</a>
            </div>
            <div class="subproc-card">
              <h4>Sentry</h4>
              <div class="row"><b>Purpose:</b> backend error monitoring (no-op unless configured)</div>
              <div class="row"><b>Data:</b> scrubbed errors - emails/tokens redacted, message content never in scope</div>
              <div class="row"><b>Location:</b> Global</div>
              <a href="https://sentry.io/privacy/" target="_blank" rel="noopener">Privacy Policy →</a>
            </div>
            <div class="subproc-card">
              <h4>Redis</h4>
              <div class="row"><b>Purpose:</b> short-lived cache, rate-limit &amp; OTP state only</div>
              <div class="row"><b>Data:</b> nothing outlives its TTL (typically minutes) - not a system of record</div>
            </div>
          </div>
        </section>

        <section class="clause" id="pp-10">
          <h3><span class="num">10</span>International Data Transfers</h3>
          <div class="prose"><p>Your data is stored in Mumbai, India. Twilio, Brevo, Google/Firebase, Apple, Spotify, and Sentry are each headquartered (and process data) outside India, so parts of the flow above cross borders in the ordinary course of sending an SMS, a push notification, or a monitored error. If you're in the EU: India has no European Commission adequacy decision, so a formal transfer mechanism (e.g. Standard Contractual Clauses) may be required for your data specifically - this is under review rather than something we assert is already fully in place.</p>
          <p><strong>If you're in the EU</strong>, two more things are under active review rather than settled: whether GDPR Art. 37 requires formally designating a Data Protection Officer (plausible, given the scale of special-category processing in §2 and §8), and naming an EU representative under Art. 27 if we have no EU establishment. Separately, where DPDP treats nearly everything here as consent-based, GDPR offers other legal bases - core matching plausibly sits on "necessary for performance of a contract" (Art. 6(1)(b)) rather than withdrawable consent, while special-category data and marketing (§14) stay consent-based either way. This mapping is being finalized, not asserted as complete today.</p></div>
        </section>

        <section class="clause" id="pp-11">
          <h3><span class="num">11</span>Data Retention &amp; Deletion</h3>
          <div class="prose"><p>Deleting your account starts a <strong>14-day recoverable grace window</strong> - sign back in and it's fully reversed, matches and chats intact. After that, your account is anonymized in place (every profile field wiped, email/phone unlinked) rather than row-deleted, so your former matches' own chat history stays intact on their end. A phone-number hash is added to a re-signup blocklist <strong>only if your account was actually flagged</strong> at deletion time - a good-standing account leaves no such trace. Three years after anonymization, the account is hard-deleted for good.</p></div>
          <div class="callout safety">
            <div class="callout-head"><span class="dot"></span>Meetup Safety data - shorter, separate timers</div>
            <ul>
              <li><strong>Digital Witness recordings</strong> hard-deleted after <strong>365 days</strong>, for every account, active or deleted - a hard cap, not a default you can extend.</li>
              <li><strong>Alerts/evidence tied to a deleted account</strong> kept under a <strong>180-day legal hold</strong> (in case of a live safety investigation), then purged for good.</li>
              <li><strong>Trusted contact records</strong> are deleted with the rest of your profile at anonymization - not held under the legal-hold window above.</li>
            </ul>
          </div>
        </section>

        <section class="clause" id="pp-12">
          <h3><span class="num">12</span>Your Rights</h3>
          <div class="prose">
            <ul>
              <li><strong>Access &amp; export</strong> - Settings → Export My Data: a structured export of your profile, matches, chat metadata (never content), safety data (evidence via signed link, never the raw key), and consent history. OTP-verified, rate-limited.</li>
              <li><strong>Correction</strong> - edit your profile directly, any time.</li>
              <li><strong>Erasure</strong> - delete your account (§11).</li>
              <li><strong>Withdraw consent</strong> - decline an updated Terms version (routes to deletion, since general consent is structurally required to use Nexus at all); turn special-category consent or Meetup Safety data off any time - neither requires deleting anything, both just lock their respective fields/features until re-granted.</li>
              <li><strong>Object to marketing</strong> - toggle "Product Updates" / "Promotions &amp; Offers" off independently; security/transactional email is never optional.</li>
              <li><strong>Grievance redressal</strong> - §16.</li>
              <li><strong>Nomination (DPDP §14)</strong> - naming someone to exercise your rights after death or incapacity isn't implemented yet; a genuinely new right with little settled practice, tracked rather than ignored.</li>
            </ul>
          </div>
        </section>

        <section class="clause" id="pp-13">
          <h3><span class="num">13</span>Children's Privacy</h3>
          <div class="prose"><p>Nexus is not for anyone under 18, on either flavor. We do not knowingly collect data from minors. Age is self-attested, not ID-verified (Terms §2) - an accepted residual risk of the product category rather than something we pretend doesn't exist. "Underage" reports are handled the same as any other Trust &amp; Safety report.</p></div>
        </section>

        <section class="clause" id="pp-14">
          <h3><span class="num">14</span>Marketing Communications</h3>
          <div class="prose"><p>Five independently toggleable email categories: new matches/likes, new messages, an activity digest, product updates, promotions/offers. <strong>All five currently default to on</strong> for a new account - turn any off any time, no justification required. Security and account-lifecycle email is never gated by these toggles.</p></div>
        </section>

        <section class="clause" id="pp-15">
          <h3><span class="num">15</span>Changes to This Policy</h3>
          <div class="prose"><p>Versioned alongside the Terms of Service. A materially updated version triggers the same full-page re-consent flow described in Terms §14 - you'll always know when something changed and get a real choice about it.</p></div>
        </section>

        <section class="clause" id="pp-16">
          <h3><span class="num">16</span>Grievance Officer &amp; Contact</h3>
          <div class="prose">
            <p>Per DPDP §13, our designated Grievance Officer:</p>
            <p><strong>__GRIEVANCE_NAME__</strong><br/>
            Email: __GRIEVANCE_EMAIL__<br/>
            Phone: __GRIEVANCE_PHONE__<br/>
            Website: __GRIEVANCE_WEBSITE__</p>
            <p>General privacy questions: <strong>privacy@__DOMAIN__</strong>.</p>
          </div>
        </section>
      </div>
    </main>
  </div>
</div>

<footer class="colophon">
  Nexus - Terms of Service &amp; Privacy Policy · generated from the live application code and database schema · not a substitute for review by qualified counsel before publication.
</footer>

</body>
</html>
"""
