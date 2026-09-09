import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_radius.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';

/// A single row in an [AppMenu]: an icon, a label, and a tap callback.
///
/// The same row shape serves both reference menus (spec §4.4/§4.5) — the
/// overflow dropdown's plain icon rows and the attach menu's icon-well
/// rows — with [iconWell] as the only switch between them.
class AppMenuItem {
  const AppMenuItem({
    required this.icon,
    required this.label,
    required this.onTap,
    this.destructive = false,
    this.iconWell = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  /// Renders the label (and icon) in [AppColors.destructive]. Used for
  /// the dropdown's trailing "Delete" row.
  final bool destructive;

  /// Wraps the icon in a 40dp [AppColors.surfaceIconWell] circle, as in
  /// the attach menu.
  final bool iconWell;
}

/// Diameter of the icon well circle used when [AppMenuItem.iconWell] is
/// set, per spec §4.5.
const double _iconWellSize = 40;

/// Shows the shared chrome menu: a fixed-width, rounded, dark panel with
/// an optional header line followed by icon + label rows. Serves both
/// the chat/home overflow dropdown and the composer's attach menu — the
/// only difference between them is each item's [AppMenuItem.iconWell].
Future<void> showAppMenu({
  required BuildContext context,
  required List<AppMenuItem> items,
  String? header,
  RelativeRect? position,
}) {
  final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
  final buttonBox = context.findRenderObject() as RenderBox?;

  final effectivePosition = position ??
      (buttonBox != null
          ? RelativeRect.fromRect(
              Rect.fromPoints(
                buttonBox.localToGlobal(Offset.zero, ancestor: overlay),
                buttonBox.localToGlobal(
                  buttonBox.size.bottomRight(Offset.zero),
                  ancestor: overlay,
                ),
              ),
              Offset.zero & overlay.size,
            )
          : const RelativeRect.fromLTRB(0, 0, 0, 0));

  return Navigator.of(context).push(
    _AppMenuRoute(
      position: effectivePosition,
      items: items,
      header: header,
    ),
  );
}

class _AppMenuRoute extends PopupRoute<void> {
  _AppMenuRoute({
    required this.position,
    required this.items,
    required this.header,
  });

  final RelativeRect position;
  final List<AppMenuItem> items;
  final String? header;

  @override
  Color? get barrierColor => Colors.transparent;

  @override
  bool get barrierDismissible => true;

  @override
  String? get barrierLabel => 'Dismiss menu';

  @override
  Duration get transitionDuration => const Duration(milliseconds: 150);

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) {
    return CustomSingleChildLayout(
      delegate: _AppMenuLayoutDelegate(position),
      child: FadeTransition(
        opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
        child: _AppMenuPanel(items: items, header: header),
      ),
    );
  }
}

class _AppMenuLayoutDelegate extends SingleChildLayoutDelegate {
  _AppMenuLayoutDelegate(this.position);

  final RelativeRect position;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) {
    return BoxConstraints.loose(constraints.biggest);
  }

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    final left = position.left;
    final top = position.top;
    final containerWidth = size.width - position.left - position.right;
    final containerHeight = size.height - position.top - position.bottom;

    double dx = left;
    double dy = top;

    // Keep the menu on-screen, anchored to the button's rect.
    if (dx + childSize.width > size.width - AppSpacing.sm) {
      dx = size.width - childSize.width - AppSpacing.sm;
    }
    if (dx < AppSpacing.sm) {
      dx = AppSpacing.sm;
    }
    if (dy + childSize.height > size.height - AppSpacing.sm) {
      dy = size.height - childSize.height - AppSpacing.sm;
    }
    if (dy < AppSpacing.sm) {
      dy = AppSpacing.sm;
    }

    // Unused, but keeps container size referenced for clarity/lints.
    assert(containerWidth >= 0 && containerHeight >= 0);

    return Offset(dx, dy);
  }

  @override
  bool shouldRelayout(_AppMenuLayoutDelegate oldDelegate) {
    return position != oldDelegate.position;
  }
}

class _AppMenuPanel extends StatelessWidget {
  const _AppMenuPanel({required this.items, required this.header});

  final List<AppMenuItem> items;
  final String? header;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Container(
        width: AppRadius.menuWidth,
        decoration: BoxDecoration(
          color: AppColors.surfaceRaised,
          borderRadius: BorderRadius.circular(AppRadius.menu),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (header != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.lg,
                  AppSpacing.md,
                  AppSpacing.lg,
                  AppSpacing.sm,
                ),
                child: Text(
                  header!,
                  style: AppTypography.label(AppColors.textSecondary),
                ),
              ),
            for (final item in items) _AppMenuRow(item: item),
          ],
        ),
      ),
    );
  }
}

class _AppMenuRow extends StatelessWidget {
  const _AppMenuRow({required this.item});

  final AppMenuItem item;

  @override
  Widget build(BuildContext context) {
    final color =
        item.destructive ? AppColors.destructive : AppColors.textPrimary;

    Widget icon = Icon(item.icon, size: 20, color: color);

    if (item.iconWell) {
      icon = Container(
        width: _iconWellSize,
        height: _iconWellSize,
        decoration: const BoxDecoration(
          shape: BoxShape.circle,
          color: AppColors.surfaceIconWell,
        ),
        child: Center(child: icon),
      );
    }

    return InkWell(
      onTap: () {
        Navigator.of(context).pop();
        item.onTap();
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.sm,
        ),
        child: Row(
          children: [
            icon,
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Text(
                item.label,
                style: AppTypography.body(color),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
