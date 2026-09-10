import 'package:flutter_test/flutter_test.dart';
import 'package:weathergpt_app/core/theme/app_colors.dart';
import 'package:weathergpt_app/features/home/nwp_bands.dart';

void main() {
  group('capeBand', () {
    test('a null CAPE has no band — "not modelled" must never read as '
        'Minimal', () {
      expect(capeBand(null), isNull);
    });

    test('pins every documented boundary', () {
      expect(capeBand(299), 'Minimal');
      expect(capeBand(300), 'Marginal');
      expect(capeBand(999), 'Marginal');
      expect(capeBand(1000), 'Moderate');
      expect(capeBand(2499), 'Moderate');
      expect(capeBand(2500), 'Strong');
      expect(capeBand(3999), 'Strong');
      expect(capeBand(4000), 'Extreme');
    });

    test('zero and negative CAPE are Minimal rather than throwing', () {
      expect(capeBand(0), 'Minimal');
      expect(capeBand(-5), 'Minimal');
    });

    test('a very large CAPE stays Extreme', () {
      expect(capeBand(6000), 'Extreme');
    });
  });

  group('capSeverityForCapeBand', () {
    test('maps the four hazardous bands onto four DISTINCT CAP colours', () {
      // Pins what actually matters visually: each hazardous band must be
      // tellable apart from the others at a glance.
      final colours = ['Marginal', 'Moderate', 'Strong', 'Extreme']
          .map((band) => AppColors.alertSeverity(capSeverityForCapeBand(band)))
          .toSet();
      expect(colours, hasLength(4));
    });

    test(
        '"Minimal" has no CAP mapping — rendered neutrally, never as a real '
        "band's colour", () {
      expect(capSeverityForCapeBand('Minimal'), isNull);
    });

    test('a null band (no CAPE reading at all) also has no mapping', () {
      expect(capSeverityForCapeBand(null), isNull);
    });

    test('an unrecognised band returns null rather than guessing', () {
      expect(capSeverityForCapeBand('Unknown'), isNull);
      expect(capSeverityForCapeBand(''), isNull);
    });
  });

  group('isGaleForceGust', () {
    test('a null gust has no answer', () {
      expect(isGaleForceGust(null), isNull);
    });

    test('pins the IMD gale threshold at 62 km/h', () {
      expect(isGaleForceGust(61.9), false);
      expect(isGaleForceGust(62.0), true);
      expect(isGaleForceGust(62.1), true);
    });
  });
}
