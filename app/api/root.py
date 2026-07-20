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
        <loc>{settings.backend_url}/faq</loc>
        <changefreq>monthly</changefreq>
        <priority>0.5</priority>
    </url>
</urlset>"""
    return Response(content=xml_content, media_type="application/xml")


@router.get("/", response_class=HTMLResponse)
async def render_landing_page():
    html_template = """<!DOCTYPE html>
<html lang="en" class="scroll-smooth">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <meta name="theme-color" content="#080616">
    <meta name="description" content="Nexus - Next-generation hyper-proximity social discovery, E2E encrypted messaging, and synchronized vibe pooling built on zero-knowledge architecture.">
    <meta name="keywords" content="Nexus, Social Discovery, Proximity Engine, Encrypted Chat, Music Pooling, Security, Zero-Knowledge">
    <meta name="author" content="Nexus Engine Team">

    <!-- Open Graph / Facebook -->
    <meta property="og:type" content="website">
    <meta property="og:url" content="https://nexus-engine.app/">
    <meta property="og:title" content="Nexus Orbot - Sync Your Circle">
    <meta property="og:description" content="Hyper-proximity social discovery matrix with zero-knowledge encryption and failsafe human protection networks.">
    <meta property="og:image" content="/nexus-wide-logo.jpg">
    <meta property="og:site_name" content="Nexus Platform">

    <!-- Twitter -->
    <meta property="twitter:card" content="summary_large_image">
    <meta property="twitter:url" content="https://nexus-engine.app/">
    <meta property="twitter:title" content="Nexus - Sync Your Circle">
    <meta property="twitter:description" content="Hyper-proximity social discovery matrix with zero-knowledge encryption and failsafe human protection networks.">
    <meta property="twitter:image" content="/nexus-wide-logo.jpg">

    <title>Nexus - Sync Your Circle</title>

    <!-- Favicon Links -->
    <link rel="icon" type="image/x-icon" href="/favicon.ico">
    <link rel="icon" type="image/png" sizes="32x32" href="/favicon-32x32.png">
    <link rel="icon" type="image/png" sizes="16x16" href="/favicon-16x16.png">
    <link rel="apple-touch-icon" sizes="180x180" href="/apple-touch-icon.png">
    <link rel="manifest" href="/site.webmanifest">

    <!-- Google Fonts -->
    <link rel="preconnect" href="https://fonts.googleapis.com">
    <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
    <link href="https://fonts.googleapis.com/css2?family=Inter:wght@300;400;500;600;700&family=JetBrains+Mono:wght@400;500;700&family=Manrope:wght@600;700;800&family=Orbitron:wght@700;800;900&display=swap" rel="stylesheet">

    <!-- Tailwind CSS CDN -->
    <script src="https://cdn.jsdelivr.net/npm/@tailwindcss/browser@4"></script>
    <!-- FontAwesome for Social Icons & Badges -->
    <link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.5.1/css/all.min.css">

    <!-- Design System Tokens & Custom Styles -->
    <style>
        :root {
            --font-display: 'Orbitron', sans-serif;
            --font-headline: 'Manrope', sans-serif;
            --font-body: 'Inter', sans-serif;
            --font-mono: 'JetBrains Mono', monospace;

            --color-teal: #0891B2;
            --color-pink: #FF7597;
            --color-bg: #080616;
            --color-surface: #0F172A;
        }

        body {
            font-family: var(--font-body);
            background-color: var(--color-bg);
            color: #F8FAFC;
        }

        .font-display { font-family: var(--font-display); letter-spacing: -0.02em; }
        .font-headline { font-family: var(--font-headline); }
        .font-mono { font-family: var(--font-mono); }

        @keyframes float {
            0%, 100% { transform: translateY(0px) rotate(0deg); }
            50% { transform: translateY(-8px) rotate(1deg); }
        }
        .animate-float { animation: float 6s ease-in-out infinite; }

        .reveal { opacity: 0; transform: translateY(24px); transition: all 0.7s cubic-bezier(0.16, 1, 0.3, 1); }
        .reveal.active { opacity: 1; transform: translateY(0); }

        .glass-card {
            background: rgba(15, 23, 42, 0.75);
            backdrop-filter: blur(16px);
            -webkit-backdrop-filter: blur(16px);
            border: 1px solid rgba(255, 255, 255, 0.1);
        }

        .glass-card:hover {
            border-color: rgba(8, 145, 178, 0.4);
            box-shadow: 0 10px 30px -10px rgba(8, 145, 178, 0.25);
        }

        /* Focus accessibility outline */
        a:focus-visible, button:focus-visible {
            outline: 2px solid #0891B2;
            outline-offset: 3px;
            border-radius: 6px;
        }

        @media (prefers-reduced-motion: reduce) {
            .animate-float, .animate-pulse, .animate-bounce, .animate-ping {
                animation: none !important;
            }
            .reveal {
                opacity: 1 !important;
                transform: none !important;
                transition: none !important;
            }
        }
    </style>
</head>
<body class="bg-[#080616] text-slate-100 antialiased overflow-x-hidden selection:bg-cyan-500 selection:text-slate-950">

    <!-- Accessibility Skip Link -->
    <a href="#main-content" class="sr-only focus:not-sr-only focus:absolute focus:top-4 focus:left-4 focus:z-[100] focus:px-4 focus:py-2.5 focus:bg-cyan-500 focus:text-slate-950 focus:font-bold focus:rounded-xl focus:shadow-2xl">
        Skip to main content
    </a>

    <!-- Ambient Lighting Visual Artifacts -->
    <div class="fixed top-0 left-1/4 w-[500px] h-[500px] bg-cyan-600/15 rounded-full filter blur-[140px] pointer-events-none z-0"></div>
    <div class="fixed top-[600px] right-1/4 w-[500px] h-[500px] bg-pink-600/15 rounded-full filter blur-[160px] pointer-events-none z-0"></div>

    <!-- Header Navigation -->
    <header class="fixed top-0 left-0 right-0 z-50 glass-card border-b border-slate-800/60" role="banner">
        <div class="max-w-7xl mx-auto px-6 h-20 flex items-center justify-between">
            <a href="/" class="flex items-center gap-3 group" aria-label="Nexus Home">
                <img src="/logo.png" alt="Nexus App Logo" class="w-10 h-10 rounded-xl shadow-lg shadow-cyan-500/20 group-hover:scale-105 transition-transform" width="40" height="40">
                <span class="font-display text-xl font-bold tracking-wider bg-clip-text text-transparent bg-gradient-to-r from-white via-slate-200 to-cyan-400">NEXUS</span>
            </a>

            <nav class="hidden md:flex items-center gap-8 text-sm font-medium text-slate-300" aria-label="Primary Navigation" role="navigation">
                <a href="#features" class="hover:text-cyan-400 transition-colors">Features</a>
                <a href="#security" class="hover:text-cyan-400 transition-colors">Security Matrix</a>
                <a href="#ecosystem" class="hover:text-cyan-400 transition-colors">Ecosystem</a>
                <a href="#social" class="hover:text-cyan-400 transition-colors">Community</a>
            </nav>

            <div class="flex items-center gap-4">
                <a href="#social" class="hidden sm:flex items-center gap-2 text-slate-400 hover:text-slate-200 text-sm font-medium transition-colors" aria-label="Official Social Media Platforms">
                    <i class="fa-solid fa-share-nodes text-cyan-400" aria-hidden="true"></i> Socials
                </a>
                <a href="#download" class="px-5 py-2.5 rounded-xl bg-gradient-to-r from-cyan-600 to-pink-600 hover:from-cyan-500 hover:to-pink-500 font-semibold text-sm text-white shadow-lg shadow-cyan-500/20 transition-all hover:scale-[1.02] active:scale-[0.98]">
                    Get App
                </a>
            </div>
        </div>
    </header>

    <!-- Main Content Section -->
    <main id="main-content" class="relative z-10" role="main">

        <!-- Hero Section -->
        <section class="min-h-screen pt-36 pb-20 flex items-center px-6" aria-labelledby="hero-heading">
            <div class="max-w-7xl mx-auto grid lg:grid-cols-12 gap-12 items-center w-full">
                <div class="lg:col-span-7 space-y-8 text-center lg:text-left">
                    <div class="inline-flex items-center gap-2 px-3.5 py-1.5 rounded-full bg-cyan-500/10 border border-cyan-500/25 text-xs font-semibold tracking-wide text-cyan-400 uppercase">
                        <span class="w-2 h-2 rounded-full bg-cyan-400 animate-ping" aria-hidden="true"></span>
                        <span>Nexus Engine Active - v1.0.0</span>
                    </div>

                    <h1 id="hero-heading" class="font-display text-4xl sm:text-6xl font-extrabold tracking-tight leading-[1.15] text-white">
                        Connect closer.<br>
                        Live inside your <span class="bg-clip-text text-transparent bg-gradient-to-r from-cyan-400 via-teal-300 to-pink-400">Orbit</span>.
                    </h1>

                    <p class="text-base sm:text-lg text-slate-300 max-w-2xl mx-auto lg:mx-0 font-normal leading-relaxed">
                        An integrated decentralized social discovery matrix engineered with zero-knowledge end-to-end security, high-fidelity Spotify music pooling, proximity vectors, and automated safety response systems.
                    </p>

                    <div id="download" class="flex flex-col sm:flex-row items-center justify-center lg:justify-start gap-4 pt-2">
                        <a href="https://play.google.com" target="_blank" rel="noopener noreferrer" class="w-full sm:w-auto px-8 py-4 bg-gradient-to-r from-cyan-600 to-pink-600 hover:from-cyan-500 hover:to-pink-500 font-semibold text-sm rounded-xl shadow-xl shadow-cyan-600/20 transition-all flex items-center justify-center gap-3 text-white" aria-label="Download Nexus on Google Play Store">
                            <i class="fa-brands fa-google-play text-lg" aria-hidden="true"></i> Download on Google Play
                        </a>
                        <a href="#security" class="w-full sm:w-auto px-8 py-4 glass-card font-semibold text-sm rounded-xl transition-all flex items-center justify-center gap-3 text-slate-200 hover:bg-slate-900" aria-label="Explore Platform Security Parameters">
                            <i class="fa-solid fa-shield-halved text-cyan-400 text-lg" aria-hidden="true"></i> Security Parameters
                        </a>
                    </div>
                </div>

                <!-- Interactive App Frame Hero Visual -->
                <div class="lg:col-span-5 flex justify-center relative animate-float">
                    <div class="w-72 sm:w-80 h-[580px] rounded-[44px] glass-card p-3.5 relative shadow-2xl shadow-cyan-500/15 border border-slate-700/60">
                        <div class="w-full h-full rounded-[34px] bg-[#0A0D1B] overflow-hidden relative border border-slate-800 flex flex-col justify-between p-6">
                            <!-- Mobile Notch -->
                            <div class="absolute top-0 left-1/2 transform -translate-x-1/2 w-32 h-5 bg-slate-950 rounded-b-xl z-20" aria-hidden="true"></div>

                            <!-- Screen Header -->
                            <div class="flex justify-between items-center mt-3">
                                <img src="/logo.png" alt="Nexus Brand Mark" class="w-7 h-7 rounded-lg" width="28" height="28">
                                <span class="font-mono text-[11px] tracking-widest text-cyan-400 font-bold">NEXUS MESH</span>
                                <div class="flex items-center gap-1.5">
                                    <span class="w-2 h-2 rounded-full bg-emerald-400 animate-pulse" aria-hidden="true"></span>
                                    <span class="text-[10px] text-emerald-400 font-semibold">Live</span>
                                </div>
                            </div>

                            <!-- Mock Screen Inner Content -->
                            <div class="space-y-4 my-auto">
                                <div class="p-3.5 bg-cyan-950/40 border border-cyan-500/30 rounded-xl">
                                    <div class="flex justify-between items-center text-xs mb-1.5">
                                        <span class="text-cyan-300 font-bold flex items-center gap-1.5">
                                            <i class="fa-solid fa-shield-heart text-cyan-400" aria-hidden="true"></i> Safety Shield
                                        </span>
                                        <span class="text-xs text-emerald-400 font-medium">Armed</span>
                                    </div>
                                    <p class="text-[11px] text-slate-300">Background safety audio loop active on local device buffer.</p>
                                </div>

                                <div class="p-3.5 bg-slate-900/90 border border-slate-800 rounded-xl flex items-center gap-3">
                                    <div class="w-9 h-9 rounded-lg bg-emerald-500/20 flex items-center justify-center text-emerald-400 shrink-0">
                                        <i class="fa-brands fa-spotify text-lg" aria-hidden="true"></i>
                                    </div>
                                    <div class="flex-1 min-w-0">
                                        <p class="text-xs font-bold text-slate-200 truncate">Orbit Music Sync</p>
                                        <p class="text-[10px] text-slate-400 truncate">Midnight Cyber Lo-Fi</p>
                                    </div>
                                    <div class="flex gap-1" aria-hidden="true">
                                        <span class="w-1 h-3 bg-emerald-400 block animate-bounce"></span>
                                        <span class="w-1 h-4 bg-emerald-400 block animate-bounce" style="animation-delay:0.15s"></span>
                                    </div>
                                </div>
                            </div>

                            <div class="w-full py-3 bg-gradient-to-r from-cyan-600 to-pink-600 rounded-xl text-center text-xs font-bold text-white shadow-lg">
                                <i class="fa-solid fa-radar text-white mr-1.5" aria-hidden="true"></i> 4 Nodes Discovered Nearby
                            </div>
                        </div>
                    </div>
                </div>
            </div>
        </section>

        <!-- Main Core Features Section -->
        <section id="features" class="max-w-7xl mx-auto px-6 py-28 border-t border-slate-800/80" aria-labelledby="features-heading">
            <div class="text-center max-w-3xl mx-auto mb-16 reveal">
                <h2 id="features-heading" class="font-headline text-3xl sm:text-5xl font-extrabold tracking-tight mb-4">Architecture Capabilities</h2>
                <p class="text-slate-300 text-base">Engineered with low-latency asynchronous primitives to serve privacy-first peer synchronization.</p>
            </div>

            <div class="grid sm:grid-cols-2 lg:grid-cols-4 gap-6">
                <!-- Feature 1 -->
                <div class="glass-card p-7 rounded-2xl transition-all group reveal">
                    <div class="w-12 h-12 rounded-xl bg-cyan-500/15 flex items-center justify-center text-cyan-400 mb-5 group-hover:scale-110 transition-transform">
                        <i class="fa-solid fa-shield-heart text-2xl" aria-hidden="true"></i>
                    </div>
                    <h3 class="font-headline text-lg font-bold mb-2 group-hover:text-cyan-400 transition-colors">Safety Portal Shield</h3>
                    <p class="text-sm text-slate-300 leading-relaxed">Foreground service monitoring paired with encrypted background audio analysis pipelines for user security.</p>
                </div>

                <!-- Feature 2 -->
                <div class="glass-card p-7 rounded-2xl transition-all group reveal" style="transition-delay: 0.1s">
                    <div class="w-12 h-12 rounded-xl bg-pink-500/15 flex items-center justify-center text-pink-400 mb-5 group-hover:scale-110 transition-transform">
                        <i class="fa-solid fa-satellite-dish text-2xl" aria-hidden="true"></i>
                    </div>
                    <h3 class="font-headline text-lg font-bold mb-2 group-hover:text-pink-400 transition-colors">Hyper-Proximity Orbit</h3>
                    <p class="text-sm text-slate-300 leading-relaxed">Match with nearby peers using geometric similarity vectors computed inside the core matching engine.</p>
                </div>

                <!-- Feature 3 -->
                <div class="glass-card p-7 rounded-2xl transition-all group reveal" style="transition-delay: 0.2s">
                    <div class="w-12 h-12 rounded-xl bg-emerald-500/15 flex items-center justify-center text-emerald-400 mb-5 group-hover:scale-110 transition-transform">
                        <i class="fa-brands fa-spotify text-2xl" aria-hidden="true"></i>
                    </div>
                    <h3 class="font-headline text-lg font-bold mb-2 group-hover:text-emerald-400 transition-colors">Music Vibe Pooling</h3>
                    <p class="text-sm text-slate-300 leading-relaxed">Synchronous music sharing routines that map active playback contexts to mutual discovery orbits.</p>
                </div>

                <!-- Feature 4 -->
                <div class="glass-card p-7 rounded-2xl transition-all group reveal" style="transition-delay: 0.3s">
                    <div class="w-12 h-12 rounded-xl bg-indigo-500/15 flex items-center justify-center text-indigo-400 mb-5 group-hover:scale-110 transition-transform">
                        <i class="fa-solid fa-key text-2xl" aria-hidden="true"></i>
                    </div>
                    <h3 class="font-headline text-lg font-bold mb-2 group-hover:text-indigo-400 transition-colors">Crypt-Key Messaging</h3>
                    <p class="text-sm text-slate-300 leading-relaxed">End-to-end asymmetrical key exchanges ensuring all private chat frames bypass cleartext storage.</p>
                </div>
            </div>
        </section>

        <!-- Technical Security Matrix Section -->
        <section id="security" class="bg-slate-900/60 border-y border-slate-800/80 py-24 px-6" aria-labelledby="security-heading">
            <div class="max-w-7xl mx-auto grid lg:grid-cols-2 gap-12 items-center">
                <div class="space-y-6 reveal">
                    <div class="inline-flex items-center gap-2 px-3 py-1 rounded-full bg-cyan-500/10 text-cyan-400 text-xs font-semibold uppercase tracking-wider">
                        <i class="fa-solid fa-lock" aria-hidden="true"></i> Hardened Backend Protocol
                    </div>
                    <h2 id="security-heading" class="font-headline text-3xl sm:text-4xl font-extrabold tracking-tight text-white">Strict Security Parameters</h2>
                    <p class="text-slate-300 leading-relaxed text-base">
                        The backend is equipped with strict security headers (CSP, HSTS, X-Frame-Options DENY, nosniff, Referrer-Policy), automated payload size limiting, rate limit control via Redis, and zero-knowledge end-to-end signature validation.
                    </p>
                    <ul class="space-y-3.5 text-sm text-slate-200">
                        <li class="flex items-center gap-3">
                            <i class="fa-solid fa-circle-check text-cyan-400 text-base" aria-hidden="true"></i>
                            <span>Strict Content Security Policy (CSP) &amp; HSTS 31536000 preload</span>
                        </li>
                        <li class="flex items-center gap-3">
                            <i class="fa-solid fa-circle-check text-cyan-400 text-base" aria-hidden="true"></i>
                            <span>Payload size guard (10MB max body limit) &amp; Redis rate limiter</span>
                        </li>
                        <li class="flex items-center gap-3">
                            <i class="fa-solid fa-circle-check text-cyan-400 text-base" aria-hidden="true"></i>
                            <span>Ephemerally scrubbed route logs &amp; zero cleartext storage</span>
                        </li>
                    </ul>
                </div>

                <div class="glass-card p-6 rounded-2xl font-mono text-xs text-slate-300 border border-slate-800 shadow-2xl reveal">
                    <div class="flex items-center justify-between border-b border-slate-800 pb-3 mb-4">
                        <span class="text-slate-400 flex items-center gap-2">
                            <i class="fa-solid fa-terminal text-cyan-400" aria-hidden="true"></i> Security Check - app/core/security.py
                        </span>
                        <div class="flex gap-1.5" aria-hidden="true">
                            <span class="w-2.5 h-2.5 rounded-full bg-red-500/80"></span>
                            <span class="w-2.5 h-2.5 rounded-full bg-yellow-500/80"></span>
                            <span class="w-2.5 h-2.5 rounded-full bg-emerald-500/80"></span>
                        </div>
                    </div>
                    <p class="text-cyan-400"># Initializing Security Header Middleware...</p>
                    <p class="mt-2 text-slate-300">headers["Content-Security-Policy"] = "default-src 'self'..."</p>
                    <p class="text-slate-300">headers["X-Frame-Options"] = "DENY"</p>
                    <p class="text-slate-300">headers["X-Content-Type-Options"] = "nosniff"</p>
                    <p class="text-pink-400 mt-2"># Verifying payload size guard limit...</p>
                    <p class="text-slate-300">if content_length &gt; MAX_REQUEST_BODY_SIZE: return 413</p>
                    <p class="mt-4 text-emerald-400 font-bold">&gt; Security Verification: 100% PASS [0 Vulnerabilities]</p>
                </div>
            </div>
        </section>

        <!-- Ecosystem Section -->
        <section id="ecosystem" class="max-w-7xl mx-auto px-6 py-28" aria-labelledby="ecosystem-heading">
            <div class="text-center max-w-3xl mx-auto mb-16 reveal">
                <h2 id="ecosystem-heading" class="font-headline text-3xl sm:text-5xl font-extrabold tracking-tight mb-4">Nexus Ecosystem</h2>
                <p class="text-slate-300 text-base">Cross-platform integration across mobile Flutter nodes and Python FastAPI backend services.</p>
            </div>

            <div class="grid md:grid-cols-3 gap-8">
                <div class="glass-card p-8 rounded-2xl text-center space-y-4 reveal">
                    <img src="/logo.png" alt="Nexus Mobile App Icon" class="w-16 h-16 mx-auto rounded-2xl shadow-xl shadow-cyan-500/20" width="64" height="64">
                    <h3 class="font-headline text-xl font-bold text-white">Mobile Client</h3>
                    <p class="text-sm text-slate-300 leading-relaxed">Built with Flutter, targeting Android &amp; iOS with smooth native performance, offline encryption, and real-time audio channels.</p>
                </div>

                <div class="glass-card p-8 rounded-2xl text-center space-y-4 reveal" style="transition-delay: 0.1s">
                    <div class="w-16 h-16 mx-auto rounded-2xl bg-cyan-500/15 flex items-center justify-center text-cyan-400">
                        <i class="fa-solid fa-server text-3xl" aria-hidden="true"></i>
                    </div>
                    <h3 class="font-headline text-xl font-bold text-white">Matchmaking Backend</h3>
                    <p class="text-sm text-slate-300 leading-relaxed">Asynchronous FastAPI engine executing matrix orbit calculations, rate limiting, and webhooks.</p>
                </div>

                <div class="glass-card p-8 rounded-2xl text-center space-y-4 reveal" style="transition-delay: 0.2s">
                    <div class="w-16 h-16 mx-auto rounded-2xl bg-pink-500/15 flex items-center justify-center text-pink-400">
                        <i class="fa-solid fa-database text-3xl" aria-hidden="true"></i>
                    </div>
                    <h3 class="font-headline text-xl font-bold text-white">Realtime &amp; Redis Cache</h3>
                    <p class="text-sm text-slate-300 leading-relaxed">Sub-millisecond state management and replay attack protection backed by high-speed Redis instances.</p>
                </div>
            </div>
        </section>

        <!-- Social Media & Community Section -->
        <section id="social" class="bg-slate-900/40 border-t border-slate-800/80 py-20 px-6" aria-labelledby="social-heading">
            <div class="max-w-7xl mx-auto text-center space-y-12">
                <div class="max-w-2xl mx-auto space-y-4 reveal">
                    <h2 id="social-heading" class="font-headline text-3xl sm:text-4xl font-bold text-white">Join the Community</h2>
                    <p class="text-slate-300 text-base">Connect with developers, contributors, and users across our official social channels.</p>
                </div>

                <!-- Social Media Icon Grid -->
                <div class="grid grid-cols-2 sm:grid-cols-3 md:grid-cols-6 gap-4 max-w-4xl mx-auto reveal">
                    <!-- GitHub -->
                    <a href="https://github.com/devakesu/Nexus" target="_blank" rel="noopener noreferrer" class="glass-card p-5 rounded-2xl flex flex-col items-center gap-3 group transition-all hover:-translate-y-1" aria-label="Visit Nexus GitHub Repository">
                        <div class="w-12 h-12 rounded-xl bg-slate-800/80 flex items-center justify-center text-slate-200 group-hover:text-white group-hover:bg-slate-700 transition-colors">
                            <i class="fa-brands fa-github text-2xl" aria-hidden="true"></i>
                        </div>
                        <span class="text-xs font-semibold text-slate-300 group-hover:text-white">GitHub</span>
                    </a>

                    <!-- Twitter / X -->
                    <a href="https://twitter.com" target="_blank" rel="noopener noreferrer" class="glass-card p-5 rounded-2xl flex flex-col items-center gap-3 group transition-all hover:-translate-y-1" aria-label="Follow Nexus on Twitter/X">
                        <div class="w-12 h-12 rounded-xl bg-slate-800/80 flex items-center justify-center text-slate-200 group-hover:text-cyan-400 group-hover:bg-cyan-950/50 transition-colors">
                            <i class="fa-brands fa-x-twitter text-2xl" aria-hidden="true"></i>
                        </div>
                        <span class="text-xs font-semibold text-slate-300 group-hover:text-cyan-400">Twitter / X</span>
                    </a>

                    <!-- Discord -->
                    <a href="https://discord.gg" target="_blank" rel="noopener noreferrer" class="glass-card p-5 rounded-2xl flex flex-col items-center gap-3 group transition-all hover:-translate-y-1" aria-label="Join Nexus Discord Server">
                        <div class="w-12 h-12 rounded-xl bg-slate-800/80 flex items-center justify-center text-slate-200 group-hover:text-indigo-400 group-hover:bg-indigo-950/50 transition-colors">
                            <i class="fa-brands fa-discord text-2xl" aria-hidden="true"></i>
                        </div>
                        <span class="text-xs font-semibold text-slate-300 group-hover:text-indigo-400">Discord</span>
                    </a>

                    <!-- Instagram -->
                    <a href="https://instagram.com" target="_blank" rel="noopener noreferrer" class="glass-card p-5 rounded-2xl flex flex-col items-center gap-3 group transition-all hover:-translate-y-1" aria-label="Follow Nexus on Instagram">
                        <div class="w-12 h-12 rounded-xl bg-slate-800/80 flex items-center justify-center text-slate-200 group-hover:text-pink-400 group-hover:bg-pink-950/50 transition-colors">
                            <i class="fa-brands fa-instagram text-2xl" aria-hidden="true"></i>
                        </div>
                        <span class="text-xs font-semibold text-slate-300 group-hover:text-pink-400">Instagram</span>
                    </a>

                    <!-- LinkedIn -->
                    <a href="https://linkedin.com" target="_blank" rel="noopener noreferrer" class="glass-card p-5 rounded-2xl flex flex-col items-center gap-3 group transition-all hover:-translate-y-1" aria-label="Connect with Nexus on LinkedIn">
                        <div class="w-12 h-12 rounded-xl bg-slate-800/80 flex items-center justify-center text-slate-200 group-hover:text-cyan-400 group-hover:bg-cyan-950/50 transition-colors">
                            <i class="fa-brands fa-linkedin text-2xl" aria-hidden="true"></i>
                        </div>
                        <span class="text-xs font-semibold text-slate-300 group-hover:text-cyan-400">LinkedIn</span>
                    </a>

                    <!-- YouTube -->
                    <a href="https://youtube.com" target="_blank" rel="noopener noreferrer" class="glass-card p-5 rounded-2xl flex flex-col items-center gap-3 group transition-all hover:-translate-y-1" aria-label="Subscribe to Nexus YouTube Channel">
                        <div class="w-12 h-12 rounded-xl bg-slate-800/80 flex items-center justify-center text-slate-200 group-hover:text-red-400 group-hover:bg-red-950/50 transition-colors">
                            <i class="fa-brands fa-youtube text-2xl" aria-hidden="true"></i>
                        </div>
                        <span class="text-xs font-semibold text-slate-300 group-hover:text-red-400">YouTube</span>
                    </a>
                </div>
            </div>
        </section>

    </main>

    <!-- Footer -->
    <footer class="border-t border-slate-800/80 py-12 text-slate-400 text-xs" role="contentinfo">
        <div class="max-w-7xl mx-auto px-6 flex flex-col sm:flex-row items-center justify-between gap-6">
            <div class="flex items-center gap-3">
                <img src="/logo.png" alt="Nexus Mark" class="w-7 h-7 rounded-lg" width="28" height="28">
                <p>&copy; 2026 Nexus Infrastructure Engine Inc. All security parameters active.</p>
            </div>

            <!-- Footer Social Media Quick Icons -->
            <div class="flex gap-5 text-lg">
                <a href="https://github.com/devakesu/Nexus" target="_blank" rel="noopener noreferrer" class="hover:text-white transition-colors" aria-label="GitHub Repository">
                    <i class="fa-brands fa-github" aria-hidden="true"></i>
                </a>
                <a href="https://twitter.com" target="_blank" rel="noopener noreferrer" class="hover:text-cyan-400 transition-colors" aria-label="Twitter Page">
                    <i class="fa-brands fa-x-twitter" aria-hidden="true"></i>
                </a>
                <a href="https://discord.gg" target="_blank" rel="noopener noreferrer" class="hover:text-indigo-400 transition-colors" aria-label="Discord Server">
                    <i class="fa-brands fa-discord" aria-hidden="true"></i>
                </a>
                <a href="https://instagram.com" target="_blank" rel="noopener noreferrer" class="hover:text-pink-400 transition-colors" aria-label="Instagram Profile">
                    <i class="fa-brands fa-instagram" aria-hidden="true"></i>
                </a>
            </div>
        </div>
    </footer>

    <!-- Scroll Reveal JavaScript -->
    <script>
        document.addEventListener('DOMContentLoaded', () => {
            const reveals = document.querySelectorAll('.reveal');
            const revealOnScroll = () => {
                const windowHeight = window.innerHeight;
                reveals.forEach(el => {
                    const elementTop = el.getBoundingClientRect().top;
                    if (elementTop < windowHeight - 40) {
                        el.classList.add('active');
                    }
                });
            };
            window.addEventListener('scroll', revealOnScroll, { passive: true });
            revealOnScroll();
        });
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
