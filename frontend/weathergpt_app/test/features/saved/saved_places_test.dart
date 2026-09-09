import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weathergpt_app/data/geocoding_api.dart';
import 'package:weathergpt_app/features/saved/saved_places_controller.dart';

const _delhi = GeocodeResult(
  displayName: 'New Delhi, India',
  latitude: 28.6139,
  longitude: 77.2090,
  country: 'India',
  state: 'Delhi',
);

/// The SAME point, named differently — reverse geocoding says
/// "New Delhi, Delhi" where search says "New Delhi, India". Saving it
/// twice under two names would be a bug, which is why identity is by
/// coordinate rather than by string.
const _delhiOtherName = GeocodeResult(
  displayName: 'New Delhi, Delhi',
  latitude: 28.6141,
  longitude: 77.2088,
  country: 'India',
  state: 'Delhi',
);

const _pune = GeocodeResult(
  displayName: 'Pune, Maharashtra',
  latitude: 18.5204,
  longitude: 73.8567,
  country: 'India',
  state: 'Maharashtra',
);

class _MemoryStore implements SavedPlacesStore {
  _MemoryStore([this.initial = const []]);

  final List<GeocodeResult> initial;
  List<GeocodeResult>? saved;

  @override
  Future<List<GeocodeResult>> load() async => initial;

  @override
  Future<void> save(List<GeocodeResult> places) async => saved = places;
}

ProviderContainer _containerWith(_MemoryStore store) {
  final container = ProviderContainer(
    overrides: [savedPlacesStoreProvider.overrideWithValue(store)],
  );
  addTearDown(container.dispose);
  // Reading the provider is what runs build() and starts the restore.
  // Without this the tests' `await Future.delayed` would settle nothing,
  // and every assertion would run against an untouched empty list.
  container.read(savedPlacesProvider);
  return container;
}

void main() {
  test('restores saved places from storage', () async {
    final container = _containerWith(_MemoryStore(const [_delhi]));

    container.read(savedPlacesProvider);
    // The restore is async; the first frame renders empty.
    await Future<void>.delayed(Duration.zero);

    expect(container.read(savedPlacesProvider).single.displayName,
        'New Delhi, India');
  });

  test('saving puts the newest place first', () async {
    final store = _MemoryStore(const [_delhi]);
    final container = _containerWith(store);
    await Future<void>.delayed(Duration.zero);

    await container.read(savedPlacesProvider.notifier).toggle(_pune);

    // Where the user is looking after saving.
    expect(
      container.read(savedPlacesProvider).map((p) => p.displayName),
      ['Pune, Maharashtra', 'New Delhi, India'],
    );
  });

  test('toggling an already-saved place removes it', () async {
    final container = _containerWith(_MemoryStore(const [_delhi]));
    await Future<void>.delayed(Duration.zero);

    await container.read(savedPlacesProvider.notifier).toggle(_delhi);

    expect(container.read(savedPlacesProvider), isEmpty);
  });

  test('identity is by coordinate, not by name', () async {
    // The core reason this is not a simple string comparison.
    final container = _containerWith(_MemoryStore(const [_delhi]));
    await Future<void>.delayed(Duration.zero);

    final controller = container.read(savedPlacesProvider.notifier);
    expect(controller.isSaved(_delhiOtherName), isTrue);

    await controller.toggle(_delhiOtherName);

    // Recognised as the same place, so it was removed rather than added.
    expect(container.read(savedPlacesProvider), isEmpty);
  });

  test('a distinct place is not mistaken for a saved one', () async {
    final container = _containerWith(_MemoryStore(const [_delhi]));
    await Future<void>.delayed(Duration.zero);

    expect(
      container.read(savedPlacesProvider.notifier).isSaved(_pune),
      isFalse,
    );
  });

  test('every change is written through to storage', () async {
    final store = _MemoryStore();
    final container = _containerWith(store);
    await Future<void>.delayed(Duration.zero);

    await container.read(savedPlacesProvider.notifier).toggle(_pune);

    // Saved places that vanish on restart would be worse than no feature.
    expect(store.saved, isNotNull);
    expect(store.saved!.single.displayName, 'Pune, Maharashtra');
  });

  test('remove writes through too', () async {
    final store = _MemoryStore(const [_delhi, _pune]);
    final container = _containerWith(store);
    await Future<void>.delayed(Duration.zero);

    await container.read(savedPlacesProvider.notifier).remove(_delhi);

    expect(store.saved!.map((p) => p.displayName), ['Pune, Maharashtra']);
  });
}
