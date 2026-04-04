import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:gestao_yahweh/services/app_permissions.dart';
import 'package:gestao_yahweh/services/tenant_resolver_service.dart';

/// Funções do painel da igreja — catálogo em `igrejas/{tenantId}/funcoesControle/{key}`.
/// O gestor pode adicionar/remover entradas e restaurar padrões. O campo [permissionTemplate]
/// define o núcleo de permissões (AppPermissions); [key] é o valor gravado em FUNCAO no membro.
class ChurchFuncoesControleService {
  ChurchFuncoesControleService._();

  /// Chaves que não podem ser excluídas (acesso base do sistema).
  static const Set<String> protectedKeys = {'membro', 'adm', 'gestor', 'master'};

  static CollectionReference<Map<String, dynamic>> collection(String tenantId) =>
      FirebaseFirestore.instance.collection('igrejas').doc(tenantId).collection('funcoesControle');

  /// Documentos padrão (mesmo conjunto que a tela informativa original).
  static List<Map<String, dynamic>> defaultRoleDocuments() => [
        _doc('membro', 'Membro / Congregado', 'Mural, eventos, agenda, perfil e cartão.', 0),
        _doc('adm', 'Administrador', 'Acesso total ao painel da igreja.', 1),
        _doc('gestor', 'Gestor', 'Acesso total: cadastro, membros, financeiro, patrimônio, etc.', 2),
        _doc(
            'pastor_presidente',
            'Pastor Presidente',
            'Liderança máxima: equivalente a gestor no painel.',
            3),
        _doc(
            'pastor_auxiliar',
            'Pastor Auxiliar / Ministerial',
            'Membros, agenda e escalas — sem financeiro ou patrimônio.',
            4),
        _doc(
            'secretario',
            'Secretário(a)',
            'Cadastros, certificados, documentos, departamentos e visitantes — sem financeiro.',
            5),
        _doc(
            'tesoureiro',
            'Tesoureiro(a)',
            'Financeiro e relatórios — sem lista geral de membros ou patrimônio.',
            6),
        _doc(
            'lider_departamento',
            'Líder de Departamento',
            'Membros e escalas do seu ministério — sem cadastro da igreja ou financeiro.',
            7),
        _doc('pastor', 'Pastor (legado)', 'Amplo acesso (igrejas antigas): mantém financeiro e patrimônio.', 8),
        _doc('presbitero', 'Presbítero', 'Membros, escalas, departamentos, financeiro, patrimônio.', 9),
        _doc('diacono', 'Diácono', 'Painel, mural, agenda e escalas.', 10),
        _doc('evangelista', 'Evangelista', 'Painel, mural, agenda e escalas.', 11),
        _doc('musico', 'Músico', 'Painel, mural, agenda e escalas.', 12),
      ];

  static Map<String, dynamic> _doc(String key, String label, String descricao, int order) => {
        'key': key,
        'label': label,
        'descricao': descricao,
        'order': order,
        'enabled': true,
        'permissionTemplate': key,
      };

  /// Rótulos de módulos exibidos na UI (igual à página de funções).
  static List<String> permissoesLabelsParaFuncao(String funcaoId) {
    final r = funcaoId.toLowerCase();
    final list = <String>[];
    if (AppRoles.isFullAccess(r)) {
      list.addAll([
        'Painel',
        'Cadastro da Igreja',
        'Membros',
        'Departamentos',
        'Visitantes',
        'Mural',
        'Eventos',
        'Pedidos de Oração',
        'Agenda',
        'Escalas',
        'Certificados',
        'Financeiro',
        'Patrimônio',
        'Relatórios',
        'Configurações',
      ]);
      return list;
    }
    list.addAll(['Painel', 'Mural de Avisos', 'Mural de Eventos', 'Minha Escala', 'Certificados', 'Relatórios']);
    if (AppPermissions.canViewFinance(r)) list.add('Financeiro');
    if (AppPermissions.canViewPatrimonio(r)) list.add('Patrimônio');
    if (AppPermissions.canViewSensitiveMembers(r)) list.add('Membros');
    if (AppPermissions.canEditSchedules(r)) list.add('Escala Geral');
    if (AppPermissions.canEditDepartments(r)) list.add('Departamentos');
    return list;
  }

  /// Templates válidos para nova função (herança de permissões).
  static const List<({String key, String label})> permissionTemplates = [
    (key: 'membro', label: 'Membro (acesso limitado)'),
    (key: 'pastor_presidente', label: 'Pastor Presidente / Admin'),
    (key: 'pastor_auxiliar', label: 'Pastor Auxiliar'),
    (key: 'secretario', label: 'Secretário'),
    (key: 'tesoureiro', label: 'Tesoureiro'),
    (key: 'lider_departamento', label: 'Líder de Departamento'),
    (key: 'pastor', label: 'Pastor (legado amplo)'),
    (key: 'presbitero', label: 'Presbítero'),
    (key: 'diacono', label: 'Diácono'),
    (key: 'evangelista', label: 'Evangelista'),
    (key: 'musico', label: 'Músico'),
    (key: 'adm', label: 'Administrador'),
    (key: 'gestor', label: 'Gestor'),
  ];

  static Future<String> resolveEffectiveTenantId(String tenantId) =>
      TenantResolverService.resolveEffectiveTenantId(tenantId);

  /// Remove toda a coleção e grava os padrões.
  static Future<void> restoreDefaults(String tenantId) async {
    await FirebaseAuth.instance.currentUser?.getIdToken(true);
    final tid = await resolveEffectiveTenantId(tenantId);
    final col = collection(tid);
    final existing = await col.get();
    final batch = FirebaseFirestore.instance.batch();
    for (final d in existing.docs) {
      batch.delete(d.reference);
    }
    for (final m in defaultRoleDocuments()) {
      final k = (m['key'] ?? '').toString();
      if (k.isEmpty) continue;
      batch.set(col.doc(k), {
        ...m,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    }
    await batch.commit();
  }

  /// Garante padrões se a coleção estiver vazia (primeiro acesso).
  static Future<void> seedDefaultsIfEmpty(String tenantId) async {
    final tid = await resolveEffectiveTenantId(tenantId);
    final col = collection(tid);
    final snap = await col.limit(1).get();
    if (snap.docs.isNotEmpty) return;
    await restoreDefaults(tenantId);
  }

  /// Núcleo de permissão usado em AppPermissions / login (FUNCAO_PERMISSOES).
  static Future<String> resolvePermissionBase(String tenantId, String funcaoKey) async {
    var key = funcaoKey.trim().toLowerCase();
    if (key.isEmpty) return 'membro';
    // Rótulo gravado no lugar da chave (ex.: "Administrador") → doc `igrejas/.../funcoesControle/adm`
    if (key == 'administrador' || key == 'administradora') key = 'adm';
    final tid = await resolveEffectiveTenantId(tenantId);
    final d = await collection(tid).doc(key).get();
    if (d.exists) {
      final t = (d.data()?['permissionTemplate'] ?? key).toString().trim().toLowerCase();
      return t.isEmpty ? key : t;
    }
    // Coleção cargos: [permissionTemplate] ou [key] como núcleo de permissão
    try {
      final byId = await FirebaseFirestore.instance
          .collection('igrejas')
          .doc(tid)
          .collection('cargos')
          .doc(key)
          .get();
      if (byId.exists) {
        final pt = (byId.data()?['permissionTemplate'] ?? '').toString().trim();
        if (pt.isNotEmpty) return pt.toLowerCase();
      }
      final cq = await FirebaseFirestore.instance
          .collection('igrejas')
          .doc(tid)
          .collection('cargos')
          .where('key', isEqualTo: key)
          .limit(1)
          .get();
      if (cq.docs.isNotEmpty) {
        final pt =
            (cq.docs.first.data()['permissionTemplate'] ?? '').toString().trim();
        if (pt.isNotEmpty) return pt.toLowerCase();
      }
    } catch (_) {}
    return key;
  }

  /// Ordem de privilégio (índice 0 = máximo) — alinhado a [AppPermissions].
  static const List<List<String>> _roleTierKeys = [
    ['master'],
    ['adm', 'admin', 'administrador', 'administradora'],
    ['gestor', 'pastor_presidente'],
    ['pastor', 'pastora'],
    ['secretario', 'secretário', 'secretária'],
    ['presbitero', 'presbitera'],
    ['pastor_auxiliar'],
    ['tesoureiro', 'tesouraria'],
    ['lider', 'lider_departamento', 'lider_depto'],
    ['diacono'],
    ['evangelista'],
    ['musico'],
    ['membro'],
    ['visitante'],
  ];

  /// Maior valor = mais privilégio no painel (departamentos, financeiro, etc.).
  static int roleRank(String role) {
    final x = role.trim().toLowerCase();
    if (x.isEmpty) return 0;
    for (var i = 0; i < _roleTierKeys.length; i++) {
      if (_roleTierKeys[i].contains(x)) return 1000 - i;
    }
    return 400;
  }

  /// Escolhe o papel mais alto entre candidatos (ex.: FUNCOES = [adm, gestor] → adm).
  static String pickHighestRole(Iterable<String> candidates) {
    var best = 'membro';
    var bestScore = roleRank(best);
    for (final c in candidates) {
      final t = c.trim().toLowerCase();
      if (t.isEmpty) continue;
      final s = roleRank(t);
      if (s > bestScore) {
        bestScore = s;
        best = t;
      }
    }
    return best;
  }

  /// Papel efetivo para o shell: [FUNCAO_PERMISSOES] às vezes fica [membro] ou cargo custom
  /// enquanto [FUNCOES] lista adm+gestor — sem isto o bootstrap de departamentos não roda.
  static Future<String> effectivePanelRoleFromMember(
    String tenantId,
    Map<String, dynamic> memberData,
    String fallbackRole,
  ) async {
    final tid = await resolveEffectiveTenantId(tenantId);
    final candidates = <String>{};

    void add(String? s) {
      final t = s?.trim().toLowerCase() ?? '';
      if (t.isNotEmpty) candidates.add(t);
    }

    add(fallbackRole);
    add((memberData['FUNCAO_PERMISSOES'] ?? memberData['funcao_permissoes'] ?? '').toString());

    final funcoes = memberData['FUNCOES'] ?? memberData['funcoes'];
    if (funcoes is List) {
      for (final e in funcoes) {
        final key = e.toString().trim();
        if (key.isEmpty) continue;
        try {
          add(await resolvePermissionBase(tid, key));
        } catch (_) {
          add(key.toLowerCase());
        }
      }
    } else {
      final fun = (memberData['FUNCAO'] ?? memberData['CARGO'] ?? memberData['cargo'] ?? '').toString().trim();
      if (fun.isNotEmpty) {
        try {
          add(await resolvePermissionBase(tid, fun));
        } catch (_) {
          add(fun.toLowerCase());
        }
      }
    }
    return pickHighestRole(candidates);
  }

  /// Opções para o cadastro de membros: vêm de [funcoesControle] se houver docs; senão fallback.
  static Future<List<({String key, String label, String permissionTemplate})>> loadOptionsForMemberPicker(
    String tenantId,
    List<String> fallbackKeys,
    String Function(String key) fallbackLabel,
  ) async {
    final tid = await resolveEffectiveTenantId(tenantId);
    try {
      final snap = await collection(tid).orderBy('order').get();
      if (snap.docs.isNotEmpty) {
        final out = <({String key, String label, String permissionTemplate})>[];
        for (final d in snap.docs) {
          final data = d.data();
          if (data['enabled'] == false) continue;
          final key = (data['key'] ?? d.id).toString().trim();
          if (key.isEmpty) continue;
          final label = (data['label'] ?? key).toString().trim();
          final tpl = (data['permissionTemplate'] ?? key).toString().trim().toLowerCase();
          out.add((key: key, label: label.isEmpty ? key : label, permissionTemplate: tpl.isEmpty ? key : tpl));
        }
        if (out.isNotEmpty) return out;
      }
    } catch (_) {}
    return fallbackKeys
        .map((k) => (key: k, label: fallbackLabel(k), permissionTemplate: k.toLowerCase()))
        .toList();
  }

  static String slugifyKey(String input) {
    return input
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[áàâã]'), 'a')
        .replaceAll(RegExp(r'[éèê]'), 'e')
        .replaceAll(RegExp(r'[íì]'), 'i')
        .replaceAll(RegExp(r'[óòôõ]'), 'o')
        .replaceAll(RegExp(r'[úù]'), 'u')
        .replaceAll(RegExp(r'ç'), 'c')
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_|_$'), '');
  }
}
