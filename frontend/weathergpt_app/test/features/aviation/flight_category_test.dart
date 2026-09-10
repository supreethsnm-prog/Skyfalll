import 'package:flutter_test/flutter_test.dart';
import 'package:weathergpt_app/core/theme/app_colors.dart';
import 'package:weathergpt_app/features/aviation/flight_category.dart';

void main() {
  group('capSeverityForFlightCategory', () {
    test('maps each of the four documented categories onto its CAP word', () {
      expect(capSeverityForFlightCategory('VFR'), 'minor');
      expect(capSeverityForFlightCategory('MVFR'), 'moderate');
      expect(capSeverityForFlightCategory('IFR'), 'severe');
      expect(capSeverityForFlightCategory('LIFR'), 'extreme');
    });

    test('those four mappings resolve to four DISTINCT colours', () {
      final colours = ['VFR', 'MVFR', 'IFR', 'LIFR']
          .map((c) => AppColors.alertSeverity(capSeverityForFlightCategory(c)))
          .toSet();
      expect(colours, hasLength(4));
    });

    test('a null category (the station reported no derivable category) '
        'is not mapped to VFR', () {
      // Null is a real, documented possibility on MetarReading.flightCategory
      // — must never read as a confident, known-good VFR.
      expect(capSeverityForFlightCategory(null), isNot('minor'));
      expect(capSeverityForFlightCategory(null), isNull);
    });

    test('an unrecognised non-null value returns null rather than guessing',
        () {
      expect(capSeverityForFlightCategory(''), isNull);
      expect(capSeverityForFlightCategory('UNKNOWN'), isNull);
    });

    test('matching is exact-case: the contract guarantees uppercase', () {
      expect(capSeverityForFlightCategory('vfr'), isNull);
      expect(capSeverityForFlightCategory('Vfr'), isNull);
    });
  });
}
