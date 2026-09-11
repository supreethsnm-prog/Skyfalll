import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';

import '../../core/geo.dart';
import '../../core/location/device_location.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';
import '../../core/theme/sky_gradient.dart';
import '../../data/alerts_api.dart';
import '../../data/weather_api.dart';
import '../../shared/error_message.dart';
import '../shell/app_drawer.dart';
import '../../shared/widgets/app_menu.dart';
import '../../shared/widgets/language_settings_button.dart';
import '../../shared/widgets/round_icon_button.dart';
import '../../l10n/app_strings.dart';
import 'home_controller.dart';
import 'widgets/alert_banner.dart';
import 'widgets/detail_tiles.dart';
import 'widgets/forecast_panel.dart';
import 'widgets/home_hero.dart';
import 'widgets/location_search_sheet.dart';
import 'widgets/severe_weather_panel.dart';
import '../saved/saved_places_controller.dart';
import '../../data/geocoding_api.dart';

/// The app's launch screen, modelled on the Google Weather home screen
/// (`Home1.jpeg`, `Home2.jpeg`): a full-bleed sky reflecting the current
/// conditions, the temperature sitting straight on it, and translucent
/// panels grouping the rest.
///
/// The chrome is two free-floating [RoundIconButton]s with no `AppBar`
/// behind them — an opaque toolbar would break the full-bleed sky, which
/// is the whole look.
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key, this.now});

  /// Injectable clock, so goldens can pin a time of day instead of
  /// rendering differently depending on when the suite runs.
  final DateTime? now;

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  StreamSubscription<List<AlertSummary>>? _alertSubscription;

  @override
  void initState() {
    super.initState();
    // Fired once, after the first frame, so the controller's state change
    // never lands during a build.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(homeControllerProvider.notifier).loadInitial();
      _listenForLiveAlerts();
    });
  }

  /// Surfaces warnings the moment the backend ingests them, rather than
  /// waiting for the user to pull to refresh. For a disaster-advisory
  /// app, waiting to be asked is the wrong way round.
  void _listenForLiveAlerts() {
    _alertSubscription =
        ref.read(alertsSocketProvider).newAlerts.listen((alerts) {
      // The controller applies the same radius filter a fetched load
      // does, and tells us what actually landed — so a batch of distant
      // warnings interrupts nobody.
      final nearby =
          ref.read(homeControllerProvider.notifier).mergeLiveAlerts(alerts);
      if (nearby.isEmpty || !mounted) return;

      final first = nearby.first;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: AppColors.alertSeverity(first.severity),
          duration: const Duration(seconds: 8),
          behavior: SnackBarBehavior.floating,
          content: Text(
            nearby.length == 1
                ? '${first.severity}: ${first.eventType}'
                : '${nearby.length} new alerts for this area',
            style: AppTypography.body(
              AppColors.onAlertSeverity(first.severity),
            ),
          ),
        ),
      );
    });
  }

  @override
  void dispose() {
    _alertSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(homeControllerProvider);

    // The sky needs a condition, which only the loaded state has. Before
    // then, fall back to the time-appropriate clear sky so the background
    // does not flash a different colour when data lands.
    final now = widget.now ?? DateTime.now();
    final time = skyTimeOfDayFor(now);
    final condition = switch (state) {
      HomeLoaded(:final weather) => skyConditionFor(weather.weatherCode),
      _ => SkyCondition.clear,
    };
    final foreground = skyForeground(time, condition);

    return Scaffold(
      drawer: const AppDrawer(),
      backgroundColor: AppColors.bgBase,
      body: Container(
        decoration: BoxDecoration(gradient: skyGradient(time, condition)),
        child: SafeArea(
          // StackFit.expand is load-bearing: without it the Stack sizes to
          // its non-positioned children, which would be just the chrome
          // row, collapsing the gradient to a 64dp strip.
          child: Stack(
            fit: StackFit.expand,
            children: [
              _Body(state: state, foreground: foreground),
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: _Chrome(
                  foreground: foreground,
                  place: state is HomeLoaded ? state.location : null,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Chrome extends ConsumerWidget {
  const _Chrome({required this.foreground, this.place});

  final Color foreground;

  /// The location currently shown, so it can be saved. Null while
  /// loading or errored, when there is nothing to bookmark.
  final GeocodeResult? place;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final current = place;
    final s = ref.watch(uiStringsProvider);
    final isSaved =
        current != null && ref.watch(savedPlacesProvider.notifier).isSaved(current);
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.screenMargin),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          RoundIconButton(
            icon: Icons.menu,
            tooltip: s.openMenu,
            onPressed: () => Scaffold.of(context).openDrawer(),
          ),
          Row(
            children: [
              if (current != null) ...[
                RoundIconButton(
                  icon: isSaved ? Icons.bookmark : Icons.bookmark_border,
                  tooltip: isSaved ? 'Remove from saved' : 'Save this place',
                  onPressed: () {
                    ref.read(savedPlacesProvider.notifier).toggle(current);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        behavior: SnackBarBehavior.floating,
                        backgroundColor: AppColors.surfaceRaised,
                        duration: const Duration(seconds: 2),
                        content: Text(
                          isSaved
                              ? 'Removed ${current.displayName}'
                              : 'Saved ${current.displayName}',
                          style: AppTypography.body(AppColors.textPrimary),
                        ),
                      ),
                    );
                  },
                ),
                const SizedBox(width: AppSpacing.sm),
              ],
              RoundIconButton(
                icon: Icons.search,
                tooltip: s.searchLocation,
                onPressed: () => showLocationSearch(context),
              ),
              const SizedBox(width: AppSpacing.sm),
              RoundIconButton(
                icon: Icons.add,
                tooltip: s.newChat,
                onPressed: () => context.go('/chat'),
              ),
              const SizedBox(width: AppSpacing.sm),
              const LanguageSettingsButton(),
              const SizedBox(width: AppSpacing.sm),
              Builder(
                builder: (context) => RoundIconButton(
                  icon: Icons.more_vert,
                  tooltip: s.moreOptions,
                  onPressed: () => showAppMenu(
                    context: context,
                    // Home shows a reduced set: most of the reference menu's
                    // items (Pin, Archive, Find in chat) are chat-context and
                    // meaningless here.
                    items: [
                      AppMenuItem(
                        icon: Icons.ios_share,
                        label: s.share,
                        onTap: () {},
                      ),
                      AppMenuItem(
                        icon: Icons.place_outlined,
                        label: s.changeLocation,
                        onTap: () => showLocationSearch(context),
                      ),
                      AppMenuItem(
                        icon: Icons.bookmark_border,
                        label: s.savedPlaces,
                        onTap: () => context.go('/saved'),
                      ),
                      AppMenuItem(
                        icon: Icons.settings_outlined,
                        label: s.settings,
                        onTap: () {},
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Body extends ConsumerWidget {
  const _Body({required this.state, required this.foreground});

  final HomeUiState state;
  final Color foreground;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return switch (state) {
      HomeLoading() => Center(
        child: CircularProgressIndicator(color: foreground),
      ),
      // Also pull-to-refresh: a failed load is exactly when someone
      // reaches for the gesture, and having it work only on success
      // would be backwards.
      HomeError(:final error) => RefreshIndicator(
        onRefresh: () =>
            ref.read(homeControllerProvider.notifier).useCurrentLocation(),
        color: AppColors.textPrimary,
        backgroundColor: AppColors.surfaceRaised,
        child: _ErrorView(
          message: errorMessageFor(error),
          foreground: foreground,
          onRetry: () => ref.read(homeControllerProvider.notifier).retry(),
        ),
      ),
      HomeLoaded() => _LoadedView(
        state: state as HomeLoaded,
        foreground: foreground,
      ),
    };
  }
}

class _LoadedView extends ConsumerWidget {
  const _LoadedView({required this.state, required this.foreground});

  final HomeLoaded state;
  final Color foreground;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final today = state.forecast.isNotEmpty ? state.forecast.first : null;
    final s = ref.watch(uiStringsProvider);

    return RefreshIndicator(
      // Re-resolves the device position as well as the data: on a screen
      // whose whole premise is "weather where you are", a pull that kept
      // a stale position after the user has moved would be wrong.
      onRefresh: () =>
          ref.read(homeControllerProvider.notifier).useCurrentLocation(),
      color: AppColors.textPrimary,
      backgroundColor: AppColors.surfaceRaised,
      child: _scrollView(context, today, s),
    );
  }

  Widget _scrollView(BuildContext context, ForecastDay? today, AppStrings s) {
    return SingleChildScrollView(
      // Always scrollable, so the pull gesture is available even when the
      // content is short enough to fit — otherwise refresh silently stops
      // working on large screens.
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        // Clears the floating chrome above.
        AppSpacing.huge + AppSpacing.lg,
        AppSpacing.lg,
        AppSpacing.xxxl,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          HomeHero(
            place: state.location.displayName,
            weather: state.weather,
            foreground: foreground,
            high: today?.tempMaxC,
            low: today?.tempMinC,
            onTapPlace: () => showLocationSearch(context),
          ),
          if (state.locationFailure != null) ...[
            const SizedBox(height: AppSpacing.sm),
            _LocationNotice(
              failure: state.locationFailure!,
              foreground: foreground,
            ),
          ],
          const SizedBox(height: AppSpacing.md),
          AqiPill(airQuality: state.airQuality, foreground: foreground),
          const SizedBox(height: AppSpacing.xxl),
          // Absence of alerts is only informative once the user knows
          // whether this location is even in scope — our sources are
          // Indian government feeds (see `_AlertCoverageNotice`), so
          // "nothing nearby" outside India means "not covered", not "all
          // clear". Inside India, silence already means all clear and a
          // disclaimer here would be noise.
          if (state.nearbyAlerts.isEmpty &&
              IndiaAlertCoverageBox.isOutsideCoverage(
                country: state.location.country,
                latitude: state.location.latitude,
                longitude: state.location.longitude,
              )) ...[
            _AlertCoverageNotice(foreground: foreground),
            const SizedBox(height: AppSpacing.md),
          ],
          for (final alert in state.nearbyAlerts) ...[
            AlertBanner(alert: alert),
            const SizedBox(height: AppSpacing.md),
          ],
          if (state.weather.hourly != null) ...[
            HourlyPanel(
              hours: state.weather.hourly!,
              foreground: foreground,
              strings: s,
            ),
            const SizedBox(height: AppSpacing.md),
          ],
          if (state.forecast.isNotEmpty) ...[
            ForecastPanel(days: state.forecast, foreground: foreground),
            const SizedBox(height: AppSpacing.md),
          ],
          DetailGrid(
            weather: state.weather,
            foreground: foreground,
            uvIndexMax: today?.uvIndexMax,
            airQuality: state.airQuality,
            strings: s,
          ),
          const SizedBox(height: AppSpacing.md),
          SevereWeatherPanel(
            nwp: state.nwp,
            foreground: foreground,
            strings: s,
          ),
          const SizedBox(height: AppSpacing.md),
          SunPanel(
            foreground: foreground,
            sunrise: today?.sunrise,
            sunset: today?.sunset,
            strings: s,
          ),
        ],
      ),
    );
  }
}

/// Shown when Home fell back to the default city because the device's
/// location was unavailable. Deliberately a quiet inline note, not a
/// blocking dialog: the weather on screen is real and useful, it is just
/// not for here.
class _LocationNotice extends ConsumerWidget {
  const _LocationNotice({required this.failure, required this.foreground});

  final LocationFailure failure;
  final Color foreground;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(uiStringsProvider);
    // Each case gets the remedy that actually works. Re-prompting after a
    // permanent denial silently no-ops at the OS level, so that case must
    // send the user to settings instead.
    final (String message, String action) = switch (failure) {
      LocationFailure.serviceDisabled => (
          'Location is turned off.',
          s.settings,
        ),
      LocationFailure.permissionDeniedForever => (
          'Location permission is blocked.',
          s.settings,
        ),
      LocationFailure.permissionDenied => (
          'Showing New Delhi.',
          s.useMyLocation,
        ),
      LocationFailure.unavailable => (
          s.couldNotGetLocation,
          s.retry,
        ),
    };

    final sendToSettings = failure == LocationFailure.serviceDisabled ||
        failure == LocationFailure.permissionDeniedForever;

    return Row(
      children: [
        Icon(Icons.location_off_outlined, size: 16, color: foreground),
        const SizedBox(width: AppSpacing.sm),
        Flexible(
          child: Text(
            message,
            style: AppTypography.caption(foreground),
          ),
        ),
        TextButton(
          onPressed: () {
            if (sendToSettings) {
              Geolocator.openAppSettings();
            } else {
              ref.read(homeControllerProvider.notifier).useCurrentLocation();
            }
          },
          style: TextButton.styleFrom(
            foregroundColor: foreground,
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
            minimumSize: const Size(0, 32),
          ),
          child: Text(action, style: AppTypography.caption(foreground)),
        ),
      ],
    );
  }
}

/// Shown in place of the (empty) alerts list when the current location is
/// outside our alert sources' coverage — see `IndiaAlertCoverageBox`.
///
/// A user in Nepal seeing no alerts during a real flood there reasonably
/// reads that as "the app missed it". It did not: our feeds
/// (SACHET-IMD-NOWCAST, SACHET-SDMA) are Indian government sources and do
/// not cover Nepal. A caption, not a warning — this is a coverage fact, not
/// something wrong with the screen.
class _AlertCoverageNotice extends ConsumerWidget {
  const _AlertCoverageNotice({required this.foreground});

  final Color foreground;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(uiStringsProvider);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.info_outline, size: 16, color: foreground),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Text(
            s.alertsNotice,
            style: AppTypography.caption(foreground),
          ),
        ),
      ],
    );
  }
}

class _ErrorView extends ConsumerWidget {
  const _ErrorView({
    required this.message,
    required this.foreground,
    required this.onRetry,
  });

  final String message;
  final Color foreground;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(uiStringsProvider);
    // Scrollable so a long message on a short screen degrades into
    // scrolling rather than a layout overflow — and so the enclosing
    // RefreshIndicator has a scrollable to hang its pull gesture on.
    return SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      child: Container(
        constraints: BoxConstraints(
          minHeight: MediaQuery.of(context).size.height * 0.6,
        ),
        alignment: Alignment.center,
        padding: const EdgeInsets.all(AppSpacing.xxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_off, size: 40, color: foreground),
            const SizedBox(height: AppSpacing.lg),
            Text(
              s.couldNotLoadWeather,
              style: AppTypography.title(foreground),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              message,
              style: AppTypography.label(foreground),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.xl),
            TextButton(
              onPressed: onRetry,
              style: TextButton.styleFrom(
                foregroundColor: foreground,
                side: BorderSide(color: foreground),
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.xxl,
                  vertical: AppSpacing.md,
                ),
              ),
              child: Text(s.tryAgain, style: AppTypography.body(foreground)),
            ),
          ],
        ),
      ),
    );
  }
}
