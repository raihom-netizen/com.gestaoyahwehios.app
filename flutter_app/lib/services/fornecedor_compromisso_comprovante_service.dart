import 'dart:typed_data';

import 'package:gestao_yahweh/core/church_central_storage_upload.dart';
import 'package:gestao_yahweh/services/church_media_upload_facade.dart';

/// Resultado do upload — path real (= ficheiro no Storage, não mime do picker).
class FornecedorComprovanteUploadResult {
  const FornecedorComprovanteUploadResult({
    required this.downloadUrl,
    required this.storagePath,
    required this.contentType,
  });

  final String downloadUrl;
  final String storagePath;
  final String contentType;
}

/// Upload de comprovante (print/imagem/PDF) — path fixo com overwrite no Storage.
/// Mesmo pipeline do financeiro (CT): 1 compress → putData → URL.
abstract final class FornecedorCompromissoComprovanteService {
  FornecedorCompromissoComprovanteService._();

  static Future<FornecedorComprovanteUploadResult> upload({
    required String churchId,
    required String fornecedorId,
    required String compromissoId,
    required Uint8List bytes,
    required String contentType,
    String ext = 'jpg',
    void Function(double progress)? onProgress,
    bool alreadyCompressed = false,
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

    final mime =
        contentType.trim().isEmpty ? 'application/octet-stream' : contentType;
    if (mime.startsWith('video/')) {
      throw StateError('Vídeo não permitido. Use JPEG, PNG ou PDF.');
    }

    await ChurchMediaUploadFacade.ensureReady(requireAuth: true);

    final uploaded =
        await ChurchCentralStorageUpload.uploadFornecedorCompromissoComprovante(
      churchId: cid,
      fornecedorId: fid,
      compromissoId: compId,
      bytes: bytes,
      mimeType: mime,
      ext: ext,
      onProgress: (p) => onProgress?.call(p.clamp(0.0, 1.0)),
      alreadyCompressed: alreadyCompressed,
      skipEnsureReady: true,
    );

    return FornecedorComprovanteUploadResult(
      downloadUrl: uploaded.downloadUrl,
      storagePath: uploaded.storagePath,
      contentType: uploaded.contentType,
    );
  }
}
