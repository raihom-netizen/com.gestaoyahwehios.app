import 'package:flutter/material.dart';

/// Letras latinas (incl. acentuadas) — demais grafemas (emoji, números, etc.) intactos.
final RegExp _latinLetterGrapheme = RegExp(
  r'[A-Za-zÀ-ÖØ-öø-ÿ]',
  unicode: true,
);

/// Maiúsculas só em letras; emojis e símbolos permanecem (Android/iOS).
String uppercaseLatinPreservingEmoji(String input) {
  if (input.isEmpty) return input;
  final out = StringBuffer();
  for (final g in input.characters) {
    out.write(_latinLetterGrapheme.hasMatch(g) ? g.toUpperCase() : g);
  }
  return out.toString();
}

/// Primeira letra latina ampliada no título; emojis no início usam [Text] simples.
Widget buildResumoTitleWithFirstLetterEmphasis({
  required String title,
  required double fontSize,
  required Color color,
  double firstLetterScale = 1.28,
}) {
  if (title.isEmpty) return const SizedBox.shrink();

  final chars = title.characters;
  final first = chars.first;
  final rest = chars.skip(1).string;

  final baseStyle = TextStyle(
    fontSize: fontSize,
    fontWeight: FontWeight.w900,
    height: 1.25,
    color: color,
  );

  if (!_latinLetterGrapheme.hasMatch(first)) {
    return Text(title, style: baseStyle);
  }

  return RichText(
    text: TextSpan(
      style: baseStyle,
      children: [
        TextSpan(
          text: first,
          style: baseStyle.copyWith(
            fontSize: fontSize * firstLetterScale,
          ),
        ),
        if (rest.isNotEmpty) TextSpan(text: rest),
      ],
    ),
  );
}

/// Comparação insensível a caixa sem corromper emoji nos rótulos.
String normalizeLabelForMatch(String input) =>
    uppercaseLatinPreservingEmoji(input.trim());
