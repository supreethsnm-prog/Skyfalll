import 'package:flutter_test/flutter_test.dart';
import 'package:weathergpt_app/core/lang_guess.dart';

void main() {
  test('latin text guesses English', () {
    expect(guessLanguageFromScript('What is the weather'), 'en');
  });

  test('kannada script guesses Kannada', () {
    expect(guessLanguageFromScript('ನಾಳೆ ಹುಬ್ಬಳ್ಳಿಯಲ್ಲಿ'), 'kn');
  });

  test('devanagari is ambiguous and returns null (hi vs mr)', () {
    expect(guessLanguageFromScript('मुंबई में मौसम'), isNull);
  });

  test('empty and digits-only return null', () {
    expect(guessLanguageFromScript(''), isNull);
    expect(guessLanguageFromScript('30.4 21.6'), isNull);
  });
}
