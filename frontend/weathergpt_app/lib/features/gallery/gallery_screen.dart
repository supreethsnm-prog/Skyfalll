import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';
import '../../core/theme/theme_mode_provider.dart';
import '../../shared/widgets/app_chip.dart';
import '../../shared/widgets/app_primary_button.dart';
import '../../shared/widgets/empty_view.dart';
import '../../shared/widgets/error_view.dart';
import '../../shared/widgets/loading_view.dart';
import '../../shared/widgets/weather_icon.dart';

/// Dev-only screen rendering every shared widget and design token for
/// visual self-review. Not part of the bottom-nav shell — reachable at
/// the `/gallery` route (see app_router.dart). Should gain a
/// debug-build guard before a public release; left open for now since
/// this phase has no other screen to link to it from.
class GalleryScreen extends ConsumerWidget {
  const GalleryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final textTheme = Theme.of(context).textTheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Component gallery'),
        actions: [
          IconButton(
            icon: Icon(
              isDark ? Icons.light_mode_outlined : Icons.dark_mode_outlined,
            ),
            tooltip: 'Toggle light/dark theme',
            onPressed: () => ref.read(themeModeProvider.notifier).toggle(),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        children: [
          Text('Display', style: textTheme.displayLarge),
          Text('Headline', style: textTheme.headlineMedium),
          Text('Title', style: textTheme.titleMedium),
          Text('Body large', style: textTheme.bodyLarge),
          Text('Body', style: textTheme.bodyMedium),
          Text('Caption', style: textTheme.bodySmall),
          Text(
            'Code · VABB 121130Z 27012KT',
            style: AppTypography.code(Theme.of(context).colorScheme.onSurface),
          ),
          const SizedBox(height: AppSpacing.xl),
          Wrap(
            spacing: AppSpacing.sm,
            children: [
              AppPrimaryButton(label: 'Primary action', onPressed: () {}),
              const AppChip(label: 'Rain'),
              const AppChip(label: 'Selected', selected: true),
            ],
          ),
          const SizedBox(height: AppSpacing.xl),
          Text('Alert severity', style: textTheme.titleMedium),
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: AppSpacing.sm,
            children: [
              for (final severity in ['Minor', 'Moderate', 'Severe', 'Extreme'])
                Chip(
                  label: Text(severity),
                  backgroundColor: AppColors.alertSeverity(severity),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.xl),
          Text('Weather icons', style: textTheme.titleMedium),
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: AppSpacing.md,
            children: [
              for (final code in [0, 3, 61, 95]) Icon(weatherIconFor(code)),
            ],
          ),
          const SizedBox(height: AppSpacing.xl),
          Text('States', style: textTheme.titleMedium),
          const SizedBox(height: AppSpacing.sm),
          const SizedBox(
            height: 120,
            child: LoadingView(message: 'Loading forecast…'),
          ),
          SizedBox(
            height: 200,
            child: ErrorView(
              message: 'Could not reach the server.',
              onRetry: () {},
            ),
          ),
          SizedBox(
            height: 200,
            child: EmptyView(
              message: 'No alerts right now.',
              actionLabel: 'Refresh',
              onAction: () {},
            ),
          ),
        ],
      ),
    );
  }
}
