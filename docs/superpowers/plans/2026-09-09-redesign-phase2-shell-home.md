# Redesign Phase 2: Navigation Shell + Home Screen

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the 4-tab bottom-nav shell with a ChatGPT-style drawer + route stack, and build the Google-Weather-style Home screen on it — the app's launch screen and the first real screen a hackathon judge sees.

**Architecture:** `go_router`'s `StatefulShellRoute.indexedStack` is deleted outright; the root becomes a plain route stack whose Home scaffold owns a `Drawer`. Home renders `HomeUiState` (already built and preserved) over a full-bleed `skyGradient` chosen from the current conditions, with `GlassPanel` groups for forecast and detail data. Every component comes from the Phase 1 library; this phase adds no new visual primitives except the drawer itself.

**Tech Stack:** Flutter, Riverpod (`Notifier`/`NotifierProvider`), go_router, the Phase 1 design tokens.

**Spec:** `docs/superpowers/specs/2026-09-09-flutter-design-literal.md` (§2 Home, §5 sidebar; values sampled from `backend/FrontendReference/Home1.jpeg`, `Home2.jpeg`, `TopLeftLines.jpeg`).

## Global Constraints

- **No backend changes.** The backend is complete, merged, and out of scope.
- **No new package dependencies.** `share_plus` is deferred with the share flows.
- **Preserved files must not change:** `lib/core/network/`, `lib/data/`, `lib/features/home/home_controller.dart`, `lib/features/chat/chat_controller.dart`, `lib/core/geo.dart`, `lib/shared/widgets/weather_icon.dart`.
- **No fabricated data.** The backend has no AQI, UV, pressure, apparent-temperature, sunrise/sunset, or hourly series. Home shows **only** fields the API actually returns — no placeholder numbers, no greyed-out "coming soon" tiles for data that does not exist. This is a repeat constraint: an earlier draft of the frontend spec invented a "feels like" field that no endpoint serves.
- **All colours from `AppColors`; all dimensions from `AppRadius`/`AppSpacing`.** No raw `Color(0x...)` or magic numbers in widget code.
- **Text over sky must use `skyForeground(time, condition)`**, never a hardcoded white or black. All 24 gradients clear WCAG AA against it; hardcoding breaks that.
- **Never call `pumpAndSettle()` on a widget with a repeating animation.** It never returns. This bug has been hit twice in this project.
- Every widget gets tests that fail if the implementation is wrong.

## Available backend data (verified — do not re-derive)

`GET /weather` → `temperature_c`, `humidity_pct`, `weather_code`, `wind_speed_kmh`, `wind_direction_deg`, `observed_at`, `timezone`.
`GET /forecast?days=N` → per day: `forecast_date`, `weather_code`, `temp_max_c`, `temp_min_c`, `precip_probability_pct`, `precip_sum_mm`, `wind_speed_max_kmh`.
`GET /alerts` → nationwide; `HomeController` already filters to 100km via `haversineKm`.

Exposed as `CurrentWeather`, `ForecastDay`, `AlertSummary`, `GeocodeResult` in `lib/data/`, and composed by `HomeController` into `HomeLoading | HomeLoaded(location, weather, forecast, nearbyAlerts) | HomeError(error)`.

---

## File Structure

| File | Responsibility |
|---|---|
| `lib/core/router/app_router.dart` | MODIFY — delete the shell route + bottom nav; plain stack: `/home`, `/chat`, `/gallery` |
| `lib/features/shell/app_drawer.dart` | CREATE — the sidebar: wordmark, nav entries, recents, account row |
| `lib/features/home/home_screen.dart` | CREATE — composes the sky, chrome, hero, panels; renders `HomeUiState` |
| `lib/features/home/widgets/home_hero.dart` | CREATE — location, temperature, condition, high/low |
| `lib/features/home/widgets/forecast_panel.dart` | CREATE — glass panel, one row per `ForecastDay` |
| `lib/features/home/widgets/conditions_panel.dart` | CREATE — glass panel: humidity, wind, precipitation |
| `lib/features/home/widgets/alert_banner.dart` | CREATE — severity-coloured banner per nearby alert |
| `lib/features/shell/placeholder_screen.dart` | KEEP — still backs `/chat` until Phase 3 |

---

### Task 1: Navigation shell

**Files:**
- Modify: `lib/core/router/app_router.dart`
- Create: `lib/features/shell/app_drawer.dart`
- Test: `test/features/shell/app_drawer_test.dart`, `test/core/router/app_router_test.dart` (modify)

**Interfaces:**
- Produces: `AppDrawer` (a `Drawer` subclass, no required args); a router with top-level `/home`, `/chat`, `/gallery` routes and no `StatefulShellRoute`.

The 4-tab bottom nav is the single biggest reason the old build read as a generic app — neither reference has one. It goes entirely, replaced by the drawer.

`AppDrawer` per `TopLeftLines.jpeg`, on `AppColors.bgBase`:
- "WeatherGPT" wordmark top-left in `AppTypography.wordmark`.
- A `RoundIconButton` (`Icons.search`) top-right of the drawer header.
- Nav entries, each an icon + label row in `AppTypography.body`: Home, Discover, News, Alerts, Saved places. Discover and News are pre-wired and inert this phase (the user asked for them to exist); Home navigates to `/home`, the rest are no-ops for now.
- A "Recents" section header in `AppTypography.label`/`textSecondary`, then chat titles. Chat history is not persisted yet, so this renders an empty-state line ("No conversations yet") rather than fake entries.
- An account row pinned to the bottom: a 40dp circular avatar (`AppColors.avatarFill`) + "Your account", tapping which is a no-op until Phase 5.

- [ ] **Step 1: Write the failing tests**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weathergpt_app/core/theme/app_colors.dart';
import 'package:weathergpt_app/features/shell/app_drawer.dart';

void main() {
  Future<void> pumpDrawer(WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(drawer: AppDrawer(), body: SizedBox()),
    ));
    tester.state<ScaffoldState>(find.byType(Scaffold)).openDrawer();
    await tester.pumpAndSettle();
  }

  testWidgets('shows the WeatherGPT wordmark', (tester) async {
    await pumpDrawer(tester);
    expect(find.text('WeatherGPT'), findsOneWidget);
  });

  testWidgets('shows every nav entry', (tester) async {
    await pumpDrawer(tester);
    for (final label in ['Home', 'Discover', 'News', 'Alerts', 'Saved places']) {
      expect(find.text(label), findsOneWidget, reason: label);
    }
  });

  testWidgets('shows an empty recents state rather than fake chats',
      (tester) async {
    await pumpDrawer(tester);
    expect(find.text('Recents'), findsOneWidget);
    expect(find.text('No conversations yet'), findsOneWidget);
  });

  testWidgets('pins an account row at the bottom', (tester) async {
    await pumpDrawer(tester);
    expect(find.text('Your account'), findsOneWidget);

    final account = tester.getRect(find.text('Your account'));
    final wordmark = tester.getRect(find.text('WeatherGPT'));
    expect(account.top, greaterThan(wordmark.bottom));
  });

  testWidgets('drawer sits on the true-black base, not a Material surface',
      (tester) async {
    await pumpDrawer(tester);
    final drawer = tester.widget<Drawer>(find.byType(Drawer));
    expect(drawer.backgroundColor, AppColors.bgBase);
  });
}
```

- [ ] **Step 2: Run and confirm they fail**

```powershell
flutter test test\features\shell\app_drawer_test.dart
```

- [ ] **Step 3: Implement `AppDrawer` and rewrite the router**

Router becomes a flat `GoRouter` with `initialLocation: '/home'` and three top-level `GoRoute`s (`/home` → `HomeScreen` once Task 3 lands; until then keep `PlaceholderScreen`, `/chat` → `PlaceholderScreen`, `/gallery` → `GalleryScreen`). Delete `StatefulShellRoute`, `StatefulShellBranch`, and the `NavigationBar` entirely.

Update `app_router_test.dart`: it currently asserts `find.byType(NavigationBar)` — that assertion must be **inverted** (`findsNothing`), not deleted, so the bottom nav cannot silently return.

- [ ] **Step 4: Verify and commit**

```powershell
flutter analyze
flutter test
```

```bash
git add frontend/weathergpt_app/lib/core/router/app_router.dart frontend/weathergpt_app/lib/features/shell/ frontend/weathergpt_app/test/
git commit -m "feat: replace tab shell with ChatGPT-style drawer"
```

---

### Task 2: Home presentational widgets

**Files:**
- Create: `lib/features/home/widgets/home_hero.dart`, `forecast_panel.dart`, `conditions_panel.dart`, `alert_banner.dart`
- Test: `test/features/home/widgets/home_widgets_test.dart`

**Interfaces:**
- Consumes: `CurrentWeather`, `ForecastDay`, `AlertSummary` from `lib/data/`; `GlassPanel`, `weatherIconFor`, `skyForeground` from earlier phases.
- Produces:
  - `HomeHero({required String place, required CurrentWeather weather, required Color foreground})`
  - `ForecastPanel({required List<ForecastDay> days, required Color foreground})`
  - `ConditionsPanel({required CurrentWeather weather, required Color foreground})`
  - `AlertBanner({required AlertSummary alert})`

Each takes `foreground` explicitly rather than reading a provider, so all four are pure and directly testable, and so the caller (which knows the sky) stays the single source of that decision.

`HomeHero` per `Home1.jpeg`: place name in `AppTypography.title`, temperature in `AppTypography.hero` with a degree glyph, condition text under it, high/low in `AppTypography.label`. All in `foreground`.

`ForecastPanel`: a `GlassPanel` containing one row per day — weekday abbreviation, `weatherIconFor(weatherCode)`, precipitation probability when > 0, and `max° / min°`. No chart (there is no hourly series to chart).

`ConditionsPanel`: a `GlassPanel` with humidity, wind speed + cardinal direction derived from `windDirectionDeg`, and nothing else — these are the only remaining fields `/weather` returns.

`AlertBanner`: full-width, `AppRadius.panel`, filled with `AppColors.alertSeverity(alert.severity)` and labelled in `AppColors.onAlertSeverity(...)`, showing event type and area description. Not a glass panel — an alert must not be subtle.

- [ ] **Step 1: Write the failing tests**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weathergpt_app/core/theme/app_colors.dart';
import 'package:weathergpt_app/data/weather_api.dart';
import 'package:weathergpt_app/features/home/widgets/forecast_panel.dart';
import 'package:weathergpt_app/features/home/widgets/home_hero.dart';

final _weather = CurrentWeather(
  temperatureC: 24.4,
  humidityPct: 71,
  weatherCode: 61,
  windSpeedKmh: 18.2,
  windDirectionDeg: 270,
  observedAt: '2026-09-09T12:00',
  timezone: 'Asia/Kolkata',
);

void main() {
  testWidgets('hero rounds the temperature and shows the place', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: HomeHero(
          place: 'Pune',
          weather: _weather,
          foreground: AppColors.textPrimary,
        ),
      ),
    ));

    expect(find.text('Pune'), findsOneWidget);
    expect(find.textContaining('24'), findsWidgets);
    // 24.4 must not be rendered raw.
    expect(find.textContaining('24.4'), findsNothing);
  });

  testWidgets('hero paints its text in the supplied foreground', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: HomeHero(
          place: 'Pune',
          weather: _weather,
          foreground: AppColors.bgBase,
        ),
      ),
    ));

    final place = tester.widget<Text>(find.text('Pune'));
    expect(place.style?.color, AppColors.bgBase);
  });

  testWidgets('forecast panel renders one row per day', (tester) async {
    final days = [
      ForecastDay(
        forecastDate: '2026-09-09',
        weatherCode: 61,
        tempMaxC: 31.2,
        tempMinC: 24.1,
        precipProbabilityPct: 80,
        precipSumMm: 12.0,
        windSpeedMaxKmh: 29.6,
      ),
      ForecastDay(
        forecastDate: '2026-09-10',
        weatherCode: 1,
        tempMaxC: 33.0,
        tempMinC: 25.0,
        precipProbabilityPct: 0,
        precipSumMm: 0,
        windSpeedMaxKmh: 12.0,
      ),
    ];

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ForecastPanel(days: days, foreground: AppColors.textPrimary),
      ),
    ));

    expect(find.textContaining('31'), findsWidgets);
    expect(find.textContaining('33'), findsWidgets);
    // A 0% chance is not shown at all rather than shown as "0%".
    expect(find.text('0%'), findsNothing);
    expect(find.text('80%'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run and confirm they fail**

- [ ] **Step 3: Implement the four widgets**

Check `lib/data/weather_api.dart` for the exact constructor parameter names before writing the fixtures — do not guess them.

- [ ] **Step 4: Verify and commit**

```bash
git commit -m "feat: add Home presentational widgets"
```

---

### Task 3: Home screen

**Files:**
- Create: `lib/features/home/home_screen.dart`
- Modify: `lib/core/router/app_router.dart` (point `/home` at it)
- Test: `test/features/home/home_screen_test.dart`

**Interfaces:**
- Consumes: `homeControllerProvider`, `HomeUiState`, Task 2's widgets, `AppDrawer`, `skyGradient`/`skyForeground`/`skyConditionFor`/`skyTimeOfDayFor`, `RoundIconButton`, `showAppMenu`.

A `ConsumerStatefulWidget` calling `loadInitial()` once in `initState`, rendering:
- **Background:** full-bleed `skyGradient(skyTimeOfDayFor(now), skyConditionFor(weather.weatherCode))`. `now` comes from the device clock; the location's `timezone` string is available but converting it needs a tz database this project does not bundle — use local time and note the limitation.
- **Chrome:** a `RoundIconButton(Icons.menu)` top-left opening the drawer, and `RoundIconButton(Icons.more_vert)` top-right opening `showAppMenu` with a Home-appropriate reduced item set (Share, Saved places, Settings — Share is inert until `share_plus` lands). `AppSpacing.screenMargin` from each edge, floating over the sky with no `AppBar`.
- **Body:** `HomeHero`, then any `AlertBanner`s, then `ForecastPanel`, then `ConditionsPanel`, in a scroll view.
- **States:** `HomeLoading` → a centred progress indicator on the sky; `HomeError` → message + a retry button calling `controller.retry()`.

Tests inject a fake API layer by overriding `weatherApiProvider`/`alertsApiProvider`/`geocodingApiProvider` — the pattern `chat_controller_test.dart` established. Prove: loaded state renders hero + forecast; error state shows retry and retry re-fetches; the sky gradient actually varies with `weatherCode`; **no bottom `NavigationBar` exists anywhere**.

- [ ] **Step 1-4:** Same TDD cycle. Commit: `feat: build the Google-Weather-style Home screen`.

---

### Task 4: Home goldens

**Files:**
- Create: `test/golden/home_golden_test.dart`, `test/golden/goldens/home_*.png`

Reuse the `FontLoader` `setUpAll` from `test/golden/gallery_golden_test.dart` verbatim. Render `HomeLoaded` with realistic Pune data across three goldens: a day sky, a night sky, and one with an active severe alert banner. Plus one `HomeError` golden — error states are where polish usually dies, and this project already shipped one illegible error state that eye-inspection caught.

Generate with `--update-goldens`, then re-run **without** the flag and confirm passing. The controller inspects every PNG by eye before this phase is done.

- [ ] Commit: `test: add Home screen goldens`.

---

## Verification

`flutter analyze` clean, full `flutter test` passing, goldens deterministic, and controller eye-inspection of every generated PNG.
