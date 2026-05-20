import 'package:flutter/foundation.dart';

/// Aviso global quando a foto de perfil muda (chat ou módulo Membros).
class MemberProfilePhotoSyncNotifier extends ChangeNotifier {
  MemberProfilePhotoSyncNotifier._();

  static final MemberProfilePhotoSyncNotifier instance =
      MemberProfilePhotoSyncNotifier._();

  String? lastTenantId;
  String? lastAuthUid;
  int lastCacheRevision = 0;

  void notifyPhotoUpdated({
    required String tenantId,
    required String authUid,
    required int cacheRevision,
  }) {
    lastTenantId = tenantId.trim();
    lastAuthUid = authUid.trim();
    lastCacheRevision = cacheRevision;
    notifyListeners();
  }
}
