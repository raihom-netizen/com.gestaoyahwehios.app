import 'package:gestao_yahweh/core/data/yahweh_write_batch.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'agenda_reminder_delete_helper.dart';
import 'package:gestao_yahweh/core/data/yahweh_doc_write.dart';

enum AgendaMirrorType { compromisso, audiencia, plantao }

/// Espelho Agenda → calendário Escalas (`users/{uid}/scales/agenda_{id}`).
abstract final class AgendaScaleMirrorService {
  AgendaScaleMirrorService._();

  static String _scaleDocId(String agendaId) => 'agenda_$agendaId';

  static CollectionReference<Map<String, dynamic>> _scales(String uid) =>
      FirebaseFirestore.instance.collection('users').doc(uid).collection('scales');

  static Future<void> upsert({
    required String userDocId,
    required String agendaId,
    required AgendaMirrorType type,
    required String label,
    required DateTime date,
    required String startHHmm,
    required String endHHmm,
    String colorHex = kAgendaCompromissoDefaultColor,
    String notes = '',
    String linkLocalizacao = '',
    String contatoWhatsApp = '',
    bool createdByLancamentoExpresso = false,
  }) async {
    if (userDocId.isEmpty || agendaId.isEmpty) return;
    final ref = _scales(userDocId).doc(_scaleDocId(agendaId));
    await YahwehDocWrite.set(ref, {
      'type': type.name,
      'title': label,
      'date': Timestamp.fromDate(DateTime(date.year, date.month, date.day)),
      'startTime': startHHmm,
      'endTime': endHHmm,
      'colorHex': colorHex,
      'notes': notes,
      'linkLocalizacao': linkLocalizacao,
      'contatoWhatsApp': contatoWhatsApp,
      'isAgendaMirror': true,
      'agendaId': agendaId,
      'linkedReminderId': agendaId,
      'source': _scaleDocId(agendaId),
      'createdByLancamentoExpresso': createdByLancamentoExpresso,
      'updatedAt': YahwehFv.serverTimestamp,
    });
  }

  static Future<void> delete({
    required String userDocId,
    required String agendaId,
  }) async {
    if (userDocId.isEmpty || agendaId.isEmpty) return;
    try {
      await _scales(userDocId).doc(_scaleDocId(agendaId)).delete();
    } catch (_) {}
  }
}
