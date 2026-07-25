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
  /// URL bustada (com `?v=cb…`) para merge imediato na UI sem esperar directory/Firestore.
  String? lastPhotoUrl;
  String? lastPhotoThumbUrl;
  String? lastStoragePath;

  void notifyPhotoUpdated({
    required String tenantId,
    required String authUid,
    required int cacheRevision,
    String? memberDocId,
    String? photoUrl,
    String? photoThumbUrl,
    String? storagePath,
  }) {
    lastTenantId = tenantId.trim();
    lastAuthUid = authUid.trim();
    final mid = (memberDocId ?? '').trim();
    lastMemberDocId = mid.isEmpty ? null : mid;
    lastCacheRevision = cacheRevision;
    final url = (photoUrl ?? '').trim();
    lastPhotoUrl = url.isEmpty ? null : url;
    final thumb = (photoThumbUrl ?? '').trim();
    lastPhotoThumbUrl = thumb.isEmpty ? null : thumb;
    final sp = (storagePath ?? '').trim();
    lastStoragePath = sp.isEmpty ? null : sp;
    notifyListeners();
  }
}
