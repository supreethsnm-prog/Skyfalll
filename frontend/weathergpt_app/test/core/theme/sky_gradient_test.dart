import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weathergpt_app/core/theme/sky_gradient.dart';

void main() {
  group('skyTimeOfDayFor', () {
    test('classifies the day into dawn/day/dusk/night', () {
      expect(skyTimeOfDayFor(DateTime(2026, 9, 9, 5, 30)), SkyTimeOfDay.dawn);
      expect(skyTimeOfDayFor(DateTime(2026, 9, 9, 12, 0)), SkyTimeOfDay.day);
      expect(skyTimeOfDayFor(DateTime(2026, 9, 9, 18, 30)), SkyTimeOfDay.dusk);
      expect(skyTimeOfDayFor(DateTime(2026, 9, 9, 23, 0)), SkyTimeOfDay.night);
      expect(skyTimeOfDayFor(DateTime(2026, 9, 9, 2, 0)), SkyTimeOfDay.night);
    });
  });

  group('skyConditionFor', () {
    test('buckets WMO codes', () {
      expect(skyConditionFor(0), SkyCondition.clear);
      expect(skyConditionFor(2), SkyCondition.cloudy);
      expect(skyConditionFor(45), SkyCondition.fog);
      expect(skyConditionFor(63), SkyCondition.rain);
      expect(skyConditionFor(73), SkyCondition.snow);
      expect(skyConditionFor(95), SkyCondition.thunderstorm);
    });

    test('falls back to cloudy for an unrecognised code', () {
      expect(skyConditionFor(-1), SkyCondition.cloudy);
      expect(skyConditionFor(999), SkyCondition.cloudy);
    });
  });

  group('skyGradient', () {
    test('day+cloudy reproduces the sampled reference exactly', () {
      final gradient = skyGradient(SkyTimeOfDay.day, SkyCondition.cloudy);
      expect(gradient.colors.first, const Color(0xFFC8D3E9));
      expect(gradient.colors[1], const Color(0xFF7995C4));
      expect(gradient.colors.last, const Color(0xFF93A8C7));
    });

    test('every combination returns a usable multi-stop gradient', () {
      for (final time in SkyTimeOfDay.values) {
        for (final condition in SkyCondition.values) {
          final gradient = skyGradient(time, condition);
          expect(gradient.colors.length, greaterThanOrEqualTo(3),
              reason: '$time/$condition');
        }
      }
    });

    test('night gradients stay dark enough for white text', () {
      for (final condition in SkyCondition.values) {
        final gradient = skyGradient(SkyTimeOfDay.night, condition);
        for (final color in gradient.colors) {
          expect(color.computeLuminance(), lessThan(0.35),
              reason: 'night/$condition stop $color is too light for white text');
        }
      }
    });

    test('day gradients are lighter than their night counterparts', () {
      for (final condition in SkyCondition.values) {
        final day = skyGradient(SkyTimeOfDay.day, condition)
            .colors
            .map((c) => c.computeLuminance())
            .reduce((a, b) => a + b);
        final night = skyGradient(SkyTimeOfDay.night, condition)
            .colors
            .map((c) => c.computeLuminance())
            .reduce((a, b) => a + b);
        expect(day, greaterThan(night), reason: condition.toString());
      }
    });
  });
}
