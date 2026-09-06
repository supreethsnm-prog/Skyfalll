# WeatherGPT — V1 Design

**SIH 2026, Problem Statement 26068** — Ministry of Earth Sciences / India Meteorological Department, Disaster Management theme.

This document is the single source of truth for what V1 builds and why. The official problem statement is the floor for V1 scope — nothing it lists is deferred to a later version. Features beyond the PS (mentioned in the original master-prompt research brief but not required by the PS) are explicitly out of V1 and noted at the end.

## 1. Grounding principle

The LLM interprets natural language and calls tools; it never invents or independently fetches a weather/alert fact. Every fact the LLM can state comes from our own Postgres cache, populated by scheduled ingestion jobs, never from a live upstream call made during a chat turn. This is enforced structurally (see §3), not by prompting alone.

## 2. Architecture

- **Client**: Flutter mobile app.
- **Backend**: FastAPI + PostgreSQL.
- **Provider abstraction**: every external data/service dependency sits behind an interface, so swapping or adding a source is a new adapter, not a rewrite. Providers: `WeatherProvider`, `WarningProvider`, `AviationProvider`, `MarineProvider`, `HistoricalWeatherProvider`, `NWPProvider`, `GeocodingProvider`, `SpeechToTextProvider`/`TextToSpeechProvider`, `NotificationProvider`, `LLMProvider`.
- **Skills/rules engine**: deterministic rule evaluation over ingested data. The LLM's job is to parse natural language into a structured request/rule; the engine's job is to evaluate it against real data and produce a structured result, which the LLM then verbalizes. Used both for user-defined alert rules and for synthesizing advisories where no direct government feed exists (agriculture, urban — see §4).

## 3. Ingestion vs. query split (latency + reliability)

Two layers, hard separation:

- **Ingestion** (scheduled jobs, one per source, cadence matched to how often that source actually changes): writes normalized rows into Postgres. Runs independently of any user request.
- **Query** (the chat request path): the LLM's tools only read from Postgres — indexed, sub-100ms, no external network call in the request path, ever.

Cadences:
| Source | Cadence |
|---|---|
| SACHET alerts (nowcasts change fast) | ~5 min |
| Open-Meteo / IMD current + forecast | ~15–30 min |
| GFS | once per model run (00/06/12/18 UTC) |
| METAR | ~20–30 min |
| INCOIS PFZ | ~daily (advisories issued 3×/week) |
| ERA5 | one-off/periodic batch, not polled |

Consequence: an upstream outage (e.g. SACHET down) stalls a cron, it does not break a live chat response — the app serves the last good cache. Geocoded place names are also cached in Postgres so repeat lookups don't re-hit the geocoding provider.

**Amendment (point-location sources):** the scheduled-ingestion model above assumes a bounded source — a nationwide feed or a fixed grid that can be polled in full. It doesn't fit a source queried by arbitrary coordinate (weather-by-lat/lon): there is no fixed set of locations to precompute. For these sources, the query path may perform a live provider call, but only as a cache-miss fallback: check Postgres first (keyed by coordinate, rounded to ~1km precision), serve it if fresher than the source's cadence above, and only call the provider live — then cache the result — when the cache misses or has gone stale. This is a deliberate, narrow exception to "no external network call in the request path, ever," granted only to sources that are official, documented, and generously rate-limited (Open-Meteo qualifies; SACHET does not — SACHET's ingestion stays strictly scheduled-only, per its risk profile in §4). A repeat query for the same rounded coordinate within the cadence window never leaves Postgres.

**Second amendment (permanent-cache sources under a hard rate limit):** geocoding (place name → coordinate) is also point-queried with no fixed location set, but the amendment above doesn't quite fit it either — Nominatim (the geocoding provider) is the opposite of "generously rate-limited" (its free public instance caps regular/scripted use at 4 requests/minute). The exception still applies, inverted: because the source is rate-constrained rather than generous, the cache carries no TTL at all — a place's coordinates don't change, so a lookup happens at most once per query, ever, and every repeat is a guaranteed cache hit. This is stricter than the first amendment (no staleness window, ever) precisely because the upstream is stricter. As of this writing, negative results (a query with no match) are not cached and a repeated not-found query does still reach the provider each time — a known gap to close (alongside a request-rate throttle in the provider itself) before this endpoint is exposed to real traffic; see the geocoding sprint's plan for the accepted-for-V1 rationale.

## 4. Data sources — verified, per feature

Every source below was tested directly (live HTTP calls) during research, not assumed from documentation.

**Alerts / early warning** — `WarningProvider`
- Primary: SACHET (`sachet.ndma.gov.in/cap_public_website/FetchAllAlertDetails`, `FetchIMDNowcastAlerts`, `FetchEarthquakeAlerts`, `FetchCycloneDetails`). Unauthenticated JSON, confirmed live. Undocumented/reverse-engineered — no ToS, no rate-limit docs, could change without notice. Mitigation: isolate entirely behind `WarningProvider`, poll server-side only, cache last-good payload, one canonical internal `Alert` model with a small adapter per endpoint (schemas differ between endpoints).
- Future swap-in: official IMD API (`api.imd.gov.in`) — confirmed real and comprehensive (28+ endpoints) but returns 401 on every endpoint; needs IP whitelisting via an institutional request with unknown turnaround. Filed in parallel, not a V1 dependency.

**Weather (current/forecast)** — `WeatherProvider`
- Open-Meteo (global, no auth) as V1 default; IMD official API as the future swap-in once whitelisted.

**NWP** — `NWPProvider`
- GFS via the public, unauthenticated AWS S3 bucket `noaa-gfs-bdp-pds`. Raw GRIB2, parsed server-side with `cfgrib`/`xarray` during ingestion, not per-request. Satisfies the PS's "GFS/WRF" requirement; WRF specifically has no live public feed for India — NCMRWF's self-serve portal (registration, no institutional gate) offers IMDAA regional reanalysis (1979–2018, historical) as a V2 upgrade path for higher-resolution India-specific analysis, not a live forecast source.

**Historical/climate** — `HistoricalWeatherProvider`
- ERA5 via Copernicus Climate Data Store, current client (`ecmwf-datastores-client`), self-serve account + per-dataset license acceptance.

**Aviation weather briefing** — `AviationProvider`
- `aviationweather.gov/api/data/metar` and `/taf`. Verified live against Indian ICAO codes (VABB Mumbai, VIDP Delhi) — real decoded JSON, free, no auth, global WMO exchange coverage.

**Marine** — `MarineProvider`
- INCOIS public GeoServer, WFS `GetFeature` at `incois.gov.in/geoserver/PFZ_Automation/ows`, `typeNames=PFZ_Automation:pfzlines`, `outputFormat=application/json`. Verified live — real GeoJSON Potential Fishing Zone line geometries, no auth, standard OGC WFS.

**Agriculture advisory** — Skill, not a data source
- No public IMD Agromet API exists (web/app-only). V1 does not scrape it. Instead, a rules-based Skill combines already-ingested district forecast + rainfall + active warnings with a small, explicit crop-advisory ruleset to generate advisories directly — transparent and explainable rather than a redistribution of a bulletin we can't reach.

**Urban planning / smart city monitoring** — Skill, not a data source
- Same pattern: a Skill over already-ingested current weather + active alerts, producing waterlogging/heat-risk-style advisories. No new data source required.

**Voice (multilingual, rural accessibility)** — `SpeechToTextProvider` / `TextToSpeechProvider`
- BHASHINI (ULCA) as primary — self-serve registration at `bhashini.gov.in/ulca/user/register`, free tier for prototyping. Google Cloud Speech as documented fallback.

**Real-time dissemination** (PS: "scalable architecture supporting real-time data ingestion", suggested stack: MQTT/WIS2.0/WebSocket)
- Satisfied structurally by §3's ingestion layer plus a WebSocket (and FCM for background) push channel: when a new alert lands in Postgres, connected clients are pushed immediately rather than polling. Literal WIS2 node subscription is filed as a parallel institutional request and would plug into the same ingestion interface later; it is not required to meet this PS requirement for V1.

**LLM** — `LLMProvider`
- No model name is hardcoded. The PS itself lists "OpenAI, Llama, Gemini, etc." as illustrative, not mandatory. A currently-real, verified model is selected at the implementation sprint for this provider — the abstraction makes the choice a config value, not an architecture decision.

## 5. Explicitly out of V1

None. Every PS bullet (real-time retrieval, NL querying, NWP, alerts, location-based advisory, multilingual, historical/climate, voice, decision support for agriculture/aviation/marine/urban planning, scalable real-time-ingestion architecture) has a verified data source or a concrete Skill-based mechanism above.

Deferred to later versions (beyond what the PS requires, drawn from the original master-prompt research brief): direct IMD API integration (pending whitelist), IMD WIS2 subscription (pending institutional access), NCMRWF/IMDAA regional reanalysis (V2 upgrade for higher-res historical data), any provider beyond what's listed above.

## 6. Delivery approach

Sprint-based. Each sprint ends in a state that actually runs and is verified (endpoint responds, screen loads, tests pass) before the next sprint starts — no multi-phase batch implementation. Sprint plan produced separately via the writing-plans process, following this spec.
