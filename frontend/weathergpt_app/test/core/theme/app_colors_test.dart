import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weathergpt_app/core/theme/app_colors.dart';

/// WCAG relative contrast ratio between two opaque colours.
double _ratio(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final brighter = la > lb ? la : lb;
  final darker = la > lb ? lb : la;
  return (brighter + 0.05) / (darker + 0.05);
}

void main() {
  group('AppColors.alertSeverity', () {
    // The CAP severities the backend's SACHET-sourced alerts use.
    const severities = ['minor', 'moderate', 'severe', 'extreme'];

    test('returns a distinct colour for each known CAP severity', () {
      final colors = severities.map(AppColors.alertSeverity).toSet();
      expect(colors.length, severities.length,
          reason: 'every severity must render as a visually distinct chip');
    });

    test('is case-insensitive', () {
      expect(AppColors.alertSeverity('MODERATE'),
          AppColors.alertSeverity('moderate'));
      expect(
          AppColors.alertSeverity('Severe'), AppColors.alertSeverity('severe'));
    });

    test('falls back to a sane default for an unknown or null severity', () {
      // "Moderate" is the defensible default: unknown severity should read
      // as a real caution colour, not silently vanish or crash.
      final fallback = AppColors.alertSeverity('moderate');
      expect(AppColors.alertSeverity(null), fallback);
      expect(AppColors.alertSeverity(''), fallback);
      expect(AppColors.alertSeverity('not-a-cap-severity'), fallback);
    });

    test('the default is one of the four known severity colours', () {
      final known = severities.map(AppColors.alertSeverity).toSet();
      expect(known, contains(AppColors.alertSeverity(null)));
    });
  });

  group('AppColors.onAlertSeverity', () {
    const severities = ['minor', 'moderate', 'severe', 'extreme'];

    test('clears 4.5:1 against its own background for every severity', () {
      // Assert the actual ratio, not merely that the result equals some
      // expected constant — this is the check that would have caught a
      // palette change silently breaking a legibility guarantee.
      for (final severity in [...severities, null, 'unknown']) {
        final background = AppColors.alertSeverity(severity);
        final foreground = AppColors.onAlertSeverity(severity);
        expect(_ratio(background, foreground), greaterThanOrEqualTo(4.5),
            reason: 'severity=$severity background=$background '
                'foreground=$foreground');
      }
    });

    test('always picks the better-contrasting of the two candidate '
        'foregrounds', () {
      // Guards against the picker being inverted: whichever colour it
      // returns must score at least as well as the one it rejected.
      for (final severity in severities) {
        final background = AppColors.alertSeverity(severity);
        final chosen = AppColors.onAlertSeverity(severity);
        final rejected = chosen == AppColors.textPrimary
            ? AppColors.bgBase
            : AppColors.textPrimary;

        expect(_ratio(background, chosen),
            greaterThanOrEqualTo(_ratio(background, rejected)),
            reason: 'severity=$severity picked the worse foreground');
      }
    });
  });
}
