import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show kDebugMode;

/// Código de membro sequencial **por igreja** (cartão CNH, QR, relatórios).
///
/// Formato: `AAAA` + `NNNNN` (ex.: `202600001`) — reinicia a sequência a cada ano civil.
abstract final class MemberCodigoService {
  MemberCodigoService._();

  static const _configDocId = 'codigo_membro';
  static const _seqPad = 5;

  static DocumentReference<Map<String, dynamic>> _configRef(String tenantId) =>
      FirebaseFirestore.instance
          .collection('igrejas')
          .doc(tenantId.trim())
          .collection('config')
          .doc(_configDocId);

  static CollectionReference<Map<String, dynamic>> _membersCol(String tenantId) =>
      FirebaseFirestore.instance
          .collection('igrejas')
          .doc(tenantId.trim())
          .collection('membros');

  /// Lê o código gravado no documento do membro (vários aliases legados).
  static String readFromMember(Map<String, dynamic> data) {
    for (final k in [
      'codigoMembro',
      'COD_MEMBRO',
      'codigo_membro',
      'numeroMembro',
      'NUMERO_MEMBRO',
    ]) {
      final v = (data[k] ?? '').toString().trim();
      if (v.isNotEmpty) return v;
    }
    return '';
  }

  static Map<String, dynamic> fieldsForFirestore(String code) {
    final c = code.trim();
    return {
      'codigoMembro': c,
      'COD_MEMBRO': c,
      'codigo_membro': c,
      'codigoMembroAtribuidoEm': FieldValue.serverTimestamp(),
    };
  }

  static Future<bool> _isCodeTaken(String tenantId, String code) async {
    final c = code.trim();
    if (c.isEmpty) return false;
    final col = _membersCol(tenantId);
    for (final field in ['codigoMembro', 'COD_MEMBRO', 'codigo_membro']) {
      final snap = await col.where(field, isEqualTo: c).limit(1).get();
      if (snap.docs.isNotEmpty) return true;
    }
    return false;
  }

  /// Próximo código da igreja (transação atómica em `config/codigo_membro`).
  static Future<String> allocateNext(String tenantId) async {
    final tid = tenantId.trim();
    if (tid.isEmpty) {
      throw ArgumentError('tenantId vazio');
    }
    final db = FirebaseFirestore.instance;
    final cfgRef = _configRef(tid);
    final yearNow = DateTime.now().year;

    for (var attempt = 0; attempt < 8; attempt++) {
      final code = await db.runTransaction<String>((tx) async {
        final snap = await tx.get(cfgRef);
        final data = snap.data() ?? {};
        var year = (data['year'] is num)
            ? (data['year'] as num).toInt()
            : yearNow;
        var next = (data['nextSequence'] is num)
            ? (data['nextSequence'] as num).toInt()
            : 1;
        if (year != yearNow) {
          year = yearNow;
          next = 1;
        }
        final candidate = '$year${next.toString().padLeft(_seqPad, '0')}';
        tx.set(
          cfgRef,
          {
            'year': year,
            'nextSequence': next + 1,
            'updatedAt': FieldValue.serverTimestamp(),
          },
          SetOptions(merge: true),
        );
        return candidate;
      });

      if (!await _isCodeTaken(tid, code)) return code;
      if (kDebugMode) {
        // ignore: avoid_print
        print('MemberCodigoService: colisão $code, nova tentativa…');
      }
    }
    throw StateError(
      'Não foi possível gerar um código de membro único. Tente novamente.',
    );
  }

  /// Garante código no documento; devolve o código final (existente ou novo).
  static Future<String> ensureForMember({
    required String tenantId,
    required String memberId,
    Map<String, dynamic>? memberData,
    bool forceNew = false,
  }) async {
    final tid = tenantId.trim();
    final mid = memberId.trim();
    if (tid.isEmpty || mid.isEmpty) {
      throw ArgumentError('tenantId e memberId são obrigatórios');
    }

    Map<String, dynamic> data = memberData ?? {};
    if (data.isEmpty) {
      final snap = await _membersCol(tid).doc(mid).get();
      data = snap.data() ?? {};
    }

    if (!forceNew) {
      final existing = readFromMember(data);
      if (existing.isNotEmpty) return existing;
    }

    final code = await allocateNext(tid);
    await _membersCol(tid).doc(mid).set(
      fieldsForFirestore(code),
      SetOptions(merge: true),
    );
    return code;
  }

  /// Atribui códigos a membros da igreja que ainda não têm (até [limit] por chamada).
  static Future<({int assigned, int skipped, int errors})> backfillMissing({
    required String tenantId,
    int limit = 80,
  }) async {
    final tid = tenantId.trim();
    if (tid.isEmpty) return (assigned: 0, skipped: 0, errors: 0);

    final snap = await _membersCol(tid).limit(limit.clamp(20, 500)).get();
    var assigned = 0;
    var skipped = 0;
    var errors = 0;

    for (final doc in snap.docs) {
      if (readFromMember(doc.data()).isNotEmpty) {
        skipped++;
        continue;
      }
      try {
        await ensureForMember(
          tenantId: tid,
          memberId: doc.id,
          memberData: doc.data(),
        );
        assigned++;
      } catch (_) {
        errors++;
      }
    }
    return (assigned: assigned, skipped: skipped, errors: errors);
  }
}
