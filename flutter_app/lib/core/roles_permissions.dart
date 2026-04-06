/// Matriz de permissões por papel (chave normalizada — [FUNCAO_PERMISSOES], `users.role`, templates).
/// Use [snapshotFor] no menu lateral e em [AppPermissions].
class ChurchRolePermissionSnapshot {
  const ChurchRolePermissionSnapshot({
    required this.restrictedNav,
    required this.viewFinance,
    required this.viewPatrimonio,
    required this.editAnyMember,
    required this.viewMemberDirectory,
    required this.editChurchProfile,
    required this.editDepartments,
    required this.editSchedulesAll,
    required this.manageVisitors,
    required this.manageCargosCatalog,
    required this.approvePendingMembers,
    required this.badgeColorArgb,
  });

  /// Menu estreito (mural, eventos, minha escala, etc.) — equivalente ao antigo “membro”.
  final bool restrictedNav;

  final bool viewFinance;
  final bool viewPatrimonio;

  /// Editar qualquer ficha, senhas de terceiros, cargos.
  final bool editAnyMember;

  /// Ver lista completa de membros (mesmo sem editar terceiros).
  final bool viewMemberDirectory;

  final bool editChurchProfile;
  final bool editDepartments;
  final bool editSchedulesAll;
  final bool manageVisitors;
  final bool manageCargosCatalog;
  final bool approvePendingMembers;

  /// Cor da etiqueta de cargo (ARGB).
  final int badgeColorArgb;
}

/// Papéis eclesiásticos / sistema — chaves estáveis para mapa e seeds.
abstract class ChurchRoleKeys {
  static const master = 'master';
  static const adm = 'adm';
  static const gestor = 'gestor';
  static const pastorPresidente = 'pastor_presidente';
  static const pastor = 'pastor';
  static const pastorAuxiliar = 'pastor_auxiliar';
  static const secretario = 'secretario';
  static const presbitero = 'presbitero';
  static const tesoureiro = 'tesoureiro';
  static const tesouraria = 'tesouraria';
  static const liderDepartamento = 'lider_departamento';
  static const lider = 'lider';
  static const diacono = 'diacono';
  static const evangelista = 'evangelista';
  static const musico = 'musico';
  static const membro = 'membro';
  static const visitante = 'visitante';
}

class ChurchRolePermissions {
  ChurchRolePermissions._();

  static String normalize(String raw) {
    var r = raw.trim().toLowerCase();
    if (r.isEmpty) return ChurchRoleKeys.membro;
    switch (r) {
      case 'admin':
      case 'administrador':
      case 'administradora':
        return ChurchRoleKeys.adm;
      case 'pastora':
        return ChurchRoleKeys.pastor;
      case 'presbitera':
        return ChurchRoleKeys.presbitero;
      case 'secretária':
      case 'secretário':
        return ChurchRoleKeys.secretario;
      case 'ministerial':
      case 'pastor_auxiliar_ministerial':
        return ChurchRoleKeys.pastorAuxiliar;
      case 'lider_departamento':
      case 'lider_depto':
        return ChurchRoleKeys.liderDepartamento;
    }
    return r;
  }

  static const ChurchRolePermissionSnapshot _full = ChurchRolePermissionSnapshot(
    restrictedNav: false,
    viewFinance: true,
    viewPatrimonio: true,
    editAnyMember: true,
    viewMemberDirectory: true,
    editChurchProfile: true,
    editDepartments: true,
    editSchedulesAll: true,
    manageVisitors: true,
    manageCargosCatalog: true,
    approvePendingMembers: true,
    badgeColorArgb: 0xFF1565C0,
  );

  static const ChurchRolePermissionSnapshot _pastorAux = ChurchRolePermissionSnapshot(
    restrictedNav: false,
    viewFinance: false,
    viewPatrimonio: false,
    editAnyMember: true,
    viewMemberDirectory: true,
    editChurchProfile: true,
    editDepartments: true,
    editSchedulesAll: true,
    manageVisitors: true,
    manageCargosCatalog: false,
    approvePendingMembers: true,
    badgeColorArgb: 0xFF5E35B1,
  );

  static const ChurchRolePermissionSnapshot _secretario = ChurchRolePermissionSnapshot(
    restrictedNav: false,
    viewFinance: false,
    viewPatrimonio: false,
    editAnyMember: true,
    viewMemberDirectory: true,
    editChurchProfile: true,
    editDepartments: true,
    editSchedulesAll: true,
    manageVisitors: true,
    manageCargosCatalog: true,
    approvePendingMembers: true,
    badgeColorArgb: 0xFF00897B,
  );

  static const ChurchRolePermissionSnapshot _tesoureiro = ChurchRolePermissionSnapshot(
    restrictedNav: false,
    viewFinance: true,
    viewPatrimonio: false,
    editAnyMember: false,
    viewMemberDirectory: false,
    editChurchProfile: false,
    editDepartments: true,
    editSchedulesAll: false,
    manageVisitors: false,
    manageCargosCatalog: false,
    approvePendingMembers: false,
    badgeColorArgb: 0xFF2E7D32,
  );

  static const ChurchRolePermissionSnapshot _liderDept = ChurchRolePermissionSnapshot(
    restrictedNav: false,
    viewFinance: false,
    viewPatrimonio: false,
    editAnyMember: true,
    viewMemberDirectory: true,
    editChurchProfile: false,
    editDepartments: true,
    editSchedulesAll: true,
    manageVisitors: false,
    manageCargosCatalog: false,
    approvePendingMembers: false,
    badgeColorArgb: 0xFF6A1B9A,
  );

  static const ChurchRolePermissionSnapshot _obreiroLeve = ChurchRolePermissionSnapshot(
    restrictedNav: false,
    viewFinance: false,
    viewPatrimonio: false,
    editAnyMember: false,
    viewMemberDirectory: true,
    editChurchProfile: false,
    editDepartments: false,
    editSchedulesAll: true,
    manageVisitors: false,
    manageCargosCatalog: false,
    approvePendingMembers: false,
    badgeColorArgb: 0xFF546E7A,
  );

  static const ChurchRolePermissionSnapshot _membro = ChurchRolePermissionSnapshot(
    restrictedNav: true,
    viewFinance: false,
    viewPatrimonio: false,
    editAnyMember: false,
    viewMemberDirectory: false,
    editChurchProfile: false,
    editDepartments: false,
    editSchedulesAll: false,
    manageVisitors: false,
    manageCargosCatalog: false,
    approvePendingMembers: false,
    badgeColorArgb: 0xFF78909C,
  );

  /// Pastor “clássico” no sistema: amplo acesso (compatibilidade com igrejas já cadastradas).
  static const ChurchRolePermissionSnapshot _pastorLegacy = ChurchRolePermissionSnapshot(
    restrictedNav: false,
    viewFinance: true,
    viewPatrimonio: true,
    editAnyMember: true,
    viewMemberDirectory: true,
    editChurchProfile: true,
    editDepartments: true,
    editSchedulesAll: true,
    manageVisitors: true,
    manageCargosCatalog: true,
    approvePendingMembers: true,
    badgeColorArgb: 0xFF3949AB,
  );

  static final Map<String, ChurchRolePermissionSnapshot> _byKey = {
    ChurchRoleKeys.master: _full,
    ChurchRoleKeys.adm: _full,
    ChurchRoleKeys.gestor: _full,
    ChurchRoleKeys.pastorPresidente: _full,
    ChurchRoleKeys.pastor: _pastorLegacy,
    ChurchRoleKeys.pastorAuxiliar: _pastorAux,
    ChurchRoleKeys.secretario: _secretario,
    ChurchRoleKeys.presbitero: _pastorLegacy,
    ChurchRoleKeys.tesoureiro: _tesoureiro,
    ChurchRoleKeys.tesouraria: _tesoureiro,
    ChurchRoleKeys.liderDepartamento: _liderDept,
    ChurchRoleKeys.lider: _liderDept,
    ChurchRoleKeys.diacono: _obreiroLeve,
    ChurchRoleKeys.evangelista: _obreiroLeve,
    ChurchRoleKeys.musico: _obreiroLeve,
    ChurchRoleKeys.membro: _membro,
    ChurchRoleKeys.visitante: _membro,
  };

  static ChurchRolePermissionSnapshot snapshotFor(String role) {
    final n = normalize(role);
    if (_byKey.containsKey(n)) return _byKey[n]!;
    return legacySnapshotForUnknownKey(n);
  }

  /// Chaves sem doc em [funcoesControle] / cargos novos — aproximação segura.
  static ChurchRolePermissionSnapshot legacySnapshotForUnknownKey(String n) {
    if (const {
          'adm',
          'admin',
          'gestor',
          'master',
          'administrador',
          'administradora',
        }.contains(n)) {
      return _full;
    }
    if (n == 'tesoureiro' || n == 'tesouraria') return _tesoureiro;
    if (n == 'secretario' || n == 'secretário' || n == 'secretária') {
      return _secretario;
    }
    if (n == 'pastor' ||
        n == 'pastora' ||
        n == 'presbitero' ||
        n == 'presbitera') {
      return _pastorLegacy;
    }
    if (n == 'lider' || n == 'lider_departamento' || n == 'lider_depto') {
      return _liderDept;
    }
    if (n == 'diacono' || n == 'evangelista' || n == 'musico') {
      return _obreiroLeve;
    }
    if (n == 'membro' || n == 'visitante') return _membro;
    return _obreiroLeve;
  }

  static int badgeColorForKey(String roleKey) => snapshotFor(roleKey).badgeColorArgb;

  static bool _hasGranularModule(List<String>? permissions, String moduleKey) {
    if (permissions == null || permissions.isEmpty) return false;
    final key = moduleKey.trim().toLowerCase();
    return permissions.map((e) => e.trim().toLowerCase()).contains(key);
  }

  /// Itens do menu [IgrejaCleanShell] (índices 0–20).
  static bool shellAllowsNavIndex(
    String role,
    int index, {
    bool? memberCanViewFinance,
    bool? memberCanViewPatrimonio,
    List<String>? permissions,
  }) {
    final s = snapshotFor(role);
    final r = normalize(role);

    bool fin() =>
        s.viewFinance ||
        _hasGranularModule(permissions, 'financeiro') ||
        (r == ChurchRoleKeys.membro && memberCanViewFinance == true);

    bool pat() =>
        s.viewPatrimonio ||
        _hasGranularModule(permissions, 'patrimonio') ||
        (r == ChurchRoleKeys.membro && memberCanViewPatrimonio == true);

    switch (index) {
      case 0:
        return true;
      case 1:
        return s.editChurchProfile;
      case 2:
        return s.viewMemberDirectory && !s.restrictedNav;
      case 3:
        if (_hasGranularModule(permissions, 'departamentos')) return true;
        return s.editDepartments && !s.restrictedNav;
      case 4:
        return s.manageVisitors && !s.restrictedNav;
      case 5:
        return s.manageCargosCatalog && !s.restrictedNav;
      case 6:
        return true;
      case 7:
        return true;
      case 8:
        return true;
      case 9:
        return true;
      case 10:
        return true;
      case 11:
        return s.editSchedulesAll;
      case 12:
        return true;
      case 13:
        return true;
      case 14:
        return fin();
      case 15:
        return pat();
      case 16:
        return true;
      case 17:
        return true;
      case 18:
        return true;
      case 19:
        return s.approvePendingMembers;
      case 20:
        return !s.restrictedNav &&
            (s.editChurchProfile || s.editSchedulesAll || s.approvePendingMembers || s.editDepartments);
      default:
        return true;
    }
  }

  /// Aparece no organograma (nível numérico maior = mais alto).
  static int hierarchyRankForRoleKey(String role) {
    final n = normalize(role);
    switch (n) {
      case ChurchRoleKeys.master:
      case ChurchRoleKeys.adm:
      case ChurchRoleKeys.gestor:
      case ChurchRoleKeys.pastorPresidente:
        return 100;
      case ChurchRoleKeys.pastor:
      case ChurchRoleKeys.pastorAuxiliar:
        return 90;
      case ChurchRoleKeys.presbitero:
        return 80;
      case ChurchRoleKeys.secretario:
        return 70;
      case ChurchRoleKeys.tesoureiro:
      case ChurchRoleKeys.tesouraria:
        return 65;
      case ChurchRoleKeys.liderDepartamento:
      case ChurchRoleKeys.lider:
        return 55;
      case ChurchRoleKeys.diacono:
        return 50;
      case ChurchRoleKeys.evangelista:
      case ChurchRoleKeys.musico:
        return 40;
      default:
        return 0;
    }
  }

  static bool isLeadershipRoleKey(String role) =>
      hierarchyRankForRoleKey(role) >= 40;
}
