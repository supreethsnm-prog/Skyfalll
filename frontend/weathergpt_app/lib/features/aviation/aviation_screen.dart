import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_radius.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';
import '../../data/geocoding_api.dart';
import '../../data/metar_api.dart';
import '../../shared/error_message.dart';
import '../../shared/widgets/round_icon_button.dart';
import '../chat/widgets/code_block.dart';
import '../home/home_controller.dart';
import '../shell/app_drawer.dart';
import 'airports.dart';
import 'aviation_controller.dart';
import 'flight_category.dart';

/// Live airport weather (METAR) for the airport nearest Home's current
/// location, with a picker to see any of the 14 bundled stations instead.
///
/// Deliberately reads its location from [homeControllerProvider] instead
/// of resolving its own, for the same reason `AdvisoryScreen` does: Home
/// already owns "where is the user", and a second, independently-resolved
/// location here could disagree with it.
class AviationScreen extends ConsumerStatefulWidget {
  const AviationScreen({super.key, this.now});

  /// Injectable clock. The observation's AGE is shown ("20 min ago"), so
  /// without this a golden would render differently every hour. Same
  /// pattern as `HomeScreen` and `SavedPlacesScreen`.
  final DateTime? now;

  @override
  ConsumerState<AviationScreen> createState() => _AviationScreenState();
}

class _AviationScreenState extends ConsumerState<AviationScreen> {
  /// The location the controller was last asked to derive an airport from,
  /// so a rebuild (e.g. from an unrelated provider change) does not
  /// re-issue the same request, and so a genuine location change from Home
  /// IS re-issued. Mirrors `AdvisoryScreen._requestedFor`.
  GeocodeResult? _requestedFor;

  @override
  void initState() {
    super.initState();
    // Home may already be loaded by the time this screen opens (the usual
    // case). Fired after the first frame so the controller's state change
    // never lands during a build.
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeLoadFromHome());
  }

  void _maybeLoadFromHome() {
    final homeState = ref.read(homeControllerProvider);
    if (homeState is HomeLoaded) {
      _loadFor(homeState.location);
      return;
    }

    // Home has not resolved a location yet. Normally it has — it is the
    // launch route — but arriving here first (a hot restart on this route,
    // or a deep link) would otherwise leave this screen spinning forever,
    // waiting on a load nothing had asked for. Kicking Home off keeps it
    // the single owner of "where is the user" rather than resolving a
    // second location here; the ref.listen below picks the result up.
    if (homeState is HomeLoading) {
      ref.read(homeControllerProvider.notifier).loadInitial();
    }
  }

  void _loadFor(GeocodeResult location) {
    final requested = _requestedFor;
    if (requested != null &&
        requested.latitude == location.latitude &&
        requested.longitude == location.longitude) {
      return;
    }
    _requestedFor = location;
    ref.read(aviationControllerProvider.notifier).loadNearest(location);
  }

  void _selectAirport(Airport airport) {
    ref.read(aviationControllerProvider.notifier).selectAirport(airport);
  }

  @override
  Widget build(BuildContext context) {
    // Home may still be loading, or finish loading, or change location
    // entirely, at any point while this screen is open — this listener
    // catches every one of those after the first frame; the initState
    // callback above only covers the "Home was already loaded" case.
    ref.listen<HomeUiState>(homeControllerProvider, (previous, next) {
      if (next is HomeLoaded) _loadFor(next.location);
    });

    final homeState = ref.watch(homeControllerProvider);
    final aviationState = ref.watch(aviationControllerProvider);

    return Scaffold(
      backgroundColor: AppColors.bgBase,
      drawer: const AppDrawer(activeRoute: '/aviation'),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.all(AppSpacing.screenMargin),
              child: Row(
                children: [
                  Builder(
                    builder: (context) => RoundIconButton(
                      icon: Icons.menu,
                      tooltip: 'Open menu',
                      onPressed: () => Scaffold.of(context).openDrawer(),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Text(
                    'Aviation',
                    style: AppTypography.title(AppColors.textPrimary),
                  ),
                ],
              ),
            ),
            Expanded(
              child: _Body(
                homeState: homeState,
                aviationState: aviationState,
                onSelectAirport: _selectAirport,
                now: widget.now,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Body extends ConsumerWidget {
  const _Body({
    required this.homeState,
    required this.aviationState,
    required this.onSelectAirport,
    this.now,
  });

  /// Injectable clock, threaded down to the observation-age label.
  final DateTime? now;

  final HomeUiState homeState;
  final AviationUiState aviationState;
  final ValueChanged<Airport> onSelectAirport;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Home not having a location yet is a loading state here too — never
    // pick a default of our own, or two screens could disagree about
    // where the user is.
    if (homeState is! HomeLoaded) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.textPrimary),
      );
    }

    return switch (aviationState) {
      AviationLoading() => const Center(
          child: CircularProgressIndicator(color: AppColors.textPrimary),
        ),
      AviationError(:final error) => RefreshIndicator(
          onRefresh: () =>
              ref.read(aviationControllerProvider.notifier).retry(),
          color: AppColors.textPrimary,
          backgroundColor: AppColors.surfaceRaised,
          child: _ErrorView(
            message: errorMessageFor(error),
            onRetry: () =>
                ref.read(aviationControllerProvider.notifier).retry(),
          ),
        ),
      AviationNotFound(:final airport, :final distanceKm) => RefreshIndicator(
          onRefresh: () =>
              ref.read(aviationControllerProvider.notifier).retry(),
          color: AppColors.textPrimary,
          backgroundColor: AppColors.surfaceRaised,
          child: _NotFoundView(
            airport: airport,
            distanceKm: distanceKm,
            onSelectAirport: onSelectAirport,
          ),
        ),
      AviationLoaded() => _LoadedView(
          now: now,
          state: aviationState as AviationLoaded,
          onSelectAirport: onSelectAirport,
        ),
    };
  }
}

/// Airport name, distance from Home, and the picker button — shown above
/// both the loaded observation and the "no observation" state, since both
/// know which airport and how far away it is.
class _AirportHeader extends StatelessWidget {
  const _AirportHeader({
    required this.airport,
    required this.distanceKm,
    required this.onSelectAirport,
    this.stationName,
  });

  final Airport airport;
  final double? distanceKm;
  final String? stationName;
  final ValueChanged<Airport> onSelectAirport;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '${airport.city} (${airport.icao})',
                style: AppTypography.title(AppColors.textPrimary),
              ),
              const SizedBox(height: AppSpacing.xs),
              // A METAR from 300km away is still useful, but the user must
              // not mistake it for local — this is why distance is shown
              // at all. Absent (only possible if a reading somehow loaded
              // before Home resolved a location) means omitted, never a
              // fake "0 km away".
              if (distanceKm != null)
                Text(
                  '${distanceKm!.round()} km away',
                  style: AppTypography.label(AppColors.textSecondary),
                ),
              if (stationName != null)
                Text(
                  stationName!,
                  style: AppTypography.caption(AppColors.textSecondary),
                ),
            ],
          ),
        ),
        const SizedBox(width: AppSpacing.md),
        Semantics(
          button: true,
          label: 'Choose a different airport',
          child: ExcludeSemantics(
            child: TextButton(
              onPressed: () =>
                  showAirportPicker(context, airport, onSelectAirport),
              style: TextButton.styleFrom(
                foregroundColor: AppColors.textPrimary,
                side: const BorderSide(color: AppColors.divider),
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.lg,
                  vertical: AppSpacing.sm,
                ),
              ),
              child: Text('Change', style: AppTypography.body(AppColors.textPrimary)),
            ),
          ),
        ),
      ],
    );
  }
}

class _LoadedView extends ConsumerWidget {
  const _LoadedView({
    required this.state,
    required this.onSelectAirport,
    this.now,
  });

  final DateTime? now;

  final AviationLoaded state;
  final ValueChanged<Airport> onSelectAirport;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reading = state.reading;

    return RefreshIndicator(
      onRefresh: () => ref.read(aviationControllerProvider.notifier).retry(),
      color: AppColors.textPrimary,
      backgroundColor: AppColors.surfaceRaised,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.sm,
          AppSpacing.lg,
          AppSpacing.xxxl,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _AirportHeader(
              airport: state.airport,
              distanceKm: state.distanceKm,
              stationName: reading.stationName,
              onSelectAirport: onSelectAirport,
            ),
            const SizedBox(height: AppSpacing.xl),
            _CategoryBanner(category: reading.flightCategory),
            const SizedBox(height: AppSpacing.sm),
            _ObservedAt(
              observedAtUtc: reading.observedAt,
              now: now,
            ),
            const SizedBox(height: AppSpacing.lg),
            _StatsGrid(reading: reading),
            const SizedBox(height: AppSpacing.xl),
            Text('Raw report', style: AppTypography.label(AppColors.textPrimary)),
            const SizedBox(height: AppSpacing.sm),
            // The actual encoded observation, verbatim — what a pilot
            // reads, and proof the data is real. Reuses the chat
            // transcript's code block rather than a bespoke monospace box.
            CodeBlock(code: reading.rawMetar),
          ],
        ),
      ),
    );
  }
}

/// The category, coloured with the app's one severity ramp via
/// [capSeverityForFlightCategory] — see that function for why an
/// unrecognised or missing category must NOT be coloured as if it were a
/// known-good one.
class _CategoryBanner extends StatelessWidget {
  const _CategoryBanner({required this.category});

  final String? category;

  @override
  Widget build(BuildContext context) {
    final capSeverity = capSeverityForFlightCategory(category);
    final background = capSeverity == null
        ? AppColors.surfaceRaised
        : AppColors.alertSeverity(capSeverity);
    final foreground = capSeverity == null
        ? AppColors.textPrimary
        : AppColors.onAlertSeverity(capSeverity);
    // A missing category is absent data, not a known value — it must read
    // as "not reported", never as blank, a dash, or the name of a real
    // category it does not actually have.
    final label = category ?? 'Not reported';

    return Semantics(
      label: 'Flight category: $label',
      child: ExcludeSemantics(
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(AppSpacing.lg),
          decoration: BoxDecoration(
            color: background,
            borderRadius: BorderRadius.circular(AppRadius.panel),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Flight category', style: AppTypography.caption(foreground)),
              const SizedBox(height: AppSpacing.xs),
              Text(label, style: AppTypography.title(foreground)),
            ],
          ),
        ),
      ),
    );
  }
}

/// When the observation was taken.
///
/// A METAR is a point-in-time measurement, not a forecast, and its AGE is
/// operationally meaningful — a report from twenty minutes ago and one
/// from three hours ago support very different decisions. The raw report
/// carries the timestamp as "100230Z", which is unreadable to anyone who
/// is not a pilot, so it is shown in plain local time as well.
class _ObservedAt extends StatelessWidget {
  const _ObservedAt({required this.observedAtUtc, this.now});

  final String observedAtUtc;
  final DateTime? now;

  @override
  Widget build(BuildContext context) {
    final parsed = DateTime.tryParse(observedAtUtc);
    // An unparseable timestamp is dropped rather than shown raw: a
    // half-rendered ISO string looks like a bug, and the raw report block
    // below still carries the real value.
    if (parsed == null) return const SizedBox.shrink();

    final local = parsed.toLocal();
    final age = (now ?? DateTime.now()).difference(local);
    final hh = local.hour.toString().padLeft(2, '0');
    final mm = local.minute.toString().padLeft(2, '0');

    final ageText = age.isNegative
        ? ''
        : age.inMinutes < 60
            ? ' · ${age.inMinutes} min ago'
            : ' · ${age.inHours} h ago';

    return Text(
      'Observed $hh:$mm$ageText',
      style: AppTypography.caption(AppColors.textSecondary),
    );
  }
}

class _StatsGrid extends StatelessWidget {
  const _StatsGrid({required this.reading});

  final MetarReading reading;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _StatTile(
                icon: Icons.thermostat,
                label: 'Temperature',
                value: formatTemperatureC(reading.temperatureC),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: _StatTile(
                icon: Icons.water_drop_outlined,
                label: 'Dew point',
                value: formatTemperatureC(reading.dewpointC),
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        Row(
          children: [
            Expanded(
              child: _StatTile(
                icon: Icons.air,
                label: 'Wind',
                value: formatWind(reading.windDirDeg, reading.windSpeedKt),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: _StatTile(
                icon: Icons.visibility_outlined,
                label: 'Visibility',
                value: formatVisibilityKm(reading.visibilityKm),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// °C rounded to a whole degree. Null in, null out — a missing reading
/// must never render as "0°C".
String? formatTemperatureC(double? celsius) =>
    celsius == null ? null : '${celsius.round()}°C';

/// Visibility already converted to km by `MetarReading.visibilityKm`; this
/// only formats it to one decimal place.
String? formatVisibilityKm(double? km) =>
    km == null ? null : '${km.toStringAsFixed(1)} km';

/// Wind direction + speed, with speed converted from the upstream knots to
/// km/h (×1.852) since the rest of the app is metric. Direction and speed
/// are independently nullable in the reading, so each half degrades on its
/// own rather than either hiding a value the other one has:
/// - both present: "260° at 17 km/h"
/// - only one present: that one alone
/// - neither: null (absent, not "0 km/h")
String? formatWind(double? directionDeg, double? speedKt) {
  final direction = directionDeg == null ? null : '${directionDeg.round()}°';
  final speed = speedKt == null ? null : '${(speedKt * 1.852).round()} km/h';
  if (direction != null && speed != null) return '$direction at $speed';
  return speed ?? direction;
}

class _StatTile extends StatelessWidget {
  const _StatTile({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;

  /// Pre-formatted, or null for an absent reading — rendered as "Not
  /// reported" rather than 0 or a dash.
  final String? value;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '$label: ${value ?? 'not reported'}',
      child: ExcludeSemantics(
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            color: AppColors.surfaceRaised,
            borderRadius: BorderRadius.circular(AppRadius.panel),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: AppRadius.iconSize, color: AppColors.textSecondary),
              const SizedBox(height: AppSpacing.sm),
              Text(label, style: AppTypography.caption(AppColors.textSecondary)),
              const SizedBox(height: AppSpacing.xs),
              Text(
                value ?? 'Not reported',
                style: AppTypography.body(AppColors.textPrimary),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NotFoundView extends StatelessWidget {
  const _NotFoundView({
    required this.airport,
    required this.distanceKm,
    required this.onSelectAirport,
  });

  final Airport airport;
  final double? distanceKm;
  final ValueChanged<Airport> onSelectAirport;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.sm,
        AppSpacing.lg,
        AppSpacing.xxxl,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _AirportHeader(
            airport: airport,
            distanceKm: distanceKm,
            onSelectAirport: onSelectAirport,
          ),
          const SizedBox(height: AppSpacing.xxxl),
          Center(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.xxl),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.flight_outlined,
                    size: 40,
                    color: AppColors.textSecondary,
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  Text(
                    'No current observation for this station',
                    style: AppTypography.title(AppColors.textPrimary),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    // A silent station is normal — this is not an outage.
                    'Stations report every 30-60 minutes and can go quiet '
                    'temporarily. Try again shortly, or pick another airport.',
                    style: AppTypography.label(AppColors.textSecondary),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
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
            const Icon(
              Icons.cloud_off,
              size: 40,
              color: AppColors.textPrimary,
            ),
            const SizedBox(height: AppSpacing.lg),
            Text(
              "Couldn't load the observation",
              style: AppTypography.title(AppColors.textPrimary),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              message,
              style: AppTypography.label(AppColors.textPrimary),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.xl),
            TextButton(
              onPressed: onRetry,
              style: TextButton.styleFrom(
                foregroundColor: AppColors.textPrimary,
                side: const BorderSide(color: AppColors.textPrimary),
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.xxl,
                  vertical: AppSpacing.md,
                ),
              ),
              child: Text(
                'Try again',
                style: AppTypography.body(AppColors.textPrimary),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Opens the airport picker as a modal bottom sheet, listing all 14
/// bundled stations. Mirrors `showLocationSearch`'s shape.
Future<void> showAirportPicker(
  BuildContext context,
  Airport selected,
  ValueChanged<Airport> onSelect,
) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: AppColors.bgBase,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.panel)),
    ),
    builder: (_) => _AirportPickerSheet(selected: selected, onSelect: onSelect),
  );
}

class _AirportPickerSheet extends StatelessWidget {
  const _AirportPickerSheet({required this.selected, required this.onSelect});

  final Airport selected;
  final ValueChanged<Airport> onSelect;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(bottom: AppSpacing.lg),
                decoration: BoxDecoration(
                  color: AppColors.divider,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Text('Choose an airport', style: AppTypography.title(AppColors.textPrimary)),
            const SizedBox(height: AppSpacing.md),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final airport in indianAirports)
                    _AirportRow(
                      airport: airport,
                      selected: airport.icao == selected.icao,
                      onTap: () {
                        Navigator.of(context).pop();
                        onSelect(airport);
                      },
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AirportRow extends StatelessWidget {
  const _AirportRow({
    required this.airport,
    required this.selected,
    required this.onTap,
  });

  final Airport airport;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: '${airport.city}, ${airport.icao}',
      child: ExcludeSemantics(
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppRadius.menu),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.sm,
              vertical: AppSpacing.md,
            ),
            child: Row(
              children: [
                Icon(
                  selected
                      ? Icons.radio_button_checked
                      : Icons.radio_button_unchecked,
                  size: AppRadius.iconSize,
                  color: selected ? AppColors.accent : AppColors.textSecondary,
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Text(
                    '${airport.city} (${airport.icao})',
                    style: AppTypography.body(AppColors.textPrimary),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
