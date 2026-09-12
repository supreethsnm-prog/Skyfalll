import 'package:flutter/material.dart';

/// Roboto, matching the Android reference screenshots (Roboto is
/// Android's system typeface, so this is the literal match rather than a
/// substitution). RobotoMono is used only for code blocks and raw
/// meteorological codes.
///
/// Sizes marked "approx" were estimated from the reference screenshots
/// rather than measured exactly, and should be tuned against the golden
/// images if they read wrong.
class AppTypography {
  AppTypography._();

  static const sans = 'Roboto';
  static const mono = 'RobotoMono';
  static const fallbackFonts = ['NotoSansKannada', 'NotoSansDevanagari'];

  static TextStyle _sans(double size, FontWeight weight, Color color,
          {double? height}) =>
      TextStyle(
        fontFamily: sans,
        fontFamilyFallback: fallbackFonts,
        fontSize: size,
        fontWeight: weight,
        color: color,
        height: height,
      );

  /// Home hero temperature. Very large; approx.
  static TextStyle hero(Color color) =>
      _sans(112, FontWeight.w300, color, height: 1.0);

  /// Sidebar wordmark ("WeatherGPT"). Approx.
  static TextStyle wordmark(Color color) => _sans(28, FontWeight.w700, color);

  /// Screen titles, Home condition line. Approx.
  static TextStyle title(Color color) => _sans(20, FontWeight.w400, color);

  /// Chat message body, menu rows, composer text.
  static TextStyle body(Color color) =>
      _sans(16, FontWeight.w400, color, height: 1.45);

  /// Emphasised body (bold runs inside assistant messages).
  static TextStyle bodyBold(Color color) =>
      _sans(16, FontWeight.w700, color, height: 1.45);

  /// Section headers ("Pinned", "Recents"), timestamps, captions.
  static TextStyle label(Color color) => _sans(14, FontWeight.w400, color);

  /// Small supporting text under forecast rows.
  static TextStyle caption(Color color) => _sans(12, FontWeight.w400, color);

  /// Code blocks and raw meteorological codes.
  static TextStyle code(Color color) => TextStyle(
        fontFamily: mono,
        fontSize: 13,
        fontWeight: FontWeight.w400,
        height: 1.45,
        color: color,
      );
}
