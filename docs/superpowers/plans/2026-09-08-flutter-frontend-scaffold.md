# Flutter Frontend Scaffold (Phase 0) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Stand up the WeatherGPT Flutter project's scaffold, design tokens, core networking, shared widget library, and navigation shell, ending in a component gallery screen that proves every token and widget renders correctly in both light and dark mode.

**Architecture:** A new `frontend/weathergpt_app/` Flutter project (Android/web/Windows targets only), organized as `lib/core/` (theme, env, network, router), `lib/shared/widgets/` (reusable UI), and `lib/features/` (screens — placeholders in this phase, real screens in later phases). No backend files are touched.

**Tech Stack:** Flutter stable (3.47.2, already verified installed), `flutter_riverpod`, `go_router`, `dio`, `web_socket_channel`. No code-gen (no `freezed`/`json_serializable`/`build_runner`), no `google_fonts` runtime package, no `fl_chart` yet (unused until Phase 3).

**Spec:** `docs/superpowers/specs/2026-09-08-flutter-frontend-design.md` (frontend design spec; companion to `docs/superpowers/specs/2026-09-05-weathergpt-v1-design.md`, the backend spec).

This plan covers **only Phase 0** of the frontend spec's §11 rollout (scaffold + core infra). Phase 1 (Home), Phase 2 (Chat), and Phase 3 (remaining screens) are separate future plans.

## Global Constraints

- **Environment setup is required before any `flutter`/`dart`/`adb`/`emulator`/`gradle` command.** Task 1's first step creates `frontend/dev-env.ps1`; every later shell command in this plan assumes it has been dot-sourced first (`. .\frontend\dev-env.ps1` from the repo root). It sets `JAVA_HOME`, `ANDROID_SDK_ROOT`, `ANDROID_HOME`, and prepends Flutter/Android tool directories to `PATH` — without it, `flutter`/`adb`/`emulator`/`sdkmanager` are not found, and `gradle` (invoked transitively by `flutter build`/`run`) fails to find a JDK 17+.
- Flutter/Android/Dart commands are pre-allowed in `C:\skyfall\.claude\settings.local.json` — no permission prompts should interrupt execution.
- An Android emulator AVD `WeatherGPT_Pixel6` (Pixel 6 profile, API 35, 1080×2400 @420dpi) already exists and has been boot-verified. Use it for any visual verification step.
- No backend files (anything under `backend/`) are touched by this plan.
- No `google_fonts` package (runtime font fetching) — fonts are bundled `.ttf` assets.
- No `freezed`, `json_serializable`, or `build_runner`.
- No `fl_chart` dependency yet — nothing in this phase renders a chart (YAGNI; added in the Phase 3 plan).
- This phase ends at a component gallery, not a real screen. Home, Chat, Forecast, and the advisory screens are explicitly out of scope here.

---

### Task 1: Project scaffold, lint config, and dev environment script

**Files:**
- Create: `frontend/dev-env.ps1`
- Create: `frontend/weathergpt_app/` (via `flutter create`)
- Modify: `frontend/weathergpt_app/analysis_options.yaml`
- Modify: `frontend/weathergpt_app/lib/main.dart`
- Modify: `frontend/weathergpt_app/test/widget_test.dart`

**Interfaces:**
- Produces: the `weathergpt_app` Flutter project itself (package name `weathergpt_app`, used in every later task's `import 'package:weathergpt_app/...'`), and `frontend/dev-env.ps1` (dot-sourced by every later task's shell commands).

- [ ] **Step 1: Create the dev environment script**

Create `frontend/dev-env.ps1`:

```powershell
# Dot-source this before any flutter/dart/adb/emulator/gradle command:
#   . .\frontend\dev-env.ps1
# Sets up PATH and the JDK Flutter's Android toolchain needs. Without this,
# a fresh PowerShell/Bash session on this machine does not have flutter,
# adb, emulator, sdkmanager, or a JDK 17+ on PATH.

$env:JAVA_HOME = "C:\Program Files\Android\Android Studio\jbr"
$env:ANDROID_SDK_ROOT = "C:\Users\ACER\AppData\Local\Android\Sdk"
$env:ANDROID_HOME = "C:\Users\ACER\AppData\Local\Android\Sdk"
$env:Path = "$env:JAVA_HOME\bin;C:\src\flutter\bin;$env:ANDROID_SDK_ROOT\platform-tools;$env:ANDROID_SDK_ROOT\emulator;$env:ANDROID_SDK_ROOT\cmdline-tools\latest\bin;" + $env:Path
```

- [ ] **Step 2: Create the Flutter project**

Run from the repo root:

```powershell
. .\frontend\dev-env.ps1
flutter create --platforms=android,web,windows --org com.weathergpt --project-name weathergpt_app frontend\weathergpt_app
```

- [ ] **Step 3: Verify the bare scaffold is clean**

```powershell
. .\frontend\dev-env.ps1
cd frontend\weathergpt_app
flutter analyze
flutter test
```

Expected: `flutter analyze` reports "No issues found!", `flutter test` passes the generated counter-app test.

- [ ] **Step 4: Strip the counter-app boilerplate**

Replace the full contents of `frontend/weathergpt_app/lib/main.dart` with:

```dart
import 'package:flutter/material.dart';

void main() {
  runApp(const WeatherGptApp());
}

class WeatherGptApp extends StatelessWidget {
  const WeatherGptApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      home: Scaffold(
        body: Center(child: Text('WeatherGPT')),
      ),
    );
  }
}
```

Replace the full contents of `frontend/weathergpt_app/test/widget_test.dart` with:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weathergpt_app/main.dart';

void main() {
  testWidgets('WeatherGptApp renders without crashing', (tester) async {
    await tester.pumpWidget(const WeatherGptApp());
    expect(find.text('WeatherGPT'), findsOneWidget);
  });
}
```

(This placeholder app and test are both replaced in Task 7 once the real router and theme exist.)

- [ ] **Step 5: Tighten lints**

`flutter create` already generates `analysis_options.yaml` with `include: package:flutter_lints/flutter.yaml` and adds `flutter_lints` to `dev_dependencies`. Open `frontend/weathergpt_app/analysis_options.yaml` and add an explicit `linter: rules:` block (this is a hackathon judged partly on code quality, so a few rules beyond the default are worth the cost):

```yaml
include: package:flutter_lints/flutter.yaml

linter:
  rules:
    always_declare_return_types: true
    avoid_print: true
    prefer_const_constructors: true
    prefer_const_literals_to_create_immutables: true
    unawaited_futures: true
```

- [ ] **Step 6: Re-verify**

```powershell
. .\frontend\dev-env.ps1
cd frontend\weathergpt_app
flutter analyze
flutter test
```

Expected: both clean/passing.

- [ ] **Step 7: Commit**

```bash
git add frontend/
git commit -m "feat: scaffold weathergpt_app Flutter project"
```

---

### Task 2: Dependencies and bundled fonts

**Files:**
- Modify: `frontend/weathergpt_app/pubspec.yaml`
- Create: `frontend/weathergpt_app/assets/fonts/Sora-Variable.ttf`
- Create: `frontend/weathergpt_app/assets/fonts/Inter-Variable.ttf`
- Create: `frontend/weathergpt_app/assets/fonts/IBMPlexMono-Regular.ttf`

**Interfaces:**
- Consumes: the project created in Task 1.
- Produces: the `flutter_riverpod`, `go_router`, `dio`, `web_socket_channel` dependencies and the `Sora`, `Inter`, `IBMPlexMono` font families, both used starting in Task 3.

- [ ] **Step 1: Add dependencies**

```powershell
. .\frontend\dev-env.ps1
cd frontend\weathergpt_app
flutter pub add flutter_riverpod go_router dio web_socket_channel
```

This edits `pubspec.yaml` automatically with current compatible version constraints.

- [ ] **Step 2: Download the font assets**

These exact URLs were verified live (HTTP 200, real font bytes) during planning — Sora and Inter are published as single variable-font files (one file spans the whole weight axis), IBM Plex Mono as a static per-weight file:

```powershell
mkdir frontend\weathergpt_app\assets\fonts -Force
Invoke-WebRequest "https://raw.githubusercontent.com/google/fonts/main/ofl/sora/Sora%5Bwght%5D.ttf" -OutFile frontend\weathergpt_app\assets\fonts\Sora-Variable.ttf
Invoke-WebRequest "https://raw.githubusercontent.com/google/fonts/main/ofl/inter/Inter%5Bopsz,wght%5D.ttf" -OutFile frontend\weathergpt_app\assets\fonts\Inter-Variable.ttf
Invoke-WebRequest "https://raw.githubusercontent.com/google/fonts/main/ofl/ibmplexmono/IBMPlexMono-Regular.ttf" -OutFile frontend\weathergpt_app\assets\fonts\IBMPlexMono-Regular.ttf
```

Verify all three downloaded with non-trivial size (not an HTML error page):

```powershell
Get-ChildItem frontend\weathergpt_app\assets\fonts\*.ttf | Select-Object Name, Length
```

Expected: `Sora-Variable.ttf` ~111KB, `Inter-Variable.ttf` ~857KB, `IBMPlexMono-Regular.ttf` ~132KB. All three under OFL license (`OFL.txt` accompanies each family in the source repo — no additional attribution file is required in the app itself, but note the license in a code comment in Task 3's typography file).

- [ ] **Step 3: Declare the fonts in pubspec.yaml**

`frontend/weathergpt_app/pubspec.yaml` already has a `flutter:` section (with `uses-material-design: true`) from `flutter create`. Add a `fonts:` key inside that existing section (do not create a second `flutter:` key):

```yaml
flutter:
  uses-material-design: true

  fonts:
    - family: Sora
      fonts:
        - asset: assets/fonts/Sora-Variable.ttf
    - family: Inter
      fonts:
        - asset: assets/fonts/Inter-Variable.ttf
    - family: IBMPlexMono
      fonts:
        - asset: assets/fonts/IBMPlexMono-Regular.ttf
          weight: 400
```

- [ ] **Step 4: Verify**

```powershell
. .\frontend\dev-env.ps1
cd frontend\weathergpt_app
flutter pub get
flutter analyze
flutter test
```

Expected: `pub get` succeeds, analyze/test still clean (nothing references the new fonts yet).

- [ ] **Step 5: Commit**

```bash
git add frontend/weathergpt_app/pubspec.yaml frontend/weathergpt_app/pubspec.lock frontend/weathergpt_app/assets/
git commit -m "feat: add core dependencies and bundle Sora/Inter/IBM Plex Mono fonts"
```

---

### Task 3: Design tokens and theme

**Files:**
- Create: `frontend/weathergpt_app/lib/core/theme/app_colors.dart`
- Create: `frontend/weathergpt_app/lib/core/theme/app_typography.dart`
- Create: `frontend/weathergpt_app/lib/core/theme/app_spacing.dart`
- Create: `frontend/weathergpt_app/lib/core/theme/app_radius.dart`
- Create: `frontend/weathergpt_app/lib/core/theme/app_theme.dart`
- Test: `frontend/weathergpt_app/test/core/theme/app_colors_test.dart`
- Test: `frontend/weathergpt_app/test/core/theme/app_theme_test.dart`

**Interfaces:**
- Consumes: the `Sora`/`Inter`/`IBMPlexMono` font families declared in Task 2.
- Produces: `AppColors` (static const colors + `AppColors.alertSeverity(String? capSeverity) -> Color`), `AppTypography` (static `TextStyle` builder methods: `display`, `headline`, `title`, `bodyLarge`, `body`, `caption`, `code`, each taking a `Color`), `AppSpacing` (static const doubles: `xs, sm, md, lg, xl, xxl, xxxl, huge`), `AppRadius` (static const doubles: `control, surface, sheet`), `AppTheme.light` / `AppTheme.dark` (`ThemeData` getters) — all consumed starting in Task 5 (widgets) and Task 6/7 (app wiring).

- [ ] **Step 1: Write the failing tests**

Create `frontend/weathergpt_app/test/core/theme/app_colors_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weathergpt_app/core/theme/app_colors.dart';

void main() {
  test('alertSeverity maps known CAP levels to their colors', () {
    expect(AppColors.alertSeverity('Extreme'), const Color(0xFF8F2836));
    expect(AppColors.alertSeverity('severe'), const Color(0xFFC23B4B));
    expect(AppColors.alertSeverity('MODERATE'), const Color(0xFFD98E2B));
    expect(AppColors.alertSeverity('minor'), const Color(0xFFF3D9AE));
  });

  test('alertSeverity falls back to Moderate for an unrecognized or missing value', () {
    expect(AppColors.alertSeverity('Unknown'), const Color(0xFFD98E2B));
    expect(AppColors.alertSeverity(null), const Color(0xFFD98E2B));
  });
}
```

Create `frontend/weathergpt_app/test/core/theme/app_theme_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weathergpt_app/core/theme/app_theme.dart';

void main() {
  test('light theme uses Material 3 and the Cloudlight background', () {
    final theme = AppTheme.light;
    expect(theme.useMaterial3, isTrue);
    expect(theme.brightness, Brightness.light);
    expect(theme.scaffoldBackgroundColor, const Color(0xFFF5F6F4));
  });

  test('dark theme uses Material 3 and the Monsoon Ink background', () {
    final theme = AppTheme.dark;
    expect(theme.useMaterial3, isTrue);
    expect(theme.brightness, Brightness.dark);
    expect(theme.scaffoldBackgroundColor, const Color(0xFF171B2E));
  });
}
```

- [ ] **Step 2: Run the tests to verify they fail**

```powershell
. .\frontend\dev-env.ps1
cd frontend\weathergpt_app
flutter test test\core\theme
```

Expected: FAIL — `app_colors.dart`/`app_theme.dart` don't exist yet.

- [ ] **Step 3: Implement the tokens**

Create `frontend/weathergpt_app/lib/core/theme/app_spacing.dart`:

```dart
/// 4px-base spacing scale. See
/// docs/superpowers/specs/2026-09-08-flutter-frontend-design.md.
class AppSpacing {
  AppSpacing._();

  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
  static const double xxl = 32;
  static const double xxxl = 48;
  static const double huge = 64;
}
```

Create `frontend/weathergpt_app/lib/core/theme/app_radius.dart`:

```dart
/// Corner-radius scale with real hierarchy — small interactive controls
/// get a tighter radius than large surfaces, deliberately avoiding one
/// radius value applied to everything regardless of size.
class AppRadius {
  AppRadius._();

  static const double control = 4;
  static const double surface = 12;
  static const double sheet = 20;
}
```

Create `frontend/weathergpt_app/lib/core/theme/app_colors.dart`:

```dart
import 'package:flutter/material.dart';

/// WeatherGPT's "Monsoon Sky" palette — see
/// docs/superpowers/specs/2026-09-08-flutter-frontend-design.md for the
/// rationale behind each color.
class AppColors {
  AppColors._();

  // Core palette
  static const monsoonInk = Color(0xFF171B2E);
  static const stormSlate = Color(0xFF2B3358);
  static const cloudlight = Color(0xFFF5F6F4);
  static const marigold = Color(0xFFE8A33D);
  static const paddyGreen = Color(0xFF3F8F6B);
  static const alertCrimson = Color(0xFFC23B4B);

  // Text hierarchy
  static const lightTextPrimary = Color(0xFF1B2340);
  static const lightTextSecondary = Color(0xFF5B6178);
  static const darkTextPrimary = Color(0xFFEDEEF2);
  static const darkTextSecondary = Color(0xFF9DA3C2);

  // Alert severity scale, keyed to the CAP protocol levels the backend's
  // SACHET-sourced alerts already use (Minor/Moderate/Severe/Extreme).
  static const _severityMinor = Color(0xFFF3D9AE);
  static const _severityModerate = Color(0xFFD98E2B);
  static const _severitySevere = alertCrimson;
  static const _severityExtreme = Color(0xFF8F2836);

  /// Maps a CAP severity string (as returned by the backend's alert
  /// endpoints) to its display color. An unrecognized value — a typo, a
  /// new level a future feed change introduces — falls back to
  /// [_severityModerate] rather than throwing; a malformed severity
  /// string must never crash the alerts screen.
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
}
```

Create `frontend/weathergpt_app/lib/core/theme/app_typography.dart`:

```dart
import 'package:flutter/material.dart';

/// WeatherGPT's type scale: Sora for display/headline/title, Inter for
/// body/UI text, IBMPlexMono for raw meteorological codes (METAR
/// strings, coordinates) only — never as a general UI/label font.
///
/// Sora and Inter ship as OFL-licensed variable fonts (one file spans a
/// weight axis) — [FontVariation] selects the weight instance;
/// [FontWeight] alone only distinguishes a font's registered STATIC
/// weights and would not pick the right instance out of a single
/// variable-font file.
class AppTypography {
  AppTypography._();

  static const _sora = 'Sora';
  static const _inter = 'Inter';
  static const _mono = 'IBMPlexMono';

  static TextStyle display(Color color) => TextStyle(
        fontFamily: _sora,
        fontVariations: const [FontVariation('wght', 600)],
        fontSize: 40,
        height: 44 / 40,
        color: color,
      );

  static TextStyle headline(Color color) => TextStyle(
        fontFamily: _sora,
        fontVariations: const [FontVariation('wght', 600)],
        fontSize: 24,
        height: 30 / 24,
        color: color,
      );

  static TextStyle title(Color color) => TextStyle(
        fontFamily: _sora,
        fontVariations: const [FontVariation('wght', 500)],
        fontSize: 18,
        height: 24 / 18,
        color: color,
      );

  static TextStyle bodyLarge(Color color) => TextStyle(
        fontFamily: _inter,
        fontVariations: const [FontVariation('wght', 400)],
        fontSize: 16,
        height: 24 / 16,
        color: color,
      );

  static TextStyle body(Color color) => TextStyle(
        fontFamily: _inter,
        fontVariations: const [FontVariation('wght', 400)],
        fontSize: 14,
        height: 20 / 14,
        color: color,
      );

  static TextStyle caption(Color color) => TextStyle(
        fontFamily: _inter,
        fontVariations: const [FontVariation('wght', 500)],
        fontSize: 12,
        height: 16 / 12,
        color: color,
      );

  static TextStyle code(Color color) => TextStyle(
        fontFamily: _mono,
        fontWeight: FontWeight.w400,
        fontSize: 13,
        height: 18 / 13,
        color: color,
      );
}
```

Create `frontend/weathergpt_app/lib/core/theme/app_theme.dart`:

```dart
import 'package:flutter/material.dart';
import 'app_colors.dart';
import 'app_radius.dart';
import 'app_typography.dart';

/// Builds the app's light and dark [ThemeData]. Tonal elevation
/// (Material 3's surface-tint model) is the primary elevation cue; real
/// drop shadows are reserved for genuinely floating surfaces (dialogs,
/// bottom sheets) rather than applied per-card — hence `cardTheme`
/// below sets elevation to 0 and relies on a surface-color shift alone.
class AppTheme {
  AppTheme._();

  static ThemeData get light => _build(
        brightness: Brightness.light,
        background: AppColors.cloudlight,
        surface: Colors.white,
        textPrimary: AppColors.lightTextPrimary,
        textSecondary: AppColors.lightTextSecondary,
      );

  static ThemeData get dark => _build(
        brightness: Brightness.dark,
        background: AppColors.monsoonInk,
        surface: AppColors.stormSlate,
        textPrimary: AppColors.darkTextPrimary,
        textSecondary: AppColors.darkTextSecondary,
      );

  static ThemeData _build({
    required Brightness brightness,
    required Color background,
    required Color surface,
    required Color textPrimary,
    required Color textSecondary,
  }) {
    // fromSeed().copyWith(...) rather than ColorScheme(...) directly —
    // it fills in every Material 3 role Flutter's algorithm expects,
    // and copyWith only overrides the specific roles this palette cares
    // about, so this doesn't depend on knowing ColorScheme's full
    // constructor signature for the pinned Flutter version.
    final colorScheme = ColorScheme.fromSeed(
      seedColor: AppColors.marigold,
      brightness: brightness,
    ).copyWith(
      primary: AppColors.marigold,
      onPrimary: AppColors.monsoonInk,
      secondary: AppColors.paddyGreen,
      onSecondary: Colors.white,
      error: AppColors.alertCrimson,
      onError: Colors.white,
      surface: surface,
      onSurface: textPrimary,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: background,
      fontFamily: 'Inter',
      textTheme: TextTheme(
        displayLarge: AppTypography.display(textPrimary),
        headlineMedium: AppTypography.headline(textPrimary),
        titleMedium: AppTypography.title(textPrimary),
        bodyLarge: AppTypography.bodyLarge(textPrimary),
        bodyMedium: AppTypography.body(textPrimary),
        bodySmall: AppTypography.caption(textSecondary),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.surface),
        ),
      ),
      chipTheme: ChipThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.control),
        ),
      ),
    );
  }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

```powershell
. .\frontend\dev-env.ps1
cd frontend\weathergpt_app
flutter test test\core\theme
```

Expected: PASS. If `CardThemeData` is not the correct type name for the installed Flutter version, `flutter analyze`/`flutter test` will report the real type to use instead (e.g. `CardTheme`) — fix the type name accordingly; this is a mechanical fix, not a design change.

- [ ] **Step 5: Full verification**

```powershell
flutter analyze
flutter test
```

- [ ] **Step 6: Commit**

```bash
git add frontend/weathergpt_app/lib/core/theme/ frontend/weathergpt_app/test/core/theme/
git commit -m "feat: add Monsoon Sky design tokens and Material 3 theme"
```

---

### Task 4: Environment config and network client

**Files:**
- Create: `frontend/weathergpt_app/lib/core/env/app_env.dart`
- Create: `frontend/weathergpt_app/lib/core/network/app_error.dart`
- Create: `frontend/weathergpt_app/lib/core/network/api_client.dart`
- Test: `frontend/weathergpt_app/test/core/network/api_client_test.dart`

**Interfaces:**
- Produces: `AppEnv.apiBaseUrl` (`String`), `AppError` (sealed class) with subtypes `NetworkTimeoutError`, `NetworkConnectionError`, `ServerError(int statusCode)`, `UnknownError(String message)`; `buildApiClient({String? baseUrl}) -> Dio`; `mapDioException(DioException) -> AppError`. None of these are consumed elsewhere in this phase — no screen makes a real API call yet — they're built now because Phase 1's Home screen is the first consumer and the interceptor's error-mapping behavior needs its own test coverage regardless of when a caller arrives.

- [ ] **Step 1: Write the failing tests**

Create `frontend/weathergpt_app/test/core/network/api_client_test.dart`:

```dart
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weathergpt_app/core/network/api_client.dart';
import 'package:weathergpt_app/core/network/app_error.dart';

void main() {
  final requestOptions = RequestOptions(path: '/weather');

  test('maps a connection timeout to NetworkTimeoutError', () {
    final err = DioException(
      requestOptions: requestOptions,
      type: DioExceptionType.connectionTimeout,
    );
    expect(mapDioException(err), isA<NetworkTimeoutError>());
  });

  test('maps a 500 response to ServerError with the status code', () {
    final err = DioException(
      requestOptions: requestOptions,
      type: DioExceptionType.badResponse,
      response: Response(requestOptions: requestOptions, statusCode: 500),
    );
    final mapped = mapDioException(err);
    expect(mapped, isA<ServerError>());
    expect((mapped as ServerError).statusCode, 500);
  });

  test('maps a connection error to NetworkConnectionError', () {
    final err = DioException(
      requestOptions: requestOptions,
      type: DioExceptionType.connectionError,
    );
    expect(mapDioException(err), isA<NetworkConnectionError>());
  });
}
```

(Testing `mapDioException` directly, against manually constructed `DioException` values, exercises the real mapping logic without needing an HTTP-mocking dependency or a live network call — `DioException` objects don't require an actual request to construct.)

- [ ] **Step 2: Run the tests to verify they fail**

```powershell
. .\frontend\dev-env.ps1
cd frontend\weathergpt_app
flutter test test\core\network
```

Expected: FAIL — `api_client.dart`/`app_error.dart` don't exist yet.

- [ ] **Step 3: Implement**

Create `frontend/weathergpt_app/lib/core/env/app_env.dart`:

```dart
/// Backend base URL, supplied at build/run time via
/// `--dart-define=API_BASE_URL=<url>`.
///
/// Defaults to `http://10.0.2.2:8000` — the special address the Android
/// emulator maps to the host machine's `127.0.0.1`, where the FastAPI
/// backend runs during development. Override it explicitly for:
///   - a real device on the same LAN:
///       `--dart-define=API_BASE_URL=http://<lan-ip>:8000`
///   - Chrome/web or Windows desktop:
///       `--dart-define=API_BASE_URL=http://127.0.0.1:8000`
class AppEnv {
  AppEnv._();

  static const String apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://10.0.2.2:8000',
  );
}
```

Create `frontend/weathergpt_app/lib/core/network/app_error.dart`:

```dart
/// Typed errors the rest of the app pattern-matches on, instead of
/// handling a raw DioException at every call site.
sealed class AppError {
  const AppError();
}

class NetworkTimeoutError extends AppError {
  const NetworkTimeoutError();
}

class NetworkConnectionError extends AppError {
  const NetworkConnectionError();
}

class ServerError extends AppError {
  final int statusCode;
  const ServerError(this.statusCode);
}

class UnknownError extends AppError {
  final String message;
  const UnknownError(this.message);
}
```

Create `frontend/weathergpt_app/lib/core/network/api_client.dart`:

```dart
import 'package:dio/dio.dart';
import '../env/app_env.dart';
import 'app_error.dart';

/// Builds the single [Dio] client the app's data layer uses to reach the
/// FastAPI backend. Centralizes base URL, timeouts, and error mapping so
/// no call site needs to know about [DioException] directly.
Dio buildApiClient({String? baseUrl}) {
  final dio = Dio(
    BaseOptions(
      baseUrl: baseUrl ?? AppEnv.apiBaseUrl,
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 15),
    ),
  );
  dio.interceptors.add(_ErrorMappingInterceptor());
  return dio;
}

class _ErrorMappingInterceptor extends Interceptor {
  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    handler.next(err.copyWith(error: mapDioException(err)));
  }
}

/// Exposed separately from the interceptor so it is directly unit-testable
/// without constructing a full request/response cycle.
AppError mapDioException(DioException err) {
  switch (err.type) {
    case DioExceptionType.connectionTimeout:
    case DioExceptionType.sendTimeout:
    case DioExceptionType.receiveTimeout:
      return const NetworkTimeoutError();
    case DioExceptionType.connectionError:
      return const NetworkConnectionError();
    case DioExceptionType.badResponse:
      return ServerError(err.response?.statusCode ?? 0);
    default:
      return UnknownError(err.message ?? 'Unknown network error');
  }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

```powershell
flutter test test\core\network
```

- [ ] **Step 5: Full verification and commit**

```powershell
flutter analyze
flutter test
```

```bash
git add frontend/weathergpt_app/lib/core/env/ frontend/weathergpt_app/lib/core/network/ frontend/weathergpt_app/test/core/network/
git commit -m "feat: add env config and Dio client with typed error mapping"
```

---

### Task 5: Shared widget library

**Files:**
- Create: `frontend/weathergpt_app/lib/shared/widgets/app_primary_button.dart`
- Create: `frontend/weathergpt_app/lib/shared/widgets/app_chip.dart`
- Create: `frontend/weathergpt_app/lib/shared/widgets/loading_view.dart`
- Create: `frontend/weathergpt_app/lib/shared/widgets/error_view.dart`
- Create: `frontend/weathergpt_app/lib/shared/widgets/empty_view.dart`
- Create: `frontend/weathergpt_app/lib/shared/widgets/weather_icon.dart`
- Test: `frontend/weathergpt_app/test/shared/widgets/app_primary_button_test.dart`
- Test: `frontend/weathergpt_app/test/shared/widgets/error_view_test.dart`
- Test: `frontend/weathergpt_app/test/shared/widgets/weather_icon_test.dart`

**Interfaces:**
- Consumes: `AppRadius`, `AppColors` from Task 3.
- Produces: `AppPrimaryButton({label, onPressed})`, `AppChip({label, onTap, selected})`, `LoadingView({message})`, `ErrorView({message, onRetry})`, `EmptyView({message, actionLabel, onAction})`, `weatherIconFor(int weatherCode) -> IconData` — all consumed by Task 6's gallery screen and every real screen from Phase 1 onward.

- [ ] **Step 1: Write the failing tests**

Create `frontend/weathergpt_app/test/shared/widgets/app_primary_button_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weathergpt_app/shared/widgets/app_primary_button.dart';

void main() {
  testWidgets('invokes onPressed when tapped', (tester) async {
    var tapped = false;
    await tester.pumpWidget(
      MaterialApp(
        home: AppPrimaryButton(label: 'Go', onPressed: () => tapped = true),
      ),
    );

    await tester.tap(find.text('Go'));
    await tester.pump();

    expect(tapped, isTrue);
  });
}
```

Create `frontend/weathergpt_app/test/shared/widgets/error_view_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weathergpt_app/shared/widgets/error_view.dart';

void main() {
  testWidgets('shows the message and invokes onRetry when Retry is tapped', (tester) async {
    var retried = false;
    await tester.pumpWidget(
      MaterialApp(
        home: ErrorView(
          message: 'Could not load weather',
          onRetry: () => retried = true,
        ),
      ),
    );

    expect(find.text('Could not load weather'), findsOneWidget);

    await tester.tap(find.text('Retry'));
    await tester.pump();

    expect(retried, isTrue);
  });
}
```

Create `frontend/weathergpt_app/test/shared/widgets/weather_icon_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weathergpt_app/shared/widgets/weather_icon.dart';

void main() {
  test('maps clear sky (0) to a sunny icon', () {
    expect(weatherIconFor(0), Icons.wb_sunny_outlined);
  });

  test('maps thunderstorm codes (95-99) to a thunderstorm icon', () {
    expect(weatherIconFor(95), Icons.thunderstorm_outlined);
    expect(weatherIconFor(99), Icons.thunderstorm_outlined);
  });

  test('falls back to a help icon for an unrecognized code', () {
    expect(weatherIconFor(-1), Icons.help_outline);
  });
}
```

- [ ] **Step 2: Run the tests to verify they fail**

```powershell
. .\frontend\dev-env.ps1
cd frontend\weathergpt_app
flutter test test\shared\widgets
```

Expected: FAIL — none of the widgets exist yet.

- [ ] **Step 3: Implement**

Create `frontend/weathergpt_app/lib/shared/widgets/app_primary_button.dart`:

```dart
import 'package:flutter/material.dart';
import '../../core/theme/app_radius.dart';

class AppPrimaryButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;

  const AppPrimaryButton({super.key, required this.label, this.onPressed});

  @override
  Widget build(BuildContext context) {
    return ElevatedButton(
      onPressed: onPressed,
      style: ElevatedButton.styleFrom(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.surface),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
      ),
      child: Text(label),
    );
  }
}
```

Create `frontend/weathergpt_app/lib/shared/widgets/app_chip.dart`:

```dart
import 'package:flutter/material.dart';
import '../../core/theme/app_radius.dart';

class AppChip extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;
  final bool selected;

  const AppChip({
    super.key,
    required this.label,
    this.onTap,
    this.selected = false,
  });

  @override
  Widget build(BuildContext context) {
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: onTap == null ? null : (_) => onTap!(),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.control),
      ),
    );
  }
}
```

Create `frontend/weathergpt_app/lib/shared/widgets/loading_view.dart`:

```dart
import 'package:flutter/material.dart';

class LoadingView extends StatelessWidget {
  final String? message;

  const LoadingView({super.key, this.message});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(),
          if (message != null) ...[
            const SizedBox(height: 12),
            Text(message!, style: Theme.of(context).textTheme.bodyMedium),
          ],
        ],
      ),
    );
  }
}
```

Create `frontend/weathergpt_app/lib/shared/widgets/error_view.dart`:

```dart
import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';

class ErrorView extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const ErrorView({super.key, required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, color: AppColors.alertCrimson, size: 40),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 16),
            OutlinedButton(onPressed: onRetry, child: const Text('Retry')),
          ],
        ),
      ),
    );
  }
}
```

Create `frontend/weathergpt_app/lib/shared/widgets/empty_view.dart`:

```dart
import 'package:flutter/material.dart';

class EmptyView extends StatelessWidget {
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  const EmptyView({
    super.key,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.inbox_outlined,
              size: 40,
              color: Theme.of(context).colorScheme.outline,
            ),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 16),
              TextButton(onPressed: onAction, child: Text(actionLabel!)),
            ],
          ],
        ),
      ),
    );
  }
}
```

Create `frontend/weathergpt_app/lib/shared/widgets/weather_icon.dart`:

```dart
import 'package:flutter/material.dart';

/// Maps Open-Meteo's numeric WMO weather code — returned verbatim as
/// `weather_code` by the backend's `/weather` and `/forecast` endpoints
/// (see backend/app/weather/service.py and backend/app/forecast/service.py)
/// — to a representative Material icon. Codes follow the WMO 4677 table;
/// see https://open-meteo.com/en/docs for the full list.
IconData weatherIconFor(int weatherCode) {
  if (weatherCode == 0) return Icons.wb_sunny_outlined;
  if (weatherCode <= 2) return Icons.wb_cloudy_outlined;
  if (weatherCode == 3) return Icons.cloud_outlined;
  if (weatherCode == 45 || weatherCode == 48) return Icons.foggy;
  if (weatherCode >= 51 && weatherCode <= 57) return Icons.grain;
  if (weatherCode >= 61 && weatherCode <= 67) return Icons.water_drop_outlined;
  if (weatherCode >= 71 && weatherCode <= 77) return Icons.ac_unit;
  if (weatherCode >= 80 && weatherCode <= 82) return Icons.water_drop;
  if (weatherCode >= 85 && weatherCode <= 86) return Icons.ac_unit;
  if (weatherCode >= 95 && weatherCode <= 99) return Icons.thunderstorm_outlined;
  return Icons.help_outline;
}
```

- [ ] **Step 4: Run the tests to verify they pass**

```powershell
flutter test test\shared\widgets
```

- [ ] **Step 5: Full verification and commit**

```powershell
flutter analyze
flutter test
```

```bash
git add frontend/weathergpt_app/lib/shared/ frontend/weathergpt_app/test/shared/
git commit -m "feat: add shared widget library (button, chip, states, weather icons)"
```

---

### Task 6: Router, placeholder screens, and component gallery

**Files:**
- Create: `frontend/weathergpt_app/lib/features/shell/placeholder_screen.dart`
- Create: `frontend/weathergpt_app/lib/features/gallery/gallery_screen.dart`
- Create: `frontend/weathergpt_app/lib/core/router/app_router.dart`
- Modify: `frontend/weathergpt_app/android/app/src/main/AndroidManifest.xml`
- Test: `frontend/weathergpt_app/test/core/router/app_router_test.dart`

**Interfaces:**
- Consumes: `AppColors`, `AppSpacing` (Task 3), `AppPrimaryButton`, `AppChip`, `LoadingView`, `ErrorView`, `EmptyView`, `weatherIconFor` (Task 5).
- Produces: `appRouter` (a `GoRouter` instance), `PlaceholderScreen({title})`, `GalleryScreen` — all consumed by `main.dart` in Task 7.

- [ ] **Step 1: Create the placeholder screen**

Create `frontend/weathergpt_app/lib/features/shell/placeholder_screen.dart`:

```dart
import 'package:flutter/material.dart';

/// Temporary stand-in for a bottom-nav destination not yet built.
/// Replaced screen-by-screen in later phases (Home in Phase 1, Chat in
/// Phase 2, Forecast/More in Phase 3).
class PlaceholderScreen extends StatelessWidget {
  final String title;

  const PlaceholderScreen({super.key, required this.title});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: Center(
        child: Text(
          '$title — coming soon',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      ),
    );
  }
}
```

- [ ] **Step 2: Create the component gallery screen**

Create `frontend/weathergpt_app/lib/features/gallery/gallery_screen.dart`:

```dart
import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../shared/widgets/app_chip.dart';
import '../../shared/widgets/app_primary_button.dart';
import '../../shared/widgets/empty_view.dart';
import '../../shared/widgets/error_view.dart';
import '../../shared/widgets/loading_view.dart';
import '../../shared/widgets/weather_icon.dart';

/// Dev-only screen rendering every shared widget and design token for
/// visual self-review. Not part of the bottom-nav shell — reachable at
/// the `/gallery` route (see app_router.dart). Should gain a
/// debug-build guard before a public release; left open for now since
/// this phase has no other screen to link to it from.
class GalleryScreen extends StatelessWidget {
  const GalleryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Component gallery')),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        children: [
          Text('Display', style: textTheme.displayLarge),
          Text('Headline', style: textTheme.headlineMedium),
          Text('Title', style: textTheme.titleMedium),
          Text('Body large', style: textTheme.bodyLarge),
          Text('Body', style: textTheme.bodyMedium),
          Text('Caption', style: textTheme.bodySmall),
          const SizedBox(height: AppSpacing.xl),
          Wrap(
            spacing: AppSpacing.sm,
            children: [
              AppPrimaryButton(label: 'Primary action', onPressed: () {}),
              const AppChip(label: 'Rain'),
              const AppChip(label: 'Selected', selected: true),
            ],
          ),
          const SizedBox(height: AppSpacing.xl),
          Text('Alert severity', style: textTheme.titleMedium),
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: AppSpacing.sm,
            children: [
              for (final severity in ['Minor', 'Moderate', 'Severe', 'Extreme'])
                Chip(
                  label: Text(severity),
                  backgroundColor: AppColors.alertSeverity(severity),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.xl),
          Text('Weather icons', style: textTheme.titleMedium),
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: AppSpacing.md,
            children: [
              for (final code in [0, 3, 61, 95]) Icon(weatherIconFor(code)),
            ],
          ),
          const SizedBox(height: AppSpacing.xl),
          Text('States', style: textTheme.titleMedium),
          const SizedBox(height: AppSpacing.sm),
          SizedBox(
            height: 120,
            child: LoadingView(message: 'Loading forecast…'),
          ),
          SizedBox(
            height: 200,
            child: ErrorView(
              message: 'Could not reach the server.',
              onRetry: () {},
            ),
          ),
          SizedBox(
            height: 200,
            child: EmptyView(
              message: 'No alerts right now.',
              actionLabel: 'Refresh',
              onAction: () {},
            ),
          ),
        ],
      ),
    );
  }
}
```

- [ ] **Step 3: Create the router**

Create `frontend/weathergpt_app/lib/core/router/app_router.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../features/gallery/gallery_screen.dart';
import '../../features/shell/placeholder_screen.dart';

final appRouter = GoRouter(
  initialLocation: '/home',
  routes: [
    StatefulShellRoute.indexedStack(
      builder: (context, state, navigationShell) => Scaffold(
        body: navigationShell,
        bottomNavigationBar: NavigationBar(
          selectedIndex: navigationShell.currentIndex,
          onDestinationSelected: navigationShell.goBranch,
          destinations: const [
            NavigationDestination(icon: Icon(Icons.home_outlined), label: 'Home'),
            NavigationDestination(icon: Icon(Icons.chat_outlined), label: 'Chat'),
            NavigationDestination(
              icon: Icon(Icons.calendar_month_outlined),
              label: 'Forecast',
            ),
            NavigationDestination(icon: Icon(Icons.apps_outlined), label: 'More'),
          ],
        ),
      ),
      branches: [
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/home',
              builder: (context, state) => const PlaceholderScreen(title: 'Home'),
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/chat',
              builder: (context, state) => const PlaceholderScreen(title: 'Chat'),
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/forecast',
              builder: (context, state) => const PlaceholderScreen(title: 'Forecast'),
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/more',
              builder: (context, state) => const PlaceholderScreen(title: 'More'),
            ),
          ],
        ),
      ],
    ),
    GoRoute(
      path: '/gallery',
      builder: (context, state) => const GalleryScreen(),
    ),
  ],
);
```

- [ ] **Step 4: Add a deep link so the gallery is reachable without UI navigation**

`flutter create` generated `frontend/weathergpt_app/android/app/src/main/AndroidManifest.xml` with an `<activity>` element containing one `<intent-filter>` for `MAIN`/`LAUNCHER`. This is genuinely useful beyond this phase too — the spec chose `go_router` partly for its deep-link readiness. Add a second `<intent-filter>` immediately after the existing one, inside the same `<activity>` element:

```xml
<intent-filter>
    <action android:name="android.intent.action.VIEW"/>
    <category android:name="android.intent.category.DEFAULT"/>
    <category android:name="android.intent.category.BROWSABLE"/>
    <data android:scheme="weathergpt"/>
</intent-filter>
```

This lets `adb shell am start -a android.intent.action.VIEW -d "weathergpt://gallery"` (used in Task 7) open the app directly at `/gallery` — no custom native code needed; Flutter's `Router`/`go_router` integration handles the incoming route automatically.

- [ ] **Step 5: Write the router test**

Create `frontend/weathergpt_app/test/core/router/app_router_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weathergpt_app/core/router/app_router.dart';

void main() {
  testWidgets('starts at Home and shows the bottom nav bar', (tester) async {
    await tester.pumpWidget(MaterialApp.router(routerConfig: appRouter));
    await tester.pumpAndSettle();

    expect(find.text('Home — coming soon'), findsOneWidget);
    expect(find.byType(NavigationBar), findsOneWidget);
  });

  testWidgets('navigating to /gallery shows the component gallery', (tester) async {
    await tester.pumpWidget(MaterialApp.router(routerConfig: appRouter));
    await tester.pumpAndSettle();

    appRouter.go('/gallery');
    await tester.pumpAndSettle();

    expect(find.text('Component gallery'), findsOneWidget);
  });
}
```

- [ ] **Step 6: Run the tests**

```powershell
. .\frontend\dev-env.ps1
cd frontend\weathergpt_app
flutter test test\core\router
```

Expected: PASS.

- [ ] **Step 7: Full verification and commit**

```powershell
flutter analyze
flutter test
```

```bash
git add frontend/weathergpt_app/lib/features/ frontend/weathergpt_app/lib/core/router/ frontend/weathergpt_app/android/app/src/main/AndroidManifest.xml frontend/weathergpt_app/test/core/router/
git commit -m "feat: add bottom-nav shell router, placeholder screens, and component gallery"
```

---

### Task 7: Wire the app together and verify visually on the emulator

**Files:**
- Modify: `frontend/weathergpt_app/lib/main.dart`
- Modify: `frontend/weathergpt_app/test/widget_test.dart`

**Interfaces:**
- Consumes: `appRouter` (Task 6), `AppTheme.light`/`AppTheme.dark` (Task 3).

- [ ] **Step 1: Wire main.dart**

Replace the full contents of `frontend/weathergpt_app/lib/main.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';

void main() {
  runApp(const ProviderScope(child: WeatherGptApp()));
}

class WeatherGptApp extends StatelessWidget {
  const WeatherGptApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'WeatherGPT',
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      routerConfig: appRouter,
    );
  }
}
```

- [ ] **Step 2: Update the widget test to match**

Replace the full contents of `frontend/weathergpt_app/test/widget_test.dart`:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weathergpt_app/main.dart';

void main() {
  testWidgets('WeatherGptApp boots to the Home tab', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: WeatherGptApp()));
    await tester.pumpAndSettle();

    expect(find.text('Home — coming soon'), findsOneWidget);
  });
}
```

- [ ] **Step 3: Run the full test suite**

```powershell
. .\frontend\dev-env.ps1
cd frontend\weathergpt_app
flutter analyze
flutter test
```

Expected: `flutter analyze` — "No issues found!"; `flutter test` — every test from Tasks 1, 3, 4, 5, 6, 7 passes.

- [ ] **Step 4: Boot the emulator if it isn't already running**

```powershell
. .\frontend\dev-env.ps1
$running = adb devices | Select-String "device$"
if (-not $running) {
    Start-Process -FilePath "emulator" -ArgumentList "-avd","WeatherGPT_Pixel6" -WindowStyle Hidden
    adb wait-for-device
    do {
        Start-Sleep -Seconds 3
        $booted = (adb shell getprop sys.boot_completed 2>$null).Trim()
    } while ($booted -ne "1")
}
```

- [ ] **Step 5: Build, install, and launch on the emulator**

```powershell
cd frontend\weathergpt_app
flutter build apk --debug --dart-define=API_BASE_URL=http://10.0.2.2:8000
adb install -r build\app\outputs\flutter-apk\app-debug.apk
adb shell cmd uimode night no
adb shell am start -a android.intent.action.VIEW -d "weathergpt://gallery"
Start-Sleep -Seconds 3
```

- [ ] **Step 6: Capture the light-mode screenshot**

```powershell
adb exec-out screencap -p > gallery_light.png
```

- [ ] **Step 7: Capture the dark-mode screenshot**

```powershell
adb shell cmd uimode night yes
Start-Sleep -Seconds 2
adb exec-out screencap -p > gallery_dark.png
adb shell cmd uimode night no
```

- [ ] **Step 8: Self-review both screenshots**

Read `gallery_light.png` and `gallery_dark.png` and check, for each:
- The six palette colors (Monsoon Ink, Storm Slate, Cloudlight, Marigold, Paddy Green, Alert Crimson) render as the specified hex values, not a fallback/default Material color.
- The type scale is visibly distinct across Display → Headline → Title → Body → Caption (real size/weight steps, not near-identical sizes).
- Spacing between sections reads as generous and consistent, not cramped or arbitrary.
- Radius hierarchy is visible: the primary button and chips have a visibly different corner radius from each other, consistent with `AppRadius.surface` (12) vs `AppRadius.control` (4).
- The four alert-severity chips are visibly distinct colors from each other.
- Text remains legible (sufficient contrast) in both light and dark mode — this is a real accessibility check, not just an aesthetic one.

If anything looks wrong (a token not applying, illegible contrast, a widget not rendering), fix the specific token or widget file and re-run Steps 3, 5–7 before proceeding — do not proceed to commit with a known-wrong screenshot.

- [ ] **Step 9: Commit**

```bash
git add frontend/weathergpt_app/lib/main.dart frontend/weathergpt_app/test/widget_test.dart
git commit -m "feat: wire router and theme into the app entry point"
```

(`gallery_light.png`/`gallery_dark.png` are review artifacts, not committed — they live in the worktree only.)

---

## Execution

This plan is ready for **subagent-driven-development** (recommended, and already the approach used for this session's backend sprints): a fresh implementer subagent per task, a task review after each, and a final whole-branch review at the end. Each task above is independently testable and produces a real, verifiable commit.
