import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weathergpt_app/core/network/app_error.dart';
import 'package:weathergpt_app/data/news_api.dart';
import 'package:weathergpt_app/features/discover/discover_controller.dart';

const _headline = NewsItem(
  title: 'Cyclone forms in the Bay of Bengal',
  source: 'The Hindu',
  link: 'https://example.com/a',
  publishedAt: 'Thu, 10 Sep 2026 12:00:00 GMT',
);

class _FakeNewsApi implements NewsApi {
  _FakeNewsApi({this.items, this.error});

  final List<NewsItem>? items;
  final AppError? error;

  @override
  Future<List<NewsItem>> fetchClimateNews() async {
    if (error != null) throw error!;
    return items ?? const [];
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

ProviderContainer _containerWith(NewsApi api) {
  return ProviderContainer(overrides: [newsApiProvider.overrideWithValue(api)]);
}

void main() {
  test('starts in a loading state', () {
    final container = _containerWith(_FakeNewsApi());
    addTearDown(container.dispose);

    expect(container.read(discoverControllerProvider), isA<DiscoverLoading>());
  });

  test('load() populates the headlines on success', () async {
    final container = _containerWith(_FakeNewsApi(items: const [_headline]));
    addTearDown(container.dispose);

    await container.read(discoverControllerProvider.notifier).load();

    final state = container.read(discoverControllerProvider) as DiscoverLoaded;
    expect(state.items, [_headline]);
  });

  test('load() surfaces the real AppError on failure', () async {
    final container =
        _containerWith(_FakeNewsApi(error: const NetworkConnectionError()));
    addTearDown(container.dispose);

    await container.read(discoverControllerProvider.notifier).load();

    final state = container.read(discoverControllerProvider) as DiscoverError;
    expect(state.error, isA<NetworkConnectionError>());
  });

  test('retry() re-issues the same fetch and can recover from a failure', () async {
    var shouldFail = true;
    final api = _FakeNewsApiSwitchable(() => shouldFail);
    final container = _containerWith(api);
    addTearDown(container.dispose);

    await container.read(discoverControllerProvider.notifier).load();
    expect(container.read(discoverControllerProvider), isA<DiscoverError>());

    shouldFail = false;
    await container.read(discoverControllerProvider.notifier).retry();
    expect(container.read(discoverControllerProvider), isA<DiscoverLoaded>());
  });
}

class _FakeNewsApiSwitchable implements NewsApi {
  _FakeNewsApiSwitchable(this.shouldFail);
  final bool Function() shouldFail;

  @override
  Future<List<NewsItem>> fetchClimateNews() async {
    if (shouldFail()) throw const NetworkConnectionError();
    return const [_headline];
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
