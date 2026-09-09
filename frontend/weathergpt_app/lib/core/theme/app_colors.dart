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

  /// Fill for [GlassPanel]. The reference's panels sample only 2-4% lighter
  /// than the sky behind them (spec §2.2), so this is deliberately far below
  /// an "opaque card" alpha. It is also load-bearing for contrast: text
  /// inside a panel sits on this composited over the sky, not on the sky, so
  /// raising it pushes the darker skies below WCAG AA. See
  /// sky_gradient.dart's AA note before changing it.
  static const Color glassFill = Color(0x08FFFFFF);

  // Alert severity scale, carried over unchanged — keyed to the CAP
  // levels the backend's SACHET-sourced alerts use.
  static const _severityMinor = Color(0xFFF3D9AE);
  static const _severityModerate = Color(0xFFD98E2B);
  static const _severitySevere = Color(0xFFC23B4B);
  static const _severityExtreme = Color(0xFF8F2836);

  /// Colour for an alert's severity.
  ///
  /// Accepts THREE vocabularies, because the live feed uses all of them:
  ///
  /// - CAP standard: minor / moderate / severe / extreme.
  /// - IMD colour codes: green / yellow / orange / red. This is what most
  ///   SACHET rows actually carry.
  /// - SACHET levels: watch / alert / warning.
  ///
  /// The first version of this only knew the CAP words, so every real
  /// alert — all of which say "Yellow", "Orange", "Watch" or "Alert" —
  /// fell through to the default and rendered identically. Check live
  /// data before trusting a severity vocabulary.
  ///
  /// Mapping follows IMD's own published meanings: yellow = watch (be
  /// updated), orange = alert (be prepared), red = warning (take action).
  static Color alertSeverity(String? capSeverity) {
    switch (capSeverity?.toLowerCase().trim()) {
      case 'minor':
      case 'green':
        return _severityMinor;
      case 'moderate':
      case 'yellow':
      case 'watch':
        return _severityModerate;
      case 'severe':
      case 'orange':
      case 'alert':
        return _severitySevere;
      case 'extreme':
      case 'red':
      case 'warning':
        return _severityExtreme;
      default:
        // An unrecognised severity is treated as significant rather than
        // trivial: under-warning is the dangerous direction.
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
