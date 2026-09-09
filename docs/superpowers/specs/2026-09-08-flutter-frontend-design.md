# WeatherGPT — Flutter Frontend Design

Companion to `2026-09-05-weathergpt-v1-design.md` (the backend spec). That
document is unaffected by this one — this spec adds a client, it does not
change the backend's contract. The backend is feature-complete for V1
(367 tests passing on `main` as of this writing) and is treated as a fixed
API surface here; no backend changes are proposed by this spec.

## 1. Goal

A judge-facing SIH 2026 mobile app that feels like a polished production
AI/weather product — ChatGPT-level interaction quality as the UX
benchmark, its own visual identity, not a generic Material demo.

## 2. Project layout

New top-level directory `frontend/weathergpt_app/`, sibling to `backend/`
(monorepo shape, not nested inside the backend). Flutter stable channel.

## 3. Tech stack

| Concern | Choice | Why |
|---|---|---|
| State management | `flutter_riverpod` (no code-gen) | Handles the amount of async server state this app has (10+ REST endpoints + 1 websocket) without build_runner fragility. |
| Routing | `go_router` | Declarative, supports a persistent bottom-nav shell plus push routes, deep-link-ready for later. |
| HTTP | `dio` | Interceptors give one place for base-URL injection, timeouts, and error mapping instead of repeating it per call. |
| Realtime | `web_socket_channel` | Backend already exposes `GET /ws/alerts` (see backend spec §3, "Real-time dissemination"). |
| Charts | `fl_chart` | Used for forecast/historical visualizations; the `dataviz` skill is invoked when those screens are actually built, not before. |
| Fonts | Bundled `.ttf` assets | Not the `google_fonts` package's runtime-fetch mode — typography must not depend on network access during a live judged demo. |
| Models | Hand-written Dart classes, manual `fromJson` | No `freezed`/`json_serializable` — avoids build_runner as a point of failure on an unfamiliar machine under time pressure. |

Minimize dependencies beyond this list; a new package needs a concrete
reason tied to a screen actually being built, not speculative future use.

## 4. Architecture (3 layers, feature-first)

```
lib/
  core/        # env config, dio client, theme tokens, router, shared error types
  shared/      # reusable design-system widgets: buttons, cards, chips,
               # loading/error/empty states, weather icon mapper
  data/        # one file per backend domain (weather_api.dart, alerts_api.dart,
               # chat_api.dart, ...) — thin wrappers returning typed models
  features/
    home/  chat/  forecast/  alerts/  historical/  advisories/  voice/
      -> each: presentation widgets + a Riverpod controller/provider
```

Presentation never calls `dio` directly — it goes through `data/`. No
separate domain/use-case layer: full 4-layer clean architecture is
unnecessary ceremony for this scope (YAGNI), and "presentation / state /
API-data / models" (the brief's own phrasing) maps directly onto
`features/ + core/state` / `data/` / the model classes inside `data/`.

## 5. Environment configuration

Base URL supplied via `--dart-define=API_BASE_URL=...`, not hardcoded and
not committed. Defaults documented in the app's README:
- Android emulator: `10.0.2.2:8000` (maps to host loopback automatically).
- Real device on the same LAN: the dev machine's LAN IP, passed explicitly.
- Chrome/web/Windows desktop dev: `127.0.0.1:8000` (loopback works directly).

No frontend secrets exist — every third-party credential (Gemini,
Anthropic, BHASHINI, CDS) lives server-side per the backend spec. The
client only ever talks to this backend.

## 6. Navigation & screen-to-API mapping

Bottom-nav shell, 4 destinations. Endpoints are grouped by user intent,
not exposed 1:1 — the full backend surface is enumerated in the backend
spec §4 and `backend/app/main.py`.

1. **Home** — `GET /weather` (current conditions), `GET /alerts` (banner,
   client-side distance-filtered — see §8), `GET /forecast` (today strip),
   `GET /geocode` (location switcher), quick-action chips into Chat /
   Forecast / Alerts.
2. **Chat** — `POST /chat`. `POST /voice/chat` + `GET /voice/languages`
   wired end-to-end but feature-flagged off in the UI (see §9) until
   BHASHINI's credential issue is resolved externally. Full design in §6a.
3. **Forecast** — `GET /forecast` (Open-Meteo daily) as the primary view,
   with a collapsible "Model outlook (GFS)" section backed by `GET /nwp`
   — same screen, since both answer "what's coming," not two screens.
4. **More** — a hub screen for:
   - **Alerts** (detail) — `GET /alerts` + live push via `GET /ws/alerts`.
   - **Historical** — `GET /historical`, city + date **pickers constrained
     to the real seeded coverage** (6 cities × 6 dates — see
     `backend/scripts/seed_era5_history.py`), never free-text input, since
     free text would just produce constant 404s against the tiny fixed
     matrix.
   - **Marine** (`GET /marine/pfz-zones`), **Aviation** (`GET /metar` by
     ICAO code), **Agriculture** (`GET /advisory/agriculture`), **Urban**
     (`GET /advisory/urban`) as cards in a shared Advisories view.

## 6a. Chat screen design

The centerpiece of this app (the user restated the goal mid-build as
"pretty much a ChatGPT app clone" — chat is the primary surface, not one
tab among four). Design, grounded in what `POST /chat` actually returns
(`{"reply": string, "history": [{"role", "content", ...}]}` per
`backend/app/chat/service.py`):

- **Message list**: reversed `ListView` (newest at bottom, auto-scrolls
  on new message). User messages are right-aligned with a light
  Marigold-tinted rounded surface (`AppRadius.surface`); assistant
  messages are left-aligned as flat text on the background — no bubble —
  per the "subtle elevation, not card-heavy" principle. Only the user's
  turn gets a visible container; the assistant's response reads as
  direct prose, the way ChatGPT's own assistant turns do.
- **Composer**: bottom-anchored, multiline auto-growing text field, a
  mic-icon affordance (present but disabled per §9's voice feature flag
  — greyed out, not hidden, so the seam is visible), and a send button
  using `AppPrimaryButton`'s icon-capable variant (added in Phase 0
  specifically anticipating this).
- **"Streaming" feel without real streaming**: `POST /chat` is a single
  request/response, not a token stream (backend spec §1's grounding
  principle — the LLM call happens once per turn — and this branch does
  not modify the backend). The feel is approximated client-side: a
  typing indicator (three animated dots, not a full-screen `LoadingView`)
  while the request is in flight, then the reply text reveals over a
  short duration (e.g. a fast word-by-word or char-by-char fade-in)
  once it arrives, rather than snapping in instantly. This is a UI
  animation choice, not a backend capability — labelled as such in code
  comments so it's never mistaken for real streaming later.
- **History**: kept in memory for the session as the same
  `role`/`content` list shape the backend's `history` field already
  uses — round-tripped back to `POST /chat` verbatim each turn (this is
  exactly what the backend contract expects; no translation layer
  needed). No local persistence in this phase (YAGNI — add if a later
  phase needs conversations to survive an app restart).
- **Empty state**: first load shows a short welcome + 3-4 suggested
  question chips (`AppChip`, e.g. "Any alerts near me?", "Will it rain
  in Pune tomorrow?") — tapping one fills and sends the composer. A
  ChatGPT-familiar affordance that also doubles as a demo aid for
  judges who don't know what to ask.
- **Errors**: a failed request shows an inline `ErrorView` in place of
  the pending assistant turn, with Retry re-sending the same user
  message — never a full-screen error that loses the conversation.

## 6c. Home screen design

Grounded in the actual verified response shapes (read directly from
backend source during planning, not assumed):

- `GET /weather` → `temperature_c, humidity_pct, weather_code,
  wind_speed_kmh, wind_direction_deg, observed_at, timezone,
  fetched_at` (plus lat/lon). **No "feels like"/apparent-temperature
  field exists** — an earlier draft of this spec mentioned one; that
  was wrong and is corrected here. Home shows only what the API
  actually returns.
- `GET /forecast?days=N` → a list of `{forecast_date, weather_code,
  temp_max_c, temp_min_c, precip_probability_pct, precip_sum_mm,
  wind_speed_max_kmh, fetched_at}`.
- `GET /alerts` → the full nationwide list (no lat/lon filtering
  server-side — see §8's known gap), each entry `{id, external_id,
  source, severity, event_type, area_description,
  effective_start_time, effective_end_time, warning_message, latitude,
  longitude, fetched_at}`. Note the row also carries a `severity_color`
  field from the upstream SACHET feed — **the frontend ignores it** and
  uses its own `AppColors.alertSeverity(severity)` mapping instead, for
  visual consistency with the rest of the app's design system rather
  than an externally-sourced color.
- `GET /geocode?q=` → `{query, display_name, latitude, longitude,
  country, state, fetched_at}`, 404 if not found.

**Layout** (left-aligned, per the design system's established
convention):
1. **Location bar** — the current location's display name + a search
   affordance opening a location picker (a modal using `GET /geocode`).
   No GPS/device-location integration in this phase (no location
   permission plumbing exists yet, and it isn't needed to demo a
   specific city) — the app starts at a fixed default location and the
   user switches it via search. This is a real, deliberate scope cut,
   not an oversight.
2. **Current conditions hero** — large temperature (`AppTypography.display`),
   a condition icon (`weatherIconFor(weather_code)`, already built),
   humidity and wind as secondary stats (`AppTypography.body`/`caption`)
   — no fabricated "feels like" value.
3. **Alert banner** — shown only when at least one alert's own lat/lon
   is within a fixed radius (e.g. 100km, matching the backend's own
   `warning_service.list_alerts`'s existing default radius constant) of
   the current location, computed client-side via a small haversine
   helper (mirroring the backend's `app/geo.py` formula) since the
   `/alerts` endpoint doesn't filter server-side. Uses
   `AppColors.alertSeverity`/`onAlertSeverity` for severity coloring —
   both already built and tested in Phase 0.
4. **Forecast strip** — a short horizontal preview of the next few
   `/forecast` days (icon + high/low), not the full multi-day view
   (that's the dedicated Forecast screen, a later phase) — tapping it
   navigates to the `/forecast` tab.
5. **Quick actions** — a row of `AppChip`s with example questions that
   navigate to `/chat` and send the tapped question, reusing the exact
   pattern Chat's own empty-state already established.

**Loading/error/empty states**: `LoadingView` while the initial fetch is
in flight, `ErrorView` with Retry on failure (matching Chat's error
pattern), and a location-not-found message (not a generic error) when
`GET /geocode` 404s during a search.

## 6b. Environment note: no Android emulator on this hardware

Recorded here because it affects every future phase's verification
step, not just Phase 0's: this machine's GPU (Intel UHD Graphics)
reports Vulkan 1.3.235 while the Android emulator requires >= 1.3.240,
so it falls back to software rendering and does not boot in practice
(confirmed: two attempts, one hung for 40+ minutes with a frozen CPU
counter). Visual verification for every phase runs against golden-image
tests (real fonts loaded via `FontLoader`, rendered offline, reviewed as
PNGs) rather than a live emulator screenshot. A real Android device,
when available, remains the way to catch device-specific issues this
approach can't (system font fallback, real touch ripple, status-bar
insets) — not required for a phase to ship, but worth doing once before
the actual hackathon demo.

## 7. Design system

A dedicated phase (see §11) produces the visual language — palette, type
scale, elevation, motion — before any screen is built, using the
`frontend-design` skill for aesthetic direction rather than improvised
Material defaults. Principles carried from the brief: calm/premium
weather-AI aesthetic, strong hierarchy, subtle elevation over heavy
cards, tasteful micro-interactions, touch-first sizing, adaptive layouts.

## 8. Known backend gap (not fixed here)

`GET /alerts` does not accept `lat`/`lon` query params even though
`warning_service.list_alerts()` already supports distance filtering
server-side (`backend/app/main.py`'s route calls it with no arguments).
Per the "do not modify the backend" constraint, the frontend performs its
own client-side haversine filtering against each alert's own lat/lon
instead of requesting a backend change. Non-blocking; flagged for a
future backend-side fix if this frontend work later needs it.

## 9. Voice (BHASHINI)

`BHASHINI_INFERENCE_KEY` currently fails server-side with
`"ulcaApiKey does not exist"` (external credential issue, not a code bug
— see project history). The chat composer's mic button and the
`/voice/chat` call path are fully implemented in code but hidden behind a
single static feature flag (e.g. `kVoiceEnabled`), so flipping it on
later requires no rework — only removing the flag once the backend
credential is fixed.

## 10. Push notifications

Architecture leaves room for FCM (a `NotificationProvider`-shaped seam in
`core/`) but no background push is implemented in this phase, per the
brief's explicit instruction.

## 11. Rollout — phased sub-projects

Each phase is its own worktree → plan → subagent-driven-development →
finish-branch cycle, consistent with how every backend sprint this
project has shipped:

- **Phase 0** — scaffold + core infra: networking (`dio` client + env
  config), theming shell, router, shared widgets/design tokens. No
  user-facing screens beyond a component gallery for visual sanity-check
  of the tokens. **Shipped** — merged to main, 30 tests passing.
- **Phase 1** — Chat (see §6a). Reordered ahead of Home per a live
  mid-build instruction restating the goal as a ChatGPT-style app —
  chat is the product's center, not one tab among four. **Shipped** —
  merged to main, 58 tests passing. Final review caught and fixed a real
  bug the per-task reviews couldn't see: the backend's tool-calling
  turns (`role: "assistant"` + a `tool_calls` key, `content` often
  `""`) were rendering as blank assistant bubbles on nearly every real
  query, since the system prompt requires tool use for most
  weather/alert questions. Fixed by rejecting any entry carrying
  `tool_calls` or empty/whitespace content in `ChatTurn.tryFromRaw`.
  Also fixed: sending a new message while in a failed state silently
  discarded the failed message with no trace — composer is now locked
  to `ChatIdle` only, forcing Retry as the sole path out of a failure.
- **Phase 2** — Home screen, visually iterated (see §12).
- **Phase 3** — Forecast, Alerts (+ live WS), Historical, Advisories.

Standing instruction for this rollout only (explicitly approved): at each
phase's finish-branch menu, auto-select "merge to main locally" and
proceed to the next phase without waiting for a response, matching how
every backend sprint this session was resolved.

## 12. Visual iteration without a human in the loop

The brief's iteration loop ("build a screen, run it, visually inspect,
iterate, then move on") assumes a human looking at each build. For the
unattended stretch, self-review replaces that: per §6b, the Android
emulator does not boot on this hardware, so verification runs as an
offline golden-image test (real bundled fonts loaded via `FontLoader`,
rendered to a PNG at a phone-shaped logical size, reviewed by eye)
rather than a live emulator or device screenshot. When the user is
present and watching, `flutter run -d chrome`/`-d windows` still updates
live on save for a fast dev loop — no extra tooling needed for that case,
it just isn't the verification step a phase's completion depends on.

## 13. Explicitly out of scope for this spec

- Any backend modification (including the `/alerts` lat/lon gap in §8).
- FCM background push implementation (architecture only, per §10).
- A working BHASHINI voice experience (blocked externally, per §9).
- Non-Android target polish (web/Windows desktop are used only as fast
  dev-loop targets, not judged deliverables).
