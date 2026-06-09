import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:gestao_yahweh/core/firebase_bootstrap.dart';
import 'package:gestao_yahweh/services/church_operational_paths.dart';

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

    final agendaCol =
        ChurchOperationalPaths.churchDoc(tid).collection('agenda');
    final existing =
        await agendaCol.where('noticiaId', isEqualTo: eid).limit(10).get();

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

    final batch = firebaseDefaultFirestore.batch();
    if (existing.docs.isEmpty) {
      payload['createdAt'] = FieldValue.serverTimestamp();
      payload['createdByUid'] = firebaseDefaultAuth.currentUser?.uid ?? '';
      batch.set(agendaCol.doc(), payload);
    } else {
      for (final d in existing.docs) {
        batch.set(d.reference, payload, SetOptions(merge: true));
      }
    }
    await batch.commit();
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

    final agendaCol =
        ChurchOperationalPaths.churchDoc(tid).collection('agenda');
    final existing =
        await agendaCol.where('avisoId', isEqualTo: aid).limit(10).get();

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

    final batch = firebaseDefaultFirestore.batch();
    if (existing.docs.isEmpty) {
      payload['createdAt'] = FieldValue.serverTimestamp();
      payload['createdByUid'] = firebaseDefaultAuth.currentUser?.uid ?? '';
      batch.set(agendaCol.doc(), payload);
    } else {
      for (final d in existing.docs) {
        batch.set(d.reference, payload, SetOptions(merge: true));
      }
    }
    await batch.commit();
  }
}
