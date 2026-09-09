import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weathergpt_app/core/network/app_error.dart';
import 'package:weathergpt_app/data/geocoding_api.dart';
import 'package:weathergpt_app/features/home/home_controller.dart';
import 'package:weathergpt_app/features/home/widgets/location_search_sheet.dart';

/// The three outcomes of a search must stay distinguishable.
///
/// "Not found" is the one that matters: the backend returns 404 for an
/// unknown place, and if that were shown as a generic error the user
/// would go debugging their connection instead of their spelling.

const _pune = GeocodeResult(
  displayName: 'Pune, Maharashtra, India',
  latitude: 18.5204,
  longitude: 73.8567,
  country: 'India',
  state: 'Maharashtra',
);

class _StubGeocoding implements GeocodingApi {
  _StubGeocoding({this.result, this.error});

  final GeocodeResult? result;
  final AppError? error;
  final queries = <String>[];

  @override
  Future<GeocodeResult?> search(String query) async {
    queries.add(query);
    if (error != null) throw error!;
    return result;
  }

  @override
  Future<GeocodeResult?> reverse(double lat, double lon) async => null;

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

Future<void> _pumpSheet(WidgetTester tester, _StubGeocoding geocoding) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [geocodingApiProvider.overrideWithValue(geocoding)],
      child: const MaterialApp(
        home: Scaffold(body: LocationSearchSheet()),
      ),
    ),
  );
  await tester.pump();
}

Future<void> _search(WidgetTester tester, String query) async {
  await tester.enterText(find.byType(TextField), query);
  await tester.testTextInput.receiveAction(TextInputAction.search);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
}

void main() {
  testWidgets('a found place is offered for selection', (tester) async {
    await _pumpSheet(tester, _StubGeocoding(result: _pune));

    await _search(tester, 'Pune');

    expect(find.text('Pune, Maharashtra, India'), findsOneWidget);
  });

  testWidgets('a 404 says not found, naming what was typed', (tester) async {
    // GeocodingApi.search returns null for 404 rather than throwing.
    await _pumpSheet(tester, _StubGeocoding(result: null));

    await _search(tester, 'Puneee');

    expect(find.textContaining('No place found'), findsOneWidget);
    // Echoing the query is what lets someone spot their own typo.
    expect(find.textContaining('Puneee'), findsWidgets);
  });

  testWidgets('a not-found result is NOT presented as an error',
      (tester) async {
    await _pumpSheet(tester, _StubGeocoding(result: null));

    await _search(tester, 'Puneee');

    // The connection-error copy must not appear for a spelling mistake.
    expect(find.textContaining("Can't reach"), findsNothing);
    expect(find.textContaining('went wrong'), findsNothing);
  });

  testWidgets('a real failure shows the network message', (tester) async {
    await _pumpSheet(
      tester,
      _StubGeocoding(error: const NetworkConnectionError()),
    );

    await _search(tester, 'Pune');

    expect(find.textContaining("Can't reach the weather service"),
        findsOneWidget);
    expect(find.textContaining('No place found'), findsNothing);
  });

  testWidgets('an empty query does not hit the API', (tester) async {
    final geocoding = _StubGeocoding(result: _pune);
    await _pumpSheet(tester, geocoding);

    await _search(tester, '   ');

    expect(geocoding.queries, isEmpty);
  });

  testWidgets('the query is trimmed before searching', (tester) async {
    final geocoding = _StubGeocoding(result: _pune);
    await _pumpSheet(tester, geocoding);

    await _search(tester, '  Pune  ');

    expect(geocoding.queries.single, 'Pune');
  });

  testWidgets('offers a way back to the device location', (tester) async {
    await _pumpSheet(tester, _StubGeocoding(result: _pune));

    // Without this, a user who searched once could never get back to
    // "here" short of restarting the app.
    expect(find.text('Use my location'), findsOneWidget);
  });
}
