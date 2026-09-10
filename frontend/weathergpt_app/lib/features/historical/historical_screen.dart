import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_radius.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';
import '../../data/historical_api.dart';
import '../../shared/error_message.dart';
import '../../shared/widgets/round_icon_button.dart';
import '../home/home_controller.dart';
import '../home/weather_label.dart';
import '../shell/app_drawer.dart';
import 'historical_controller.dart';

/// ERA5 reanalysis (ECMWF) readings for a small, fixed seed of locations
/// and sample dates.
///
/// Deliberately discovers what is available from `/historical/available`
/// rather than guessing a location/date pair — see the docs on
/// `HistoricalController` and `HistoricalApi`. The point of this screen is
/// the same-month-day comparison (e.g. two 15 Julys a year apart), which a
/// plain "today's forecast" screen has no way to show.
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
    // by then. Fires the coverage load exactly once, whatever Home ends up
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
      HistoricalCoverageEmpty() => RefreshIndicator(
          onRefresh: () =>
              ref.read(historicalControllerProvider.notifier).retry(),
          color: AppColors.textPrimary,
          backgroundColor: AppColors.surfaceRaised,
          child: const _EmptyCoverageView(),
        ),
      HistoricalNotFound(:final coverage, :final location, :final date) =>
        RefreshIndicator(
          onRefresh: () =>
              ref.read(historicalControllerProvider.notifier).retry(),
          color: AppColors.textPrimary,
          backgroundColor: AppColors.surfaceRaised,
          child: _NotFoundView(
            coverage: coverage,
            location: location,
            date: date,
            onSelectLocation: (l) =>
                ref.read(historicalControllerProvider.notifier).selectLocation(l),
            onSelectDate: (d) =>
                ref.read(historicalControllerProvider.notifier).selectDate(d),
          ),
        ),
      HistoricalLoaded() => _LoadedView(state: state as HistoricalLoaded),
    };
  }
}

/// Location name, "Change" picker, current date, and "Change date" picker —
/// shown above both the loaded reading and the not-found state, since both
/// know which location and date are selected. Both pickers are driven
/// entirely by [coverage]/[location].dates — never a hardcoded list.
class _SelectionHeader extends StatelessWidget {
  const _SelectionHeader({
    required this.coverage,
    required this.location,
    required this.date,
    required this.onSelectLocation,
    required this.onSelectDate,
  });

  final List<HistoricalCoverage> coverage;
  final HistoricalCoverage location;
  final String date;
  final ValueChanged<HistoricalCoverage> onSelectLocation;
  final ValueChanged<String> onSelectDate;

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
                location.locationName,
                style: AppTypography.title(AppColors.textPrimary),
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            _ChangeButton(
              label: 'Change',
              semanticsLabel: 'Choose a different location',
              onPressed: () =>
                  _showLocationPicker(context, coverage, location, onSelectLocation),
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
              onPressed: () =>
                  _showDatePicker(context, location.dates, date, onSelectDate),
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

Future<void> _showLocationPicker(
  BuildContext context,
  List<HistoricalCoverage> coverage,
  HistoricalCoverage selected,
  ValueChanged<HistoricalCoverage> onSelect,
) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: AppColors.bgBase,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.panel)),
    ),
    builder: (_) => _PickerSheet<HistoricalCoverage>(
      title: 'Choose a location',
      items: coverage,
      isSelected: (item) => item.locationName == selected.locationName,
      labelFor: (item) => item.locationName,
      onSelect: onSelect,
    ),
  );
}

Future<void> _showDatePicker(
  BuildContext context,
  List<String> dates,
  String selected,
  ValueChanged<String> onSelect,
) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: AppColors.bgBase,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.panel)),
    ),
    builder: (_) => _PickerSheet<String>(
      title: 'Choose a date',
      items: dates,
      isSelected: (item) => item == selected,
      labelFor: formatHistoricalDate,
      onSelect: onSelect,
    ),
  );
}

/// A modal bottom sheet listing [items], one radio row each. Generic over
/// [T] so the same sheet serves both the location and date pickers, which
/// mirror `AviationScreen`'s `showAirportPicker` in shape.
class _PickerSheet<T> extends StatelessWidget {
  const _PickerSheet({
    required this.title,
    required this.items,
    required this.isSelected,
    required this.labelFor,
    required this.onSelect,
  });

  final String title;
  final List<T> items;
  final bool Function(T item) isSelected;
  final String Function(T item) labelFor;
  final ValueChanged<T> onSelect;

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
            Text(title, style: AppTypography.title(AppColors.textPrimary)),
            const SizedBox(height: AppSpacing.md),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final item in items)
                    _PickerRow(
                      label: labelFor(item),
                      selected: isSelected(item),
                      onTap: () {
                        Navigator.of(context).pop();
                        onSelect(item);
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

class _PickerRow extends StatelessWidget {
  const _PickerRow({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: label,
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
                  child: Text(label, style: AppTypography.body(AppColors.textPrimary)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
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
              coverage: state.coverage,
              location: state.location,
              date: state.date,
              onSelectLocation: (l) =>
                  ref.read(historicalControllerProvider.notifier).selectLocation(l),
              onSelectDate: (d) =>
                  ref.read(historicalControllerProvider.notifier).selectDate(d),
            ),
            const SizedBox(height: AppSpacing.xl),
            _StatsGrid(reading: reading),
            const SizedBox(height: AppSpacing.sm),
            _PrecipTile(precipMm: reading.precipMm),
            if (state.hasComparison) ...[
              const SizedBox(height: AppSpacing.xl),
              _ComparisonSection(
                date: state.date,
                reading: reading,
                comparisonDate: state.comparisonDate!,
                comparisonReading: state.comparisonReading!,
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

  final HistoricalReading reading;

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
                value: formatHistoricalTempC(reading.temp2mC),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: _StatTile(
                icon: Icons.water_drop_outlined,
                label: 'Dew point',
                value: formatHistoricalTempC(reading.dewpoint2mC),
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        Row(
          children: [
            Expanded(
              child: _StatTile(
                icon: Icons.speed_outlined,
                label: 'Pressure (MSLP)',
                value: formatPressureHpa(reading.mslpHpa),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: _StatTile(
                icon: Icons.air,
                label: 'Wind',
                value: formatHistoricalWind(
                  reading.windDirection10mDeg,
                  reading.windSpeed10mKmh,
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

/// Full-width, so the hourly caveat sits directly under the number it
/// qualifies rather than in a footnote someone can miss. This is
/// deliberately the loudest label on the screen: mislabelling ERA5's
/// 1-hour accumulation as a daily total would overstate a monsoon figure by
/// more than an order of magnitude — see the doc on
/// `HistoricalReading.precipMm`.
class _PrecipTile extends StatelessWidget {
  const _PrecipTile({required this.precipMm});

  final double? precipMm;

  @override
  Widget build(BuildContext context) {
    final value = formatHourlyPrecipMm(precipMm);
    return Semantics(
      label:
          'Precipitation, one hour ending 12:00 UTC: ${value ?? 'not reported'}',
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
                '1-hour accumulation ending 12:00 UTC — not a daily total',
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
/// reading against the other reading at the same location sharing its
/// month-and-day, with the temperature difference stated plainly. Only
/// rendered by the caller when `HistoricalLoaded.hasComparison` is true —
/// this widget never invents a pairing of its own.
class _ComparisonSection extends StatelessWidget {
  const _ComparisonSection({
    required this.date,
    required this.reading,
    required this.comparisonDate,
    required this.comparisonReading,
  });

  final String date;
  final HistoricalReading reading;
  final String comparisonDate;
  final HistoricalReading comparisonReading;

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
                child: _ComparisonColumn(date: date, tempC: reading.temp2mC),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: _ComparisonColumn(
                  date: comparisonDate,
                  tempC: comparisonReading.temp2mC,
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
    final currentTemp = reading.temp2mC;
    final otherTemp = comparisonReading.temp2mC;
    if (currentTemp == null || otherTemp == null) return null;

    final currentLabel = formatHistoricalDate(date);
    final otherLabel = formatHistoricalDate(comparisonDate);
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

class _EmptyCoverageView extends StatelessWidget {
  const _EmptyCoverageView();

  @override
  Widget build(BuildContext context) {
    // An empty coverage list is a real, expected state — the seed table is
    // truncated by the backend's own test suite and re-seeding is
    // expensive — never an error.
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
              Icons.history_toggle_off,
              size: 40,
              color: AppColors.textSecondary,
            ),
            const SizedBox(height: AppSpacing.lg),
            Text(
              'No historical data loaded',
              style: AppTypography.title(AppColors.textPrimary),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'The ERA5 archive has no seeded locations right now. Pull to '
              'refresh once it does.',
              style: AppTypography.label(AppColors.textSecondary),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _NotFoundView extends StatelessWidget {
  const _NotFoundView({
    required this.coverage,
    required this.location,
    required this.date,
    required this.onSelectLocation,
    required this.onSelectDate,
  });

  final List<HistoricalCoverage> coverage;
  final HistoricalCoverage location;
  final String date;
  final ValueChanged<HistoricalCoverage> onSelectLocation;
  final ValueChanged<String> onSelectDate;

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
          _SelectionHeader(
            coverage: coverage,
            location: location,
            date: date,
            onSelectLocation: onSelectLocation,
            onSelectDate: onSelectDate,
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
                    'No ERA5 reading for this date',
                    style: AppTypography.title(AppColors.textPrimary),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    'Try a different date or location from the pickers above.',
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

/// Mean sea-level pressure, rounded to the nearest hPa.
String? formatPressureHpa(double? hpa) =>
    hpa == null ? null : '${hpa.round()} hPa';

/// ERA5's 1-hour accumulation ending at 12:00 UTC, to two decimal places —
/// NOT a daily total. See the doc on `HistoricalReading.precipMm`.
String? formatHourlyPrecipMm(double? mm) =>
    mm == null ? null : '${mm.toStringAsFixed(2)} mm';

/// Cardinal direction (via `windDirectionLabel`) + speed in km/h — already
/// the unit ERA5 reports in, so unlike Aviation's METAR knots this needs no
/// conversion. Direction and speed are independently nullable, so each
/// degrades on its own rather than either hiding a value the other has.
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
