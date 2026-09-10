import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_radius.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';
import '../../data/marine_api.dart';
import '../../shared/error_message.dart';
import '../../shared/widgets/round_icon_button.dart';
import '../shell/app_drawer.dart';
import 'marine_controller.dart';

/// The tile provider `MarineScreen`'s map layer uses.
///
/// A provider — like every other network dependency in this app (see
/// `test/support/fake_apis.dart`) — rather than a constructor parameter on
/// the screen, so widget tests can swap in a non-networking fake without
/// teaching `MarineScreen` a test-only argument. flutter_test blocks real
/// sockets, so an unoverridden `NetworkTileProvider` would sit on a doomed
/// request rather than failing fast.
final marineTileProviderProvider =
    Provider<TileProvider>((ref) => NetworkTileProvider());

/// OSM's tile policy requires an identifying User-Agent.
const _osmUserAgent = 'com.weathergpt.app';

/// Roughly the geographic centre of India — used only as a neutral resting
/// view for the empty state, where there is no zone data to fit a camera
/// to. Never used when zones are present: the loaded map always fits the
/// real bounds of whatever came back (see `_MapView`), not a fixed camera.
const _indiaCenter = LatLng(20.5937, 78.9629);

const _months = [
  'January', 'February', 'March', 'April', 'May', 'June',
  'July', 'August', 'September', 'October', 'November', 'December',
];

/// "9 September 2026" rather than the raw `julian_day`/`year` pair the
/// backend sends — see `PfzZone.issueDate`.
String formatIssueDate(DateTime date) =>
    '${date.day} ${_months[date.month - 1]} ${date.year}';

/// Live INCOIS Potential Fishing Zone (PFZ) advisories, drawn on a map.
///
/// Unlike every other screen in this app, this one's data IS inherently
/// geographic line geometry — a list of zone lengths would technically
/// show the same numbers but communicate nothing to the roughly four
/// million fisherfolk this advisory serves. The map is the product.
///
/// Does not read Home's location: `GET /marine/pfz-zones` returns every
/// current zone nationwide, and the camera fits itself to the data.
class MarineScreen extends ConsumerStatefulWidget {
  const MarineScreen({super.key});

  @override
  ConsumerState<MarineScreen> createState() => _MarineScreenState();
}

class _MarineScreenState extends ConsumerState<MarineScreen> {
  @override
  void initState() {
    super.initState();
    // Fired once, after the first frame, so the controller's state change
    // never lands during a build — matches Advisories/Aviation, though
    // this screen has no upstream location to wait on first.
    WidgetsBinding.instance
        .addPostFrameCallback((_) => ref.read(marineControllerProvider.notifier).load());
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(marineControllerProvider);

    return Scaffold(
      backgroundColor: AppColors.bgBase,
      drawer: const AppDrawer(activeRoute: '/marine'),
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
                    'Fishing zones',
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

  final MarineUiState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return switch (state) {
      MarineLoading() => const Center(
          child: CircularProgressIndicator(color: AppColors.textPrimary),
        ),
      MarineError(:final error) => _ErrorView(
          message: errorMessageFor(error),
          onRetry: () => ref.read(marineControllerProvider.notifier).retry(),
        ),
      MarineLoaded(:final zones) => _MapView(zones: zones),
    };
  }
}

/// Full-bleed map with the zones drawn over it, a summary bar, and (when
/// `zones` is empty) a state explaining that clearly rather than leaving a
/// bare map that would read as "no zones exist".
class _MapView extends ConsumerStatefulWidget {
  const _MapView({required this.zones});

  final List<PfzZone> zones;

  @override
  ConsumerState<_MapView> createState() => _MapViewState();
}

class _MapViewState extends ConsumerState<_MapView> {
  /// Notified by `PolylineLayer`'s built-in hit-testing whenever a tap
  /// lands on (or near) a drawn line. Chosen over a list-based fallback
  /// because it gives real point-on-line hit detection for free — matching
  /// against 37k+ raw coordinate points by hand would be both slower and
  /// less accurate.
  final _hitNotifier = ValueNotifier<LayerHitResult<PfzZone>?>(null);

  @override
  void initState() {
    super.initState();
    _hitNotifier.addListener(_onHit);
  }

  @override
  void dispose() {
    _hitNotifier.removeListener(_onHit);
    _hitNotifier.dispose();
    super.dispose();
  }

  void _onHit() {
    final hit = _hitNotifier.value;
    if (hit == null || hit.hitValues.isEmpty) return;
    showZoneDetails(context, hit.hitValues.first);
  }

  @override
  Widget build(BuildContext context) {
    final zones = widget.zones;
    final points = zones.expand((zone) => zone.allPoints).toList();
    final tileProvider = ref.watch(marineTileProviderProvider);

    return Stack(
      children: [
        Positioned.fill(
          child: FlutterMap(
            options: MapOptions(
              initialCenter:
                  points.isEmpty ? _indiaCenter : LatLngBounds.fromPoints(points).center,
              initialZoom: points.isEmpty ? 4.2 : 5,
              // Fits the camera to the real bounds of whatever zones came
              // back — never a hardcoded position — so it stays correct if
              // the ingested data moves. Only skipped when there is no
              // data to fit to at all (see `_indiaCenter`).
              initialCameraFit: points.isEmpty
                  ? null
                  : CameraFit.bounds(
                      bounds: LatLngBounds.fromPoints(points),
                      padding: const EdgeInsets.all(AppSpacing.xxl),
                    ),
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: _osmUserAgent,
                tileProvider: tileProvider,
              ),
              PolylineLayer<PfzZone>(
                hitNotifier: _hitNotifier,
                polylines: [
                  for (final zone in zones)
                    for (final line in zone.lines)
                      Polyline<PfzZone>(
                        points: line,
                        strokeWidth: 3,
                        color: AppColors.accent,
                        hitValue: zone,
                      ),
                ],
              ),
              // A licence obligation, not decoration — OSM's tile usage
              // policy requires visible attribution.
              const RichAttributionWidget(
                attributions: [
                  TextSourceAttribution('OpenStreetMap contributors'),
                ],
              ),
            ],
          ),
        ),
        Positioned(
          left: AppSpacing.lg,
          right: AppSpacing.lg,
          top: AppSpacing.lg,
          child: _SummaryBar(zones: zones),
        ),
        // Legible over a blank tile background too: if OSM's tiles fail to
        // load the map goes blank, and this must not disappear with them.
        if (zones.isEmpty) const _EmptyOverlay(),
      ],
    );
  }
}

class _SummaryBar extends StatelessWidget {
  const _SummaryBar({required this.zones});

  final List<PfzZone> zones;

  @override
  Widget build(BuildContext context) {
    final count = zones.length;
    // All zones in one ingestion batch share the same issue day in
    // practice, so the first zone's date stands for the batch.
    final issueDate = zones.isEmpty ? null : formatIssueDate(zones.first.issueDate);

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.md,
      ),
      decoration: BoxDecoration(
        color: AppColors.surfaceRaised,
        borderRadius: BorderRadius.circular(AppRadius.panel),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            zones.isEmpty
                ? 'No fishing zone advisories available'
                : '$count fishing zone${count == 1 ? '' : 's'} · issued $issueDate',
            style: AppTypography.body(AppColors.textPrimary),
          ),
          // The satellite product this advisory derives from — provenance
          // worth showing once, not per zone (every zone shares the same
          // `category`). Omitted entirely when there is no zone to read it
          // from, rather than guessing.
          if (zones.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(
              'INCOIS · ${zones.first.category.toUpperCase()}',
              style: AppTypography.caption(AppColors.textSecondary),
            ),
          ],
        ],
      ),
    );
  }
}

class _EmptyOverlay extends StatelessWidget {
  const _EmptyOverlay();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        margin: const EdgeInsets.all(AppSpacing.xxl),
        padding: const EdgeInsets.all(AppSpacing.xxl),
        decoration: BoxDecoration(
          color: AppColors.surfaceRaised,
          borderRadius: BorderRadius.circular(AppRadius.panel),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.sailing_outlined,
              size: 40,
              color: AppColors.textSecondary,
            ),
            const SizedBox(height: AppSpacing.lg),
            Text(
              'No advisories available',
              style: AppTypography.title(AppColors.textPrimary),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              // An empty list means ingestion has not run yet — this is
              // not an error, and it must not be read as "there are no
              // fishing zones today".
              'INCOIS has not published fishing zone advisories yet. '
              'Check back soon.',
              style: AppTypography.label(AppColors.textSecondary),
              textAlign: TextAlign.center,
            ),
          ],
        ),
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
              "Couldn't load fishing zone advisories",
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

/// Opens a zone's details as a modal bottom sheet. Mirrors
/// `showAirportPicker`'s shape in `aviation_screen.dart`.
Future<void> showZoneDetails(BuildContext context, PfzZone zone) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: AppColors.bgBase,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.panel)),
    ),
    builder: (_) => _ZoneDetailsSheet(zone: zone),
  );
}

class _ZoneDetailsSheet extends StatelessWidget {
  const _ZoneDetailsSheet({required this.zone});

  final PfzZone zone;

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
            Text(zone.externalId, style: AppTypography.title(AppColors.textPrimary)),
            const SizedBox(height: AppSpacing.lg),
            _DetailRow(label: 'Issued', value: formatIssueDate(zone.issueDate)),
            _DetailRow(label: 'Length', value: '${zone.lengthKm.round()} km'),
            _DetailRow(
              label: 'Sector boundary',
              value: '${zone.sectorBoundary}',
            ),
          ],
        ),
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Row(
        children: [
          Text(label, style: AppTypography.label(AppColors.textSecondary)),
          const Spacer(),
          Text(value, style: AppTypography.body(AppColors.textPrimary)),
        ],
      ),
    );
  }
}
