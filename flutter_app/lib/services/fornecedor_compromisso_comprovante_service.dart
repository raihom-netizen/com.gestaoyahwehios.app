import 'dart:typed_data';

import 'package:gestao_yahweh/core/church_storage_layout.dart';
import 'package:gestao_yahweh/core/firebase_bootstrap_service.dart';
import 'package:gestao_yahweh/services/image_helper.dart';
import 'package:gestao_yahweh/services/upload_bytes_core.dart';

/// Upload de comprovante (print/imagem/PDF) — path fixo com overwrite no Storage.
abstract final class FornecedorCompromissoComprovanteService {
  FornecedorCompromissoComprovanteService._();

  static Future<String> upload({
    required String churchId,
    required String fornecedorId,
    required String compromissoId,
    required Uint8List bytes,
    required String contentType,
    String ext = 'jpg',
  }) async {
    final cid = churchId.trim();
    final fid = fornecedorId.trim();
    final compId = compromissoId.trim();
    if (cid.isEmpty || fid.isEmpty || compId.isEmpty) {
      throw ArgumentError('churchId, fornecedorId e compromissoId são obrigatórios.');
    }
    if (bytes.isEmpty) {
      throw StateError('Anexo vazio — selecione outro ficheiro.');
    }

    await FirebaseBootstrapService.ensureStorageAlwaysLinked(refreshAuthToken: true);

    var payload = bytes;
    var mime = contentType.trim().isEmpty ? 'application/octet-stream' : contentType;
    var fileExt = ext.replaceAll('.', '').trim().isEmpty ? 'jpg' : ext.replaceAll('.', '');

    if (mime.startsWith('image/') && mime != 'application/pdf') {
      payload = await ImageHelper.compressPatrimonioPhotoForUpload(bytes);
      mime = 'image/jpeg';
      fileExt = 'jpg';
    }

    final path = ChurchStorageLayout.fornecedorCompromissoComprovantePath(
      tenantId: cid,
      fornecedorId: fid,
      compromissoId: compId,
      ext: fileExt,
    );

    return uploadStoragePutDataWithRetry(
      storagePath: path,
      bytes: payload,
      contentType: mime,
      cacheControl: 'public, max-age=31536000',
      maxAttempts: 4,
      useOfflineQueue: false,
    );
  }
}
