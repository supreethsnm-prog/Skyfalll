import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_radius.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';
import '../../data/advisory_api.dart';
import '../../data/alerts_api.dart';
import '../../data/geocoding_api.dart';
import '../../data/weather_api.dart';
import '../../shared/error_message.dart';
import '../../shared/widgets/glass_panel.dart';
import '../../shared/widgets/round_icon_button.dart';
import '../../shared/widgets/weather_icon.dart';
import '../chat/chat_controller.dart';
import '../home/home_controller.dart';
import '../home/widgets/alert_banner.dart';
import '../shell/app_drawer.dart';
import '../../l10n/app_strings.dart';
import 'advisory_controller.dart';
import 'risk_band.dart';

/// Agriculture and urban advisories for the location Home is currently
/// showing — the app's one screen dedicated to the problem statement it
/// was actually built for (a weather advisory service for the Ministry of
/// Earth Sciences), so it is built as a first-class screen rather than a
/// debug view of two JSON endpoints.
///
/// Deliberately reads its location from [homeControllerProvider] instead
/// of resolving its own — Home already owns "where is the user", and a
/// second, independently-resolved location here could disagree with it.
class AdvisoryScreen extends ConsumerStatefulWidget {
  const AdvisoryScreen({super.key});

  @override
  ConsumerState<AdvisoryScreen> createState() => _AdvisoryScreenState();
}

class _AdvisoryScreenState extends ConsumerState<AdvisoryScreen> {
  /// The location the controller was last asked to load, so a rebuild
  /// (e.g. from an unrelated provider change) does not re-issue the same
  /// request, and so a genuine location change from Home IS re-issued.
  GeocodeResult? _requestedFor;
  String? _crop;

  @override
  void initState() {
    super.initState();
    // Home may already be loaded by the time this screen opens (the usual
    // case — Home loads on app boot). Fired after the first frame so the
    // controller's state change never lands during a build.
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeLoadFromHome());
  }

  void _maybeLoadFromHome() {
    final homeState = ref.read(homeControllerProvider);
    if (homeState is HomeLoaded) {
      _loadFor(homeState.location);
      return;
    }

    // Home has not resolved a location yet. Normally it has — it is the
    // launch route — but arriving here first (a hot restart on this
    // route, or a deep link) would otherwise leave this screen spinning
    // forever, waiting on a load nothing had asked for. Kicking Home off
    // keeps it the single owner of "where is the user" rather than
    // resolving a second location here; the ref.listen below picks the
    // result up.
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
    ref.read(advisoryControllerProvider.notifier).load(location, crop: _crop);
  }

  void _selectCrop(String? crop) {
    if (_crop == crop) return;
    setState(() => _crop = crop);
    ref.read(advisoryControllerProvider.notifier).changeCrop(crop);
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
    final advisoryState = ref.watch(advisoryControllerProvider);
    final s = ref.watch(uiStringsProvider);

    return Scaffold(
      backgroundColor: AppColors.bgBase,
      drawer: const AppDrawer(activeRoute: '/advisories'),
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
                      tooltip: s.openMenu,
                      onPressed: () => Scaffold.of(context).openDrawer(),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Text(
                    s.advisories,
                    style: AppTypography.title(AppColors.textPrimary),
                  ),
                ],
              ),
            ),
            Expanded(
              child: _Body(
                homeState: homeState,
                advisoryState: advisoryState,
                crop: _crop,
                onSelectCrop: _selectCrop,
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
    required this.advisoryState,
    required this.crop,
    required this.onSelectCrop,
  });

  final HomeUiState homeState;
  final AdvisoryUiState advisoryState;
  final String? crop;
  final ValueChanged<String?> onSelectCrop;

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

    return switch (advisoryState) {
      AdvisoryLoading() => const Center(
          child: CircularProgressIndicator(color: AppColors.textPrimary),
        ),
      AdvisoryError(:final error) => RefreshIndicator(
          onRefresh: () =>
              ref.read(advisoryControllerProvider.notifier).retry(),
          color: AppColors.textPrimary,
          backgroundColor: AppColors.surfaceRaised,
          child: _ErrorView(
            message: errorMessageFor(error),
            onRetry: () =>
                ref.read(advisoryControllerProvider.notifier).retry(),
          ),
        ),
      AdvisoryLoaded() => _LoadedView(
          state: advisoryState as AdvisoryLoaded,
          crop: crop,
          onSelectCrop: onSelectCrop,
        ),
    };
  }
}

class _LoadedView extends ConsumerWidget {
  const _LoadedView({
    required this.state,
    required this.crop,
    required this.onSelectCrop,
  });

  final AdvisoryLoaded state;
  final String? crop;
  final ValueChanged<String?> onSelectCrop;

  /// Alerts from both endpoints, deduplicated by id. Both `/advisory/urban`
  /// and `/advisory/agriculture` filter the same nationwide feed through
  /// the same 50km radius and hazard keywords for this same location, so in
  /// practice they return the same set — this just guards against the two
  /// ever drifting apart without showing the same warning twice.
  List<AlertSummary> get _alerts {
    final seen = <int>{};
    final merged = <AlertSummary>[];
    for (final alert in [...state.urban.activeAlerts, ...state.agriculture.activeAlerts]) {
      if (seen.add(alert.id)) merged.add(alert);
    }
    return merged;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(uiStringsProvider);
    return RefreshIndicator(
      onRefresh: () => ref.read(advisoryControllerProvider.notifier).retry(),
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
            Text(
              state.location.displayName,
              style: AppTypography.body(AppColors.textSecondary),
            ),
            const SizedBox(height: AppSpacing.lg),
            Text(s.urbanRisk, style: AppTypography.label(AppColors.textPrimary)),
            const SizedBox(height: AppSpacing.sm),
            _UrbanRiskRow(riskSummary: state.urban.riskSummary),
            const SizedBox(height: AppSpacing.xxl),
            // Headed "Advisories", not "Agriculture": the list below
            // merges both endpoints' advice, and sitting it under an
            // "Agriculture" heading attributed urban warnings — waterlogged
            // underpasses, loose hoardings — to farming. The crop chips
            // filter only the agriculture half, so they carry their own
            // label rather than heading the whole section.
            Text(s.advisories, style: AppTypography.label(AppColors.textPrimary)),
            const SizedBox(height: AppSpacing.md),
            Text(
              s.filterCropAdvice,
              style: AppTypography.caption(AppColors.textSecondary),
            ),
            const SizedBox(height: AppSpacing.sm),
            _CropChips(selected: crop, onSelected: onSelectCrop),
            const SizedBox(height: AppSpacing.md),
            // Both endpoints' advisory strings are complementary, plain-
            // English sentences of advice for the SAME place — splitting
            // them into two separate lists would make the user read two
            // feeds to get one picture, so they are unified here into a
            // single readable advisory list rather than mirroring the
            // backend's two-endpoint split in the UI.
            _AdvisoryList(
              advisories: [...state.urban.advisories, ...state.agriculture.advisories],
            ),
            if (_alerts.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.xxl),
              for (final alert in _alerts) ...[
                AlertBanner(alert: alert),
                const SizedBox(height: AppSpacing.md),
              ],
            ],
            const SizedBox(height: AppSpacing.xxl),
            _BasedOnSection(days: state.urban.forecastBasis),
          ],
        ),
      ),
    );
  }
}

/// Waterlogging / heat / wind, each coloured with the app's one existing
/// severity ramp via [capSeverityForRiskBand] — see that function for why
/// an unrecognised band (including the backend's own `UNKNOWN`) must NOT
/// be coloured as if it were a real, known-safe band.
class _UrbanRiskRow extends ConsumerWidget {
  const _UrbanRiskRow({required this.riskSummary});

  final UrbanRiskSummary riskSummary;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(uiStringsProvider);
    return Row(
      children: [
        Expanded(
          child: _RiskTile(
            icon: Icons.water_damage_outlined,
            label: s.waterlogging,
            band: riskSummary.waterloggingRisk,
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: _RiskTile(
            icon: Icons.thermostat,
            label: s.heat,
            band: riskSummary.heatRisk,
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: _RiskTile(
            icon: Icons.air,
            label: s.wind,
            band: riskSummary.windRisk,
          ),
        ),
      ],
    );
  }
}

class _RiskTile extends ConsumerWidget {
  const _RiskTile({
    super.key,
    required this.icon,
    required this.label,
    required this.band,
  });

  final IconData icon;
  final String label;
  final String band;

  static String _titleCase(String value) => value.isEmpty
      ? value
      : '${value[0]}${value.substring(1).toLowerCase()}';

  static String _localizedBand(String band, AppStrings s) {
    switch (band.toUpperCase()) {
      case 'LOW':
        return s.riskLow;
      case 'MODERATE':
        return s.riskModerate;
      case 'HIGH':
        return s.riskHigh;
      case 'SEVERE':
      case 'EXTREME':
        return s.riskExtreme;
      default:
        return _titleCase(band);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(uiStringsProvider);
    final capSeverity = capSeverityForRiskBand(band);
    // No mapping (including the backend's own UNKNOWN) renders as a plain,
    // neutral tile — never as one of the four real severity colours, which
    // would misrepresent an unknown risk as a known one.
    final background = capSeverity == null
        ? AppColors.surfaceRaised
        : AppColors.alertSeverity(capSeverity);
    final foreground = capSeverity == null
        ? AppColors.textPrimary
        : AppColors.onAlertSeverity(capSeverity);
    final displayedBand = _localizedBand(band, s);

    return Semantics(
      label: '$label risk: $displayedBand',
      child: ExcludeSemantics(
        child: Container(
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            color: background,
            borderRadius: BorderRadius.circular(AppRadius.panel),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: AppRadius.iconSize, color: foreground),
              const SizedBox(height: AppSpacing.sm),
              Text(label, style: AppTypography.caption(foreground)),
              const SizedBox(height: AppSpacing.xs),
              Text(displayedBand, style: AppTypography.body(foreground)),
            ],
          ),
        ),
      ),
    );
  }
}

class _CropChips extends ConsumerWidget {
  const _CropChips({super.key, required this.selected, required this.onSelected});

  final String? selected;
  final ValueChanged<String?> onSelected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(uiStringsProvider);
    final cropOptions = <(String? value, String label)>[
      (null, s.allCrops),
      ('rice', s.rice),
      ('wheat', s.wheat),
      ('cotton', s.cotton),
      ('sugarcane', s.sugarcane),
    ];
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final (value, label) in cropOptions) ...[
            _CropChip(
              label: label,
              selected: selected == value,
              onTap: () => onSelected(value),
            ),
            const SizedBox(width: AppSpacing.sm),
          ],
        ],
      ),
    );
  }
}

class _CropChip extends StatelessWidget {
  const _CropChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final foreground =
        selected ? AppColors.textPrimary : AppColors.textSecondary;

    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: ExcludeSemantics(
        child: Material(
          color: selected ? AppColors.accent : AppColors.surfaceRaised,
          borderRadius: BorderRadius.circular(AppRadius.composerHeight / 2),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.lg,
                vertical: AppSpacing.sm,
              ),
              child: Text(label, style: AppTypography.label(foreground)),
            ),
          ),
        ),
      ),
    );
  }
}

/// The advisory feed. Full sentences with room to wrap — these are IMD-
/// threshold-quoting recommendations, not labels, so none of them are
/// truncated to one line.
class _AdvisoryList extends StatelessWidget {
  const _AdvisoryList({required this.advisories});

  final List<String> advisories;

  @override
  Widget build(BuildContext context) {
    if (advisories.isEmpty) return const _EmptyAdvisories();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final advisory in advisories) _AdvisoryRow(text: advisory),
      ],
    );
  }
}

class _AdvisoryRow extends StatelessWidget {
  const _AdvisoryRow({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.info_outline,
            size: AppRadius.iconSize,
            color: AppColors.textSecondary,
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: DynamicText(text, style: AppTypography.body(AppColors.textPrimary)),
          ),
        ],
      ),
    );
  }
}

/// `advisories` is very often empty, which means conditions are normal —
/// good news that must read as such, not as a failed or missing feed.
///
/// Also the only place this screen offers a next step: a reassuring empty
/// state with nowhere to go still reads as a dead end, so it carries a CTA
/// into a fresh chat for whatever the standard advisories didn't cover.
class _EmptyAdvisories extends ConsumerWidget {
  const _EmptyAdvisories();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(uiStringsProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(
                Icons.check_circle_outline,
                size: AppRadius.iconSize,
                color: AppColors.textSecondary,
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Text(
                  s.noAdvisoriesArea,
                  style: AppTypography.body(AppColors.textSecondary),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        Text(
          s.wantSomethingSpecific,
          style: AppTypography.label(AppColors.textSecondary),
        ),
        const SizedBox(height: AppSpacing.sm),
        TextButton(
          onPressed: () {
            // Mirrors app_drawer.dart's "New chat" entry exactly: reset
            // the controller before navigating, so the composer opens on
            // a genuinely blank conversation rather than whatever was
            // last open. Deliberately no prefilled text — the composer's
            // own hint already invites a question.
            ref.read(chatControllerProvider.notifier).startNew();
            context.go('/chat');
          },
          style: TextButton.styleFrom(
            foregroundColor: AppColors.textPrimary,
            side: const BorderSide(color: AppColors.textPrimary),
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.xxl,
              vertical: AppSpacing.md,
            ),
          ),
          child: Text(s.askQuestion, style: AppTypography.body(AppColors.textPrimary)),
        ),
      ],
    );
  }
}

/// Traces the advice back to the data it was computed from. Collapsed by
/// default and visually secondary — this is provenance for anyone who
/// wants to check it, not something that competes with the advisories
/// themselves for attention.
class _BasedOnSection extends ConsumerStatefulWidget {
  const _BasedOnSection({super.key, required this.days});

  final List<ForecastDay> days;

  @override
  ConsumerState<_BasedOnSection> createState() => _BasedOnSectionState();
}

class _BasedOnSectionState extends ConsumerState<_BasedOnSection> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    if (widget.days.isEmpty) return const SizedBox.shrink();
    final s = ref.watch(uiStringsProvider);

    return GlassPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Semantics(
            button: true,
            label: _expanded ? 'Hide what this is based on' : 'Show what this is based on',
            child: ExcludeSemantics(
              child: InkWell(
                onTap: () => setState(() => _expanded = !_expanded),
                child: Row(
                  children: [
                    const Icon(
                      Icons.fact_check_outlined,
                      size: AppRadius.iconSize,
                      color: AppColors.textSecondary,
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Text(
                        s.basedOnForecast,
                        style: AppTypography.label(AppColors.textSecondary),
                      ),
                    ),
                    Icon(
                      _expanded ? Icons.expand_less : Icons.expand_more,
                      size: AppRadius.iconSize,
                      color: AppColors.textSecondary,
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (_expanded) ...[
            const SizedBox(height: AppSpacing.sm),
            for (final day in widget.days) _BasedOnRow(day: day),
          ],
        ],
      ),
    );
  }
}

class _BasedOnRow extends StatelessWidget {
  const _BasedOnRow({required this.day});

  final ForecastDay day;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Row(
        children: [
          SizedBox(
            width: 72,
            child: Text(
              day.forecastDate,
              style: AppTypography.caption(AppColors.textSecondary),
            ),
          ),
          Icon(
            weatherIconFor(day.weatherCode),
            size: AppRadius.iconSize,
            color: AppColors.textSecondary,
          ),
          const Spacer(),
          Text(
            '${day.tempMaxC.round()}° / ${day.tempMinC.round()}°',
            style: AppTypography.caption(AppColors.textSecondary),
          ),
        ],
      ),
    );
  }
}

class _ErrorView extends ConsumerWidget {
  const _ErrorView({super.key, required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(uiStringsProvider);
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
              s.couldNotLoadAdvisories,
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
                s.tryAgain,
                style: AppTypography.body(AppColors.textPrimary),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
