import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/app_error.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../data/geocoding_api.dart';
import '../../../l10n/app_strings.dart';
import '../../../shared/error_message.dart';
import '../home_controller.dart';

/// What the sheet is currently showing.
///
/// "Not found" is modelled as its own outcome rather than folded into
/// error: a place the geocoder doesn't know is a normal result of typing,
/// and telling the user "something went wrong" would send them debugging
/// their network instead of their spelling.
sealed class _SearchState {
  const _SearchState();
}

class _Idle extends _SearchState {
  const _Idle();
}

class _Searching extends _SearchState {
  const _Searching();
}

class _Found extends _SearchState {
  final GeocodeResult result;
  const _Found(this.result);
}

class _NotFound extends _SearchState {
  final String query;
  const _NotFound(this.query);
}

class _Failed extends _SearchState {
  final AppError error;
  const _Failed(this.error);
}

/// Opens the location search as a modal bottom sheet.
///
/// A sheet rather than a full screen: choosing a place is a quick,
/// reversible detour, and keeping the weather visible behind it makes
/// that obvious.
///
/// [onSelected], when given, receives the chosen place instead of the
/// default behaviour (changing Home's own current location) — this is how
/// other screens (Historical, say) reuse this same search UI for "any
/// place on Earth" without redirecting Home. [showUseMyLocation] hides the
/// "Use my location" row for callers where "the device's current position"
/// isn't a meaningful choice.
Future<void> showLocationSearch(
  BuildContext context, {
  ValueChanged<GeocodeResult>? onSelected,
  bool showUseMyLocation = true,
}) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: AppColors.bgBase,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(
        top: Radius.circular(AppRadius.panel),
      ),
    ),
    builder: (_) => LocationSearchSheet(
      onSelected: onSelected,
      showUseMyLocation: showUseMyLocation,
    ),
  );
}

class LocationSearchSheet extends ConsumerStatefulWidget {
  const LocationSearchSheet({
    super.key,
    this.onSelected,
    this.showUseMyLocation = true,
  });

  /// Called with the chosen place instead of the default "change Home's
  /// location" behaviour, when given.
  final ValueChanged<GeocodeResult>? onSelected;

  /// Whether to show the "Use my location" row. Ignored (never shown) when
  /// [onSelected] is set, since that row's default behaviour is specific to
  /// Home's own current-location concept.
  final bool showUseMyLocation;

  @override
  ConsumerState<LocationSearchSheet> createState() =>
      _LocationSearchSheetState();
}

class _LocationSearchSheetState extends ConsumerState<LocationSearchSheet> {
  final _controller = TextEditingController();
  _SearchState _state = const _Idle();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    final query = _controller.text.trim();
    if (query.isEmpty) return;

    setState(() => _state = const _Searching());

    try {
      final result = await ref.read(geocodingApiProvider).search(query);
      if (!mounted) return;
      setState(
        () => _state = result == null ? _NotFound(query) : _Found(result),
      );
    } on AppError catch (e) {
      if (!mounted) return;
      setState(() => _state = _Failed(e));
    }
  }

  void _choose(GeocodeResult result) {
    final onSelected = widget.onSelected;
    if (onSelected != null) {
      onSelected(result);
    } else {
      ref.read(homeControllerProvider.notifier).changeLocation(result);
    }
    Navigator.of(context).pop();
  }

  void _useDeviceLocation() {
    ref.read(homeControllerProvider.notifier).useCurrentLocation();
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(uiStringsProvider);
    return Padding(
      // Lifts the sheet clear of the keyboard, which otherwise covers the
      // very result the user is reaching for.
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SafeArea(
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
              Text(
                s.changeLocation,
                style: AppTypography.title(AppColors.textPrimary),
              ),
              const SizedBox(height: AppSpacing.lg),
              _SearchField(
                controller: _controller,
                onSubmitted: _search,
                hintText: s.searchCityOrDistrict,
              ),
              if (widget.onSelected == null && widget.showUseMyLocation) ...[
                const SizedBox(height: AppSpacing.md),
                _UseMyLocationRow(
                  onTap: _useDeviceLocation,
                  label: s.useMyLocation,
                ),
              ],
              const SizedBox(height: AppSpacing.sm),
              _Outcome(state: _state, onChoose: _choose),
            ],
          ),
        ),
      ),
    );
  }
}


class _SearchField extends StatelessWidget {
  const _SearchField({
    required this.controller,
    required this.onSubmitted,
    required this.hintText,
  });

  final TextEditingController controller;
  final VoidCallback onSubmitted;
  final String hintText;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: AppRadius.composerHeight),
      decoration: BoxDecoration(
        color: AppColors.surfaceRaised,
        borderRadius: BorderRadius.circular(AppRadius.composerHeight / 2),
      ),
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
      child: Row(
        children: [
          const Icon(
            Icons.search,
            size: AppRadius.iconSize,
            color: AppColors.textSecondary,
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: TextField(
              controller: controller,
              autofocus: true,
              textInputAction: TextInputAction.search,
              onSubmitted: (_) => onSubmitted(),
              style: AppTypography.body(AppColors.textPrimary),
              cursorColor: AppColors.accent,
              decoration: InputDecoration(
                isDense: true,
                hintText: hintText,
                hintStyle: AppTypography.body(AppColors.textSecondary),
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _UseMyLocationRow extends StatelessWidget {
  const _UseMyLocationRow({required this.onTap, required this.label});

  final VoidCallback onTap;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
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
                const Icon(
                  Icons.my_location,
                  size: AppRadius.iconSize,
                  color: AppColors.accent,
                ),
                const SizedBox(width: AppSpacing.md),
                Text(
                  label,
                  style: AppTypography.body(AppColors.accent),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Outcome extends StatelessWidget {
  const _Outcome({required this.state, required this.onChoose});

  final _SearchState state;
  final ValueChanged<GeocodeResult> onChoose;

  @override
  Widget build(BuildContext context) {
    return switch (state) {
      _Idle() => const SizedBox.shrink(),
      _Searching() => const Padding(
          padding: EdgeInsets.all(AppSpacing.lg),
          child: Center(
            child: SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
        ),
      _Found(:final result) => _ResultRow(result: result, onTap: onChoose),
      // Names what was actually typed, so the user can see the typo.
      _NotFound(:final query) => _Message(
          icon: Icons.search_off,
          text: 'No place found for "$query".',
        ),
      _Failed(:final error) => _Message(
          icon: Icons.cloud_off,
          text: errorMessageFor(error),
        ),
    };
  }
}

class _ResultRow extends StatelessWidget {
  const _ResultRow({required this.result, required this.onTap});

  final GeocodeResult result;
  final ValueChanged<GeocodeResult> onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: result.displayName,
      child: ExcludeSemantics(
        child: InkWell(
          onTap: () => onTap(result),
          borderRadius: BorderRadius.circular(AppRadius.menu),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.sm,
              vertical: AppSpacing.md,
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.place_outlined,
                  size: AppRadius.iconSize,
                  color: AppColors.textPrimary,
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Text(
                    result.displayName,
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

class _Message extends StatelessWidget {
  const _Message({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.lg,
      ),
      child: Row(
        children: [
          Icon(icon, size: AppRadius.iconSize, color: AppColors.textSecondary),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Text(
              text,
              style: AppTypography.body(AppColors.textSecondary),
            ),
          ),
        ],
      ),
    );
  }
}
