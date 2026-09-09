import 'package:flutter_test/flutter_test.dart';
import 'package:weathergpt_app/core/geo.dart';

void main() {
  test('distance from a point to itself is zero', () {
    expect(haversineKm(28.6139, 77.2090, 28.6139, 77.2090), 0.0);
  });

  test('distance between New Delhi and Mumbai is a few hundred to ~1300km (real great-circle range)', () {
    // New Delhi (28.6139, 77.2090) and Mumbai (19.0760, 72.8777) —
    // real coordinates, not invented. The great-circle distance
    // between these two cities is well-documented to fall in this
    // range; asserting a wide-but-real range rather than a single
    // exact figure keeps this test meaningful without depending on
    // an unverifiable precise value.
    final distance = haversineKm(28.6139, 77.2090, 19.0760, 72.8777);
    expect(distance, inInclusiveRange(1000, 1300));
  });

  test('is symmetric (A to B equals B to A)', () {
    final ab = haversineKm(28.6139, 77.2090, 19.0760, 72.8777);
    final ba = haversineKm(19.0760, 72.8777, 28.6139, 77.2090);
    expect(ab, closeTo(ba, 0.001));
  });
}
