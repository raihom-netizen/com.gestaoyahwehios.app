import 'package:flutter/material.dart';
import 'member_demographics_utils.dart';

export 'member_demographics_utils.dart'
    show birthDateFromMemberData, ageFromMemberData, genderCategoryFromMemberData;

/// Sexo legado: prefixo m/f para compatibilidade.
String sexFromMemberData(Map<String, dynamic>? data) {
  final c = genderCategoryFromMemberData(data);
  if (c == 'M') return 'm';
  if (c == 'F') return 'f';
  return '';
}

/// Cor do avatar quando o membro não tem foto. Retorna null se tiver foto (usa placeholder do widget).
Color? avatarColorForMember(Map<String, dynamic>? data, {bool hasPhoto = false}) {
  if (hasPhoto) return null;
  if (data == null) return Colors.grey.shade600;
  final age = ageFromMemberData(data);
  final isMale = genderCategoryFromMemberData(data) == 'M';
  final isFemale = genderCategoryFromMemberData(data) == 'F';

  const blue = Color(0xFF2563EB);
  const pink = Color(0xFFDB2777);
  const green = Color(0xFF059669);

  if (age != null) {
    if (age < 13) return isMale ? blue : (isFemale ? pink : green);
    if (age < 18) return green;
    return isMale ? blue : (isFemale ? pink : Colors.grey.shade600);
  }
  return isMale ? blue : (isFemale ? pink : Colors.grey.shade600);
}
