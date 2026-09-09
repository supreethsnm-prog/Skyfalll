# WeatherGPT Frontend — Literal Visual Specification

**Status:** authoritative visual spec. Every frontend implementation task
builds from *this document*, not from imagination or general knowledge of
"what ChatGPT looks like."

**Source of truth:** the 16 reference screenshots in
`backend/FrontendReference/` (committed alongside this spec). Every value
below was either **sampled directly from those pixels** (colours) or
**measured from them** (geometry) — not estimated by eye. Where a value is
inferred rather than measured, it says so.

**Why this document exists:** the frontend is built by dispatched agents
that work from a text brief, not by looking at the screenshots. A precise
written spec is what keeps every task building the *same* target. The goal
is literal fidelity to the references, adapted only where WeatherGPT's own
content differs (weather data, WeatherGPT branding).

---

## 1. Reference inventory

| File | Source app | What it defines |
|---|---|---|
| `Home1.jpeg`, `Home2.jpeg` | Google Weather | Home screen: sky background, hero temperature, glass panels, hourly graph, detail widgets |
| `HomeShare.jpeg` | Google Weather | Home share: generated weather **image card** + OS share sheet |
| `Details4.jpeg` | Google Weather | Units settings (temperature / wind / pressure) |
| `NewChat.jpeg`, `NewChat2.jpeg` | ChatGPT | Empty chat state, composer (idle + typed) |
| `Convo1.jpeg`, `Convo2.jpeg` | ChatGPT | Conversation rendering: user bubble, assistant prose, code block, message action row |
| `TopLeftLines.jpeg` | ChatGPT | Sidebar / drawer |
| `TopRightDots.jpeg` | ChatGPT | Overflow dropdown menu |
| `Attach.jpeg` | ChatGPT | `+` attachment menu |
| `Voice.jpeg` | ChatGPT | Voice-recording composer state |
| `Details1-3.jpeg` | ChatGPT | Account / settings screens |

All ChatGPT references were captured at **540×1170 px**. Logical dp values
below assume that maps to a ~360dp-wide logical viewport
(`dp = px × 0.667`).

---

## 2. Colour tokens (sampled from the references)

### 2.1 Chat surface (dark) — the app's primary chrome

| Token | Hex | Where sampled |
|---|---|---|
| `bgBase` | `#000000` | Page + sidebar background (true black, `NewChat`, `TopLeftLines`) |
| `surfaceRaised` | `#212121` | Round icon buttons, composer pill, dropdown menu, attach menu — **one shared elevation colour for all chrome** |
| `surfaceInset` | `#131313` | Code block fill (`Convo2`) |
| `surfaceIconWell` | `#454545` | Small icon circles inside the attach menu (`Attach`) |
| `divider` | `#434343` | Blockquote rule / hairlines (`Convo1`) |
| `textPrimary` | `#FFFFFF` | Body copy, menu items, wordmark, recents (brightest pixel is pure white in every sample) |
| `textSecondary` | `#9E9E9E` | Section headers ("Pinned", "Recents") |
| `accent` | `#3A83F6` | Voice circle, "Chat" pill (`NewChat`, `TopLeftLines`) |
| `userBubble` | `#133362` | User message bubble fill (`Convo1`) |
| `avatarFill` | `#7E8C8D` | Account avatar circle (`TopLeftLines`) |
| `destructive` | `#EF4444` | "Delete" menu item. **Inferred**: only anti-aliased edge pixels were sampleable (`#FC8D93`); this is a standard red matching its appearance. |

Note `surfaceRaised` `#212121` is used for *every* raised chrome element —
buttons, composer, menus. Do not introduce additional greys.

### 2.2 Home surface (Google Weather)

The Home background is a **photographic sky**, not a flat colour or simple
gradient. Sampled vertical profile of `Home1`:

| Position | Hex |
|---|---|
| Top (cloud-lit) | `#C8D3E9` |
| Mid (open sky) | `#7995C4` |
| Lower | `#93A8C7` |
| `Home2` upper (scrolled) | `#5D80B6` |

Glass panels over that background:

| Token | Hex (as composited) | Notes |
|---|---|---|
| `glassPanel` | `#7794C0` | Only ~2–4% lighter than the sky behind it — a **very subtle** white overlay (~8–12% alpha) + blur, not a heavy frosted card |
| `glassPill` (AQI) | `#91A9CF` | Lighter than the panel |
| `glassButton` (5-day) | `#96ADCD` | Lighter still — nested elevation reads by small luminance steps only |
| Home text | `#FFFFFF` | All text on Home is white |

**Implementation:** panels are `BackdropFilter(ImageFilter.blur(...))` +
a low-alpha white fill. The subtlety is the point — a strong frosted card
would not match.

---

## 3. Geometry (measured from the references)

| Element | Measured | Spec value |
|---|---|---|
| Round icon button (hamburger, new-chat, search, overflow) | 57px | **40dp diameter**, `surfaceRaised` fill |
| Icon button horizontal screen margin | 18px | **12dp** |
| Composer pill height | 61px | **40dp** |
| Composer pill shape | corner profile matches r = height/2 | **fully rounded stadium** (radius 20dp) |
| Dropdown menu width | 286px | **191dp** |
| Dropdown menu corner radius | ~25px | **16dp** |
| User bubble corner radius | ~27px | **18dp** |
| User bubble max width | 388px of 540px | **~72% of screen width** |
| User bubble right margin | 21px | **14dp** |
| Sidebar "Chat" pill height | 59px | **40dp**, fully rounded |

Every round chrome affordance is the **same 40dp circle** — hamburger,
new-chat, search, overflow, avatar. This uniformity is load-bearing to the
look; do not vary sizes per-button.

---

## 4. Screen specifications

### 4.1 Chat — empty state (`NewChat.jpeg`, `NewChat2.jpeg`)

- Pure `#000000` background, no app bar surface.
- Top-left: 40dp round hamburger. Top-right: 40dp round new-chat button.
  Both float directly on the background — **no toolbar, no title text**.
- Body: empty, or a centred single-line prompt (`NewChat2` shows
  "Where should we begin?" centred above the composer).
- Composer docked to the bottom: 40dp-tall fully-rounded `#212121` pill,
  spanning full width minus side margins, containing **inside the pill**:
  - left: `+` attach icon
  - centre: placeholder text (WeatherGPT copy, e.g. "Ask WeatherGPT")
  - right (empty field): mic icon, then a solid `#3A83F6` circle with a
    waveform glyph (voice mode)
  - right (field has text): the mic/voice pair is replaced by a single
    circular send button with an up-arrow (`NewChat2`)

### 4.2 Chat — conversation (`Convo1.jpeg`, `Convo2.jpeg`)

- **User turn:** right-aligned `#133362` bubble, 18dp radius, max ~72% width,
  white text.
- **Assistant turn:** *no bubble* — white prose directly on the background,
  full width.
- **Assistant action row** beneath each reply: small outline icons —
  copy, read-aloud, share, overflow (`⋮`).
- **Code blocks:** `#131313` fill, monospace, copy icon top-right.
- **Blockquote:** left hairline rule `#434343`, indented text.
- Date separator ("Sunday 1:44 pm") centred, `textSecondary`.
- Top bar in a conversation: hamburger left; on the right a **grouped
  pill** containing edit/new-chat + overflow (`⋮`) — see `Convo1`/`Convo2`.

### 4.3 Sidebar / drawer (`TopLeftLines.jpeg`)

Slides over the screen, `#000000`, roughly 78% of screen width.

- Header row: **"WeatherGPT"** wordmark (large, bold, white) at left;
  40dp round search button and 40dp round new-chat button at right.
- Primary nav list (icon + label): the reference shows Images / Library /
  Projects / Scheduled / Plugins. **WeatherGPT's equivalents** — see
  Section 6, Open Decision 1.
- `Pinned` section header (`textSecondary`), then pinned conversation rows
  (speech-bubble icon + title).
- `Recents` section header, then conversation titles (text only, no icon).
- Bottom bar, pinned: `#3A83F6` fully-rounded pill with an edit glyph and
  the label **"Chat"** at left; account avatar circle (`#7E8C8D`, initials)
  at right.

### 4.4 Overflow dropdown (`TopRightDots.jpeg`)

- Anchored under the top-right button, 191dp wide, 16dp radius, `#212121`.
- Header line showing the conversation title, `textSecondary`.
- Rows: outline icon + label, white text, generous row height.
- Reference rows: Share / Pin / Add to project / Uploaded files / Find in
  chat / Add to home / Archive / Delete. **Delete is red** and last.
- WeatherGPT's row set and per-screen behaviour: Section 6, Open Decision 2.

### 4.5 Attach menu (`Attach.jpeg`)

- Opens **upward** from the `+` in the composer, anchored bottom-left.
- `#212121` fill, ~16dp radius.
- Rows: `#454545` circular icon well (~40dp) + white label.
- Reference rows: Camera / Photos / Files / Plugins / Think harder.
- In this build the rows render but perform no action (no attachment
  endpoint exists) — same treatment as the disabled mic.

### 4.6 Voice recording (`Voice.jpeg`)

The composer **transforms in place**: the text field and its icons are
replaced by, left to right —
- an `X` cancel button,
- a live scrolling **waveform** filling the pill's width,
- a stop button (square in a dark circle),
- a send button (up-arrow in a `#3A83F6` circle).

Visual only in this build; no STT wiring (BHASHINI remains blocked).

### 4.7 Home (`Home1.jpeg`, `Home2.jpeg`)

Scrolling screen over a full-bleed sky background.

Top chrome (over the background, no toolbar): hamburger (left), new-chat
(left, beside it), location name centred, overflow `⋮` (right).
*(The reference's own top bar is `+` / title / `⋮`; the hamburger and
new-chat buttons are WeatherGPT's addition per the brief.)*

Content order:
1. Location name + a status chip (the reference shows "Turn on location
   services"); page-indicator dots beneath.
2. **Hero:** very large temperature with a smaller `°C`, directly on the
   background — no card. Beneath it: condition + hi/lo (e.g.
   "Cloudy 30°/21°"), then an AQI pill.
3. Glass panel — **5-day forecast**: header row with icon, then one row
   per day (icon, day label + condition, `hi° / lo°` right-aligned), then
   a full-width rounded "5-day forecast" button.
4. Glass panel — **24-hour forecast**: a horizontally scrolling line graph
   with a temperature label above each point, a weather icon, wind speed,
   and the hour beneath. The line is a smooth curve with a warm-to-cool
   gradient stroke.
5. Two side-by-side glass panels: **wind** (compass dial with N/E/S/W and a
   direction arrow, plus speed) and **sunrise/sunset** (arc with a sun
   marker, times at each end).
6. Glass panel — **details grid**: Humidity, Real feel, UV, Pressure,
   Chance of rain as label/value rows.
7. AQI panel, then an attribution line.

> **Data reality check:** the backend's `/weather` returns
> `temperature_c, humidity_pct, weather_code, wind_speed_kmh,
> wind_direction_deg, observed_at, timezone`; `/forecast` returns
> `forecast_date, weather_code, temp_max_c, temp_min_c,
> precip_probability_pct, precip_sum_mm, wind_speed_max_kmh`.
> **There is no AQI, no UV, no pressure, no sunrise/sunset, no real-feel,
> and no hourly data.** See Section 6, Open Decision 3 — this is the
> single biggest gap between the reference and what we can populate.

### 4.8 Home share (`HomeShare.jpeg`)

Two-part flow:
1. A generated **image card**: sky photo top with big temperature,
   condition, AQI, and a 4-day mini forecast row; white footer with
   region, city, a tagline, and the date. App watermark top-right.
2. That image is handed to the **OS share sheet** (app icon grid).

Implementation: render the card widget inside a `RepaintBoundary`, capture
to PNG, hand to `share_plus`. Card content follows §4.7's data note.

### 4.9 Chat share (`ChatShare.jpeg`)

In-app modal sheet, not the OS sheet first:
- Title "Share conversation", subtitle "Anyone with the link can view
  previous messages."
- A horizontally paged preview card (conversation title + app wordmark on
  a coloured backdrop), with page dots.
- App-icon share target grid.
- Bottom row: "Copy link" and "Share via…" as circular icon + label.

### 4.10 Account & settings (`Details1-3`, `Details4`)

- Header: large avatar circle with an edit badge, display name beneath,
  40dp round back button top-left.
- Grouped rounded rows (`#212121`), section headers in `textSecondary`.
- Rows are icon + label, some with a secondary value line, some with a
  trailing chevron/expander.
- WeatherGPT's sections: profile, appearance/accent, notifications, voice,
  data controls — **plus a Units section** taken from `Details4`
  (temperature °C, wind km/h, pressure mbar).

---

## 5. Motion

The references are stills, so motion is inferred and deliberately minimal:
- Drawer: standard slide-in with scrim.
- Menus (overflow, attach): scale+fade from their anchor corner.
- Composer: cross-fade when swapping mic/voice ↔ send.
- Voice: continuously animating waveform while recording.
- No scroll-triggered reveals, no per-card entrance animations.

---

## 6. Decisions (resolved by the user)

1. **Sidebar nav rows** — **Home, Discover, News, Alerts, Saved places.**
   Only Home navigates anywhere in this build; Discover, News, Alerts and
   Saved places render as rows but are inert placeholders for future
   features (explicitly requested as "pre-firing future features").
2. **Overflow menu per screen** — context-dependent. On Home: a reduced
   menu (Share → the weather-image share flow, plus Settings). In an open
   conversation: the reference set minus rows with no backing feature —
   so Share / Pin / Find in chat / Archive / Delete, and **not** "Add to
   project" or "Uploaded files".
3. **Home panels** — **build only what the backend can actually fill.**
   Ship: hero temperature, condition + hi/lo, 5-day forecast panel, wind
   panel (speed + compass direction), and a details panel limited to
   humidity and wind. **Do not build** AQI, UV, pressure, real-feel,
   sunrise/sunset, or the 24-hour graph — no data source exists for them
   and no placeholder or invented values are to be shown. The Home screen
   is therefore shorter than `Home1`/`Home2`, using the same visual
   language for the panels it does have.
4. **Light mode** — **dark-only for this build**, but the theme must be
   structured so a light palette can be added later without rework
   (tokens resolved through a theme object, never hardcoded per widget).

### 6.1 Sky background system (user-directed refinement)

The Home background is **not a fixed light sky**. As in the real app, it
varies with **time of day** and **current conditions**. Build it as a
gradient system selected by two inputs:

- **Time of day**, derived from the device clock against the location's
  `timezone` (returned by `/weather`): `dawn`, `day`, `dusk`, `night`.
- **Condition bucket**, derived from the existing `weatherIconFor` WMO
  mapping: `clear`, `cloudy`, `fog`, `rain`, `snow`, `thunderstorm`.

Each combination resolves to a vertical multi-stop gradient. The sampled
`Home1` values (`#C8D3E9` → `#7995C4` → `#93A8C7`) define the
**day + cloudy** case; the others are designed to match its structure
(light top, saturated middle, lighter base) shifted in hue and value —
night variants are dark blues where white text still reads cleanly, which
also keeps foreground contrast constant across every variant.

Glass panels keep the same low-alpha-white + blur treatment against every
sky, so panel styling never needs per-variant special-casing.
