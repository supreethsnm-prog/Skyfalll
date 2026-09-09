import 'package:flutter/material.dart';

/// Colours sampled directly from the reference screenshots in
/// backend/FrontendReference/ — see
/// docs/superpowers/specs/2026-09-09-flutter-design-literal.md §2.
/// These are measured values, not design choices; do not "improve" them.
class AppColors {
  AppColors._();

  /// Page and sidebar background. True black, as sampled.
  static const bgBase = Color(0xFF000000);

  /// The single raised-chrome colour: round icon buttons, the composer
  /// pill, dropdown menus, the attach menu. One colour for all of them.
  static const surfaceRaised = Color(0xFF212121);

  /// Inset surfaces that sit *below* the base — code blocks.
  static const surfaceInset = Color(0xFF131313);

  /// Small icon wells inside menus.
  static const surfaceIconWell = Color(0xFF454545);

  /// Hairlines and blockquote rules.
  static const divider = Color(0xFF434343);

  static const textPrimary = Color(0xFFFFFFFF);
  static const textSecondary = Color(0xFF9E9E9E);

  /// Accent: send/voice button, the sidebar "Chat" pill, links.
  static const accent = Color(0xFF3A83F6);

  /// User message bubble fill.
  static const userBubble = Color(0xFF133362);

  /// Account avatar circle.
  static const avatarFill = Color(0xFF7E8C8D);

  /// Destructive actions ("Delete"). Inferred rather than sampled — only
  /// anti-aliased edge pixels were recoverable from the reference.
  static const destructive = Color(0xFFEF4444);

  // Alert severity scale, carried over unchanged — keyed to the CAP
  // levels the backend's SACHET-sourced alerts use.
  static const _severityMinor = Color(0xFFF3D9AE);
  static const _severityModerate = Color(0xFFD98E2B);
  static const _severitySevere = Color(0xFFC23B4B);
  static const _severityExtreme = Color(0xFF8F2836);

  static Color alertSeverity(String? capSeverity) {
    switch (capSeverity?.toLowerCase()) {
      case 'minor':
        return _severityMinor;
      case 'moderate':
        return _severityModerate;
      case 'severe':
        return _severitySevere;
      case 'extreme':
        return _severityExtreme;
      default:
        return _severityModerate;
    }
  }

  /// Readable label colour for a severity chip, chosen by contrast ratio
  /// against that severity's own background.
  static Color onAlertSeverity(String? capSeverity) {
    final background = alertSeverity(capSeverity);
    final onDark = _contrastRatio(background, textPrimary);
    final onLight = _contrastRatio(background, bgBase);
    return onDark >= onLight ? textPrimary : bgBase;
  }

  static double _contrastRatio(Color a, Color b) {
    final la = a.computeLuminance();
    final lb = b.computeLuminance();
    final brighter = la > lb ? la : lb;
    final darker = la > lb ? lb : la;
    return (brighter + 0.05) / (darker + 0.05);
  }
}
