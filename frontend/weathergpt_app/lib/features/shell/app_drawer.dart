import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_radius.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';
import '../../shared/widgets/round_icon_button.dart';
import '../chat/chat_controller.dart';

/// The app's sidebar, modelled on ChatGPT's (`TopLeftLines.jpeg`): the
/// wordmark top-left, a search affordance top-right, a short list of
/// destinations, then chat history, with the account row pinned to the
/// bottom.
///
/// Sits on [AppColors.bgBase] like the rest of the chrome — the drawer is
/// not a raised surface in the reference, it is the same true black with
/// the content simply sliding over it.
class AppDrawer extends ConsumerWidget {
  const AppDrawer({
    super.key,
    this.recents,
    this.activeRoute = '/home',
  });

  /// Which destination is currently open, so it can be marked selected —
  /// the reference sidebar always shows where you are.
  final String activeRoute;

  /// Overrides the saved conversation list. Used by goldens and tests so
  /// they do not depend on stored history; null means read the real one.
  final List<String>? recents;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final conversations = ref.watch(conversationsProvider);
    final titles =
        recents ?? conversations.map((c) => c.title).toList(growable: false);
    return Drawer(
      backgroundColor: AppColors.bgBase,
      // The reference drawer is a plain panel, not an elevated Material
      // sheet with a tint over it.
      elevation: 0,
      shape: const RoundedRectangleBorder(),
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _DrawerHeader(),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
                children: [
                  _NavEntry(
                    icon: Icons.wb_sunny_outlined,
                    label: 'Home',
                    selected: activeRoute == '/home',
                    onTap: () {
                      Navigator.of(context).pop();
                      context.go('/home');
                    },
                  ),
                  _NavEntry(
                    icon: Icons.add_comment_outlined,
                    label: 'New chat',
                    selected: activeRoute == '/chat',
                    onTap: () {
                      Navigator.of(context).pop();
                      // A fresh chat, not whatever was last open.
                      ref.read(chatControllerProvider.notifier).startNew();
                      context.go('/chat');
                    },
                  ),
                  _NavEntry(
                    icon: Icons.agriculture_outlined,
                    label: 'Advisories',
                    selected: activeRoute == '/advisories',
                    onTap: () {
                      Navigator.of(context).pop();
                      context.go('/advisories');
                    },
                  ),
                  _NavEntry(
                    icon: Icons.flight_outlined,
                    label: 'Aviation',
                    selected: activeRoute == '/aviation',
                    onTap: () {
                      Navigator.of(context).pop();
                      context.go('/aviation');
                    },
                  ),
                  _NavEntry(
                    icon: Icons.explore_outlined,
                    label: 'Discover',
                    onTap: () {},
                  ),
                  _NavEntry(
                    icon: Icons.article_outlined,
                    label: 'News',
                    onTap: () {},
                  ),
                  _NavEntry(
                    icon: Icons.warning_amber_rounded,
                    label: 'Alerts',
                    onTap: () {},
                  ),
                  _NavEntry(
                    icon: Icons.bookmark_border,
                    label: 'Saved places',
                    selected: activeRoute == '/saved',
                    onTap: () {
                      Navigator.of(context).pop();
                      context.go('/saved');
                    },
                  ),
                  const _SectionLabel('Recents'),
                  if (titles.isEmpty)
                    const _EmptyRecents()
                  else
                    for (var i = 0; i < titles.length; i++)
                      _NavEntry(
                        icon: Icons.chat_bubble_outline,
                        label: titles[i],
                        onTap: () {
                          Navigator.of(context).pop();
                          // Only a real saved conversation can be
                          // reopened; an injected title list is display
                          // only.
                          if (recents == null && i < conversations.length) {
                            ref
                                .read(chatControllerProvider.notifier)
                                .resume(conversations[i]);
                          }
                          context.go('/chat');
                        },
                      ),
                ],
              ),
            ),
            const Divider(height: 1, color: AppColors.divider),
            const _AccountRow(),
          ],
        ),
      ),
    );
  }
}

class _DrawerHeader extends StatelessWidget {
  const _DrawerHeader();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.lg,
        AppSpacing.md,
        AppSpacing.sm,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // The wordmark is the largest type in the app and the drawer is
          // the narrowest surface it appears on, so it shrinks to fit
          // rather than overflowing beside the search button on a narrow
          // screen or at a large text scale.
          Flexible(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                'WeatherGPT',
                maxLines: 1,
                style: AppTypography.wordmark(AppColors.textPrimary),
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          RoundIconButton(
            icon: Icons.search,
            tooltip: 'Search chats',
            onPressed: () {},
          ),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.xl,
        AppSpacing.lg,
        AppSpacing.sm,
      ),
      child: Text(text, style: AppTypography.label(AppColors.textSecondary)),
    );
  }
}

class _NavEntry extends StatelessWidget {
  const _NavEntry({
    required this.icon,
    required this.label,
    required this.onTap,
    this.selected = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  /// The current destination gets a filled pill, as in the reference —
  /// the sidebar should always say where you are.
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: ExcludeSemantics(
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.sm,
            vertical: 2,
          ),
          child: Material(
            color: selected ? AppColors.surfaceRaised : Colors.transparent,
            borderRadius: BorderRadius.circular(AppRadius.menu),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: onTap,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md,
                  vertical: AppSpacing.md,
                ),
                child: Row(
                  children: [
                    Icon(
                      icon,
                      size: AppRadius.iconSize,
                      color: AppColors.textPrimary,
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: Text(
                        label,
                        style: AppTypography.body(AppColors.textPrimary),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
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

class _EmptyRecents extends StatelessWidget {
  const _EmptyRecents();

  @override
  Widget build(BuildContext context) {
    // An empty screen is an invitation to act, not an apology. Nothing
    // persists conversations yet, so this says what will appear here
    // rather than pretending there is history.
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.sm,
      ),
      child: Text(
        'Your conversations will appear here.',
        style: AppTypography.label(AppColors.textSecondary),
      ),
    );
  }
}

class _AccountRow extends StatelessWidget {
  const _AccountRow();

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Your account',
      child: ExcludeSemantics(
        child: InkWell(
          onTap: () {},
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Row(
              children: [
                Container(
                  width: AppRadius.iconButton,
                  height: AppRadius.iconButton,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppColors.avatarFill,
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    'S',
                    style: AppTypography.body(AppColors.textPrimary),
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Text(
                    'Your account',
                    style: AppTypography.body(AppColors.textPrimary),
                  ),
                ),
                const Icon(
                  Icons.more_horiz,
                  size: AppRadius.iconSize,
                  color: AppColors.textSecondary,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
