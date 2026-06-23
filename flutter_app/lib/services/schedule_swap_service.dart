import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:gestao_yahweh/services/church_operational_paths.dart';
import 'package:gestao_yahweh/services/member_schedule_availability_service.dart';

import 'package:gestao_yahweh/core/firebase_bootstrap.dart';
Map<String, dynamic> _asStringKeyMap(dynamic raw) {
  if (raw is Map) {
    return Map<String, dynamic>.from(raw.map((k, v) => MapEntry(k.toString(), v)));
  }
  return <String, dynamic>{};
}

/// Troca de escala entre membros (convite â†’ aceite â†’ escala atualizada + aviso ao lÃ­der).
class ScheduleSwapCandidate {
  final String cpf;
  final String nome;
  const ScheduleSwapCandidate({required this.cpf, required this.nome});
}

abstract final class ScheduleSwapService {
  ScheduleSwapService._();

  static String _normCpf(String s) => s.replaceAll(RegExp(r'[^0-9]'), '');

  /// Membros do departamento livres no [escalaDay] para o horÃ¡rio [escalaTime]
  /// (sem outra escala sobreposta, sem indisponibilidade no calendÃ¡rio, fora da escala atual).
  static Future<List<ScheduleSwapCandidate>> filterFreeCandidates({
    required String tenantId,
    required String departmentId,
    required String solicitanteCpfDigits,
    required DateTime escalaDay,
    required String escalaTime,
    required Set<String> currentEscalaMemberCpfsNorm,
  }) async {
    final sol = _normCpf(solicitanteCpfDigits);
    if (sol.length != 11) return [];

    final start = DateTime(escalaDay.year, escalaDay.month, escalaDay.day);
    final end = DateTime(escalaDay.year, escalaDay.month, escalaDay.day, 23, 59, 59, 999);

    final op = await ChurchOperationalPaths.resolveCached(tenantId);
    final escCol = ChurchOperationalPaths.churchDoc(op).collection('escalas');

    QuerySnapshot<Map<String, dynamic>> daySnap;
    try {
      daySnap = await escCol
          .where('date', isGreaterThanOrEqualTo: Timestamp.fromDate(start))
          .where('date', isLessThanOrEqualTo: Timestamp.fromDate(end))
          .limit(120)
          .get();
    } catch (_) {
      return [];
    }

    /// normCpf -> true se estÃ¡ ocupado em alguma escala com horÃ¡rio sobreposto a [escalaTime].
    final busyNorm = <String, bool>{};

    for (final doc in daySnap.docs) {
      final d = doc.data();
      final t = (d['time'] ?? '').toString();
      if (!MemberScheduleAvailability.timesOverlapRough(escalaTime, t)) continue;
      final mems =
          ((d['memberCpfs'] as List?) ?? []).map((e) => _normCpf(e.toString())).toList();
      for (final c in mems) {
        if (c.length == 11) busyNorm[c] = true;
      }
    }

    final membrosCol =
        await ChurchOperationalPaths.subcollectionResolved(tenantId, 'membros');
    final snap = await membrosCol.get();
    final out = <ScheduleSwapCandidate>[];

    for (final m in snap.docs) {
      final data = m.data();
      final depts =
          (data['DEPARTAMENTOS'] as List?)?.map((e) => e.toString()).toList() ?? [];
      if (!depts.contains(departmentId)) continue;
      final cpf =
          (data['CPF'] ?? data['cpf'] ?? '').toString().replaceAll(RegExp(r'[^0-9]'), '');
      if (cpf.length != 11 || cpf == sol) continue;
      final n = _normCpf(cpf);
      if (currentEscalaMemberCpfsNorm.contains(n)) continue;
      if (busyNorm[n] == true) continue;
      final ymds = MemberScheduleAvailability.parseYmdList(
        data[MemberScheduleAvailability.fieldYmds],
      );
      if (MemberScheduleAvailability.isUnavailableOn(ymds, escalaDay)) continue;
      final nome =
          (data['NOME_COMPLETO'] ?? data['nome'] ?? '').toString().trim();
      out.add(ScheduleSwapCandidate(cpf: cpf, nome: nome.isNotEmpty ? nome : cpf));
    }

    out.sort((a, b) => a.nome.toLowerCase().compareTo(b.nome.toLowerCase()));
    return out;
  }

  /// Aceitar ou recusar convite de troca (Cloud Function aplica a troca e notifica lÃ­deres).
  static Future<Map<String, dynamic>> respondSwap({
    required String tenantId,
    required String trocaId,
    required bool accept,
  }) async {
    final fn = FirebaseFunctions.instanceFor(app: firebaseDefaultApp, region: '')
        .httpsCallable('respondScheduleSwap');
    final res = await fn.call(<String, dynamic>{
      'tenantId': tenantId,
      'trocaId': trocaId,
      'accept': accept,
    });
    return _asStringKeyMap(res.data);
  }
}

