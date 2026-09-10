import 'package:flutter_test/flutter_test.dart';
import 'package:weathergpt_app/data/marine_api.dart';

void main() {
  group('PfzZone.fromJson', () {
    test('parses a real-shaped PFZ response (verified live)', () {
      final zone = PfzZone.fromJson({
        'id': 1,
        'external_id': 'pfzlines.1',
        'category': 'ghrsst',
        'sector_boundary': 3,
        'sector_name': '',
        'julian_day': '252',
        'serial_number': 'abc',
        'year': 2026,
        'uid': 1,
        'length_km': 58.3588654526,
        'geometry': {
          'type': 'MultiLineString',
          'coordinates': [
            [
              [72.4817, 20.1663],
              [72.4819, 20.1653],
            ],
          ],
        },
        'fetched_at': '2026-09-09T12:00:00Z',
      });

      expect(zone.id, 1);
      expect(zone.externalId, 'pfzlines.1');
      expect(zone.category, 'ghrsst');
      expect(zone.sectorBoundary, 3);
      expect(zone.julianDay, '252');
      expect(zone.year, 2026);
      expect(zone.lengthKm, 58.3588654526);
      expect(zone.lines, hasLength(1));
      expect(zone.lines.first, hasLength(2));
    });

    test(
        'GeoJSON [lon, lat] coordinates are not swapped into LatLng(lat, '
        'lon) — the single most likely bug in this feature: get it wrong '
        'and every zone lands in the wrong hemisphere', () {
      final zone = PfzZone.fromJson({
        'id': 1,
        'external_id': 'pfzlines.1',
        'category': 'ghrsst',
        'sector_boundary': 3,
        'sector_name': '',
        'julian_day': '252',
        'year': 2026,
        'length_km': 58.3588654526,
        'geometry': {
          'type': 'MultiLineString',
          'coordinates': [
            [
              [72.4817, 20.1663], // [lon, lat]
            ],
          ],
        },
      });

      final point = zone.lines.first.first;

      // India's real bounds (measured live): longitude 67.90-82.04,
      // latitude 7.87-23.48. A lon/lat swap would put 72.4817 in `latitude`
      // (out of India's latitude range) and 20.1663 in `longitude` (also
      // out of India's longitude range) — this assertion fails either way
      // if the swap happens.
      expect(point.latitude, inInclusiveRange(7.87, 23.48));
      expect(point.longitude, inInclusiveRange(67.90, 82.04));
      expect(point.latitude, 20.1663);
      expect(point.longitude, 72.4817);
    });

    test(
        'a MultiLineString with several segments yields several point '
        'lists, not one line joining them together', () {
      final zone = PfzZone.fromJson({
        'id': 1,
        'external_id': 'pfzlines.1',
        'category': 'ghrsst',
        'sector_boundary': 3,
        'sector_name': '',
        'julian_day': '252',
        'year': 2026,
        'length_km': 12.0,
        'geometry': {
          'type': 'MultiLineString',
          'coordinates': [
            [
              [72.0, 20.0],
              [72.1, 20.1],
            ],
            [
              [75.0, 15.0],
              [75.1, 15.1],
              [75.2, 15.2],
            ],
            [
              [80.0, 10.0],
              [80.1, 10.1],
            ],
          ],
        },
      });

      expect(zone.lines, hasLength(3));
      expect(zone.lines[0], hasLength(2));
      expect(zone.lines[1], hasLength(3));
      expect(zone.lines[2], hasLength(2));
      // The three segments' points, flattened, must add up rather than one
      // segment silently absorbing another's points.
      expect(zone.allPoints, hasLength(7));
    });

    test('sector_name being empty on every live row does not break parsing',
        () {
      final zone = PfzZone.fromJson({
        'id': 1,
        'external_id': 'pfzlines.1',
        'category': 'ghrsst',
        'sector_boundary': 3,
        'sector_name': '',
        'julian_day': '252',
        'year': 2026,
        'length_km': 1.0,
        'geometry': {
          'type': 'MultiLineString',
          'coordinates': [
            [
              [72.0, 20.0],
              [72.1, 20.1],
            ],
          ],
        },
      });

      expect(zone.externalId, 'pfzlines.1');
    });
  });

  group('PfzZone.issueDate', () {
    test('converts julian_day "252" + year 2026 to 9 September 2026', () {
      const zone = PfzZone(
        id: 1,
        externalId: 'pfzlines.1',
        category: 'ghrsst',
        sectorBoundary: 3,
        julianDay: '252',
        year: 2026,
        lengthKm: 1.0,
        lines: [],
      );

      final date = zone.issueDate;
      expect(date.year, 2026);
      expect(date.month, 9);
      expect(date.day, 9);
    });

    test('converts julian_day "1" to 1 January of that year', () {
      const zone = PfzZone(
        id: 1,
        externalId: 'pfzlines.1',
        category: 'ghrsst',
        sectorBoundary: 3,
        julianDay: '1',
        year: 2026,
        lengthKm: 1.0,
        lines: [],
      );

      final date = zone.issueDate;
      expect(date.year, 2026);
      expect(date.month, 1);
      expect(date.day, 1);
    });
  });
}
