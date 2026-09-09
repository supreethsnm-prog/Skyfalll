import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../data/geocoding_api.dart';

/// Storage for the user's saved places.
///
/// Local, not server-side: this app has no accounts, so there is no user
/// to attach a saved list to. `SharedPreferences` is the right size for
/// a handful of places — a database would be ceremony for a list that is
/// realistically under twenty entries.
abstract class SavedPlacesStore {
  Future<List<GeocodeResult>> load();
  Future<void> save(List<GeocodeResult> places);
}

class PrefsSavedPlacesStore implements SavedPlacesStore {
  static const _key = 'saved_places';

  /// The stored shape is this repository's own, deliberately NOT
  /// `GeocodeResult`'s API JSON: the API's field names belong to the
  /// backend and could change without warning, whereas this format has
  /// to stay readable by future versions of the app.
  static Map<String, dynamic> _encode(GeocodeResult place) => {
        'display_name': place.displayName,
        'latitude': place.latitude,
        'longitude': place.longitude,
        'country': place.country,
        'state': place.state,
      };

  static GeocodeResult? _decode(dynamic raw) {
    if (raw is! Map) return null;
    final name = raw['display_name'];
    final lat = raw['latitude'];
    final lon = raw['longitude'];
    // A malformed entry is dropped rather than throwing: one bad record
    // must not cost the user their whole list.
    if (name is! String || lat is! num || lon is! num) return null;

    return GeocodeResult(
      displayName: name,
      latitude: lat.toDouble(),
      longitude: lon.toDouble(),
      country: raw['country'] as String?,
      state: raw['state'] as String?,
    );
  }

  @override
  Future<List<GeocodeResult>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null) return const [];

    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return decoded
          .map(_decode)
          .whereType<GeocodeResult>()
          .toList(growable: false);
    } catch (_) {
      // Corrupt storage degrades to an empty list rather than blocking
      // the screen. Losing saved places is bad; a screen that cannot open
      // at all is worse.
      return const [];
    }
  }

  @override
  Future<void> save(List<GeocodeResult> places) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _key,
      jsonEncode(places.map(_encode).toList()),
    );
  }
}

final savedPlacesStoreProvider =
    Provider<SavedPlacesStore>((ref) => PrefsSavedPlacesStore());

final savedPlacesProvider =
    NotifierProvider<SavedPlacesController, List<GeocodeResult>>(
  SavedPlacesController.new,
);

class SavedPlacesController extends Notifier<List<GeocodeResult>> {
  /// Completes when storage has been read.
  ///
  /// Every mutation awaits this first. Without it, a save tapped in the
  /// moment between launch and storage answering would operate on an
  /// empty list, and the in-flight restore would then overwrite it —
  /// silently wiping the user's saved places.
  late final Future<void> _restored;

  @override
  List<GeocodeResult> build() {
    // Starts empty and fills in asynchronously; the screen renders its
    // empty state for the one frame before storage answers.
    _restored = _restore();
    return const [];
  }

  Future<void> _restore() async {
    state = await ref.read(savedPlacesStoreProvider).load();
  }

  /// Coordinates identify a place, not its name: the same point can be
  /// called "New Delhi, Delhi" by reverse geocoding and "New Delhi,
  /// India" by search, and saving it twice would be a bug. Rounded to
  /// ~1.1km, matching the backend's own cache precision.
  static bool _samePlace(GeocodeResult a, GeocodeResult b) =>
      (a.latitude - b.latitude).abs() < 0.01 &&
      (a.longitude - b.longitude).abs() < 0.01;

  bool isSaved(GeocodeResult place) =>
      state.any((saved) => _samePlace(saved, place));

  Future<void> toggle(GeocodeResult place) async {
    await _restored;
    final next = isSaved(place)
        ? state.where((saved) => !_samePlace(saved, place)).toList()
        // Newest first, so a place just saved is at the top where the
        // user is looking.
        : [place, ...state];

    state = next;
    await ref.read(savedPlacesStoreProvider).save(next);
  }

  Future<void> remove(GeocodeResult place) async {
    await _restored;
    final next = state.where((saved) => !_samePlace(saved, place)).toList();
    state = next;
    await ref.read(savedPlacesStoreProvider).save(next);
  }
}
