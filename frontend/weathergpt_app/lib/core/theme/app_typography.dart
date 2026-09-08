import 'package:flutter/material.dart';

/// WeatherGPT's type scale: Sora for display/headline/title, Inter for
/// body/UI text, IBMPlexMono for raw meteorological codes (METAR
/// strings, coordinates) only — never as a general UI/label font.
///
/// Sora and Inter ship as OFL-licensed variable fonts (one file spans a
/// weight axis) — [FontVariation] selects the weight instance;
/// [FontWeight] alone only distinguishes a font's registered STATIC
/// weights and would not pick the right instance out of a single
/// variable-font file.
class AppTypography {
  AppTypography._();

  static const _sora = 'Sora';
  static const _inter = 'Inter';
  static const _mono = 'IBMPlexMono';

  static TextStyle display(Color color) => TextStyle(
        fontFamily: _sora,
        fontVariations: const [FontVariation('wght', 600)],
        fontSize: 40,
        height: 44 / 40,
        color: color,
      );

  static TextStyle headline(Color color) => TextStyle(
        fontFamily: _sora,
        fontVariations: const [FontVariation('wght', 600)],
        fontSize: 24,
        height: 30 / 24,
        color: color,
      );

  static TextStyle title(Color color) => TextStyle(
        fontFamily: _sora,
        fontVariations: const [FontVariation('wght', 500)],
        fontSize: 18,
        height: 24 / 18,
        color: color,
      );

  static TextStyle bodyLarge(Color color) => TextStyle(
        fontFamily: _inter,
        fontVariations: const [FontVariation('wght', 400)],
        fontSize: 16,
        height: 24 / 16,
        color: color,
      );

  static TextStyle body(Color color) => TextStyle(
        fontFamily: _inter,
        fontVariations: const [FontVariation('wght', 400)],
        fontSize: 14,
        height: 20 / 14,
        color: color,
      );

  static TextStyle caption(Color color) => TextStyle(
        fontFamily: _inter,
        fontVariations: const [FontVariation('wght', 500)],
        fontSize: 12,
        height: 16 / 12,
        color: color,
      );

  static TextStyle code(Color color) => TextStyle(
        fontFamily: _mono,
        fontWeight: FontWeight.w400,
        fontSize: 13,
        height: 18 / 13,
        color: color,
      );
}
