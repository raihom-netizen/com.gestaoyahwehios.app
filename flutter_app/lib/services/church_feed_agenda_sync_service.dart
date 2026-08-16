import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:gestao_yahweh/core/firebase_bootstrap.dart';
import 'package:gestao_yahweh/services/church_operational_paths.dart';
import 'package:gestao_yahweh/utils/firestore_web_guard.dart';
import 'package:gestao_yahweh/core/data/yahweh_write_batch.dart';

/// Sincroniza evento publicado com a coleção `agenda` (calendário colorido).
abstract final class ChurchFeedAgendaSyncService {
  ChurchFeedAgendaSyncService._();

  static Future<void> upsertForEvento({
    required String tenantId,
    required String eventoId,
    required String title,
    required String description,
    required DateTime startAt,
    DateTime? endAt,
    String? location,
    String category = 'evento_social',
    String colorHex = '#E11D48',
  }) async {
    final tid = tenantId.trim();
    final eid = eventoId.trim();
    if (tid.isEmpty || eid.isEmpty) return;

    await ensureFirebaseReadyForPublishUpload();
    if (kIsWeb) {
      await FirestoreWebGuard.prepareForPublishWrite().catchError((_) {});
    }

    final agendaCol = ChurchOperationalPaths.churchDoc(
      tid,
    ).collection('agenda');
    final existing = await FirestoreWebGuard.runWithWebRecovery(
      () => agendaCol.where('noticiaId', isEqualTo: eid).limit(10).get(),
      maxAttempts: kIsWeb ? 3 : 2,
    );

    final end = endAt ?? startAt.add(const Duration(hours: 2));
    final payload = <String, dynamic>{
      'title': title.trim(),
      'description': description.trim(),
      'startTime': Timestamp.fromDate(startAt),
      'endTime': Timestamp.fromDate(end),
      'noticiaId': eid,
      'category': category,
      'color': colorHex,
      'location': location?.trim() ?? '',
      'type': 'evento',
      'updatedAt': FieldValue.serverTimestamp(),
    };

    final batch = YahwehBatch();
    if (existing.docs.isEmpty) {
      payload['createdAt'] = YahwehFv.serverTimestamp;
      payload['createdByUid'] = firebaseDefaultAuth.currentUser?.uid ?? '';
      batch.set(agendaCol.doc('evento_'), payload);
    } else {
      batch.set(
        existing.docs.first.reference,
        payload,
        merge: true,
      );
      for (final duplicate in existing.docs.skip(1)) {
        batch.deleteDoc(duplicate.reference);
      }
    }
    await FirestoreWebGuard.runWithWebRecovery(
      () => batch.commit(),
      maxAttempts: kIsWeb ? 4 : 2,
    );
  }

  static Future<void> deleteForEvento({
    required String tenantId,
    required String eventoId,
  }) async {
    final tid = tenantId.trim();
    final eid = eventoId.trim();
    if (tid.isEmpty || eid.isEmpty) return;
    final agendaCol = ChurchOperationalPaths.churchDoc(
      tid,
    ).collection('agenda');
    final existing = await FirestoreWebGuard.runWithWebRecovery(
      () => agendaCol.where('noticiaId', isEqualTo: eid).limit(20).get(),
      maxAttempts: kIsWeb ? 3 : 2,
    );
    if (existing.docs.isEmpty) return;
    final batch = YahwehBatch();
    for (final doc in existing.docs) {
      batch.deleteDoc(doc.reference);
    }
    await FirestoreWebGuard.runWithWebRecovery(
      () => batch.commit(),
      maxAttempts: kIsWeb ? 4 : 2,
    );
  }

  static Future<void> deleteForAviso({
    required String tenantId,
    required String avisoId,
  }) async {
    final tid = tenantId.trim();
    final aid = avisoId.trim();
    if (tid.isEmpty || aid.isEmpty) return;

    final agendaCol = ChurchOperationalPaths.churchDoc(
      tid,
    ).collection('agenda');
    final existing = await FirestoreWebGuard.runWithWebRecovery(
      () => agendaCol.where('avisoId', isEqualTo: aid).limit(20).get(),
      maxAttempts: kIsWeb ? 3 : 2,
    );
    if (existing.docs.isEmpty) return;

    final batch = YahwehBatch();
    for (final doc in existing.docs) {
      batch.deleteDoc(doc.reference);
    }
    await FirestoreWebGuard.runWithWebRecovery(
      () => batch.commit(),
      maxAttempts: kIsWeb ? 4 : 2,
    );
  }

  static Future<void> upsertForAviso({
    required String tenantId,
    required String avisoId,
    required String title,
    required String description,
    required DateTime referenceDate,
    String colorHex = '#2563EB',
  }) async {
    final tid = tenantId.trim();
    final aid = avisoId.trim();
    if (tid.isEmpty || aid.isEmpty) return;

    await ensureFirebaseReadyForPublishUpload();

    final agendaCol = ChurchOperationalPaths.churchDoc(
      tid,
    ).collection('agenda');
    final existing = await agendaCol
        .where('avisoId', isEqualTo: aid)
        .limit(10)
        .get();

    final start = DateTime(
      referenceDate.year,
      referenceDate.month,
      referenceDate.day,
    );
    final end = start.add(const Duration(days: 1));
    final payload = <String, dynamic>{
      'title': title.trim(),
      'description': description.trim(),
      'startTime': Timestamp.fromDate(start),
      'endTime': Timestamp.fromDate(end),
      'avisoId': aid,
      'category': 'aviso',
      'color': colorHex,
      'type': 'aviso',
      'updatedAt': FieldValue.serverTimestamp(),
    };

    final batch = YahwehBatch();
    if (existing.docs.isEmpty) {
      payload['createdAt'] = YahwehFv.serverTimestamp;
      payload['createdByUid'] = firebaseDefaultAuth.currentUser?.uid ?? '';
      batch.set(agendaCol.doc('aviso_'), payload);
    } else {
      batch.set(
        existing.docs.first.reference,
        payload,
        merge: true,
      );
      for (final duplicate in existing.docs.skip(1)) {
        batch.deleteDoc(duplicate.reference);
      }
    }
    await batch.commit();
  }
}
