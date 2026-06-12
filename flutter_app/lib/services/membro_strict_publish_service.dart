import 'dart:typed_data';

import 'package:gestao_yahweh/core/yahweh_flow_log.dart';
import 'package:gestao_yahweh/services/member_profile_photo_save_service.dart';
import 'package:gestao_yahweh/services/member_profile_photo_update_service.dart';
import 'package:gestao_yahweh/services/membro_publish_verification_service.dart';

/// Foto de perfil — fachada com logs → [MemberProfilePhotoSaveService].
abstract final class MembroStrictPublishService {
  MembroStrictPublishService._();

  static Future<MemberProfilePhotoUpdateResult> publishPhoto({
    required String seedTenantId,
    required String memberDocId,
    required Map<String, dynamic> memberData,
    required Uint8List rawBytes,
    String? userUid,
    bool requireAuth = true,
    void Function(String phaseLabel)? onPhase,
  }) async {
    final igrejaId = await MembroPublishVerificationService.resolveTenantForPublish(
      seedTenantId: seedTenantId,
      userUid: userUid,
    );

    await MembroPublishVerificationService.logPublishPhase(
      phase: 'before',
      igrejaId: igrejaId,
      memberDocId: memberDocId,
    );

    try {
      final result = await MemberProfilePhotoSaveService.saveInternal(
        tenantId: igrejaId,
        memberDocId: memberDocId,
        memberData: memberData,
        rawBytes: rawBytes,
        onPhase: onPhase,
        requireAuth: requireAuth,
      );

      await MembroPublishVerificationService.logPublishPhase(
        phase: 'after',
        igrejaId: igrejaId,
        memberDocId: memberDocId,
        storagePath: result.storagePath,
      );

      return result;
    } catch (e, st) {
      YahwehFlowLog.error('MEMBROS', e, st);
      rethrow;
    }
  }
}
