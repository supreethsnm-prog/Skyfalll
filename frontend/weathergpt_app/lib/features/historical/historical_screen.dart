import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_radius.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';
import '../../data/geocoding_api.dart';
import '../../data/historical_api.dart';
import '../../shared/error_message.dart';
import '../../shared/widgets/round_icon_button.dart';
import '../home/home_controller.dart';
import '../home/weather_label.dart';
import '../home/widgets/location_search_sheet.dart';
import '../shell/app_drawer.dart';
import 'historical_controller.dart';

/// Open-Meteo Archive (ECMWF ERA5/ERA5-Land reanalysis) readings for any
/// location on Earth and any date from 1940 to a few days ago.
///
/// The point of this screen is the "same day, different year" comparison
/// (e.g. two 15 Julys a year apart), which a plain "today's forecast"
/// screen has no way to show. "Change"/"Change date" reuse Home's own
/// location search and a standard Material date picker rather than
/// offering a small fixed list — see `HistoricalController`.
class HistoricalScreen extends ConsumerStatefulWidget {
  const HistoricalScreen({super.key});

  @override
  ConsumerState<HistoricalScreen> createState() => _HistoricalScreenState();
}

class _HistoricalScreenState extends ConsumerState<HistoricalScreen> {
  /// Whether the initial load (with or without Home's location as a
  /// preference) has already been issued, so a later rebuild does not
  /// re-issue it, while Home resolving its own location AFTER this screen
  /// opened is still picked up exactly once. Mirrors `AviationScreen`.
  bool _started = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeStart());
  }

  void _maybeStart() {
    if (_started) return;
    final homeState = ref.read(homeControllerProvider);
    if (homeState is HomeLoading) {
      // Home may not have resolved a location yet (this route opened first
      // via a deep link or hot restart, say). Kick it off; the ref.listen
      // in build() picks up whatever it settles on.
      ref.read(homeControllerProvider.notifier).loadInitial();
      return;
    }
    _started = true;
    ref.read(historicalControllerProvider.notifier).load(
          preferredLocation:
              homeState is HomeLoaded ? homeState.location : null,
        );
  }

  @override
  Widget build(BuildContext context) {
    // Catches Home settling (or failing) AFTER this screen's first frame —
    // the initState callback above only covers Home already being resolved
    // by then. Fires the initial load exactly once, whatever Home ends up
    // doing, so this screen is never left waiting on a load nothing asked
    // for.
    ref.listen<HomeUiState>(homeControllerProvider, (previous, next) {
      if (_started || next is HomeLoading) return;
      _started = true;
      ref.read(historicalControllerProvider.notifier).load(
            preferredLocation: next is HomeLoaded ? next.location : null,
          );
    });

    final state = ref.watch(historicalControllerProvider);

    return Scaffold(
      backgroundColor: AppColors.bgBase,
      drawer: const AppDrawer(activeRoute: '/historical'),
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
                    'Historical',
                    style: AppTypography.title(AppColors.textPrimary),
                  ),
                ],
              ),
            ),
            Expanded(child: _Body(state: state)),
          ],
        ),
      ),
    );
  }
}

class _Body extends ConsumerWidget {
  const _Body({required this.state});

  final HistoricalUiState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return switch (state) {
      HistoricalLoading() => const Center(
          child: CircularProgressIndicator(color: AppColors.textPrimary),
        ),
      HistoricalError(:final error) => RefreshIndicator(
          onRefresh: () =>
              ref.read(historicalControllerProvider.notifier).retry(),
          color: AppColors.textPrimary,
          backgroundColor: AppColors.surfaceRaised,
          child: _ErrorView(
            message: errorMessageFor(error),
            onRetry: () =>
                ref.read(historicalControllerProvider.notifier).retry(),
          ),
        ),
      HistoricalNotFound(:final location, :final date) => RefreshIndicator(
          onRefresh: () =>
              ref.read(historicalControllerProvider.notifier).retry(),
          color: AppColors.textPrimary,
          backgroundColor: AppColors.surfaceRaised,
          child: _NotFoundView(location: location, date: date),
        ),
      HistoricalLoaded() => _LoadedView(state: state as HistoricalLoaded),
    };
  }
}

/// Location name, "Change" (Home's own location search), current date, and
/// "Change date" (a standard Material date picker bounded to the archive's
/// real coverage) — shown above both the loaded reading and the not-found
/// state, since both know which location and date are selected.
class _SelectionHeader extends StatelessWidget {
  const _SelectionHeader({
    required this.location,
    required this.date,
    required this.onChangeLocation,
    required this.onChangeDate,
  });

  final GeocodeResult location;
  final String date;
  final VoidCallback onChangeLocation;
  final VoidCallback onChangeDate;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Text(
                location.displayName,
                style: AppTypography.title(AppColors.textPrimary),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            _ChangeButton(
              label: 'Change',
              semanticsLabel: 'Choose a different location',
              onPressed: onChangeLocation,
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Text(
                formatHistoricalDate(date),
                style: AppTypography.label(AppColors.textSecondary),
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            _ChangeButton(
              label: 'Change date',
              semanticsLabel: 'Choose a different date',
              onPressed: onChangeDate,
            ),
          ],
        ),
      ],
    );
  }
}

class _ChangeButton extends StatelessWidget {
  const _ChangeButton({
    required this.label,
    required this.semanticsLabel,
    required this.onPressed,
  });

  final String label;
  final String semanticsLabel;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: semanticsLabel,
      child: ExcludeSemantics(
        child: TextButton(
          onPressed: onPressed,
          style: TextButton.styleFrom(
            foregroundColor: AppColors.textPrimary,
            side: const BorderSide(color: AppColors.divider),
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.lg,
              vertical: AppSpacing.sm,
            ),
          ),
          child: Text(label, style: AppTypography.body(AppColors.textPrimary)),
        ),
      ),
    );
  }
}

/// Opens Home's own location search sheet, rewired so a chosen place
/// selects it for Historical rather than changing Home's own location.
/// "Use my location" is hidden — a fixed historical date has no
/// "current position" concept.
void _changeLocation(BuildContext context, WidgetRef ref) {
  showLocationSearch(
    context,
    onSelected: (result) =>
        ref.read(historicalControllerProvider.notifier).selectLocation(result),
    showUseMyLocation: false,
  );
}

/// A standard Material date picker bounded to what the Open-Meteo Archive
/// actually serves (1940-01-01 through a few days before today — see
/// `historicalDateBounds`), so no offered date can 404.
Future<void> _changeDate(
  BuildContext context,
  WidgetRef ref,
  String currentDate,
) async {
  final bounds = historicalDateBounds();
  final initial = _parseIsoDate(currentDate) ?? bounds.last;
  final clampedInitial = initial.isBefore(bounds.first)
      ? bounds.first
      : (initial.isAfter(bounds.last) ? bounds.last : initial);

  final picked = await showDatePicker(
    context: context,
    firstDate: bounds.first,
    lastDate: bounds.last,
    initialDate: clampedInitial,
  );
  if (picked == null) return;
  await ref
      .read(historicalControllerProvider.notifier)
      .selectDate(isoDateString(picked));
}

DateTime? _parseIsoDate(String isoDate) {
  final parts = isoDate.split('-');
  if (parts.length != 3) return null;
  final y = int.tryParse(parts[0]);
  final m = int.tryParse(parts[1]);
  final d = int.tryParse(parts[2]);
  if (y == null || m == null || d == null) return null;
  return DateTime(y, m, d);
}

class _LoadedView extends ConsumerWidget {
  const _LoadedView({required this.state});

  final HistoricalLoaded state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reading = state.reading;

    return RefreshIndicator(
      onRefresh: () => ref.read(historicalControllerProvider.notifier).retry(),
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
            _SelectionHeader(
              location: state.location,
              // The backend's own `reading.date` is authoritative for
              // display — it is what the returned figures actually
              // describe — rather than `state.date`, the requested date
              // used only to drive the next fetch/picker.
              date: reading.date,
              onChangeLocation: () => _changeLocation(context, ref),
              onChangeDate: () => _changeDate(context, ref, state.date),
            ),
            const SizedBox(height: AppSpacing.xl),
            _StatsGrid(reading: reading),
            const SizedBox(height: AppSpacing.sm),
            _PrecipTile(precipMm: reading.precipSumMm),
            if (state.hasComparison) ...[
              const SizedBox(height: AppSpacing.xl),
              _ComparisonSection(
                date: reading.date,
                reading: reading,
                comparisonReading: state.previousYearReading!,
              ),
            ],
            const SizedBox(height: AppSpacing.xl),
            Text(
              'Source: ECMWF ERA5 reanalysis',
              style: AppTypography.caption(AppColors.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatsGrid extends StatelessWidget {
  const _StatsGrid({required this.reading});

  final ArchiveReading reading;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _StatTile(
                icon: Icons.thermostat,
                label: 'Max temperature',
                value: formatHistoricalTempC(reading.tempMaxC),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: _StatTile(
                icon: Icons.thermostat_outlined,
                label: 'Min temperature',
                value: formatHistoricalTempC(reading.tempMinC),
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        Row(
          children: [
            Expanded(
              child: _StatTile(
                icon: Icons.thermostat,
                label: 'Mean temperature',
                value: formatHistoricalTempC(reading.tempMeanC),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: _StatTile(
                icon: Icons.air,
                label: 'Max wind',
                value: formatHistoricalWind(
                  reading.windDirectionDominantDeg,
                  reading.windSpeedMaxKmh,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
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

/// Full-width daily precipitation total from the Open-Meteo Archive
/// (`precipitation_sum`) — a real daily sum, unlike the old ERA5-seed
/// path's 1-hour accumulation, so this tile no longer needs to caveat what
/// the number means.
class _PrecipTile extends StatelessWidget {
  const _PrecipTile({required this.precipMm});

  final double? precipMm;

  @override
  Widget build(BuildContext context) {
    final value = formatDailyPrecipMm(precipMm);
    return Semantics(
      label: 'Daily precipitation total: ${value ?? 'not reported'}',
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
              Row(
                children: [
                  const Icon(
                    Icons.water_drop,
                    size: AppRadius.iconSize,
                    color: AppColors.textSecondary,
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Text('Precipitation', style: AppTypography.caption(AppColors.textSecondary)),
                ],
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                value ?? 'Not reported',
                style: AppTypography.title(AppColors.textPrimary),
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                'Daily total',
                style: AppTypography.caption(AppColors.textSecondary),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The comparison that is the actual point of this screen: the selected
/// reading against the reading for the same calendar date one year
/// earlier, with the temperature difference stated plainly. Only rendered
/// by the caller when `HistoricalLoaded.hasComparison` is true.
class _ComparisonSection extends StatelessWidget {
  const _ComparisonSection({
    required this.date,
    required this.reading,
    required this.comparisonReading,
  });

  final String date;
  final ArchiveReading reading;
  final ArchiveReading comparisonReading;

  @override
  Widget build(BuildContext context) {
    final diffText = _diffText();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: AppColors.surfaceRaised,
        borderRadius: BorderRadius.circular(AppRadius.panel),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Same day, different year',
            style: AppTypography.caption(AppColors.textSecondary),
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              Expanded(
                child: _ComparisonColumn(date: date, tempC: reading.tempMeanC),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: _ComparisonColumn(
                  date: comparisonReading.date,
                  tempC: comparisonReading.tempMeanC,
                ),
              ),
            ],
          ),
          // Only stated when both temperatures are actually present — an
          // absent reading must never be treated as 0 in a subtraction.
          if (diffText != null) ...[
            const SizedBox(height: AppSpacing.md),
            Text(diffText, style: AppTypography.body(AppColors.textPrimary)),
          ],
        ],
      ),
    );
  }

  String? _diffText() {
    final currentTemp = reading.tempMeanC;
    final otherTemp = comparisonReading.tempMeanC;
    if (currentTemp == null || otherTemp == null) return null;

    final currentLabel = formatHistoricalDate(date);
    final otherLabel = formatHistoricalDate(comparisonReading.date);
    final diff = currentTemp - otherTemp;

    if (diff.abs() < 0.05) {
      return '$currentLabel was about the same temperature as $otherLabel.';
    }
    final warmerLabel = diff > 0 ? currentLabel : otherLabel;
    final coolerLabel = diff > 0 ? otherLabel : currentLabel;
    return '$warmerLabel was ${diff.abs().toStringAsFixed(1)}°C warmer than '
        '$coolerLabel.';
  }
}

class _ComparisonColumn extends StatelessWidget {
  const _ComparisonColumn({required this.date, required this.tempC});

  final String date;
  final double? tempC;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          formatHistoricalDate(date),
          style: AppTypography.caption(AppColors.textSecondary),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          formatHistoricalTempC(tempC) ?? 'Not reported',
          style: AppTypography.title(AppColors.textPrimary),
        ),
      ],
    );
  }
}

class _NotFoundView extends ConsumerWidget {
  const _NotFoundView({required this.location, required this.date});

  final GeocodeResult location;
  final String date;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
          _SelectionHeader(
            location: location,
            date: date,
            onChangeLocation: () => _changeLocation(context, ref),
            onChangeDate: () => _changeDate(context, ref, date),
          ),
          const SizedBox(height: AppSpacing.xxxl),
          Center(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.xxl),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.event_busy_outlined,
                    size: 40,
                    color: AppColors.textSecondary,
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  Text(
                    'No archive reading for this date',
                    style: AppTypography.title(AppColors.textPrimary),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    'Try a different date or location above.',
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
              "Couldn't load historical data",
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

/// °C to one decimal place — ERA5's reanalysis values carry more precision
/// than a live METAR, so this screen keeps a decimal where Aviation rounds
/// to a whole degree. Null in, null out: a missing reading must never
/// render as "0.0°C".
String? formatHistoricalTempC(double? celsius) =>
    celsius == null ? null : '${celsius.toStringAsFixed(1)}°C';

/// A daily precipitation total (`precipitation_sum`), to one decimal
/// place. Unlike the old ERA5-seed path, this IS a real daily total — no
/// caveat needed.
String? formatDailyPrecipMm(double? mm) =>
    mm == null ? null : '${mm.toStringAsFixed(1)} mm';

/// Cardinal direction (via `windDirectionLabel`) + speed in km/h — already
/// the unit Open-Meteo reports in, so unlike Aviation's METAR knots this
/// needs no conversion. Direction and speed are independently nullable, so
/// each degrades on its own rather than either hiding a value the other
/// has.
String? formatHistoricalWind(double? directionDeg, double? speedKmh) {
  final direction =
      directionDeg == null ? null : windDirectionLabel(directionDeg);
  final speed = speedKmh == null ? null : '${speedKmh.round()} km/h';
  if (direction != null && speed != null) return '$direction at $speed';
  return speed ?? direction;
}

const _monthNames = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', //
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

/// "2024-07-15" -> "15 Jul 2024". Pure string parsing of the ISO date the
/// backend sends — deliberately NOT `DateTime.parse`+`DateTime.now()`
/// dependent, since these are historical calendar dates with no time-of-day
/// or timezone component to resolve against the current clock. Falls back
/// to the raw string for anything that does not look like `YYYY-MM-DD`
/// rather than throwing on an unexpected shape.
String formatHistoricalDate(String isoDate) {
  final parts = isoDate.split('-');
  if (parts.length != 3) return isoDate;
  final month = int.tryParse(parts[1]);
  final day = int.tryParse(parts[2]);
  if (month == null || day == null || month < 1 || month > 12) return isoDate;
  return '$day ${_monthNames[month - 1]} ${parts[0]}';
}
