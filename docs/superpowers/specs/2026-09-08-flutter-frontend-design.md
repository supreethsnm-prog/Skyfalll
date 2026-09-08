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
   BHASHINI's credential issue is resolved externally.
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
  of the tokens.
- **Phase 1** — Home screen, visually iterated (see §12).
- **Phase 2** — Chat.
- **Phase 3** — Forecast, Alerts (+ live WS), Historical, Advisories.

Standing instruction for this rollout only (explicitly approved): at each
phase's finish-branch menu, auto-select "merge to main locally" and
proceed to the next phase without waiting for a response, matching how
every backend sprint this session was resolved.

## 12. Visual iteration without a human in the loop

The brief's iteration loop ("build Home, run it, visually inspect,
iterate, then move on") assumes a human looking at each build. For the
unattended stretch, self-review replaces that: run the build (Chrome via
`claude-in-chrome`, or the Android emulator via screencap), take a
screenshot, and critique it against the design tokens and the brief's
design principles before calling a screen "polished." When the user is
present and watching, `flutter run -d chrome`/an emulator window updates
live on save — no extra tooling needed for that case.

## 13. Explicitly out of scope for this spec

- Any backend modification (including the `/alerts` lat/lon gap in §8).
- FCM background push implementation (architecture only, per §10).
- A working BHASHINI voice experience (blocked externally, per §9).
- Non-Android target polish (web/Windows desktop are used only as fast
  dev-loop targets, not judged deliverables).
