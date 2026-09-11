import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/app_error.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_radius.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';
import '../../core/voice_language_prefs.dart';
import '../../data/voice_api.dart';
import '../../features/chat/chat_controller.dart';
import '../../l10n/app_strings.dart';
import '../../shared/error_message.dart';
import 'round_icon_button.dart';

/// Top-right language entry point, shared by Home and Chat chrome.
///
/// Same 40dp [RoundIconButton] as every other chrome affordance
/// (menu/search/new-chat/overflow) — no new visual language. Opens
/// [LanguageSettingsSheet]: global voice language (23), mic auto-detect,
/// and read-aloud mode.
class LanguageSettingsButton extends ConsumerWidget {
  const LanguageSettingsButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(uiStringsProvider);
    return RoundIconButton(
      icon: Icons.translate,
      tooltip: s.languageSettings,
      onPressed: () => showLanguageSettings(context),
    );
  }
}

/// Opens the language settings as a modal bottom sheet — same chrome as
/// `LanguagePickerSheet` (grip, title, panel radius) so the app keeps one
/// bottom-sheet idiom.
Future<void> showLanguageSettings(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: AppColors.bgBase,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.panel)),
    ),
    builder: (_) => const LanguageSettingsSheet(),
  );
}

class LanguageSettingsSheet extends ConsumerWidget {
  const LanguageSettingsSheet({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final global = ref.watch(voiceLanguageProvider);
    final autoDetect = ref.watch(voiceAutoDetectProvider);
    final readAloud = ref.watch(readAloudModeProvider);
    final s = ref.watch(uiStringsProvider);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(bottom: AppSpacing.lg),
                decoration: BoxDecoration(
                  color: AppColors.divider,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Text(s.languageSettings,
                style: AppTypography.title(AppColors.textPrimary)),
            const SizedBox(height: AppSpacing.xs),
            Text(
              s.voiceInputDesc,
              style: AppTypography.label(AppColors.textSecondary),
            ),
            const SizedBox(height: AppSpacing.lg),
            _SectionLabel(s.micRecognitionTitle),
            _RadioRow(
              label: s.autoDetectLabel,
              subtitle: s.autoDetectSubtitle,
              selected: autoDetect,
              onTap: () => ref
                  .read(voiceAutoDetectProvider.notifier)
                  .setAutoDetect(true),
            ),
            _RadioRow(
              label: s.fixedLanguageLabel,
              subtitle: s.fixedLanguageSubtitle,
              selected: !autoDetect,
              onTap: () => ref
                  .read(voiceAutoDetectProvider.notifier)
                  .setAutoDetect(false),
            ),
            const SizedBox(height: AppSpacing.lg),
            _SectionLabel(s.globalVoiceLanguage),
            _GlobalLanguageRow(current: global),
            const SizedBox(height: AppSpacing.lg),
            _SectionLabel(s.speakerReadMode),
            _RadioRow(
              label: s.messageLanguage,
              subtitle: s.messageLanguageDesc,
              selected: readAloud == ReadAloudMode.message,
              onTap: () => ref
                  .read(readAloudModeProvider.notifier)
                  .setMode(ReadAloudMode.message),
            ),
            _RadioRow(
              label: s.globalLanguage,
              subtitle: s.globalLanguageDesc,
              selected: readAloud == ReadAloudMode.global,
              onTap: () => ref
                  .read(readAloudModeProvider.notifier)
                  .setMode(ReadAloudMode.global),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Text(text, style: AppTypography.label(AppColors.textSecondary)),
    );
  }
}

class _RadioRow extends StatelessWidget {
  const _RadioRow({
    required this.label,
    required this.subtitle,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: ExcludeSemantics(
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            child: Padding(
              padding:
                  const EdgeInsets.symmetric(vertical: AppSpacing.sm),
              child: Row(
                children: [
                  Icon(
                    selected
                        ? Icons.radio_button_checked
                        : Icons.radio_button_unchecked,
                    color: selected
                        ? AppColors.accent
                        : AppColors.textSecondary,
                    size: AppRadius.iconSize,
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(label,
                            style: AppTypography.body(
                                AppColors.textPrimary)),
                        Text(subtitle,
                            style: AppTypography.caption(
                                AppColors.textSecondary)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _GlobalLanguageRow extends ConsumerStatefulWidget {
  const _GlobalLanguageRow({required this.current});
  final String current;

  @override
  ConsumerState<_GlobalLanguageRow> createState() =>
      _GlobalLanguageRowState();
}

class _GlobalLanguageRowState extends ConsumerState<_GlobalLanguageRow> {
  List<VoiceLanguage>? _languages;
  bool _failed = false;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _failed = false;
    });
    try {
      final languages =
          await ref.read(voiceApiProvider).fetchLanguages();
      if (!mounted) return;
      setState(() {
        _languages = languages;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _failed = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(uiStringsProvider);
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: AppSpacing.md),
        child: Center(
          child: CircularProgressIndicator(color: AppColors.textPrimary),
        ),
      );
    }
    if (_failed || _languages == null) {
      return Row(
        children: [
          Expanded(
            child: Text(errorMessageFor(const UnknownError('Could not load languages')),
                style: AppTypography.label(AppColors.textSecondary)),
          ),
          TextButton(
            onPressed: _load,
            style: TextButton.styleFrom(foregroundColor: AppColors.accent),
            child: Text(s.tryAgain,
                style: AppTypography.label(AppColors.accent)),
          ),
        ],
      );
    }
    final current = _languages!.where((l) => l.code == widget.current);
    final name = current.isEmpty ? widget.current : current.first.name;
    return Semantics(
      button: true,
      label: 'Global voice language: $name',
      child: ExcludeSemantics(
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () async {
              // Reuse the existing full-list picker for choosing; this row
              // only shows the current value to keep this sheet compact.
              Navigator.of(context).pop();
              // Deferred to after pop so sheets never stack.
              await Future<void>.delayed(const Duration(milliseconds: 150));
              if (!context.mounted) return;
              final pickerContext = context;
              // ignore: use_build_context_synchronously
              await showModalBottomSheet<void>(
                context: pickerContext,
                backgroundColor: AppColors.bgBase,
                isScrollControlled: true,
                shape: const RoundedRectangleBorder(
                  borderRadius: BorderRadius.vertical(
                      top: Radius.circular(AppRadius.panel)),
                ),
                builder: (_) => const _GlobalLanguagePicker(),
              );
            },
            child: Padding(
              padding:
                  const EdgeInsets.symmetric(vertical: AppSpacing.sm),
              child: Row(
                children: [
                  Expanded(
                    child: Text(name,
                        style:
                            AppTypography.body(AppColors.textPrimary)),
                  ),
                  Text(s.change,
                      style: AppTypography.label(AppColors.accent)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _GlobalLanguagePicker extends ConsumerStatefulWidget {
  const _GlobalLanguagePicker();

  @override
  ConsumerState<_GlobalLanguagePicker> createState() =>
      _GlobalLanguagePickerState();
}

class _GlobalLanguagePickerState
    extends ConsumerState<_GlobalLanguagePicker> {
  List<VoiceLanguage>? _languages;
  bool _failed = false;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _failed = false;
    });
    try {
      final languages =
          await ref.read(voiceApiProvider).fetchLanguages();
      if (!mounted) return;
      setState(() {
        _languages = languages;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _failed = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final current = ref.watch(voiceLanguageProvider);
    final s = ref.watch(uiStringsProvider);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(s.globalVoiceLanguage,
                style: AppTypography.title(AppColors.textPrimary)),
            const SizedBox(height: AppSpacing.lg),
            if (_loading)
              const Padding(
                padding:
                    EdgeInsets.symmetric(vertical: AppSpacing.xxl),
                child: Center(
                  child: CircularProgressIndicator(
                      color: AppColors.textPrimary),
                ),
              )
            else if (_failed || _languages == null)
              TextButton(
                onPressed: _load,
                style:
                    TextButton.styleFrom(foregroundColor: AppColors.accent),
                child: Text(s.tryAgain,
                    style: AppTypography.label(AppColors.accent)),
              )
            else
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(context).size.height * 0.5,
                ),
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: _languages!.length,
                  itemBuilder: (context, index) {
                    final language = _languages![index];
                    final selected = language.code == current;
                    return Semantics(
                      button: true,
                      selected: selected,
                      label: language.name,
                      child: ExcludeSemantics(
                        child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                            onTap: () {
                              ref
                                  .read(voiceLanguageProvider.notifier)
                                  .setLanguage(language.code);
                              Navigator.of(context).pop();
                            },
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                  vertical: AppSpacing.md),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Text(language.name,
                                        style: AppTypography.body(
                                            AppColors.textPrimary)),
                                  ),
                                  if (selected)
                                    const Icon(Icons.check,
                                        color: AppColors.accent,
                                        size: AppRadius.iconSize),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}
