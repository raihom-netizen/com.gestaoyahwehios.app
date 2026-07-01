import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:gestao_yahweh/core/entity_publish_status.dart';
import 'package:gestao_yahweh/core/marketing_storage_layout.dart';
import 'package:gestao_yahweh/ui/widgets/safe_network_image.dart'
    show
        dedupeImageRefsByStorageIdentity,
        firebaseStorageObjectPathFromHttpUrl,
        isValidImageUrl,
        normalizeFirebaseStorageObjectPath,
        sanitizeImageUrl;

/// Referência canónica de mídia — Storage path + URL https (quando aplicável).
class ChurchCanonicalMediaRef {
  const ChurchCanonicalMediaRef({
    this.downloadUrl = '',
    this.storagePath = '',
    this.thumbDownloadUrl = '',
    this.thumbStoragePath = '',
    this.mimeType = '',
    this.fileName = '',
    this.slotIndex,
  });

  final String downloadUrl;
  final String storagePath;
  final String thumbDownloadUrl;
  final String thumbStoragePath;
  final String mimeType;
  final String fileName;
  final int? slotIndex;

  bool get hasStorage => storagePath.trim().isNotEmpty;
  bool get hasUrl => downloadUrl.trim().isNotEmpty;
  bool get isResolvable => hasStorage || hasUrl;

  /// Preferir path Storage; fallback URL https legada.
  String get primaryRef =>
      hasStorage ? storagePath.trim() : downloadUrl.trim();
}

/// Contrato único — leitura (painel + site) e escrita (publish) por módulo.
abstract final class ChurchCanonicalMediaContract {
  ChurchCanonicalMediaContract._();

  // ─── Chaves canónicas (documentação + grep) ─────────────────────────────

  static const chatStoragePathKeys = ['storagePath', 'storage_path'];
  static const chatThumbStoragePathKeys = [
    'thumbStoragePath',
    'thumb_storage_path',
  ];
  static const chatLegacyUrlKeys = ['mediaUrl', 'fileUrl', 'downloadURL'];

  static const financeUrlKeys = ['comprovanteUrl', 'comprovanteLink'];
  static const financeStoragePathKeys = ['comprovanteStoragePath'];

  static const patrimonioUrlSlotKeys = [
    'foto01',
    'foto02',
    'foto03',
    'foto04',
  ];
  static const patrimonioPathSlotKeys = [
    'foto01Path',
    'foto02Path',
    'foto03Path',
    'foto04Path',
  ];
  static const int patrimonioMaxPhotos = 4;

  static const patrimonioLegacyUrlKeys = [
    'fotoUrls',
    'fotos',
    'imageUrls',
    'imageUrl',
    'fotoUrl',
    'thumbnail',
  ];
  static const patrimonioLegacyPathKeys = [
    'fotoStoragePaths',
    'fotoPath',
    'imageStoragePath',
    'fotoPrincipalPath',
    'storagePath',
  ];

  static String _firstString(Map<String, dynamic>? data, List<String> keys) {
    if (data == null) return '';
    for (final k in keys) {
      final v = (data[k] ?? '').toString().trim();
      if (v.isNotEmpty) return v;
    }
    return '';
  }

  static String _normalizePath(String? raw) {
    final p = (raw ?? '').trim();
    if (p.isEmpty) return '';
    return normalizeFirebaseStorageObjectPath(p);
  }

  // ─── Leitura — Chat ───────────────────────────────────────────────────────

  static ChurchCanonicalMediaRef resolveChat(Map<String, dynamic> data) {
    final path = _normalizePath(
      _firstString(data, chatStoragePathKeys),
    );
    final thumbPath = _normalizePath(
      _firstString(data, chatThumbStoragePathKeys),
    );
    final legacyUrl = sanitizeImageUrl(
      _firstString(data, chatLegacyUrlKeys),
    );
    final legacyThumb = sanitizeImageUrl(
      _firstString(data, [
        'thumbnailUrl',
        'thumbUrl',
        'posterUrl',
      ]),
    );
    return ChurchCanonicalMediaRef(
      storagePath: path,
      thumbStoragePath: thumbPath,
      downloadUrl: legacyUrl,
      thumbDownloadUrl: legacyThumb,
      fileName: (data['fileName'] ?? '').toString().trim(),
      mimeType: (data['mimeType'] ?? data['contentType'] ?? '').toString().trim(),
    );
  }

  static String chatStoragePath(Map<String, dynamic> data) =>
      resolveChat(data).storagePath;

  static String chatThumbStoragePath(Map<String, dynamic> data) =>
      resolveChat(data).thumbStoragePath;

  static String chatLegacyMediaUrl(Map<String, dynamic> data) =>
      resolveChat(data).downloadUrl;

  static bool hasViewableChatMedia(Map<String, dynamic> data) {
    final ref = resolveChat(data);
    if (ref.hasStorage) return true;
    if (_chatUploadInProgress(data)) return false;
    return ref.hasUrl;
  }

  static bool _chatUploadInProgress(Map<String, dynamic> data) {
    if (data['uploadCompleted'] == true) return false;
    final ds = (data['status'] ?? data['deliveryStatus'] ?? '')
        .toString()
        .trim();
    if (ds == 'sent' || ds == 'delivered' || ds == 'read') return false;
    return ds == 'uploading' || ds == 'queued' || ds == 'sending';
  }

  // ─── Leitura — Financeiro ─────────────────────────────────────────────────

  static ChurchCanonicalMediaRef resolveFinanceComprovante(
    Map<String, dynamic>? data,
  ) {
    if (data == null) {
      return const ChurchCanonicalMediaRef();
    }
    final url = sanitizeImageUrl(_firstString(data, financeUrlKeys));
    final path = _normalizePath(
      _firstString(data, financeStoragePathKeys),
    );
    var fileName = (data['comprovanteFileName'] ?? '').toString().trim();
    if (fileName.isEmpty && path.contains('/')) {
      fileName = path.split('/').last;
    }
    if (fileName.isEmpty) fileName = 'Comprovante';
    final mime = (data['comprovanteMimeType'] ?? '').toString().trim();
    return ChurchCanonicalMediaRef(
      downloadUrl: url,
      storagePath: path,
      fileName: fileName,
      mimeType: mime.isNotEmpty ? mime : _mimeFromFileName(fileName),
    );
  }

  static bool hasViewableFinanceComprovante(Map<String, dynamic>? data) {
    if (data == null) return false;
    final ref = resolveFinanceComprovante(data);
    if (data['hasComprovante'] == true && ref.isResolvable) return true;
    return ref.isResolvable;
  }

  static String financeComprovanteViewUrl(Map<String, dynamic>? data) =>
      resolveFinanceComprovante(data).downloadUrl;

  static String financeComprovanteStoragePath(Map<String, dynamic>? data) =>
      resolveFinanceComprovante(data).storagePath;

  // ─── Leitura — Patrimônio ─────────────────────────────────────────────────

  static List<ChurchCanonicalMediaRef> resolvePatrimonioPhotos(
    Map<String, dynamic> data,
  ) {
    final slots = <ChurchCanonicalMediaRef>[];
    for (var i = 0; i < patrimonioMaxPhotos; i++) {
      final url = sanitizeImageUrl(
        (data[patrimonioUrlSlotKeys[i]] ?? '').toString(),
      );
      final path = _normalizePath(
        (data[patrimonioPathSlotKeys[i]] ?? '').toString(),
      );
      if (url.isNotEmpty || path.isNotEmpty) {
        slots.add(
          ChurchCanonicalMediaRef(
            downloadUrl: url,
            storagePath: path,
            slotIndex: i,
          ),
        );
      }
    }
    if (slots.isNotEmpty) return slots;

    final legacyUrls = patrimonioImageUrlsLegacy(data);
    final legacyPaths = patrimonioStoragePathsLegacy(data);
    final count = legacyUrls.length > legacyPaths.length
        ? legacyUrls.length
        : legacyPaths.length;
    for (var i = 0; i < count && i < patrimonioMaxPhotos; i++) {
      final u = i < legacyUrls.length ? legacyUrls[i] : '';
      final p = i < legacyPaths.length ? legacyPaths[i] : '';
      if (u.isNotEmpty || p.isNotEmpty) {
        slots.add(
          ChurchCanonicalMediaRef(
            downloadUrl: u,
            storagePath: p,
            slotIndex: i,
          ),
        );
      }
    }
    return slots;
  }

  static List<String> patrimonioImageUrls(Map<String, dynamic> data) {
    final refs = resolvePatrimonioPhotos(data);
    if (refs.isNotEmpty) {
      return dedupeImageRefsByStorageIdentity(
        refs.map(
          (r) => r.downloadUrl.isNotEmpty ? r.downloadUrl : r.storagePath,
        ),
      );
    }
    return dedupeImageRefsByStorageIdentity(patrimonioImageUrlsLegacy(data));
  }

  static List<String> patrimonioStoragePaths(Map<String, dynamic> data) {
    final fromSlots = resolvePatrimonioPhotos(data)
        .map((r) => r.storagePath)
        .where((p) => p.isNotEmpty)
        .toList();
    if (fromSlots.isNotEmpty) return fromSlots;
    return patrimonioStoragePathsLegacy(data);
  }

  static List<String> patrimonioImageUrlsLegacy(Map<String, dynamic> data) {
    final legacy = <String>[];
    void push(String raw) {
      final s = sanitizeImageUrl(raw);
      if (s.isNotEmpty && !legacy.contains(s)) legacy.add(s);
    }

    final raw = data['fotoUrls'];
    if (raw is List) {
      for (final e in raw) {
        push(e?.toString() ?? '');
      }
    }
    final fotos = data['fotos'];
    if (fotos is List) {
      for (final e in fotos) {
        push(e?.toString() ?? '');
      }
    }
    for (var i = 1; i <= patrimonioMaxPhotos; i++) {
      push((data['foto0$i'] ?? '').toString());
    }
    for (final k in patrimonioLegacyUrlKeys) {
      push((data[k] ?? '').toString());
    }
    return legacy.take(patrimonioMaxPhotos).toList();
  }

  static List<String> patrimonioStoragePathsLegacy(Map<String, dynamic> data) {
    final raw = data['fotoStoragePaths'];
    if (raw is List) {
      return raw
          .map((e) => _normalizePath(e.toString()))
          .where((e) => e.isNotEmpty)
          .take(patrimonioMaxPhotos)
          .toList();
    }
    for (final k in patrimonioLegacyPathKeys) {
      final p = _normalizePath((data[k] ?? '').toString());
      if (p.isNotEmpty) return [p];
    }
    return const [];
  }

  static bool hasViewablePatrimonioPhoto(Map<String, dynamic> data) =>
      resolvePatrimonioPhotos(data).isNotEmpty ||
      patrimonioImageUrlsLegacy(data).isNotEmpty;

  // ─── Escrita — Chat (Storage path + URL https para visualização) ─────────

  /// Campos de mídia após upload Storage — path + URL https (painel, site, chat).
  static Map<String, dynamic> chatMediaWritePatch({
    required String storagePath,
    String? thumbStoragePath,
    String? mediaUrl,
    String? thumbUrl,
    String? fileName,
    int? fileSize,
    int? voiceDurationSeconds,
    bool uploadCompleted = true,
    bool storageVerified = true,
    String deliveryStatus = 'sent',
  }) {
    final sp = _normalizePath(storagePath);
    final patch = <String, dynamic>{
      'storagePath': sp,
      'uploadCompleted': uploadCompleted,
      'storageVerified': storageVerified,
      'status': deliveryStatus,
      'deliveryStatus': deliveryStatus,
      if (fileName != null && fileName.trim().isNotEmpty)
        'fileName': fileName.trim(),
      if (fileSize != null && fileSize > 0) 'fileSize': fileSize,
      if (voiceDurationSeconds != null && voiceDurationSeconds > 0) ...{
        'duration': voiceDurationSeconds,
        'durationSeconds': voiceDurationSeconds,
      },
    };
    final url = sanitizeImageUrl(mediaUrl ?? '');
    if (url.isNotEmpty) {
      patch['mediaUrl'] = url;
      patch['fileUrl'] = url;
    }
    final thumbPath = _normalizePath(thumbStoragePath);
    if (thumbPath.isNotEmpty) {
      patch['thumbStoragePath'] = thumbPath;
    }
    final thumbHttps = sanitizeImageUrl(thumbUrl ?? '');
    if (thumbHttps.isNotEmpty) {
      patch['thumbUrl'] = thumbHttps;
      patch['thumbnailUrl'] = thumbHttps;
    }
    return patch;
  }

  // ─── Escrita — Financeiro ───────────────────────────────────────────────

  static Map<String, dynamic> financeComprovanteWritePatch({
    required String url,
    required String storagePath,
    required String mimeType,
    required String fileName,
  }) {
    final safeUrl = sanitizeImageUrl(url);
    final path = _normalizePath(storagePath);
    return {
      'comprovanteUrl': safeUrl,
      'comprovanteLink': safeUrl,
      'comprovanteStoragePath': path,
      'comprovanteMimeType': mimeType,
      'comprovanteFileName': fileName,
      'hasComprovante': true,
      'comprovanteUploadState': EntityPublishStatus.published,
      'comprovanteUploadError': FieldValue.delete(),
      'comprovanteUpdatedAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    };
  }

  // ─── Escrita — Patrimônio (foto01…foto04 + paths) ───────────────────────

  static const patrimonioLegacyKeysToDelete = [
    'fotos',
    'fotoUrls',
    'imageUrls',
    'imageUrl',
    'fotoUrl',
    'thumbnail',
    'fotoStoragePaths',
    'imageStoragePath',
    'fotoPath',
    'fotoPrincipalPath',
    'gallery',
    'galeria',
    'fotoPrincipalThumbPath',
    'thumbStoragePath',
    'imageVariants',
    'fotoVariants',
    'publishState',
  ];

  static void patrimonioStripLegacyFields(Map<String, dynamic> payload) {
    for (final k in patrimonioLegacyKeysToDelete) {
      payload[k] = FieldValue.delete();
    }
  }

  static void patrimonioApplyIndexedSlots(
    Map<String, dynamic> payload,
    List<String> slotUrls,
    List<String> slotPaths,
  ) {
    for (var i = 0; i < patrimonioMaxPhotos; i++) {
      final u = sanitizeImageUrl(i < slotUrls.length ? slotUrls[i] : '');
      final p = _normalizePath(i < slotPaths.length ? slotPaths[i] : '');
      if (u.isNotEmpty) {
        payload[patrimonioUrlSlotKeys[i]] = u;
        payload[patrimonioPathSlotKeys[i]] =
            p.isNotEmpty ? p : FieldValue.delete();
      } else {
        payload[patrimonioUrlSlotKeys[i]] = FieldValue.delete();
        payload[patrimonioPathSlotKeys[i]] = FieldValue.delete();
      }
    }
    patrimonioStripLegacyFields(payload);
  }

  // ─── Escrita — outros módulos (reutilizado pelo publish) ─────────────────

  static Map<String, dynamic> memberProfileWritePatch({
    required String downloadUrl,
    required String storagePath,
    String? thumbStoragePath,
  }) {
    final url = sanitizeImageUrl(downloadUrl.trim());
    final path = _normalizePath(storagePath);
    final patch = <String, dynamic>{
      'photoStoragePath': path,
      'fotoPath': path,
      if (thumbStoragePath != null && thumbStoragePath.trim().isNotEmpty)
        'photoThumbStoragePath': _normalizePath(thumbStoragePath),
    };
    if (url.isNotEmpty) {
      patch.addAll({
        'fotoUrl': url,
        'foto_url': url,
        'FOTO_URL_OU_ID': url,
        'photoURL': url,
        'photoUrl': url,
        'avatarUrl': url,
      });
    }
    return patch;
  }

  static Map<String, dynamic> marketingClienteCapaWritePatch({
    required String downloadUrl,
    required String storagePath,
  }) {
    final url = sanitizeImageUrl(downloadUrl.trim());
    final path = _normalizePath(storagePath);
    return {
      if (path.isNotEmpty) 'fotoPath': path,
      if (url.isNotEmpty) 'fotoUrl': url,
    };
  }

  static Map<String, dynamic> eventTemplateCoverWritePatch({
    required String downloadUrl,
    required String storagePath,
  }) {
    final url = sanitizeImageUrl(downloadUrl.trim());
    final path = _normalizePath(storagePath);
    if (url.isEmpty && path.isEmpty) return const {};
    return {
      if (url.isNotEmpty) ...{
        'defaultImageUrl': url,
        'imageUrl': url,
        'imageUrls': <String>[url],
        'imagemUrl': url,
        'imagem_url': url,
        'coverUrl': url,
      },
      if (path.isNotEmpty) ...{
        'coverStoragePath': path,
        'photoStoragePath': path,
        'imageStoragePath': path,
        'defaultImageStoragePath': path,
      },
    };
  }

  static Map<String, dynamic> divulgacaoAssetWritePatch({
    required String downloadUrl,
    required String storagePath,
    required String kind,
  }) {
    final url = sanitizeImageUrl(downloadUrl.trim());
    final path =
        MarketingStorageLayout.normalizeObjectPath(_normalizePath(storagePath));
    return {
      'path': path,
      'kind': kind,
      if (url.isNotEmpty) 'downloadUrl': url,
    };
  }

  /// Deriva path Storage a partir de URL https (docs legados).
  static String? storagePathFromHttpsUrl(String? url) {
    final u = sanitizeImageUrl((url ?? '').trim());
    if (!isValidImageUrl(u)) return null;
    final p = firebaseStorageObjectPathFromHttpUrl(u);
    if (p == null || p.isEmpty) return null;
    return _normalizePath(p);
  }

  static String _mimeFromFileName(String fileName) {
    final low = fileName.toLowerCase();
    if (low.endsWith('.pdf')) return 'application/pdf';
    if (low.endsWith('.png')) return 'image/png';
    if (low.endsWith('.webp')) return 'image/webp';
    return 'image/jpeg';
  }

  // ─── Limpeza Firestore (exclusão instantânea de mídia) ─────────────────

  static Map<String, dynamic> comprovanteClearFirestorePatch() => {
        'hasComprovante': false,
        'comprovanteUploadState': FieldValue.delete(),
        'comprovanteUrl': FieldValue.delete(),
        'comprovanteLink': FieldValue.delete(),
        'comprovanteStoragePath': FieldValue.delete(),
        'comprovanteMimeType': FieldValue.delete(),
        'comprovanteFileName': FieldValue.delete(),
        'comprovanteUploadError': FieldValue.delete(),
        'comprovanteUpdatedAt': FieldValue.delete(),
        'updatedAt': FieldValue.serverTimestamp(),
      };

  static Map<String, dynamic> churchLogoClearFirestorePatch() {
    final patch = <String, dynamic>{
      'logoPath': FieldValue.delete(),
      'logoStoragePath': FieldValue.delete(),
      'logoUrl': FieldValue.delete(),
      'logoCacheRevision': FieldValue.delete(),
      'logoDataBase64': FieldValue.delete(),
      'logoBase64': FieldValue.delete(),
      'updatedAt': FieldValue.serverTimestamp(),
    };
    for (final k in const [
      'logo_url',
      'logoProcessedUrl',
      'logoProcessed',
      'logoImage',
      'logoDownloadUrl',
      'logoVariants',
    ]) {
      patch[k] = FieldValue.delete();
    }
    return patch;
  }

  static Map<String, dynamic> memberProfileClearFirestorePatch() => {
        'fotoUrl': FieldValue.delete(),
        'foto_url': FieldValue.delete(),
        'FOTO_URL_OU_ID': FieldValue.delete(),
        'FOTO': FieldValue.delete(),
        'foto': FieldValue.delete(),
        'photoURL': FieldValue.delete(),
        'photoUrl': FieldValue.delete(),
        'avatarUrl': FieldValue.delete(),
        'photoStoragePath': FieldValue.delete(),
        'fotoStoragePath': FieldValue.delete(),
        'fotoPath': FieldValue.delete(),
        'photoThumbStoragePath': FieldValue.delete(),
        'photoThumbUrl': FieldValue.delete(),
        'fotoThumbUrl': FieldValue.delete(),
        'profileThumbUrl': FieldValue.delete(),
        'profile_thumb_url': FieldValue.delete(),
        'photoVariants': FieldValue.delete(),
        'photoUploadState': FieldValue.delete(),
        'photoUploadError': FieldValue.delete(),
        'ATUALIZADO_EM': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      };
}
