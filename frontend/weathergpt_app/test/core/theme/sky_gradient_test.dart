import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weathergpt_app/core/theme/app_colors.dart';
import 'package:weathergpt_app/core/theme/sky_gradient.dart';

/// WCAG relative contrast ratio between two opaque colours.
double _ratio(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final brighter = la > lb ? la : lb;
  final darker = la > lb ? lb : la;
  return (brighter + 0.05) / (darker + 0.05);
}

/// Composites [fill] (translucent) over the opaque [base], per channel:
/// `fill.a * fill.channel + (1 - fill.a) * base.channel`. This is what a
/// viewer actually sees when a [GlassPanel] sits over a sky stop — text
/// inside the panel reads against THIS colour, not the bare sky.
Color _compositeOver(Color fill, Color base) {
  double mix(double f, double b) => fill.a * f + (1 - fill.a) * b;
  return Color.from(
    alpha: 1.0,
    red: mix(fill.r, base.r),
    green: mix(fill.g, base.g),
    blue: mix(fill.b, base.b),
  );
}

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

  group('skyForeground', () {
    // White type washes out on the light dawn/day skies sampled from the
    // Google Weather reference, so Home flips to near-black over them.
    test('is dark on the light day and dawn skies', () {
      for (final time in [SkyTimeOfDay.day, SkyTimeOfDay.dawn]) {
        for (final condition in [SkyCondition.clear, SkyCondition.cloudy]) {
          expect(skyForeground(time, condition), AppColors.bgBase,
              reason: '$time/$condition is a light sky');
        }
      }
    });

    test('is white on every night sky', () {
      for (final condition in SkyCondition.values) {
        expect(skyForeground(SkyTimeOfDay.night, condition),
            AppColors.textPrimary,
            reason: 'night/$condition');
      }
    });

    test('always picks the better-contrasting of the two foregrounds', () {
      // Guards against the picker being inverted: whichever colour it
      // returns must score at least as well, at the gradient's weakest
      // stop, as the one it rejected.
      for (final time in SkyTimeOfDay.values) {
        for (final condition in SkyCondition.values) {
          final stops = skyGradient(time, condition).colors;
          double worst(Color fg) => stops
              .map((s) => _ratio(s, fg))
              .reduce((a, b) => a < b ? a : b);

          final chosen = skyForeground(time, condition);
          final rejected = chosen == AppColors.textPrimary
              ? AppColors.bgBase
              : AppColors.textPrimary;

          expect(worst(chosen), greaterThanOrEqualTo(worst(rejected)),
              reason: '$time/$condition picked the worse foreground');
        }
      }
    });

    test('all 24 skies clear WCAG AA against their own foreground', () {
      // No exception list: seven mid-tone gradients used to fail this
      // against BOTH foregrounds and were darkened (see the AA note in
      // sky_gradient.dart). Every stop is checked, not an average —
      // Home's text spans the whole gradient.
      for (final time in SkyTimeOfDay.values) {
        for (final condition in SkyCondition.values) {
          final fg = skyForeground(time, condition);
          for (final stop in skyGradient(time, condition).colors) {
            expect(_ratio(stop, fg), greaterThanOrEqualTo(4.5),
                reason: '$time/$condition stop $stop vs $fg');
          }
        }
      }
    });

    test(
        'all 24 skies clear WCAG AA against their foreground THROUGH '
        'GlassPanel', () {
      // This is the test whose absence let the contrast bug ship: a prior
      // pass verified only the bare sky and left ~0.4% headroom on the
      // worst stops, which GlassPanel's white fill then consumed. Text
      // inside a panel sits on the sky COMPOSITED with
      // AppColors.glassFill, not on the bare sky, so that is what must be
      // checked — and this must keep catching it if any future
      // compositing layer does the same thing again (raise the fill,
      // stack another translucent layer, etc.), which is why this
      // composites explicitly here rather than trusting the bare-sky
      // test above to generalise.
      for (final time in SkyTimeOfDay.values) {
        for (final condition in SkyCondition.values) {
          final fg = skyForeground(time, condition);
          for (final stop in skyGradient(time, condition).colors) {
            final composited = _compositeOver(AppColors.glassFill, stop);
            expect(_ratio(composited, fg), greaterThanOrEqualTo(4.5),
                reason:
                    '$time/$condition stop $stop composited with glassFill '
                    '-> $composited vs $fg');
          }
        }
      }
    });
  });
}
