import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';
import '../../data/news_api.dart';
import '../../l10n/app_strings.dart';
import '../../shared/error_message.dart';
import '../../shared/widgets/round_icon_button.dart';
import '../shell/app_drawer.dart';
import 'discover_controller.dart';

/// Worldwide climate/weather-disaster headlines — the app's one screen
/// that reads like a news outlet's home page rather than a data panel:
/// a lead headline first, then a plain list of the rest, both driven by
/// live data (`GET /news/climate`), never placeholder copy.
class DiscoverScreen extends ConsumerStatefulWidget {
  const DiscoverScreen({super.key});

  @override
  ConsumerState<DiscoverScreen> createState() => _DiscoverScreenState();
}

class _DiscoverScreenState extends ConsumerState<DiscoverScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance
        .addPostFrameCallback((_) => ref.read(discoverControllerProvider.notifier).load());
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(discoverControllerProvider);
    final s = ref.watch(uiStringsProvider);

    return Scaffold(
      backgroundColor: AppColors.bgBase,
      drawer: const AppDrawer(activeRoute: '/discover'),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.all(AppSpacing.screenMargin),
              child: Row(
                children: [
                  Builder(
                    builder: (context) => RoundIconButton(
                      icon: Icons.menu,
                      tooltip: s.openMenu,
                      onPressed: () => Scaffold.of(context).openDrawer(),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Text(s.discover, style: AppTypography.title(AppColors.textPrimary)),
                ],
              ),
            ),
            Expanded(child: _Body(state: state)),
          ],
        ),
      ),
    );
  }
}

class _Body extends ConsumerWidget {
  const _Body({required this.state});

  final DiscoverUiState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return switch (state) {
      DiscoverLoading() => const Center(
          child: CircularProgressIndicator(color: AppColors.textPrimary),
        ),
      DiscoverError(:final error) => _ErrorView(
          message: errorMessageFor(error),
          onRetry: () => ref.read(discoverControllerProvider.notifier).retry(),
        ),
      DiscoverLoaded(:final items) => _NewsFeed(items: items),
    };
  }
}

class _NewsFeed extends StatelessWidget {
  const _NewsFeed({required this.items});

  final List<NewsItem> items;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const _EmptyView();

    final lead = items.first;
    final rest = items.skip(1).toList(growable: false);

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.screenMargin)
          .copyWith(bottom: AppSpacing.xxl),
      children: [
        _LeadHeadline(item: lead),
        const SizedBox(height: AppSpacing.xl),
        for (final item in rest) ...[
          _HeadlineRow(item: item),
          const Divider(height: AppSpacing.xl, color: AppColors.divider),
        ],
      ],
    );
  }
}

/// The top story, given real weight — a news home page's masthead
/// headline, not another list row.
class _LeadHeadline extends StatelessWidget {
  const _LeadHeadline({required this.item});

  final NewsItem item;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          item.title,
          style: AppTypography.hero(AppColors.textPrimary).copyWith(fontSize: 28),
        ),
        const SizedBox(height: AppSpacing.sm),
        _Byline(item: item),
      ],
    );
  }
}

class _HeadlineRow extends StatelessWidget {
  const _HeadlineRow({required this.item});

  final NewsItem item;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          item.title,
          style: AppTypography.bodyBold(AppColors.textPrimary),
        ),
        const SizedBox(height: AppSpacing.xs),
        _Byline(item: item),
      ],
    );
  }
}

/// "Outlet name · 3h ago" — omits either half it doesn't have, never a
/// dash standing in for a source or time the feed didn't supply.
class _Byline extends StatelessWidget {
  const _Byline({required this.item});

  final NewsItem item;

  @override
  Widget build(BuildContext context) {
    final parts = <String>[
      if (item.source != null) item.source!,
      if (item.publishedAt != null) _relativeTime(item.publishedAt!),
    ];
    if (parts.isEmpty) return const SizedBox.shrink();

    return Text(
      parts.join(' · '),
      style: AppTypography.caption(AppColors.textSecondary),
    );
  }
}

/// RSS `pubDate` is RFC 822 ("Thu, 10 Sep 2026 12:00:00 GMT"), which
/// `DateTime` cannot parse directly — this hand-rolls just enough of it to
/// render "Xh ago"/"Xd ago". Returns the raw string unparsed rather than
/// guessing at a malformed one.
String _relativeTime(String rfc822) {
  final parsed = _parseRfc822(rfc822);
  if (parsed == null) return rfc822;

  final diff = DateTime.now().toUtc().difference(parsed);
  if (diff.inMinutes < 1) return 'just now';
  if (diff.inHours < 1) return '${diff.inMinutes}m ago';
  if (diff.inHours < 24) return '${diff.inHours}h ago';
  return '${diff.inDays}d ago';
}

const _rfc822Months = {
  'Jan': 1, 'Feb': 2, 'Mar': 3, 'Apr': 4, 'May': 5, 'Jun': 6,
  'Jul': 7, 'Aug': 8, 'Sep': 9, 'Oct': 10, 'Nov': 11, 'Dec': 12,
};

DateTime? _parseRfc822(String value) {
  // "Thu, 10 Sep 2026 12:00:00 GMT"
  final match = RegExp(
    r'(\d{1,2})\s+(\w{3})\s+(\d{4})\s+(\d{2}):(\d{2}):(\d{2})',
  ).firstMatch(value);
  if (match == null) return null;
  final month = _rfc822Months[match.group(2)];
  if (month == null) return null;
  return DateTime.utc(
    int.parse(match.group(3)!),
    month,
    int.parse(match.group(1)!),
    int.parse(match.group(4)!),
    int.parse(match.group(5)!),
    int.parse(match.group(6)!),
  );
}

class _EmptyView extends ConsumerWidget {
  const _EmptyView();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(uiStringsProvider);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.public_off, size: 40, color: AppColors.textPrimary),
            const SizedBox(height: AppSpacing.lg),
            Text(
              s.noHeadlines,
              style: AppTypography.title(AppColors.textPrimary),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              s.checkBackSoonNews,
              style: AppTypography.label(AppColors.textSecondary),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorView extends ConsumerWidget {
  const _ErrorView({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(uiStringsProvider);
    return SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      child: Container(
        constraints: BoxConstraints(minHeight: MediaQuery.of(context).size.height * 0.6),
        alignment: Alignment.center,
        padding: const EdgeInsets.all(AppSpacing.xxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off, size: 40, color: AppColors.textPrimary),
            const SizedBox(height: AppSpacing.lg),
            Text(
              s.couldNotLoadNews,
              style: AppTypography.title(AppColors.textPrimary),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              message,
              style: AppTypography.label(AppColors.textPrimary),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.xl),
            TextButton(
              onPressed: onRetry,
              style: TextButton.styleFrom(
                foregroundColor: AppColors.textPrimary,
                side: const BorderSide(color: AppColors.textPrimary),
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.xxl,
                  vertical: AppSpacing.md,
                ),
              ),
              child: Text(
                s.tryAgain,
                style: AppTypography.body(AppColors.textPrimary),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
