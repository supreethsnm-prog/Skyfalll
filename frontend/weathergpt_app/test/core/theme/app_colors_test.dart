import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weathergpt_app/core/theme/app_colors.dart';

void main() {
  test('alertSeverity maps known CAP levels to their colors', () {
    expect(AppColors.alertSeverity('Extreme'), const Color(0xFF8F2836));
    expect(AppColors.alertSeverity('severe'), const Color(0xFFC23B4B));
    expect(AppColors.alertSeverity('MODERATE'), const Color(0xFFD98E2B));
    expect(AppColors.alertSeverity('minor'), const Color(0xFFF3D9AE));
  });

  test('alertSeverity falls back to Moderate for an unrecognized or missing value', () {
    expect(AppColors.alertSeverity('Unknown'), const Color(0xFFD98E2B));
    expect(AppColors.alertSeverity(null), const Color(0xFFD98E2B));
  });

  test('onAlertSeverity always picks the higher-contrast of the two label colors', () {
    double contrastRatio(Color a, Color b) {
      final lumA = a.computeLuminance();
      final lumB = b.computeLuminance();
      final brighter = lumA > lumB ? lumA : lumB;
      final darker = lumA > lumB ? lumB : lumA;
      return (brighter + 0.05) / (darker + 0.05);
    }

    for (final severity in ['Minor', 'Moderate', 'Severe', 'Extreme']) {
      final background = AppColors.alertSeverity(severity);
      final label = AppColors.onAlertSeverity(severity);
      final inkContrast = contrastRatio(background, AppColors.monsoonInk);
      final cloudContrast = contrastRatio(background, AppColors.cloudlight);
      final expected = inkContrast >= cloudContrast ? AppColors.monsoonInk : AppColors.cloudlight;

      expect(label, expected,
          reason: '$severity: ink contrast $inkContrast, cloud contrast $cloudContrast');

      // The winning color must clear the WCAG AA body-text bar (4.5:1)
      // against its own background — the real accessibility assertion.
      final winningContrast = label == AppColors.monsoonInk ? inkContrast : cloudContrast;
      expect(winningContrast, greaterThanOrEqualTo(4.5),
          reason: '$severity label/background contrast too low: $winningContrast');
    }
  });

  test('onAlertSeverity is near-white on the two dark severities and Monsoon Ink on the two light ones', () {
    expect(AppColors.onAlertSeverity('Severe'), AppColors.cloudlight);
    expect(AppColors.onAlertSeverity('Extreme'), AppColors.cloudlight);
    expect(AppColors.onAlertSeverity('Minor'), AppColors.monsoonInk);
    expect(AppColors.onAlertSeverity('Moderate'), AppColors.monsoonInk);
  });
}
