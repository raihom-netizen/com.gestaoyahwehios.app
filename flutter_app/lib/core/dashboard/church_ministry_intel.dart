import 'package:cloud_firestore/cloud_firestore.dart';

/// Modelos e cálculos do painel "Saúde ministerial & BI" (painel da igreja).
class MemberPastoralAlert {
  final String memberId;
  final String name;
  final String cpfDigits;
  final String summary;

  const MemberPastoralAlert({
    required this.memberId,
    required this.name,
    required this.cpfDigits,
    required this.summary,
  });
}

class VisitorFunnelSnapshot {
  final int novosNoMes;
  final int emAcompanhamento;
  final int convertidosNoMes;

  const VisitorFunnelSnapshot({
    required this.novosNoMes,
    required this.emAcompanhamento,
    required this.convertidosNoMes,
  });
}

class MonthlyMemberFlow {
  final String key;
  final int novos;
  final int batismos;
  final int saidas;

  const MonthlyMemberFlow({
    required this.key,
    required this.novos,
    required this.batismos,
    required this.saidas,
  });
}

class ChurchFinanceInsight {
  final double mediaEntradasMensal;
  final double mediaSaidasMensal;
  final double projecaoSaidasProxMes;
  final double? metaValor;
  final double? metaAcumulado;
  final String? metaTitulo;

  const ChurchFinanceInsight({
    required this.mediaEntradasMensal,
    required this.mediaSaidasMensal,
    required this.projecaoSaidasProxMes,
    this.metaValor,
    this.metaAcumulado,
    this.metaTitulo,
  });
}

class ChurchMinistryIntel {
  final List<MemberPastoralAlert> alerts;
  final VisitorFunnelSnapshot funnel;
  final List<MonthlyMemberFlow> last12Months;
  final ChurchFinanceInsight? finance;

  const ChurchMinistryIntel({
    required this.alerts,
    required this.funnel,
    required this.last12Months,
    this.finance,
  });
}

class ChurchMinistryIntelService {
  static const int staleDays = 45;

  static String _normCpf(String? raw) =>
      (raw ?? '').replaceAll(RegExp(r'\D'), '');

  /// Evita `List.cast<String>()` / `as List?` com tipos errados vindos do Firestore.
  static List<String> _memberCpfDigitsFromField(dynamic v) {
    if (v == null) return <String>[];
    if (v is List) {
      return v
          .map((e) => _normCpf(e?.toString()))
          .where((c) => c.length >= 3)
          .toList();
    }
    final single = _normCpf(v.toString());
    return single.length >= 3 ? <String>[single] : <String>[];
  }

  /// RSVP: lista de UIDs; aceita legado em Map (chaves = uid).
  static List<String> _rsvpUidListFromField(dynamic v) {
    if (v == null) return <String>[];
    if (v is List) {
      return v
          .map((e) => e?.toString().trim() ?? '')
          .where((s) => s.isNotEmpty)
          .toList();
    }
    if (v is Map) {
      return v.keys
          .map((k) => k?.toString().trim() ?? '')
          .where((s) => s.isNotEmpty)
          .toList();
    }
    return <String>[];
  }

  static DateTime? _ts(dynamic v) {
    if (v == null) return null;
    if (v is Timestamp) return v.toDate();
    if (v is DateTime) return v;
    if (v is Map) {
      final sec = v['seconds'] ?? v['_seconds'];
      if (sec != null) {
        final n = sec is num ? sec.toInt() : int.tryParse(sec.toString());
        if (n != null) {
          return DateTime.fromMillisecondsSinceEpoch(n * 1000);
        }
      }
    }
    return DateTime.tryParse(v.toString());
  }

  static String _memberName(Map<String, dynamic> m) {
    for (final k in ['NOME_COMPLETO', 'nome', 'name']) {
      final s = (m[k] ?? '').toString().trim();
      if (s.isNotEmpty) return s;
    }
    return 'Membro';
  }

  static bool _isActiveMember(Map<String, dynamic> m) {
    final s = (m['STATUS'] ?? m['status'] ?? m['ativo'] ?? 'ativo').toString().toLowerCase();
    if (s.contains('pendent')) return false;
    if (s.contains('inativ')) return false;
    return true;
  }

  static DateTime? _memberJoinedAt(Map<String, dynamic> m) =>
      _ts(m['CRIADO_EM'] ?? m['createdAt']);

  static bool _noticiaIsAviso(Map<String, dynamic> m) =>
      (m['type'] ?? 'aviso').toString().toLowerCase() == 'aviso';

  /// Agrega dados já carregados (evita N+1 no dashboard).
  static ChurchMinistryIntel build({
    required List<QueryDocumentSnapshot<Map<String, dynamic>>> members,
    required List<QueryDocumentSnapshot<Map<String, dynamic>>> escalas,
    required List<QueryDocumentSnapshot<Map<String, dynamic>>> noticias,
    required List<QueryDocumentSnapshot<Map<String, dynamic>>> visitantes,
    required List<QueryDocumentSnapshot<Map<String, dynamic>>> financeDocs,
    Map<String, dynamic>? churchData,
    bool includeFinance = true,
  }) {
    final now = DateTime.now();
    final cutoff = now.subtract(const Duration(days: staleDays));

    final escalaLast = <String, DateTime>{}; // cpf digits -> last date in window
    for (final d in escalas) {
      final m = d.data();
      final dt = _ts(m['date']);
      if (dt == null) continue;
      if (dt.isBefore(cutoff)) continue;
      final cpfs = _memberCpfDigitsFromField(m['memberCpfs']);
      for (final c in cpfs) {
        final prev = escalaLast[c];
        if (prev == null || dt.isAfter(prev)) escalaLast[c] = dt;
      }
    }

    final rsvpLast = <String, DateTime>{};
    for (final d in noticias) {
      final m = d.data();
      if (_noticiaIsAviso(m)) continue;
      final dt = _ts(m['startAt']) ?? _ts(m['createdAt']);
      if (dt == null || dt.isBefore(cutoff)) continue;
      final rsvp = _rsvpUidListFromField(m['rsvp']);
      for (final uid in rsvp) {
        final prev = rsvpLast[uid];
        if (prev == null || dt.isAfter(prev)) rsvpLast[uid] = dt;
      }
    }

    final alerts = <MemberPastoralAlert>[];
    for (final doc in members) {
      final m = doc.data();
      if (!_isActiveMember(m)) continue;
      final joined = _memberJoinedAt(m);
      if (joined != null && joined.isAfter(cutoff)) continue;

      final cpf = _normCpf(
        (m['CPF'] ?? m['cpf'] ?? doc.id).toString(),
      );
      if (cpf.length < 3) continue;

      final authUid = (m['authUid'] ?? '').toString().trim();
      final lastE = escalaLast[cpf];
      final lastR = authUid.isNotEmpty ? rsvpLast[authUid] : null;
      DateTime? lastEng;
      if (lastE != null && lastR != null) {
        lastEng = lastE.isAfter(lastR) ? lastE : lastR;
      } else {
        lastEng = lastE ?? lastR;
      }

      if (lastEng != null && !lastEng.isBefore(cutoff)) continue;

      final parts = <String>[];
      if (lastE == null) parts.add('sem escala (${staleDays}d)');
      if (authUid.isNotEmpty && lastR == null) {
        parts.add('sem confirmação em eventos (${staleDays}d)');
      } else if (authUid.isEmpty) {
        parts.add('sem vínculo de app para RSVP');
      }
      alerts.add(MemberPastoralAlert(
        memberId: doc.id,
        name: _memberName(m),
        cpfDigits: cpf,
        summary: parts.join(' · '),
      ));
    }
    alerts.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

    final startMonth = DateTime(now.year, now.month, 1);
    int novosMes = 0, convMes = 0, acomp = 0;
    for (final d in visitantes) {
      final v = d.data();
      final st = (v['status'] ?? 'Novo').toString();
      final ca = _ts(v['createdAt']);
      if (ca != null &&
          ca.year == startMonth.year &&
          ca.month == startMonth.month) {
        novosMes++;
      }
      final ua = _ts(v['updatedAt']);
      if (st == 'Convertido' &&
          ua != null &&
          ua.year == startMonth.year &&
          ua.month == startMonth.month) {
        convMes++;
      }
      if (st == 'Em acompanhamento') acomp++;
    }

    final monthKeys = <String>[];
    final byMonth = <String, ({int n, int b, int s})>{};
    for (var i = 11; i >= 0; i--) {
      final d = DateTime(now.year, now.month - i, 1);
      final k = '${d.year}-${d.month.toString().padLeft(2, '0')}';
      monthKeys.add(k);
      byMonth[k] = (n: 0, b: 0, s: 0);
    }

    for (final doc in members) {
      final m = doc.data();
      final c = _ts(m['CRIADO_EM'] ?? m['createdAt']);
      if (c != null) {
        final k = '${c.year}-${c.month.toString().padLeft(2, '0')}';
        final e = byMonth[k];
        if (e != null) {
          byMonth[k] = (n: e.n + 1, b: e.b, s: e.s);
        }
      }
      final bat = _ts(m['DATA_BATISMO'] ?? m['dataBatismo'] ?? m['data_batismo']);
      if (bat != null) {
        final k = '${bat.year}-${bat.month.toString().padLeft(2, '0')}';
        final e = byMonth[k];
        if (e != null) {
          byMonth[k] = (n: e.n, b: e.b + 1, s: e.s);
        }
      }
      final st = (m['STATUS'] ?? m['status'] ?? '').toString().toLowerCase();
      if (st.contains('inativ')) {
        final u = _ts(m['updatedAt']);
        if (u != null) {
          final k = '${u.year}-${u.month.toString().padLeft(2, '0')}';
          final e = byMonth[k];
          if (e != null) {
            byMonth[k] = (n: e.n, b: e.b, s: e.s + 1);
          }
        }
      }
    }

    final flow = monthKeys
        .map((k) {
          final e = byMonth[k]!;
          return MonthlyMemberFlow(key: k, novos: e.n, batismos: e.b, saidas: e.s);
        })
        .toList();

    ChurchFinanceInsight? fin;
    if (includeFinance && financeDocs.isNotEmpty) {
      final sixMonthsKeys = <String>{};
      for (var i = 0; i < 6; i++) {
        final d = DateTime(now.year, now.month - i, 1);
        sixMonthsKeys.add('${d.year}-${d.month.toString().padLeft(2, '0')}');
      }
      final entByMonth = <String, double>{};
      final saiByMonth = <String, double>{};
      for (final d in financeDocs) {
        final m = d.data();
        final tipo = (m['type'] ?? m['tipo'] ?? '').toString().toLowerCase();
        final raw = m['createdAt'] ?? m['date'];
        final dt = _ts(raw);
        if (dt == null) continue;
        final k = '${dt.year}-${dt.month.toString().padLeft(2, '0')}';
        final amt = m['amount'] ?? m['valor'] ?? 0;
        final v = amt is num ? amt.toDouble() : double.tryParse(amt.toString()) ?? 0;
        if (tipo.contains('saida') || tipo.contains('despesa')) {
          saiByMonth[k] = (saiByMonth[k] ?? 0) + v.abs();
        } else if (!tipo.contains('transfer')) {
          entByMonth[k] = (entByMonth[k] ?? 0) + v.abs();
        }
      }
      double sumE = 0, sumS = 0;
      var c = 0;
      for (final k in sixMonthsKeys) {
        final e = entByMonth[k] ?? 0;
        final s = saiByMonth[k] ?? 0;
        if (e > 0 || s > 0) c++;
        sumE += e;
        sumS += s;
      }
      final div = c > 0 ? c : 1;
      final metaVal = _parseDouble(churchData?['metaMinisterialValor']);
      final metaAcu = _parseDouble(churchData?['metaMinisterialAcumulado']);
      final metaTit = (churchData?['metaMinisterialTitulo'] ?? '').toString().trim();
      fin = ChurchFinanceInsight(
        mediaEntradasMensal: sumE / div,
        mediaSaidasMensal: sumS / div,
        projecaoSaidasProxMes: sumS / div,
        metaValor: metaVal,
        metaAcumulado: metaAcu,
        metaTitulo: metaTit.isEmpty ? null : metaTit,
      );
    }

    return ChurchMinistryIntel(
      alerts: alerts.take(40).toList(),
      funnel: VisitorFunnelSnapshot(
        novosNoMes: novosMes,
        emAcompanhamento: acomp,
        convertidosNoMes: convMes,
      ),
      last12Months: flow,
      finance: fin,
    );
  }

  static double? _parseDouble(dynamic v) {
    if (v == null) return null;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString().replaceAll(',', '.'));
  }
}
