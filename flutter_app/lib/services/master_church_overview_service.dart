import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show debugPrint, kDebugMode;
import 'package:gestao_yahweh/core/firebase_bootstrap.dart';

/// Uma pessoa com papel de liderança ou gestão na igreja.
class MasterChurchPerson {
  const MasterChurchPerson({
    required this.id,
    required this.name,
    required this.role,
    this.email = '',
    this.phone = '',
    this.photoUrl = '',
  });

  final String id;
  final String name;
  final String role;
  final String email;
  final String phone;
  final String photoUrl;
}

/// Retrato de uma igreja para o painel master.
class MasterChurchOverview {
  const MasterChurchOverview({
    required this.tenantId,
    required this.data,
    required this.membersTotal,
    required this.membersActive,
    required this.membersPending,
    required this.leaders,
    required this.managers,
    required this.departmentsCount,
    required this.eventsCount,
    required this.avisosCount,
    required this.visitorsCount,
  });

  final String tenantId;
  final Map<String, dynamic> data;
  final int membersTotal;
  final int membersActive;
  final int membersPending;
  final List<MasterChurchPerson> leaders;
  final List<MasterChurchPerson> managers;
  final int departmentsCount;
  final int eventsCount;
  final int avisosCount;
  final int visitorsCount;

  String get name {
    for (final k in ['nome', 'name', 'nomeIgreja']) {
      final v = (data[k] ?? '').toString().trim();
      if (v.isNotEmpty) return v;
    }
    return tenantId;
  }

  String get logoUrl => (data['logoUrl'] ?? '').toString().trim();

  String get document {
    for (final k in ['cnpj', 'CNPJ', 'cnpjCpf']) {
      final v = (data[k] ?? '').toString().trim();
      if (v.isNotEmpty) return v;
    }
    return '';
  }

  String get plan {
    for (final k in ['plano', 'planId', 'saasTier']) {
      final v = (data[k] ?? '').toString().trim();
      if (v.isNotEmpty) return v;
    }
    return '';
  }

  /// Endereço numa linha — vazio quando não há nada preenchido.
  String get address {
    final rua = (data['rua'] ?? data['endereco'] ?? '').toString().trim();
    final num = (data['quadraLoteNumero'] ?? '').toString().trim();
    final bairro = (data['bairro'] ?? '').toString().trim();
    final cidade = (data['cidade'] ?? '').toString().trim();
    final uf = (data['estado'] ?? '').toString().trim();
    final cep = (data['cep'] ?? '').toString().trim();
    final partes = <String>[
      if (rua.isNotEmpty) [rua, if (num.isNotEmpty) num].join(', '),
      if (bairro.isNotEmpty) bairro,
      if (cidade.isNotEmpty) [cidade, if (uf.isNotEmpty) uf].join(' - '),
      if (cep.isNotEmpty) 'CEP $cep',
    ];
    return partes.join(' · ');
  }

  String get phone {
    for (final k in ['telefone', 'phone', 'whatsapp']) {
      final v = (data[k] ?? '').toString().trim();
      if (v.isNotEmpty) return v;
    }
    return '';
  }

  String get managerName => (data['gestorNome'] ?? '').toString().trim();
  String get managerEmail => (data['gestorEmail'] ?? '').toString().trim();
  String get managerPhone => (data['gestorTelefone'] ?? '').toString().trim();

  DateTime? get expiresAt {
    final v = data['data_vencimento'] ?? data['licenseExpiresAt'];
    if (v is Timestamp) return v.toDate();
    if (v is String && v.trim().isNotEmpty) return DateTime.tryParse(v.trim());
    return null;
  }
}

/// Carrega o retrato completo de uma igreja para a tela do master.
///
/// Lê o documento da igreja (que já traz contadores mantidos por triggers) e a
/// lista de membros uma única vez, classificando liderança em memória — em vez
/// de uma query `count()` por papel, que seria uma ida à rede para cada um.
abstract final class MasterChurchOverviewService {
  MasterChurchOverviewService._();

  /// Papéis que contam como liderança na igreja (normalizados, minúsculas).
  static const _leaderRoles = <String>{
    'pastor',
    'pastor(a)',
    'pastora',
    'pastor_aux',
    'pastor auxiliar',
    'lider',
    'líder',
    'lider de departamento',
    'diacono',
    'diácono',
    'diaconisa',
    'evangelista',
    'presbitero',
    'presbítero',
    'secretario',
    'secretário',
    'secretaria',
    'tesoureiro',
    'tesoureira',
    'missionario',
    'missionária',
    'missionaria',
  };

  /// Papéis de gestão (acesso administrativo ao painel).
  static const _managerRoles = <String>{
    'adm',
    'admin',
    'administrador',
    'manager',
    'gestor',
    'gestora',
    'master',
  };

  static String _roleOf(Map<String, dynamic> m) {
    for (final k in ['role', 'CARGO', 'FUNCAO', 'FUNCAO_PERMISSOES', 'cargo']) {
      final v = (m[k] ?? '').toString().trim();
      if (v.isNotEmpty) return v.toLowerCase();
    }
    return '';
  }

  static String _nameOf(Map<String, dynamic> m, String fallbackId) {
    for (final k in ['nome', 'name', 'NOME', 'displayName', 'nomeCompleto']) {
      final v = (m[k] ?? '').toString().trim();
      if (v.isNotEmpty) return v;
    }
    return fallbackId;
  }

  static String _firstOf(Map<String, dynamic> m, List<String> keys) {
    for (final k in keys) {
      final v = (m[k] ?? '').toString().trim();
      if (v.isNotEmpty) return v;
    }
    return '';
  }

  static int _intOf(Map<String, dynamic> d, List<String> keys) {
    for (final k in keys) {
      final v = d[k];
      if (v is num) return v.toInt();
      final p = int.tryParse('${v ?? ''}');
      if (p != null) return p;
    }
    return 0;
  }

  static Future<MasterChurchOverview> load(String tenantId) async {
    final tid = tenantId.trim();
    if (tid.isEmpty) throw ArgumentError('tenantId vazio');
    final db = firebaseDefaultFirestore;
    final churchRef = db.collection('igrejas').doc(tid);

    final churchSnap = await churchRef.get();
    final data = Map<String, dynamic>.from(churchSnap.data() ?? {});

    // Membros: uma leitura só. O teto de 800 é generoso para a escala atual e
    // evita puxar uma coleção inteira sem limite se uma igreja crescer muito.
    final leaders = <MasterChurchPerson>[];
    var membersTotal = 0;
    var membersActive = 0;
    var membersPending = 0;
    try {
      final membros = await churchRef.collection('membros').limit(800).get();
      membersTotal = membros.size;
      for (final d in membros.docs) {
        final m = d.data();
        final role = _roleOf(m);
        final status = _firstOf(m, ['status', 'STATUS']).toLowerCase();
        final ativo = m['ativo'];
        final inativo = status.contains('inativ') || ativo == false;
        if (inativo) {
          // não conta como ativo
        } else {
          membersActive++;
        }
        if (status.contains('pendente')) membersPending++;
        if (_leaderRoles.contains(role) || _managerRoles.contains(role)) {
          leaders.add(
            MasterChurchPerson(
              id: d.id,
              name: _nameOf(m, d.id),
              role: role,
              email: _firstOf(m, ['email', 'EMAIL']),
              phone: _firstOf(m, ['telefone', 'phone', 'whatsapp', 'TELEFONE']),
              photoUrl: _firstOf(m, [
                'photoUrl',
                'fotoUrl',
                'foto',
                'photoThumbUrl',
              ]),
            ),
          );
        }
      }
    } catch (e) {
      if (kDebugMode) debugPrint('MasterChurchOverview membros: $e');
      // Contadores do doc como rede de segurança quando a leitura falha.
      membersTotal = _intOf(data, ['membersTotalCount', 'membersCount']);
      membersActive = _intOf(data, ['activeMembersCount']);
    }
    if (membersTotal == 0) {
      membersTotal = _intOf(data, ['membersTotalCount', 'membersCount']);
    }
    if (membersPending == 0) {
      membersPending = _intOf(data, ['pendingMembersCount']);
    }

    // Gestores: quem tem acesso administrativo ao painel da igreja.
    final managers = <MasterChurchPerson>[];
    try {
      final users = await churchRef.collection('users').limit(100).get();
      for (final d in users.docs) {
        final u = d.data();
        final role = (u['role'] ?? '').toString().trim().toLowerCase();
        if (!_managerRoles.contains(role)) continue;
        managers.add(
          MasterChurchPerson(
            id: d.id,
            name: _nameOf(u, _firstOf(u, ['email']) ),
            role: role,
            email: _firstOf(u, ['email']),
            phone: _firstOf(u, ['telefone', 'phone', 'whatsapp']),
          ),
        );
      }
    } catch (e) {
      if (kDebugMode) debugPrint('MasterChurchOverview users: $e');
    }
    // O gestor principal vive no doc da igreja, não em `users` — sem isto uma
    // igreja recém-criada aparecia sem nenhum gestor.
    final gestorEmail = (data['gestorEmail'] ?? '').toString().trim();
    if (gestorEmail.isNotEmpty &&
        !managers.any(
          (m) => m.email.toLowerCase() == gestorEmail.toLowerCase(),
        )) {
      managers.insert(
        0,
        MasterChurchPerson(
          id: 'gestor_principal',
          name: (data['gestorNome'] ?? '').toString().trim().isNotEmpty
              ? (data['gestorNome']).toString().trim()
              : gestorEmail,
          role: 'gestor',
          email: gestorEmail,
          phone: (data['gestorTelefone'] ?? '').toString().trim(),
        ),
      );
    }

    leaders.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

    return MasterChurchOverview(
      tenantId: tid,
      data: data,
      membersTotal: membersTotal,
      membersActive: membersActive,
      membersPending: membersPending,
      leaders: leaders,
      managers: managers,
      departmentsCount: _intOf(data, ['departmentsCount']),
      eventsCount: _intOf(data, ['eventsCount', 'upcomingEventsCount']),
      avisosCount: _intOf(data, ['avisosCount']),
      visitorsCount: _intOf(data, ['newVisitorsCount', 'visitorsCount']),
    );
  }
}
