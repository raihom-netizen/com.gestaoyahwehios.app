import 'dart:typed_data';

import 'package:gestao_yahweh/core/church_central_storage_upload.dart';
import 'package:gestao_yahweh/core/yahweh_module_media_gate.dart';
import 'package:gestao_yahweh/services/church_media_upload_facade.dart';

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
    void Function(double progress)? onProgress,
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

    final mime = contentType.trim().isEmpty ? 'application/octet-stream' : contentType;
    if (mime.startsWith('video/')) {
      throw StateError('Vídeo não permitido. Use JPEG, PNG ou PDF.');
    }

    await ChurchMediaUploadFacade.ensureModuleReady(YahwehMediaModule.financeiro);

    final uploaded =
        await ChurchCentralStorageUpload.uploadFornecedorCompromissoComprovante(
      churchId: cid,
      fornecedorId: fid,
      compromissoId: compId,
      bytes: bytes,
      mimeType: mime,
      ext: ext,
      onProgress: onProgress,
    );

    return uploaded.downloadUrl;
  }
}
