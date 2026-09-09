import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_radius.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';
import '../../core/theme/sky_gradient.dart';
import '../../data/geocoding_api.dart';
import '../../data/weather_api.dart';
import '../../shared/widgets/round_icon_button.dart';
import '../../shared/widgets/weather_icon.dart';
import '../home/home_controller.dart';
import '../home/weather_label.dart';
import '../shell/app_drawer.dart';
import 'saved_places_controller.dart';

/// Current conditions for one saved place.
///
/// Each card fetches its own weather. The backend caches per coordinate
/// with a 20-minute TTL, so revisiting this screen is nearly free, and a
/// place that fails to load shows its name rather than vanishing.
final savedPlaceWeatherProvider =
    FutureProvider.family<CurrentWeather, ({double lat, double lon})>(
  (ref, point) =>
      ref.read(weatherApiProvider).fetchCurrent(point.lat, point.lon),
);

class SavedPlacesScreen extends ConsumerWidget {
  const SavedPlacesScreen({super.key, this.now});

  /// Injectable clock. The card gradients depend on the time of day, so
  /// without this the goldens would render a different sky depending on
  /// when the suite happened to run.
  final DateTime? now;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final places = ref.watch(savedPlacesProvider);

    return Scaffold(
      backgroundColor: AppColors.bgBase,
      drawer: const AppDrawer(activeRoute: '/saved'),
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
                    'Saved places',
                    style: AppTypography.title(AppColors.textPrimary),
                  ),
                ],
              ),
            ),
            Expanded(
              child: places.isEmpty
                  ? const _EmptyState()
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(
                        AppSpacing.lg,
                        AppSpacing.sm,
                        AppSpacing.lg,
                        AppSpacing.xxxl,
                      ),
                      itemCount: places.length,
                      separatorBuilder: (_, _) =>
                          const SizedBox(height: AppSpacing.md),
                      itemBuilder: (context, i) =>
                          _PlaceCard(place: places[i], now: now),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    // Says how to fill the screen rather than just reporting it is empty.
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.bookmark_border,
              size: 40,
              color: AppColors.textSecondary,
            ),
            const SizedBox(height: AppSpacing.lg),
            Text(
              'No saved places yet',
              style: AppTypography.title(AppColors.textPrimary),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Tap the bookmark on any location to keep it here.',
              textAlign: TextAlign.center,
              style: AppTypography.label(AppColors.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}

/// One saved place, over its own sky.
///
/// The gradient is chosen from that place's live conditions and the
/// current hour, so a list of saved places reads at a glance — a stormy
/// city looks stormy. Tapping it makes that place the Home location.
class _PlaceCard extends ConsumerWidget {
  const _PlaceCard({required this.place, this.now});

  final GeocodeResult place;
  final DateTime? now;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final weather = ref.watch(
      savedPlaceWeatherProvider((lat: place.latitude, lon: place.longitude)),
    );

    // Before the weather lands, and if it never does, fall back to a
    // clear sky for the current hour rather than a grey placeholder.
    final time = skyTimeOfDayFor(now ?? DateTime.now());
    final condition = weather.maybeWhen(
      data: (w) => skyConditionFor(w.weatherCode),
      orElse: () => SkyCondition.clear,
    );
    final foreground = skyForeground(time, condition);

    return Semantics(
      button: true,
      label: 'Show weather for ${place.displayName}',
      child: ExcludeSemantics(
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadius.panel),
          onTap: () {
            ref.read(homeControllerProvider.notifier).changeLocation(place);
            context.go('/home');
          },
          child: ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.panel),
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: skyGradient(time, condition),
              ),
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.lg),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            place.displayName,
                            style: AppTypography.body(foreground),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: AppSpacing.xs),
                          _Subtitle(weather: weather, foreground: foreground),
                        ],
                      ),
                    ),
                    const SizedBox(width: AppSpacing.md),
                    _Temperature(weather: weather, foreground: foreground),
                    const SizedBox(width: AppSpacing.sm),
                    _RemoveButton(place: place, foreground: foreground),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Subtitle extends StatelessWidget {
  const _Subtitle({required this.weather, required this.foreground});

  final AsyncValue<CurrentWeather> weather;
  final Color foreground;

  @override
  Widget build(BuildContext context) {
    final text = weather.when(
      data: (w) => '${weatherLabelFor(w.weatherCode)} · '
          '${w.humidityPct.round()}% · ${w.windSpeedKmh.round()} km/h',
      loading: () => 'Loading…',
      // The place is still usable even if its weather did not load, so
      // the card stays and says so rather than disappearing.
      error: (_, _) => 'Weather unavailable',
    );

    return Text(
      text,
      style: AppTypography.caption(foreground),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }
}

class _Temperature extends StatelessWidget {
  const _Temperature({required this.weather, required this.foreground});

  final AsyncValue<CurrentWeather> weather;
  final Color foreground;

  @override
  Widget build(BuildContext context) {
    return weather.when(
      data: (w) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            weatherIconFor(w.weatherCode),
            size: AppRadius.iconSize,
            color: foreground,
          ),
          const SizedBox(width: AppSpacing.sm),
          Text(
            '${w.temperatureC.round()}°',
            style: AppTypography.title(foreground),
          ),
        ],
      ),
      loading: () => SizedBox(
        width: 20,
        height: 20,
        child: CircularProgressIndicator(strokeWidth: 2, color: foreground),
      ),
      error: (_, _) => Icon(
        Icons.cloud_off,
        size: AppRadius.iconSize,
        color: foreground,
      ),
    );
  }
}

class _RemoveButton extends ConsumerWidget {
  const _RemoveButton({required this.place, required this.foreground});

  final GeocodeResult place;
  final Color foreground;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Semantics(
      button: true,
      label: 'Remove ${place.displayName}',
      child: ExcludeSemantics(
        child: IconButton(
          icon: Icon(Icons.close, size: AppRadius.iconSize, color: foreground),
          onPressed: () =>
              ref.read(savedPlacesProvider.notifier).remove(place),
        ),
      ),
    );
  }
}
