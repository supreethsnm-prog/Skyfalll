import 'package:flutter/material.dart';

/// WeatherGPT's "Monsoon Sky" palette — see
/// docs/superpowers/specs/2026-09-08-flutter-frontend-design.md for the
/// rationale behind each color.
class AppColors {
  AppColors._();

  // Core palette
  static const monsoonInk = Color(0xFF171B2E);
  static const stormSlate = Color(0xFF2B3358);
  static const cloudlight = Color(0xFFF5F6F4);
  static const marigold = Color(0xFFE8A33D);
  static const paddyGreen = Color(0xFF3F8F6B);
  static const alertCrimson = Color(0xFFC23B4B);

  // Text hierarchy
  static const lightTextPrimary = Color(0xFF1B2340);
  static const lightTextSecondary = Color(0xFF5B6178);
  static const darkTextPrimary = Color(0xFFEDEEF2);
  static const darkTextSecondary = Color(0xFF9DA3C2);

  // Alert severity scale, keyed to the CAP protocol levels the backend's
  // SACHET-sourced alerts already use (Minor/Moderate/Severe/Extreme).
  static const _severityMinor = Color(0xFFF3D9AE);
  static const _severityModerate = Color(0xFFD98E2B);
  static const _severitySevere = alertCrimson;
  static const _severityExtreme = Color(0xFF8F2836);

  /// Maps a CAP severity string (as returned by the backend's alert
  /// endpoints) to its display color. An unrecognized value — a typo, a
  /// new level a future feed change introduces — falls back to
  /// [_severityModerate] rather than throwing; a malformed severity
  /// string must never crash the alerts screen.
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

  /// Returns a readable label color for text drawn on top of
  /// [alertSeverity]'s background for the same [capSeverity]. Computed
  /// from the background color's actual luminance
  /// ([Color.computeLuminance]) rather than a hardcoded per-name guess,
  /// so it stays correct if the severity hex values ever change.
  ///
  /// Picks whichever of [monsoonInk] / [cloudlight] yields the higher
  /// WCAG contrast ratio against the background — not a flat "luminance
  /// > 0.5" split, which (checked against these actual hex values) would
  /// wrongly hand Moderate's mid-luminance orange a near-white label
  /// even though Monsoon Ink contrasts against it far better.
  static Color onAlertSeverity(String? capSeverity) {
    final background = alertSeverity(capSeverity);
    final contrastWithInk = _contrastRatio(background, monsoonInk);
    final contrastWithCloud = _contrastRatio(background, cloudlight);
    return contrastWithInk >= contrastWithCloud ? monsoonInk : cloudlight;
  }

  /// WCAG relative-luminance contrast ratio between two colors, in
  /// [1, 21] — see https://www.w3.org/TR/WCAG21/#dfn-contrast-ratio.
  static double _contrastRatio(Color a, Color b) {
    final lumA = a.computeLuminance();
    final lumB = b.computeLuminance();
    final brighter = lumA > lumB ? lumA : lumB;
    final darker = lumA > lumB ? lumB : lumA;
    return (brighter + 0.05) / (darker + 0.05);
  }
}
