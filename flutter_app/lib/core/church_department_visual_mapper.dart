import 'package:flutter/material.dart';

/// Campos **opcionais** (evolução do modelo) — convivem com `iconKey`, `bgColor1`, etc.
abstract final class ChurchDepartmentFirestoreFields {
  ChurchDepartmentFirestoreFields._();

  static const iconName = 'icon_name';
  static const colorHex = 'color_hex';
  static const colorHexSecondary = 'color_hex_secondary';
  static const ultimaAtualizacao = 'ultima_atualizacao';
  static const membrosCount = 'membros_count';
}

/// Mapeia `icon_name` (string) e `color_hex` (#RRGGBB) para o modelo visual do app,
/// com **fallbacks sólidos** (evita transparência / tipos inválidos no Firestore).
abstract final class ChurchDepartmentVisualMapper {
  ChurchDepartmentVisualMapper._();

  /// Aliases de produto / painel remoto → chave canónica usada em `DepartmentsPage._iconOptions`.
  static const Map<String, String> _iconNameToCanonical = {
    'shield_moon': 'pastoral',
    'shield': 'pastoral',
    'church': 'pastoral',
    'cross': 'pastoral',
    'group': 'men',
    'groups': 'men',
    'group_work': 'men',
    'people': 'mulheres',
    'music': 'louvor',
    'note': 'louvor',
    'bolt': 'jovens',
    'child': 'criancas',
    'baby': 'criancas',
    'wallet': 'finance',
    'money': 'finance',
    'book': 'escola_biblica',
    'door': 'recepcao',
    'video': 'media',
    'pray': 'intercessao',
    'hands': 'intercessao',
    'heart': 'diaconal',
    'help': 'auxiliares',
  };

  /// Lê `icon_name` / variantes antes de `iconKey` / `themeKey`.
  static String rawIconStringFromDoc(Map<String, dynamic> m) {
    final a = (m[ChurchDepartmentFirestoreFields.iconName] ??
            m['iconName'] ??
            '')
        .toString()
        .trim();
    if (a.isNotEmpty) return a;
    return (m['iconKey'] ?? m['themeKey'] ?? '').toString();
  }

  /// Converte [raw] (ex.: `shield_moon`, `louvor`) para chave conhecida ou devolve lower-case para resolver depois.
  static String mapIconNameToCanonicalKey(String raw) {
    final n = raw.trim().toLowerCase().replaceAll('-', '_');
    if (n.isEmpty) return '';
    return _iconNameToCanonical[n] ?? n;
  }

  /// `#RRGGBB` / `#AARRGGBB` / `RRGGBB` → ARGB 32 bits; opaco se alpha vier 0.
  static int? parseColorHexToArgb(String? hex) {
    if (hex == null) return null;
    var s = hex.trim();
    if (s.isEmpty) return null;
    if (s.startsWith('#')) s = s.substring(1);
    if (s.length == 6) {
      final v = int.tryParse(s, radix: 16);
      if (v == null) return null;
      return 0xFF000000 | v;
    }
    if (s.length == 8) {
      final v = int.tryParse(s, radix: 16);
      if (v == null) return null;
      final a = (v >> 24) & 0xFF;
      if (a == 0) return 0xFF000000 | (v & 0xFFFFFF);
      return v;
    }
    return null;
  }

  static int _opaqueArgb(int v) {
    if ((v & 0xFF000000) == 0) return 0xFF000000 | (v & 0xFFFFFF);
    return v;
  }

  static int _partnerArgb(int argb) {
    final c = Color(_opaqueArgb(argb));
    final d = Color.lerp(c, Colors.black, 0.2) ?? c;
    return _opaqueArgb(d.value);
  }

  /// Par gradiente a partir de `color_hex` (+ opcional secundária) ou `null` para usar legado.
  static (int, int)? gradientArgbPairFromDoc(
    Map<String, dynamic> m, {
    required int fallback1,
    required int fallback2,
  }) {
    final h1 = (m[ChurchDepartmentFirestoreFields.colorHex] ??
            m['colorHex'] ??
            '')
        .toString();
    final h2 = (m[ChurchDepartmentFirestoreFields.colorHexSecondary] ??
            m['colorHexSecondary'] ??
            '')
        .toString();
    final a = parseColorHexToArgb(h1);
    if (a == null) return null;
    final b = parseColorHexToArgb(h2.isNotEmpty ? h2 : null) ?? _partnerArgb(a);
    return (_opaqueArgb(a), _opaqueArgb(b));
  }

  /// Hex `#RRGGBB` para gravar no Firestore a partir de ARGB (ex.: tema).
  static String hexStringFromArgb(int argb) {
    final v = _opaqueArgb(argb) & 0xFFFFFF;
    return '#${v.toRadixString(16).padLeft(6, '0')}';
  }

  /// Contagem de membros: novo campo ou legado.
  static int membrosCountFromDoc(Map<String, dynamic> m) {
    final v = m[ChurchDepartmentFirestoreFields.membrosCount] ??
        m['membrosVinculadosCount'];
    if (v is int) return v < 0 ? 0 : v;
    if (v is double) return v.round().clamp(0, 1 << 30);
    return int.tryParse(v.toString()) ?? 0;
  }
}
