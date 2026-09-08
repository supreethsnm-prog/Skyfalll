import 'package:flutter/material.dart';
import '../../core/theme/app_radius.dart';

class AppChip extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;
  final bool selected;

  const AppChip({
    super.key,
    required this.label,
    this.onTap,
    this.selected = false,
  });

  @override
  Widget build(BuildContext context) {
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: onTap == null ? null : (_) => onTap!(),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.control),
      ),
    );
  }
}
