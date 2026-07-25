# ruff: noqa: E501
import os

from fastapi import APIRouter
from fastapi.responses import FileResponse, HTMLResponse, PlainTextResponse, Response

from app.core.config import settings

router = APIRouter()

STATIC_DIR = os.path.join(os.path.dirname(__file__), "..", "static")


@router.get("/favicon.ico", include_in_schema=False)
async def favicon():
    return FileResponse(
        os.path.join(STATIC_DIR, "favicon.ico"),
        media_type="image/x-icon",
    )


@router.get("/favicon-16x16.png", include_in_schema=False)
async def favicon_16():
    return FileResponse(
        os.path.join(STATIC_DIR, "favicon-16x16.png"),
        media_type="image/png",
    )


@router.get("/favicon-32x32.png", include_in_schema=False)
async def favicon_32():
    return FileResponse(
        os.path.join(STATIC_DIR, "favicon-32x32.png"),
        media_type="image/png",
    )


@router.get("/apple-touch-icon.png", include_in_schema=False)
async def apple_touch_icon():
    return FileResponse(
        os.path.join(STATIC_DIR, "apple-touch-icon.png"),
        media_type="image/png",
    )


@router.get("/android-chrome-192x192.png", include_in_schema=False)
async def android_chrome_192():
    return FileResponse(
        os.path.join(STATIC_DIR, "android-chrome-192x192.png"),
        media_type="image/png",
    )


@router.get("/android-chrome-512x512.png", include_in_schema=False)
async def android_chrome_512():
    return FileResponse(
        os.path.join(STATIC_DIR, "android-chrome-512x512.png"),
        media_type="image/png",
    )


@router.get("/site.webmanifest", include_in_schema=False)
async def webmanifest():
    return FileResponse(
        os.path.join(STATIC_DIR, "site.webmanifest"),
        media_type="application/manifest+json",
    )


@router.get("/logo.png", include_in_schema=False)
async def logo_png():
    return FileResponse(os.path.join(STATIC_DIR, "logo.png"), media_type="image/png")


@router.get("/logo-foreground.png", include_in_schema=False)
async def logo_fg_png():
    return FileResponse(
        os.path.join(STATIC_DIR, "logo-foreground.png"),
        media_type="image/png",
    )


@router.get("/og-image.png", include_in_schema=False)
async def og_image_png():
    return FileResponse(
        os.path.join(STATIC_DIR, "nexus-wide-logo.jpg"),
        media_type="image/jpeg",
    )


@router.get("/nexus-wide-logo.jpg", include_in_schema=False)
async def nexus_wide_logo_jpg():
    return FileResponse(
        os.path.join(STATIC_DIR, "nexus-wide-logo.jpg"),
        media_type="image/jpeg",
    )


@router.get("/robots.txt", include_in_schema=False)
async def robots_txt():
    content = f"User-agent: *\nAllow: /\nSitemap: {settings.backend_url}/sitemap.xml\n"
    return PlainTextResponse(content)


@router.get("/error", response_class=HTMLResponse, include_in_schema=False)
async def render_error_page(code: int = 404, message: str | None = None):
    """Renders a common error page inspired by Nexus backend root design system."""
    error_titles = {
        400: (
            "400",
            "Bad Request",
            "The request payload or parameters were invalid or corrupted.",
            "var(--nova)",
        ),
        401: (
            "401",
            "Unauthorized",
            "Authentication credentials were missing or invalid.",
            "var(--nova)",
        ),
        403: (
            "403",
            "Access Forbidden",
            "You do not have authorization to access this deep-space node.",
            "var(--pulsar)",
        ),
        404: (
            "404",
            "Signal Lost",
            "The node or signal frequency requested could not be located in orbit.",
            "var(--starlight)",
        ),
        429: (
            "429",
            "Rate Limit Exceeded",
            "Too many requests. Please throttle your pulse rate before reconnecting.",
            "var(--nova)",
        ),
        500: (
            "500",
            "Internal Anomaly",
            "An unexpected void anomaly occurred within our core engine cluster.",
            "var(--pulsar)",
        ),
        502: (
            "502",
            "Bad Gateway",
            "The upstream gateway engine returned an invalid response.",
            "var(--nebula)",
        ),
        503: (
            "503",
            "Service Unavailable",
            "System maintenance or temporary overload in progress. Re-orbiting soon.",
            "var(--nova)",
        ),
    }

    code_str, default_title, default_desc, signal_color = error_titles.get(
        code,
        (
            str(code),
            "HTTP Error",
            "An error occurred while processing your request.",
            "var(--starlight)",
        ),
    )

    display_title = default_title
    display_desc = message if message else default_desc

    html_template = f"""<!DOCTYPE html>
<html lang="en">
    <head>
        <meta charset="UTF-8">
        <meta name="viewport" content="width=device-width, initial-scale=1.0">
        <meta name="theme-color" content="#04060f">
        <title>{code_str} - {display_title} | Nexus</title>
        <link rel="icon" type="image/x-icon" href="/favicon.ico">
        <link rel="preconnect" href="https://fonts.googleapis.com">
        <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
        <link href="https://fonts.googleapis.com/css2?family=Sora:wght@400;600;700;800&family=Nunito+Sans:wght@400;600;700&family=JetBrains+Mono:wght@400;600;700&display=swap" rel="stylesheet">
        <script src="https://cdn.jsdelivr.net/npm/lucide@latest/dist/umd/lucide.min.js"></script>
        <style>
            :root {{
                --font-display: 'Sora', sans-serif;
                --font-body: 'Nunito Sans', sans-serif;
                --font-mono: 'JetBrains Mono', monospace;
                --starlight:   oklch(0.74 0.18 205);
                --pulsar:      oklch(0.71 0.22 0);
                --nebula:      oklch(0.68 0.20 280);
                --nova:        oklch(0.80 0.19 85);
                --z-canvas: 0;
                --z-glow: 1;
                --z-content: 10;
            }}
            *, *::before, *::after {{ box-sizing: border-box; margin: 0; padding: 0; }}
            body {{
                font-family: var(--font-body);
                background-color: #04060f;
                color: #f8fafc;
                min-height: 100vh;
                display: flex;
                flex-direction: column;
                align-items: center;
                justify-content: center;
                position: relative;
                overflow: hidden;
                padding: 1.5rem;
            }}
            .f-display {{ font-family: var(--font-display); letter-spacing: -0.025em; }}
            .f-mono    {{ font-family: var(--font-mono); }}
            #cosmos-canvas {{
                position: fixed; inset: 0; pointer-events: none; z-index: var(--z-canvas);
            }}
            .nebula-blob {{
                position: fixed; border-radius: 50%; filter: blur(140px); pointer-events: none; z-index: var(--z-glow);
            }}
            .glass-card {{
                width: 100%;
                max-width: 540px;
                background: rgba(15, 23, 42, 0.85);
                backdrop-filter: blur(24px);
                -webkit-backdrop-filter: blur(24px);
                border: 1px solid rgba(255, 255, 255, 0.12);
                border-radius: 1.5rem;
                padding: 2.5rem 2rem;
                text-align: center;
                position: relative;
                z-index: var(--z-content);
                box-shadow: 0 25px 60px rgba(0, 0, 0, 0.7);
                margin: auto;
            }}
            .badge-signal {{
                display: inline-flex;
                align-items: center;
                gap: 0.5rem;
                padding: 0.35rem 0.85rem;
                border-radius: 9999px;
                font-size: 0.75rem;
                font-weight: 600;
                font-family: var(--font-mono);
                background: rgba(255, 255, 255, 0.05);
                border: 1px solid rgba(255, 255, 255, 0.12);
                color: {signal_color};
                margin-bottom: 1.5rem;
            }}
            .badge-dot {{
                width: 0.5rem;
                height: 0.5rem;
                border-radius: 50%;
                background-color: {signal_color};
                animation: pulse 2s cubic-bezier(0.4, 0, 0.6, 1) infinite;
            }}
            @keyframes pulse {{
                0%, 100% {{ opacity: 1; }}
                50% {{ opacity: .5; }}
            }}
            .error-code {{
                font-size: 4.5rem;
                line-height: 1;
                font-weight: 800;
                color: #ffffff;
                margin-bottom: 0.75rem;
                text-shadow: 0 0 35px {signal_color};
            }}
            .error-title {{
                font-size: 1.5rem;
                font-weight: 700;
                color: #f1f5f9;
                margin-bottom: 0.75rem;
            }}
            .error-desc {{
                font-size: 0.95rem;
                line-height: 1.6;
                color: #94a3b8;
                margin-bottom: 2rem;
                max-width: 420px;
                margin-left: auto;
                margin-right: auto;
            }}
            .btn-group {{
                display: flex;
                flex-direction: row;
                flex-wrap: wrap;
                align-items: center;
                justify-content: center;
                gap: 0.75rem;
            }}
            .btn-primary {{
                display: inline-flex;
                align-items: center;
                justify-content: center;
                gap: 0.5rem;
                padding: 0.75rem 1.5rem;
                border-radius: 0.85rem;
                font-weight: 700;
                font-size: 0.9rem;
                text-decoration: none;
                background: linear-gradient(135deg, #38bdf8 0%, #818cf8 100%);
                color: #0f172a;
                box-shadow: 0 0 25px rgba(56, 189, 248, 0.3);
                transition: all 0.25s ease;
                border: none;
                cursor: pointer;
            }}
            .btn-primary:hover {{
                box-shadow: 0 0 35px rgba(56, 189, 248, 0.55);
                transform: translateY(-2px);
            }}
            .btn-secondary {{
                display: inline-flex;
                align-items: center;
                justify-content: center;
                gap: 0.5rem;
                padding: 0.75rem 1.5rem;
                border-radius: 0.85rem;
                font-weight: 600;
                font-size: 0.9rem;
                color: #e2e8f0;
                background: rgba(255, 255, 255, 0.06);
                border: 1px solid rgba(255, 255, 255, 0.15);
                transition: all 0.25s ease;
                cursor: pointer;
            }}
            .btn-secondary:hover {{
                background: rgba(255, 255, 255, 0.12);
                color: #ffffff;
                transform: translateY(-2px);
            }}
            .error-footer {{
                position: relative;
                z-index: var(--z-content);
                margin-top: 1.5rem;
                font-size: 0.75rem;
                color: #64748b;
                text-align: center;
            }}
        </style>
    </head>
    <body>
        <canvas id="cosmos-canvas"></canvas>
        <div class="nebula-blob" style="width: 500px; height: 500px; top: -128px; left: -128px; opacity: 0.25; background: radial-gradient(circle, {signal_color} 0%, transparent 70%);"></div>
        <div class="nebula-blob" style="width: 400px; height: 400px; bottom: -128px; right: -128px; opacity: 0.20; background: radial-gradient(circle, var(--nebula) 0%, transparent 70%);"></div>

        <div class="glass-card">
            <div class="badge-signal">
                <span class="badge-dot"></span>
                HTTP STATUS {code_str}
            </div>

            <h1 class="f-display error-code">
                {code_str}
            </h1>
            <h2 class="f-display error-title">
                {display_title}
            </h2>
            <p class="error-desc">
                {display_desc}
            </p>

            <div class="btn-group">
                <a href="/" class="f-display btn-primary">
                    <i data-lucide="home" style="width:18px;height:18px;"></i> Return to Orbit
                </a>
                <button onclick="window.history.back()" class="f-display btn-secondary">
                    <i data-lucide="arrow-left" style="width:18px;height:18px;"></i> Go Back
                </button>
            </div>
        </div>

        <div class="f-mono error-footer">
            Nexus Matchmaking Engine &bull; Hyper-Proximity Social Discovery
        </div>

        <script>
            if (window.lucide) {{ lucide.createIcons(); }}
            const canvas = document.getElementById('cosmos-canvas');
            const ctx = canvas.getContext('2d');
            let stars = [];
            function resizeCanvas() {{
                canvas.width = window.innerWidth;
                canvas.height = window.innerHeight;
            }}
            window.addEventListener('resize', resizeCanvas);
            resizeCanvas();
            for(let i = 0; i < 70; i++) {{
                stars.push({{
                    x: Math.random() * canvas.width,
                    y: Math.random() * canvas.height,
                    r: Math.random() * 1.5 + 0.5,
                    alpha: Math.random() * 0.5 + 0.2,
                    speed: Math.random() * 0.2 + 0.05
                }});
            }}
            function render() {{
                ctx.clearRect(0, 0, canvas.width, canvas.height);
                stars.forEach(s => {{
                    ctx.fillStyle = `rgba(255, 255, 255, ${{s.alpha}})`;
                    ctx.beginPath();
                    ctx.arc(s.x, s.y, s.r, 0, Math.PI * 2);
                    ctx.fill();
                    s.y -= s.speed;
                    if(s.y < 0) s.y = canvas.height;
                }});
                requestAnimationFrame(render);
            }}
            render();
        </script>
    </body>
</html>"""
    return HTMLResponse(content=html_template, status_code=code)


@router.get("/sitemap.xml", include_in_schema=False)
async def sitemap_xml():
    xml_content = f"""<?xml version="1.0" encoding="UTF-8"?>
<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">
    <url>
        <loc>{settings.backend_url}/</loc>
        <changefreq>daily</changefreq>
        <priority>1.0</priority>
    </url>
    <url>
        <loc>{settings.backend_url}/safety</loc>
        <changefreq>weekly</changefreq>
        <priority>0.8</priority>
    </url>
    <url>
        <loc>{settings.backend_url}/legal</loc>
        <changefreq>monthly</changefreq>
        <priority>0.5</priority>
    </url>
    <url>
        <loc>{settings.backend_url}/contact</loc>
        <changefreq>monthly</changefreq>
        <priority>0.5</priority>
    </url>
    <url>
        <loc>{settings.backend_url}/help</loc>
        <changefreq>weekly</changefreq>
        <priority>0.8</priority>
    </url>
    <url>
        <loc>{settings.backend_url}/faq</loc>
        <changefreq>weekly</changefreq>
        <priority>0.8</priority>
    </url>
</urlset>"""
    return Response(content=xml_content, media_type="application/xml")


@router.get("/", response_class=HTMLResponse)
async def render_landing_page():
    html_template = """<!DOCTYPE html>
<html lang="en">
    <head>
        <meta charset="UTF-8">
        <meta name="viewport" content="width=device-width, initial-scale=1.0">
        <meta name="theme-color" content="#04060f">
        <meta name="description" content="Nexus - hyper-proximity social discovery. 2D spatial orbit radar, Spotify vibe matching, E2EE messaging, and a Safety Center that actually keeps you safe. No swipe cards.">
        <meta name="keywords" content="Nexus, Social Discovery, Orbit Radar, Proximity Engine, Encrypted Chat, Spotify Vibe Sync, Safety Center, Campus Orbit, devakesu, MEC">
        <meta name="author" content="@devakesu (https://devakesu.com)">

        <!-- Open Graph -->
        <meta property="og:type" content="website">
        <meta property="og:url" content="https://nexus-engine.app/">
        <meta property="og:title" content="Nexus - Discover People In Your Real-Life Orbit">
        <meta property="og:description" content="Spatial orbit discovery, Spotify vibe sync, E2EE pre-key messaging & Safety Center check-in alerts. Not another swipe app.">
        <meta property="og:image" content="/nexus-wide-logo.jpg">
        <meta property="og:site_name" content="Nexus Platform">

        <!-- Twitter -->
        <meta property="twitter:card" content="summary_large_image">
        <meta property="twitter:url" content="https://nexus-engine.app/">
        <meta property="twitter:title" content="Nexus - Discover People In Your Real-Life Orbit">
        <meta property="twitter:description" content="Spatial orbit discovery, Spotify vibe sync, E2EE messaging & Safety Center. Campus-verified. No swipe cards.">
        <meta property="twitter:image" content="/nexus-wide-logo.jpg">

        <title>Nexus - Discover People In Your Real-Life Orbit</title>

        <!-- Favicons -->
        <link rel="icon" type="image/x-icon" href="/favicon.ico">
        <link rel="icon" type="image/png" sizes="32x32" href="/favicon-32x32.png">
        <link rel="icon" type="image/png" sizes="16x16" href="/favicon-16x16.png">
        <link rel="apple-touch-icon" sizes="180x180" href="/apple-touch-icon.png">
        <link rel="manifest" href="/site.webmanifest">

        <!-- Fonts: Sora (display) + JetBrains Mono (mono) + Nunito Sans (body) -->
        <link rel="preconnect" href="https://fonts.googleapis.com">
        <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
        <link href="https://fonts.googleapis.com/css2?family=Sora:wght@400;500;600;700;800&family=Nunito+Sans:ital,wght@0,400;0,500;0,600;0,700;1,400&family=JetBrains+Mono:wght@400;500;700&display=swap" rel="stylesheet">

        <!-- Tailwind v4 CDN -->
        <script src="https://cdn.jsdelivr.net/npm/@tailwindcss/browser@4"></script>
        <!-- Lucide Icons -->
        <script src="https://cdn.jsdelivr.net/npm/lucide@latest/dist/umd/lucide.min.js"></script>

        <style>
            /* ── Design Tokens ─────────────────────────── */
            :root {
                --font-display: 'Sora', sans-serif;
                --font-body: 'Nunito Sans', sans-serif;
                --font-mono: 'JetBrains Mono', monospace;

                /* Deep-space palette */
                --void:        oklch(0.07 0.018 265);
                --void-mid:    oklch(0.10 0.022 265);
                --surface:     oklch(0.13 0.026 265);
                --surface-2:   oklch(0.16 0.024 265);
                --border:      oklch(0.22 0.020 265);

                /* Signal colors */
                --starlight:   oklch(0.74 0.18 205);   /* cyan-sky */
                --pulsar:      oklch(0.71 0.22 0);      /* rose-pink */
                --nebula:      oklch(0.68 0.20 280);    /* indigo-violet */
                --nova:        oklch(0.80 0.19 85);     /* amber */
                --aurora:      oklch(0.74 0.20 165);    /* emerald */

                /* Text */
                --ink-1: oklch(0.97 0.005 265);
                --ink-2: oklch(0.78 0.012 265);
                --ink-3: oklch(0.58 0.015 265);

                /* Z-index scale */
                --z-canvas: 0;
                --z-glow: 1;
                --z-content: 10;
                --z-nav: 50;
                --z-modal: 100;
            }

            /* ── Reset & Base ───────────────────────────── */
            *, *::before, *::after { box-sizing: border-box; margin: 0; padding: 0; }
            html { scroll-behavior: smooth; -webkit-text-size-adjust: 100%; }

            body {
                font-family: var(--font-body);
                background: var(--void);
                color: var(--ink-1);
                overflow-x: hidden;
                -webkit-font-smoothing: antialiased;
                -moz-osx-font-smoothing: grayscale;
            }

            /* ── Typography ─────────────────────────────── */
            .f-display { font-family: var(--font-display); letter-spacing: -0.025em; }
            .f-mono    { font-family: var(--font-mono); }

            /* ── Universal canvas ───────────────────────── */
            #cosmos-canvas {
                position: fixed; inset: 0;
                pointer-events: none;
                z-index: var(--z-canvas);
            }

            /* ── Nebula glow blobs ──────────────────────── */
            .nebula-blob {
                position: fixed;
                border-radius: 50%;
                filter: blur(140px);
                pointer-events: none;
                z-index: var(--z-glow);
                will-change: transform;
            }
            .nb-1 { width: 700px; height: 700px; background: oklch(0.55 0.22 205 / 0.12); top: -15%; left: 5%; }
            .nb-2 { width: 800px; height: 800px; background: oklch(0.55 0.20 280 / 0.10); top: 40%; right: -10%; }
            .nb-3 { width: 600px; height: 600px; background: oklch(0.55 0.22 0   / 0.09); bottom: -10%; left: 20%; }
            .nb-4 { width: 500px; height: 500px; background: oklch(0.65 0.20 85  / 0.07); top: 10%; right: 30%; }

            /* ── Nav ────────────────────────────────────── */
            .nav-pill {
                position: fixed;
                top: 1.25rem; left: 50%;
                transform: translateX(-50%);
                z-index: var(--z-nav);
                width: min(1100px, calc(100vw - 2rem));
                background: oklch(0.10 0.022 265 / 0.82);
                backdrop-filter: blur(20px) saturate(1.5);
                -webkit-backdrop-filter: blur(20px) saturate(1.5);
                border: 1px solid oklch(0.28 0.025 265 / 0.7);
                border-radius: 2rem;
                padding: 0.75rem 1.5rem;
                display: flex; align-items: center; justify-content: space-between;
                gap: 1rem;
            }

            .nav-link {
                font-size: 0.8125rem; font-weight: 600;
                color: var(--ink-2);
                text-decoration: none;
                transition: color 0.2s;
                white-space: nowrap;
            }
            .nav-link:hover { color: var(--ink-1); }
            a:focus-visible, button:focus-visible {
                outline: 2px solid var(--starlight);
                outline-offset: 3px;
                border-radius: 6px;
            }

            /* ── Buttons ────────────────────────────────── */
            .btn-primary {
                display: inline-flex; align-items: center; gap: 0.6rem;
                padding: 0.875rem 1.75rem;
                background: linear-gradient(135deg, oklch(0.72 0.19 205), oklch(0.60 0.22 250));
                border: none; border-radius: 1rem;
                font-family: var(--font-display); font-weight: 700; font-size: 0.9rem;
                color: oklch(0.06 0.01 265);
                cursor: pointer; text-decoration: none;
                transition: transform 0.18s, box-shadow 0.18s;
                box-shadow: 0 4px 24px oklch(0.72 0.19 205 / 0.35);
                white-space: nowrap;
            }
            .btn-primary:hover  { transform: translateY(-2px); box-shadow: 0 8px 32px oklch(0.72 0.19 205 / 0.45); }
            .btn-primary:active { transform: translateY(0); }

            .btn-nexus {
                background: linear-gradient(135deg, oklch(0.74 0.18 205), oklch(0.68 0.20 280));
                box-shadow: 0 4px 24px oklch(0.72 0.19 205 / 0.30);
                color: oklch(0.97 0.005 265);
            }
            .btn-nexus:hover { box-shadow: 0 8px 32px oklch(0.72 0.19 205 / 0.45); }

            .btn-campus {
                background: linear-gradient(135deg, oklch(0.78 0.20 85), oklch(0.68 0.22 60));
                box-shadow: 0 4px 24px oklch(0.78 0.20 85 / 0.30);
                color: oklch(0.10 0.01 85);
            }
            .btn-campus:hover { box-shadow: 0 8px 32px oklch(0.78 0.20 85 / 0.45); }

            .btn-ghost {
                display: inline-flex; align-items: center; gap: 0.6rem;
                padding: 0.875rem 1.75rem;
                background: oklch(0.16 0.024 265 / 0.7);
                border: 1px solid oklch(0.28 0.025 265 / 0.8);
                border-radius: 1rem;
                font-family: var(--font-display); font-weight: 600; font-size: 0.9rem;
                color: var(--ink-2);
                cursor: pointer; text-decoration: none;
                transition: all 0.18s;
                white-space: nowrap;
            }
            .btn-ghost:hover { border-color: var(--starlight); color: var(--ink-1); background: oklch(0.18 0.026 265 / 0.9); }

            /* ── Glass surface ──────────────────────────── */
            .glass {
                background: oklch(0.13 0.026 265 / 0.72);
                backdrop-filter: blur(18px);
                -webkit-backdrop-filter: blur(18px);
                border: 1px solid oklch(0.28 0.022 265 / 0.6);
                border-radius: 1.25rem;
            }
            .glass-hover { transition: border-color 0.22s, box-shadow 0.22s; cursor: default; }
            .glass-hover:hover {
                border-color: oklch(0.40 0.025 265 / 0.8);
                box-shadow: 0 12px 40px oklch(0 0 0 / 0.3);
            }

            /* ── Accent glass variants ──────────────────── */
            .glass-cyan  { border-color: oklch(0.72 0.19 205 / 0.25); background: oklch(0.13 0.026 205 / 0.65); }
            .glass-rose  { border-color: oklch(0.65 0.22 0   / 0.25); background: oklch(0.13 0.026 0   / 0.65); }
            .glass-indigo{ border-color: oklch(0.62 0.20 280 / 0.25); background: oklch(0.13 0.026 280 / 0.65); }
            .glass-amber { border-color: oklch(0.78 0.20 85  / 0.25); background: oklch(0.13 0.026 85  / 0.65); }
            .glass-green { border-color: oklch(0.72 0.20 165 / 0.25); background: oklch(0.13 0.026 165 / 0.65); }

            /* ── Bespoke Status Indicators & Micro-Chips System ───────── */
            .badge {
                display: inline-flex; align-items: center; justify-content: center; gap: 0.45rem;
                font-family: var(--font-mono); font-size: 0.65rem; font-weight: 700;
                padding: 0.35rem 0.75rem;
                border-radius: 0.5rem;
                letter-spacing: 0.09em; text-transform: uppercase;
                backdrop-filter: blur(12px);
                -webkit-backdrop-filter: blur(12px);
                position: relative;
                box-shadow: inset 0 1px 0 oklch(1 0 0 / 0.08);
                transition: all 0.2s cubic-bezier(0.16, 1, 0.3, 1);
                white-space: nowrap;
                line-height: 1;
            }

            .badge-live {
                background: oklch(0.12 0.035 205 / 0.9);
                color: oklch(0.92 0.14 205);
                border: 1px solid oklch(0.72 0.19 205 / 0.45);
                box-shadow: 0 0 16px oklch(0.72 0.19 205 / 0.2), inset 0 1px 0 oklch(0.72 0.19 205 / 0.3);
            }

            .badge-campus {
                background: oklch(0.14 0.04 85 / 0.9);
                color: oklch(0.92 0.18 85);
                border: 1px solid oklch(0.78 0.20 85 / 0.45);
                box-shadow: 0 0 16px oklch(0.78 0.20 85 / 0.2), inset 0 1px 0 oklch(0.78 0.20 85 / 0.3);
            }

            .badge-beta {
                background: oklch(0.12 0.04 280 / 0.9);
                color: oklch(0.90 0.16 280);
                border: 1px solid oklch(0.68 0.20 280 / 0.45);
                box-shadow: 0 0 16px oklch(0.68 0.20 280 / 0.2), inset 0 1px 0 oklch(0.68 0.20 280 / 0.3);
            }

            .badge-soon {
                background: oklch(0.12 0.02 265 / 0.9);
                color: oklch(0.82 0.08 205);
                border: 1px solid oklch(0.40 0.04 265 / 0.6);
                box-shadow: inset 0 1px 0 oklch(1 0 0 / 0.05);
            }

            .badge-premium {
                background: linear-gradient(135deg, oklch(0.14 0.03 265 / 0.95), oklch(0.20 0.05 280 / 0.95));
                color: oklch(0.95 0.14 280);
                border: 1px solid oklch(0.72 0.18 280 / 0.55);
                box-shadow: 0 0 20px oklch(0.72 0.18 280 / 0.25), inset 0 1px 0 oklch(1 0 0 / 0.15);
            }

            .badge-rose {
                background: oklch(0.14 0.04 0 / 0.9);
                color: oklch(0.92 0.18 0);
                border: 1px solid oklch(0.71 0.22 0 / 0.45);
                box-shadow: 0 0 16px oklch(0.71 0.22 0 / 0.2), inset 0 1px 0 oklch(0.71 0.22 0 / 0.3);
            }

            /* Bespoke Micro Status Icon Nodes */
            .beacon-dot {
                position: relative;
                display: inline-flex; align-items: center; justify-content: center;
                width: 7px; height: 7px; flex-shrink: 0;
                border-radius: 50%;
                background: currentColor;
                box-sizing: border-box;
            }
            .beacon-dot.pulse::after {
                content: '';
                position: absolute; inset: -3px;
                border-radius: 50%;
                border: 1.5px solid currentColor;
                animation: beacon-ping 2s cubic-bezier(0, 0, 0.2, 1) infinite;
                box-sizing: border-box;
            }
            @keyframes beacon-ping {
                0% { transform: scale(0.5); opacity: 0.9; }
                80%, 100% { transform: scale(1.8); opacity: 0; }
            }

            /* Orbital Dash Spinner for Coming Soon */
            .beacon-orbit {
                position: relative;
                width: 11px; height: 11px; flex-shrink: 0;
                display: inline-flex; align-items: center; justify-content: center;
                box-sizing: border-box;
            }
            .beacon-orbit::before {
                content: '';
                position: absolute; inset: 0;
                border-radius: 50%;
                border: 1.5px dashed currentColor;
                animation: beacon-spin 6s linear infinite;
                opacity: 0.85;
                box-sizing: border-box;
            }
            .beacon-orbit::after {
                content: '';
                width: 3px; height: 3px;
                border-radius: 50%;
                background: currentColor;
                position: absolute;
                top: 50%; left: 50%;
                transform: translate(-50%, -50%);
            }
            @keyframes beacon-spin {
                from { transform: rotate(0deg); }
                to   { transform: rotate(360deg); }
            }

            /* Tech Diamond / Hex Node for Beta & Premium */
            .beacon-hex {
                position: relative;
                width: 9px; height: 9px; flex-shrink: 0;
                display: inline-flex; align-items: center; justify-content: center;
                box-sizing: border-box;
            }
            .beacon-hex::before {
                content: '';
                position: absolute; inset: 0;
                background: currentColor;
                clip-path: polygon(50% 0%, 100% 25%, 100% 75%, 50% 100%, 0% 75%, 0% 25%);
                animation: twinkle 2.5s ease-in-out infinite;
            }

            /* ── Section layout ─────────────────────────── */
            .section { max-width: 1200px; margin-inline: auto; padding: clamp(4rem,8vw,7rem) 1.5rem; }
            .section-divider { border-top: 1px solid oklch(0.22 0.020 265 / 0.7); }

            /* ── Orbit radar mockup ─────────────────────── */
            .orbit-ring {
                position: absolute; border-radius: 50%;
                border: 1px solid oklch(0.72 0.19 205 / 0.15);
                top: 50%; left: 50%;
                transform: translate(-50%, -50%);
            }
            .orbit-ring-1 { width: 90%;  height: 90%;  border-color: oklch(0.72 0.19 205 / 0.12); }
            .orbit-ring-2 { width: 64%;  height: 64%;  border-color: oklch(0.68 0.20 280 / 0.20); }
            .orbit-ring-3 { width: 38%;  height: 38%;  border-color: oklch(0.72 0.19 205 / 0.28); }

            /* ── Animations ─────────────────────────────── */
            @keyframes float-gentle {
                0%, 100% { transform: translateY(0); }
                50%       { transform: translateY(-10px); }
            }
            @keyframes orbit-spin {
                from { transform: translate(-50%, -50%) rotate(0deg); }
                to   { transform: translate(-50%, -50%) rotate(360deg); }
            }
            @keyframes pulse-ring {
                0%   { transform: translate(-50%, -50%) scale(1);   opacity: 0.3; }
                70%  { transform: translate(-50%, -50%) scale(1.18); opacity: 0; }
                100% { transform: translate(-50%, -50%) scale(1.18); opacity: 0; }
            }
            @keyframes twinkle {
                0%, 100% { opacity: 0.6; }
                50%       { opacity: 1; }
            }
            @keyframes scan-sweep {
                from { transform: rotate(0deg); }
                to   { transform: rotate(360deg); }
            }
            @keyframes reveal-up {
                from { opacity: 0; transform: translateY(28px); }
                to   { opacity: 1; transform: translateY(0); }
            }
            @keyframes slide-in-left {
                from { opacity: 0; transform: translateX(-24px); }
                to   { opacity: 1; transform: translateX(0); }
            }
            @keyframes fade-in {
                from { opacity: 0; }
                to   { opacity: 1; }
            }
            @keyframes glow-pulse {
                0%, 100% { box-shadow: 0 0 20px oklch(0.72 0.19 205 / 0.3); }
                50%       { box-shadow: 0 0 40px oklch(0.72 0.19 205 / 0.55); }
            }
            @keyframes bar-dance {
                0%, 100% { height: 8px; }
                25%       { height: 16px; }
                50%       { height: 12px; }
                75%       { height: 20px; }
            }

            .animate-float  { animation: float-gentle 6s ease-in-out infinite; }
            .animate-glow   { animation: glow-pulse 3s ease-in-out infinite; }
            .bar-1 { animation: bar-dance 1.2s ease-in-out infinite; }
            .bar-2 { animation: bar-dance 1.2s ease-in-out infinite 0.2s; }
            .bar-3 { animation: bar-dance 1.2s ease-in-out infinite 0.4s; }
            .bar-4 { animation: bar-dance 1.2s ease-in-out infinite 0.6s; }

            /* Scroll reveal */
            .reveal { opacity: 0; transform: translateY(24px); transition: opacity 0.65s cubic-bezier(0.16,1,0.3,1), transform 0.65s cubic-bezier(0.16,1,0.3,1); }
            .reveal.in { opacity: 1; transform: translateY(0); }
            .reveal-l { opacity: 0; transform: translateX(-24px); transition: opacity 0.65s cubic-bezier(0.16,1,0.3,1), transform 0.65s cubic-bezier(0.16,1,0.3,1); }
            .reveal-l.in { opacity: 1; transform: translateX(0); }

            /* ── Orbit node dots ────────────────────────── */
            .orbit-node {
                position: absolute;
                display: flex; align-items: center; gap: 0.35rem;
                background: oklch(0.10 0.022 265 / 0.95);
                border: 1px solid oklch(0.28 0.022 265 / 0.8);
                border-radius: 999px;
                padding: 0.2rem 0.55rem 0.2rem 0.2rem;
                font-family: var(--font-mono); font-size: 0.6rem;
                white-space: nowrap;
                box-shadow: 0 2px 12px oklch(0 0 0 / 0.4);
            }
            .orbit-avatar {
                width: 1.25rem; height: 1.25rem; border-radius: 50%;
                font-size: 0.55rem; font-weight: 800;
                display: flex; align-items: center; justify-content: center;
                color: oklch(0.97 0 0);
                flex-shrink: 0;
            }

            /* ── Mode selector tabs ─────────────────────── */
            .mode-tab {
                display: inline-flex; align-items: center; gap: 0.5rem;
                padding: 0.5rem 1.1rem;
                border-radius: 999px;
                font-size: 0.8rem; font-weight: 600;
                border: 1px solid transparent;
                cursor: pointer; transition: all 0.2s;
                background: transparent;
                color: var(--ink-3);
            }
            .mode-tab.active-dating  { background: oklch(0.71 0.22 0   / 0.18); color: oklch(0.80 0.18 0);   border-color: oklch(0.71 0.22 0   / 0.35); }
            .mode-tab.active-friends { background: oklch(0.74 0.20 165 / 0.18); color: oklch(0.80 0.18 165); border-color: oklch(0.74 0.20 165 / 0.35); }
            .mode-tab.active-pro     { background: oklch(0.68 0.20 280 / 0.18); color: oklch(0.72 0.18 280); border-color: oklch(0.68 0.20 280 / 0.35); }
            .mode-tab:not(.active-dating):not(.active-friends):not(.active-pro):hover { color: var(--ink-2); }

            /* ── How it works steps ─────────────────────── */
            .step-num {
                width: 2.5rem; height: 2.5rem; border-radius: 50%;
                display: flex; align-items: center; justify-content: center;
                font-family: var(--font-mono); font-weight: 700; font-size: 0.9rem;
                background: oklch(0.16 0.024 265);
                border: 1px solid oklch(0.28 0.022 265 / 0.7);
                color: var(--starlight);
                flex-shrink: 0;
            }

            /* ── Safety ring SVG animation ──────────────── */
            .safety-ring-track { fill: none; stroke: oklch(0.22 0.020 265); stroke-width: 5; }
            .safety-ring-fill  {
                fill: none; stroke-width: 5;
                stroke: url(#safetyGrad); stroke-linecap: round;
                stroke-dasharray: 251.2;
                stroke-dashoffset: 65;
                transform: rotate(-90deg); transform-origin: 50% 50%;
                transition: stroke-dashoffset 1.2s cubic-bezier(0.16,1,0.3,1);
            }

            /* ── Scan line effect ───────────────────────── */
            .scan-arm {
                position: absolute; top: 50%; left: 50%;
                width: 45%; height: 1px;
                transform-origin: 0% 50%;
                background: linear-gradient(90deg, oklch(0.72 0.19 205 / 0.8), transparent);
                animation: scan-sweep 4s linear infinite;
            }
            .scan-pulse {
                position: absolute; top: 50%; left: 50%;
                width: 90%; height: 90%;
                border-radius: 50%;
                transform: translate(-50%, -50%);
                animation: pulse-ring 3s ease-out infinite;
                border: 1px solid oklch(0.72 0.19 205 / 0.5);
            }

            /* ── FAQ accordion ──────────────────────────── */
            details { border-radius: 1rem; transition: background 0.2s; }
            details[open] { background: oklch(0.15 0.025 265 / 0.8); }
            details summary { list-style: none; cursor: pointer; }
            details summary::-webkit-details-marker { display: none; }
            .faq-chevron { transition: transform 0.25s; }
            details[open] .faq-chevron { transform: rotate(180deg); }

            /* ── Feature icon containers ────────────────── */
            .feat-icon {
                width: 2.75rem; height: 2.75rem; border-radius: 0.875rem;
                display: flex; align-items: center; justify-content: center;
                flex-shrink: 0;
            }

            /* ── CTA section ────────────────────────────── */
            .cta-glow {
                position: absolute; inset: 0; border-radius: inherit; pointer-events: none;
                background: radial-gradient(ellipse 60% 50% at 50% 100%, oklch(0.72 0.19 205 / 0.15), transparent);
            }

            /* ── Footer ─────────────────────────────────── */
            .footer-link {
                color: oklch(0.92 0.01 265);
                text-decoration: none;
                font-size: 0.875rem;
                font-weight: 500;
                transition: color 0.2s, text-shadow 0.2s;
                text-shadow: 0 2px 10px rgba(0, 0, 0, 0.95);
            }
            .footer-link:hover {
                color: var(--starlight);
                text-shadow: 0 0 16px oklch(0.72 0.19 205 / 0.8);
            }

            /* ── Scrollbar ──────────────────────────────── */
            ::-webkit-scrollbar { width: 6px; }
            ::-webkit-scrollbar-track { background: var(--void); }
            ::-webkit-scrollbar-thumb { background: oklch(0.25 0.022 265); border-radius: 3px; }

            /* ── Selection ──────────────────────────────── */
            ::selection { background: oklch(0.72 0.19 205 / 0.30); color: var(--ink-1); }

            /* ── Reduced motion ─────────────────────────── */
            @media (prefers-reduced-motion: reduce) {
                *, *::before, *::after { animation-duration: 0.01ms !important; transition-duration: 0.01ms !important; }
                .reveal, .reveal-l { opacity: 1 !important; transform: none !important; }
            }

            /* ── Responsive 2-column grid ───────────────── */
            .grid-2col {
                display: grid;
                grid-template-columns: 1fr;
                gap: 2.5rem;
                align-items: center;
                width: 100%;
            }
            @media (min-width: 992px) {
                .grid-2col { grid-template-columns: 1fr 1fr; gap: 3.5rem; }
            }

            /* ── Floating stat pills around mockup ───── */
            .floating-stat-right {
                position: absolute; top: -1rem; right: -1rem;
                padding: 0.45rem 0.85rem; border-radius: 0.6rem;
                box-shadow: 0 8px 24px oklch(0 0 0 / 0.55);
                z-index: 25;
            }
            .floating-stat-left {
                position: absolute; bottom: 2rem; left: -2rem;
                padding: 0.45rem 0.85rem; border-radius: 0.6rem;
                box-shadow: 0 8px 24px oklch(0 0 0 / 0.55);
                z-index: 25;
            }

            /* ── Scanning reticle indicator ───────────── */
            @keyframes reticle-rotate {
                0%   { transform: rotate(0deg); }
                100% { transform: rotate(360deg); }
            }
            @keyframes reticle-core {
                0%, 100% { opacity: 1;   transform: scale(1); }
                50%       { opacity: 0.5; transform: scale(0.7); }
            }
            .live-reticle {
                position: relative;
                display: inline-flex; align-items: center; justify-content: center;
                width: 16px; height: 16px; flex-shrink: 0;
            }
            .live-reticle .r-brackets {
                position: absolute; inset: 0;
                animation: reticle-rotate 4s linear infinite;
            }
            .live-reticle .r-core {
                position: absolute;
                width: 5px; height: 5px;
                background: currentColor;
                transform: rotate(45deg);
                animation: reticle-core 2s ease-in-out infinite;
            }

            /* ── Footer grid & Universe Constellation animation ──── */
            @keyframes constellation-twinkle {
                0%, 100% { opacity: 0.4; transform: scale(0.9); }
                50%       { opacity: 1.0; transform: scale(1.5); }
            }
            .star-twinkle-1 { animation: constellation-twinkle 3s ease-in-out infinite; }
            .star-twinkle-2 { animation: constellation-twinkle 4s ease-in-out 1s infinite; }
            .star-twinkle-3 { animation: constellation-twinkle 3.5s ease-in-out 1.8s infinite; }
            .star-twinkle-4 { animation: constellation-twinkle 2.8s ease-in-out 0.6s infinite; }

            @keyframes comet-fly {
                0%   { transform: translateX(120px) translateY(-80px) rotate(-32deg); opacity: 0; }
                12%  { opacity: 1; }
                75%  { opacity: 0.9; }
                100% { transform: translateX(-550px) translateY(320px) rotate(-32deg); opacity: 0; }
            }

            .footer-comet {
                position: absolute;
                width: 160px; height: 2px;
                background: linear-gradient(90deg, oklch(0.98 0.05 205), oklch(0.72 0.19 205 / 0.5), transparent);
                border-radius: 999px;
                box-shadow: 0 0 10px oklch(0.72 0.19 205 / 0.5), 0 0 20px oklch(0.68 0.20 280 / 0.4);
                pointer-events: none;
                z-index: 1;
                opacity: 0.45;
            }
            .footer-comet::before {
                content: '';
                position: absolute; left: 0; top: -2px;
                width: 5px; height: 5px; border-radius: 50%;
                background: #ffffff;
                box-shadow: 0 0 8px oklch(0.98 0.05 205), 0 0 16px oklch(0.72 0.19 205);
            }
            .comet-1 { top: 10%; right: 5%;  animation: comet-fly 6.5s cubic-bezier(0.25, 1, 0.5, 1) infinite; }
            .comet-2 { top: 35%; right: 25%; animation: comet-fly 8.5s cubic-bezier(0.25, 1, 0.5, 1) 2.5s infinite; }
            .comet-3 { top: 15%; right: 50%; animation: comet-fly 7.5s cubic-bezier(0.25, 1, 0.5, 1) 4.8s infinite; }

            @keyframes footer-orbit-spin {
                0%   { transform: translate(-50%, -50%) rotate(0deg); }
                100% { transform: translate(-50%, -50%) rotate(360deg); }
            }
            .footer-orbit-ring {
                position: absolute; top: 50%; left: 50%;
                width: 650px; height: 650px; border-radius: 50%;
                border: 1px dashed oklch(0.72 0.19 205 / 0.18);
                box-shadow: 0 0 30px oklch(0.72 0.19 205 / 0.08);
                animation: footer-orbit-spin 50s linear infinite;
                pointer-events: none;
            }

            .footer-grid {
                max-width: 1200px; margin: 0 auto; padding: 0 1.5rem;
                display: grid;
                grid-template-columns: 1.6fr 1fr 1fr;
                gap: 3.5rem;
                position: relative;
                z-index: 2;
            }
            @media (max-width: 768px) {
                .footer-grid { grid-template-columns: 1fr; gap: 2.25rem; }
            }

            /* ── QR Modal grid ───────────────────────── */
            .qr-modal-grid {
                display: grid;
                grid-template-columns: repeat(2, 1fr);
                gap: 1.25rem;
                width: 100%;
            }
            @media (max-width: 580px) {
                .qr-modal-grid {
                    grid-template-columns: 1fr !important;
                    gap: 1rem !important;
                }
            }

            /* ── How-it-works grid ───────────────────── */
            .how-grid {
                display: grid;
                grid-template-columns: 1fr;
                gap: 1.25rem;
                width: 100%;
            }
            @media (min-width: 640px) {
                .how-grid { grid-template-columns: repeat(2, 1fr); }
            }
            @media (min-width: 1024px) {
                .how-grid { grid-template-columns: repeat(4, 1fr); }
            }

            /* ── Privacy grid ──────────────────────── */
            .privacy-grid {
                display: grid;
                grid-template-columns: 1fr;
                gap: 1.25rem;
                width: 100%;
            }
            @media (min-width: 640px) {
                .privacy-grid { grid-template-columns: repeat(2, 1fr); }
            }
            @media (min-width: 1024px) {
                .privacy-grid { grid-template-columns: repeat(3, 1fr); }
            }

            /* ── Mobile viewport & responsive containment ───── */
            html, body {
                overflow-x: hidden !important;
                width: 100% !important;
                max-width: 100vw !important;
            }

            @media (max-width: 768px) {
                .nav-desktop { display: none; }
                .nav-pill {
                    padding: 0.5rem 0.875rem !important;
                    width: calc(100vw - 1.25rem) !important;
                    top: 0.75rem !important;
                }
                .section {
                    padding: clamp(3rem, 6vw, 4.5rem) 1rem !important;
                }
            }

            @media (max-width: 640px) {
                .floating-stat-right {
                    right: 0.25rem !important;
                    top: -0.75rem !important;
                    transform: scale(0.85);
                    transform-origin: top right;
                }
                .floating-stat-left {
                    left: 0.25rem !important;
                    bottom: 0.5rem !important;
                    transform: scale(0.85);
                    transform-origin: bottom left;
                }
                .btn-primary, .btn-ghost {
                    width: 100% !important;
                    justify-content: center !important;
                    text-align: center !important;
                    box-sizing: border-box !important;
                }
                .mode-tab {
                    width: 100% !important;
                    justify-content: center !important;
                }
                .hero-download-group {
                    width: 100% !important;
                    flex-direction: column !important;
                }
            }
        </style>
    </head>

    <body>

        <!-- Skip link -->
        <a href="#main-content" class="sr-only focus:not-sr-only focus:fixed focus:top-4 focus:left-4 focus:z-[200] focus:px-4 focus:py-2 focus:rounded-xl focus:bg-white focus:text-black focus:font-bold">
            Skip to main content
        </a>

        <!-- Cosmos canvas -->
        <canvas id="cosmos-canvas" aria-hidden="true"></canvas>

        <!-- Nebula blobs -->
        <div class="nebula-blob nb-1" aria-hidden="true"></div>
        <div class="nebula-blob nb-2" aria-hidden="true"></div>
        <div class="nebula-blob nb-3" aria-hidden="true"></div>
        <div class="nebula-blob nb-4" aria-hidden="true"></div>

        <!-- ═══════════════════════ NAV ═══════════════════════ -->
        <header role="banner">
        <nav class="nav-pill" role="navigation" aria-label="Primary navigation">
            <!-- Brand -->
            <a href="/" class="flex items-center gap-2.5 shrink-0" aria-label="Nexus home">
                <div class="w-8 h-8 rounded-xl overflow-hidden border border-white/10 flex items-center justify-center bg-[oklch(0.12_0.024_265)]">
                    <img src="/logo.png" alt="" width="28" height="28" class="w-full h-full object-cover rounded-lg">
                </div>
                <span class="f-display font-extrabold text-base tracking-tight text-white">NEXUS</span>
                <span class="f-mono text-[0.6rem] text-[oklch(0.72_0.19_205)] hidden sm:inline tracking-widest uppercase" style="letter-spacing:0.12em;">ORBIT</span>
            </a>

            <!-- Desktop links -->
            <div class="nav-desktop flex items-center gap-6">
                <a href="#orbit"    class="nav-link">Orbit Radar</a>
                <a href="#spotify"  class="nav-link">Vibe Sync</a>
                <a href="#safety"   class="nav-link">Safety</a>
                <a href="#modes"    class="nav-link">Modes</a>
                <a href="#campus"   class="nav-link">Campus</a>
                <a href="#how"      class="nav-link">How It Works</a>
                <a href="#faq"      class="nav-link">FAQ</a>
            </div>

            <!-- CTA -->
            <a href="https://play.google.com/store/apps/details?id=com.devakesu.apps.nexus"
            target="_blank" rel="noopener noreferrer"
            class="btn-nexus shrink-0 !py-2 !px-4 !text-xs !rounded-xl">
                <svg xmlns="http://www.w3.org/2000/svg" width="14" height="14" viewBox="0 0 24 24" fill="currentColor" aria-hidden="true">
                    <path d="M3.18 23.5a1.5 1.5 0 0 1-.94-1.41V1.91A1.5 1.5 0 0 1 3.18.5l11.52 11.52zm1.32-20.1v17.2l9.26-8.6zM21.32 13.5l-2.88 1.66-2.88-2.88 2.88-2.88 2.88 1.66a1.5 1.5 0 0 1 0 2.44zM3.18.5l11.52 11.52-2.88 2.88L3.18.5z"/>
                </svg>
                Get App
            </a>
        </nav>
        </header>

        <!-- ═══════════════════════ MAIN ═══════════════════════ -->
        <main id="main-content" role="main">

        <!-- ─────────────── HERO ─────────────── -->
        <section id="hero" style="min-height: 100svh; display: flex; align-items: center; padding-top: 7rem; padding-bottom: 4rem;">
            <div class="section" style="padding-top: 0; padding-bottom: 0; width: 100%;">
                <div class="grid-2col">

                    <!-- Left: Copy -->
                    <div style="animation: reveal-up 0.8s cubic-bezier(0.16,1,0.3,1) both;">

                        <!-- Status pill -->
                        <div class="badge badge-soon" style="padding:0.45rem 1rem;font-size:0.7rem;margin-bottom:1.75rem;border-radius:0.6rem;background:oklch(0.12 0.025 265 / 0.95);border:1px solid oklch(0.72 0.19 205 / 0.4);box-shadow:0 0 20px oklch(0.72 0.19 205 / 0.15);">
                            <span class="beacon-orbit" style="color:oklch(0.74 0.19 205);" aria-hidden="true"></span>
                            <span style="color:oklch(0.92 0.12 205);">COMING SOON - NEXUS</span>
                        </div>

                        <h1 class="f-display" style="font-size:clamp(2.6rem,5.5vw,4.25rem);font-weight:800;line-height:1.08;letter-spacing:-0.03em;color:var(--ink-1);text-wrap:balance;margin-bottom:1.5rem;">
                            You're already<br>
                            in someone's<br>
                            <span style="color: oklch(0.74 0.19 205);">orbit.</span>
                        </h1>

                        <p style="font-size:clamp(1rem,1.5vw,1.125rem);color:var(--ink-2);line-height:1.7;max-width:48ch;margin-bottom:2.25rem;">
                            Nexus replaces swipe-card gamification with a <strong style="color:var(--ink-1);font-weight:600;">2D spatial orbit radar</strong> - see who's actually near you, sync music vibes via Spotify, and meet safely with automated check-in alerts. Real connections. No deck of curated strangers.
                        </p>

                        <!-- Download buttons -->
                        <div style="display:flex;flex-wrap:wrap;gap:0.875rem;margin-bottom:1.75rem;">
                            <a href="https://play.google.com/store/apps/details?id=com.devakesu.apps.nexus"
                            target="_blank" rel="noopener noreferrer"
                            class="btn-primary btn-nexus">
                                <svg xmlns="http://www.w3.org/2000/svg" width="18" height="18" viewBox="0 0 24 24" fill="currentColor" aria-hidden="true">
                                    <path d="M3.18 23.5a1.5 1.5 0 0 1-.94-1.41V1.91A1.5 1.5 0 0 1 3.18.5l11.52 11.52zm1.32-20.1v17.2l9.26-8.6zM21.32 13.5l-2.88 1.66-2.88-2.88 2.88-2.88 2.88 1.66a1.5 1.5 0 0 1 0 2.44zM3.18.5l11.52 11.52-2.88 2.88L3.18.5z"/>
                                </svg>
                                <span>
                                    <span style="display:block;font-size:0.6rem;font-family:var(--font-mono);letter-spacing:0.07em;opacity:0.85;font-weight:500;">NEXUS - COMING SOON</span>
                                    <span style="display:block;font-size:0.9rem;">Preview on Play Store</span>
                                </span>
                            </a>

                            <a href="https://play.google.com/store/apps/details?id=com.devakesu.apps.nexus.mec"
                            target="_blank" rel="noopener noreferrer"
                            class="btn-primary btn-campus">
                                <svg xmlns="http://www.w3.org/2000/svg" width="18" height="18" viewBox="0 0 24 24" fill="currentColor" aria-hidden="true">
                                    <path d="M3.18 23.5a1.5 1.5 0 0 1-.94-1.41V1.91A1.5 1.5 0 0 1 3.18.5l11.52 11.52zm1.32-20.1v17.2l9.26-8.6zM21.32 13.5l-2.88 1.66-2.88-2.88 2.88-2.88 2.88 1.66a1.5 1.5 0 0 1 0 2.44zM3.18.5l11.52 11.52-2.88 2.88L3.18.5z"/>
                                </svg>
                                <span>
                                    <span style="display:block;font-size:0.6rem;font-family:var(--font-mono);letter-spacing:0.07em;opacity:0.75;font-weight:500;">NEXUS MEC - CAMPUS VERIFIED</span>
                                    <span style="display:block;font-size:0.9rem;">Get on Google Play</span>
                                </span>
                            </a>
                        </div>

                        <!-- QR trigger -->
                        <button onclick="document.getElementById('qr-modal').style.display='flex'"
                                class="btn-ghost !py-2 !px-4 !text-xs !rounded-xl f-mono"
                                aria-label="Show QR codes to install Nexus">
                            <svg xmlns="http://www.w3.org/2000/svg" width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><rect width="5" height="5" x="3" y="3" rx="1"/><rect width="5" height="5" x="16" y="3" rx="1"/><rect width="5" height="5" x="3" y="16" rx="1"/><path d="M21 16h-3a2 2 0 0 0-2 2v3"/><path d="M21 21v.01"/><path d="M12 7v3a2 2 0 0 1-2 2H7"/><path d="M3 12h.01"/><path d="M12 3h.01"/><path d="M12 16v.01"/><path d="M16 12h1"/><path d="M21 12v.01"/><path d="M12 21v-1"/></svg>
                            Scan QR to Install
                        </button>
                    </div>

                    <!-- Right: Orbit Radar Mockup -->
                    <div class="animate-float" style="animation-delay:0.3s;display:flex;justify-content:center;align-items:center;position:relative;">

                        <!-- Phone shell -->
                        <div style="width:min(300px,80vw);height:min(580px,70vh);background:oklch(0.09 0.022 265);border:1px solid oklch(0.22 0.020 265 / 0.8);border-radius:2.75rem;padding:0.875rem;box-shadow:0 32px 80px oklch(0 0 0 / 0.55), 0 0 60px oklch(0.72 0.19 205 / 0.08);position:relative;overflow:hidden;" class="animate-glow">

                            <!-- Notch -->
                            <div style="position:absolute;top:0;left:50%;transform:translateX(-50%);width:7.5rem;height:1.25rem;background:oklch(0.06 0.016 265);border-radius:0 0 0.875rem 0.875rem;z-index:20;" aria-hidden="true"></div>

                            <!-- Screen -->
                            <div style="width:100%;height:100%;background:oklch(0.07 0.018 265);border-radius:2rem;overflow:hidden;display:flex;flex-direction:column;padding:1.25rem 0.875rem 0.875rem;gap:0.75rem;">

                                <!-- App header -->
                                <div style="display:flex;justify-content:space-between;align-items:center;margin-top:0.75rem;">
                                    <div style="display:flex;align-items:center;gap:0.5rem;">
                                        <img src="/logo.png" alt="" width="20" height="20" style="border-radius:0.375rem;width:1.25rem;height:1.25rem;">
                                        <span class="f-display" style="font-size:0.7rem;font-weight:700;color:var(--ink-1);letter-spacing:0.08em;">ORBIT RADAR</span>
                                    </div>
                                    <div class="badge badge-live" style="padding:0.2rem 0.55rem;font-size:0.55rem;border-radius:0.375rem;background:oklch(0.74 0.20 165 / 0.15);color:oklch(0.85 0.18 165);border-color:oklch(0.74 0.20 165 / 0.4);">
                                        <span class="beacon-dot pulse" style="color:oklch(0.74 0.20 165);" aria-hidden="true"></span>
                                        <span>ACTIVE</span>
                                    </div>
                                </div>

                                <!-- Radar canvas area -->
                                <div style="flex:1;position:relative;border-radius:1.25rem;background:oklch(0.055 0.016 265);border:1px solid oklch(0.18 0.020 265 / 0.7);overflow:hidden;display:flex;align-items:center;justify-content:center;">

                                    <!-- Orbital rings -->
                                    <div class="orbit-ring orbit-ring-1"></div>
                                    <div class="orbit-ring orbit-ring-2"></div>
                                    <div class="orbit-ring orbit-ring-3"></div>

                                    <!-- Scan arm + pulse -->
                                    <div class="scan-pulse" aria-hidden="true"></div>
                                    <div class="scan-arm" aria-hidden="true"></div>

                                    <!-- Grid overlay -->
                                    <div style="position:absolute;inset:0;background-image:linear-gradient(oklch(0.72 0.19 205 / 0.04) 1px,transparent 1px),linear-gradient(90deg,oklch(0.72 0.19 205 / 0.04) 1px,transparent 1px);background-size:24px 24px;" aria-hidden="true"></div>

                                    <!-- YOU -->
                                    <div style="position:absolute;z-index:20;width:2.75rem;height:2.75rem;border-radius:50%;background:linear-gradient(135deg,oklch(0.72 0.19 205),oklch(0.62 0.20 280));padding:2px;box-shadow:0 0 20px oklch(0.72 0.19 205 / 0.5);">
                                        <div style="width:100%;height:100%;border-radius:50%;background:oklch(0.08 0.020 265);display:flex;align-items:center;justify-content:center;" class="f-mono" style="font-size:0.55rem;font-weight:800;color:var(--ink-1);">YOU</div>
                                    </div>

                                    <!-- Orbit nodes -->
                                    <div class="orbit-node" style="top:14%;left:10%;">
                                        <div class="orbit-avatar" style="background:oklch(0.68 0.20 280);">S</div>
                                        <span style="color:oklch(0.78 0.18 205);">Sophia · 45m</span>
                                    </div>
                                    <div class="orbit-node" style="bottom:18%;right:8%;">
                                        <div class="orbit-avatar" style="background:oklch(0.71 0.22 0);">A</div>
                                        <span style="color:oklch(0.80 0.18 0);">Alex · 120m</span>
                                    </div>
                                    <div class="orbit-node" style="top:28%;right:6%;">
                                        <div class="orbit-avatar" style="background:oklch(0.78 0.20 85);">M</div>
                                        <span style="color:oklch(0.80 0.18 85);">Marcus · 210m</span>
                                    </div>
                                    <div class="orbit-node" style="bottom:35%;left:5%;">
                                        <div class="orbit-avatar" style="background:oklch(0.74 0.20 165);">J</div>
                                        <span style="color:oklch(0.80 0.18 165);">Jade · 380m</span>
                                    </div>
                                </div>

                                <!-- Spotify banner -->
                                <div style="padding:0.7rem 0.875rem;background:oklch(0.10 0.022 265);border:1px solid oklch(0.74 0.20 165 / 0.25);border-radius:0.875rem;display:flex;align-items:center;gap:0.75rem;">
                                    <div style="width:2rem;height:2rem;border-radius:0.5rem;background:oklch(0.74 0.20 165 / 0.15);display:flex;align-items:center;justify-content:center;flex-shrink:0;">
                                        <svg xmlns="http://www.w3.org/2000/svg" width="14" height="14" viewBox="0 0 496 512" fill="oklch(0.74 0.20 165)" aria-hidden="true"><path d="M248 8C111.1 8 8 111.1 8 248s103.1 240 240 240 240-103.1 240-240S384.9 8 248 8zm96.4 328.3c-3.8 5.8-11.5 7.5-17.4 3.7-47.6-29.1-107.5-35.7-178.1-19.5-6.7 1.5-13.4-2.8-14.9-9.5-1.5-6.7 2.8-13.4 9.5-14.9 77.1-17.6 143.3-10 196.4 22.5 5.9 3.8 7.5 11.5 3.7 17.4zm25.9-57.9c-4.7 7.3-14.7 9.5-21.9 4.8-54.5-33.5-137.6-43.2-202.1-23.6-8.3 2.5-17.1-2.2-19.6-10.5-2.5-8.3 2.2-17.1 10.5-19.6 73.6-22.3 165.2-11.5 227.4 26.9 7.2 4.6 9.4 14.7 4.7 21.9zm2.2-60.1c-65.4-38.8-173.3-42.4-235.7-23.5-9.9 3-20.3-2.5-23.3-12.4-3-9.9 2.5-20.3 12.4-23.3 71.6-21.7 190.6-17.5 265.7 27.1 8.9 5.3 11.9 16.8 6.6 25.7-5.3 8.9-16.8 11.8-25.7 6.4z"/></svg>
                                    </div>
                                    <div style="flex:1;min-width:0;">
                                        <p style="font-size:0.65rem;font-weight:700;color:var(--ink-1);white-space:nowrap;overflow:hidden;text-overflow:ellipsis;">Spotify Vibe Sync</p>
                                        <p class="f-mono" style="font-size:0.55rem;color:oklch(0.74 0.20 165);">94% Genre Match · Midnight Lo-Fi</p>
                                    </div>
                                    <!-- Bars -->
                                    <div style="display:flex;align-items:flex-end;gap:2px;height:20px;" aria-hidden="true">
                                        <div class="bar-1" style="width:3px;background:oklch(0.74 0.20 165);border-radius:2px;"></div>
                                        <div class="bar-2" style="width:3px;background:oklch(0.74 0.20 165);border-radius:2px;"></div>
                                        <div class="bar-3" style="width:3px;background:oklch(0.74 0.20 165);border-radius:2px;"></div>
                                        <div class="bar-4" style="width:3px;background:oklch(0.74 0.20 165);border-radius:2px;"></div>
                                    </div>
                                </div>

                                <!-- Safety strip -->
                                <div class="badge badge-rose" style="width:100%;justify-content:center;padding:0.55rem;border-radius:0.75rem;font-size:0.6rem;">
                                    <span class="beacon-dot pulse" style="color:oklch(0.80 0.18 0);" aria-hidden="true"></span>
                                    <span>CHECK-IN ALERT MATRIX · ARMED</span>
                                </div>
                            </div>
                        </div>

                        <!-- Floating stat pills around phone -->
                        <div class="badge badge-live floating-stat-right" aria-hidden="true">
                            <span class="beacon-dot pulse" style="color:oklch(0.74 0.20 165);" aria-hidden="true"></span>
                            <span style="color:var(--ink-1);font-weight:600;">4 people nearby</span>
                        </div>
                        <div class="badge badge-beta floating-stat-left" aria-hidden="true">
                            <span class="beacon-hex" style="color:oklch(0.74 0.20 165);" aria-hidden="true"></span>
                            <span style="color:var(--ink-1);font-weight:600;">94% vibe match</span>
                        </div>
                    </div>
                </div>

                <!-- Trust stats row -->
                <div class="reveal" style="margin-top:4rem;display:flex;flex-wrap:wrap;gap:1rem;justify-content:center;border-top:1px solid oklch(0.22 0.020 265 / 0.5);padding-top:2rem;">
                    <div style="display:flex;align-items:center;gap:0.6rem;">
                        <svg xmlns="http://www.w3.org/2000/svg" width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="oklch(0.74 0.20 165)" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M12 22s8-4 8-10V5l-8-3-8 3v7c0 6 8 10 8 10z"/></svg>
                        <span style="font-size:0.8125rem;color:var(--ink-2);">E2EE on every message</span>
                    </div>
                    <div style="display:flex;align-items:center;gap:0.6rem;">
                        <svg xmlns="http://www.w3.org/2000/svg" width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="oklch(0.72 0.19 205)" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><circle cx="12" cy="12" r="10"/><path d="m9 12 2 2 4-4"/></svg>
                        <span style="font-size:0.8125rem;color:var(--ink-2);">Campus-verified identities</span>
                    </div>
                    <div style="display:flex;align-items:center;gap:0.6rem;">
                        <svg xmlns="http://www.w3.org/2000/svg" width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="oklch(0.78 0.20 85)" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M21 10c0 7-9 13-9 13s-9-6-9-13a9 9 0 0 1 18 0z"/><circle cx="12" cy="10" r="3"/></svg>
                        <span style="font-size:0.8125rem;color:var(--ink-2);">Real proximity - not distance buckets</span>
                    </div>
                    <div style="display:flex;align-items:center;gap:0.6rem;">
                        <svg xmlns="http://www.w3.org/2000/svg" width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="oklch(0.68 0.20 280)" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><rect width="18" height="11" x="3" y="11" rx="2" ry="2"/><path d="M7 11V7a5 5 0 0 1 10 0v4"/></svg>
                        <span style="font-size:0.8125rem;color:var(--ink-2);">GDPR data export & deletion</span>
                    </div>
                </div>
            </div>
        </section>

        <!-- ─────────────── ORBIT RADAR ─────────────── -->
        <section id="orbit" class="section section-divider">
            <div class="grid-2col">

                <!-- Visual: Orbit comparison -->
                <div class="reveal-l" style="display:flex;flex-direction:column;gap:1rem;">
                    <!-- Bad: Swipe deck -->
                    <div class="glass glass-rose" style="padding:1.5rem;border-radius:1.25rem;">
                        <div style="display:flex;align-items:center;gap:0.5rem;margin-bottom:1rem;">
                            <svg xmlns="http://www.w3.org/2000/svg" width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="oklch(0.71 0.22 0)" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M18 6 6 18"/><path d="m6 6 12 12"/></svg>
                            <span class="f-mono" style="font-size:0.65rem;color:oklch(0.75 0.18 0);font-weight:700;letter-spacing:0.08em;">OLD WAY &mdash; SWIPE CARDS</span>
                        </div>
                        <div style="display:flex;gap:0.625rem;position:relative;height:5.5rem;margin-bottom:0.75rem;">
                            <div style="width:5rem;height:5.5rem;background:oklch(0.18 0.020 265);border-radius:0.875rem;transform:rotate(-6deg);border:1px solid oklch(0.25 0.018 265);position:absolute;left:0.5rem;"></div>
                            <div style="width:5rem;height:5.5rem;background:oklch(0.16 0.020 265);border-radius:0.875rem;transform:rotate(-2deg);border:1px solid oklch(0.22 0.018 265);position:absolute;left:0.75rem;"></div>
                            <div style="width:5rem;height:5.5rem;background:oklch(0.72 0.19 205 / 0.08);border-radius:0.875rem;border:1px solid oklch(0.72 0.19 205 / 0.20);display:flex;align-items:center;justify-content:center;position:relative;z-index:3;">
                                <span style="font-size:0.6rem;color:var(--ink-3);text-align:center;padding:0.25rem;">Binary<br>yes/no<br>swipe</span>
                            </div>
                        </div>
                        <ul style="display:flex;flex-direction:column;gap:0.35rem;font-size:0.75rem;color:oklch(0.78 0.010 265);">
                            <li>&#x2717; Gamifies human connection</li>
                            <li>&#x2717; Forces romantic framing</li>
                            <li>&#x2717; Hides real distance</li>
                        </ul>
                    </div>

                    <!-- Good: Nexus orbit -->
                    <div class="glass glass-cyan" style="padding:1.5rem;border-radius:1.25rem;position:relative;overflow:hidden;">
                        <div style="display:flex;align-items:center;gap:0.5rem;margin-bottom:1rem;">
                            <svg xmlns="http://www.w3.org/2000/svg" width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="oklch(0.72 0.19 205)" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M22 11.08V12a10 10 0 1 1-5.93-9.14"/><path d="m9 11 3 3L22 4"/></svg>
                            <span class="f-mono" style="font-size:0.65rem;color:oklch(0.72 0.19 205);font-weight:700;letter-spacing:0.08em;">NEXUS - SPATIAL ORBIT RADAR</span>
                            <span class="badge badge-live" style="margin-left:auto;"><span class="beacon-dot pulse" aria-hidden="true"></span>RADAR LIVE</span>
                        </div>
                        <div style="position:relative;height:5rem;display:flex;align-items:center;justify-content:center;">
                            <div style="width:4.5rem;height:4.5rem;border-radius:50%;border:1px solid oklch(0.72 0.19 205 / 0.15);position:absolute;"></div>
                            <div style="width:3rem;height:3rem;border-radius:50%;border:1px solid oklch(0.68 0.20 280 / 0.25);position:absolute;"></div>
                            <div style="width:1.4rem;height:1.4rem;border-radius:50%;background:linear-gradient(135deg,oklch(0.72 0.19 205),oklch(0.62 0.20 280));"></div>
                            <div style="position:absolute;top:5px;left:calc(50% + 20px);width:0.6rem;height:0.6rem;border-radius:50%;background:oklch(0.68 0.20 280);"></div>
                            <div style="position:absolute;bottom:8px;right:calc(50% - 32px);width:0.5rem;height:0.5rem;border-radius:50%;background:oklch(0.71 0.22 0);"></div>
                            <div style="position:absolute;top:20px;right:8px;width:0.45rem;height:0.45rem;border-radius:50%;background:oklch(0.78 0.20 85);"></div>
                        </div>
                        <ul style="display:flex;flex-direction:column;gap:0.35rem;font-size:0.75rem;color:oklch(0.85 0.010 265);">
                            <li>✓ 2D spatial canvas with 3 orbital tiers (50m - 500m)</li>
                            <li>✓ Friends, study peers, romance - you choose the context</li>
                            <li>✓ Real-time proximity vectors, no buckets</li>
                        </ul>
                    </div>
                </div>

                <!-- Copy -->
                <div class="reveal" style="display:flex;flex-direction:column;gap:1.25rem;">
                    <h2 class="f-display" style="font-size:clamp(2rem,3.5vw,3rem);font-weight:800;line-height:1.1;letter-spacing:-0.025em;color:var(--ink-1);text-wrap:balance;">
                        The radar, not the deck.
                    </h2>
                    <p style="font-size:1rem;color:var(--ink-2);line-height:1.7;max-width:46ch;">
                        Swipe apps turned meeting people into an Amazon product listing. Nexus maps real-life proximity onto a <strong style="color:var(--ink-1);">2D orbit canvas</strong> - three concentric tiers at 50m, 250m, and 500m - so discovery feels more like running into someone than scrolling a catalog.
                    </p>
                    <div style="display:flex;flex-direction:column;gap:0.875rem;">
                        <div class="glass" style="padding:1rem 1.25rem;border-radius:1rem;display:flex;align-items:flex-start;gap:1rem;">
                            <div class="feat-icon" style="background:oklch(0.72 0.19 205 / 0.12);">
                                <svg xmlns="http://www.w3.org/2000/svg" width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="oklch(0.72 0.19 205)" stroke-width="1.75" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><circle cx="12" cy="12" r="2"/><path d="M4.93 4.93 19.07 19.07"/><path d="M12 2a10 10 0 0 1 7.07 17.07"/><path d="M4.93 4.93A10 10 0 0 0 12 22"/></svg>
                            </div>
                            <div>
                                <p style="font-weight:700;color:var(--ink-1);font-size:0.9rem;margin-bottom:0.2rem;">Tier 1 · Tier 2 · Tier 3</p>
                                <p style="font-size:0.8125rem;color:var(--ink-3);">Concentric orbital bands: 50m (immediate), 250m (block), 500m (neighbourhood). Nodes appear on real distance vectors.</p>
                            </div>
                        </div>
                        <div class="glass" style="padding:1rem 1.25rem;border-radius:1rem;display:flex;align-items:flex-start;gap:1rem;">
                            <div class="feat-icon" style="background:oklch(0.68 0.20 280 / 0.12);">
                                <svg xmlns="http://www.w3.org/2000/svg" width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="oklch(0.68 0.20 280)" stroke-width="1.75" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M20.84 4.61a5.5 5.5 0 0 0-7.78 0L12 5.67l-1.06-1.06a5.5 5.5 0 0 0-7.78 7.78l1.06 1.06L12 21.23l7.78-7.78 1.06-1.06a5.5 5.5 0 0 0 0-7.78z"/><line x1="12" x2="12" y1="8" y2="12"/><line x1="12" x2="12.01" y1="16" y2="16"/></svg>
                            </div>
                            <div>
                                <p style="font-weight:700;color:var(--ink-1);font-size:0.9rem;margin-bottom:0.2rem;">Personality-driven discovery</p>
                                <p style="font-size:0.8125rem;color:var(--ink-3);">Nexus matches on who you are, not just where you are. Music taste, discovery mode, and shared context define closeness &mdash; physical proximity is the starting point, not the ranking signal.</p>
                            </div>
                        </div>
                    </div>
                </div>
            </div>
        </section>

        <!-- ─────────────── FEATURES GRID ─────────────── -->
        <section id="features" class="section section-divider">
            <div class="reveal" style="text-align:center;max-width:42rem;margin:0 auto 3.5rem;">
                <h2 class="f-display" style="font-size:clamp(1.875rem,3.5vw,2.75rem);font-weight:800;line-height:1.12;letter-spacing:-0.025em;color:var(--ink-1);margin-bottom:0.875rem;">Every capability, transparent status.</h2>
                <p style="color:var(--ink-2);font-size:1rem;line-height:1.65;">No vague feature claims. Here's exactly what ships today, what's in beta, and what's on the roadmap.</p>
            </div>

            <div style="display:grid;grid-template-columns:repeat(auto-fit,minmax(280px,1fr));gap:1.25rem;">

                <!-- Feature 1: Spatial Radar -->
                <div class="glass glass-hover" style="padding:1.75rem;border-radius:1.25rem;display:flex;flex-direction:column;gap:1rem;" role="article">
                    <div style="display:flex;justify-content:space-between;align-items:flex-start;">
                        <div class="feat-icon" style="background:oklch(0.72 0.19 205 / 0.12);border-radius:0.875rem;">
                            <svg xmlns="http://www.w3.org/2000/svg" width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="oklch(0.72 0.19 205)" stroke-width="1.75" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><circle cx="12" cy="12" r="2"/><path d="M4.93 4.93 19.07 19.07"/><path d="M12 2a10 10 0 0 1 7.07 17.07"/><path d="M4.93 4.93A10 10 0 0 0 12 22"/></svg>
                        </div>
                        <span class="badge badge-live"><span class="beacon-dot pulse" aria-hidden="true"></span>LIVE</span>
                    </div>
                    <div>
                        <h3 style="font-family:var(--font-display);font-weight:700;font-size:1rem;color:var(--ink-1);margin-bottom:0.4rem;">2D Spatial Orbit Radar</h3>
                        <p style="font-size:0.8125rem;color:var(--ink-3);line-height:1.6;">Real-time proximity node positioning across 3 orbital tiers. Constellation-style lines connect nearby users. Canvas twinkling starfield behind every profile.</p>
                    </div>
                </div>

                <!-- Feature 2: Safety Center -->
                <div class="glass glass-hover glass-rose" style="padding:1.75rem;border-radius:1.25rem;display:flex;flex-direction:column;gap:1rem;" role="article">
                    <div style="display:flex;justify-content:space-between;align-items:flex-start;">
                        <div class="feat-icon" style="background:oklch(0.71 0.22 0 / 0.12);border-radius:0.875rem;">
                            <svg xmlns="http://www.w3.org/2000/svg" width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="oklch(0.71 0.22 0)" stroke-width="1.75" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M12 22s8-4 8-10V5l-8-3-8 3v7c0 6 8 10 8 10z"/></svg>
                        </div>
                        <span class="badge badge-rose"><span class="beacon-dot pulse" style="color:oklch(0.71 0.22 0);" aria-hidden="true"></span>LIVE</span>
                    </div>
                    <div>
                        <h3 style="font-family:var(--font-display);font-weight:700;font-size:1rem;color:var(--ink-1);margin-bottom:0.4rem;">Safety Center & Check-in Timers</h3>
                        <p style="font-size:0.8125rem;color:var(--ink-3);line-height:1.6;">Set a meetup timer with PIN disarm. If it expires unattended, Nexus dispatches emergency alerts and a live Web Portal link to your Emergency Contacts.</p>
                    </div>
                </div>

                <!-- Feature 3: Spotify Vibe -->
                <div class="glass glass-hover glass-green" style="padding:1.75rem;border-radius:1.25rem;display:flex;flex-direction:column;gap:1rem;" role="article">
                    <div style="display:flex;justify-content:space-between;align-items:flex-start;">
                        <div class="feat-icon" style="background:oklch(0.74 0.20 165 / 0.12);border-radius:0.875rem;">
                            <svg xmlns="http://www.w3.org/2000/svg" width="22" height="22" viewBox="0 0 496 512" fill="oklch(0.74 0.20 165)" aria-hidden="true"><path d="M248 8C111.1 8 8 111.1 8 248s103.1 240 240 240 240-103.1 240-240S384.9 8 248 8zm96.4 328.3c-3.8 5.8-11.5 7.5-17.4 3.7-47.6-29.1-107.5-35.7-178.1-19.5-6.7 1.5-13.4-2.8-14.9-9.5-1.5-6.7 2.8-13.4 9.5-14.9 77.1-17.6 143.3-10 196.4 22.5 5.9 3.8 7.5 11.5 3.7 17.4zm25.9-57.9c-4.7 7.3-14.7 9.5-21.9 4.8-54.5-33.5-137.6-43.2-202.1-23.6-8.3 2.5-17.1-2.2-19.6-10.5-2.5-8.3 2.2-17.1 10.5-19.6 73.6-22.3 165.2-11.5 227.4 26.9 7.2 4.6 9.4 14.7 4.7 21.9zm2.2-60.1c-65.4-38.8-173.3-42.4-235.7-23.5-9.9 3-20.3-2.5-23.3-12.4-3-9.9 2.5-20.3 12.4-23.3 71.6-21.7 190.6-17.5 265.7 27.1 8.9 5.3 11.9 16.8 6.6 25.7-5.3 8.9-16.8 11.8-25.7 6.4z"/></svg>
                        </div>
                        <span class="badge badge-beta"><span class="beacon-hex" aria-hidden="true"></span>BETA</span>
                    </div>
                    <div>
                        <h3 style="font-family:var(--font-display);font-weight:700;font-size:1rem;color:var(--ink-1);margin-bottom:0.4rem;">Spotify Vibe Synchronizer</h3>
                        <p style="font-size:0.8125rem;color:var(--ink-3);line-height:1.6;">OAuth2 top artists, top tracks, and current playback broadcast to your node. Mutual acoustic genre affinity vectors score 0-100% vibe compatibility with nearby users.</p>
                    </div>
                </div>

                <!-- Feature 4: E2EE Chat -->
                <div class="glass glass-hover glass-indigo" style="padding:1.75rem;border-radius:1.25rem;display:flex;flex-direction:column;gap:1rem;" role="article">
                    <div style="display:flex;justify-content:space-between;align-items:flex-start;">
                        <div class="feat-icon" style="background:oklch(0.68 0.20 280 / 0.12);border-radius:0.875rem;">
                            <svg xmlns="http://www.w3.org/2000/svg" width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="oklch(0.68 0.20 280)" stroke-width="1.75" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><rect width="18" height="11" x="3" y="11" rx="2" ry="2"/><path d="M7 11V7a5 5 0 0 1 10 0v4"/></svg>
                        </div>
                        <span class="badge badge-live"><span class="beacon-dot pulse" aria-hidden="true"></span>LIVE</span>
                    </div>
                    <div>
                        <h3 style="font-family:var(--font-display);font-weight:700;font-size:1rem;color:var(--ink-1);margin-bottom:0.4rem;">Pre-Key E2EE Messaging</h3>
                        <p style="font-size:0.8125rem;color:var(--ink-3);line-height:1.6;">Asymmetric ECDH prekey bundle exchange establishes per-session E2EE. Messages are encrypted on device, decrypted on device. The server never holds plaintext.</p>
                    </div>
                </div>

                <!-- Feature 5: Cross-campus -->
                <div class="glass glass-hover" style="padding:1.75rem;border-radius:1.25rem;display:flex;flex-direction:column;gap:1rem;" role="article">
                    <div style="display:flex;justify-content:space-between;align-items:flex-start;">
                        <div class="feat-icon" style="background:oklch(0.68 0.20 280 / 0.10);border-radius:0.875rem;">
                            <svg xmlns="http://www.w3.org/2000/svg" width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="oklch(0.68 0.20 280)" stroke-width="1.75" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><circle cx="12" cy="5" r="3"/><line x1="12" x2="12" y1="8" y2="21"/><line x1="9" x2="15" y1="21" y2="21"/><line x1="3" x2="21" y1="14" y2="14"/></svg>
                        </div>
                        <span class="badge badge-soon"><span class="beacon-orbit" aria-hidden="true"></span>COMING SOON</span>
                    </div>
                    <div>
                        <h3 style="font-family:var(--font-display);font-weight:700;font-size:1rem;color:var(--ink-1);margin-bottom:0.4rem;">Cross-Campus Global Orbit</h3>
                        <p style="font-size:0.8125rem;color:var(--ink-3);line-height:1.6;">Inter-university federation allowing multi-campus student communities to connect during athletic tournaments and cultural exchange events.</p>
                    </div>
                </div>

                <!-- Feature 6: Live Audio Rooms -->
                <div class="glass glass-hover" style="padding:1.75rem;border-radius:1.25rem;display:flex;flex-direction:column;gap:1rem;" role="article">
                    <div style="display:flex;justify-content:space-between;align-items:flex-start;">
                        <div class="feat-icon" style="background:oklch(0.55 0.012 265 / 0.25);border-radius:0.875rem;">
                            <svg xmlns="http://www.w3.org/2000/svg" width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="oklch(0.65 0.012 265)" stroke-width="1.75" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M12 1a3 3 0 0 0-3 3v8a3 3 0 0 0 6 0V4a3 3 0 0 0-3-3z"/><path d="M19 10v2a7 7 0 0 1-14 0v-2"/><line x1="12" x2="12" y1="19" y2="23"/><line x1="8" x2="16" y1="23" y2="23"/></svg>
                        </div>
                        <span class="badge badge-premium"><span class="beacon-hex" style="color:oklch(0.85 0.16 280);" aria-hidden="true"></span>NEXUS+</span>
                    </div>
                    <div>
                        <h3 style="font-family:var(--font-display);font-weight:700;font-size:1rem;color:var(--ink-1);margin-bottom:0.4rem;">Live Vibe Audio Rooms</h3>
                        <p style="font-size:0.8125rem;color:var(--ink-3);line-height:1.6;">Synchronized group music listening lounges with proximity-based spatial voice channels - ephemeral, ambient, social. Nexus+ premium.</p>
                    </div>
                </div>
            </div>
        </section>

        <!-- ─────────────── SPOTIFY SECTION ─────────────── -->
        <section id="spotify" class="section section-divider">
            <div class="grid-2col">

                <!-- Copy -->
                <div class="reveal" style="display:flex;flex-direction:column;gap:1.25rem;order:1;">
                    <div class="badge badge-beta" style="align-self:flex-start;font-size:0.7rem;padding:0.4rem 0.9rem;border-radius:0.6rem;"><span class="beacon-hex" aria-hidden="true"></span>SPOTIFY INTEGRATION · BETA</div>
                    <h2 class="f-display" style="font-size:clamp(1.875rem,3.5vw,2.875rem);font-weight:800;line-height:1.1;letter-spacing:-0.025em;color:var(--ink-1);text-wrap:balance;">
                        Music taste as a genuine first impression.
                    </h2>
                    <p style="font-size:1rem;color:var(--ink-2);line-height:1.7;max-width:46ch;">
                        Every conversation needs a way in. Nexus authenticates with Spotify so your top artists and currently-playing song appear on your orbit node - visible to anyone you're near who shares taste.
                    </p>
                    <ul style="display:flex;flex-direction:column;gap:0.75rem;">
                        <li style="display:flex;align-items:flex-start;gap:0.75rem;font-size:0.875rem;color:var(--ink-2);">
                            <svg xmlns="http://www.w3.org/2000/svg" width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="oklch(0.74 0.20 165)" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true" style="flex-shrink:0;margin-top:2px;"><path d="M22 11.08V12a10 10 0 1 1-5.93-9.14"/><path d="m9 11 3 3L22 4"/></svg>
                            <span>Spotify OAuth2 connects in one tap - no manual input</span>
                        </li>
                        <li style="display:flex;align-items:flex-start;gap:0.75rem;font-size:0.875rem;color:var(--ink-2);">
                            <svg xmlns="http://www.w3.org/2000/svg" width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="oklch(0.74 0.20 165)" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true" style="flex-shrink:0;margin-top:2px;"><path d="M22 11.08V12a10 10 0 1 1-5.93-9.14"/><path d="m9 11 3 3L22 4"/></svg>
                            <span>Acoustic genre vector scoring produces a 0-100% mutual vibe affinity</span>
                        </li>
                        <li style="display:flex;align-items:flex-start;gap:0.75rem;font-size:0.875rem;color:var(--ink-2);">
                            <svg xmlns="http://www.w3.org/2000/svg" width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="oklch(0.74 0.20 165)" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true" style="flex-shrink:0;margin-top:2px;"><path d="M22 11.08V12a10 10 0 1 1-5.93-9.14"/><path d="m9 11 3 3L22 4"/></svg>
                            <span>Shared top artists & current track visible as orbit node detail</span>
                        </li>
                    </ul>
                </div>

                <!-- Visual: Spotify card -->
                <div class="reveal" style="order:2;">
                    <div class="glass glass-green" style="padding:2rem;border-radius:1.5rem;display:flex;flex-direction:column;gap:1.5rem;">
                        <div style="display:flex;align-items:center;justify-content:space-between;padding-bottom:1.25rem;border-bottom:1px solid oklch(0.74 0.20 165 / 0.20);">
                            <div style="display:flex;align-items:center;gap:0.875rem;">
                                <div style="width:2.75rem;height:2.75rem;border-radius:0.875rem;background:oklch(0.74 0.20 165 / 0.15);display:flex;align-items:center;justify-content:center;">
                                    <svg xmlns="http://www.w3.org/2000/svg" width="22" height="22" viewBox="0 0 496 512" fill="oklch(0.74 0.20 165)" aria-hidden="true"><path d="M248 8C111.1 8 8 111.1 8 248s103.1 240 240 240 240-103.1 240-240S384.9 8 248 8zm96.4 328.3c-3.8 5.8-11.5 7.5-17.4 3.7-47.6-29.1-107.5-35.7-178.1-19.5-6.7 1.5-13.4-2.8-14.9-9.5-1.5-6.7 2.8-13.4 9.5-14.9 77.1-17.6 143.3-10 196.4 22.5 5.9 3.8 7.5 11.5 3.7 17.4zm25.9-57.9c-4.7 7.3-14.7 9.5-21.9 4.8-54.5-33.5-137.6-43.2-202.1-23.6-8.3 2.5-17.1-2.2-19.6-10.5-2.5-8.3 2.2-17.1 10.5-19.6 73.6-22.3 165.2-11.5 227.4 26.9 7.2 4.6 9.4 14.7 4.7 21.9zm2.2-60.1c-65.4-38.8-173.3-42.4-235.7-23.5-9.9 3-20.3-2.5-23.3-12.4-3-9.9 2.5-20.3 12.4-23.3 71.6-21.7 190.6-17.5 265.7 27.1 8.9 5.3 11.9 16.8 6.6 25.7-5.3 8.9-16.8 11.8-25.7 6.4z"/></svg>
                                </div>
                                <div>
                                    <p style="font-weight:700;color:var(--ink-1);font-size:0.9rem;">Active Vibe Sync</p>
                                    <p style="font-size:0.75rem;color:var(--ink-3);">OAuth2 token connected</p>
                                </div>
                            </div>
                            <span class="badge badge-beta" style="font-size:0.65rem;padding:0.25rem 0.6rem;border-radius:0.4rem;"><span class="beacon-hex" aria-hidden="true"></span>94% VIBE MATCH</span>
                        </div>

                        <div>
                            <p class="f-mono" style="font-size:0.65rem;color:var(--ink-3);letter-spacing:0.08em;margin-bottom:0.625rem;">SHARED TOP ARTISTS</p>
                            <div style="display:flex;flex-wrap:wrap;gap:0.5rem;">
                                <span style="padding:0.3rem 0.75rem;background:oklch(0.16 0.024 265);border:1px solid oklch(0.24 0.022 265);border-radius:999px;font-size:0.78rem;color:var(--ink-2);">The Weeknd</span>
                                <span style="padding:0.3rem 0.75rem;background:oklch(0.16 0.024 265);border:1px solid oklch(0.24 0.022 265);border-radius:999px;font-size:0.78rem;color:var(--ink-2);">Frank Ocean</span>
                                <span style="padding:0.3rem 0.75rem;background:oklch(0.16 0.024 265);border:1px solid oklch(0.24 0.022 265);border-radius:999px;font-size:0.78rem;color:var(--ink-2);">Tame Impala</span>
                                <span style="padding:0.3rem 0.75rem;background:oklch(0.16 0.024 265);border:1px solid oklch(0.24 0.022 265);border-radius:999px;font-size:0.78rem;color:var(--ink-2);">Kaye</span>
                            </div>
                        </div>

                        <div style="padding:1rem 1.25rem;background:oklch(0.09 0.020 265);border-radius:1rem;border:1px solid oklch(0.20 0.020 265);display:flex;align-items:center;justify-content:space-between;gap:1rem;">
                            <div style="display:flex;align-items:center;gap:0.875rem;">
                                <svg xmlns="http://www.w3.org/2000/svg" width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="oklch(0.74 0.20 165)" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M9 18V5l12-2v13"/><circle cx="6" cy="18" r="3"/><circle cx="18" cy="16" r="3"/></svg>
                                <div>
                                    <p style="font-weight:700;color:var(--ink-1);font-size:0.825rem;">Starboy (feat. Daft Punk)</p>
                                    <p style="font-size:0.7rem;color:var(--ink-3);">Currently playing · The Weeknd</p>
                                </div>
                            </div>
                            <div style="display:flex;align-items:flex-end;gap:2px;height:1.25rem;" aria-hidden="true">
                                <div class="bar-1" style="width:3px;background:oklch(0.74 0.20 165);border-radius:2px;min-height:6px;"></div>
                                <div class="bar-2" style="width:3px;background:oklch(0.74 0.20 165);border-radius:2px;min-height:6px;"></div>
                                <div class="bar-3" style="width:3px;background:oklch(0.74 0.20 165);border-radius:2px;min-height:6px;"></div>
                                <div class="bar-4" style="width:3px;background:oklch(0.74 0.20 165);border-radius:2px;min-height:6px;"></div>
                            </div>
                        </div>
                    </div>
                </div>
            </div>
        </section>

        <!-- ─────────────── SAFETY SECTION ─────────────── -->
        <section id="safety" class="section section-divider">
            <div class="grid-2col">

                <!-- Visual: Check-in timer sandbox -->
                <div class="reveal" style="order:2;">
                    <div class="glass glass-rose" style="padding:2rem;border-radius:1.5rem;display:flex;flex-direction:column;gap:1.5rem;">
                        <div style="display:flex;align-items:center;justify-content:space-between;padding-bottom:1.25rem;border-bottom:1px solid oklch(0.71 0.22 0 / 0.20);">
                            <div style="display:flex;align-items:center;gap:0.875rem;">
                                <div style="width:2.75rem;height:2.75rem;border-radius:0.875rem;background:oklch(0.71 0.22 0 / 0.15);display:flex;align-items:center;justify-content:center;">
                                    <svg xmlns="http://www.w3.org/2000/svg" width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="oklch(0.71 0.22 0)" stroke-width="1.75" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M12 22s8-4 8-10V5l-8-3-8 3v7c0 6 8 10 8 10z"/></svg>
                                </div>
                                <div>
                                    <p style="font-weight:700;color:var(--ink-1);font-size:0.9rem;">Meetup Check-in Timer</p>
                                    <p style="font-size:0.75rem;color:var(--ink-3);">Interactive safety sandbox</p>
                                </div>
                            </div>
                            <span id="timer-status-badge" class="badge badge-rose" style="font-size:0.65rem;padding:0.3rem 0.7rem;border-radius:0.4rem;"><span class="beacon-dot pulse" style="color:oklch(0.71 0.22 0);" aria-hidden="true"></span>Disarmed</span>
                        </div>

                        <div style="text-align:center;display:flex;flex-direction:column;gap:1rem;">
                            <p style="font-size:0.8125rem;color:var(--ink-3);">Test the real check-in timer. Start a 10-second countdown - if not disarmed, alerts fire.</p>
                            <div class="f-mono" id="timer-display" style="font-size:3rem;font-weight:700;color:var(--ink-1);letter-spacing:0.05em;">00:10</div>

                            <!-- SVG Safety ring -->
                            <svg width="90" height="90" viewBox="0 0 90 90" style="margin:0 auto;" aria-hidden="true">
                                <defs>
                                    <linearGradient id="safetyGrad" x1="0%" y1="0%" x2="100%" y2="100%">
                                        <stop offset="0%" stop-color="oklch(0.74 0.20 165)"/>
                                        <stop offset="100%" stop-color="oklch(0.71 0.22 0)"/>
                                    </linearGradient>
                                </defs>
                                <circle cx="45" cy="45" r="40" class="safety-ring-track"/>
                                <circle id="safety-ring" cx="45" cy="45" r="40" class="safety-ring-fill"/>
                            </svg>

                            <div style="display:flex;justify-content:center;gap:0.75rem;flex-wrap:wrap;">
                                <button id="start-timer-btn" onclick="startTestTimer()"
                                        style="padding:0.6rem 1.25rem;background:oklch(0.71 0.22 0);border:none;border-radius:0.875rem;font-family:var(--font-display);font-weight:700;font-size:0.8125rem;color:oklch(0.08 0.01 0);cursor:pointer;transition:opacity 0.15s;"
                                        onmouseover="this.style.opacity='0.85'" onmouseout="this.style.opacity='1'">
                                    Start 10s Timer
                                </button>
                                <button id="disarm-timer-btn" onclick="disarmTestTimer()"
                                        class="btn-ghost !py-2.5 !px-5 !text-sm !rounded-2xl">
                                    Disarm PIN
                                </button>
                            </div>
                        </div>

                        <div id="portal-alert-box" style="display:none;padding:1rem;background:oklch(0.09 0.020 265);border-radius:1rem;border:1px solid oklch(0.24 0.022 265);">
                            <p style="color:oklch(0.75 0.18 0);font-weight:700;font-size:0.8125rem;margin-bottom:0.5rem;display:flex;align-items:center;gap:0.5rem;">
                                <svg xmlns="http://www.w3.org/2000/svg" width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="m21.73 18-8-14a2 2 0 0 0-3.48 0l-8 14A2 2 0 0 0 4 21h16a2 2 0 0 0 1.73-3z"/><line x1="12" x2="12.01" y1="9" y2="13"/><line x1="12" x2="12.01" y1="17" y2="17"/></svg>
                                Emergency check-in triggered!
                            </p>
                            <p style="font-size:0.75rem;color:var(--ink-3);margin-bottom:0.5rem;">Alert dispatched to 2 Emergency Contacts with Web Portal link:</p>
                            <code class="f-mono" style="display:block;font-size:0.7rem;color:oklch(0.72 0.19 205);background:oklch(0.07 0.018 265);padding:0.5rem 0.75rem;border-radius:0.5rem;border:1px solid oklch(0.18 0.020 265);word-break:break-all;white-space:normal;">
                                https://nexus-engine.app/safety/portal/alert-8f92k3
                            </code>
                        </div>
                    </div>
                </div>

                <!-- Copy -->
                <div class="reveal" style="display:flex;flex-direction:column;gap:1.25rem;order:1;">
                    <div class="badge badge-rose" style="align-self:flex-start;font-size:0.7rem;padding:0.4rem 0.9rem;border-radius:0.6rem;"><span class="beacon-dot pulse" style="color:oklch(0.71 0.22 0);" aria-hidden="true"></span>SAFETY CENTER - LIVE</div>
                    <h2 class="f-display" style="font-size:clamp(1.875rem,3.5vw,2.875rem);font-weight:800;line-height:1.1;letter-spacing:-0.025em;color:var(--ink-1);text-wrap:balance;">
                        Safety is core surface, not a footnote.
                    </h2>
                    <p style="font-size:1rem;color:var(--ink-2);line-height:1.7;max-width:46ch;">
                        Nexus ships a dedicated Safety Center - not a buried settings page. In-person meetups require real protection: automated timers, emergency contacts, crisis helplines, and a live Web Portal that updates in real time.
                    </p>
                    <div style="display:flex;flex-direction:column;gap:0.75rem;">
                        <div style="display:flex;align-items:flex-start;gap:0.75rem;font-size:0.875rem;color:var(--ink-2);">
                            <svg xmlns="http://www.w3.org/2000/svg" width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="oklch(0.71 0.22 0)" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true" style="flex-shrink:0;margin-top:2px;"><path d="M22 11.08V12a10 10 0 1 1-5.93-9.14"/><path d="m9 11 3 3L22 4"/></svg>
                            <span>Meetup timer with PIN disarm - auto-alerts if you don't check in</span>
                        </div>
                        <div style="display:flex;align-items:flex-start;gap:0.75rem;font-size:0.875rem;color:var(--ink-2);">
                            <svg xmlns="http://www.w3.org/2000/svg" width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="oklch(0.71 0.22 0)" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true" style="flex-shrink:0;margin-top:2px;"><path d="M22 11.08V12a10 10 0 1 1-5.93-9.14"/><path d="m9 11 3 3L22 4"/></svg>
                            <span>Live Safety Web Portal - shareable emergency link</span>
                        </div>
                        <div style="display:flex;align-items:flex-start;gap:0.75rem;font-size:0.875rem;color:var(--ink-2);">
                            <svg xmlns="http://www.w3.org/2000/svg" width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="oklch(0.71 0.22 0)" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true" style="flex-shrink:0;margin-top:2px;"><path d="M22 11.08V12a10 10 0 1 1-5.93-9.14"/><path d="m9 11 3 3L22 4"/></svg>
                            <span>Pre-meetup safety checklists + crisis helpline directory</span>
                        </div>
                        <div style="display:flex;align-items:flex-start;gap:0.75rem;font-size:0.875rem;color:var(--ink-2);">
                            <svg xmlns="http://www.w3.org/2000/svg" width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="oklch(0.71 0.22 0)" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true" style="flex-shrink:0;margin-top:2px;"><path d="M22 11.08V12a10 10 0 1 1-5.93-9.14"/><path d="m9 11 3 3L22 4"/></svg>
                            <span>Ghost mode - instantly vanish from orbit discovery without logging out</span>
                        </div>
                    </div>
                </div>
            </div>
        </section>

        <!-- ─────────────── DISCOVERY MODES ─────────────── -->
        <section id="modes" class="section section-divider">
            <div class="reveal" style="text-align:center;max-width:40rem;margin:0 auto 2.5rem;">
                <h2 class="f-display" style="font-size:clamp(1.875rem,3.5vw,2.75rem);font-weight:800;line-height:1.12;letter-spacing:-0.025em;color:var(--ink-1);margin-bottom:0.875rem;">One app. Three discovery modes.</h2>
                <p style="color:var(--ink-2);font-size:1rem;line-height:1.65;">Nexus is not a dating app. You set the context - and every mode gets its own visual signal colour so the UI always reflects your intent.</p>
            </div>

            <div class="reveal" style="display:flex;justify-content:center;gap:0.5rem;flex-wrap:wrap;margin-bottom:2.5rem;" role="tablist">
                <button class="mode-tab active-dating" id="tab-dating" onclick="switchMode('dating')" role="tab" aria-selected="true" aria-controls="mode-panel">
                    <svg xmlns="http://www.w3.org/2000/svg" width="14" height="14" viewBox="0 0 24 24" fill="currentColor" aria-hidden="true"><path d="M20.84 4.61a5.5 5.5 0 0 0-7.78 0L12 5.67l-1.06-1.06a5.5 5.5 0 0 0-7.78 7.78l1.06 1.06L12 21.23l7.78-7.78 1.06-1.06a5.5 5.5 0 0 0 0-7.78z"/></svg>
                    Dating & Romance
                </button>
                <button class="mode-tab" id="tab-friends" onclick="switchMode('friends')" role="tab" aria-selected="false" aria-controls="mode-panel">
                    <svg xmlns="http://www.w3.org/2000/svg" width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M17 21v-2a4 4 0 0 0-4-4H5a4 4 0 0 0-4 4v2"/><circle cx="9" cy="7" r="4"/><path d="M23 21v-2a4 4 0 0 0-3-3.87"/><path d="M16 3.13a4 4 0 0 1 0 7.75"/></svg>
                    Friends & Social
                </button>
                <button class="mode-tab" id="tab-pro" onclick="switchMode('pro')" role="tab" aria-selected="false" aria-controls="mode-panel">
                    <svg xmlns="http://www.w3.org/2000/svg" width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><rect width="20" height="14" x="2" y="7" rx="2" ry="2"/><path d="M16 21V5a2 2 0 0 0-2-2h-4a2 2 0 0 0-2 2v16"/></svg>
                    Professional
                </button>
            </div>

            <div id="mode-panel" role="tabpanel" class="reveal glass" style="padding:2rem;border-radius:1.5rem;max-width:680px;margin:0 auto;">
                <div id="mode-content-dating">
                    <div style="display:flex;align-items:center;gap:0.875rem;margin-bottom:1.25rem;">
                        <div style="width:2.5rem;height:2.5rem;border-radius:50%;background:oklch(0.71 0.22 0 / 0.15);border:1px solid oklch(0.71 0.22 0 / 0.35);display:flex;align-items:center;justify-content:center;">
                            <svg xmlns="http://www.w3.org/2000/svg" width="18" height="18" viewBox="0 0 24 24" fill="oklch(0.71 0.22 0)" aria-hidden="true"><path d="M20.84 4.61a5.5 5.5 0 0 0-7.78 0L12 5.67l-1.06-1.06a5.5 5.5 0 0 0-7.78 7.78l1.06 1.06L12 21.23l7.78-7.78 1.06-1.06a5.5 5.5 0 0 0 0-7.78z"/></svg>
                        </div>
                        <div>
                            <p class="f-display" style="font-weight:700;color:var(--ink-1);">Dating & Romance Mode</p>
                            <p class="f-mono" style="font-size:0.65rem;color:oklch(0.75 0.18 0);letter-spacing:0.08em;">SIGNAL: PULSAR PINK · #FF7597</p>
                        </div>
                    </div>
                    <p style="font-size:0.9rem;color:var(--ink-2);line-height:1.7;">Browse potential romantic connections within your real orbit. Orbit nodes glow Pulsar Pink. Conversation is designed to feel natural - shared music, proximity, and real-world context as the opener, not a photo and a bio blurb.</p>
                </div>
                <div id="mode-content-friends" style="display:none;">
                    <div style="display:flex;align-items:center;gap:0.875rem;margin-bottom:1.25rem;">
                        <div style="width:2.5rem;height:2.5rem;border-radius:50%;background:oklch(0.74 0.20 165 / 0.15);border:1px solid oklch(0.74 0.20 165 / 0.35);display:flex;align-items:center;justify-content:center;">
                            <svg xmlns="http://www.w3.org/2000/svg" width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="oklch(0.74 0.20 165)" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M17 21v-2a4 4 0 0 0-4-4H5a4 4 0 0 0-4 4v2"/><circle cx="9" cy="7" r="4"/><path d="M23 21v-2a4 4 0 0 0-3-3.87"/><path d="M16 3.13a4 4 0 0 1 0 7.75"/></svg>
                        </div>
                        <div>
                            <p class="f-display" style="font-weight:700;color:var(--ink-1);">Friends & Social Mode</p>
                            <p class="f-mono" style="font-size:0.65rem;color:oklch(0.74 0.20 165);letter-spacing:0.08em;">SIGNAL: AURORA GREEN</p>
                        </div>
                    </div>
                    <p style="font-size:0.9rem;color:var(--ink-2);line-height:1.7;">Find study partners, event companions, music buddies, or just new people to hang with. Orbit nodes glow Aurora Green. No romantic framing - ideal for campus communities where you want broader social discovery.</p>
                </div>
                <div id="mode-content-pro" style="display:none;">
                    <div style="display:flex;align-items:center;gap:0.875rem;margin-bottom:1.25rem;">
                        <div style="width:2.5rem;height:2.5rem;border-radius:50%;background:oklch(0.68 0.20 280 / 0.15);border:1px solid oklch(0.68 0.20 280 / 0.35);display:flex;align-items:center;justify-content:center;">
                            <svg xmlns="http://www.w3.org/2000/svg" width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="oklch(0.68 0.20 280)" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><rect width="20" height="14" x="2" y="7" rx="2" ry="2"/><path d="M16 21V5a2 2 0 0 0-2-2h-4a2 2 0 0 0-2 2v16"/></svg>
                        </div>
                        <div>
                            <p class="f-display" style="font-weight:700;color:var(--ink-1);">Professional Mode</p>
                            <p class="f-mono" style="font-size:0.65rem;color:oklch(0.68 0.20 280);letter-spacing:0.08em;">SIGNAL: NEBULA INDIGO</p>
                        </div>
                    </div>
                    <p style="font-size:0.9rem;color:var(--ink-2);line-height:1.7;">Discover co-founders, collaborators, and industry peers at conferences or co-working spaces. Orbit nodes glow Nebula Indigo. Professional context is broadcast clearly on your node - no mixed signals.</p>
                </div>
            </div>
        </section>

        <!-- ─────────────── CAMPUS ─────────────── -->
        <section id="campus" class="section section-divider">
            <div class="reveal" style="text-align:center;max-width:42rem;margin:0 auto 3rem;">
                <h2 class="f-display" style="font-size:clamp(1.875rem,3.5vw,2.75rem);font-weight:800;line-height:1.12;letter-spacing:-0.025em;color:var(--ink-1);margin-bottom:0.875rem;">One codebase. Two orbit contexts.</h2>
                <p style="color:var(--ink-2);font-size:1rem;line-height:1.65;">Nexus ships two variants from a single unified backend and Flutter codebase. Same design language, same features - different identity verification gates.</p>
            </div>

            <div style="display:grid;grid-template-columns:repeat(auto-fit,minmax(280px,1fr));gap:1.5rem;">

                <!-- Nexus General -->
                <div class="glass glass-hover reveal" style="padding:2rem;border-radius:1.5rem;display:flex;flex-direction:column;gap:1.25rem;">
                    <div style="display:flex;justify-content:space-between;align-items:flex-start;">
                        <div style="width:3rem;height:3rem;border-radius:1rem;background:oklch(0.72 0.19 205 / 0.12);border:1px solid oklch(0.72 0.19 205 / 0.25);display:flex;align-items:center;justify-content:center;">
                            <svg xmlns="http://www.w3.org/2000/svg" width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="oklch(0.72 0.19 205)" stroke-width="1.75" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><circle cx="12" cy="12" r="10"/><line x1="2" x2="22" y1="12" y2="12"/><path d="M12 2a15.3 15.3 0 0 1 4 10 15.3 15.3 0 0 1-4 10 15.3 15.3 0 0 1-4-10 15.3 15.3 0 0 1 4-10z"/></svg>
                        </div>
                        <span class="badge badge-soon"><span class="beacon-orbit" aria-hidden="true"></span>COMING SOON</span>
                    </div>
                    <div>
                        <h3 class="f-display" style="font-size:1.25rem;font-weight:700;color:var(--ink-1);margin-bottom:0.5rem;">Nexus</h3>
                        <code class="f-mono" style="font-size:0.7rem;color:oklch(0.72 0.19 205);background:oklch(0.72 0.19 205 / 0.08);padding:0.2rem 0.5rem;border-radius:0.375rem;display:inline-block;margin-bottom:0.875rem;">com.devakesu.apps.nexus</code>
                        <p style="font-size:0.875rem;color:var(--ink-3);line-height:1.65;">Open discovery for any valid email domain. Find connections in your city, at events, or anywhere your orbit takes you. Currently in pre-launch on Play Store.</p>
                    </div>
                    <a href="https://play.google.com/store/apps/details?id=com.devakesu.apps.nexus"
                    target="_blank" rel="noopener noreferrer"
                    class="footer-link" style="display:inline-flex;align-items:center;gap:0.4rem;font-size:0.8125rem;font-weight:600;color:oklch(0.72 0.19 205);">
                        Preview on Play Store
                        <svg xmlns="http://www.w3.org/2000/svg" width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M5 12h14"/><path d="m12 5 7 7-7 7"/></svg>
                    </a>
                </div>

                <!-- Nexus MEC -->
                <div class="glass glass-hover glass-amber reveal" style="padding:2rem;border-radius:1.5rem;display:flex;flex-direction:column;gap:1.25rem;" style="transition-delay:0.1s">
                    <div style="display:flex;justify-content:space-between;align-items:flex-start;">
                        <div style="width:3rem;height:3rem;border-radius:1rem;background:oklch(0.78 0.20 85 / 0.12);border:1px solid oklch(0.78 0.20 85 / 0.25);display:flex;align-items:center;justify-content:center;">
                            <svg xmlns="http://www.w3.org/2000/svg" width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="oklch(0.78 0.20 85)" stroke-width="1.75" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M22 10v6M2 10l10-5 10 5-10 5z"/><path d="M6 12v5c3 3 9 3 12 0v-5"/></svg>
                        </div>
                        <span class="badge badge-campus"><span class="beacon-dot pulse" style="color:oklch(0.78 0.20 85);" aria-hidden="true"></span>CAMPUS LIVE</span>
                    </div>
                    <div>
                        <h3 class="f-display" style="font-size:1.25rem;font-weight:700;color:var(--ink-1);margin-bottom:0.5rem;">Nexus MEC - Campus Verified</h3>
                        <code class="f-mono" style="font-size:0.7rem;color:oklch(0.78 0.20 85);background:oklch(0.78 0.20 85 / 0.08);padding:0.2rem 0.5rem;border-radius:0.375rem;display:inline-block;margin-bottom:0.875rem;">com.devakesu.apps.nexus.mec</code>
                        <p style="font-size:0.875rem;color:var(--ink-3);line-height:1.65;">Signup strictly gated to verified <code class="f-mono" style="font-size:0.75rem;color:oklch(0.78 0.20 85);">@mec.ac.in</code> student email domains. Discover study peers, campus events, and genuine connections inside your university community.</p>
                    </div>
                    <a href="https://play.google.com/store/apps/details?id=com.devakesu.apps.nexus.mec"
                    target="_blank" rel="noopener noreferrer"
                    class="btn-primary btn-campus" style="align-self:flex-start;!py-2.5 !px-5 !text-sm">
                        <svg xmlns="http://www.w3.org/2000/svg" width="16" height="16" viewBox="0 0 24 24" fill="currentColor" aria-hidden="true"><path d="M3.18 23.5a1.5 1.5 0 0 1-.94-1.41V1.91A1.5 1.5 0 0 1 3.18.5l11.52 11.52zm1.32-20.1v17.2l9.26-8.6zM21.32 13.5l-2.88 1.66-2.88-2.88 2.88-2.88 2.88 1.66a1.5 1.5 0 0 1 0 2.44zM3.18.5l11.52 11.52-2.88 2.88L3.18.5z"/></svg>
                        Get on Google Play
                    </a>
                </div>
            </div>
        </section>

        <!-- ─────────────── HOW IT WORKS ─────────────── -->
        <section id="how" class="section section-divider">
            <div class="reveal" style="text-align:center;max-width:38rem;margin:0 auto 3.5rem;">
                <h2 class="f-display" style="font-size:clamp(1.875rem,3.5vw,2.75rem);font-weight:800;line-height:1.12;letter-spacing:-0.025em;color:var(--ink-1);margin-bottom:0.875rem;">From install to orbit in minutes.</h2>
                <p style="color:var(--ink-2);font-size:1rem;line-height:1.65;">No algorithm deciding who you should meet. You appear on nearby people's radars. They appear on yours. Natural, ambient, real.</p>
            </div>

            <div class="how-grid">
                <div class="glass glass-hover reveal" style="padding:1.75rem;border-radius:1.25rem;display:flex;flex-direction:column;gap:1rem;">
                    <div class="step-num">1</div>
                    <h3 class="f-display" style="font-weight:700;color:var(--ink-1);font-size:0.9375rem;">Download & Verify</h3>
                    <p style="font-size:0.8125rem;color:var(--ink-3);line-height:1.6;">Install Nexus from Google Play. Sign up with your email address - verified securely via OTP. Your identity is active in seconds.</p>
                </div>
                <div class="glass glass-hover reveal" style="padding:1.75rem;border-radius:1.25rem;display:flex;flex-direction:column;gap:1rem;" style="transition-delay:0.1s">
                    <div class="step-num">2</div>
                    <h3 class="f-display" style="font-weight:700;color:var(--ink-1);font-size:0.9375rem;">Build Your Profile</h3>
                    <p style="font-size:0.8125rem;color:var(--ink-3);line-height:1.6;">Add photos, write a short bio, connect Spotify for vibe sync. Choose your discovery mode and set your orbit radius - from 50m to 500m.</p>
                </div>
                <div class="glass glass-hover reveal" style="padding:1.75rem;border-radius:1.25rem;display:flex;flex-direction:column;gap:1rem;" style="transition-delay:0.2s">
                    <div class="step-num">3</div>
                    <h3 class="f-display" style="font-weight:700;color:var(--ink-1);font-size:0.9375rem;">Open the Orbit Radar</h3>
                    <p style="font-size:0.8125rem;color:var(--ink-3);line-height:1.6;">Your radar populates in real time. Nearby users appear as orbit nodes - colour-coded by mode, with music taste and distance shown on each node.</p>
                </div>
                <div class="glass glass-hover reveal" style="padding:1.75rem;border-radius:1.25rem;display:flex;flex-direction:column;gap:1rem;" style="transition-delay:0.3s">
                    <div class="step-num">4</div>
                    <h3 class="f-display" style="font-weight:700;color:var(--ink-1);font-size:0.9375rem;">Connect & Meet Safely</h3>
                    <p style="font-size:0.8125rem;color:var(--ink-3);line-height:1.6;">Like a profile, match, send E2EE messages. Before meeting in person, arm your Check-in Timer. Stay safe - the Safety Center has your back if anything goes wrong.</p>
                </div>
            </div>
        </section>

        <!-- ─────────────── PRIVACY ─────────────── -->
        <section id="privacy" class="section section-divider">
            <div class="reveal" style="text-align:center;max-width:42rem;margin:0 auto 3rem;">
                <h2 class="f-display" style="font-size:clamp(1.875rem,3.5vw,2.75rem);font-weight:800;line-height:1.12;letter-spacing:-0.025em;color:var(--ink-1);margin-bottom:0.875rem;">You own your data. Completely.</h2>
                <p style="color:var(--ink-2);font-size:1rem;line-height:1.65;">Nexus gives you granular controls - not buried settings, not dark patterns. Privacy is a first-class feature.</p>
            </div>

            <div class="privacy-grid">
                <div class="glass glass-hover reveal" style="padding:1.5rem;border-radius:1.25rem;display:flex;gap:1rem;align-items:flex-start;">
                    <div class="feat-icon" style="background:oklch(0.72 0.19 205 / 0.10);border-radius:0.75rem;flex-shrink:0;">
                        <svg xmlns="http://www.w3.org/2000/svg" width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="oklch(0.72 0.19 205)" stroke-width="1.75" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M17.94 17.94A10.07 10.07 0 0 1 12 20c-7 0-11-8-11-8a18.45 18.45 0 0 1 5.06-5.94"/><path d="M9.9 4.24A9.12 9.12 0 0 1 12 4c7 0 11 8 11 8a18.5 18.5 0 0 1-2.16 3.19"/><line x1="1" x2="23" y1="1" y2="23"/></svg>
                    </div>
                    <div>
                        <h3 style="font-family:var(--font-display);font-weight:700;font-size:0.9rem;color:var(--ink-1);margin-bottom:0.3rem;">Ghost Mode</h3>
                        <p style="font-size:0.8rem;color:var(--ink-3);line-height:1.55;">Instantly hide from all orbit discovery while keeping existing chats open. One toggle.</p>
                    </div>
                </div>

                <div class="glass glass-hover reveal" style="padding:1.5rem;border-radius:1.25rem;display:flex;gap:1rem;align-items:flex-start;" style="transition-delay:0.1s">
                    <div class="feat-icon" style="background:oklch(0.68 0.20 280 / 0.10);border-radius:0.75rem;flex-shrink:0;">
                        <svg xmlns="http://www.w3.org/2000/svg" width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="oklch(0.68 0.20 280)" stroke-width="1.75" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><rect width="18" height="11" x="3" y="11" rx="2" ry="2"/><path d="M7 11V7a5 5 0 0 1 10 0v4"/></svg>
                    </div>
                    <div>
                        <h3 style="font-family:var(--font-display);font-weight:700;font-size:0.9rem;color:var(--ink-1);margin-bottom:0.3rem;">Pre-Key E2EE Chat</h3>
                        <p style="font-size:0.8rem;color:var(--ink-3);line-height:1.55;">ECDH prekey bundle encryption. The server stores ciphertext only. Plaintext never leaves your device.</p>
                    </div>
                </div>

                <div class="glass glass-hover reveal" style="padding:1.5rem;border-radius:1.25rem;display:flex;gap:1rem;align-items:flex-start;">
                    <div class="feat-icon" style="background:oklch(0.78 0.20 85 / 0.10);border-radius:0.75rem;flex-shrink:0;">
                        <svg xmlns="http://www.w3.org/2000/svg" width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="oklch(0.78 0.20 85)" stroke-width="1.75" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><circle cx="12" cy="12" r="10"/><path d="M12 8v4"/><path d="M12 16h.01"/></svg>
                    </div>
                    <div>
                        <h3 style="font-family:var(--font-display);font-weight:700;font-size:0.9rem;color:var(--ink-1);margin-bottom:0.3rem;">Mode-Scoped Visibility</h3>
                        <p style="font-size:0.8rem;color:var(--ink-3);line-height:1.55;">Your orbit node is only visible to people in the same discovery mode. Dating mode stays separate from Friends &mdash; no accidental cross-mode exposure.</p>
                    </div>
                </div>

                <div class="glass glass-hover reveal" style="padding:1.5rem;border-radius:1.25rem;display:flex;gap:1rem;align-items:flex-start;" style="transition-delay:0.3s">
                    <div class="feat-icon" style="background:oklch(0.74 0.20 165 / 0.10);border-radius:0.75rem;flex-shrink:0;">
                        <svg xmlns="http://www.w3.org/2000/svg" width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="oklch(0.74 0.20 165)" stroke-width="1.75" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4"/><polyline points="7 10 12 15 17 10"/><line x1="12" x2="12" y1="15" y2="3"/></svg>
                    </div>
                    <div>
                        <h3 style="font-family:var(--font-display);font-weight:700;font-size:0.9rem;color:var(--ink-1);margin-bottom:0.3rem;">GDPR Data Export</h3>
                        <p style="font-size:0.8rem;color:var(--ink-3);line-height:1.55;">Download a full JSON archive of your account data at any time.</p>
                    </div>
                </div>

                <div class="glass glass-hover reveal" style="padding:1.5rem;border-radius:1.25rem;display:flex;gap:1rem;align-items:flex-start;" style="transition-delay:0.4s">
                    <div class="feat-icon" style="background:oklch(0.71 0.22 0 / 0.10);border-radius:0.75rem;flex-shrink:0;">
                        <svg xmlns="http://www.w3.org/2000/svg" width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="oklch(0.71 0.22 0)" stroke-width="1.75" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><circle cx="18" cy="18" r="3"/><circle cx="6" cy="6" r="3"/><path d="M13 6h3a2 2 0 0 1 2 2v7"/><path d="M6 9v12"/></svg>
                    </div>
                    <div>
                        <h3 style="font-family:var(--font-display);font-weight:700;font-size:0.9rem;color:var(--ink-1);margin-bottom:0.3rem;">Block & Hide Controls</h3>
                        <p style="font-size:0.8rem;color:var(--ink-3);line-height:1.55;">Block any user instantly. Blocked profiles are permanently excluded from your orbit, chats, and discovery feed.</p>
                    </div>
                </div>

                <div class="glass glass-hover reveal" style="padding:1.5rem;border-radius:1.25rem;display:flex;gap:1rem;align-items:flex-start;" style="transition-delay:0.5s">
                    <div class="feat-icon" style="background:oklch(0.68 0.20 280 / 0.10);border-radius:0.75rem;flex-shrink:0;">
                        <svg xmlns="http://www.w3.org/2000/svg" width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="oklch(0.68 0.20 280)" stroke-width="1.75" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><polyline points="3 6 5 6 21 6"/><path d="m19 6-.867 12.142A2 2 0 0 1 16.138 20H7.862a2 2 0 0 1-1.995-1.858L5 6"/><path d="M10 11v6"/><path d="M14 11v6"/><path d="M9 6V4a1 1 0 0 1 1-1h4a1 1 0 0 1 1 1v2"/></svg>
                    </div>
                    <div>
                        <h3 style="font-family:var(--font-display);font-weight:700;font-size:0.9rem;color:var(--ink-1);margin-bottom:0.3rem;">Account Deletion Grace Period</h3>
                        <p style="font-size:0.8rem;color:var(--ink-3);line-height:1.55;">Request deletion - 30-day reactivation window before permanent purge. Your call, your timeline.</p>
                    </div>
                </div>
            </div>
        </section>

        <!-- ─────────────── COMMUNITY ─────────────── -->
        <section id="community" class="section section-divider">
            <div class="reveal" style="text-align:center;max-width:36rem;margin:0 auto 2.5rem;">
                <h2 class="f-display" style="font-size:clamp(1.5rem,3vw,2.25rem);font-weight:800;line-height:1.12;letter-spacing:-0.025em;color:var(--ink-1);margin-bottom:0.75rem;">Find us in orbit.</h2>
                <p style="color:var(--ink-2);font-size:0.9375rem;line-height:1.65;">Connect with the team, student ambassadors, and the open-source community across our channels.</p>
            </div>

            <div class="reveal" style="display:flex;flex-wrap:wrap;justify-content:center;gap:0.875rem;max-width:700px;margin:0 auto;">
                <a href="https://github.com/devakesu/Nexus" target="_blank" rel="noopener noreferrer" class="glass glass-hover" style="padding:0.875rem 1.5rem;border-radius:1rem;display:flex;align-items:center;gap:0.625rem;text-decoration:none;color:var(--ink-2);font-weight:600;font-size:0.875rem;transition:color 0.2s;" aria-label="GitHub repository">
                    <svg xmlns="http://www.w3.org/2000/svg" width="18" height="18" viewBox="0 0 24 24" fill="currentColor" aria-hidden="true"><path d="M12 2A10 10 0 0 0 2 12c0 4.42 2.87 8.17 6.84 9.5.5.08.66-.23.66-.5v-1.69c-2.77.6-3.36-1.34-3.36-1.34-.46-1.16-1.11-1.47-1.11-1.47-.91-.62.07-.6.07-.6 1 .07 1.53 1.03 1.53 1.03.87 1.52 2.34 1.07 2.91.83.09-.65.35-1.09.63-1.34-2.22-.25-4.55-1.11-4.55-4.92 0-1.11.38-2 1.03-2.71-.1-.25-.45-1.29.1-2.64 0 0 .84-.27 2.75 1.02.79-.22 1.65-.33 2.5-.33.85 0 1.71.11 2.5.33 1.91-1.29 2.75-1.02 2.75-1.02.55 1.35.2 2.39.1 2.64.65.71 1.03 1.6 1.03 2.71 0 3.82-2.34 4.66-4.57 4.91.36.31.69.92.69 1.85V21c0 .27.16.59.67.5C19.14 20.16 22 16.42 22 12A10 10 0 0 0 12 2z"/></svg>
                    GitHub
                </a>
            </div>
        </section>

        <!-- ─────────────── FAQ ─────────────── -->
        <section id="faq" class="section section-divider">
            <div class="reveal" style="text-align:center;max-width:36rem;margin:0 auto 3rem;">
                <h2 class="f-display" style="font-size:clamp(1.875rem,3.5vw,2.5rem);font-weight:800;line-height:1.12;letter-spacing:-0.025em;color:var(--ink-1);margin-bottom:0.75rem;">Questions answered.</h2>
                <p style="color:var(--ink-2);font-size:0.9375rem;line-height:1.65;">No corporate vagueness. Clear answers about how Nexus actually works.</p>
            </div>

            <div class="reveal" style="max-width:700px;margin:0 auto;display:flex;flex-direction:column;gap:0.625rem;">
                <details class="glass" style="padding:0;">
                    <summary style="padding:1.25rem 1.5rem;display:flex;align-items:center;justify-content:space-between;font-weight:700;color:var(--ink-1);font-size:0.9375rem;">
                        <span>How do I install Nexus from Google Play?</span>
                        <svg class="faq-chevron" xmlns="http://www.w3.org/2000/svg" width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="oklch(0.72 0.19 205)" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="m6 9 6 6 6-6"/></svg>
                    </summary>
                    <div style="padding:0 1.5rem 1.25rem;font-size:0.875rem;color:var(--ink-3);line-height:1.65;border-top:1px solid oklch(0.22 0.020 265 / 0.5);">
                        <div style="padding-top:1rem;">For verified campus students, search <code class="f-mono" style="font-size:0.8rem;color:oklch(0.78 0.20 85);">Nexus MEC</code> on Google Play or use package ID <code class="f-mono" style="font-size:0.8rem;color:oklch(0.78 0.20 85);">com.devakesu.apps.nexus.mec</code>. It's live and available now. The general variant (<code class="f-mono" style="font-size:0.8rem;color:oklch(0.72 0.19 205);">com.devakesu.apps.nexus</code>) is currently in pre-launch and coming soon.</div>
                    </div>
                </details>

                <details class="glass" style="padding:0;">
                    <summary style="padding:1.25rem 1.5rem;display:flex;align-items:center;justify-content:space-between;font-weight:700;color:var(--ink-1);font-size:0.9375rem;">
                        <span>How does the Meetup Check-in Timer work?</span>
                        <svg class="faq-chevron" xmlns="http://www.w3.org/2000/svg" width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="oklch(0.72 0.19 205)" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="m6 9 6 6 6-6"/></svg>
                    </summary>
                    <div style="padding:0 1.5rem 1.25rem;font-size:0.875rem;color:var(--ink-3);line-height:1.65;border-top:1px solid oklch(0.22 0.020 265 / 0.5);">
                        <div style="padding-top:1rem;">Before meeting someone in person, arm a Check-in Timer (e.g. 30 minutes) from Safety Center. You get a unique PIN. If you don't extend or disarm the timer before it expires, Nexus automatically sends emergency alerts and a live Web Portal link to your designated Emergency Contacts.</div>
                    </div>
                </details>

                <details class="glass" style="padding:0;">
                    <summary style="padding:1.25rem 1.5rem;display:flex;align-items:center;justify-content:space-between;font-weight:700;color:var(--ink-1);font-size:0.9375rem;">
                        <span>What's the difference between Nexus and Nexus MEC?</span>
                        <svg class="faq-chevron" xmlns="http://www.w3.org/2000/svg" width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="oklch(0.72 0.19 205)" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="m6 9 6 6 6-6"/></svg>
                    </summary>
                    <div style="padding:0 1.5rem 1.25rem;font-size:0.875rem;color:var(--ink-3);line-height:1.65;border-top:1px solid oklch(0.22 0.020 265 / 0.5);">
                        <div style="padding-top:1rem;">Both share the same codebase, features, and design language. The general variant (<code class="f-mono" style="font-size:0.8rem;color:oklch(0.72 0.19 205);">nexus</code>) opens discovery to any email domain. The MEC variant (<code class="f-mono" style="font-size:0.8rem;color:oklch(0.78 0.20 85);">nexus_mec</code>) restricts signup to verified <code class="f-mono" style="font-size:0.8rem;color:oklch(0.78 0.20 85);">@mec.ac.in</code> campus student email domains - ensuring the orbit is strictly your campus community.</div>
                    </div>
                </details>

                <details class="glass" style="padding:0;">
                    <summary style="padding:1.25rem 1.5rem;display:flex;align-items:center;justify-content:space-between;font-weight:700;color:var(--ink-1);font-size:0.9375rem;">
                        <span>Are my messages really end-to-end encrypted?</span>
                        <svg class="faq-chevron" xmlns="http://www.w3.org/2000/svg" width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="oklch(0.72 0.19 205)" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="m6 9 6 6 6-6"/></svg>
                    </summary>
                    <div style="padding:0 1.5rem 1.25rem;font-size:0.875rem;color:var(--ink-3);line-height:1.65;border-top:1px solid oklch(0.22 0.020 265 / 0.5);">
                        <div style="padding-top:1rem;">Yes. Nexus uses an asymmetric ECDH prekey bundle exchange (similar to Signal Protocol) to set up a per-session E2EE tunnel for every conversation. Messages are encrypted on your device before leaving it, and only decrypted on the recipient's device. The backend server only stores and relays encrypted ciphertext - it never has access to plaintext.</div>
                    </div>
                </details>

                <details class="glass" style="padding:0;">
                    <summary style="padding:1.25rem 1.5rem;display:flex;align-items:center;justify-content:space-between;font-weight:700;color:var(--ink-1);font-size:0.9375rem;">
                        <span>Can I export or delete my account data?</span>
                        <svg class="faq-chevron" xmlns="http://www.w3.org/2000/svg" width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="oklch(0.72 0.19 205)" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="m6 9 6 6 6-6"/></svg>
                    </summary>
                    <div style="padding:0 1.5rem 1.25rem;font-size:0.875rem;color:var(--ink-3);line-height:1.65;border-top:1px solid oklch(0.22 0.020 265 / 0.5);">
                        <div style="padding-top:1rem;">Yes to both. Data export gives you a full JSON archive of your account, settings, and chat metadata. Account deletion requests trigger a 30-day grace period before permanent, irreversible data purging - so you can change your mind.</div>
                    </div>
                </details>

                <details class="glass" style="padding:0;">
                    <summary style="padding:1.25rem 1.5rem;display:flex;align-items:center;justify-content:space-between;font-weight:700;color:var(--ink-1);font-size:0.9375rem;">
                        <span>What is Ghost Mode and how does it work?</span>
                        <svg class="faq-chevron" xmlns="http://www.w3.org/2000/svg" width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="oklch(0.72 0.19 205)" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="m6 9 6 6 6-6"/></svg>
                    </summary>
                    <div style="padding:0 1.5rem 1.25rem;font-size:0.875rem;color:var(--ink-3);line-height:1.65;border-top:1px solid oklch(0.22 0.020 265 / 0.5);">
                        <div style="padding-top:1rem;">Ghost Mode is a single-toggle privacy control accessible from your profile. When active, your orbit node is completely hidden from all nearby discovery radars - you won't appear in anyone's orbit. Your existing matched chats remain accessible and functional. Ghost Mode doesn't log you out or delete data.</div>
                    </div>
                </details>
            </div>
        </section>

        <!-- ─────────────── CTA ─────────────── -->
        <section class="section">
            <div style="position:relative;background:oklch(0.10 0.022 265 / 0.7);border:1px solid oklch(0.28 0.022 265 / 0.7);border-radius:2rem;padding:clamp(2.5rem,5vw,4.5rem) 2rem;text-align:center;overflow:hidden;" class="reveal">
                <div class="cta-glow" aria-hidden="true"></div>

                <!-- Decorative orbit rings -->
                <div style="position:absolute;width:600px;height:600px;border:1px solid oklch(0.72 0.19 205 / 0.06);border-radius:50%;top:50%;left:50%;transform:translate(-50%,-50%);pointer-events:none;" aria-hidden="true"></div>
                <div style="position:absolute;width:400px;height:400px;border:1px solid oklch(0.68 0.20 280 / 0.08);border-radius:50%;top:50%;left:50%;transform:translate(-50%,-50%);pointer-events:none;" aria-hidden="true"></div>

                <div style="position:relative;z-index:10;max-width:580px;margin:0 auto;display:flex;flex-direction:column;gap:1.5rem;align-items:center;">
                    <h2 class="f-display" style="font-size:clamp(2rem,4vw,3.25rem);font-weight:800;line-height:1.1;letter-spacing:-0.025em;color:var(--ink-1);">
                        You're already in someone's orbit.
                    </h2>
                    <p style="color:var(--ink-2);font-size:1rem;line-height:1.65;max-width:42ch;">
                        Start discovering the people genuinely near you. No swipe decks. No algorithmic curation. Just real proximity.
                    </p>
                    <div style="display:flex;flex-wrap:wrap;gap:0.875rem;justify-content:center;">
                        <a href="https://play.google.com/store/apps/details?id=com.devakesu.apps.nexus.mec"
                        target="_blank" rel="noopener noreferrer"
                        class="btn-primary btn-campus">
                            <svg xmlns="http://www.w3.org/2000/svg" width="20" height="20" viewBox="0 0 24 24" fill="currentColor" aria-hidden="true"><path d="M3.18 23.5a1.5 1.5 0 0 1-.94-1.41V1.91A1.5 1.5 0 0 1 3.18.5l11.52 11.52zm1.32-20.1v17.2l9.26-8.6zM21.32 13.5l-2.88 1.66-2.88-2.88 2.88-2.88 2.88 1.66a1.5 1.5 0 0 1 0 2.44zM3.18.5l11.52 11.52-2.88 2.88L3.18.5z"/></svg>
                            Download Nexus MEC
                        </a>
                        <a href="https://play.google.com/store/apps/details?id=com.devakesu.apps.nexus"
                        target="_blank" rel="noopener noreferrer"
                        class="btn-ghost">
                            <svg xmlns="http://www.w3.org/2000/svg" width="20" height="20" viewBox="0 0 24 24" fill="currentColor" style="color:oklch(0.72 0.19 205)" aria-hidden="true"><path d="M3.18 23.5a1.5 1.5 0 0 1-.94-1.41V1.91A1.5 1.5 0 0 1 3.18.5l11.52 11.52zm1.32-20.1v17.2l9.26-8.6zM21.32 13.5l-2.88 1.66-2.88-2.88 2.88-2.88 2.88 1.66a1.5 1.5 0 0 1 0 2.44zM3.18.5l11.52 11.52-2.88 2.88L3.18.5z"/></svg>
                            Nexus (Coming Soon)
                        </a>
                    </div>
                </div>
            </div>
        </section>

        </main>

        <!-- ═══════════════════════ FOOTER ═══════════════════════ -->
        <footer style="border-top:1px solid oklch(0.38 0.08 240 / 0.6);background:radial-gradient(ellipse 100% 120% at 50% -20%, oklch(0.15 0.05 265 / 0.96) 0%, oklch(0.04 0.018 285 / 0.99) 100%);backdrop-filter:blur(24px);-webkit-backdrop-filter:blur(24px);padding:3.5rem 0 8.5rem;margin-top:1rem;position:relative;overflow:hidden;z-index:var(--z-content);" role="contentinfo">
            <!-- Universe Constellation Visual Layer -->
            <div aria-hidden="true" style="position:absolute;inset:0;pointer-events:none;z-index:1;overflow:hidden;">
                <!-- Glowing Nebula Orbs -->
                <div style="position:absolute;top:-60px;left:8%;width:420px;height:420px;background:radial-gradient(circle, oklch(0.72 0.19 205 / 0.22), transparent 70%);filter:blur(60px);"></div>
                <div style="position:absolute;bottom:-60px;right:5%;width:480px;height:480px;background:radial-gradient(circle, oklch(0.68 0.20 280 / 0.20), transparent 70%);filter:blur(70px);"></div>
                <div style="position:absolute;top:30%;right:35%;width:300px;height:300px;background:radial-gradient(circle, oklch(0.71 0.22 0 / 0.12), transparent 70%);filter:blur(65px);"></div>

                <!-- Rotating Background Orbital Ring -->
                <div class="footer-orbit-ring"></div>

                <!-- Animated Shooting Comets -->
                <div class="footer-comet comet-1"></div>
                <div class="footer-comet comet-2"></div>
                <div class="footer-comet comet-3"></div>

                <!-- Constellation Lines & Star Nodes SVG -->
                <svg width="100%" height="100%" preserveAspectRatio="none" style="position:absolute;inset:0;width:100%;height:100%;opacity:0.28;">
                    <!-- Constellation vector connections -->
                    <g stroke="oklch(0.72 0.19 205 / 0.18)" stroke-width="1" stroke-dasharray="5 4">
                        <line x1="5%" y1="20%" x2="22%" y2="58%" />
                        <line x1="22%" y1="58%" x2="40%" y2="22%" />
                        <line x1="40%" y1="22%" x2="58%" y2="68%" />
                        <line x1="58%" y1="68%" x2="76%" y2="28%" />
                        <line x1="76%" y1="28%" x2="94%" y2="72%" />
                        <line x1="22%" y1="58%" x2="58%" y2="68%" />
                        <line x1="40%" y1="22%" x2="76%" y2="28%" />
                        <line x1="12%" y1="75%" x2="32%" y2="85%" />
                        <line x1="32%" y1="85%" x2="50%" y2="40%" />
                        <line x1="68%" y1="80%" x2="88%" y2="40%" />
                    </g>

                    <!-- Major Glowing Constellation Star Nodes -->
                    <g>
                        <circle class="star-twinkle-1" cx="5%" cy="20%" r="3.5" fill="oklch(0.95 0.08 205)" />
                        <circle class="star-twinkle-2" cx="22%" cy="58%" r="4.5" fill="oklch(0.88 0.18 205)" />
                        <circle class="star-twinkle-3" cx="40%" cy="22%" r="3" fill="oklch(0.98 0.02 265)" />
                        <circle class="star-twinkle-4" cx="58%" cy="68%" r="5" fill="oklch(0.82 0.20 280)" />
                        <circle class="star-twinkle-1" cx="76%" cy="28%" r="3.5" fill="oklch(0.92 0.14 205)" />
                        <circle class="star-twinkle-2" cx="94%" cy="72%" r="4" fill="oklch(0.90 0.18 85)" />
                        <circle class="star-twinkle-3" cx="12%" cy="75%" r="3" fill="oklch(0.85 0.22 0)" />
                        <circle class="star-twinkle-4" cx="32%" cy="85%" r="4" fill="oklch(0.88 0.18 205)" />
                        <circle class="star-twinkle-1" cx="50%" cy="40%" r="3.5" fill="oklch(0.95 0.05 265)" />
                        <circle class="star-twinkle-2" cx="68%" cy="80%" r="3" fill="oklch(0.82 0.20 280)" />
                        <circle class="star-twinkle-3" cx="88%" cy="40%" r="4.5" fill="oklch(0.92 0.14 205)" />
                    </g>

                    <!-- Star Flare Crosshairs -->
                    <g stroke="oklch(0.95 0.05 205 / 0.4)" stroke-width="0.75">
                        <line x1="22%" y1="52%" x2="22%" y2="64%" />
                        <line x1="19%" y1="58%" x2="25%" y2="58%" />
                        <line x1="58%" y1="62%" x2="58%" y2="74%" />
                        <line x1="55%" y1="68%" x2="61%" y2="68%" />
                        <line x1="94%" y1="66%" x2="94%" y2="78%" />
                        <line x1="91%" y1="72%" x2="97%" y2="72%" />
                    </g>
                </svg>
            </div>

            <div class="footer-grid">
                <!-- Brand -->
                <div style="display:flex;flex-direction:column;gap:1rem;">
                    <a href="/" style="display:inline-flex;align-items:center;gap:0.625rem;text-decoration:none;">
                        <img src="/logo.png" alt="" width="28" height="28" style="width:1.75rem;height:1.75rem;border-radius:0.5rem;">
                        <span class="f-display" style="font-weight:800;font-size:1.1rem;color:var(--ink-1);text-shadow:0 2px 10px rgba(0,0,0,0.95);">NEXUS</span>
                    </a>
                    <p style="font-size:0.85rem;color:oklch(0.85 0.01 265);line-height:1.65;max-width:28ch;font-weight:500;text-shadow:0 2px 10px rgba(0,0,0,0.95);">
                        Cosmic-themed, authentic social discovery app for spontaneous, in-the-moment human connections across multiple social dimensions: whether you are looking for new friends, professional connections, or romance. ✨
                    </p>
                    <p style="font-size:0.75rem;color:oklch(0.65 0.012 265);font-weight:500;text-shadow:0 2px 8px rgba(0,0,0,0.95);">© 2026 <a href="https://devakesu.com" target="_blank" rel="noopener noreferrer" style="color:inherit;text-decoration:none;font-weight:600;">@devakesu</a></p>
                </div>

                <!-- Privacy -->
                <div style="display:flex;flex-direction:column;gap:0.875rem;">
                    <p style="font-family:var(--font-display);font-weight:800;font-size:0.8125rem;letter-spacing:0.1em;text-transform:uppercase;color:var(--ink-1);text-shadow:0 2px 10px rgba(0,0,0,0.95);">Legal & Support</p>
                    <a href="/legal"   class="footer-link">Privacy & Terms</a>
                    <a href="/contact" class="footer-link">Contact Us</a>
                    <a href="/help"    class="footer-link">Help Center</a>
                    <a href="/delete-account" class="footer-link">Delete Your Data</a>
                </div>

                <!-- Download -->
                <div style="display:flex;flex-direction:column;gap:0.875rem;">
                    <p style="font-family:var(--font-display);font-weight:800;font-size:0.8125rem;letter-spacing:0.1em;text-transform:uppercase;color:var(--ink-1);text-shadow:0 2px 10px rgba(0,0,0,0.95);">Get the App</p>
                    <a href="https://play.google.com/store/apps/details?id=com.devakesu.apps.nexus" target="_blank" rel="noopener noreferrer" class="footer-link" style="display:flex;align-items:center;gap:0.4rem;">
                        <svg xmlns="http://www.w3.org/2000/svg" width="14" height="14" viewBox="0 0 24 24" fill="currentColor" aria-hidden="true"><path d="M3.18 23.5a1.5 1.5 0 0 1-.94-1.41V1.91A1.5 1.5 0 0 1 3.18.5l11.52 11.52zm1.32-20.1v17.2l9.26-8.6zM21.32 13.5l-2.88 1.66-2.88-2.88 2.88-2.88 2.88 1.66a1.5 1.5 0 0 1 0 2.44zM3.18.5l11.52 11.52-2.88 2.88L3.18.5z"/></svg>
                        Nexus (Coming Soon)
                    </a>
                    <a href="https://play.google.com/store/apps/details?id=com.devakesu.apps.nexus.mec" target="_blank" rel="noopener noreferrer" class="footer-link" style="display:flex;align-items:center;gap:0.4rem;">
                        <svg xmlns="http://www.w3.org/2000/svg" width="14" height="14" viewBox="0 0 24 24" fill="currentColor" aria-hidden="true"><path d="M3.18 23.5a1.5 1.5 0 0 1-.94-1.41V1.91A1.5 1.5 0 0 1 3.18.5l11.52 11.52zm1.32-20.1v17.2l9.26-8.6zM21.32 13.5l-2.88 1.66-2.88-2.88 2.88-2.88 2.88 1.66a1.5 1.5 0 0 1 0 2.44zM3.18.5l11.52 11.52-2.88 2.88L3.18.5z"/></svg>
                        Nexus MEC (Campus)
                    </a>
                    <p style="font-size:0.75rem;color:oklch(0.65 0.012 265);margin-top:0.25rem;font-weight:500;text-shadow:0 2px 8px rgba(0,0,0,0.95);">
                        Made with <span style="color:oklch(0.71 0.22 0);">❤️</span> by <a href="https://devakesu.com" target="_blank" rel="noopener noreferrer" style="color:oklch(0.74 0.19 205);text-decoration:none;font-weight:700;text-shadow:0 0 10px oklch(0.72 0.19 205 / 0.5);">@devakesu</a>
                    </p>
                </div>
            </div>
        </footer>

        <!-- ═══════════════════════ QR MODAL ═══════════════════════ -->
        <div id="qr-modal" role="dialog" aria-modal="true" aria-labelledby="qr-modal-title"
            style="display:none;position:fixed;inset:0;z-index:var(--z-modal);background:oklch(0.04 0.010 265 / 0.88);backdrop-filter:blur(20px);-webkit-backdrop-filter:blur(20px);align-items:center;justify-content:center;padding:1rem;">
            <div class="glass" style="max-width:520px;width:100%;max-height:calc(100vh - 2rem);overflow-y:auto;padding:1.5rem;border-radius:1.5rem;position:relative;border-color:oklch(0.28 0.022 265 / 0.9);box-sizing:border-box;margin:auto;">
                <button onclick="document.getElementById('qr-modal').style.display='none'"
                        style="position:absolute;top:1rem;right:1rem;background:oklch(0.16 0.02 265);border:1px solid oklch(0.28 0.025 265);cursor:pointer;color:var(--ink-1);padding:0.4rem;border-radius:0.5rem;display:flex;z-index:10;"
                        aria-label="Close modal">
                    <svg xmlns="http://www.w3.org/2000/svg" width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M18 6 6 18"/><path d="m6 6 12 12"/></svg>
                </button>

                <h3 id="qr-modal-title" class="f-display" style="font-size:1.25rem;font-weight:700;color:var(--ink-1);margin-bottom:0.25rem;text-align:center;">Scan to Install</h3>
                <p style="font-size:0.8125rem;color:var(--ink-3);text-align:center;margin-bottom:1.5rem;">Point your camera at the QR code to open the Play Store listing directly.</p>

                <div class="qr-modal-grid">
                    <!-- General QR (Nexus) -->
                    <div style="background:oklch(0.10 0.022 265);border:1px solid oklch(0.72 0.19 205 / 0.35);border-radius:1.25rem;padding:1.25rem;text-align:center;display:flex;flex-direction:column;gap:0.75rem;align-items:center;">
                        <span class="badge badge-soon"><span class="beacon-orbit" aria-hidden="true"></span>COMING SOON</span>
                        <p style="font-weight:700;color:var(--ink-1);font-size:0.9rem;">Nexus</p>
                        <div style="background:white;border-radius:0.875rem;padding:0.625rem;width:10rem;height:10rem;display:flex;align-items:center;justify-content:center;box-shadow:0 8px 24px rgba(0,0,0,0.4);">
                            <img src="https://api.qrserver.com/v1/create-qr-code/?size=300x300&data=https%3A%2F%2Fplay.google.com%2Fstore%2Fapps%2Fdetails%3Fid%3Dcom.devakesu.apps.nexus"
                                alt="Scannable QR code for Nexus on Play Store"
                                style="width:100%;height:100%;object-fit:contain;border-radius:0.375rem;image-rendering:pixelated;"
                                loading="eager" />
                        </div>
                        <a href="https://play.google.com/store/apps/details?id=com.devakesu.apps.nexus"
                        target="_blank" rel="noopener noreferrer"
                        class="btn-ghost" style="width:100%;padding:0.6rem!important;font-size:0.75rem!important;border-radius:0.75rem!important;justify-content:center;display:flex!important;">
                            Preview Page
                        </a>
                    </div>

                    <!-- Campus QR (Nexus MEC) -->
                    <div style="background:oklch(0.10 0.022 265);border:1px solid oklch(0.78 0.20 85 / 0.40);border-radius:1.25rem;padding:1.25rem;text-align:center;display:flex;flex-direction:column;gap:0.75rem;align-items:center;">
                        <span class="badge badge-campus"><span class="beacon-dot pulse" style="color:oklch(0.78 0.20 85);" aria-hidden="true"></span>CAMPUS LIVE</span>
                        <p style="font-weight:700;color:var(--ink-1);font-size:0.9rem;">Nexus MEC</p>
                        <div style="background:white;border-radius:0.875rem;padding:0.625rem;width:10rem;height:10rem;display:flex;align-items:center;justify-content:center;box-shadow:0 8px 24px rgba(0,0,0,0.4);">
                            <img src="https://api.qrserver.com/v1/create-qr-code/?size=300x300&data=https%3A%2F%2Fplay.google.com%2Fstore%2Fapps%2Fdetails%3Fid%3Dcom.devakesu.apps.nexus.mec"
                                alt="Scannable QR code for Nexus MEC on Play Store"
                                style="width:100%;height:100%;object-fit:contain;border-radius:0.375rem;image-rendering:pixelated;"
                                loading="eager" />
                        </div>
                        <a href="https://play.google.com/store/apps/details?id=com.devakesu.apps.nexus.mec"
                        target="_blank" rel="noopener noreferrer"
                        class="btn-primary btn-campus" style="width:100%;padding:0.6rem!important;font-size:0.75rem!important;border-radius:0.75rem!important;justify-content:center;display:flex!important;">
                            Open Play Store
                        </a>
                    </div>
                </div>
            </div>
        </div>

        <!-- ═══════════════════════ SCRIPTS ═══════════════════════ -->
        <script>
            // ── Cosmos starfield canvas ──────────────────────────────────────────────────
            (function () {
                const canvas = document.getElementById('cosmos-canvas');
                if (!canvas) return;
                const ctx = canvas.getContext('2d');
                let W = canvas.width  = window.innerWidth;
                let H = canvas.height = window.innerHeight;

                window.addEventListener('resize', () => {
                    W = canvas.width  = window.innerWidth;
                    H = canvas.height = window.innerHeight;
                }, { passive: true });

                const N = Math.min(160, Math.floor(W * H / 7500));
                let mx = W / 2, my = H / 2;
                window.addEventListener('mousemove', e => { mx = e.clientX; my = e.clientY; }, { passive: true });

                const stars = Array.from({ length: N }, () => ({
                    x: Math.random() * W, y: Math.random() * H,
                    r: Math.random() * 1.4 + 0.3,
                    vx: (Math.random() - 0.5) * 0.18,
                    vy: (Math.random() - 0.5) * 0.18,
                    alpha: Math.random() * 0.7 + 0.2,
                    phase: Math.random() * Math.PI * 2,
                    freq: Math.random() * 0.018 + 0.005,
                    hue: Math.random() > 0.8 ? 205 : (Math.random() > 0.5 ? 280 : 265),
                }));

                // Static constellation clusters - deterministic positions
                const CLUSTERS = [
                    { cx: W * 0.25, cy: H * 0.22, pts: [[0,0],[80,-30],[40,60],[-50,40],[90,20]] },
                    { cx: W * 0.75, cy: H * 0.65, pts: [[0,0],[-70,25],[30,70],[80,10],[-20,80]] },
                    { cx: W * 0.60, cy: H * 0.15, pts: [[0,0],[50,-20],[-30,50],[60,30]] },
                ];

                function draw(t) {
                    ctx.clearRect(0, 0, W, H);

                    // Constellation lines (static)
                    ctx.save();
                    CLUSTERS.forEach(cl => {
                        const pts = cl.pts.map(([dx, dy]) => ({ x: cl.cx + dx, y: cl.cy + dy }));
                        ctx.beginPath();
                        pts.forEach((p, i) => { i === 0 ? ctx.moveTo(p.x, p.y) : ctx.lineTo(p.x, p.y); });
                        ctx.closePath();
                        ctx.strokeStyle = 'oklch(0.72 0.19 205 / 0.08)';
                        ctx.lineWidth = 0.5;
                        ctx.stroke();
                    });
                    ctx.restore();

                    // Dynamic star connections
                    for (let i = 0; i < stars.length; i++) {
                        for (let j = i + 1; j < stars.length; j++) {
                            const dx = stars[i].x - stars[j].x;
                            const dy = stars[i].y - stars[j].y;
                            const d2 = dx * dx + dy * dy;
                            if (d2 < 9800) {
                                const a = (1 - Math.sqrt(d2) / 99) * 0.12;
                                ctx.beginPath();
                                ctx.moveTo(stars[i].x, stars[i].y);
                                ctx.lineTo(stars[j].x, stars[j].y);
                                ctx.strokeStyle = `oklch(0.72 0.19 205 / ${a.toFixed(3)})`;
                                ctx.lineWidth = 0.4;
                                ctx.stroke();
                            }
                        }
                    }

                    // Mouse connections
                    stars.forEach(s => {
                        const dx = mx - s.x, dy = my - s.y;
                        const d = Math.sqrt(dx * dx + dy * dy);
                        if (d < 120) {
                            const a = (1 - d / 120) * 0.22;
                            ctx.beginPath();
                            ctx.moveTo(s.x, s.y);
                            ctx.lineTo(mx, my);
                            ctx.strokeStyle = `oklch(0.68 0.20 280 / ${a.toFixed(3)})`;
                            ctx.lineWidth = 0.6;
                            ctx.stroke();
                        }
                    });

                    // Stars
                    stars.forEach(s => {
                        s.x = (s.x + s.vx + W) % W;
                        s.y = (s.y + s.vy + H) % H;
                        const a = Math.max(0.08, Math.min(0.95, 0.5 + 0.45 * Math.sin(t * s.freq + s.phase)));
                        ctx.beginPath();
                        ctx.arc(s.x, s.y, s.r, 0, Math.PI * 2);
                        ctx.fillStyle = `oklch(0.94 0.010 ${s.hue} / ${a.toFixed(3)})`;
                        ctx.shadowBlur = 3;
                        ctx.shadowColor = `oklch(0.72 0.19 ${s.hue})`;
                        ctx.fill();
                        ctx.shadowBlur = 0;
                    });

                    requestAnimationFrame(draw);
                }
                requestAnimationFrame(draw);
            })();

            // ── Scroll reveal ────────────────────────────────────────────────────────────
            (function () {
                const els = document.querySelectorAll('.reveal, .reveal-l');
                const io = new IntersectionObserver((entries) => {
                    entries.forEach(e => { if (e.isIntersecting) { e.target.classList.add('in'); io.unobserve(e.target); } });
                }, { threshold: 0.07, rootMargin: '0px 0px -40px 0px' });
                els.forEach(el => io.observe(el));
            })();

            // ── Nebula parallax ──────────────────────────────────────────────────────────
            (function () {
                const blobs = document.querySelectorAll('.nebula-blob');
                let ticking = false;
                window.addEventListener('scroll', () => {
                    if (!ticking) {
                        requestAnimationFrame(() => {
                            const y = window.scrollY;
                            blobs[0].style.transform = `translateY(${y * 0.12}px)`;
                            blobs[1].style.transform = `translateY(${-y * 0.08}px)`;
                            blobs[2].style.transform = `translateY(${y * 0.06}px)`;
                            ticking = false;
                        });
                        ticking = true;
                    }
                }, { passive: true });
            })();

            // ── Safety check-in timer sandbox ───────────────────────────────────────────
            let _timerRef = null, _timeLeft = 10;

            function _updateTimer(n) {
                const d = document.getElementById('timer-display');
                if (d) d.textContent = '00:' + (n < 10 ? '0' : '') + n;
                const r = document.getElementById('safety-ring');
                if (r) r.style.strokeDashoffset = 251.2 * (1 - n / 10);
            }

            function startTestTimer() {
                if (_timerRef) clearInterval(_timerRef);
                _timeLeft = 10;
                _updateTimer(10);
                const badge = document.getElementById('timer-status-badge');
                const box   = document.getElementById('portal-alert-box');
                if (badge) { badge.textContent = 'Armed · Countdown'; badge.style.color = 'oklch(0.78 0.20 85)'; badge.style.background = 'oklch(0.78 0.20 85 / 0.12)'; }
                if (box)   box.style.display = 'none';

                _timerRef = setInterval(() => {
                    _timeLeft--;
                    _updateTimer(_timeLeft);
                    if (_timeLeft <= 0) {
                        clearInterval(_timerRef); _timerRef = null;
                        if (badge) { badge.textContent = 'Alert Dispatched!'; badge.style.color = 'oklch(0.75 0.18 0)'; badge.style.background = 'oklch(0.71 0.22 0 / 0.12)'; }
                        if (box)   box.style.display = 'block';
                    }
                }, 1000);
            }

            function disarmTestTimer() {
                if (_timerRef) { clearInterval(_timerRef); _timerRef = null; }
                _timeLeft = 10;
                _updateTimer(10);
                const badge = document.getElementById('timer-status-badge');
                const box   = document.getElementById('portal-alert-box');
                if (badge) { badge.textContent = 'Disarmed via PIN'; badge.style.color = 'oklch(0.74 0.20 165)'; badge.style.background = 'oklch(0.74 0.20 165 / 0.10)'; }
                if (box)   box.style.display = 'none';
            }

            // ── Discovery mode tabs ──────────────────────────────────────────────────────
            function switchMode(mode) {
                ['dating','friends','pro'].forEach(m => {
                    const tab     = document.getElementById('tab-' + m);
                    const content = document.getElementById('mode-content-' + m);
                    const active  = m === mode;
                    if (tab) {
                        tab.className = 'mode-tab' + (active ? (' active-' + m) : '');
                        tab.setAttribute('aria-selected', active);
                    }
                    if (content) content.style.display = active ? 'block' : 'none';
                });
            }

            // Close QR modal on backdrop click
            document.getElementById('qr-modal').addEventListener('click', function(e) {
                if (e.target === this) this.style.display = 'none';
            });

            // Close modal on Escape key
            document.addEventListener('keydown', e => {
                if (e.key === 'Escape') {
                    const m = document.getElementById('qr-modal');
                    if (m) m.style.display = 'none';
                }
            });
        </script>

        <!-- Interactive Scripts: Starfield Canvas, Scroll Reveal, & Check-in Timer Sandbox -->
        <script>
            document.addEventListener('DOMContentLoaded', () => {
                // 1. Starfield Canvas
                const canvas = document.getElementById('universe-canvas');
                if (canvas) {
                    const ctx = canvas.getContext('2d');
                    let width = canvas.width = window.innerWidth;
                    let height = canvas.height = window.innerHeight;

                    window.addEventListener('resize', () => {
                        width = canvas.width = window.innerWidth;
                        height = canvas.height = window.innerHeight;
                    });

                    const numStars = Math.min(120, Math.floor((width * height) / 9500));
                    const stars = [];
                    let mouseX = width / 2;
                    let mouseY = height / 2;

                    window.addEventListener('mousemove', (e) => {
                        mouseX = e.clientX;
                        mouseY = e.clientY;
                    });

                    for (let i = 0; i < numStars; i++) {
                        stars.push({
                            x: Math.random() * width,
                            y: Math.random() * height,
                            radius: Math.random() * 1.5 + 0.5,
                            vx: (Math.random() - 0.5) * 0.2,
                            vy: (Math.random() - 0.5) * 0.2,
                            alpha: Math.random() * 0.8 + 0.2,
                            twinkleSpeed: Math.random() * 0.02 + 0.005,
                        });
                    }

                    function animateUniverse() {
                        ctx.clearRect(0, 0, width, height);

                        for (let i = 0; i < stars.length; i++) {
                            for (let j = i + 1; j < stars.length; j++) {
                                const dx = stars[i].x - stars[j].x;
                                const dy = stars[i].y - stars[j].y;
                                const dist = Math.sqrt(dx * dx + dy * dy);

                                if (dist < 110) {
                                    const lineAlpha = (1 - dist / 110) * 0.15;
                                    ctx.beginPath();
                                    ctx.moveTo(stars[i].x, stars[i].y);
                                    ctx.lineTo(stars[j].x, stars[j].y);
                                    ctx.strokeStyle = `rgba(56, 189, 248, ${lineAlpha})`;
                                    ctx.lineWidth = 0.5;
                                    ctx.stroke();
                                }
                            }
                        }

                        for (let s of stars) {
                            s.x += s.vx;
                            s.y += s.vy;

                            if (s.x < 0) s.x = width;
                            if (s.x > width) s.x = 0;
                            if (s.y < 0) s.y = height;
                            if (s.y > height) s.y = 0;

                            const mdx = mouseX - s.x;
                            const mdy = mouseY - s.y;
                            const mdist = Math.sqrt(mdx * mdx + mdy * mdy);

                            if (mdist < 130) {
                                const mouseAlpha = (1 - mdist / 130) * 0.25;
                                ctx.beginPath();
                                ctx.moveTo(s.x, s.y);
                                ctx.lineTo(mouseX, mouseY);
                                ctx.strokeStyle = `rgba(129, 140, 248, ${mouseAlpha})`;
                                ctx.lineWidth = 0.7;
                                ctx.stroke();
                            }

                            s.alpha += Math.sin(Date.now() * s.twinkleSpeed) * 0.01;
                            const clampedAlpha = Math.max(0.1, Math.min(0.9, s.alpha));

                            ctx.beginPath();
                            ctx.arc(s.x, s.y, s.radius, 0, Math.PI * 2);
                            ctx.fillStyle = `rgba(248, 250, 252, ${clampedAlpha})`;
                            ctx.shadowBlur = 4;
                            ctx.shadowColor = '#38bdf8';
                            ctx.fill();
                            ctx.shadowBlur = 0;
                        }

                        requestAnimationFrame(animateUniverse);
                    }

                    animateUniverse();
                }

                // 2. Scroll Reveal
                const reveals = document.querySelectorAll('.reveal');
                const revealOnScroll = () => {
                    const windowHeight = window.innerHeight;
                    reveals.forEach(el => {
                        const elementTop = el.getBoundingClientRect().top;
                        if (elementTop < windowHeight - 30) {
                            el.classList.add('active');
                        }
                    });
                };
                window.addEventListener('scroll', revealOnScroll, { passive: true });
                revealOnScroll();
            });

            // 3. Safety Check-in Timer Interactive Sandbox Script
            let timerInterval = null;
            let timeLeft = 10;

            function startTestTimer() {
                if (timerInterval) clearInterval(timerInterval);
                timeLeft = 10;
                const display = document.getElementById('timer-display');
                const badge = document.getElementById('timer-status-badge');
                const alertBox = document.getElementById('portal-alert-box');

                if (display) display.innerText = '00:10';
                if (badge) {
                    badge.innerHTML = '<span class="beacon-dot pulse" style="color:oklch(0.80 0.18 85);" aria-hidden="true"></span>Armed & Countdown';
                    badge.className = 'badge badge-campus';
                }
                if (alertBox) alertBox.style.display = 'none';

                timerInterval = setInterval(() => {
                    timeLeft--;
                    const secStr = timeLeft < 10 ? `0${timeLeft}` : `${timeLeft}`;
                    if (display) display.innerText = `00:${secStr}`;

                    if (timeLeft <= 0) {
                        clearInterval(timerInterval);
                        timerInterval = null;
                        if (badge) {
                            badge.innerHTML = '<span class="beacon-dot pulse" style="color:oklch(0.71 0.22 0);" aria-hidden="true"></span>Alert Dispatched!';
                            badge.className = 'badge badge-rose';
                        }
                        if (alertBox) alertBox.style.display = 'block';
                    }
                }, 1000);
            }

            function disarmTestTimer() {
                if (timerInterval) {
                    clearInterval(timerInterval);
                    timerInterval = null;
                }
                timeLeft = 10;
                const display = document.getElementById('timer-display');
                const badge = document.getElementById('timer-status-badge');
                const alertBox = document.getElementById('portal-alert-box');

                if (display) display.innerText = '00:10';
                if (badge) {
                    badge.innerHTML = '<span class="beacon-hex" style="color:oklch(0.74 0.20 165);" aria-hidden="true"></span>Disarmed via PIN';
                    badge.className = 'badge badge-live';
                }
                if (alertBox) alertBox.style.display = 'none';
            }
        </script>
    </body>
</html>
"""
    backend_url = str(settings.backend_url or f"https://{settings.app_domain}")
    return HTMLResponse(
        content=html_template.replace(
            "https://nexus-engine.app",
            backend_url,
        ),
    )


@router.get("/help", response_class=FileResponse)
@router.get("/faq", response_class=FileResponse)
async def render_help_page():
    return FileResponse(
        os.path.join(STATIC_DIR, "help.html"),
        media_type="text/html",
    )


@router.get("/contact", response_class=HTMLResponse)
async def render_contact_page():
    turnstile_site_key = settings.turnstile_site_key or ""
    backend_url = str(settings.backend_url or f"https://{settings.app_domain}")

    html_content = """<!DOCTYPE html>
<html lang="en">
    <head>
        <meta charset="UTF-8">
        <meta name="viewport" content="width=device-width, initial-scale=1.0">
        <meta name="theme-color" content="#04060f">
        <meta name="description" content="Nexus Support & Contact Portal. Submit support requests, account suspension appeals, bug reports, product feedback, and security disclosures.">
        <title>Contact Us & Support Portal - Nexus</title>

        <!-- Favicons -->
        <link rel="icon" type="image/x-icon" href="/favicon.ico">
        <link rel="icon" type="image/png" sizes="32x32" href="/favicon-32x32.png">
        <link rel="icon" type="image/png" sizes="16x16" href="/favicon-16x16.png">
        <link rel="apple-touch-icon" sizes="180x180" href="/apple-touch-icon.png">

        <!-- Fonts: Sora + JetBrains Mono + Nunito Sans -->
        <link rel="preconnect" href="https://fonts.googleapis.com">
        <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
        <link href="https://fonts.googleapis.com/css2?family=Sora:wght@400;500;600;700;800&family=Nunito+Sans:ital,wght@0,400;0,500;0,600;0,700;1,400&family=JetBrains+Mono:wght@400;500;700&display=swap" rel="stylesheet">

        <!-- Tailwind v4 & Lucide Icons -->
        <script src="https://cdn.jsdelivr.net/npm/@tailwindcss/browser@4"></script>
        <script src="https://cdn.jsdelivr.net/npm/lucide@latest/dist/umd/lucide.min.js"></script>

        <!-- Cloudflare Turnstile -->
        <script src="https://challenges.cloudflare.com/turnstile/v0/api.js" async defer></script>

        <style>
            :root {
                --font-display: 'Sora', sans-serif;
                --font-body: 'Nunito Sans', sans-serif;
                --font-mono: 'JetBrains Mono', monospace;

                --void:        oklch(0.07 0.018 265);
                --void-mid:    oklch(0.10 0.022 265);
                --surface:     oklch(0.13 0.026 265);
                --surface-2:   oklch(0.16 0.024 265);
                --border:      oklch(0.22 0.020 265);

                --starlight:   oklch(0.74 0.18 205);
                --pulsar:      oklch(0.71 0.22 0);
                --nebula:      oklch(0.68 0.20 280);
                --nova:        oklch(0.80 0.19 85);
                --aurora:      oklch(0.74 0.20 165);

                --ink-1: oklch(0.97 0.005 265);
                --ink-2: oklch(0.78 0.012 265);
                --ink-3: oklch(0.58 0.015 265);
            }

            *, *::before, *::after { box-sizing: border-box; margin: 0; padding: 0; }
            html { scroll-behavior: smooth; }
            body {
                font-family: var(--font-body);
                background: var(--void);
                color: var(--ink-1);
                overflow-x: hidden;
                -webkit-font-smoothing: antialiased;
            }

            .f-display { font-family: var(--font-display); letter-spacing: -0.025em; }
            .f-mono    { font-family: var(--font-mono); }

            #cosmos-canvas {
                position: fixed; inset: 0; pointer-events: none; z-index: 0;
            }

            .glass-card {
                background: rgba(16, 20, 38, 0.7);
                backdrop-filter: blur(16px);
                border: 1px solid var(--border);
                border-radius: 1.25rem;
                box-shadow: 0 20px 50px rgba(0, 0, 0, 0.5);
                transition: border-color 0.3s ease, transform 0.3s ease;
            }

            .category-card {
                cursor: pointer;
                border: 1px solid var(--border);
                background: rgba(22, 27, 48, 0.6);
                border-radius: 1rem;
                padding: 1.25rem;
                transition: all 0.25s cubic-bezier(0.4, 0, 0.2, 1);
            }
            .category-card:hover {
                border-color: var(--starlight);
                transform: translateY(-2px);
                background: rgba(30, 38, 66, 0.8);
            }
            .category-card.selected {
                border-color: var(--nebula);
                background: linear-gradient(135deg, rgba(79, 70, 229, 0.25), rgba(124, 58, 237, 0.25));
                box-shadow: 0 0 20px rgba(124, 58, 237, 0.3);
            }

            .input-field {
                width: 100%;
                background: rgba(10, 14, 28, 0.8);
                border: 1px solid var(--border);
                border-radius: 0.75rem;
                padding: 0.875rem 1rem;
                color: var(--ink-1);
                font-family: var(--font-body);
                font-size: 0.95rem;
                outline: none;
                transition: border-color 0.2s, box-shadow 0.2s;
            }
            .input-field:focus {
                border-color: var(--starlight);
                box-shadow: 0 0 0 3px rgba(74, 222, 128, 0.15);
            }

            .btn-primary {
                background: linear-gradient(135deg, #4F46E5 0%, #7C3AED 100%);
                color: #FFFFFF;
                font-weight: 700;
                border-radius: 0.75rem;
                padding: 0.875rem 1.75rem;
                border: none;
                cursor: pointer;
                transition: all 0.2s ease;
                display: inline-flex;
                align-items: center;
                justify-content: center;
                gap: 0.5rem;
                font-family: var(--font-display);
            }
            .btn-primary:hover {
                transform: translateY(-1px);
                box-shadow: 0 8px 25px rgba(124, 58, 237, 0.4);
            }
            .btn-primary:disabled {
                opacity: 0.5;
                cursor: not-allowed;
                transform: none;
                box-shadow: none;
            }

            .badge {
                display: inline-flex;
                align-items: center;
                gap: 0.5rem;
                padding: 0.35rem 0.85rem;
                border-radius: 9999px;
                font-size: 0.75rem;
                font-weight: 700;
                letter-spacing: 0.05em;
                text-transform: uppercase;
                border: 1px solid rgba(124, 58, 237, 0.3);
                background: rgba(124, 58, 237, 0.15);
                color: #A78BFA;
            }

            .footer-link {
                color: var(--ink-2);
                text-decoration: none;
                font-size: 0.875rem;
                transition: all 0.2s;
                position: relative;
                padding-bottom: 2px;
            }
            .footer-link:hover { color: var(--ink-1); }
            .footer-link.active {
                color: var(--starlight) !important;
                font-weight: 700 !important;
                border-bottom: 2px solid var(--starlight);
            }
        </style>
    </head>
    <body>
        <canvas id="cosmos-canvas"></canvas>

        <!-- Navbar -->
        <header style="position:sticky;top:0;z-index:50;background:rgba(7,9,20,0.85);backdrop-filter:blur(16px);border-bottom:1px solid var(--border);">
            <div style="max-width:1200px;margin:0 auto;padding:1rem 1.5rem;display:flex;align-items:center;justify-content:space-between;">
                <a href="/" style="display:flex;align-items:center;gap:0.75rem;text-decoration:none;">
                    <img src="/logo.png" alt="Nexus Logo" width="32" height="32" style="border-radius:0.5rem;">
                    <span class="f-display" style="font-weight:800;font-size:1.25rem;color:var(--ink-1);">NEXUS</span>
                </a>
                <nav style="display:flex;align-items:center;gap:1.75rem;">
                    <a href="/" class="footer-link">Home</a>
                    <a href="/help" class="footer-link">Help Center</a>
                    <a href="/legal" class="footer-link">Legal & Privacy</a>
                    <a href="/contact" class="footer-link active">Contact Us</a>
                </nav>
            </div>
        </header>

        <!-- Main Content Container -->
        <main style="position:relative;z-index:10;max-width:1100px;margin:3rem auto;padding:0 1.5rem 6rem;">
            <!-- Hero Header -->
            <div style="text-align:center;margin-bottom:3.5rem;">
                <div class="badge" style="margin-bottom:1rem;">
                    <i data-lucide="shield-alert" style="width:14px;height:14px;"></i>
                    NEXUS SUPPORT & CONTACT PORTAL
                </div>
                <h1 class="f-display" style="font-size:2.75rem;font-weight:800;line-height:1.2;margin-bottom:1rem;">
                    How can we help your <span style="background:linear-gradient(135deg,var(--starlight),var(--nebula));-webkit-background-clip:text;-webkit-text-fill-color:transparent;">orbit</span>?
                </h1>
                <p style="color:var(--ink-2);font-size:1.1rem;max-width:650px;margin:0 auto;line-height:1.6;">
                    Whether you are appealing an account suspension, reporting a bug, providing feedback, or asking a support question, our team is here for you.
            </div>

            <!-- Main Form Card -->
            <div class="glass-card" style="padding:2.5rem;">

                <!-- Category Selection -->
                <div style="margin-bottom:2.5rem;">
                    <label class="f-display" style="display:block;font-size:0.9rem;font-weight:700;text-transform:uppercase;letter-spacing:0.05em;color:var(--ink-2);margin-bottom:1rem;">
                        Select Inquiry Topic
                    </label>
                    <div style="display:grid;grid-template-columns:repeat(auto-fit, minmax(200px, 1fr));gap:1rem;">
                        <div class="category-card selected" onclick="selectCategory('suspended', this)">
                            <div style="display:flex;align-items:center;gap:0.75rem;margin-bottom:0.5rem;">
                                <i data-lucide="shield-off" style="color:var(--pulsar);width:20px;height:20px;"></i>
                                <span class="f-display" style="font-weight:700;font-size:0.95rem;">Suspended Account</span>
                            </div>
                            <p style="font-size:0.8rem;color:var(--ink-3);line-height:1.4;">Appeal an active suspension, restriction, or block on your account.</p>
                        </div>

                        <div class="category-card" onclick="selectCategory('help', this)">
                            <div style="display:flex;align-items:center;gap:0.75rem;margin-bottom:0.5rem;">
                                <i data-lucide="help-circle" style="color:var(--starlight);width:20px;height:20px;"></i>
                                <span class="f-display" style="font-weight:700;font-size:0.95rem;">General Support</span>
                            </div>
                            <p style="font-size:0.8rem;color:var(--ink-3);line-height:1.4;">Get help with account settings, orbits, discovery, or profile management.</p>
                        </div>

                        <div class="category-card" onclick="selectCategory('feedback', this)">
                            <div style="display:flex;align-items:center;gap:0.75rem;margin-bottom:0.5rem;">
                                <i data-lucide="lightbulb" style="color:var(--nova);width:20px;height:20px;"></i>
                                <span class="f-display" style="font-weight:700;font-size:0.95rem;">Product Feedback</span>
                            </div>
                            <p style="font-size:0.8rem;color:var(--ink-3);line-height:1.4;">Share suggestions, new feature requests, or UI improvements.</p>
                        </div>

                        <div class="category-card" onclick="selectCategory('bug_report', this)">
                            <div style="display:flex;align-items:center;gap:0.75rem;margin-bottom:0.5rem;">
                                <i data-lucide="bug" style="color:#F43F5E;width:20px;height:20px;"></i>
                                <span class="f-display" style="font-weight:700;font-size:0.95rem;">Bug Report</span>
                            </div>
                            <p style="font-size:0.8rem;color:var(--ink-3);line-height:1.4;">Report crashes, technical glitches, or broken app functionality.</p>
                        </div>

                        <div class="category-card" onclick="selectCategory('security', this)">
                            <div style="display:flex;align-items:center;gap:0.75rem;margin-bottom:0.5rem;">
                                <i data-lucide="lock" style="color:var(--aurora);width:20px;height:20px;"></i>
                                <span class="f-display" style="font-weight:700;font-size:0.95rem;">Security & Privacy</span>
                            </div>
                            <p style="font-size:0.8rem;color:var(--ink-3);line-height:1.4;">Responsible vulnerability disclosure, privacy requests, or safety.</p>
                        </div>
                    </div>
                </div>

                <!-- Step 2: Form Inputs -->
                <form id="contact-form" onsubmit="event.preventDefault();">
                    <input type="hidden" id="selected-query-type" value="suspended">

                    <div style="display:grid;grid-template-columns:repeat(auto-fit, minmax(280px, 1fr));gap:1.25rem;margin-bottom:1.25rem;">
                        <div>
                            <label style="display:block;font-size:0.85rem;font-weight:600;color:var(--ink-2);margin-bottom:0.5rem;">Full Name (Optional)</label>
                            <input type="text" id="input-name" class="input-field" placeholder="e.g. Alex Morgan">
                        </div>
                        <div>
                            <label style="display:block;font-size:0.85rem;font-weight:600;color:var(--ink-2);margin-bottom:0.5rem;">Email Address <span style="color:var(--pulsar);">*</span></label>
                            <input type="email" id="input-email" class="input-field" placeholder="you@example.com" required>
                        </div>
                    </div>

                    <div style="margin-bottom:1.25rem;">
                        <label style="display:block;font-size:0.85rem;font-weight:600;color:var(--ink-2);margin-bottom:0.5rem;">Registered Phone Number (Optional)</label>
                        <input type="text" id="input-account-id" class="input-field" placeholder="e.g. +1234567890 (Recommended for account appeals)">
                    </div>

                    <div style="margin-bottom:1.25rem;">
                        <label style="display:block;font-size:0.85rem;font-weight:600;color:var(--ink-2);margin-bottom:0.5rem;">Subject <span style="color:var(--pulsar);">*</span></label>
                        <input type="text" id="input-subject" class="input-field" placeholder="Brief summary of your inquiry" required minlength="3" maxlength="150">
                    </div>

                    <div id="github-url-group" style="display:none;margin-bottom:1.25rem;">
                        <label style="display:block;font-size:0.85rem;font-weight:600;color:var(--ink-2);margin-bottom:0.5rem;">Linked GitHub Issue URL (Optional)</label>
                        <input type="url" id="input-github-url" class="input-field" placeholder="https://github.com/devakesu/Nexus/issues/123">
                    </div>

                    <div style="margin-bottom:1.5rem;">
                        <div style="display:flex;justify-content:space-between;align-items:center;margin-bottom:0.5rem;">
                            <label style="font-size:0.85rem;font-weight:600;color:var(--ink-2);">Detailed Message <span style="color:var(--pulsar);">*</span></label>
                            <span id="char-counter" class="f-mono" style="font-size:0.75rem;color:var(--ink-3);">0 / 5000</span>
                        </div>
                        <textarea id="input-message" class="input-field" rows="6" placeholder="Please describe your issue or question in detail..." required minlength="10" maxlength="5000" oninput="updateCharCounter(this)"></textarea>
                    </div>

                    <!-- Cloudflare Turnstile Widget (If Turnstile key configured) -->
                    __TURNSTILE_WIDGET_HTML__

                    <!-- OTP Gating Section -->
                    <div style="border-top:1px solid var(--border);padding-top:1.5rem;margin-top:1.5rem;">
                        <div id="otp-request-step">
                            <p style="font-size:0.875rem;color:var(--ink-2);margin-bottom:1rem;">
                                Security Check: Request a 6-digit verification code sent to your email before submitting.
                            </p>
                            <button type="button" id="btn-send-otp" class="btn-primary" onclick="requestOtp()">
                                <i data-lucide="mail-check" style="width:18px;height:18px;"></i>
                                Send Email Verification Code
                            </button>
                        </div>

                        <!-- OTP Verification Step (Hidden until OTP requested) -->
                        <div id="otp-verify-step" style="display:none;background:rgba(10,14,28,0.6);border:1px solid var(--border);border-radius:1rem;padding:1.5rem;margin-top:1rem;">
                            <div style="display:flex;align-items:center;gap:0.5rem;color:var(--starlight);margin-bottom:0.75rem;">
                                <i data-lucide="key-round" style="width:18px;height:18px;"></i>
                                <span class="f-display" style="font-weight:700;font-size:0.95rem;">Enter 6-Digit Verification Code</span>
                            </div>
                            <p style="font-size:0.85rem;color:var(--ink-2);margin-bottom:1rem;">
                                We've sent a verification code to <span id="sent-email-display" style="color:var(--ink-1);font-weight:600;"></span>.
                            </p>
                            <div style="display:flex;gap:0.75rem;align-items:center;margin-bottom:1.25rem;">
                                <input type="text" id="input-otp" class="input-field f-mono" placeholder="123456" maxlength="6" style="max-width:200px;letter-spacing:0.25em;font-size:1.2rem;text-align:center;">
                                <button type="button" id="btn-submit-ticket" class="btn-primary" onclick="submitForm()">
                                    <i data-lucide="send" style="width:18px;height:18px;"></i>
                                    Submit Ticket
                                </button>
                            </div>
                            <p style="font-size:0.8rem;color:var(--ink-3);">
                                Didn't receive the code? <a href="#" id="resend-link" onclick="requestOtp(); return false;" style="color:var(--starlight);text-decoration:none;font-weight:600;">Resend OTP</a> <span id="resend-timer" class="f-mono"></span>
                            </p>
                        </div>
                    </div>
                </form>

                <!-- Feedback Status Message Box -->
                <div id="status-box" style="display:none;margin-top:1.5rem;padding:1rem;border-radius:0.75rem;font-size:0.9rem;"></div>

                <!-- Success Screen (Hidden by default) -->
                <div id="success-screen" style="display:none;text-align:center;padding:2rem 1rem;">
                    <div style="width:64px;height:64px;border-radius:50%;background:rgba(16,185,129,0.15);border:1px solid rgba(16,185,129,0.4);display:flex;align-items:center;justify-content:center;margin:0 auto 1.5rem;color:var(--aurora);">
                        <i data-lucide="check-circle" style="width:36px;height:36px;"></i>
                    </div>
                    <h2 class="f-display" style="font-size:1.75rem;font-weight:800;margin-bottom:0.75rem;">Support Ticket Created!</h2>
                    <p style="color:var(--ink-2);font-size:1rem;max-width:500px;margin:0 auto 1.5rem;line-height:1.6;">
                        Your ticket <span id="ticket-id-tag" class="f-mono" style="color:var(--starlight);font-weight:700;"></span> has been successfully logged. A confirmation receipt has been sent to your email.
                    </p>
                    <div style="background:rgba(10,14,28,0.8);border:1px solid var(--border);border-radius:1rem;padding:1.25rem;max-width:480px;margin:0 auto 2rem;text-align:left;">
                        <div style="font-size:0.8rem;color:var(--ink-3);text-transform:uppercase;letter-spacing:0.05em;margin-bottom:0.5rem;" class="f-mono">Ticket Summary</div>
                        <div style="display:flex;justify-content:space-between;font-size:0.9rem;margin-bottom:0.4rem;">
                            <span style="color:var(--ink-2);">Category:</span>
                            <span id="summary-category" style="color:var(--ink-1);font-weight:600;text-transform:capitalize;"></span>
                        </div>
                        <div style="display:flex;justify-content:space-between;font-size:0.9rem;">
                            <span style="color:var(--ink-2);">Estimated Review:</span>
                            <span style="color:var(--aurora);font-weight:600;">24–48 Hours</span>
                        </div>
                    </div>
                    <button class="btn-primary" onclick="resetForm()">
                        <i data-lucide="plus-circle" style="width:18px;height:18px;"></i>
                        Submit Another Inquiry
                    </button>
                </div>
            </div>

            <!-- Self-Service FAQ Section -->
            <div style="margin-top:5rem;">
                <h3 class="f-display" style="font-size:1.5rem;font-weight:800;margin-bottom:1.5rem;text-align:center;">
                    Frequently Asked Questions
                </h3>
                <div style="display:flex;flex-direction:column;gap:1rem;max-width:800px;margin:0 auto;">
                    <div class="glass-card" style="padding:1.25rem;">
                        <h4 class="f-display" style="font-size:1rem;font-weight:700;margin-bottom:0.5rem;color:var(--starlight);">How do account suspension appeals work?</h4>
                        <p style="font-size:0.9rem;color:var(--ink-2);line-height:1.6;">If your account was suspended or restricted, select 'Suspended Account' as your topic. Submit your registered email or phone number along with details regarding your appeal. Our safety team reviews every appeal within 24-48 hours.</p>
                    </div>
                    <div class="glass-card" style="padding:1.25rem;">
                        <h4 class="f-display" style="font-size:1rem;font-weight:700;margin-bottom:0.5rem;color:var(--starlight);">Why is email OTP verification required?</h4>
                        <p style="font-size:0.9rem;color:var(--ink-2);line-height:1.6;">Email OTP verification prevents spam and ensures that ticket update notifications reach a valid, accessible inbox.</p>
                    </div>
                    <div class="glass-card" style="padding:1.25rem;">
                        <h4 class="f-display" style="font-size:1rem;font-weight:700;margin-bottom:0.5rem;color:var(--starlight);">How can I track my ticket status?</h4>
                        <p style="font-size:0.9rem;color:var(--ink-2);line-height:1.6;">Log into the Nexus Mobile App and visit <strong>Settings → Help, Feedback & Bug Report</strong> to view ticket progress, read staff comments, or add follow-up details.</p>
                    </div>
                </div>
            </div>
        </main>

        <!-- Footer -->
        <footer style="border-top: 1px solid var(--border); background: oklch(0.06 0.015 265); padding: 2.5rem 1.5rem; margin-top: auto; position: relative; z-index: 10;">
            <div style="max-width: 1200px; margin: 0 auto; display: flex; flex-wrap: wrap; align-items: center; justify-content: space-between; gap: 1.5rem;">
                <div style="display: flex; align-items: center; gap: 0.75rem;">
                    <img src="/logo.png" alt="Nexus Engine" style="width: 24px; height: 24px; opacity: 0.8;">
                    <span class="f-display" style="font-weight: 700; font-size: 0.9rem; color: #fff;">Nexus Engine</span>
                    <span style="font-size: 0.75rem; color: var(--ink-3);">&copy; 2026 <a href="https://devakesu.com" target="_blank" rel="noopener noreferrer" style="color: var(--ink-2); text-decoration: none; font-weight: 600;">@devakesu</a>. All rights reserved.</span>
                </div>

                <div style="display: flex; align-items: center; gap: 1.5rem; font-size: 0.825rem;">
                    <a href="/" class="footer-link">Home</a>
                    <a href="/help" class="footer-link">Help Center</a>
                    <a href="/contact" class="footer-link active">Contact Us</a>
                    <a href="https://github.com/devakesu/Nexus" target="_blank" rel="noopener noreferrer" class="footer-link">GitHub</a>
                </div>
            </div>
        </footer>

        <script>
            lucide.createIcons();

            let turnstileToken = null;
            let resendTimer = null;

            function selectCategory(type, element) {
                document.querySelectorAll('.category-card').forEach(el => el.classList.remove('selected'));
                element.classList.add('selected');
                document.getElementById('selected-query-type').value = type;

                const githubGroup = document.getElementById('github-url-group');
                if (type === 'bug_report') {
                    githubGroup.style.display = 'block';
                } else {
                    githubGroup.style.display = 'none';
                }
            }

            function updateCharCounter(textarea) {
                const count = textarea.value.length;
                document.getElementById('char-counter').innerText = `${count} / 5000`;
            }

            function showStatus(message, isError = false) {
                const box = document.getElementById('status-box');
                box.style.display = 'block';
                box.style.background = isError ? 'rgba(244,63,94,0.15)' : 'rgba(16,185,129,0.15)';
                box.style.border = isError ? '1px solid rgba(244,63,94,0.4)' : '1px solid rgba(16,185,129,0.4)';
                box.style.color = isError ? '#FDA4AF' : '#A7F3D0';
                box.innerText = message;
            }

            function clearStatus() {
                const box = document.getElementById('status-box');
                box.style.display = 'none';
            }

            async function requestOtp() {
                clearStatus();
                const email = document.getElementById('input-email').value.trim();
                if (!email || !email.includes('@')) {
                    showStatus('Please enter a valid email address.', true);
                    return;
                }

                const btn = document.getElementById('btn-send-otp');
                btn.disabled = true;
                btn.innerText = 'Sending OTP...';

                try {
                    const resp = await fetch('/api/v1/contact/otp/send', {
                        method: 'POST',
                        headers: { 'Content-Type': 'application/json' },
                        body: JSON.stringify({
                            email: email,
                            turnstile_token: turnstileToken
                        })
                    });
                    const data = await resp.json();
                    if (!resp.ok) {
                        throw new Error(data.detail || 'Failed to send verification email.');
                    }

                    document.getElementById('sent-email-display').innerText = email;
                    document.getElementById('otp-verify-step').style.display = 'block';
                    document.getElementById('otp-request-step').style.display = 'none';
                    showStatus('Verification code sent! Please check your email inbox.', false);
                    startResendTimer();
                } catch (err) {
                    showStatus(err.message, true);
                } finally {
                    btn.disabled = false;
                    btn.innerText = 'Send Email Verification Code';
                }
            }

            function startResendTimer() {
                let seconds = 60;
                const link = document.getElementById('resend-link');
                const timerSpan = document.getElementById('resend-timer');
                link.style.pointerEvents = 'none';
                link.style.opacity = '0.5';

                if (resendTimer) clearInterval(resendTimer);
                resendTimer = setInterval(() => {
                    seconds--;
                    timerSpan.innerText = `(${seconds}s)`;
                    if (seconds <= 0) {
                        clearInterval(resendTimer);
                        timerSpan.innerText = '';
                        link.style.pointerEvents = 'auto';
                        link.style.opacity = '1';
                    }
                }, 1000);
            }

            async function submitForm() {
                clearStatus();
                const email = document.getElementById('input-email').value.trim();
                const otpCode = document.getElementById('input-otp').value.trim();
                const queryType = document.getElementById('selected-query-type').value;
                const subject = document.getElementById('input-subject').value.trim();
                const message = document.getElementById('input-message').value.trim();
                const name = document.getElementById('input-name').value.trim();
                const accountId = document.getElementById('input-account-id').value.trim();
                const githubUrl = document.getElementById('input-github-url').value.trim();

                if (!otpCode || otpCode.length !== 6) {
                    showStatus('Please enter the 6-digit verification code.', true);
                    return;
                }
                if (!subject || subject.length < 3) {
                    showStatus('Subject must be at least 3 characters long.', true);
                    return;
                }
                if (!message || message.length < 10) {
                    showStatus('Message must be at least 10 characters long.', true);
                    return;
                }

                const submitBtn = document.getElementById('btn-submit-ticket');
                submitBtn.disabled = true;
                submitBtn.innerText = 'Submitting...';

                try {
                    const resp = await fetch('/api/v1/contact/submit', {
                        method: 'POST',
                        headers: { 'Content-Type': 'application/json' },
                        body: JSON.stringify({
                            email: email,
                            otp_code: otpCode,
                            query_type: queryType,
                            subject: subject,
                            message: message,
                            name: name || null,
                            account_id_or_phone: accountId || null,
                            github_issue_url: githubUrl || null,
                            turnstile_token: turnstileToken
                        })
                    });
                    const data = await resp.json();
                    if (!resp.ok) {
                        throw new Error(data.detail || 'Failed to submit ticket.');
                    }

                    document.getElementById('contact-form').style.display = 'none';
                    document.getElementById('success-screen').style.display = 'block';
                    document.getElementById('ticket-id-tag').innerText = '#' + (data.ticket_id ? data.ticket_id.substring(0,8).toUpperCase() : 'NEXUS-TICKET');
                    document.getElementById('summary-category').innerText = queryType.replace('_', ' ');
                } catch (err) {
                    showStatus(err.message, true);
                } finally {
                    submitBtn.disabled = false;
                    submitBtn.innerText = 'Submit Ticket';
                }
            }

            function resetForm() {
                document.getElementById('contact-form').reset();
                document.getElementById('contact-form').style.display = 'block';
                document.getElementById('success-screen').style.display = 'none';
                document.getElementById('otp-verify-step').style.display = 'none';
                document.getElementById('otp-request-step').style.display = 'block';
                clearStatus();
            }

            // Turnstile Callback if present
            window.onTurnstileSuccess = function(token) {
                turnstileToken = token;
            };

            // Cosmos Canvas Animation
            const canvas = document.getElementById('cosmos-canvas');
            if (canvas) {
                const ctx = canvas.getContext('2d');
                let width = canvas.width = window.innerWidth;
                let height = canvas.height = window.innerHeight;

                window.addEventListener('resize', () => {
                    width = canvas.width = window.innerWidth;
                    height = canvas.height = window.innerHeight;
                });

                const stars = Array.from({ length: 45 }, () => ({
                    x: Math.random() * width,
                    y: Math.random() * height,
                    radius: Math.random() * 1.5 + 0.5,
                    vx: (Math.random() - 0.5) * 0.2,
                    vy: (Math.random() - 0.5) * 0.2,
                    alpha: Math.random() * 0.6 + 0.2
                }));

                function drawUniverse() {
                    ctx.clearRect(0, 0, width, height);
                    stars.forEach(s => {
                        s.x += s.vx;
                        s.y += s.vy;
                        if (s.x < 0) s.x = width;
                        if (s.x > width) s.x = 0;
                        if (s.y < 0) s.y = height;
                        if (s.y > height) s.y = 0;

                        ctx.beginPath();
                        ctx.arc(s.x, s.y, s.radius, 0, Math.PI * 2);
                        ctx.fillStyle = `rgba(167, 139, 250, ${s.alpha})`;
                        ctx.fill();
                    });
                    requestAnimationFrame(drawUniverse);
                }
                drawUniverse();
            }
        </script>
    </body>
</html>
"""

    turnstile_widget_html = ""
    if turnstile_site_key:
        turnstile_widget_html = f"""
        <div class="my-4 flex justify-center">
            <div class="cf-turnstile" data-sitekey="{turnstile_site_key}" data-callback="onTurnstileSuccess" data-theme="dark"></div>
        </div>
        """

    return HTMLResponse(
        content=html_content.replace("__TURNSTILE_WIDGET_HTML__", turnstile_widget_html).replace(
            "https://nexus-engine.app", backend_url
        )
    )

