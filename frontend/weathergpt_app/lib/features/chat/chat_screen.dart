import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/network/app_error.dart';
import '../../core/theme/app_spacing.dart';
import '../../shared/widgets/app_chip.dart';
import '../../shared/widgets/error_view.dart';
import 'chat_controller.dart';
import 'widgets/chat_composer.dart';
import 'widgets/chat_turn_tile.dart';
import 'widgets/typing_indicator.dart';

const _suggestedQuestions = [
  'Any alerts near me?',
  'Will it rain in Pune tomorrow?',
  "What's the weather in Mumbai right now?",
  'Should I expect a heatwave this week?',
];

class ChatScreen extends ConsumerWidget {
  const ChatScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(chatControllerProvider);
    final controller = ref.read(chatControllerProvider.notifier);

    return Scaffold(
      appBar: AppBar(title: const Text('Chat')),
      body: Column(
        children: [
          Expanded(
            child: state.messages.isEmpty && state is! ChatFailed
                ? _EmptyChatView(onSuggestionTap: controller.sendMessage)
                : _ConversationList(state: state, controller: controller),
          ),
          ChatComposer(
            // Only ChatIdle allows starting a NEW send. ChatSending is the
            // obvious disable; ChatFailed must ALSO disable — otherwise a
            // user can type a new message instead of using Retry, which
            // silently discards the failed message and its optimistic
            // bubble (sendMessage starts fresh from _rawHistory, and a
            // successful send replaces the message list wholesale).
            enabled: state is ChatIdle,
            onSend: controller.sendMessage,
          ),
        ],
      ),
    );
  }
}

class _EmptyChatView extends StatelessWidget {
  final ValueChanged<String> onSuggestionTap;

  const _EmptyChatView({required this.onSuggestionTap});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Ask WeatherGPT about weather, alerts, or advisories anywhere in India.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyLarge,
            ),
            const SizedBox(height: AppSpacing.lg),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              alignment: WrapAlignment.center,
              children: [
                for (final question in _suggestedQuestions)
                  AppChip(label: question, onTap: () => onSuggestionTap(question)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ConversationList extends StatelessWidget {
  final ChatUiState state;
  final ChatController controller;

  const _ConversationList({required this.state, required this.controller});

  @override
  Widget build(BuildContext context) {
    final items = <Widget>[];
    final currentState = state;
    if (currentState is ChatFailed) {
      items.add(
        ErrorView(
          message: _describeError(currentState.error),
          onRetry: controller.retry,
        ),
      );
    } else if (currentState is ChatSending) {
      items.add(const TypingIndicator());
    }
    items.addAll(
      state.messages.reversed.map((turn) => ChatTurnTile(turn: turn)),
    );

    return ListView(
      reverse: true,
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
      children: items,
    );
  }

  String _describeError(AppError error) => switch (error) {
        NetworkTimeoutError() =>
          'That took too long — check your connection and try again.',
        NetworkConnectionError() =>
          'Could not reach the server. Check your connection and try again.',
        ServerError(:final statusCode) =>
          'The server had a problem (code $statusCode). Try again in a moment.',
        UnknownError() => 'Something went wrong. Please try again.',
      };
}
