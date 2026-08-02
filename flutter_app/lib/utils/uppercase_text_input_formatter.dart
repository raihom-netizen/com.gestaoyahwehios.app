import 'package:flutter/services.dart';

import 'text_case_preserving_utils.dart';

/// Força maiúsculas em letras; preserva emojis e símbolos (iOS/Android).
class UpperCaseTextFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final t = uppercaseLatinPreservingEmoji(newValue.text);
    if (t == newValue.text) return newValue;
    return newValue.copyWith(text: t, composing: TextRange.empty);
  }
}
