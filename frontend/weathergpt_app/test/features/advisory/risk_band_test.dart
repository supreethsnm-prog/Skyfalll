import 'package:flutter_test/flutter_test.dart';
import 'package:weathergpt_app/core/theme/app_colors.dart';
import 'package:weathergpt_app/features/advisory/risk_band.dart';

void main() {
  group('capSeverityForRiskBand', () {
    test('maps each of the four documented bands onto its CAP word', () {
      expect(capSeverityForRiskBand('LOW'), 'minor');
      expect(capSeverityForRiskBand('MODERATE'), 'moderate');
      expect(capSeverityForRiskBand('HIGH'), 'severe');
      expect(capSeverityForRiskBand('SEVERE'), 'extreme');
    });

    test('those four mappings resolve to four DISTINCT colours', () {
      // Pins the actual thing that matters visually: each band must be
      // tellable apart from the others at a glance, not just individually
      // "correct" against a string.
      final colours = ['LOW', 'MODERATE', 'HIGH', 'SEVERE']
          .map((band) => AppColors.alertSeverity(capSeverityForRiskBand(band)))
          .toSet();
      expect(colours, hasLength(4));
    });

    test('an unknown band is not mapped to LOW', () {
      // The backend's own escape hatch for missing forecast data — must
      // never read as a confident, known-safe LOW.
      expect(capSeverityForRiskBand('UNKNOWN'), isNot('minor'));
      expect(capSeverityForRiskBand('UNKNOWN'), isNull);
    });

    test('an unrecognised value returns null rather than guessing', () {
      expect(capSeverityForRiskBand(''), isNull);
      expect(capSeverityForRiskBand('EXTREME'), isNull);
    });

    test('matching is exact-case: the contract guarantees uppercase', () {
      expect(capSeverityForRiskBand('low'), isNull);
      expect(capSeverityForRiskBand('Low'), isNull);
    });
  });
}
