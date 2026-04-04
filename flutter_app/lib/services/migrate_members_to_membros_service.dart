import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Migração automatizada: copia documentos de igrejas/{tenantId}/members para igrejas/{tenantId}/membros.
/// Executa uma vez por tenant (flag em SharedPreferences). Merge por doc id para não sobrescrever dados já em membros.
class MigrateMembersToMembrosService {
  MigrateMembersToMembrosService._();
  static final MigrateMembersToMembrosService instance = MigrateMembersToMembrosService._();

  static const _prefKeyPrefix = 'migrate_members_to_membros_done_';
  static const int _batchSize = 100;

  final FirebaseFirestore _db = FirebaseFirestore.instance;

  /// Retorna true se a migração já foi executada para este tenant.
  Future<bool> hasMigrationDone(String tenantId) async {
    if (tenantId.isEmpty) return true;
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_prefKeyPrefix + tenantId) ?? false;
  }

  /// Marca a migração como concluída para este tenant.
  Future<void> _setMigrationDone(String tenantId) async {
    if (tenantId.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefKeyPrefix + tenantId, true);
  }

  /// Migra documentos de igrejas/[tenantId]/members para igrejas/[tenantId]/membros.
  /// Usa merge para não apagar campos já existentes em membros. Retorna quantidade migrada.
  /// Se não existir subcoleção members ou estiver vazia, retorna 0 e marca como feito.
  Future<int> migrateTenant(String tenantId) async {
    if (tenantId.isEmpty) return 0;
    try {
      final membersRef = _db.collection('igrejas').doc(tenantId).collection('members');
      final membrosRef = _db.collection('igrejas').doc(tenantId).collection('membros');
      var totalMigrated = 0;
      DocumentSnapshot<Map<String, dynamic>>? lastDoc;
      while (true) {
        var q = membersRef.orderBy(FieldPath.documentId).limit(_batchSize);
        if (lastDoc != null) {
          q = membersRef.orderBy(FieldPath.documentId).startAfterDocument(lastDoc).limit(_batchSize);
        }
        final snap = await q.get();
        if (snap.docs.isEmpty) break;
        final batch = _db.batch();
        for (final d in snap.docs) {
          final data = d.data();
          batch.set(membrosRef.doc(d.id), data, SetOptions(merge: true));
          totalMigrated++;
        }
        await batch.commit();
        lastDoc = snap.docs.last;
        if (snap.docs.length < _batchSize) break;
      }
      await _setMigrationDone(tenantId);
      return totalMigrated;
    } catch (_) {
      return 0;
    }
  }

  /// Executa a migração apenas se ainda não foi feita para este tenant. Retorna quantidade migrada (0 se já feita ou erro).
  Future<int> runIfNeeded(String tenantId) async {
    if (tenantId.isEmpty) return 0;
    final done = await hasMigrationDone(tenantId);
    if (done) return 0;
    return migrateTenant(tenantId);
  }
}
