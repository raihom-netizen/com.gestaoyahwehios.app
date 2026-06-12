import 'dart:async';
import 'dart:typed_data';

import 'package:gestao_yahweh/core/church_storage_layout.dart';
import 'package:gestao_yahweh/core/ecofire/ecofire_firestore_meta.dart';
import 'package:gestao_yahweh/core/ecofire/ecofire_media_upload.dart';

/// Resultado de upload de galeria — um ficheiro por slot na pasta do bem.
class PatrimonioGalleryUploadResult {
  const PatrimonioGalleryUploadResult({
    required this.downloadUrl,
    required this.storagePath,
  });

  final String downloadUrl;
  final String storagePath;
}

/// Upload patrimônio — EcoFire directo: `igrejas/{churchId}/patrimonio/{itemId}/galeria_XX.webp`.
abstract final class PatrimonioMediaUpload {
  PatrimonioMediaUpload._();

  static const Duration uploadTimeout = Duration(seconds: 45);

  static Future<PatrimonioGalleryUploadResult> uploadGalleryPhoto({
    required String churchId,
    required String itemDocId,
    required int slotIndex,
    required Uint8List rawBytes,
    void Function(double progress)? onProgress,
  }) async {
    final cid = churchId.trim();
    final iid = itemDocId.trim();
    if (cid.isEmpty || iid.isEmpty) {
      throw ArgumentError('churchId e itemDocId são obrigatórios.');
    }
    if (rawBytes.isEmpty) {
      throw StateError('Imagem vazia — selecione outra foto.');
    }

    final path = ChurchStorageLayout.patrimonioPhotoPath(cid, iid, slotIndex);

    final url = await EcoFireMediaUpload.uploadBytes(
      storagePath: path,
      bytes: rawBytes,
      contentType: 'image/webp',
      profile: EcoFireMediaProfile.patrimonio,
      onProgress: onProgress,
    ).timeout(
      uploadTimeout,
      onTimeout: () => throw TimeoutException(
        'Upload da foto ${slotIndex + 1} demorou demais. Verifique a rede.',
      ),
    );

    return PatrimonioGalleryUploadResult(
      downloadUrl: url,
      storagePath: path,
    );
  }
}
