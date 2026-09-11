import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/clipboard/clipboard_service.dart';
import '../../core/lang_guess.dart';
import '../../core/network/app_error.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';
import '../../core/voice_language_prefs.dart';
import '../../shared/error_message.dart';
import '../../shared/widgets/app_menu.dart';
import '../../shared/widgets/language_settings_button.dart';
import '../../shared/widgets/round_icon_button.dart';
import '../shell/app_drawer.dart';
import 'audio_playback_controller.dart';
import 'chat_controller.dart';
import 'widgets/assistant_message.dart';
import '../../l10n/app_strings.dart';
import 'widgets/chat_composer.dart';
import 'widgets/user_bubble.dart';

/// Identifies the reply just spoken back after a voice turn, for
/// [AudioPlaybackController] — distinct from any transcript-list index
/// (which shifts as new turns are appended) since this fires once, right
/// as the new turns land.
const _voiceReplyPlaybackKey = 'voice-reply';

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
    final s = ref.watch(uiStringsProvider);

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
              hintText: s.askAboutWeather,
              // Only an idle composer accepts input: while a send is in
              // flight or has failed, typing a new message would silently
              // discard the one already in play.
              enabled: state is ChatIdle,
              sending: state is ChatSending,
              onSend: controller.sendMessage,
              onSendVoice: (audioPath) async {
                // Await persisted settings first: on a fresh launch the
                // providers still hold defaults until SharedPreferences
                // answers (see VoiceLanguageController.restored).
                await ref.read(voiceLanguageProvider.notifier).restored;
                await ref.read(voiceAutoDetectProvider.notifier).restored;
                final language = ref.read(voiceLanguageProvider);
                final autoDetect = ref.read(voiceAutoDetectProvider);
                await controller.sendVoice(
                  audioPath,
                  language,
                  autoDetect: autoDetect,
                  onReplyAudio: (audioBase64) => ref
                      .read(audioPlaybackControllerProvider.notifier)
                      .playBase64Wav(audioBase64, turnKey: _voiceReplyPlaybackKey),
                  onError: (error) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(errorMessageFor(error))),
                    );
                  },
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _ChatChrome extends ConsumerWidget {
  const _ChatChrome();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(uiStringsProvider);
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.screenMargin),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Builder(
            builder: (context) => RoundIconButton(
              icon: Icons.menu,
              tooltip: s.openMenu,
              onPressed: () => Scaffold.of(context).openDrawer(),
            ),
          ),
          Row(
            children: [
              const LanguageSettingsButton(),
              const SizedBox(width: AppSpacing.sm),
              Builder(
                builder: (context) => RoundIconButton(
                  icon: Icons.more_vert,
                  tooltip: s.moreOptions,
                  onPressed: () => showAppMenu(
                    context: context,
                    header: s.thisConversation,
                    items: [
                      AppMenuItem(
                        icon: Icons.ios_share,
                        label: s.share,
                        onTap: () {},
                      ),
                      AppMenuItem(
                        icon: Icons.push_pin_outlined,
                        label: s.pin,
                        onTap: () {},
                      ),
                      AppMenuItem(
                        icon: Icons.search,
                        label: s.findInChat,
                        onTap: () {},
                      ),
                      AppMenuItem(
                        icon: Icons.archive_outlined,
                        label: s.archive,
                        onTap: () {},
                      ),
                      AppMenuItem(
                        icon: Icons.delete_outline,
                        label: s.delete,
                        onTap: () {},
                        destructive: true,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends ConsumerWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(uiStringsProvider);
    // A centred single line, as in NewChat.jpeg — no illustration, no
    // feature tour, no suggestion grid. The composer below it is the
    // invitation.
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xxl),
        child: Text(
          s.whatWouldYouLikeToKnow,
          style: AppTypography.title(AppColors.textPrimary),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}

class _Transcript extends ConsumerWidget {
  const _Transcript({required this.messages});

  final List<dynamic> messages;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
          // Long-press copies — the standard mobile-chat convention, and
          // it keeps the bubble itself visually identical to the spec
          // (no extra chrome on the user's own turns).
          return GestureDetector(
            onLongPress: () => copyChatText(context, ref, turn.content),
            child: UserBubble(text: turn.content),
          );
        }
        // The turn's position in THIS list, not a stable message id — the
        // list is rebuilt from `result.history` on every turn, so an
        // index is stable for exactly as long as a given render, which is
        // all a "currently reading this one aloud" indicator needs.
        // Stored per-message language travels with the turn (null for
        // typed turns and pre-language-memory chats).
        return _ReadAloudAssistantMessage(
          text: turn.content,
          messageLang: turn.lang,
          playbackKey: index,
        );
      },
    );
  }
}

/// [AssistantMessage] wired to real "read aloud": synthesizes on first
/// tap, plays through the same shared player voice auto-play uses, and
/// tapping again on a message already loading/playing stops it — a
/// second tap must not fire a second synthesis request.
class _ReadAloudAssistantMessage extends ConsumerWidget {
  const _ReadAloudAssistantMessage(
      {required this.text, required this.messageLang, required this.playbackKey});

  final String text;

  /// Stored language of this reply (null for old chats). Message mode
  /// prefers it, then an unambiguous script guess, then global.
  final String? messageLang;
  final int playbackKey;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playback = ref.watch(audioPlaybackControllerProvider);
    final isThisOne = (playback is PlaybackLoading && playback.turnKey == playbackKey) ||
        (playback is PlaybackPlaying && playback.turnKey == playbackKey);

    return AssistantMessage(
      text: text,
      onCopy: () => copyChatText(context, ref, text),
      onReadAloud: () => _toggle(context, ref, playback, isThisOne),
      onShare: () {},
      onMore: () {},
      readAloudActive: isThisOne,
    );
  }

  Future<void> _toggle(
    BuildContext context,
    WidgetRef ref,
    AudioPlaybackUiState playback,
    bool isThisOne,
  ) async {
    final controller = ref.read(audioPlaybackControllerProvider.notifier);
    if (isThisOne) {
      await controller.stop();
      return;
    }
    try {
      await ref.read(readAloudModeProvider.notifier).restored;
      await ref.read(voiceLanguageProvider.notifier).restored;
      final mode = ref.read(readAloudModeProvider);
      final global = ref.read(voiceLanguageProvider);
      final fallbackScript = text.codeUnits.any((u) => u >= 0x0900 && u <= 0x097F)
          ? 'hi'
          : (text.codeUnits.any((u) => (u >= 0x0600 && u <= 0x06FF) || (u >= 0x0750 && u <= 0x077F))
              ? 'ur'
              : null);
      final language = mode == ReadAloudMode.global
          ? global
          : (messageLang ??
              guessLanguageFromScript(text) ??
              fallbackScript ??
              global);
      final speech =
          await ref.read(voiceApiProvider).synthesize(text: text, language: language);
      await controller.playBase64Wav(speech.audioBase64, turnKey: playbackKey);
    } on AppError catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(errorMessageFor(e))));
    }
  }
}

/// Copies chat text and confirms with a transient notice. Shared by the
/// assistant copy icon and the user-bubble long-press so both confirm
/// identically.
Future<void> copyChatText(
    BuildContext context, WidgetRef ref, String text) async {
  await ref.read(clipboardServiceProvider).copy(text);
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(
    const SnackBar(content: Text('Copied to clipboard')),
  );
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
