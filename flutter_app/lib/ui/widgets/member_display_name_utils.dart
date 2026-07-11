import 'package:gestao_yahweh/services/church_chat_display_name.dart';

/// Nome exibível de membro — evita «Sem nome» / stubs sem ficha válida.
const Set<String> kMemberNamePlaceholderLower = {
  'sem nome',
  'membro',
  '(sem nome)',
  '—',
  '-',
  'n/a',
  'na',
};

bool isRealMemberDisplayName(String? raw) {
  final s = (raw ?? '').trim();
  if (s.isEmpty) return false;
  return !kMemberNamePlaceholderLower.contains(s.toLowerCase());
}

/// Extrai nome canónico; [fallback] só quando nenhum campo tem nome real.
String memberDisplayNameFromData(
  Map<String, dynamic>? data, {
  String fallback = '',
}) {
  if (data == null) return fallback;
  for (final k in const [
    'NOME_COMPLETO',
    'nome',
    'name',
    'displayName',
  ]) {
    final s = (data[k] ?? '').toString().trim();
    if (isRealMemberDisplayName(s) &&
        !ChurchChatDisplayName.looksLikeFirebaseUid(s)) {
      return s;
    }
  }
  return fallback;
}

bool memberDataHasValidName(Map<String, dynamic>? data) =>
    memberDisplayNameFromData(data).isNotEmpty;

String? memberNameValidationMessage(String? raw) {
  final s = (raw ?? '').trim();
  if (s.isEmpty) return 'Informe o nome completo';
  if (!isRealMemberDisplayName(s)) return 'Nome inválido';
  if (s.length < 2) return 'Nome muito curto';
  return null;
}
