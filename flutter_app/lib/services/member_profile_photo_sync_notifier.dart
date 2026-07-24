import 'package:flutter/foundation.dart';

/// Aviso global quando a foto de perfil muda (chat ou módulo Membros).
class MemberProfilePhotoSyncNotifier extends ChangeNotifier {
  MemberProfilePhotoSyncNotifier._();

  static final MemberProfilePhotoSyncNotifier instance =
      MemberProfilePhotoSyncNotifier._();

  String? lastTenantId;
  String? lastAuthUid;
  /// Doc `membros/{id}` — cartão/certificados/painel podem não ter authUid no mapa.
  String? lastMemberDocId;
  int lastCacheRevision = 0;

  void notifyPhotoUpdated({
    required String tenantId,
    required String authUid,
    required int cacheRevision,
    String? memberDocId,
  }) {
    lastTenantId = tenantId.trim();
    lastAuthUid = authUid.trim();
    final mid = (memberDocId ?? '').trim();
    lastMemberDocId = mid.isEmpty ? null : mid;
    lastCacheRevision = cacheRevision;
    notifyListeners();
  }
}
