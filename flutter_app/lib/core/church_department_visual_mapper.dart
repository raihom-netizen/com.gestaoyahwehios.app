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
    'book_open_reader': 'escola_biblica',
    'library_books': 'escola_biblica',
    'school': 'escola_biblica',
    'auto_stories': 'escola_biblica',
    'escola_dominical': 'escola_biblica',
    'dominical': 'escola_biblica',
    'ebd': 'escola_biblica',
    'sunday_school': 'escola_biblica',
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
    if (n.contains('dominical')) return 'escola_biblica';
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

/// Cores de gradiente dos cards de departamento — **alinhadas** com `DepartmentsPage._themeOptions`
/// / `_deptCardGradientInts` (hub do chat reutiliza o mesmo visual).
abstract final class ChurchDepartmentThemeGradients {
  ChurchDepartmentThemeGradients._();

  static const List<Map<String, dynamic>> themeOptions = <Map<String, dynamic>>[
    {'key': 'auxiliares', 'c1': 0xFF4A148C, 'c2': 0xFF6A1B9A},
    {'key': 'comunicacao', 'c1': 0xFF006064, 'c2': 0xFF0097A7},
    {'key': 'criancas', 'c1': 0xFF00BCD4, 'c2': 0xFF80DEEA},
    {'key': 'kids', 'c1': 0xFF00BCD4, 'c2': 0xFF80DEEA},
    {'key': 'diaconal', 'c1': 0xFF5D4037, 'c2': 0xFF8D6E63},
    {'key': 'evangelismo', 'c1': 0xFF6A1B9A, 'c2': 0xFF7B1FA2},
    {'key': 'escola_biblica', 'c1': 0xFF00695C, 'c2': 0xFF26A69A},
    {'key': 'finance', 'c1': 0xFF546E7A, 'c2': 0xFF90A4AE},
    {'key': 'intercessao', 'c1': 0xFFB71C1C, 'c2': 0xFFD32F2F},
    {'key': 'jovens', 'c1': 0xFF6A1B9A, 'c2': 0xFFAB47BC},
    {'key': 'youth', 'c1': 0xFF6A1B9A, 'c2': 0xFFAB47BC},
    {'key': 'louvor', 'c1': 0xFFF57C00, 'c2': 0xFFFFA726},
    {'key': 'worship', 'c1': 0xFFF57C00, 'c2': 0xFFFFA726},
    {'key': 'media', 'c1': 0xFF1976D2, 'c2': 0xFF64B5F6},
    {'key': 'missionarios', 'c1': 0xFF455A64, 'c2': 0xFF90A4AE},
    {'key': 'mulheres', 'c1': 0xFFC2185B, 'c2': 0xFFF48FB1},
    {'key': 'women', 'c1': 0xFFC2185B, 'c2': 0xFFF48FB1},
    {'key': 'obreiros', 'c1': 0xFF4E342E, 'c2': 0xFF795548},
    {'key': 'oracao', 'c1': 0xFF558B2F, 'c2': 0xFFAED581},
    {'key': 'prayer', 'c1': 0xFF558B2F, 'c2': 0xFFAED581},
    {'key': 'pastoral', 'c1': 0xFF2E7D32, 'c2': 0xFF81C784},
    {'key': 'presbiteros', 'c1': 0xFF0D47A1, 'c2': 0xFF1565C0},
    {'key': 'recepcao', 'c1': 0xFFE64A19, 'c2': 0xFFFF8A65},
    {'key': 'welcome', 'c1': 0xFFE64A19, 'c2': 0xFFFF8A65},
    {'key': 'secretarios', 'c1': 0xFF283593, 'c2': 0xFF3949AB},
    {'key': 'social', 'c1': 0xFF00695C, 'c2': 0xFF00897B},
    {'key': 'tesouraria', 'c1': 0xFF1B5E20, 'c2': 0xFF2E7D32},
    {'key': 'varoes', 'c1': 0xFF0D47A1, 'c2': 0xFF1976D2},
    {'key': 'men', 'c1': 0xFF0D47A1, 'c2': 0xFF1976D2},
  ];

  static int _opaqueArgb32(int v) {
    if ((v & 0xFF000000) == 0) return 0xFF000000 | (v & 0xFFFFFF);
    return v;
  }

  static bool _luminanceTooHighForWhiteText(int argb) {
    return Color(_opaqueArgb32(argb)).computeLuminance() > 0.74;
  }

  static Map<String, dynamic> themeByKey(String key) {
    final k = key.trim().toLowerCase();
    for (final e in themeOptions) {
      if (e['key'] == k) return e;
    }
    return themeOptions.firstWhere((e) => e['key'] == 'pastoral');
  }

  /// Igual a `DepartmentsPage._deptCardGradientInts` — hex Firestore, `bgColor1`/`bgColor2` ou tema por ícone.
  static (int, int) cardGradientArgbPair(
    Map<String, dynamic> m,
    String themeKey,
  ) {
    final th = themeByKey(themeKey);
    final fallback1 = th['c1'] as int;
    final fallback2 = th['c2'] as int;
    final fromHex = ChurchDepartmentVisualMapper.gradientArgbPairFromDoc(
      m,
      fallback1: fallback1,
      fallback2: fallback2,
    );
    if (fromHex != null) {
      var a = _opaqueArgb32(fromHex.$1);
      var b = _opaqueArgb32(fromHex.$2);
      if (_luminanceTooHighForWhiteText(a) &&
          _luminanceTooHighForWhiteText(b)) {
        a = _opaqueArgb32(fallback1);
        b = _opaqueArgb32(fallback2);
      }
      return (a, b);
    }
    int parse(dynamic v, int fallback) {
      if (v == null) return fallback;
      if (v is int) return v;
      if (v is num) return v.toInt();
      final s = v.toString().trim();
      if (s.isEmpty) return fallback;
      if (s.startsWith('0x') || s.startsWith('0X')) {
        return int.tryParse(
              s.replaceFirst(RegExp(r'^0x', caseSensitive: false), ''),
              radix: 16,
            ) ??
            fallback;
      }
      return int.tryParse(s) ?? fallback;
    }

    var a = _opaqueArgb32(parse(m['bgColor1'], fallback1));
    var b = _opaqueArgb32(parse(m['bgColor2'], fallback2));
    if (_luminanceTooHighForWhiteText(a) && _luminanceTooHighForWhiteText(b)) {
      a = _opaqueArgb32(fallback1);
      b = _opaqueArgb32(fallback2);
    }
    return (a, b);
  }
}
