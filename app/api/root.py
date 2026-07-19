from fastapi import APIRouter
from fastapi.responses import HTMLResponse

router = APIRouter()


# Temporary AI Template for Development Purpose only
@router.get("/", response_class=HTMLResponse)
async def render_landing_page():
    return """
    <!DOCTYPE html>
    <html lang="en" class="scroll-smooth">
    <head>
        <meta charset="UTF-8">
        <meta name="viewport" content="width=device-width, initial-scale=1.0">
        <title>Nexus — Sync Your Circle</title>
        <!-- Tailwind CSS CDN -->
        <script src="https://cdn.jsdelivr.net/npm/@tailwindcss/browser@4"></script>
        <!-- FontAwesome for Premium Icons -->
        <link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.4.0/css/all.min.css">
        <!-- Custom Micro-interactions & Core Style overrides -->
        <style>
            @keyframes float {
                0%, 100% { transform: translateY(0px) rotate(0deg); }
                50% { transform: translateY(-10px) rotate(2deg); }
            }
            .animate-float { animation: float 6s ease-in-out infinite; }
            .reveal { opacity: 0; transform: translateY(30px); transition: all 0.8s ease-out; }
            .reveal.active { opacity: 1; transform: translateY(0); }
            .glass { background: rgba(15, 23, 42, 0.65); backdrop-filter: blur(12px); border: 1px solid rgba(255, 255, 255, 0.08); }
        </style>
    </head>
    <body class="bg-slate-950 text-slate-100 font-sans antialiased overflow-x-hidden selection:bg-purple-500 selection:text-white">

        <!-- Background Ambient Glows -->
        <div class="absolute top-0 left-1/4 w-96 h-96 bg-purple-600/20 rounded-full filter blur-[120px] pointer-events-none intense"></div>
        <div class="absolute top-[800px] right-1/4 w-96 h-96 bg-cyan-600/15 rounded-full filter blur-[150px] pointer-events-none"></div>

        <!-- Sticky Header Navbar -->
        <header class="fixed top-0 left-0 right-0 z-50 glass border-b border-slate-900/50 navbar-glow">
            <div class="max-w-7xl mx-auto px-6 h-20 flex items-center justify-between">
                <div class="flex items-center gap-3">
                    <div class="w-10 h-10 rounded-xl bg-gradient-to-tr from-purple-600 to-cyan-400 flex items-center justify-center shadow-lg shadow-purple-500/20">
                        <i class="fa-solid fa-circle-nodes text-lg text-white"></i>
                    </div>
                    <span class="text-xl font-bold tracking-wider bg-clip-text text-transparent bg-gradient-to-r from-white to-slate-400">NEXUS</span>
                </div>
                <nav class="hidden md:flex items-center gap-8 text-sm font-medium text-slate-400">
                    <a href="#features" class="hover:text-purple-400 transition-colors">Features</a>
                    <a href="#security" class="hover:text-purple-400 transition-colors">Security</a>
                    <a href="#ecosystem" class="hover:text-purple-400 transition-colors">Ecosystem</a>
                </nav>
                <div class="flex items-center gap-4">
                    <a href="#download" class="relative group overflow-hidden px-5 py-2.5 rounded-xl bg-slate-900 font-medium text-sm transition-all border border-slate-800 hover:border-purple-500/50">
                        <span class="relative z-10 bg-clip-text text-transparent bg-gradient-to-r from-purple-400 to-cyan-400 group-hover:from-white group-hover:to-white">Get App</span>
                    </a>
                </div>
            </div>
        </header>

        <!-- Hero Blueprint Section -->
        <section class="relative min-h-screen pt-40 pb-20 flex items-center px-6">
            <div class="max-w-7xl mx-auto grid lg:grid-cols-12 gap-12 items-center w-full">
                <div class="lg:col-span-7 space-y-8 text-center lg:text-left">
                    <div class="inline-flex items-center gap-2 px-3 py-1.5 rounded-full bg-purple-500/10 border border-purple-500/20 text-xs font-semibold tracking-wide text-purple-400 uppercase animate-pulse">
                        <span class="w-2 h-2 rounded-full bg-purple-400"></span> Nexus Ecosystem Live
                    </div>
                    <h1 class="text-4xl sm:text-6xl font-black tracking-tight leading-[1.1] text-white">
                        Connect closer.<br>
                        Live within your <span class="bg-clip-text text-transparent bg-gradient-to-r from-purple-400 via-indigo-400 to-cyan-400">Orbit</span>.
                    </h1>
                    <p class="text-lg text-slate-400 max-w-2xl mx-auto lg:mx-0 font-normal leading-relaxed">
                        An integrated decentralized matrix built for absolute security, high-fidelity real-time music pooling, proximity discovery, and failsafe human protection networks.
                    </p>
                    <div class="flex flex-col sm:flex-row items-center justify-center lg:justify-start gap-4 pt-4">
                        <button class="w-full sm:w-auto px-8 py-4 bg-gradient-to-r from-purple-600 to-indigo-600 hover:from-purple-500 hover:to-indigo-500 font-semibold text-sm rounded-xl shadow-xl shadow-purple-600/20 transform hover:-translate-y-0.5 transition-all flex items-center justify-center gap-3">
                            <i class="fa-brands fa-google-play text-base"></i> Deploy Mobile Build
                        </button>
                        <button class="w-full sm:w-auto px-8 py-4 glass hover:bg-slate-900 font-semibold text-sm rounded-xl transition-all flex items-center justify-center gap-3 text-slate-300">
                            <i class="fa-solid fa-code text-base"></i> View Platform Config
                        </button>
                    </div>
                </div>

                <!-- Interactive App Frame Animation mockup -->
                <div class="lg:col-span-5 flex justify-center relative animate-float">
                    <div class="w-72 h-[580px] rounded-[40px] glass p-3 relative shadow-2xl shadow-indigo-500/10 border border-slate-800">
                        <div class="w-full h-full rounded-[32px] bg-slate-950 overflow-hidden relative border border-slate-900 flex flex-col justify-between p-6">
                            <!-- Notch -->
                            <div class="absolute top-0 left-1/2 transform -translate-x-1/2 w-32 h-5 bg-slate-950 rounded-b-xl z-20"></div>

                            <!-- Mock Screen Inner Content -->
                            <div class="flex justify-between items-center mt-3">
                                <i class="fa-solid fa-bars text-slate-500"></i>
                                <span class="text-xs tracking-widest text-slate-600 font-bold">NEXUS M-01</span>
                                <div class="w-2 h-2 rounded-full bg-green-400 animate-ping"></div>
                            </div>

                            <!-- Visual UI Cards Mockup -->
                            <div class="space-y-4 my-auto">
                                <div class="p-3 bg-purple-950/30 border border-purple-500/20 rounded-xl">
                                    <div class="flex justify-between items-center text-xs mb-2">
                                        <span class="text-purple-400 font-semibold"><i class="fa-solid fa-shield-halved mr-1"></i> Failsafe</span>
                                        <span class="text-slate-500">Active</span>
                                    </div>
                                    <div class="text-[11px] text-slate-400">Audio Node Recording background engine listening loop initialized.</div>
                                </div>

                                <div class="p-3 bg-slate-900/80 border border-slate-800 rounded-xl flex items-center gap-3">
                                    <div class="w-8 h-8 rounded-lg bg-green-500/20 flex items-center justify-center text-green-400"><i class="fa-brands fa-spotify"></i></div>
                                    <div class="flex-1 min-w-0">
                                        <p class="text-[11px] font-bold text-slate-200 truncate">Orbit Synced Audio</p>
                                        <p class="text-[9px] text-slate-500 truncate">Chilled Lo-Fi Loop</p>
                                    </div>
                                    <div class="flex gap-1"><span class="w-1 h-3 bg-green-400 block animate-bounce"></span><span class="w-1 h-4 bg-green-400 block animate-bounce" style="animation-delay:0.1s"></span></div>
                                </div>
                            </div>

                            <div class="w-full py-3 bg-gradient-to-r from-purple-600 to-indigo-600 rounded-xl text-center text-xs font-bold text-white shadow-lg">
                                Discovered 4 Nodes Nearby
                            </div>
                        </div>
                    </div>
                </div>
            </div>
        </section>

        <!-- Main Core Features Section -->
        <section id="features" class="max-w-7xl mx-auto px-6 py-32 border-t border-slate-900">
            <div class="text-center max-w-3xl mx-auto mb-20 reveal">
                <h2 class="text-3xl sm:text-5xl font-extrabold tracking-tight mb-4">Architecture Capabilities</h2>
                <p class="text-slate-400">Engineered modular configurations serving asynchronous user synchronization across decentralized nodes.</p>
            </div>

            <div class="grid sm:grid-cols-2 lg:grid-cols-4 gap-6">
                <!-- Feature 1: Safety Portal -->
                <div class="glass p-8 rounded-2xl border border-slate-800/80 hover:border-purple-500/40 transition-all group reveal">
                    <div class="w-12 h-12 rounded-xl bg-purple-500/10 flex items-center justify-center text-purple-400 mb-6 group-hover:scale-110 transition-transform">
                        <i class="fa-solid fa-shield-heart text-xl"></i>
                    </div>
                    <h3 class="text-lg font-bold mb-2 group-hover:text-purple-400 transition-colors">Safety Portal Shield</h3>
                    <p class="text-sm text-slate-400 leading-relaxed">Failsafe foreground monitoring with instant background background audio processing pipelines (`SafetyRecordingService`).</p>
                </div>

                <!-- Feature 2: Discovery Orbits -->
                <div class="glass p-8 rounded-2xl border border-slate-800/80 hover:border-indigo-500/40 transition-all group reveal" style="animation-delay: 0.1s">
                    <div class="w-12 h-12 rounded-xl bg-indigo-500/10 flex items-center justify-center text-indigo-400 mb-6 group-hover:scale-110 transition-transform">
                        <i class="fa-solid fa-satellite-dish text-xl"></i>
                    </div>
                    <h3 class="text-lg font-bold mb-2 group-hover:text-indigo-400 transition-colors">Hyper-Proximity Orbit</h3>
                    <p class="text-sm text-slate-400 leading-relaxed">Discover nearby peer vectors based on geometric matching weights, calculated directly inside the matching module engine (`orbit.py`).</p>
                </div>

                <!-- Feature 3: Spotify Pool Sync -->
                <div class="glass p-8 rounded-2xl border border-slate-800/80 hover:border-green-500/40 transition-all group reveal" style="animation-delay: 0.2s">
                    <div class="w-12 h-12 rounded-xl bg-green-500/10 flex items-center justify-center text-green-400 mb-6 group-hover:scale-110 transition-transform">
                        <i class="fa-brands fa-spotify text-xl"></i>
                    </div>
                    <h3 class="text-lg font-bold mb-2 group-hover:text-green-400 transition-colors">Music Vibe Pooling</h3>
                    <p class="text-sm text-slate-400 leading-relaxed">Asynchronous playback synchronization routines matching user vectors with streaming contexts on active node frames (`spotify_sync.py`).</p>
                </div>

                <!-- Feature 4: E2E Encrypted Chat Keys -->
                <div class="glass p-8 rounded-2xl border border-slate-800/80 hover:border-cyan-500/40 transition-all group reveal" style="animation-delay: 0.3s">
                    <div class="w-12 h-12 rounded-xl bg-cyan-500/10 flex items-center justify-center text-cyan-400 mb-6 group-hover:scale-110 transition-transform">
                        <i class="fa-solid fa-key text-xl"></i>
                    </div>
                    <h3 class="text-lg font-bold mb-2 group-hover:text-cyan-400 transition-colors">Crypt-Key Messaging</h3>
                    <p class="text-sm text-slate-400 leading-relaxed">Direct message handshakes verified through asymmetrical encryption keys for uncompromised privacy relays (`chat_keys.py`).</p>
                </div>
            </div>
        </section>

        <!-- Technical Security Matrix Section -->
        <section id="security" class="bg-slate-900/40 border-y border-slate-900/60 py-24 px-6 relative">
            <div class="max-w-7xl mx-auto grid lg:grid-cols-2 gap-12 items-center">
                <div class="space-y-6 reveal">
                    <h2 class="text-3xl sm:text-4xl font-extrabold tracking-tight">Zero-Knowledge Key Architecture</h2>
                    <p class="text-slate-400 leading-relaxed">
                        Nexus executes operations under rigorous data protection layers. Direct messaging frames and local authentication handshakes completely bypass clear-text storage structures.
                    </p>
                    <ul class="space-y-3 text-sm text-slate-300">
                        <li class="flex items-center gap-3"><i class="fa-solid fa-circle-check text-cyan-400"></i> Local cryptographic seed derivation keys</li>
                        <li class="flex items-center gap-3"><i class="fa-solid fa-circle-check text-cyan-400"></i> Automated scrubbing of ephemeral route traces</li>
                        <li class="flex items-center gap-3"><i class="fa-solid fa-circle-check text-cyan-400"></i> Transparent user verification hashes</li>
                    </ul>
                </div>
                <div class="glass p-6 rounded-2xl font-mono text-xs text-slate-400 border border-slate-800/80 shadow-2xl relative reveal">
                    <div class="flex items-center justify-between border-b border-slate-800 pb-3 mb-4">
                        <span class="text-slate-500">Terminal Node Check — crypt_keys.py</span>
                        <div class="flex gap-1.5"><span class="w-2.5 h-2.5 rounded-full bg-red-500/40"></span><span class="w-2.5 h-2.5 rounded-full bg-yellow-500/40"></span><span class="w-2.5 h-2.5 rounded-full bg-green-500/40"></span></div>
                    </div>
                    <p class="text-purple-400"># Initializing asynchronous signature verification...</p>
                    <p class="mt-2 text-slate-300">import crypto_core from app.core</p>
                    <p class="text-slate-300">def verify_matrix_handshake(user_id, key_signature):</p>
                    <p class="text-slate-500 class pl-4">\"\"\"Zero-knowledge trace verification check\"\"\"</p>
                    <p class="text-cyan-400 pl-4">session_token = crypto_core.generate_ephemeral_hash()</p>
                    <p class="text-slate-300 pl-4">if not crypto_core.validate(user_id, key_signature):</p>
                    <p class="text-red-400 pl-8">raise MatrixTraceException("Invalid Validation Signature Vector")</p>
                    <p class="text-green-400 pl-4">return session_token.seal_envelope()</p>
                    <p class="mt-4 text-slate-500">&gt; Node verification successfully processed. Status: 200 OK</p>
                </div>
            </div>
        </section>

        <!-- Clean Footer -->
        <footer class="border-t border-slate-900 py-12 text-center text-slate-500 text-xs">
            <div class="max-w-7xl mx-auto px-6 flex flex-col sm:flex-row items-center justify-between gap-6">
                <p>&copy; 2026 Nexus Infrastructure Engine Inc. All code blocks running on safe parameters.</p>
                <div class="flex gap-6 text-sm">
                    <a href="#" class="hover:text-slate-300"><i class="fa-brands fa-github"></i></a>
                    <a href="#" class="hover:text-slate-300"><i class="fa-brands fa-discord"></i></a>
                </div>
            </div>
            <!-- Playful meme easter egg constraint mapping -->
            <p class="text-slate-800 text-[10px] mt-4 tracking-widest uppercase">Zero padding was harmed during the compilation of this interface.</p>
        </footer>

        <!-- Scroll Animations Script Trigger -->
        <script>
            const reveals = document.querySelectorAll('.reveal');
            const revealOnScroll = () => {
                reveals.forEach(el => {
                    const windowHeight = window.innerHeight;
                    const elementTop = el.getBoundingClientRect().top;
                    if (elementTop < windowHeight - 50) {
                        el.classList.add('active');
                    }
                });
            };
            window.addEventListener('scroll', revealOnScroll);
            window.addEventListener('load', revealOnScroll);
        </script>
    </body>
    </html>
    """  # noqa: E501
