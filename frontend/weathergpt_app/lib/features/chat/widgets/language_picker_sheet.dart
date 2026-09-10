import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/app_error.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/voice_language_prefs.dart';
import '../../../data/voice_api.dart';
import '../../../shared/error_message.dart';
import '../chat_controller.dart';

/// Opens the voice-language picker as a modal bottom sheet — reached by
/// long-pressing the composer's mic button. Chrome mirrors
/// `LocationSearchSheet`'s (same grip handle, title, panel radius).
Future<void> showLanguagePicker(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: AppColors.bgBase,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.panel)),
    ),
    builder: (_) => const LanguagePickerSheet(),
  );
}

sealed class _LoadState {
  const _LoadState();
}

class _Loading extends _LoadState {
  const _Loading();
}

class _Loaded extends _LoadState {
  final List<VoiceLanguage> languages;
  const _Loaded(this.languages);
}

class _Failed extends _LoadState {
  final AppError error;
  const _Failed(this.error);
}

class LanguagePickerSheet extends ConsumerStatefulWidget {
  const LanguagePickerSheet({super.key});

  @override
  ConsumerState<LanguagePickerSheet> createState() => _LanguagePickerSheetState();
}

class _LanguagePickerSheetState extends ConsumerState<LanguagePickerSheet> {
  _LoadState _state = const _Loading();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    setState(() => _state = const _Loading());
    try {
      final languages = await ref.read(voiceApiProvider).fetchLanguages();
      if (!mounted) return;
      setState(() => _state = _Loaded(languages));
    } on AppError catch (e) {
      if (!mounted) return;
      setState(() => _state = _Failed(e));
    }
  }

  void _choose(String code) {
    ref.read(voiceLanguageProvider.notifier).setLanguage(code);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final current = ref.watch(voiceLanguageProvider);

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
            Text('Voice language', style: AppTypography.title(AppColors.textPrimary)),
            const SizedBox(height: AppSpacing.lg),
            ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.5,
              ),
              child: _Body(state: _state, current: current, onChoose: _choose, onRetry: _load),
            ),
          ],
        ),
      ),
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({
    required this.state,
    required this.current,
    required this.onChoose,
    required this.onRetry,
  });

  final _LoadState state;
  final String current;
  final ValueChanged<String> onChoose;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return switch (state) {
      _Loading() => const Padding(
          padding: EdgeInsets.symmetric(vertical: AppSpacing.xxl),
          child: Center(
            child: CircularProgressIndicator(color: AppColors.textPrimary),
          ),
        ),
      _Failed(:final error) => Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                errorMessageFor(error),
                style: AppTypography.label(AppColors.textSecondary),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppSpacing.md),
              TextButton(
                onPressed: onRetry,
                style: TextButton.styleFrom(foregroundColor: AppColors.accent),
                child: Text('Try again', style: AppTypography.label(AppColors.accent)),
              ),
            ],
          ),
        ),
      _Loaded(:final languages) => ListView.builder(
          shrinkWrap: true,
          itemCount: languages.length,
          itemBuilder: (context, index) {
            final language = languages[index];
            final selected = language.code == current;
            return Semantics(
              button: true,
              selected: selected,
              label: language.name,
              child: ExcludeSemantics(
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: () => onChoose(language.code),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              language.name,
                              style: AppTypography.body(AppColors.textPrimary),
                            ),
                          ),
                          if (selected)
                            const Icon(Icons.check, color: AppColors.accent, size: AppRadius.iconSize),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
    };
  }
}
