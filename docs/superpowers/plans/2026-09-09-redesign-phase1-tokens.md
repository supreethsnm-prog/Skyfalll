# Redesign Phase 1 — Design Tokens & Component Library

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the abandoned "Monsoon Sky" visual layer with the token set and component library specified in the literal visual spec, verified by a component gallery rendered to golden images.

**Architecture:** Demolish the old theme + shared widgets + chat screen in one task (they are mutually dependent and all being replaced), lay the new sampled-value token foundation, then rebuild the component library on top of it: chrome (round buttons, glass panels), chat messages (user bubble, assistant prose, code block), and menus.

**Tech Stack:** Flutter, `flutter_riverpod`, `go_router`, `dio` — all already installed. Adds Roboto/RobotoMono as bundled font assets, removes Sora/Inter/IBMPlexMono. No new packages in this phase.

**Spec:** `docs/superpowers/specs/2026-09-09-flutter-design-literal.md` — **read it first; it is the authority for every colour, size, and radius below.** Reference screenshots are committed at `backend/FrontendReference/`.

## Global Constraints

- **Every value comes from the spec.** Colours were sampled from the reference pixels and geometry was measured from them. Do not substitute "nicer" values, do not round them off, do not invent additions.
- Exact colours: `bgBase #000000`, `surfaceRaised #212121`, `surfaceInset #131313`, `surfaceIconWell #454545`, `divider #434343`, `textPrimary #FFFFFF`, `textSecondary #9E9E9E`, `accent #3A83F6`, `userBubble #133362`, `avatarFill #7E8C8D`, `destructive #EF4444`.
- Exact geometry: round icon button **40dp**, screen side margin **12dp**, composer pill **40dp tall, fully rounded (r=20dp)**, dropdown menu **191dp wide, 16dp radius**, user bubble **18dp radius, max 72% screen width, 14dp right margin**.
- `surfaceRaised` `#212121` is the **one** raised-chrome colour — buttons, composer, menus all share it. Do not introduce other greys.
- Dark-only in this phase, but **all tokens resolve through the theme**, never hardcoded per widget, so a light palette can be added later without rework.
- Every shell command dot-sources `frontend/dev-env.ps1` from the worktree root first (`. .\frontend\dev-env.ps1`) — Flutter is not on PATH otherwise. Windows + PowerShell.
- No Android emulator on this hardware — verification is golden-image tests only.
- No backend files touched. No new packages.

---

### Task 1: Demolition + new token foundation

Removes the old visual layer and replaces the tokens. The old theme, shared widgets, chat screen, gallery, and golden tests are mutually dependent — deleting the tokens alone would leave the project uncompilable, so they go together in one task.

**Files:**
- Delete: `lib/core/theme/app_colors.dart`, `app_typography.dart`, `app_spacing.dart`, `app_radius.dart`, `app_theme.dart`
- Delete: `lib/shared/widgets/app_primary_button.dart`, `app_chip.dart`, `loading_view.dart`, `error_view.dart`, `empty_view.dart`
- Delete: `lib/features/chat/chat_screen.dart`, `lib/features/chat/widgets/` (all three)
- Delete: `lib/features/gallery/gallery_screen.dart`
- Delete: `test/golden/gallery_golden_test.dart`, `test/golden/chat_screen_golden_test.dart`, `test/golden/goldens/*.png`
- Delete: `test/core/theme/app_colors_test.dart`, `app_theme_test.dart`, `test/shared/widgets/*`, `test/features/chat/chat_screen_test.dart`, `test/features/chat/widgets/*`
- Delete: `assets/fonts/Sora-Variable.ttf`, `Inter-Variable.ttf`, `IBMPlexMono-Regular.ttf`
- Create: `assets/fonts/Roboto-Variable.ttf`, `assets/fonts/RobotoMono-Variable.ttf` (downloaded)
- Create: `lib/core/theme/app_colors.dart`, `app_spacing.dart`, `app_radius.dart`, `app_typography.dart`, `app_theme.dart`
- Modify: `pubspec.yaml` (font declarations)
- Modify: `lib/core/router/app_router.dart` (point `/chat` and `/gallery` at temporary placeholders so the app still compiles)
- Modify: `test/widget_test.dart`, `test/core/router/app_router_test.dart` (update assertions for the placeholders)
- Keep untouched: `lib/shared/widgets/weather_icon.dart` (pure WMO-code logic), `lib/core/theme/theme_mode_provider.dart`, everything under `lib/data/`, `lib/core/network/`, `lib/core/env/`, `lib/core/geo.dart`, `lib/features/*/[a-z]*_controller.dart`

**Interfaces:**
- Produces: `AppColors` (static const fields per the constraint list, plus `alertSeverity`/`onAlertSeverity` carried over unchanged from the old file), `AppSpacing`, `AppRadius`, `AppTypography`, `AppTheme.dark` — consumed by every later task.

- [ ] **Step 1: Download the Roboto fonts**

```powershell
Invoke-WebRequest "https://raw.githubusercontent.com/google/fonts/main/ofl/roboto/Roboto%5Bwdth,wght%5D.ttf" -OutFile frontend\weathergpt_app\assets\fonts\Roboto-Variable.ttf
Invoke-WebRequest "https://raw.githubusercontent.com/google/fonts/main/ofl/robotomono/RobotoMono%5Bwght%5D.ttf" -OutFile frontend\weathergpt_app\assets\fonts\RobotoMono-Variable.ttf
Remove-Item frontend\weathergpt_app\assets\fonts\Sora-Variable.ttf, frontend\weathergpt_app\assets\fonts\Inter-Variable.ttf, frontend\weathergpt_app\assets\fonts\IBMPlexMono-Regular.ttf
Get-ChildItem frontend\weathergpt_app\assets\fonts\
```

Expected: `Roboto-Variable.ttf` ~489KB, `RobotoMono-Variable.ttf` ~184KB, and the three old fonts gone. (URLs verified live during planning — HTTP 200 with those byte sizes.)

Update `pubspec.yaml`'s `flutter.fonts` to exactly:

```yaml
  fonts:
    - family: Roboto
      fonts:
        - asset: assets/fonts/Roboto-Variable.ttf
    - family: RobotoMono
      fonts:
        - asset: assets/fonts/RobotoMono-Variable.ttf
```

- [ ] **Step 2: Delete the old visual layer**

Delete every file in the "Delete:" list above. After this the project will not compile — that is expected; Step 3 restores it.

- [ ] **Step 3: Write the new tokens**

`lib/core/theme/app_colors.dart`:

```dart
import 'package:flutter/material.dart';

/// Colours sampled directly from the reference screenshots in
/// backend/FrontendReference/ — see
/// docs/superpowers/specs/2026-09-09-flutter-design-literal.md §2.
/// These are measured values, not design choices; do not "improve" them.
class AppColors {
  AppColors._();

  /// Page and sidebar background. True black, as sampled.
  static const bgBase = Color(0xFF000000);

  /// The single raised-chrome colour: round icon buttons, the composer
  /// pill, dropdown menus, the attach menu. One colour for all of them.
  static const surfaceRaised = Color(0xFF212121);

  /// Inset surfaces that sit *below* the base — code blocks.
  static const surfaceInset = Color(0xFF131313);

  /// Small icon wells inside menus.
  static const surfaceIconWell = Color(0xFF454545);

  /// Hairlines and blockquote rules.
  static const divider = Color(0xFF434343);

  static const textPrimary = Color(0xFFFFFFFF);
  static const textSecondary = Color(0xFF9E9E9E);

  /// Accent: send/voice button, the sidebar "Chat" pill, links.
  static const accent = Color(0xFF3A83F6);

  /// User message bubble fill.
  static const userBubble = Color(0xFF133362);

  /// Account avatar circle.
  static const avatarFill = Color(0xFF7E8C8D);

  /// Destructive actions ("Delete"). Inferred rather than sampled — only
  /// anti-aliased edge pixels were recoverable from the reference.
  static const destructive = Color(0xFFEF4444);

  // Alert severity scale, carried over unchanged — keyed to the CAP
  // levels the backend's SACHET-sourced alerts use.
  static const _severityMinor = Color(0xFFF3D9AE);
  static const _severityModerate = Color(0xFFD98E2B);
  static const _severitySevere = Color(0xFFC23B4B);
  static const _severityExtreme = Color(0xFF8F2836);

  static Color alertSeverity(String? capSeverity) {
    switch (capSeverity?.toLowerCase()) {
      case 'minor':
        return _severityMinor;
      case 'moderate':
        return _severityModerate;
      case 'severe':
        return _severitySevere;
      case 'extreme':
        return _severityExtreme;
      default:
        return _severityModerate;
    }
  }

  /// Readable label colour for a severity chip, chosen by contrast ratio
  /// against that severity's own background.
  static Color onAlertSeverity(String? capSeverity) {
    final background = alertSeverity(capSeverity);
    final onDark = _contrastRatio(background, textPrimary);
    final onLight = _contrastRatio(background, bgBase);
    return onDark >= onLight ? textPrimary : bgBase;
  }

  static double _contrastRatio(Color a, Color b) {
    final la = a.computeLuminance();
    final lb = b.computeLuminance();
    final brighter = la > lb ? la : lb;
    final darker = la > lb ? lb : la;
    return (brighter + 0.05) / (darker + 0.05);
  }
}
```

`lib/core/theme/app_spacing.dart`:

```dart
/// 4dp grid. `screenMargin` is measured from the references (12dp side
/// margin for the floating chrome buttons); the rest is a conventional
/// scale built on the same grid.
class AppSpacing {
  AppSpacing._();

  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 20;
  static const double xxl = 24;
  static const double xxxl = 32;
  static const double huge = 48;

  /// Horizontal margin from the screen edge to floating chrome.
  static const double screenMargin = 12;
}
```

`lib/core/theme/app_radius.dart`:

```dart
/// Radii and fixed element sizes measured from the reference
/// screenshots — see the spec's §3 table.
class AppRadius {
  AppRadius._();

  /// Dropdown and attach menus.
  static const double menu = 16;

  /// User message bubbles.
  static const double bubble = 18;

  /// Glass panels on Home.
  static const double panel = 24;

  /// Code blocks.
  static const double codeBlock = 12;

  // --- Measured element sizes (not radii, but fixed by the reference) ---

  /// Every round chrome affordance: hamburger, new-chat, search,
  /// overflow, avatar. Uniform by design.
  static const double iconButton = 40;

  /// Composer pill height; it is fully rounded, so its radius is half.
  static const double composerHeight = 40;

  /// Dropdown menu width.
  static const double menuWidth = 191;

  /// User bubbles never exceed this fraction of the screen width.
  static const double bubbleMaxWidthFactor = 0.72;
}
```

`lib/core/theme/app_typography.dart`:

```dart
import 'package:flutter/material.dart';

/// Roboto, matching the Android reference screenshots (Roboto is
/// Android's system typeface, so this is the literal match rather than a
/// substitution). RobotoMono is used only for code blocks and raw
/// meteorological codes.
///
/// Sizes marked "approx" were estimated from the reference screenshots
/// rather than measured exactly, and should be tuned against the golden
/// images if they read wrong.
class AppTypography {
  AppTypography._();

  static const sans = 'Roboto';
  static const mono = 'RobotoMono';

  static TextStyle _sans(double size, FontWeight weight, Color color,
          {double? height}) =>
      TextStyle(
        fontFamily: sans,
        fontSize: size,
        fontWeight: weight,
        color: color,
        height: height,
      );

  /// Home hero temperature. Very large; approx.
  static TextStyle hero(Color color) =>
      _sans(112, FontWeight.w300, color, height: 1.0);

  /// Sidebar wordmark ("WeatherGPT"). Approx.
  static TextStyle wordmark(Color color) => _sans(28, FontWeight.w700, color);

  /// Screen titles, Home condition line. Approx.
  static TextStyle title(Color color) => _sans(20, FontWeight.w400, color);

  /// Chat message body, menu rows, composer text.
  static TextStyle body(Color color) =>
      _sans(16, FontWeight.w400, color, height: 1.45);

  /// Emphasised body (bold runs inside assistant messages).
  static TextStyle bodyBold(Color color) =>
      _sans(16, FontWeight.w700, color, height: 1.45);

  /// Section headers ("Pinned", "Recents"), timestamps, captions.
  static TextStyle label(Color color) => _sans(14, FontWeight.w400, color);

  /// Small supporting text under forecast rows.
  static TextStyle caption(Color color) => _sans(12, FontWeight.w400, color);

  /// Code blocks and raw meteorological codes.
  static TextStyle code(Color color) => TextStyle(
        fontFamily: mono,
        fontSize: 13,
        fontWeight: FontWeight.w400,
        height: 1.45,
        color: color,
      );
}
```

`lib/core/theme/app_theme.dart`:

```dart
import 'package:flutter/material.dart';
import 'app_colors.dart';
import 'app_radius.dart';
import 'app_typography.dart';

/// Dark-only for this build. Light mode is deliberately deferred, but
/// every token is resolved through this theme rather than hardcoded in
/// widgets, so adding a light palette later is additive.
class AppTheme {
  AppTheme._();

  static ThemeData get dark {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: AppColors.accent,
      brightness: Brightness.dark,
    ).copyWith(
      primary: AppColors.accent,
      onPrimary: AppColors.textPrimary,
      surface: AppColors.bgBase,
      onSurface: AppColors.textPrimary,
      surfaceContainerHighest: AppColors.surfaceRaised,
      outline: AppColors.divider,
      error: AppColors.destructive,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: AppColors.bgBase,
      canvasColor: AppColors.bgBase,
      fontFamily: AppTypography.sans,
      textTheme: TextTheme(
        displayLarge: AppTypography.hero(AppColors.textPrimary),
        headlineLarge: AppTypography.wordmark(AppColors.textPrimary),
        titleLarge: AppTypography.title(AppColors.textPrimary),
        bodyLarge: AppTypography.body(AppColors.textPrimary),
        bodyMedium: AppTypography.body(AppColors.textPrimary),
        labelLarge: AppTypography.label(AppColors.textSecondary),
        bodySmall: AppTypography.caption(AppColors.textSecondary),
      ),
      dividerColor: AppColors.divider,
      // Chrome floats directly on the background — no toolbar surface.
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: AppColors.surfaceRaised,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.menu),
        ),
      ),
      drawerTheme: const DrawerThemeData(
        backgroundColor: AppColors.bgBase,
        surfaceTintColor: Colors.transparent,
      ),
    );
  }
}
```

- [ ] **Step 4: Restore compilation with temporary placeholders**

Replace the `/chat` and `/gallery` route builders in `lib/core/router/app_router.dart` with the existing `PlaceholderScreen(title: ...)` (already in `lib/features/shell/placeholder_screen.dart`, kept), removing the now-deleted imports. Update `lib/main.dart` to use `theme: AppTheme.dark` and `themeMode: ThemeMode.dark` (the old light/dark pair no longer exists).

Update `test/widget_test.dart` and `test/core/router/app_router_test.dart` so their assertions match the placeholders (the old tests asserted on the deleted gallery's theme toggle and the chat screen's copy — those assertions go; keep the "boots to the Home tab" style navigation assertions, adjusted to whatever the placeholders now render).

- [ ] **Step 5: Verify and commit**

```powershell
. .\frontend\dev-env.ps1
cd frontend\weathergpt_app
flutter pub get
flutter analyze
flutter test
```

Expected: analyze clean; all remaining tests pass (the data-layer and controller tests are untouched and must still pass — if any of them fail, something outside the visual layer was deleted by mistake).

```bash
git add -A frontend/weathergpt_app
git commit -m "refactor: replace visual layer with sampled design tokens"
```

---

### Task 2: Sky gradient system

**Files:**
- Create: `lib/core/theme/sky_gradient.dart`
- Test: `test/core/theme/sky_gradient_test.dart`

**Interfaces:**
- Consumes: nothing (pure logic).
- Produces: `enum SkyTimeOfDay { dawn, day, dusk, night }`, `enum SkyCondition { clear, cloudy, fog, rain, snow, thunderstorm }`, `SkyTimeOfDay skyTimeOfDayFor(DateTime local)`, `SkyCondition skyConditionFor(int weatherCode)`, `LinearGradient skyGradient(SkyTimeOfDay time, SkyCondition condition)` — consumed by the Home screen in a later phase and by the gallery in Task 6.

Per spec §6.1: the Home background varies with time of day and conditions, not a fixed light sky. The sampled `Home1` values (`#C8D3E9` → `#7995C4` → `#93A8C7`) are the **day + cloudy** case and must be reproduced exactly; the other combinations follow the same structure (lighter top, saturated middle, lighter base) shifted in hue/value.

- [ ] **Step 1: Write the failing test**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weathergpt_app/core/theme/sky_gradient.dart';

void main() {
  group('skyTimeOfDayFor', () {
    test('classifies the day into dawn/day/dusk/night', () {
      expect(skyTimeOfDayFor(DateTime(2026, 9, 9, 5, 30)), SkyTimeOfDay.dawn);
      expect(skyTimeOfDayFor(DateTime(2026, 9, 9, 12, 0)), SkyTimeOfDay.day);
      expect(skyTimeOfDayFor(DateTime(2026, 9, 9, 18, 30)), SkyTimeOfDay.dusk);
      expect(skyTimeOfDayFor(DateTime(2026, 9, 9, 23, 0)), SkyTimeOfDay.night);
      expect(skyTimeOfDayFor(DateTime(2026, 9, 9, 2, 0)), SkyTimeOfDay.night);
    });
  });

  group('skyConditionFor', () {
    test('buckets WMO codes', () {
      expect(skyConditionFor(0), SkyCondition.clear);
      expect(skyConditionFor(2), SkyCondition.cloudy);
      expect(skyConditionFor(45), SkyCondition.fog);
      expect(skyConditionFor(63), SkyCondition.rain);
      expect(skyConditionFor(73), SkyCondition.snow);
      expect(skyConditionFor(95), SkyCondition.thunderstorm);
    });

    test('falls back to cloudy for an unrecognised code', () {
      expect(skyConditionFor(-1), SkyCondition.cloudy);
      expect(skyConditionFor(999), SkyCondition.cloudy);
    });
  });

  group('skyGradient', () {
    test('day+cloudy reproduces the sampled reference exactly', () {
      final gradient = skyGradient(SkyTimeOfDay.day, SkyCondition.cloudy);
      expect(gradient.colors.first, const Color(0xFFC8D3E9));
      expect(gradient.colors[1], const Color(0xFF7995C4));
      expect(gradient.colors.last, const Color(0xFF93A8C7));
    });

    test('every combination returns a usable multi-stop gradient', () {
      for (final time in SkyTimeOfDay.values) {
        for (final condition in SkyCondition.values) {
          final gradient = skyGradient(time, condition);
          expect(gradient.colors.length, greaterThanOrEqualTo(3),
              reason: '$time/$condition');
        }
      }
    });

    test('night gradients stay dark enough for white text', () {
      for (final condition in SkyCondition.values) {
        final gradient = skyGradient(SkyTimeOfDay.night, condition);
        for (final color in gradient.colors) {
          expect(color.computeLuminance(), lessThan(0.35),
              reason: 'night/$condition stop $color is too light for white text');
        }
      }
    });

    test('day gradients are lighter than their night counterparts', () {
      for (final condition in SkyCondition.values) {
        final day = skyGradient(SkyTimeOfDay.day, condition)
            .colors
            .map((c) => c.computeLuminance())
            .reduce((a, b) => a + b);
        final night = skyGradient(SkyTimeOfDay.night, condition)
            .colors
            .map((c) => c.computeLuminance())
            .reduce((a, b) => a + b);
        expect(day, greaterThan(night), reason: condition.toString());
      }
    });
  });
}
```

- [ ] **Step 2: Run it and confirm it fails**

```powershell
flutter test test\core\theme\sky_gradient_test.dart
```
Expected: FAIL — `sky_gradient.dart` doesn't exist.

- [ ] **Step 3: Implement**

Create `lib/core/theme/sky_gradient.dart`. Requirements the tests pin down:
- `skyTimeOfDayFor`: dawn 05:00–07:59, day 08:00–16:59, dusk 17:00–19:59, night 20:00–04:59.
- `skyConditionFor` buckets the WMO codes the same way `lib/shared/widgets/weather_icon.dart` already does — read that file and mirror its ranges rather than inventing new ones (0 clear; 1–2 cloudy; 3 cloudy; 45/48 fog; 51–57 and 61–67 and 80–82 rain; 71–77 and 85–86 snow; 95–99 thunderstorm; anything else cloudy).
- `skyGradient` returns a `LinearGradient` (`begin: Alignment.topCenter`, `end: Alignment.bottomCenter`) with at least three stops.
- **day+cloudy must be exactly** `#C8D3E9`, `#7995C4`, `#93A8C7` — the sampled reference.
- Night variants must have every stop below 0.35 luminance so white text stays readable.
- Day variants must be collectively lighter than their night counterparts.

Design the remaining combinations to match the reference's structure. Suggested approach: define one base triple per time-of-day, then apply a per-condition adjustment (desaturate for fog, darken and desaturate for rain/thunderstorm, brighten slightly for clear, cool for snow). Keep it readable — a `const` map of explicit triples is perfectly acceptable and easier to review than colour maths.

- [ ] **Step 4: Confirm the tests pass, then verify and commit**

```powershell
flutter test test\core\theme\sky_gradient_test.dart
flutter analyze
flutter test
```

```bash
git add frontend/weathergpt_app/lib/core/theme/sky_gradient.dart frontend/weathergpt_app/test/core/theme/sky_gradient_test.dart
git commit -m "feat: add time-of-day and condition driven sky gradients"
```

---

### Task 3: Chrome components

**Files:**
- Create: `lib/shared/widgets/round_icon_button.dart`
- Create: `lib/shared/widgets/glass_panel.dart`
- Test: `test/shared/widgets/round_icon_button_test.dart`
- Test: `test/shared/widgets/glass_panel_test.dart`

**Interfaces:**
- Consumes: `AppColors`, `AppRadius` (Task 1).
- Produces: `RoundIconButton({required IconData icon, required VoidCallback? onPressed, String? tooltip, Color? background})`, `GlassPanel({required Widget child, EdgeInsets? padding})` — consumed by every screen in later phases and by the gallery in Task 6.

Per spec §3, the round button is the single uniform chrome affordance: **40dp diameter, `surfaceRaised` fill**, used for hamburger / new-chat / search / overflow. Per spec §2.2, a glass panel is a **subtle** low-alpha white fill over a `BackdropFilter` blur — the reference panels are only 2–4% lighter than the sky behind them; a heavy frosted card is wrong.

- [ ] **Step 1: Write the failing tests**

```dart
// test/shared/widgets/round_icon_button_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weathergpt_app/core/theme/app_colors.dart';
import 'package:weathergpt_app/core/theme/app_radius.dart';
import 'package:weathergpt_app/shared/widgets/round_icon_button.dart';

void main() {
  testWidgets('is a 40dp circle filled with surfaceRaised', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RoundIconButton(icon: Icons.menu, onPressed: () {}),
        ),
      ),
    );

    final size = tester.getSize(find.byType(RoundIconButton));
    expect(size.width, AppRadius.iconButton);
    expect(size.height, AppRadius.iconButton);

    final decorated = tester.widgetList<Container>(find.byType(Container))
        .firstWhere((c) => c.decoration is BoxDecoration);
    final decoration = decorated.decoration as BoxDecoration;
    expect(decoration.shape, BoxShape.circle);
    expect(decoration.color, AppColors.surfaceRaised);
  });

  testWidgets('invokes onPressed when tapped', (tester) async {
    var tapped = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RoundIconButton(icon: Icons.menu, onPressed: () => tapped = true),
        ),
      ),
    );

    await tester.tap(find.byType(RoundIconButton));
    await tester.pump();

    expect(tapped, isTrue);
  });

  testWidgets('renders disabled when onPressed is null', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: RoundIconButton(icon: Icons.mic_none, onPressed: null)),
      ),
    );

    expect(tester.takeException(), isNull);
    await tester.tap(find.byType(RoundIconButton));
    await tester.pump();
    // No callback to assert; the test proves tapping a disabled button is inert.
  });
}
```

```dart
// test/shared/widgets/glass_panel_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weathergpt_app/shared/widgets/glass_panel.dart';

void main() {
  testWidgets('renders its child inside a blurred, rounded surface', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: GlassPanel(child: Text('forecast')),
        ),
      ),
    );

    expect(find.text('forecast'), findsOneWidget);
    expect(find.byType(BackdropFilter), findsOneWidget);
    expect(find.byType(ClipRRect), findsOneWidget);
  });

  testWidgets('its fill is a low-alpha white, not an opaque card', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: GlassPanel(child: Text('x')))),
    );

    final decorated = tester.widgetList<Container>(find.byType(Container))
        .firstWhere((c) => c.decoration is BoxDecoration);
    final color = (decorated.decoration as BoxDecoration).color!;
    expect(color.a, lessThan(0.25),
        reason: 'glass panels are a subtle overlay, not an opaque card');
  });
}
```

Note: `Color.a` (a 0.0-1.0 double) is the current accessor for a colour's alpha; if the analyzer on this Flutter version disagrees, use whatever it confirms is current (`.opacity` on older versions) rather than changing what the test asserts.

- [ ] **Step 2: Run them and confirm they fail**

```powershell
flutter test test\shared\widgets\round_icon_button_test.dart test\shared\widgets\glass_panel_test.dart
```

- [ ] **Step 3: Implement**

`RoundIconButton`: a 40dp `Container` with `BoxShape.circle` and `AppColors.surfaceRaised` (overridable via `background`), wrapping an `IconButton`/`InkWell` with the icon centred in `AppColors.textPrimary` (dimmed when `onPressed == null`), with `Tooltip` when `tooltip` is provided. Keep it exactly 40×40 — wrap in `SizedBox` so `tester.getSize` reports 40.

`GlassPanel`: `ClipRRect(borderRadius: AppRadius.panel)` → `BackdropFilter(ImageFilter.blur(sigmaX: 20, sigmaY: 20))` → `Container` with a low-alpha white fill (start at ~12% white, matching the reference's subtlety) and the same radius, with default padding of `AppSpacing.lg`.

- [ ] **Step 4: Confirm passing, verify, commit**

```powershell
flutter analyze
flutter test
```

```bash
git add frontend/weathergpt_app/lib/shared/widgets/round_icon_button.dart frontend/weathergpt_app/lib/shared/widgets/glass_panel.dart frontend/weathergpt_app/test/shared/widgets/
git commit -m "feat: add round icon button and glass panel chrome components"
```

---

### Task 4: Chat message components

**Files:**
- Create: `lib/features/chat/widgets/user_bubble.dart`
- Create: `lib/features/chat/widgets/assistant_message.dart`
- Create: `lib/features/chat/widgets/code_block.dart`
- Test: `test/features/chat/widgets/user_bubble_test.dart`
- Test: `test/features/chat/widgets/assistant_message_test.dart`
- Test: `test/features/chat/widgets/code_block_test.dart`

**Interfaces:**
- Consumes: `AppColors`, `AppRadius`, `AppSpacing`, `AppTypography` (Task 1).
- Produces: `UserBubble({required String text})`, `AssistantMessage({required String text, VoidCallback? onCopy, VoidCallback? onReadAloud, VoidCallback? onShare, VoidCallback? onMore})`, `CodeBlock({required String code, VoidCallback? onCopy})` — consumed by the chat screen in a later phase and the gallery in Task 6.

Per spec §4.2: the user turn is a right-aligned `#133362` bubble at 18dp radius, max 72% of screen width, 14dp right margin. The assistant turn has **no bubble** — white prose on the background, full width, with a row of small outline action icons beneath it (copy, read-aloud, share, overflow). Code blocks are `#131313` at 12dp radius with a copy affordance.

- [ ] **Step 1: Write the failing tests**

```dart
// test/features/chat/widgets/user_bubble_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weathergpt_app/core/theme/app_colors.dart';
import 'package:weathergpt_app/features/chat/widgets/user_bubble.dart';

void main() {
  testWidgets('renders its text in a userBubble-filled rounded container', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: UserBubble(text: 'hello'))),
    );

    expect(find.text('hello'), findsOneWidget);

    final decorated = tester.widgetList<Container>(find.byType(Container))
        .firstWhere((c) => c.decoration is BoxDecoration);
    final decoration = decorated.decoration as BoxDecoration;
    expect(decoration.color, AppColors.userBubble);
  });

  testWidgets('never exceeds 72% of the available width', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: UserBubble(
            text: 'a very long message that would otherwise span the entire '
                'width of the screen if it were not constrained by the '
                'bubble max width rule from the design spec',
          ),
        ),
      ),
    );

    final screenWidth = tester.view.physicalSize.width / tester.view.devicePixelRatio;
    final decorated = find.byType(Container).first;
    expect(tester.getSize(decorated).width, lessThanOrEqualTo(screenWidth * 0.72 + 1));
  });
}
```

```dart
// test/features/chat/widgets/assistant_message_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weathergpt_app/features/chat/widgets/assistant_message.dart';

void main() {
  testWidgets('renders prose with no bubble container behind it', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: AssistantMessage(text: 'It is sunny.'))),
    );

    expect(find.text('It is sunny.'), findsOneWidget);

    final decoratedContainers = tester
        .widgetList<Container>(find.byType(Container))
        .where((c) => c.decoration != null);
    expect(decoratedContainers, isEmpty,
        reason: 'assistant turns are flat prose, never boxed');
  });

  testWidgets('shows the action row and fires each callback', (tester) async {
    var copied = false, readAloud = false, shared = false, more = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AssistantMessage(
            text: 'reply',
            onCopy: () => copied = true,
            onReadAloud: () => readAloud = true,
            onShare: () => shared = true,
            onMore: () => more = true,
          ),
        ),
      ),
    );

    await tester.tap(find.byIcon(Icons.copy_outlined));
    await tester.tap(find.byIcon(Icons.volume_up_outlined));
    await tester.tap(find.byIcon(Icons.share_outlined));
    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pump();

    expect([copied, readAloud, shared, more], everyElement(isTrue));
  });

  testWidgets('hides the action row when no callbacks are supplied', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: AssistantMessage(text: 'reply'))),
    );

    expect(find.byIcon(Icons.copy_outlined), findsNothing);
  });
}
```

```dart
// test/features/chat/widgets/code_block_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weathergpt_app/core/theme/app_colors.dart';
import 'package:weathergpt_app/features/chat/widgets/code_block.dart';

void main() {
  testWidgets('renders code on a surfaceInset fill in a monospace face', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: CodeBlock(code: 'flutter test'))),
    );

    expect(find.text('flutter test'), findsOneWidget);

    final decorated = tester.widgetList<Container>(find.byType(Container))
        .firstWhere((c) => c.decoration is BoxDecoration);
    expect((decorated.decoration as BoxDecoration).color, AppColors.surfaceInset);

    final text = tester.widget<Text>(find.text('flutter test'));
    expect(text.style?.fontFamily, 'RobotoMono');
  });

  testWidgets('fires onCopy when the copy affordance is tapped', (tester) async {
    var copied = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: CodeBlock(code: 'x', onCopy: () => copied = true)),
      ),
    );

    await tester.tap(find.byIcon(Icons.copy_outlined));
    await tester.pump();

    expect(copied, isTrue);
  });
}
```

- [ ] **Step 2: Run and confirm they fail**

```powershell
flutter test test\features\chat\widgets
```

- [ ] **Step 3: Implement all three widgets**

Follow the spec's §4.2 exactly. Notes that the tests pin down:
- `UserBubble` is right-aligned, wrapped in a `ConstrainedBox` at `AppRadius.bubbleMaxWidthFactor` of the available width, `AppRadius.bubble` radius, `AppColors.userBubble` fill, `AppColors.textPrimary` text, `AppSpacing.md`/`sm` internal padding, `AppSpacing.md` right margin.
- `AssistantMessage` must have **no decorated `Container`** anywhere in its tree — plain `Text` at full width plus the action row. The action row only renders if at least one callback is non-null; icons are `copy_outlined`, `volume_up_outlined`, `share_outlined`, `more_vert`, sized small (~20dp) in `AppColors.textSecondary`.
- `CodeBlock` uses `AppColors.surfaceInset`, `AppRadius.codeBlock`, `AppTypography.code`, with the copy icon top-right.

- [ ] **Step 4: Confirm passing, verify, commit**

```powershell
flutter analyze
flutter test
```

```bash
git add frontend/weathergpt_app/lib/features/chat/widgets/ frontend/weathergpt_app/test/features/chat/widgets/
git commit -m "feat: add user bubble, assistant message, and code block components"
```

---

### Task 5: Menu component

**Files:**
- Create: `lib/shared/widgets/app_menu.dart`
- Test: `test/shared/widgets/app_menu_test.dart`

**Interfaces:**
- Consumes: `AppColors`, `AppRadius`, `AppSpacing`, `AppTypography` (Task 1).
- Produces: `AppMenuItem({required IconData icon, required String label, required VoidCallback onTap, bool destructive = false, bool iconWell = false})` and `Future<void> showAppMenu({required BuildContext context, required List<AppMenuItem> items, String? header, RelativeRect? position})` — consumed by the chat/home overflow menus and the composer's attach menu in later phases, and by the gallery in Task 6.

One component serves both reference menus: the overflow dropdown (§4.4 — plain icon + label rows, 191dp wide, header line, red Delete last) and the attach menu (§4.5 — same shell, but each row's icon sits in a `#454545` circular well). The `iconWell` flag is the only difference.

- [ ] **Step 1: Write the failing test**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weathergpt_app/core/theme/app_colors.dart';
import 'package:weathergpt_app/shared/widgets/app_menu.dart';

void main() {
  Widget harness(List<AppMenuItem> items, {String? header}) {
    return MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () => showAppMenu(context: context, items: items, header: header),
            child: const Text('open'),
          ),
        ),
      ),
    );
  }

  testWidgets('shows each item and fires its callback', (tester) async {
    var shared = false;
    await tester.pumpWidget(harness([
      AppMenuItem(icon: Icons.share_outlined, label: 'Share', onTap: () => shared = true),
      AppMenuItem(icon: Icons.push_pin_outlined, label: 'Pin', onTap: () {}),
    ]));

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('Share'), findsOneWidget);
    expect(find.text('Pin'), findsOneWidget);

    await tester.tap(find.text('Share'));
    await tester.pumpAndSettle();

    expect(shared, isTrue);
  });

  testWidgets('renders a destructive item in the destructive colour', (tester) async {
    await tester.pumpWidget(harness([
      AppMenuItem(
        icon: Icons.delete_outline,
        label: 'Delete',
        onTap: () {},
        destructive: true,
      ),
    ]));

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    final label = tester.widget<Text>(find.text('Delete'));
    expect(label.style?.color, AppColors.destructive);
  });

  testWidgets('renders an optional header above the items', (tester) async {
    await tester.pumpWidget(harness(
      [AppMenuItem(icon: Icons.share_outlined, label: 'Share', onTap: () {})],
      header: 'Model Selection Strategy',
    ));

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('Model Selection Strategy'), findsOneWidget);
  });

  testWidgets('iconWell items wrap their icon in a filled circle', (tester) async {
    await tester.pumpWidget(harness([
      AppMenuItem(
        icon: Icons.photo_camera_outlined,
        label: 'Camera',
        onTap: () {},
        iconWell: true,
      ),
    ]));

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    final well = tester.widgetList<Container>(find.byType(Container)).firstWhere(
        (c) =>
            c.decoration is BoxDecoration &&
            (c.decoration as BoxDecoration).color == AppColors.surfaceIconWell);
    expect((well.decoration as BoxDecoration).shape, BoxShape.circle);
  });
}
```

- [ ] **Step 2: Run and confirm it fails**

```powershell
flutter test test\shared\widgets\app_menu_test.dart
```

- [ ] **Step 3: Implement**

Build on Flutter's own overlay/menu machinery (`showMenu` with a custom `shape`/`color`, or a `PopupRoute` if `showMenu`'s row layout fights the spec). Requirements: `AppColors.surfaceRaised` fill, `AppRadius.menu` radius, `AppRadius.menuWidth` width, `AppTypography.body` labels in `textPrimary` (or `destructive`), optional header line in `AppTypography.label`/`textSecondary`, and `iconWell` rows wrapping the icon in a 40dp `surfaceIconWell` circle.

- [ ] **Step 4: Confirm passing, verify, commit**

```powershell
flutter analyze
flutter test
```

```bash
git add frontend/weathergpt_app/lib/shared/widgets/app_menu.dart frontend/weathergpt_app/test/shared/widgets/app_menu_test.dart
git commit -m "feat: add shared menu component for overflow and attach menus"
```

---

### Task 6: Component gallery and goldens

**Files:**
- Create: `lib/features/gallery/gallery_screen.dart`
- Create: `test/golden/gallery_golden_test.dart`
- Create (generated): `test/golden/goldens/gallery_chrome.png`, `test/golden/goldens/gallery_sky.png`
- Modify: `lib/core/router/app_router.dart` (point `/gallery` at the real gallery again)

**Interfaces:**
- Consumes: every component from Tasks 1-5.
- Produces: the gallery screen and its goldens — the visual artefact the controller reviews before this phase is considered done.

- [ ] **Step 1: Build the gallery**

A scrollable dev-only screen on `AppColors.bgBase` showing, with a `textSecondary` label above each group:
- **Type scale** — one line per `AppTypography` style, each labelled.
- **Chrome** — a row of `RoundIconButton`s (menu, add, search, more_vert) and one disabled.
- **Chat** — a `UserBubble`, an `AssistantMessage` with all four actions, and a `CodeBlock`.
- **Menus** — buttons that open the overflow menu (Share/Pin/Find in chat/Archive/Delete-destructive, with a header) and the attach menu (Camera/Photos/Files with `iconWell: true`).
- **Sky + glass** — a `SizedBox` (~200dp tall) for each of several `skyGradient` combinations (at minimum day+cloudy, night+clear, dusk+rain), each containing a `GlassPanel` with sample forecast-ish content, so the glass treatment is visible against real backgrounds.

- [ ] **Step 2: Write the golden test**

Two goldens (one screen would be too tall to read):
- `gallery_chrome.png` — type scale, chrome, chat, menus sections.
- `gallery_sky.png` — the sky + glass section.

Reuse the `FontLoader` `setUpAll` pattern from the golden test deleted in Task 1 — recover it from git history (`git show HEAD~n:frontend/weathergpt_app/test/golden/gallery_golden_test.dart`) rather than rewriting it, adapting the font paths to `Roboto-Variable.ttf` / `RobotoMono-Variable.ttf` and the family names to `Roboto` / `RobotoMono`. Also load `MaterialIcons` as that file did, so icons render as glyphs rather than tofu.

Use the same `tester.view.physicalSize` / `devicePixelRatio` approach the old test used. Pump enough duration for any animation to settle, and **never** use `pumpAndSettle()` if a repeating animation is on screen.

- [ ] **Step 3: Generate and verify determinism**

```powershell
flutter test --update-goldens test\golden\gallery_golden_test.dart
flutter test test\golden\gallery_golden_test.dart
```

The second run must pass **without** `--update-goldens`. If it doesn't, the gallery contains something non-deterministic — fix it before proceeding and report what it was.

- [ ] **Step 4: Full verification and commit**

```powershell
flutter analyze
flutter test
```

```bash
git add frontend/weathergpt_app/lib/features/gallery/ frontend/weathergpt_app/lib/core/router/app_router.dart frontend/weathergpt_app/test/golden/
git commit -m "feat: add component gallery with golden coverage"
```

---

## Execution

Ready for **subagent-driven-development**: fresh implementer per task, task review after each, final whole-branch review at the end. The controller inspects both generated golden PNGs by eye before the phase is considered complete.
