import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../l10n/app_strings.dart';
import '../../../shared/widgets/app_menu.dart';
import '../voice_recording_controller.dart';
import 'language_picker_sheet.dart';
import 'voice_waveform.dart';

/// The chat input, per `NewChat.jpeg` / `NewChat2.jpeg`, with a third
/// mode added beyond the reference's two: an active-recording state per
/// `Voice.jpeg` (waveform replacing the text field, cancel + stop/send).
///
/// **One continuous pill**, with every affordance living *inside* it: the
/// `+` attach button, the text field, and a trailing control. The previous
/// build used an outlined `TextField` beside a separate filled button,
/// which is what made it read as a web form rather than a chat app — do
/// not split these apart again.
///
/// The trailing control swaps on content, exactly as the references show:
/// with the field empty it is a mic; once anything is typed it becomes a
/// filled send button. Tapping the mic starts recording (in place of a
/// separate reference two-button stop/send, this collapses to one:
/// tapping the stop control both ends the recording and sends it — there
/// is nothing to meaningfully preview between those two steps, since the
/// only artifact at that point is an undecoded WAV file). Long-pressing
/// the mic opens the voice-language picker.
class ChatComposer extends ConsumerStatefulWidget {
  const ChatComposer({
    super.key,
    required this.onSend,
    required this.onSendVoice,
    this.enabled = true,
    this.sending = false,
    this.hintText = 'Ask about the weather',
  });

  final ValueChanged<String> onSend;

  /// Called with the path of a finished recording once the user taps
  /// stop. The composer itself does not know about `ChatController` or
  /// the current voice language — mirrors [onSend]'s own separation of
  /// "the composer produced input" from "here is what happens to it".
  final ValueChanged<String> onSendVoice;

  /// False while a send is in flight. A disabled composer is what stops a
  /// user typing over a failed message and silently discarding it.
  final bool enabled;

  /// True while the last send (text or voice) is still awaiting a reply.
  /// Shows a small spinner at the trailing end of the pill — the user
  /// asked for a ChatGPT-like sending indicator after tap/stop.
  final bool sending;

  final String hintText;

  @override
  ConsumerState<ChatComposer> createState() => _ChatComposerState();
}

class _ChatComposerState extends ConsumerState<ChatComposer> {
  final _controller = TextEditingController();
  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    // Drives the mic <-> send swap.
    _controller.addListener(_onChanged);
  }

  void _onChanged() => setState(() {});

  @override
  void dispose() {
    _controller.removeListener(_onChanged);
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  bool get _hasText => _controller.text.trim().isNotEmpty;

  void _send() {
    final text = _controller.text.trim();
    if (text.isEmpty || !widget.enabled) return;
    _controller.clear();
    widget.onSend(text);
  }

  Future<void> _startRecording() async {
    if (!widget.enabled) return;
    final started = await ref.read(voiceRecordingControllerProvider.notifier).start();
    if (!started && mounted) _showMicPermissionDenied();
  }

  void _showMicPermissionDenied() {
    final s = ref.read(uiStringsProvider);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(s.micAccessNeeded),
        action: SnackBarAction(
          label: s.settings,
          onPressed: () => Geolocator.openAppSettings(),
        ),
      ),
    );
  }

  Future<void> _cancelRecording() {
    return ref.read(voiceRecordingControllerProvider.notifier).cancel();
  }

  Future<void> _stopAndSendRecording() async {
    final path = await ref.read(voiceRecordingControllerProvider.notifier).stop();
    if (path != null) widget.onSendVoice(path);
  }

  void _showAttachMenu(BuildContext context) {
    final s = ref.read(uiStringsProvider);
    showAppMenu(
      context: context,
      items: [
        AppMenuItem(
          icon: Icons.photo_camera_outlined,
          label: s.camera,
          onTap: () {},
          iconWell: true,
        ),
        AppMenuItem(
          icon: Icons.photo_outlined,
          label: s.photos,
          onTap: () {},
          iconWell: true,
        ),
        AppMenuItem(
          icon: Icons.insert_drive_file_outlined,
          label: s.files,
          onTap: () {},
          iconWell: true,
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final recordingState = ref.watch(voiceRecordingControllerProvider);
    final isRecording = recordingState is VoiceRecordingActive;
    final s = ref.watch(uiStringsProvider);

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.sm,
        AppSpacing.md,
        AppSpacing.md,
      ),
      child: Container(
        constraints: const BoxConstraints(
          minHeight: AppRadius.composerHeight,
        ),
        decoration: const BoxDecoration(
          color: AppColors.surfaceRaised,
          // Fully rounded: the pill's radius is half its height, so it
          // stays a stadium as the field grows to multiple lines.
          borderRadius: BorderRadius.all(
            Radius.circular(AppRadius.composerHeight / 2),
          ),
        ),
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
        child: isRecording
            ? _RecordingRow(
                amplitude: recordingState.amplitude,
                onCancel: _cancelRecording,
                onStopAndSend: _stopAndSendRecording,
                cancelTooltip: s.cancelRecording,
                stopAndSendTooltip: s.stopAndSend,
              )
            : Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Builder(
                    builder: (context) => _CircleAction(
                      icon: Icons.add,
                      tooltip: s.addAttachment,
                      onPressed:
                          widget.enabled ? () => _showAttachMenu(context) : null,
                    ),
                  ),
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      focusNode: _focus,
                      enabled: widget.enabled,
                      style: AppTypography.body(AppColors.textPrimary),
                      cursorColor: AppColors.accent,
                      minLines: 1,
                      maxLines: 5,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _send(),
                      decoration: InputDecoration(
                        isDense: true,
                        hintText: widget.hintText == 'Ask about the weather'
                            ? s.askAboutWeather
                            : widget.hintText,
                        hintStyle: AppTypography.body(AppColors.textSecondary),
                        // The pill IS the input's chrome; the field itself must
                        // contribute no border of its own.
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        disabledBorder: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(
                          vertical: AppSpacing.sm,
                        ),
                      ),
                    ),
                  ),
                  if (widget.sending)
                    _SendingSpinner(label: s.sending)
                  else if (_hasText)
                    _CircleAction(
                      icon: Icons.arrow_upward,
                      tooltip: s.sendMessage,
                      onPressed: widget.enabled ? _send : null,
                      filled: true,
                    )
                  else
                    _MicButton(
                      enabled: widget.enabled,
                      tooltip: s.micTooltip,
                      onTap: _startRecording,
                      onLongPress: () => showLanguagePicker(context),
                    ),
                ],
              ),
      ),
    );
  }
}

/// The composer's contents while actively recording: cancel on the left,
/// a live waveform filling the middle, stop-and-send on the right — per
/// `Voice.jpeg`, collapsed from its two right-hand controls to one (see
/// the class doc on [ChatComposer] for why).
class _RecordingRow extends StatelessWidget {
  const _RecordingRow({
    required this.amplitude,
    required this.onCancel,
    required this.onStopAndSend,
    this.cancelTooltip = 'Cancel recording',
    this.stopAndSendTooltip = 'Stop and send',
  });

  final Stream<double> amplitude;
  final VoidCallback onCancel;
  final VoidCallback onStopAndSend;
  final String cancelTooltip;
  final String stopAndSendTooltip;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        _CircleAction(
          icon: Icons.close,
          tooltip: cancelTooltip,
          onPressed: onCancel,
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
            child: VoiceWaveform(amplitude: amplitude),
          ),
        ),
        _CircleAction(
          icon: Icons.stop,
          tooltip: stopAndSendTooltip,
          onPressed: onStopAndSend,
          filled: true,
        ),
      ],
    );
  }
}

/// The trailing indicator while a send is in flight. Same 32dp footprint
/// as [_CircleAction] so the pill never shifts height when it appears —
/// small [CircularProgressIndicator] in the secondary tone, per the
/// reference's restrained motion language (no bounce, no shimmer).
class _SendingSpinner extends StatelessWidget {
  const _SendingSpinner({this.label = 'Sending'});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: label,
      child: const ExcludeSemantics(
        child: Padding(
          padding: EdgeInsets.all(AppSpacing.xs),
          child: SizedBox(
            width: 32,
            height: 32,
            child: Center(
              child: SizedBox(
                width: AppRadius.iconSize,
                height: AppRadius.iconSize,
                child: CircularProgressIndicator(
                  color: AppColors.textSecondary,
                  strokeWidth: 2,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The idle-state mic control. A plain [_CircleAction] can't carry a
/// long-press, so this wraps one with a [GestureDetector] rather than
/// growing `_CircleAction` a rarely-used second callback.
class _MicButton extends StatelessWidget {
  const _MicButton({
    required this.enabled,
    required this.onTap,
    required this.onLongPress,
    this.tooltip = 'Voice input — long-press to change language',
  });

  final bool enabled;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final String tooltip;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onLongPress: enabled ? onLongPress : null,
      child: _CircleAction(
        icon: Icons.mic_none,
        tooltip: tooltip,
        onPressed: enabled ? onTap : null,
      ),
    );
  }
}

/// A 32dp circular control sized to sit inside the composer pill without
/// forcing it taller. Distinct from `RoundIconButton`, which is the 40dp
/// free-floating screen chrome.
class _CircleAction extends StatelessWidget {
  const _CircleAction({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.filled = false,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final bool filled;

  static const double _size = 32;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    final foreground = filled
        ? AppColors.bgBase
        : (enabled ? AppColors.textPrimary : AppColors.textSecondary);

    return Semantics(
      button: true,
      enabled: enabled,
      label: tooltip,
      child: ExcludeSemantics(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xs),
          child: SizedBox(
            width: _size,
            height: _size,
            child: Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: filled ? AppColors.textPrimary : Colors.transparent,
              ),
              child: Material(
                type: MaterialType.transparency,
                shape: const CircleBorder(),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: onPressed,
                  child: Icon(icon, size: AppRadius.iconSize, color: foreground),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
