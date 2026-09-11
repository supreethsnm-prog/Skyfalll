import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';
import '../../data/alerts_api.dart';
import '../../data/geocoding_api.dart';
import '../../shared/error_message.dart';
import '../../shared/widgets/round_icon_button.dart';
import '../../l10n/app_strings.dart';
import '../home/home_controller.dart';
import '../home/widgets/alert_banner.dart';
import '../shell/app_drawer.dart';
import 'alert_history_controller.dart';

/// The last week of weather alerts near wherever Home is currently
/// showing — a history view, distinct from Home's own banner which only
/// ever shows what is happening *right now*.
///
/// Reads its location from [homeControllerProvider] rather than
/// resolving its own, mirroring `AdvisoryScreen`: Home already owns
/// "where is the user", and a second, independently-resolved location
/// here could disagree with it.
class AlertHistoryScreen extends ConsumerStatefulWidget {
  const AlertHistoryScreen({super.key});

  @override
  ConsumerState<AlertHistoryScreen> createState() => _AlertHistoryScreenState();
}

class _AlertHistoryScreenState extends ConsumerState<AlertHistoryScreen> {
  GeocodeResult? _requestedFor;

  @override
  void initState() {
    super.initState();
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
    // forever, waiting on a load nothing had asked for.
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
    ref.read(alertHistoryControllerProvider.notifier).load(
          location.latitude,
          location.longitude,
          location.displayName,
        );
  }

  @override
  Widget build(BuildContext context) {
    // Home may still be loading, finish loading, or change location
    // entirely while this screen is open — this listener catches every
    // one of those after the first frame.
    ref.listen<HomeUiState>(homeControllerProvider, (previous, next) {
      if (next is HomeLoaded) _loadFor(next.location);
    });

    final state = ref.watch(alertHistoryControllerProvider);
    final s = ref.watch(uiStringsProvider);

    return Scaffold(
      backgroundColor: AppColors.bgBase,
      drawer: const AppDrawer(activeRoute: '/alerts'),
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
                  Text(s.alerts, style: AppTypography.title(AppColors.textPrimary)),
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

  final AlertHistoryUiState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return switch (state) {
      AlertHistoryLoading() => const Center(
          child: CircularProgressIndicator(color: AppColors.textPrimary),
        ),
      AlertHistoryError(:final error) => _ErrorView(
          message: errorMessageFor(error),
          onRetry: () => ref.read(alertHistoryControllerProvider.notifier).retry(),
        ),
      AlertHistoryLoaded(:final locationName, :final alerts) => _HistoryList(
          locationName: locationName,
          alerts: alerts,
        ),
    };
  }
}

class _HistoryList extends ConsumerWidget {
  const _HistoryList({required this.locationName, required this.alerts});

  final String locationName;
  final List<AlertSummary> alerts;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(uiStringsProvider);
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.screenMargin)
          .copyWith(bottom: AppSpacing.xxl),
      children: [
        Text(
          s.pastDaysNear(alertHistoryWindowDays, locationName),
          style: AppTypography.label(AppColors.textSecondary),
        ),
        const SizedBox(height: AppSpacing.lg),
        if (alerts.isEmpty)
          const _EmptyView()
        else
          for (final alert in alerts) ...[
            _HistoryEntry(alert: alert),
            const SizedBox(height: AppSpacing.md),
          ],
      ],
    );
  }
}

class _HistoryEntry extends StatelessWidget {
  const _HistoryEntry({required this.alert});

  final AlertSummary alert;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AlertBanner(alert: alert),
        if (alert.effectiveStartTime != null) ...[
          const SizedBox(height: AppSpacing.xs),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
            child: Text(
              alert.effectiveStartTime!,
              style: AppTypography.caption(AppColors.textSecondary),
            ),
          ),
        ],
      ],
    );
  }
}

class _EmptyView extends ConsumerWidget {
  const _EmptyView();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(uiStringsProvider);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxl),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.check_circle_outline, size: 40, color: AppColors.textPrimary),
          const SizedBox(height: AppSpacing.lg),
          Text(
            s.noAlertsNearby,
            style: AppTypography.title(AppColors.textPrimary),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            s.noAlertsAffecting,
            style: AppTypography.label(AppColors.textSecondary),
            textAlign: TextAlign.center,
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
        constraints: BoxConstraints(minHeight: MediaQuery.of(context).size.height * 0.6),
        alignment: Alignment.center,
        padding: const EdgeInsets.all(AppSpacing.xxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off, size: 40, color: AppColors.textPrimary),
            const SizedBox(height: AppSpacing.lg),
            Text(
              s.couldNotLoadAlertHistory,
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
