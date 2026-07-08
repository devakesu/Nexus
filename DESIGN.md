---
name: Nexus
description: A cosmic-themed social discovery app where each relationship mode carries its own signal color.
colors:
  primary-teal: "#0891B2"
  pulsar-pink: "#FF7597"
  mode-dating: "#FF4F81"
  mode-friends: "#A45E00"
  mode-professional: "#007E6D"
  mode-settings: "#4EA8DE"
  ink: "#0F172A"
  ink-muted: "#64748B"
  ink-faint: "#94A3B8"
  border-neutral: "#E2E8F0"
  surface: "#FFFFFF"
  bg: "#F4F6FA"
  safety-blue: "#0284C7"
  safety-teal: "#0D9488"
  success: "#10B981"
  error: "#EF4444"
  warning: "#F59E0B"
  info: "#60A5FA"
typography:
  display:
    fontFamily: "Orbitron, sans-serif"
    fontSize: "28px"
    fontWeight: 900
    lineHeight: 1.1
    letterSpacing: "0.02em"
  headline:
    fontFamily: "Manrope, sans-serif"
    fontSize: "20px"
    fontWeight: 800
    lineHeight: 1.2
    letterSpacing: "normal"
  title:
    fontFamily: "Manrope, sans-serif"
    fontSize: "16px"
    fontWeight: 700
    lineHeight: 1.25
    letterSpacing: "normal"
  body:
    fontFamily: "Inter, sans-serif"
    fontSize: "14px"
    fontWeight: 400
    lineHeight: 1.4
    letterSpacing: "normal"
  label:
    fontFamily: "Inter, sans-serif"
    fontSize: "12px"
    fontWeight: 600
    lineHeight: 1.2
    letterSpacing: "0.5px"
  mono:
    fontFamily: "JetBrains Mono, monospace"
    fontSize: "16px"
    fontWeight: 500
    lineHeight: 1.2
    letterSpacing: "4px"
rounded:
  xs: "8px"
  sm: "12px"
  md: "16px"
  lg: "20px"
  xl: "24px"
  sheet: "28px"
  pill: "36px"
spacing:
  xs: "8px"
  sm: "12px"
  md: "16px"
  lg: "20px"
  xl: "24px"
components:
  button-primary:
    backgroundColor: "{colors.pulsar-pink}"
    textColor: "#FFFFFF"
    rounded: "{rounded.md}"
    padding: "16px 24px"
    height: "52px"
  button-primary-disabled:
    backgroundColor: "rgba(255,255,255,0.08)"
    textColor: "rgba(255,255,255,0.3)"
    rounded: "{rounded.md}"
    height: "52px"
  input-field:
    backgroundColor: "{colors.surface}"
    textColor: "{colors.ink}"
    rounded: "{rounded.xs}"
    padding: "12px 16px"
  chip-selected:
    backgroundColor: "rgba(8,145,178,0.15)"
    textColor: "{colors.primary-teal}"
    rounded: "{rounded.pill}"
    padding: "8px 14px"
  chip-unselected:
    backgroundColor: "rgba(255,255,255,0.05)"
    textColor: "{colors.ink-muted}"
    rounded: "{rounded.pill}"
    padding: "8px 14px"
  nav-item-selected:
    backgroundColor: "rgba(255,79,129,0.15)"
    textColor: "{colors.mode-dating}"
    rounded: "{rounded.sm}"
    padding: "8px 12px"
---

# Design System: Nexus

## 1. Overview

**Creative North Star: "Constellation Social"**

Nexus already speaks this language in its own code before any design system named it: an "Orbit" discovery screen with a hand-painted starfield and HUD-style coordinate grid, a "Constellation" loader with concentric rotating dot-rings and a radar sweep, a brand pink literally named `pulsarPink` in the source. Constellation Social treats every person on the app as a point of light, and the product's job is to help two isolated points resolve into a recognizable pattern — a match, a friendship, a connection worth following. Discovery is navigation: you scan the sky, not swipe a deck.

This is a **product register** surface: the design serves the workflows (discover, like, chat, stay safe), it doesn't sell them. The energy is playful and energetic, closer to BeReal's in-the-moment authenticity than to a curated dating-app gloss — Nexus explicitly rejects the generic Tinder stacked swipe-card cliché, even though liking and passing exist as interactions. Safety is a first-class citizen of this system, not a settings-page afterthought: the Safety Center, meetup-safety guidance, and crisis helplines borrow the same calm blue-teal signal color and soft elevation as the rest of the app, so they read as considered product, not a compliance bolt-on.

**Key Characteristics:**
- A cosmic/signal vocabulary (orbit, constellation, pulsar, pulse) that's already load-bearing in the codebase, not decorative
- One deliberate rule broken into four colors: every relationship mode (Dating, Friends, Professional, Profile) carries its own accent that follows the user across nav, chat, and filters
- Ambient soft depth throughout — nothing is stark-flat, nothing is heavy Material elevation
- Tactile, glowing interaction states: focus and press are announced with color and glow, not just a ripple
- Safety surfaces get the same craft budget as growth surfaces

## 2. Colors

The palette pairs a calm base (slate ink on soft cool-white) with saturated, single-purpose signal colors — each one means something specific and doesn't leak into other contexts.

### Primary
- **Pulsar Pink** (`#FF7597`): The app's signature brand accent — primary CTAs, focused input glows, login/onboarding/profile flourishes. This is the color Nexus reaches for when it wants to feel like itself, independent of which discovery mode the user is in.
- **Signal Teal** (`#0891B2`): The seed/system color (Flutter's `ColorScheme.fromSeed`) and the Profile tab's mode color. Used for the neutral, "always-on" accent — sliders, the profile tab, and anywhere the UI needs an accent that isn't mode-specific or brand-specific.

### Secondary — Mode Colors (Named Rule)
**The Mode Signal Rule.** Every relationship mode owns one color, everywhere. That color is not decorative — it is the mode's identity, and it must be the same accent in the bottom nav, the chat header gradient, the home header, and the filter panel for that mode. This was previously violated (chat-tab gradients and a couple of other surfaces used older, brighter hex values than the nav) and has been reconciled: every surface now reads from the same four hex values below.

- **Dating Signal** (`#FF4F81`): Dating tab, its chat threads, its filter accents.
- **Friends Signal** (`#A45E00`): Friends tab, its chat threads, its filter accents. Deepened from an earlier, brighter `#FF9F1C` — that value read at only 2.05:1 against white as flat text/icon color and 2.05:1 for white text over it as a fill, both well under the 4.5:1 floor; `#A45E00` clears ~4.5:1 in both directions while staying recognizably orange.
- **Professional Signal** (`#007E6D`): Professional tab, its chat threads, its filter accents. Deepened from an earlier, brighter `#00F5D4` for the same reason — that mint measured just 1.40:1 in both directions; `#007E6D` clears ~5:1.
- **Settings Signal** (`#4EA8DE`): Settings tab accent, used more quietly than the three discovery modes.

### Tertiary — Safety Duo
- **Safety Blue** (`#0284C7`) and **Safety Teal** (`#0D9488`): A dedicated gradient pair reserved for safety surfaces — the safety-score ring, Safety Center, crisis helplines, meetup-safety guidance. Calm and clinical-adjacent without being cold; never reused for growth/marketing moments, so it stays trustworthy by not being everywhere.

### Neutral
- **Ink** (`#0F172A`): Primary text, headings, display copy. The single darkest neutral in the system.
- **Ink Muted** (`#64748B`): Secondary text, subtitles, unselected nav labels in light mode.
- **Ink Faint** (`#94A3B8`): Placeholder text, disabled states, unselected nav labels in dark mode.
- **Border Neutral** (`#E2E8F0`): Card borders, dividers, the safety ring's track color.
- **Surface** (`#FFFFFF`): Card and sheet backgrounds.
- **Canvas** (`#F4F6FA`): The scaffold background — a cool off-white, never a warm cream/sand tone.

### Status
- **Success** (`#10B981`), **Error** (`#EF4444`), **Warning** (`#F59E0B`), **Info** (`#60A5FA`): Reserved exclusively for toast/status feedback (`nexus_toast.dart`) and validation states. Never used as decorative accents.

### Named Rules
**The One Signal Rule.** A screen shows exactly one accent identity at a time: its mode color (if it's a Dating/Friends/Professional/Settings surface), Pulsar Pink (if it's brand/onboarding), or the Safety Duo (if it's a safety surface). Never mix two of these families on one screen.

## 3. Typography

**Display Font:** Orbitron (with sans-serif fallback) — reserved for one futuristic moment, not a workhorse.
**Headline Font:** Manrope (with sans-serif fallback)
**Body Font:** Inter (with sans-serif fallback)
**Mono Font:** JetBrains Mono (with monospace fallback)

**Character:** Manrope's geometric weight carries headlines with confidence; Inter stays quiet and legible underneath it for body copy — a standard, restrained display/body contrast pairing. JetBrains Mono is the deliberate outlier, reserved for OTP entry and the login/splash "terminal" sequence, where a monospace, code-like feel is the point. Plus Jakarta Sans appears as a secondary voice specifically inside profile-section headings (bio, social coordinates, universe sections) — treat it as a profile-specific accent typeface, not a system-wide role.

### Hierarchy
- **Display** (weight 900, 28px, line-height 1.1, Orbitron): One-off futuristic headers (e.g. the home common header). Use sparingly — this is the loudest typographic move in the system.
- **Headline** (weight 800, 20px, line-height 1.2, Manrope): Section titles, sheet titles, primary screen headings.
- **Title** (weight 700, 16px, line-height 1.25, Manrope): Card titles, list-item primary text.
- **Body** (weight 400, 14px, line-height 1.4, Inter): Standard copy, descriptions, chat bubbles. Cap prose blocks at 65-75ch equivalent on any screen wide enough to need it.
- **Label** (weight 600, 12px, letter-spacing 0.5px, Inter): Nav labels, chip labels, micro-copy. Bottom-nav labels step up to letter-spacing 1.2px specifically to read as tracked micro-caps.
- **Mono** (weight 500, 16px, letter-spacing 4px, JetBrains Mono): OTP digits and terminal-style login/splash sequences only.

### Named Rules
**The One Display Moment Rule.** Orbitron appears at most once per screen. It's a signature flourish, not a heading family — overuse turns "futuristic" into "busy."

## 4. Elevation

Nexus reads as ambient soft depth throughout, not flat-by-default and not heavy Material elevation. Nearly every card and sheet carries a barely-there shadow (`black @ 2-8% alpha`) as a constant, resting cue that content is lifted off the canvas — Material's numeric `elevation` prop is actively avoided (set to `0` far more often than to any positive value) in favor of hand-tuned `BoxShadow`. On top of that ambient layer, interactive and focused elements add a second, color-matched glow shadow (Pulsar Pink, mode color, or brand accent at 12-30% alpha, larger blur) that only appears in response to focus/press/active state.

### Shadow Vocabulary
- **Ambient Card** (`box-shadow: 0 2px 8px rgba(0,0,0,0.03)`): Resting elevation for every white card and container. Always present, never state-dependent.
- **Nav Float** (`box-shadow: 0 4px 16px rgba(0,0,0,0.06)` light / `rgba(0,0,0,0.2)` dark): The floating pill bottom nav's constant lift off the canvas.
- **Signal Glow** (`box-shadow: 0 4px 12px [mode or brand color]@20-30%`): Appears on focused inputs and active primary buttons, colored to match whichever signal family (Pulsar Pink, mode color, safety duo) owns that screen.
- **Toast Glow** (`box-shadow: 0 6px 24px [status color]@12%, 0 2px 8px rgba(0,0,0,0.55)`): Stacked ambient + color glow specific to toast notifications.

### Named Rules
**The Ambient-Plus-One Rule.** Every surface gets its ambient card shadow at rest. At most one additional glow layer is added for state (focus/active/toast) — never stack two colored glows on the same element.

## 5. Components

Buttons, inputs, and the bottom nav are hand-built (`Container` + `InkWell` + `BoxDecoration`) rather than default Material widgets — this is a deliberate, tactile-and-glowing register: interactive states announce themselves with color, gradient, and glow rather than plain Material ripple.

### Buttons
- **Shape:** Rounded rectangle, 16px radius (`{rounded.md}`), 52px height.
- **Primary:** Filled with a Pulsar Pink → deep-rose gradient (`#FF7597 → #E04B76`) when active; disabled state drops to flat `rgba(255,255,255,0.08)` fill with 30%-alpha white label. Padding roughly 16px vertical, 24px horizontal.
- **Hover / Focus:** Active state adds a Pulsar Pink glow shadow (`0 4px 12px rgba(255,117,151,0.3)`). No Material ripple; the glow is the feedback.
- **Secondary / Ghost:** Reserved for one-off integrations (e.g. Spotify connect uses its own brand green `#1DB954` at 12px radius) — treat third-party brand buttons as an explicit exception, not a pattern to replicate elsewhere.

### Chips
- **Style:** Pill-shaped (`{rounded.pill}`), selected state fills with the screen's owning signal color at 15% alpha and sets the checkmark/text to that same color; unselected state is a near-transparent `rgba(255,255,255,0.05)` fill with muted-ink text.
- **State:** Selected/unselected only — no separate hover state on touch devices.

### Cards / Containers
- **Corner Style:** 16-24px radius depending on prominence (16px standard card, 20-24px for larger/featured containers).
- **Background:** White (light mode) or dark navy surface (dark mode).
- **Shadow Strategy:** Ambient Card shadow at rest (see Elevation).
- **Border:** 1px `Border Neutral` (`#E2E8F0`) hairline on cards that need definition against a similarly-light background.
- **Internal Padding:** 16-20px standard.

### Inputs / Fields
- **Style:** Two registers coexist. Profile/onboarding fields use the "glass" treatment: an outer gradient-bordered container (cyan-to-pink when focused, translucent otherwise) wrapping an inner 15px-radius field with a ~1.2px margin that creates the visible border-glow ring. Settings/login fields use a plainer `OutlineInputBorder` at 14px radius.
- **Focus:** Border color shifts to Pulsar Pink (width 1.5px) plus a matching glow shadow; the glass variant animates its gradient border in on focus.
- **Error / Disabled:** Error state uses the Error red (`#EF4444`); disabled fields drop to flat, low-alpha fills.

### Navigation
- **Style:** A fully custom floating pill, not Flutter's default `BottomNavigationBar` — 72px tall, 36px corner radius, 24px horizontal / 20px bottom margin off the screen edge, with a constant Nav Float shadow. Each tab's icon+label animates (250ms) into a rounded-rect (16px radius) fill at 15% alpha of that tab's Mode Signal color when selected; labels are 9px, letter-spacing 1.2px, weight 800 selected / 400 unselected. The center Profile tab breaks the rounded-rect pattern deliberately with a circular ring treatment, marking it as the "you" anchor point among the mode tabs.

### Signature Components
- **Safety Score Ring** (`safety_score_ring_painter.dart`): A circular progress gauge — `Border Neutral` track, Safety Duo sweep-gradient fill. Reused for both the safety-score gauge and check-in countdown timers, so the Safety Duo becomes visually synonymous with "you are being looked after."
- **Orbit Backdrop** (`orbit_painters.dart` + `constellation_loader.dart`): The discovery screen's signature visual — a deterministic twinkling starfield with a faint HUD coordinate grid tinted to the active mode color at very low alpha (3-8%), plus a multi-ring rotating "Aligning Constellations" loading sequence. This is the clearest expression of the Constellation Social north star and should not be diluted by reusing the same painter treatment on non-discovery screens.

## 6. Do's and Don'ts

### Do:
- **Do** give every relationship mode (Dating, Friends, Professional) its own consistent signal color across nav, chat, and filters — the Mode Signal Rule.
- **Do** keep the Safety Duo (`#0284C7` / `#0D9488`) exclusive to Safety Center, meetup-safety, and crisis-helpline surfaces so it stays recognizable as "you're safe here."
- **Do** treat glow shadows as a response to focus/press/active state, never a resting default (the Ambient-Plus-One Rule).
- **Do** use JetBrains Mono only for OTP entry and the login/splash terminal sequence — it's a deliberate outlier, not a body font.
- **Do** keep the canvas a cool off-white (`#F4F6FA`) — never drift toward a warm cream/sand background.

### Don't:
- **Don't** build a stacked swipe-deck card UI for discovery, even where like/pass actions exist — Nexus's own anti-reference is the generic Tinder card cliché, and the Orbit screen's radar/starfield metaphor is the intended alternative.
- **Don't** let chat-tab gradients, the home header, or any other surface diverge from the nav's Mode Signal hex values — this drifted before (older, brighter tones per mode) and was reconciled; don't reintroduce a second set of "close enough" mode colors.
- **Don't** reach for Material's default `elevation:` prop for depth; use the Ambient Card / Signal Glow shadow vocabulary instead.
- **Don't** mix two colored glow shadows on one element, or mix two signal families (e.g. a mode color and Pulsar Pink) on one screen.
- **Don't** default to the default Material `ElevatedButton`/`BottomNavigationBar` look — the hand-built, tactile-and-glowing components are the system, not a placeholder for "real" Material components.
- **Don't** skip the reduced-motion alternative on the Orbit/Constellation animations (twinkle, radar sweep, ring rotation) — these are the system's most elaborate motion and the most likely to be missed when adding `prefers-reduced-motion` support.
