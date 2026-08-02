import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:gestao_yahweh/data/financial_tips_firestore_seed_bank.dart';
import 'package:gestao_yahweh/utils/insights_engine.dart';

/// Importa o banco diversificado de dicas para `financial_tips` (admin).
class FinancialTipsSeedService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  /// Grava dicas com ID fixo. Se [skipExisting], ignora documentos que já existem;
  /// se false, sobrescreve os IDs do banco (modo «Substituir existentes»).
  Future<FinancialTipsSeedResult> seedDiversifiedBank({
    bool skipExisting = true,
  }) async {
    final col = _db.collection(InsightsEngine.kFinancialTipsCollection);
    var created = 0;
    var skipped = 0;
    var updated = 0;

    WriteBatch? batch;
    var opsInBatch = 0;

    Future<void> flush() async {
      if (batch != null && opsInBatch > 0) {
        await batch!.commit();
        batch = null;
        opsInBatch = 0;
      }
    }

    for (final seed in kFinancialTipsFirestoreSeedBank) {
      final ref = col.doc(seed.docId);
      final existing = await ref.get();
      if (skipExisting && existing.exists) {
        skipped++;
        continue;
      }
      if (!skipExisting && existing.exists) {
        updated++;
      } else {
        created++;
      }

      batch ??= _db.batch();
      batch!.set(
        ref,
        {
          ...seed.toFirestorePayload(),
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: false),
      );
      opsInBatch++;

      if (opsInBatch >= 400) {
        await flush();
      }
    }

    await flush();

    InsightsEngine.clearTipsCache();

    return FinancialTipsSeedResult(
      created: created,
      skipped: skipped,
      updated: updated,
      totalInBank: kFinancialTipsFirestoreSeedBank.length,
    );
  }
}

class FinancialTipsSeedResult {
  final int created;
  final int skipped;
  final int updated;
  final int totalInBank;

  const FinancialTipsSeedResult({
    required this.created,
    required this.skipped,
    required this.updated,
    required this.totalInBank,
  });
}
