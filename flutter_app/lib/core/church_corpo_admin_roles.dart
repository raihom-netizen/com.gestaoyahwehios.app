/// Papéis do corpo administrativo (painel + Cloud Functions).
abstract final class ChurchCorpoAdminRoles {
  ChurchCorpoAdminRoles._();

  static const List<String> defaultRoleKeys = [
    'pastor',
    'pastora',
    'gestor',
    'administrador',
    'admin',
    'secretario',
    'secretaria',
    'tesoureiro',
    'tesoureira',
  ];

  static String foldFuncaoKey(String raw) {
    var s = raw.trim().toLowerCase();
    const pairs = <String, String>{
      '\u00e1': 'a', '\u00e0': 'a', '\u00e3': 'a', '\u00e2': 'a', '\u00e4': 'a',
      '\u00e9': 'e', '\u00e8': 'e', '\u00ea': 'e', '\u00eb': 'e',
      '\u00ed': 'i', '\u00ec': 'i', '\u00ee': 'i', '\u00ef': 'i',
      '\u00f3': 'o', '\u00f2': 'o', '\u00f5': 'o', '\u00f4': 'o', '\u00f6': 'o',
      '\u00fa': 'u', '\u00f9': 'u', '\u00fb': 'u', '\u00fc': 'u',
      '\u00e7': 'c', '\u00f1': 'n',
    };
    pairs.forEach((a, b) => s = s.replaceAll(a, b));
    return s;
  }

  static List<String> configuredRolesFromTenant(Map<String, dynamic>? tenant) {
    if (tenant == null || tenant.isEmpty) return defaultRoleKeys;
    dynamic raw = tenant['corpoAdminRoles'];
    if (raw == null && tenant['config'] is Map) {
      raw = (tenant['config'] as Map)['corpoAdminRoles'];
    }
    if (raw is! List || raw.isEmpty) return defaultRoleKeys;
    final out = <String>[];
    for (final e in raw) {
      final s = e.toString().trim();
      if (s.isNotEmpty) out.add(foldFuncaoKey(s));
    }
    return out.isEmpty ? defaultRoleKeys : out;
  }

  static bool isAllowedRole(String raw, List<String> configured) {
    final k = foldFuncaoKey(raw);
    if (k.isEmpty) return false;
    for (final c in configured) {
      final cc = foldFuncaoKey(c);
      if (k == cc) return true;
      if (k.startsWith(cc) && cc.length >= 4) return true;
    }
    return false;
  }

  static List<String> rolesFromMember(
    Map<String, dynamic> data,
    List<String> configured,
  ) {
    final seen = <String>{};
    final out = <String>[];
    void tryAdd(String raw) {
      if (!isAllowedRole(raw, configured)) return;
      final k = foldFuncaoKey(raw);
      if (seen.add(k)) out.add(k);
    }

    tryAdd(
      (data['FUNCAO'] ?? data['funcao'] ?? data['CARGO'] ?? data['role'] ?? '')
          .toString(),
    );
    final flist = data['FUNCOES'] ?? data['funcoes'];
    if (flist is List) {
      for (final x in flist) {
        tryAdd(x.toString());
      }
    }
    return out;
  }

  /// Pastor ? gestor/admin ? secretário ? tesoureiro ? outros (config).
  static int sortRank(String foldedKey) {
    final k = foldFuncaoKey(foldedKey);
    if (k.startsWith('pastor')) return 300;
    if (k.startsWith('gestor')) return 250;
    if (k.startsWith('admin')) return 240;
    if (k.startsWith('secretar')) return 200;
    if (k.startsWith('tesour')) return 100;
    return 50;
  }

  static int memberSortRank(List<String> roles) {
    if (roles.isEmpty) return 0;
    return roles.map(sortRank).reduce((a, b) => a > b ? a : b);
  }

  static String canonicalDisplayKey(String foldedKey) {
    final k = foldFuncaoKey(foldedKey);
    if (k == 'pastor' || k == 'pastora') return k;
    if (k == 'secretario' || k == 'secretaria') return k;
    if (k == 'tesoureiro' || k == 'tesoureira') return k;
    return k;
  }
}
