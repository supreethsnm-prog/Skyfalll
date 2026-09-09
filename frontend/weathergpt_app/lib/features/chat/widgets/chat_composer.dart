import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../shared/widgets/app_menu.dart';

/// The chat input, per `NewChat.jpeg` / `NewChat2.jpeg`.
///
/// **One continuous pill**, with every affordance living *inside* it: the
/// `+` attach button, the text field, and a trailing control. The previous
/// build used an outlined `TextField` beside a separate filled button,
/// which is what made it read as a web form rather than a chat app — do
/// not split these apart again.
///
/// The trailing control swaps on content, exactly as the references show:
/// with the field empty it is a mic; once anything is typed it becomes a
/// filled send button.
class ChatComposer extends StatefulWidget {
  const ChatComposer({
    super.key,
    required this.onSend,
    this.enabled = true,
    this.hintText = 'Ask about the weather',
  });

  final ValueChanged<String> onSend;

  /// False while a send is in flight. A disabled composer is what stops a
  /// user typing over a failed message and silently discarding it.
  final bool enabled;

  final String hintText;

  @override
  State<ChatComposer> createState() => _ChatComposerState();
}

class _ChatComposerState extends State<ChatComposer> {
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

  void _showAttachMenu(BuildContext context) {
    showAppMenu(
      context: context,
      items: [
        AppMenuItem(
          icon: Icons.photo_camera_outlined,
          label: 'Camera',
          onTap: () {},
          iconWell: true,
        ),
        AppMenuItem(
          icon: Icons.photo_outlined,
          label: 'Photos',
          onTap: () {},
          iconWell: true,
        ),
        AppMenuItem(
          icon: Icons.insert_drive_file_outlined,
          label: 'Files',
          onTap: () {},
          iconWell: true,
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
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
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Builder(
              builder: (context) => _CircleAction(
                icon: Icons.add,
                tooltip: 'Add attachment',
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
                  hintText: widget.hintText,
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
            if (_hasText)
              _CircleAction(
                icon: Icons.arrow_upward,
                tooltip: 'Send message',
                onPressed: widget.enabled ? _send : null,
                filled: true,
              )
            else
              const _CircleAction(
                icon: Icons.mic_none,
                tooltip: 'Voice input',
                // Speech-to-text is not wired: the BHASHINI credential is
                // blocked upstream. Disabled rather than hidden, so the
                // affordance is honest about existing but not working.
                onPressed: null,
              ),
          ],
        ),
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
