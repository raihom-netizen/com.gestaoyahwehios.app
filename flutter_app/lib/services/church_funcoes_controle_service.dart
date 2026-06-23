import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:gestao_yahweh/core/repositories/church_repository.dart';
import 'package:gestao_yahweh/core/roles_permissions.dart';
import 'package:gestao_yahweh/services/app_permissions.dart';
import 'package:gestao_yahweh/services/church_operational_paths.dart';
import 'package:gestao_yahweh/services/church_tenant_resilient_reads.dart';

import 'package:gestao_yahweh/core/firebase_bootstrap.dart';
/// FunÃ§Ãµes do painel da igreja â€” catÃ¡logo em `igrejas/{tenantId}/funcoesControle/{key}`.
/// O gestor pode adicionar/remover entradas e restaurar padrÃµes. O campo [permissionTemplate]
/// define o nÃºcleo de permissÃµes (AppPermissions); [key] Ã© o valor gravado em FUNCAO no membro.
class ChurchFuncoesControleService {
  ChurchFuncoesControleService._();

  /// Chaves que nÃ£o podem ser excluÃ­das (acesso base do sistema).
  static const Set<String> protectedKeys = {'membro', 'adm', 'gestor', 'master'};

  /// [tenantId] deve ser o ID operacional (jÃ¡ resolvido pelo painel).
  static CollectionReference<Map<String, dynamic>> collection(String tenantId) =>
      ChurchOperationalPaths.churchDoc(tenantId).collection('funcoesControle');

  /// Documentos padrÃ£o (mesmo conjunto que a tela informativa original).
  static List<Map<String, dynamic>> defaultRoleDocuments() => [
        _doc('membro', 'Membro / Congregado', 'Mural, eventos, agenda, perfil e cartÃ£o.', 0),
        _doc('adm', 'Administrador', 'Acesso total ao painel da igreja.', 1),
        _doc('gestor', 'Gestor', 'Acesso total: cadastro, membros, financeiro, patrimÃ´nio, etc.', 2),
        _doc(
            'pastor_presidente',
            'Pastor Presidente',
            'LideranÃ§a mÃ¡xima: equivalente a gestor no painel.',
            3),
        _doc(
            'pastor_auxiliar',
            'Pastor Auxiliar / Ministerial',
            'Membros, agenda e escalas â€” sem financeiro ou patrimÃ´nio.',
            4),
        _doc(
            'secretario',
            'SecretÃ¡rio(a)',
            'Cadastros, certificados, documentos, departamentos e visitantes â€” sem financeiro.',
            5),
        _doc(
            'tesoureiro',
            'Tesoureiro(a)',
            'Financeiro e relatÃ³rios â€” sem lista geral de membros ou patrimÃ´nio.',
            6),
        _doc(
            'lider_departamento',
            'LÃ­der de Departamento',
            'Agenda, mural (avisos), eventos e escalas dos departamentos em que Ã© lÃ­der (pode ser vÃ¡rios). Sem financeiro.',
            7),
        _doc('pastor', 'Pastor (legado)', 'Amplo acesso (igrejas antigas): mantÃ©m financeiro e patrimÃ´nio.', 8),
        _doc('presbitero', 'PresbÃ­tero', 'Membros, escalas, departamentos, financeiro, patrimÃ´nio.', 9),
        _doc('diacono', 'DiÃ¡cono', 'Painel, mural, agenda e escalas.', 10),
        _doc('evangelista', 'Evangelista', 'Painel, mural, agenda e escalas.', 11),
        _doc('musico', 'MÃºsico', 'Painel, mural, agenda e escalas.', 12),
      ];

  static Map<String, dynamic> _doc(String key, String label, String descricao, int order) => {
        'key': key,
        'label': label,
        'descricao': descricao,
        'order': order,
        'enabled': true,
        'permissionTemplate': key,
      };

  /// RÃ³tulos de mÃ³dulos exibidos na UI (igual Ã  pÃ¡gina de funÃ§Ãµes).
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
        'Pedidos de OraÃ§Ã£o',
        'Agenda',
        'Escalas',
        'Certificados',
        'Financeiro',
        'PatrimÃ´nio',
        'RelatÃ³rios',
        'ConfiguraÃ§Ãµes',
      ]);
      return list;
    }
    list.addAll(['Painel', 'Mural de Avisos', 'Mural de Eventos', 'Minha Escala', 'Certificados', 'RelatÃ³rios']);
    if (AppPermissions.canViewFinance(r)) list.add('Financeiro');
    if (AppPermissions.canViewPatrimonio(r)) list.add('PatrimÃ´nio');
    if (AppPermissions.canViewSensitiveMembers(r)) list.add('Membros');
    if (AppPermissions.canEditSchedules(r)) {
      list.add('Escala Geral');
    } else if (ChurchRolePermissions.isDepartmentLeaderRoleKey(r)) {
      list.add('Escala (departamentos)');
    }
    if (AppPermissions.canEditDepartments(r)) list.add('Departamentos');
    return list;
  }

  /// Templates vÃ¡lidos para nova funÃ§Ã£o (heranÃ§a de permissÃµes).
  static const List<({String key, String label})> permissionTemplates = [
    (key: 'membro', label: 'Membro (acesso limitado)'),
    (key: 'pastor_presidente', label: 'Pastor Presidente / Admin'),
    (key: 'pastor_auxiliar', label: 'Pastor Auxiliar'),
    (key: 'secretario', label: 'SecretÃ¡rio'),
    (key: 'tesoureiro', label: 'Tesoureiro'),
    (key: 'lider_departamento', label: 'LÃ­der de Departamento'),
    (key: 'pastor', label: 'Pastor (legado amplo)'),
    (key: 'presbitero', label: 'PresbÃ­tero'),
    (key: 'diacono', label: 'DiÃ¡cono'),
    (key: 'evangelista', label: 'Evangelista'),
    (key: 'musico', label: 'MÃºsico'),
    (key: 'adm', label: 'Administrador'),
    (key: 'gestor', label: 'Gestor'),
  ];

  static Future<String> resolveEffectiveTenantId(String tenantId) async {
    final direct = ChurchRepository.churchId(tenantId);
    return direct.isNotEmpty ? direct : tenantId.trim();
  }

  /// Remove toda a coleÃ§Ã£o e grava os padrÃµes.
  static Future<void> restoreDefaults(String tenantId) async {
    await firebaseDefaultAuth.currentUser?.getIdToken(true);
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

  /// Garante padrÃµes se a coleÃ§Ã£o estiver vazia (primeiro acesso).
  static Future<void> seedDefaultsIfEmpty(String tenantId) async {
    final tid = await resolveEffectiveTenantId(tenantId);
    final col = collection(tid);
    final snap = await col.limit(1).get();
    if (snap.docs.isNotEmpty) return;
    await restoreDefaults(tenantId);
  }

  /// NÃºcleo de permissÃ£o usado em AppPermissions / login (FUNCAO_PERMISSOES).
  static Future<String> resolvePermissionBase(String tenantId, String funcaoKey) async {
    var key = funcaoKey.trim().toLowerCase();
    if (key.isEmpty) return 'membro';
    // RÃ³tulo gravado no lugar da chave (ex.: "Administrador") â†’ doc `igrejas/.../funcoesControle/adm`
    if (key == 'administrador' || key == 'administradora') key = 'adm';
    final tid = await resolveEffectiveTenantId(tenantId);
    final d = await collection(tid).doc(key).get();
    if (d.exists) {
      final t = (d.data()?['permissionTemplate'] ?? key).toString().trim().toLowerCase();
      return t.isEmpty ? key : t;
    }
    // ColeÃ§Ã£o cargos: [permissionTemplate] ou [key] como nÃºcleo de permissÃ£o
    try {
      final cargosSnap = await ChurchTenantResilientReads.cargos(tid, limit: 120);
      for (final d in cargosSnap.docs) {
        if (d.id == key) {
          final pt = (d.data()['permissionTemplate'] ?? '').toString().trim();
          if (pt.isNotEmpty) return pt.toLowerCase();
        }
        final dk = (d.data()['key'] ?? '').toString().trim().toLowerCase();
        if (dk == key) {
          final pt = (d.data()['permissionTemplate'] ?? '').toString().trim();
          if (pt.isNotEmpty) return pt.toLowerCase();
        }
      }
    } catch (_) {}
    return key;
  }

  /// Ordem de privilÃ©gio (Ã­ndice 0 = mÃ¡ximo) â€” alinhado a [AppPermissions].
  static const List<List<String>> _roleTierKeys = [
    ['master'],
    ['adm', 'admin', 'administrador', 'administradora'],
    ['gestor', 'pastor_presidente'],
    ['pastor', 'pastora'],
    ['secretario', 'secretÃ¡rio', 'secretÃ¡ria'],
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

  /// Maior valor = mais privilÃ©gio no painel (departamentos, financeiro, etc.).
  static int roleRank(String role) {
    final x = role.trim().toLowerCase();
    if (x.isEmpty) return 0;
    for (var i = 0; i < _roleTierKeys.length; i++) {
      if (_roleTierKeys[i].contains(x)) return 1000 - i;
    }
    return 400;
  }

  /// Escolhe o papel mais alto entre candidatos (ex.: FUNCOES = [adm, gestor] â†’ adm).
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

  /// Papel efetivo para o shell: [FUNCAO_PERMISSOES] Ã s vezes fica [membro] ou cargo custom
  /// enquanto [FUNCOES] lista adm+gestor â€” sem isto o bootstrap de departamentos nÃ£o roda.
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

  /// OpÃ§Ãµes para o cadastro de membros: prioriza [cargos] (mÃ³dulo Cargos); legado [funcoesControle]; fallback.
  static Future<List<({String key, String label, String permissionTemplate})>> loadOptionsForMemberPicker(
    String tenantId,
    List<String> fallbackKeys,
    String Function(String key) fallbackLabel,
  ) async {
    final tid = await resolveEffectiveTenantId(tenantId);
    try {
      final cargos = await ChurchTenantResilientReads.cargos(tid, limit: 120);
      if (cargos.docs.isNotEmpty) {
        final out = <({String key, String label, String permissionTemplate})>[];
        for (final d in cargos.docs) {
          final data = d.data();
          final key = (data['key'] ?? d.id).toString().trim();
          if (key.isEmpty) continue;
          final label = (data['name'] ?? key).toString().trim();
          final tpl =
              (data['permissionTemplate'] ?? key).toString().trim().toLowerCase();
          out.add((
            key: key,
            label: label.isEmpty ? key : label,
            permissionTemplate: tpl.isEmpty ? key : tpl,
          ));
        }
        if (out.isNotEmpty) return out;
      }
    } catch (_) {}
    try {
      final snap = await ChurchTenantResilientReads.funcoesControle(tid, limit: 120);
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
        .replaceAll(RegExp(r'[Ã¡Ã Ã¢Ã£]'), 'a')
        .replaceAll(RegExp(r'[Ã©Ã¨Ãª]'), 'e')
        .replaceAll(RegExp(r'[Ã­Ã¬]'), 'i')
        .replaceAll(RegExp(r'[Ã³Ã²Ã´Ãµ]'), 'o')
        .replaceAll(RegExp(r'[ÃºÃ¹]'), 'u')
        .replaceAll(RegExp(r'Ã§'), 'c')
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_|_$'), '');
  }
}

