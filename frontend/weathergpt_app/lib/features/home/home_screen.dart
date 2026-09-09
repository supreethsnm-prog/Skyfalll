import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';
import '../../core/theme/sky_gradient.dart';
import '../../shared/error_message.dart';
import '../shell/app_drawer.dart';
import '../../shared/widgets/app_menu.dart';
import '../../shared/widgets/round_icon_button.dart';
import 'home_controller.dart';
import 'widgets/alert_banner.dart';
import 'widgets/detail_tiles.dart';
import 'widgets/forecast_panel.dart';
import 'widgets/home_hero.dart';

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
  @override
  void initState() {
    super.initState();
    // Fired once, after the first frame, so the controller's state change
    // never lands during a build.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(homeControllerProvider.notifier).loadInitial();
    });
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
                child: _Chrome(foreground: foreground),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Chrome extends StatelessWidget {
  const _Chrome({required this.foreground});

  final Color foreground;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.screenMargin),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          RoundIconButton(
            icon: Icons.menu,
            tooltip: 'Open menu',
            onPressed: () => Scaffold.of(context).openDrawer(),
          ),
          Row(
            children: [
              RoundIconButton(
                icon: Icons.add,
                tooltip: 'New chat',
                onPressed: () => context.go('/chat'),
              ),
              const SizedBox(width: AppSpacing.sm),
              Builder(
                builder: (context) => RoundIconButton(
                  icon: Icons.more_vert,
                  tooltip: 'More options',
                  onPressed: () => showAppMenu(
                    context: context,
                    // Home shows a reduced set: most of the reference menu's
                    // items (Pin, Archive, Find in chat) are chat-context and
                    // meaningless here.
                    items: [
                      AppMenuItem(
                        icon: Icons.ios_share,
                        label: 'Share',
                        onTap: () {},
                      ),
                      AppMenuItem(
                        icon: Icons.place_outlined,
                        label: 'Saved places',
                        onTap: () {},
                      ),
                      AppMenuItem(
                        icon: Icons.settings_outlined,
                        label: 'Settings',
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
      HomeError(:final error) => _ErrorView(
        message: errorMessageFor(error),
        foreground: foreground,
        onRetry: () => ref.read(homeControllerProvider.notifier).retry(),
      ),
      HomeLoaded() => _LoadedView(
        state: state as HomeLoaded,
        foreground: foreground,
      ),
    };
  }
}

class _LoadedView extends StatelessWidget {
  const _LoadedView({required this.state, required this.foreground});

  final HomeLoaded state;
  final Color foreground;

  @override
  Widget build(BuildContext context) {
    final today = state.forecast.isNotEmpty ? state.forecast.first : null;

    return SingleChildScrollView(
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
          ),
          const SizedBox(height: AppSpacing.md),
          AqiPill(airQuality: state.airQuality, foreground: foreground),
          const SizedBox(height: AppSpacing.xxl),
          for (final alert in state.nearbyAlerts) ...[
            AlertBanner(alert: alert),
            const SizedBox(height: AppSpacing.md),
          ],
          if (state.weather.hourly != null) ...[
            HourlyPanel(
              hours: state.weather.hourly!,
              foreground: foreground,
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
          ),
          const SizedBox(height: AppSpacing.md),
          SunPanel(
            foreground: foreground,
            sunrise: today?.sunrise,
            sunset: today?.sunset,
          ),
        ],
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({
    required this.message,
    required this.foreground,
    required this.onRetry,
  });

  final String message;
  final Color foreground;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    // Scrollable so a long message on a short screen degrades into
    // scrolling rather than a layout overflow.
    return SingleChildScrollView(
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
              "Couldn't load the weather",
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
              child: Text('Try again', style: AppTypography.body(foreground)),
            ),
          ],
        ),
      ),
    );
  }
}
