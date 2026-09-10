import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_client.dart';
import '../../core/network/app_error.dart';
import '../../data/news_api.dart';

sealed class DiscoverUiState {
  const DiscoverUiState();
}

class DiscoverLoading extends DiscoverUiState {
  const DiscoverLoading();
}

/// `items` can legitimately be empty (an upstream hiccup on a
/// non-safety-critical feed returns an empty list rather than an error —
/// see `ClimateNewsProvider`), so the screen decides how to render that.
class DiscoverLoaded extends DiscoverUiState {
  final List<NewsItem> items;
  const DiscoverLoaded(this.items);
}

class DiscoverError extends DiscoverUiState {
  final AppError error;
  const DiscoverError(this.error);
}

final newsApiProvider = Provider<NewsApi>((ref) => NewsApi(buildApiClient()));

final discoverControllerProvider =
    NotifierProvider<DiscoverController, DiscoverUiState>(DiscoverController.new);

/// Fetches worldwide climate/weather-disaster headlines for the Discover
/// tab. Mirrors `MarineController`'s shape: no location dependency, a
/// sealed UI state, `retry` re-running the same fetch.
class DiscoverController extends Notifier<DiscoverUiState> {
  @override
  DiscoverUiState build() => const DiscoverLoading();

  Future<void> load() => _fetch();

  Future<void> retry() => _fetch();

  Future<void> _fetch() async {
    state = const DiscoverLoading();
    try {
      final items = await ref.read(newsApiProvider).fetchClimateNews();
      state = DiscoverLoaded(items);
    } on AppError catch (e) {
      state = DiscoverError(e);
    }
  }
}
