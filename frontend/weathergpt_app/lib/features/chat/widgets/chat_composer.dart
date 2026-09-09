import 'package:flutter/material.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../shared/widgets/app_primary_button.dart';

/// The chat input row: a disabled mic affordance (BHASHINI voice is
/// externally blocked — see spec §9 — kept VISIBLE rather than hidden
/// so the seam is obvious and removing the disable is the only change
/// needed once voice is unblocked), a multiline text field, and a send
/// button.
class ChatComposer extends StatefulWidget {
  final ValueChanged<String> onSend;
  final bool enabled;

  const ChatComposer({super.key, required this.onSend, this.enabled = true});

  @override
  State<ChatComposer> createState() => _ChatComposerState();
}

class _ChatComposerState extends State<ChatComposer> {
  final _controller = TextEditingController();

  void _submit() {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    widget.onSend(text);
    _controller.clear();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          const IconButton(
            icon: Icon(Icons.mic_none),
            tooltip: 'Voice input (coming soon)',
            onPressed: null,
          ),
          Expanded(
            child: TextField(
              controller: _controller,
              enabled: widget.enabled,
              minLines: 1,
              maxLines: 5,
              textInputAction: TextInputAction.send,
              onSubmitted: widget.enabled ? (_) => _submit() : null,
              decoration: const InputDecoration(
                hintText: 'Ask WeatherGPT…',
                border: OutlineInputBorder(),
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          AppPrimaryButton(
            label: 'Send',
            icon: Icons.send,
            onPressed: widget.enabled ? _submit : null,
          ),
        ],
      ),
    );
  }
}
