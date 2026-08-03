import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:gestao_yahweh/core/data/church_ui_collections.dart';

/// Lista principal do Financeiro com menos tráfego: consulta só com [where] em
/// [date], [type] e [status] (sem pesquisa livre, sem categoria, sem conta).
bool financeMainPeriodCanServerPage({
  required String searchLowerTrim,
  required String statusFilter,
  required String? categoryFilter,
  required String? financeAccountFilterId,
}) {
  if (searchLowerTrim.isNotEmpty) return false;
  final cat = categoryFilter?.trim() ?? '';
  if (cat.isNotEmpty) return false;
  final acc = financeAccountFilterId?.trim() ?? '';
  if (acc.isNotEmpty) return false;
  return statusFilter == 'all' ||
      statusFilter == 'pending' ||
      statusFilter == 'paid';
}

bool financeIsMissingIndexError(Object error) {
  final s = error.toString().toLowerCase();
  if (s.contains('failed-precondition') && s.contains('index')) return true;
  if (s.contains('requires an index')) return true;
  if (error is FirebaseException) {
    return error.code == 'failed-precondition' &&
        (error.message ?? '').toLowerCase().contains('index');
  }
  return false;
}

/// Query alinhada aos índices `transactions`.
///
/// Ordem obrigatória Firestore: igualdades (`status`/`type`) **antes** do
/// intervalo em `date`, depois `orderBy('date')`.
Query<Map<String, dynamic>> financeMainPeriodFirestoreQuery({
  required String sessionUid,
  required DateTime from,
  required DateTime to,
  required String statusFilter,
  required String typeFilter,
  bool omitStatusFilter = false,
  bool omitTypeFilter = false,
}) {
  // `sessionUid` aqui é o churchId — Financeiro é por igreja, não por login.
  final col = ChurchUiCollections.financeiro(sessionUid);
  final start = Timestamp.fromDate(DateTime(from.year, from.month, from.day));
  final end =
      Timestamp.fromDate(DateTime(to.year, to.month, to.day, 23, 59, 59));

  Query<Map<String, dynamic>> q = col;

  // 1) Igualdades primeiro (índices status+date / type+date / type+status+date).
  if (!omitStatusFilter) {
    if (statusFilter == 'pending') {
      q = q.where('status', isEqualTo: 'pending');
    } else if (statusFilter == 'paid') {
      q = q.where('status', isEqualTo: 'paid');
    }
  }
  if (!omitTypeFilter) {
    if (typeFilter == 'income') {
      q = q.where('type', isEqualTo: 'income');
    } else if (typeFilter == 'expense') {
      q = q.where('type', isEqualTo: 'expense');
    }
  }

  // 2) Intervalo + orderBy no mesmo campo.
  return q
      .where('date', isGreaterThanOrEqualTo: start)
      .where('date', isLessThanOrEqualTo: end)
      .orderBy('date', descending: false);
}
