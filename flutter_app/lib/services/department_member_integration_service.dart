import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:gestao_yahweh/core/church_department_leaders.dart';
import 'package:gestao_yahweh/ui/widgets/safe_network_image.dart' show imageUrlFromMap;

/// Integração Membros ↔ Departamentos ↔ Escalas (denormalização + limpeza de escalas futuras).
class DepartmentMemberIntegrationService {
  DepartmentMemberIntegrationService._();

  static String _normCpf(String s) => s.replaceAll(RegExp(r'[^0-9]'), '');

  static Map<String, dynamic> _linkedMemberSnapshot(
    String memberDocId,
    Map<String, dynamic> memberData,
  ) {
    final nome = (memberData['NOME_COMPLETO'] ??
            memberData['nome'] ??
            memberData['name'] ??
            memberDocId)
        .toString()
        .trim();
    final foto = imageUrlFromMap(memberData);
    final cpf = _normCpf(
        (memberData['CPF'] ?? memberData['cpf'] ?? '').toString());
    return {
      'memberDocId': memberDocId,
      'nome': nome,
      'fotoUrl': foto,
      'cpfDigits': cpf,
      'updatedAt': FieldValue.serverTimestamp(),
    };
  }

  static DocumentReference<Map<String, dynamic>> _memberRef(
    String tenantId,
    String memberDocId,
  ) =>
      FirebaseFirestore.instance
          .collection('igrejas')
          .doc(tenantId)
          .collection('membros')
          .doc(memberDocId);

  static DocumentReference<Map<String, dynamic>> _linkedRef(
    String tenantId,
    String departmentId,
    String memberDocId,
  ) =>
      FirebaseFirestore.instance
          .collection('igrejas')
          .doc(tenantId)
          .collection('departamentos')
          .doc(departmentId)
          .collection('membros_vinculados')
          .doc(memberDocId);

  static DocumentReference<Map<String, dynamic>> _deptRef(
    String tenantId,
    String departmentId,
  ) =>
      FirebaseFirestore.instance
          .collection('igrejas')
          .doc(tenantId)
          .collection('departamentos')
          .doc(departmentId);

  /// Atualiza a lista completa de departamentos do membro + subcoleções + contadores em **um ou mais**
  /// [WriteBatch] (até ~450 operações por batch). Depois remove o CPF das escalas futuras dos
  /// departamentos **removidos** (leitura + batches separados).
  ///
  /// Use no fluxo “editar departamentos” na ficha do membro, em vez de `set` no membro + N chamadas
  /// a [addLinkedDocIncrement] / [removeLinkedDocDecrementAndSchedules].
  static Future<void> syncMemberDepartmentLinks({
    required String tenantId,
    required String memberDocId,
    required Map<String, dynamic> memberData,
    required Set<String> previousDepartmentIds,
    required Set<String> nextDepartmentIds,
    Map<String, dynamic>? extraMemberFields,
  }) async {
    final tid = tenantId.trim();
    final mid = memberDocId.trim();
    if (tid.isEmpty || mid.isEmpty) return;

    final removed = previousDepartmentIds.difference(nextDepartmentIds);
    final added = nextDepartmentIds.difference(previousDepartmentIds);

    final listIds = nextDepartmentIds.toList();
    final extra = extraMemberFields ?? {};

    void applyMemberAndDiff(WriteBatch b) {
      b.set(
        _memberRef(tid, mid),
        {
          'DEPARTAMENTOS': listIds,
          'departamentosIds': listIds,
          'DEPARTAMENTOS_ATUALIZADO_EM': FieldValue.serverTimestamp(),
          ...extra,
        },
        SetOptions(merge: true),
      );
      for (final did in removed) {
        final d = did.trim();
        if (d.isEmpty) continue;
        b.delete(_linkedRef(tid, d, mid));
        b.set(
          _deptRef(tid, d),
          {
            'membrosVinculadosCount': FieldValue.increment(-1),
            'updatedAt': FieldValue.serverTimestamp(),
          },
          SetOptions(merge: true),
        );
      }
      for (final did in added) {
        final d = did.trim();
        if (d.isEmpty) continue;
        b.set(
          _linkedRef(tid, d, mid),
          _linkedMemberSnapshot(mid, memberData),
          SetOptions(merge: true),
        );
        b.set(
          _deptRef(tid, d),
          {
            'membrosVinculadosCount': FieldValue.increment(1),
            'updatedAt': FieldValue.serverTimestamp(),
          },
          SetOptions(merge: true),
        );
      }
    }

    // 1 + 2*|removed| + 2*|added|; limite seguro 450 por batch.
    const maxOps = 450;
    final diffOps = 1 + 2 * removed.length + 2 * added.length;
    if (diffOps <= maxOps) {
      final batch = FirebaseFirestore.instance.batch();
      applyMemberAndDiff(batch);
      await batch.commit();
    } else {
      // Primeiro batch: documento do membro + parte dos removes/adds.
      final remList = removed.toList();
      final addList = added.toList();
      var ri = 0;
      var ai = 0;
      var batch = FirebaseFirestore.instance.batch();
      var count = 0;

      Future<void> commitBatch() async {
        await batch.commit();
        batch = FirebaseFirestore.instance.batch();
        count = 0;
      }

      batch.set(
        _memberRef(tid, mid),
        {
          'DEPARTAMENTOS': listIds,
          'departamentosIds': listIds,
          'DEPARTAMENTOS_ATUALIZADO_EM': FieldValue.serverTimestamp(),
          ...extra,
        },
        SetOptions(merge: true),
      );
      count = 1;

      Future<void> flushIfNeeded(int nextDelta) async {
        if (count + nextDelta > maxOps) {
          await commitBatch();
        }
      }

      while (ri < remList.length) {
        await flushIfNeeded(2);
        final d = remList[ri++].trim();
        if (d.isEmpty) continue;
        batch.delete(_linkedRef(tid, d, mid));
        batch.set(
          _deptRef(tid, d),
          {
            'membrosVinculadosCount': FieldValue.increment(-1),
            'updatedAt': FieldValue.serverTimestamp(),
          },
          SetOptions(merge: true),
        );
        count += 2;
      }
      while (ai < addList.length) {
        await flushIfNeeded(2);
        final d = addList[ai++].trim();
        if (d.isEmpty) continue;
        batch.set(
          _linkedRef(tid, d, mid),
          _linkedMemberSnapshot(mid, memberData),
          SetOptions(merge: true),
        );
        batch.set(
          _deptRef(tid, d),
          {
            'membrosVinculadosCount': FieldValue.increment(1),
            'updatedAt': FieldValue.serverTimestamp(),
          },
          SetOptions(merge: true),
        );
        count += 2;
      }
      if (count > 0) await batch.commit();
    }

    for (final did in removed) {
      final d = did.trim();
      if (d.isEmpty) continue;
      await removeMemberFromFutureSchedulesOfDepartment(
        tenantId: tid,
        departmentId: d,
        memberData: memberData,
      );
    }
  }

  /// Vincula membro ao departamento: [DEPARTAMENTOS], [departamentosIds], subcoleção e contador.
  static Future<void> linkMember({
    required String tenantId,
    required String departmentId,
    required String memberDocId,
    required Map<String, dynamic> memberData,
  }) async {
    final tid = tenantId.trim();
    final did = departmentId.trim();
    final mid = memberDocId.trim();
    if (tid.isEmpty || did.isEmpty || mid.isEmpty) return;

    final batch = FirebaseFirestore.instance.batch();
    batch.set(
      _memberRef(tid, mid),
      {
        'DEPARTAMENTOS': FieldValue.arrayUnion([did]),
        'departamentosIds': FieldValue.arrayUnion([did]),
        'DEPARTAMENTOS_ATUALIZADO_EM': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
    batch.set(
      _linkedRef(tid, did, mid),
      _linkedMemberSnapshot(mid, memberData),
      SetOptions(merge: true),
    );
    batch.set(
      _deptRef(tid, did),
      {
        'membrosVinculadosCount': FieldValue.increment(1),
        'updatedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
    await batch.commit();
  }

  /// Só subcoleção + contador + escalas futuras (o doc do membro já foi atualizado em outro write).
  static Future<void> removeLinkedDocDecrementAndSchedules({
    required String tenantId,
    required String departmentId,
    required String memberDocId,
    required Map<String, dynamic> memberData,
  }) async {
    final tid = tenantId.trim();
    final did = departmentId.trim();
    final mid = memberDocId.trim();
    if (tid.isEmpty || did.isEmpty || mid.isEmpty) return;
    final batch = FirebaseFirestore.instance.batch();
    batch.delete(_linkedRef(tid, did, mid));
    batch.set(
      _deptRef(tid, did),
      {
        'membrosVinculadosCount': FieldValue.increment(-1),
        'updatedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
    await batch.commit();
    await removeMemberFromFutureSchedulesOfDepartment(
      tenantId: tid,
      departmentId: did,
      memberData: memberData,
    );
  }

  /// Só subcoleção + contador (membro já tem o array atualizado).
  static Future<void> addLinkedDocIncrement({
    required String tenantId,
    required String departmentId,
    required String memberDocId,
    required Map<String, dynamic> memberData,
  }) async {
    final tid = tenantId.trim();
    final did = departmentId.trim();
    final mid = memberDocId.trim();
    if (tid.isEmpty || did.isEmpty || mid.isEmpty) return;
    final batch = FirebaseFirestore.instance.batch();
    batch.set(
      _linkedRef(tid, did, mid),
      _linkedMemberSnapshot(mid, memberData),
      SetOptions(merge: true),
    );
    batch.set(
      _deptRef(tid, did),
      {
        'membrosVinculadosCount': FieldValue.increment(1),
        'updatedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
    await batch.commit();
  }

  /// Remove vínculo e retira o membro das escalas **futuras** daquele departamento.
  static Future<void> unlinkMember({
    required String tenantId,
    required String departmentId,
    required String memberDocId,
    required Map<String, dynamic> memberData,
  }) async {
    final tid = tenantId.trim();
    final did = departmentId.trim();
    final mid = memberDocId.trim();
    if (tid.isEmpty || did.isEmpty || mid.isEmpty) return;

    final batch = FirebaseFirestore.instance.batch();
    batch.set(
      _memberRef(tid, mid),
      {
        'DEPARTAMENTOS': FieldValue.arrayRemove([did]),
        'departamentosIds': FieldValue.arrayRemove([did]),
        'DEPARTAMENTOS_ATUALIZADO_EM': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
    batch.delete(_linkedRef(tid, did, mid));
    batch.set(
      _deptRef(tid, did),
      {
        'membrosVinculadosCount': FieldValue.increment(-1),
        'updatedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
    await batch.commit();

    await removeMemberFromFutureSchedulesOfDepartment(
      tenantId: tid,
      departmentId: did,
      memberData: memberData,
    );
  }

  static Set<String> _cpfKeysForMember(Map<String, dynamic> memberData) {
    final out = <String>{};
    final c = _normCpf((memberData['CPF'] ?? memberData['cpf'] ?? '').toString());
    if (c.isNotEmpty) {
      out.add(c);
      if (c.length == 11) {
        out.add(
            '${c.substring(0, 3)}.${c.substring(3, 6)}.${c.substring(6, 9)}-${c.substring(9)}');
      }
    }
    return out;
  }

  static bool _rowMatchesMember(
    String rawCpfInEscala,
    Set<String> keys,
  ) {
    final n = _normCpf(rawCpfInEscala);
    if (keys.contains(rawCpfInEscala.trim())) return true;
    if (n.isNotEmpty && keys.contains(n)) return true;
    return false;
  }

  /// Remove o CPF do membro das escalas com `date` ≥ hoje e `departmentId` igual.
  static Future<void> removeMemberFromFutureSchedulesOfDepartment({
    required String tenantId,
    required String departmentId,
    required Map<String, dynamic> memberData,
  }) async {
    final tid = tenantId.trim();
    final did = departmentId.trim();
    if (tid.isEmpty || did.isEmpty) return;

    final keys = _cpfKeysForMember(memberData);
    if (keys.isEmpty) return;

    final now = DateTime.now();
    final startOfToday = DateTime(now.year, now.month, now.day);

    final snap = await FirebaseFirestore.instance
        .collection('igrejas')
        .doc(tid)
        .collection('escalas')
        .where('departmentId', isEqualTo: did)
        .limit(400)
        .get();

    WriteBatch? batch;
    var ops = 0;

    Future<void> commitIfNeeded() async {
      if (batch != null && ops > 0) {
        await batch!.commit();
        batch = null;
        ops = 0;
      }
    }

    for (final esc in snap.docs) {
      DateTime? dt;
      try {
        dt = (esc.data()['date'] as Timestamp?)?.toDate();
      } catch (_) {}
      if (dt == null || dt.isBefore(startOfToday)) continue;

      final cpfs = ((esc.data()['memberCpfs'] as List?) ?? [])
          .map((e) => e.toString())
          .toList();
      final names = ((esc.data()['memberNames'] as List?) ?? [])
          .map((e) => e.toString())
          .toList();

      var changed = false;
      final newCpfs = <String>[];
      final newNames = <String>[];
      for (var i = 0; i < cpfs.length; i++) {
        if (_rowMatchesMember(cpfs[i], keys)) {
          changed = true;
          continue;
        }
        newCpfs.add(cpfs[i]);
        newNames.add(i < names.length ? names[i] : '');
      }
      if (!changed) continue;

      batch ??= FirebaseFirestore.instance.batch();
      batch!.update(esc.reference, {
        'memberCpfs': newCpfs,
        'memberNames': newNames,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      ops++;
      if (ops >= 450) {
        await batch!.commit();
        batch = null;
        ops = 0;
      }
    }
    await commitIfNeeded();
  }

  /// IDs de departamentos em que o CPF é líder ([leaderCpfs] ou legado [leaderCpf]/[viceLeaderCpf]).
  static Future<Set<String>> managedDepartmentIdsForCpf({
    required String tenantId,
    required String cpfDigits,
  }) async {
    final my = _normCpf(cpfDigits);
    if (my.length < 11) return {};
    final snap = await FirebaseFirestore.instance
        .collection('igrejas')
        .doc(tenantId.trim())
        .collection('departamentos')
        .get();
    final out = <String>{};
    for (final d in snap.docs) {
      if (ChurchDepartmentLeaders.memberIsLeaderOfDepartment(d.data(), my)) {
        out.add(d.id);
      }
    }
    return out;
  }

  /// Apaga documentos em `membros_vinculados` antes de excluir o departamento.
  static Future<void> deleteAllLinkedMembersDocs({
    required String tenantId,
    required String departmentId,
  }) async {
    final col = FirebaseFirestore.instance
        .collection('igrejas')
        .doc(tenantId.trim())
        .collection('departamentos')
        .doc(departmentId.trim())
        .collection('membros_vinculados');
    final snap = await col.limit(500).get();
    var batch = FirebaseFirestore.instance.batch();
    var n = 0;
    for (final d in snap.docs) {
      batch.delete(d.reference);
      n++;
      if (n >= 450) {
        await batch.commit();
        batch = FirebaseFirestore.instance.batch();
        n = 0;
      }
    }
    if (n > 0) await batch.commit();
  }
}
