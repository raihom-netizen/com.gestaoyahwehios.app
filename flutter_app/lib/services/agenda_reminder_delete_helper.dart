import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:gestao_yahweh/models/scale_entry.dart';

/// Cor padrão de compromisso particular na Agenda/Escalas.
const String kAgendaCompromissoDefaultColor = '#12B5A5';

Future<void> deleteAudienciaStorageForReminder({
  required String userDocId,
  required String reminderDocId,
}) async {}

/// Helpers de exclusão de lembretes da Agenda (stub mínimo).
abstract final class AgendaReminderDeleteHelper {
  AgendaReminderDeleteHelper._();
}
