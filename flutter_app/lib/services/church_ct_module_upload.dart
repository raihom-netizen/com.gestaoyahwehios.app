import 'dart:typed_data';

import 'package:file_picker/file_picker.dart' show FileType;
import 'package:image_picker/image_picker.dart';
import 'package:gestao_yahweh/core/church_central_storage_upload.dart';
import 'package:gestao_yahweh/core/media_upload_limits.dart';
import 'package:gestao_yahweh/core/yahweh_module_media_gate.dart'
    show YahwehMediaModule;
import 'package:gestao_yahweh/services/church_media_upload_facade.dart';
import 'package:gestao_yahweh/services/media_service.dart';
import 'package:gestao_yahweh/utils/utilitarios_file_io.dart'
    show utilitariosReadPlatformFileBytes;
import 'package:gestao_yahweh/utils/yahweh_file_picker.dart';

/// Resultado do picker (bytes + nome) — Web/Android/iOS iguais.
class ChurchCtPickedFile {
  const ChurchCtPickedFile({
    required this.bytes,
    required this.fileName,
    this.contentType,
  });

  final Uint8List bytes;
  final String fileName;
  final String? contentType;
}

/// **Padrão Controle Total** — entrada única para os módulos do painel:
/// Cadastro, Membros, Eventos/Avisos, Financeiro, Fornecedores, Património.
///
/// Fluxo: pick → bytes (`Uint8List`) → [ChurchMediaUploadFacade] → URL+path
/// no Firestore. Nunca `putFile` na Web; nunca base64 permanente no Firestore.
abstract final class ChurchCtModuleUpload {
  ChurchCtModuleUpload._();

  static const int kMaxImageBytes = kStorageRulesMaxFeedImageBytes;
  static const int kMaxReceiptBytes = 5 * 1024 * 1024;

  /// Warm gate — use antes de qualquer upload (painel, Master, signup, divulgação).
  static Future<void> ensureReady({
    YahwehMediaModule? gateModule,
    bool requireAuth = true,
  }) async {
    if (gateModule != null) {
      await ChurchMediaUploadFacade.ensureModuleReady(gateModule);
    } else {
      await ChurchMediaUploadFacade.ensureReady(requireAuth: requireAuth);
    }
  }

  /// Galeria/câmara — imagem para logo, foto membro, património, capa, etc.
  static Future<ChurchCtPickedFile?> pickImage({
    ImageSource source = ImageSource.gallery,
    int imageQuality = 88,
    double? maxWidth = 1920,
  }) async {
    final x = await ImagePicker().pickImage(
      source: source,
      imageQuality: imageQuality,
      maxWidth: maxWidth,
    );
    if (x == null) return null;
    final bytes = await MediaService.readXFileBytes(x);
    if (bytes.isEmpty) return null;
    if (bytes.length > kMaxImageBytes) {
      throw StateError(
        'Imagem muito grande. Máximo ${(kMaxImageBytes / (1024 * 1024)).toStringAsFixed(0)} MB.',
      );
    }
    return ChurchCtPickedFile(
      bytes: bytes,
      fileName: x.name.isNotEmpty ? x.name : 'imagem.jpg',
      contentType: x.mimeType,
    );
  }

  /// PDF/PNG/JPG — comprovantes (financeiro / fornecedor), padrão CT ≤ 5 MB.
  static Future<ChurchCtPickedFile?> pickReceiptOrDocument({
    List<String> allowedExtensions = const ['pdf', 'png', 'jpg', 'jpeg'],
    int maxBytes = kMaxReceiptBytes,
  }) async {
    final result = await YahwehFilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: allowedExtensions,
      withData: true,
      allowMultiple: false,
    );
    if (result == null || result.files.isEmpty) return null;
    final f = result.files.first;
    final bytes = await utilitariosReadPlatformFileBytes(f);
    if (bytes.isEmpty) {
      throw StateError('Não foi possível ler o ficheiro.');
    }
    if (bytes.length > maxBytes) {
      throw StateError(
        'Ficheiro muito grande. Máximo ${(maxBytes / (1024 * 1024)).toStringAsFixed(0)} MB.',
      );
    }
    return ChurchCtPickedFile(
      bytes: bytes,
      fileName: f.name,
      contentType: f.extension,
    );
  }

  /// Master / divulgação — imagens, PDF e vídeo (bytes; nunca putFile na Web).
  static Future<ChurchCtPickedFile?> pickDivulgacaoMedia({
    int maxBytes = 40 * 1024 * 1024,
  }) {
    return pickReceiptOrDocument(
      allowedExtensions: const [
        'jpg',
        'jpeg',
        'png',
        'webp',
        'gif',
        'mp4',
        'mov',
        'webm',
        'm4v',
        'pdf',
      ],
      maxBytes: maxBytes,
    );
  }

  /// Upload canónico — path `igrejas/{churchId}/…` via Facade (padrão CT).
  static Future<ChurchCentralUploadResult> uploadImageAtPath({
    required Uint8List bytes,
    required String storagePath,
    required String logLabel,
    YahwehMediaModule? gateModule,
    bool alreadyCompressed = false,
    bool requireAuth = true,
    void Function(double progress)? onProgress,
    Duration timeout = ChurchMediaUploadFacade.kDefaultTimeout,
    int maxBytes = kMaxImageBytes,
  }) async {
    await ensureReady(gateModule: gateModule, requireAuth: requireAuth);
    return ChurchMediaUploadFacade.uploadMidia(
      bytes: bytes,
      storagePath: storagePath,
      logLabel: logLabel,
      alreadyCompressed: alreadyCompressed,
      onProgress: onProgress,
      timeout: timeout,
      maxBytes: maxBytes,
    );
  }

  /// Várias fotos em paralelo (património / galeria evento).
  static Future<List<ChurchMediaUploadBatchResult>> uploadBatch({
    required List<ChurchMediaUploadBatchItem> items,
    void Function(int index, double progress)? onItemProgress,
    void Function(int completed, int total)? onBatchProgress,
  }) {
    return ChurchMediaUploadFacade.uploadBatchParallel(
      items: items,
      onItemProgress: onItemProgress,
      onBatchProgress: onBatchProgress,
    );
  }

  static String mensagemAmigavel(Object e) =>
      ChurchMediaUploadFacade.mensagemAmigavel(e);
}
