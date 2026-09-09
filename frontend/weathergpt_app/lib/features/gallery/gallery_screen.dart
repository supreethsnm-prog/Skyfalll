import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_radius.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';
import '../../core/theme/sky_gradient.dart';
import '../../shared/widgets/app_menu.dart';
import '../../shared/widgets/glass_panel.dart';
import '../../shared/widgets/round_icon_button.dart';
import '../chat/widgets/assistant_message.dart';
import '../chat/widgets/code_block.dart';
import '../chat/widgets/user_bubble.dart';

/// Dev-only screen rendering every component in the redesigned design
/// system, so the whole visual layer can be reviewed in one place without
/// a running device. Golden tests capture it section by section — the
/// Android emulator is non-functional on this hardware, so these PNGs are
/// the project's only visual verification surface.
///
/// Not reachable from the app's own navigation; it lives at `/gallery`.
class GalleryScreen extends StatelessWidget {
  const GalleryScreen({super.key, this.section});

  /// Which section to render alone. When null, all sections render in one
  /// scroll view — that is the form a human browses at `/gallery`, while
  /// the goldens pin one section each so each PNG stays legible.
  final GallerySection? section;

  @override
  Widget build(BuildContext context) {
    final sections = section == null ? GallerySection.values : [section!];

    return Scaffold(
      backgroundColor: AppColors.bgBase,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.screenMargin,
            vertical: AppSpacing.xxl,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final s in sections) _buildSection(s),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSection(GallerySection s) {
    switch (s) {
      case GallerySection.type:
        return const _TypeScaleSection();
      case GallerySection.chrome:
        return const _ChromeSection();
      case GallerySection.chat:
        return const _ChatSection();
      case GallerySection.menus:
        return const _MenusSection();
      case GallerySection.sky:
        return const _SkySection();
    }
  }
}

/// The gallery's sections, in render order.
enum GallerySection { type, chrome, chat, menus, sky }

/// A `textSecondary` caption above each group, so a reviewer reading the
/// golden PNG can tell what they are looking at.
class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(
        top: AppSpacing.xxl,
        bottom: AppSpacing.md,
      ),
      child: Text(text, style: AppTypography.label(AppColors.textSecondary)),
    );
  }
}

class _TypeScaleSection extends StatelessWidget {
  const _TypeScaleSection();

  @override
  Widget build(BuildContext context) {
    // Every style in AppTypography, each rendered in itself and named, so
    // a wrong size or weight is visible rather than merely documented.
    final samples = <(String, TextStyle)>[
      ('hero 112/300', AppTypography.hero(AppColors.textPrimary)),
      ('wordmark 28/700', AppTypography.wordmark(AppColors.textPrimary)),
      ('title 20/400', AppTypography.title(AppColors.textPrimary)),
      ('body 16/400', AppTypography.body(AppColors.textPrimary)),
      ('bodyBold 16/700', AppTypography.bodyBold(AppColors.textPrimary)),
      ('label 14/400', AppTypography.label(AppColors.textSecondary)),
      ('caption 12/400', AppTypography.caption(AppColors.textSecondary)),
      ('code 13 mono', AppTypography.code(AppColors.textPrimary)),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        const _SectionLabel('TYPE SCALE'),
        for (final (name, style) in samples)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  name,
                  style: AppTypography.caption(AppColors.textSecondary),
                ),
                Text(
                  // The hero style is huge; a short sample keeps it on one
                  // line so the section stays readable.
                  style.fontSize! > 40 ? '24°' : 'Heavy rain likely by 4 pm',
                  style: style,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _ChromeSection extends StatelessWidget {
  const _ChromeSection();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        const _SectionLabel('CHROME — 40dp round buttons'),
        Row(
          children: [
            RoundIconButton(
              icon: Icons.menu,
              tooltip: 'Open menu',
              onPressed: () {},
            ),
            const SizedBox(width: AppSpacing.md),
            RoundIconButton(
              icon: Icons.add,
              tooltip: 'New chat',
              onPressed: () {},
            ),
            const SizedBox(width: AppSpacing.md),
            RoundIconButton(
              icon: Icons.search,
              tooltip: 'Search',
              onPressed: () {},
            ),
            const SizedBox(width: AppSpacing.md),
            RoundIconButton(
              icon: Icons.more_vert,
              tooltip: 'More',
              onPressed: () {},
            ),
            const SizedBox(width: AppSpacing.md),
            const RoundIconButton(
              icon: Icons.mic_none,
              tooltip: 'Voice (disabled)',
              onPressed: null,
            ),
          ],
        ),
      ],
    );
  }
}

class _ChatSection extends StatelessWidget {
  const _ChatSection();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        const _SectionLabel('CHAT — boxed user turn, unboxed assistant turn'),
        const UserBubble(text: 'Will it rain in Pune this evening?'),
        const SizedBox(height: AppSpacing.xl),
        AssistantMessage(
          text: 'Yes — showers are likely in Pune after about 6 pm, easing '
              'overnight. Expect around 12 mm of rain and gusts near '
              '30 km/h. Nothing severe is in force for the district.',
          onCopy: () {},
          onReadAloud: () {},
          onShare: () {},
          onMore: () {},
        ),
        const SizedBox(height: AppSpacing.lg),
        CodeBlock(
          code: 'GET /forecast?lat=18.5204&lon=73.8567&days=3\n'
              '  precip_probability_pct: 78\n'
              '  wind_speed_max_kmh: 29.6',
          onCopy: () {},
        ),
      ],
    );
  }
}

class _MenusSection extends StatelessWidget {
  const _MenusSection();

  static final _overflowItems = <AppMenuItem>[
    AppMenuItem(icon: Icons.ios_share, label: 'Share', onTap: () {}),
    AppMenuItem(icon: Icons.push_pin_outlined, label: 'Pin', onTap: () {}),
    AppMenuItem(icon: Icons.search, label: 'Find in chat', onTap: () {}),
    AppMenuItem(icon: Icons.archive_outlined, label: 'Archive', onTap: () {}),
    AppMenuItem(
      icon: Icons.delete_outline,
      label: 'Delete',
      onTap: () {},
      destructive: true,
    ),
  ];

  static final _attachItems = <AppMenuItem>[
    AppMenuItem(
      icon: Icons.photo_camera_outlined,
      label: 'Camera',
      onTap: () {},
      iconWell: true,
    ),
    AppMenuItem(
      icon: Icons.photo_outlined,
      label: 'Photos',
      onTap: () {},
      iconWell: true,
    ),
    AppMenuItem(
      icon: Icons.insert_drive_file_outlined,
      label: 'Files',
      onTap: () {},
      iconWell: true,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        const _SectionLabel('MENUS — same shell, iconWell is the only switch'),
        Row(
          children: [
            Builder(
              builder: (context) => RoundIconButton(
                key: const Key('gallery-overflow-launcher'),
                icon: Icons.more_vert,
                tooltip: 'Overflow menu',
                onPressed: () => showAppMenu(
                  context: context,
                  items: _overflowItems,
                  header: 'This conversation',
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Builder(
              builder: (context) => RoundIconButton(
                key: const Key('gallery-attach-launcher'),
                icon: Icons.add,
                tooltip: 'Attach menu',
                onPressed: () => showAppMenu(
                  context: context,
                  items: _attachItems,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _SkySection extends StatelessWidget {
  const _SkySection();

  @override
  Widget build(BuildContext context) {
    const combos = <(String, SkyTimeOfDay, SkyCondition)>[
      ('day + cloudy (the sampled reference)', SkyTimeOfDay.day,
          SkyCondition.cloudy),
      ('night + clear', SkyTimeOfDay.night, SkyCondition.clear),
      ('dusk + rain', SkyTimeOfDay.dusk, SkyCondition.rain),
      ('dawn + clear', SkyTimeOfDay.dawn, SkyCondition.clear),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        const _SectionLabel('SKY + GLASS — panels over real gradients'),
        for (final (name, time, condition) in combos)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  name,
                  style: AppTypography.caption(AppColors.textSecondary),
                ),
                const SizedBox(height: AppSpacing.sm),
                ClipRRect(
                  borderRadius: BorderRadius.circular(AppRadius.panel),
                  child: SizedBox(
                    height: 200,
                    width: double.infinity,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: skyGradient(time, condition),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(AppSpacing.lg),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '24°',
                              style:
                                  AppTypography.title(AppColors.textPrimary),
                            ),
                            const Spacer(),
                            const GlassPanel(child: _ForecastRows()),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// Sample content inside the glass panels — shaped like the Home
/// forecast rows so the panel is judged at a realistic density.
class _ForecastRows extends StatelessWidget {
  const _ForecastRows();

  @override
  Widget build(BuildContext context) {
    const rows = <(String, IconData, String)>[
      ('Tue', Icons.water_drop_outlined, '31° / 24°'),
      ('Wed', Icons.wb_sunny_outlined, '33° / 25°'),
    ];

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final (day, icon, temps) in rows)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
            child: Row(
              children: [
                SizedBox(
                  width: 40,
                  child: Text(
                    day,
                    style: AppTypography.label(AppColors.textPrimary),
                  ),
                ),
                Icon(icon, size: 20, color: AppColors.textPrimary),
                const Spacer(),
                Text(
                  temps,
                  style: AppTypography.label(AppColors.textPrimary),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
