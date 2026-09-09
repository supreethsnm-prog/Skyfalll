import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';
import '../../shared/error_message.dart';
import '../../shared/widgets/app_menu.dart';
import '../../shared/widgets/round_icon_button.dart';
import '../shell/app_drawer.dart';
import 'chat_controller.dart';
import 'widgets/assistant_message.dart';
import 'widgets/chat_composer.dart';
import 'widgets/user_bubble.dart';

/// The conversation screen, per `NewChat.jpeg` (empty) and `Convo1.jpeg`
/// / `Convo2.jpeg` (populated).
///
/// True black, free-floating round chrome with no `AppBar`, and a single
/// pill composer. The message rendering is deliberately asymmetric —
/// boxed user turns against unboxed assistant prose — which is the core
/// of what the references show and what the first build got wrong.
class ChatScreen extends ConsumerWidget {
  const ChatScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(chatControllerProvider);
    final controller = ref.read(chatControllerProvider.notifier);

    return Scaffold(
      backgroundColor: AppColors.bgBase,
      drawer: const AppDrawer(),
      body: SafeArea(
        child: Column(
          children: [
            const _ChatChrome(),
            Expanded(
              child: state.messages.isEmpty
                  ? const _EmptyState()
                  : _Transcript(messages: state.messages),
            ),
            if (state is ChatFailed)
              _FailureNotice(
                message: errorMessageFor(state.error),
                onRetry: controller.retry,
              ),
            ChatComposer(
              // Only an idle composer accepts input: while a send is in
              // flight or has failed, typing a new message would silently
              // discard the one already in play.
              enabled: state is ChatIdle,
              onSend: controller.sendMessage,
            ),
          ],
        ),
      ),
    );
  }
}

class _ChatChrome extends StatelessWidget {
  const _ChatChrome();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.screenMargin),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Builder(
            builder: (context) => RoundIconButton(
              icon: Icons.menu,
              tooltip: 'Open menu',
              onPressed: () => Scaffold.of(context).openDrawer(),
            ),
          ),
          Builder(
            builder: (context) => RoundIconButton(
              icon: Icons.more_vert,
              tooltip: 'More options',
              onPressed: () => showAppMenu(
                context: context,
                header: 'This conversation',
                items: [
                  AppMenuItem(
                      icon: Icons.ios_share, label: 'Share', onTap: () {}),
                  AppMenuItem(
                      icon: Icons.push_pin_outlined,
                      label: 'Pin',
                      onTap: () {}),
                  AppMenuItem(
                      icon: Icons.search,
                      label: 'Find in chat',
                      onTap: () {}),
                  AppMenuItem(
                      icon: Icons.archive_outlined,
                      label: 'Archive',
                      onTap: () {}),
                  AppMenuItem(
                    icon: Icons.delete_outline,
                    label: 'Delete',
                    onTap: () {},
                    destructive: true,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    // A centred single line, as in NewChat.jpeg — no illustration, no
    // feature tour, no suggestion grid. The composer below it is the
    // invitation.
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xxl),
        child: Text(
          'What would you like to know?',
          style: AppTypography.title(AppColors.textPrimary),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}

class _Transcript extends StatelessWidget {
  const _Transcript({required this.messages});

  final List<dynamic> messages;

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.lg,
      ),
      itemCount: messages.length,
      separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.xl),
      itemBuilder: (context, index) {
        final turn = messages[index];
        if (turn.role == 'user') {
          return UserBubble(text: turn.content);
        }
        return AssistantMessage(
          text: turn.content,
          onCopy: () {},
          onReadAloud: () {},
          onShare: () {},
          onMore: () {},
        );
      },
    );
  }
}

class _FailureNotice extends StatelessWidget {
  const _FailureNotice({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.sm,
      ),
      child: Row(
        children: [
          const Icon(
            Icons.error_outline,
            size: 18,
            color: AppColors.destructive,
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              message,
              style: AppTypography.label(AppColors.textSecondary),
            ),
          ),
          TextButton(
            onPressed: onRetry,
            style: TextButton.styleFrom(foregroundColor: AppColors.accent),
            child: Text('Retry', style: AppTypography.label(AppColors.accent)),
          ),
        ],
      ),
    );
  }
}
