import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show debugPrint, kDebugMode;
import 'package:gestao_yahweh/core/repositories/church_repository.dart';
import 'package:gestao_yahweh/services/church_certificados_load_service.dart';
import 'package:gestao_yahweh/services/membro_strict_update_service.dart';
import 'package:gestao_yahweh/services/members_directory_snapshot_service.dart';
import 'package:gestao_yahweh/ui/widgets/member_display_name_utils.dart';

/// Remove fichas `membros` sem nome válido (stubs / importações incompletas).
abstract final class MemberNamelessPurgeService {
  MemberNamelessPurgeService._();

  static final Set<String> _purgedChurchIds = {};

  static bool alreadyPurgedThisSession(String churchId) =>
      _purgedChurchIds.contains(churchId.trim());

  /// Uma vez por sessão e igreja — só gestores (caller valida papel).
  static Future<int> purgeNamelessMembersOnce({
    required String seedTenantId,
    int limit = 120,
  }) async {
    final churchId = ChurchRepository.churchId(seedTenantId.trim());
    if (churchId.isEmpty) return 0;
    if (_purgedChurchIds.contains(churchId)) return 0;
    _purgedChurchIds.add(churchId);

    try {
      final snap = await ChurchUiCollections.membros(churchId)
          .limit(limit.clamp(20, ChurchCertificadosLoadService.kAllMembersLimit))
          .get();
      final toDelete = <QueryDocumentSnapshot<Map<String, dynamic>>>[];
      for (final d in snap.docs) {
        if (!memberDataHasValidName(d.data())) {
          toDelete.add(d);
        }
      }
      if (toDelete.isEmpty) return 0;

      var removed = 0;
      for (final d in toDelete) {
        try {
          await MembroStrictUpdateService.purgeMemberCompletely(
            seedTenantId: churchId,
            memberDocId: d.id,
            memberData: d.data(),
          );
          removed++;
        } catch (e, st) {
          if (kDebugMode) {
            debugPrint('MemberNamelessPurge ${d.id}: $e\n$st');
          }
        }
      }

      if (removed > 0) {
        ChurchCertificadosLoadService.invalidate(churchId);
        MembersDirectorySnapshotService.invalidateMemory(churchId);
        if (kDebugMode) {
          debugPrint(
            'MemberNamelessPurge: $removed ficha(s) sem nome em $churchId',
          );
        }
      }
      return removed;
    } catch (e, st) {
      if (kDebugMode) debugPrint('MemberNamelessPurgeService: $e\n$st');
      return 0;
    }
  }
}
