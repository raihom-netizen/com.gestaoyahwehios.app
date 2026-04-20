import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import 'package:firebase_auth/firebase_auth.dart';

import 'package:gestao_yahweh/certificates/certificate_visual_template.dart';
import 'package:gestao_yahweh/core/church_storage_layout.dart';
import 'package:gestao_yahweh/core/public_site_media_auth.dart';
import 'package:gestao_yahweh/core/services/app_storage_image_service.dart';
import 'package:gestao_yahweh/pdf/certificate_pdf_builder.dart';
import 'package:gestao_yahweh/pdf/certificate_pdf_isolate.dart';
import 'package:gestao_yahweh/services/firebase_storage_service.dart';
import 'package:gestao_yahweh/ui/widgets/safe_network_image.dart';
import 'package:gestao_yahweh/utils/cert_pdf_image_optimize.dart'
    show
        CertPdfImageOptimizeMessage,
        optimizeCertPdfImageBytes,
        optimizeCertPdfImageBytesMaxMemory,
        CertPdfImageMaxMemoryMessage,
        CertPdfLogoOptimizeMessage,
        optimizeCertPdfLogoBytes;
import 'package:gestao_yahweh/utils/carteirinha_pdf_signature_enhance.dart';
import 'package:gestao_yahweh/utils/report_pdf_branding.dart';

/// Signatário efetivo (com [memberId] para buscar imagem no Firestore/Storage).
class CertPdfPipelineSignatory {
  final String memberId;
  final String nome;
  final String cargo;
  /// CPF só dígitos (até 11) para o selo de assinatura digital no PDF.
  final String cpfDigits;
  /// Quando preenchido (ex.: lista de membros já carregada), evita leitura extra no Firestore.
  final String? assinaturaUrlHint;

  const CertPdfPipelineSignatory({
    required this.memberId,
    required this.nome,
    required this.cargo,
    this.cpfDigits = '',
    this.assinaturaUrlHint,
  });
}

/// Parâmetros serializáveis para montar o PDF (rede + otimização na isolate principal; PDF em [Isolate.run] fora da web).
class CertPdfPipelineParams {
  final String tenantId;
  final List<String> logoFetchCandidates;
  final String logoUrlFallback;
  final String titulo;
  final String subtitulo;
  final String texto;
  final String nomeMembro;
  /// Segunda linha do nome no PDF (ex.: segundo cônjuge).
  final String nomeMembroLinha2;
  /// CPF já formatado (ex.: 000.000.000-00) para negrito no PDF.
  final String cpfFormatado;
  final String nomeIgreja;
  final String local;
  final String issuedDate;
  final String layoutId;
  final String fontStyleId;
  final int colorPrimaryArgb;
  final int colorTextArgb;
  final String pastorManual;
  final String cargoManual;
  final bool useDigitalSignature;
  /// Linha «Dados: …» do selo digital (preenchida na emissão; vazio usa texto mínimo no PDF).
  final String digitalSignatureDadosLine;
  final List<CertPdfPipelineSignatory> signatoriesForPdf;
  /// URL para QR no layout [gala_luxo]; vazio omite o QR no selo.
  final String qrValidationUrl;

  /// Modelo visual ([CertificateVisualTemplate.id]).
  final String visualTemplateId;

  /// Texto extra anexado ao corpo do certificado.
  final String textoAdicional;

  /// Incluir imagem de `configuracoes/assinatura.png` (pastor) além dos signatários.
  final bool includeInstitutionalPastorSignature;

  /// Nome exibido junto à assinatura institucional.
  final String institutionalPastorNome;

  /// Cargo exibido junto à assinatura institucional.
  final String institutionalPastorCargo;

  const CertPdfPipelineParams({
    required this.tenantId,
    required this.logoFetchCandidates,
    required this.logoUrlFallback,
    required this.titulo,
    this.subtitulo = '',
    required this.texto,
    required this.nomeMembro,
    this.nomeMembroLinha2 = '',
    this.cpfFormatado = '',
    required this.nomeIgreja,
    required this.local,
    this.issuedDate = '',
    required this.layoutId,
    this.fontStyleId = 'moderna',
    required this.colorPrimaryArgb,
    required this.colorTextArgb,
    required this.pastorManual,
    required this.cargoManual,
    required this.useDigitalSignature,
    this.digitalSignatureDadosLine = '',
    required this.signatoriesForPdf,
    this.qrValidationUrl = '',
    this.visualTemplateId = 'classico_dourado',
    this.textoAdicional = '',
    this.includeInstitutionalPastorSignature = true,
    this.institutionalPastorNome = '',
    this.institutionalPastorCargo = 'Pastor(a) Presidente',
  });
}

/// Uma fatia por membro no PDF único em lote (layout [gala_luxo]).
class CertPdfGalaBatchMemberSlice {
  final String nomeMembro;
  final String cpfFormatado;
  /// Texto do corpo com placeholders já resolvidos.
  final String texto;
  final String qrValidationUrl;
  /// Quando preenchidos, permitem misturar tipos de certificado num único PDF.
  final String? titulo;
  final String? subtitulo;
  final int? colorPrimaryArgb;
  final int? colorTextArgb;
  final String? fontStyleId;

  const CertPdfGalaBatchMemberSlice({
    required this.nomeMembro,
    required this.cpfFormatado,
    required this.texto,
    required this.qrValidationUrl,
    this.titulo,
    this.subtitulo,
    this.colorPrimaryArgb,
    this.colorTextArgb,
    this.fontStyleId,
  });
}

/// Logo, fundo e assinaturas já descarregados e otimizados — reutilizar no ZIP em lote.
class CertPdfResolvedShared {
  final Uint8List? logoOpt;
  final Uint8List? bgOpt;
  final List<CertSignatoryPdfData> pdfSignatories;

  const CertPdfResolvedShared({
    required this.logoOpt,
    required this.bgOpt,
    required this.pdfSignatories,
  });
}

final Map<String, Uint8List?> _logoBytesCache = <String, Uint8List?>{};
final Map<String, Uint8List?> _signatureBytesCache = <String, Uint8List?>{};
/// Fundo de certificado por tenant + modelo — evita novo download a cada emissão.
final Map<String, Uint8List?> _certificateBackgroundBytesCache =
    <String, Uint8List?>{};
/// Fundo já redimensionado para o PDF (por tenant + modelo).
final Map<String, Uint8List?> _certificateBackgroundOptimizedCache =
    <String, Uint8List?>{};
final Map<String, Uint8List?> _logoOptimizedBytesCache = <String, Uint8List?>{};
final Map<String, Uint8List?> _signatureOptimizedBytesCache =
    <String, Uint8List?>{};
/// Assinatura institucional (configuracoes/assinatura) por igreja — evita Storage a cada PDF.
final Map<String, Uint8List?> _institutionalPastorSigRawCache =
    <String, Uint8List?>{};
final Map<String, Uint8List?> _institutionalPastorSigOptCache =
    <String, Uint8List?>{};
Uint8List? _fontMontserratCache;
Uint8List? _fontGreatVibesCache;
Uint8List? _fontUnifrakturCache;
Uint8List? _fontCinzelDecorativeCache;
Uint8List? _fontPinyonScriptCache;
Uint8List? _fontLibreBaskervilleCache;

Future<void> _ensureLuxuryPdfFontsLoaded() async {
  await Future.wait([
    () async {
      if (_fontCinzelDecorativeCache == null) {
        try {
          final b =
              await rootBundle.load('assets/fonts/CinzelDecorative-Regular.ttf');
          _fontCinzelDecorativeCache = b.buffer.asUint8List();
        } catch (_) {}
      }
    }(),
    () async {
      if (_fontPinyonScriptCache == null) {
        try {
          final b =
              await rootBundle.load('assets/fonts/PinyonScript-Regular.ttf');
          _fontPinyonScriptCache = b.buffer.asUint8List();
        } catch (_) {}
      }
    }(),
    () async {
      if (_fontLibreBaskervilleCache == null) {
        try {
          final b = await rootBundle
              .load('assets/fonts/LibreBaskerville-Variable.ttf');
          _fontLibreBaskervilleCache = b.buffer.asUint8List();
        } catch (_) {}
      }
    }(),
  ]);
}

Future<Uint8List?> _fetchCertificateTemplateBackgroundBytes({
  required String tenantId,
  required String storageStem,
}) async {
  final tid = tenantId.trim();
  if (tid.isEmpty) return null;
  final stem = storageStem.trim();
  final cacheKey = '$tid|$stem';
  if (_certificateBackgroundBytesCache.containsKey(cacheKey)) {
    return _certificateBackgroundBytesCache[cacheKey];
  }
  if (kIsWeb) {
    await PublicSiteMediaAuth.ensureWebAnonymousForStorage();
    try {
      await FirebaseAuth.instance.currentUser?.getIdToken();
    } catch (_) {}
  }
  for (final path
      in ChurchStorageLayout.certificateTemplateBackgroundPaths(tid, stem)) {
    try {
      final b = await FirebaseStorage.instance
          .ref(path)
          .getData(12 * 1024 * 1024)
          .timeout(const Duration(seconds: 28), onTimeout: () => null);
      if (b != null && b.length > 64) {
        final out = Uint8List.fromList(b);
        _certificateBackgroundBytesCache[cacheKey] = out;
        return out;
      }
    } catch (_) {}
  }
  return null;
}

Future<Uint8List?> _optimizeBackgroundForPrintPdf(Uint8List bytes) async {
  /// ~300 DPI no lado longo do A4 paisagem (11,7") ≈ 3500 px; limitamos para PDF leve (~200 DPI efetivo).
  final msg = CertPdfImageOptimizeMessage(
    bytes: bytes,
    maxW: 2400,
    maxH: 1700,
    jpegQuality: 88,
  );
  if (kIsWeb) return optimizeCertPdfImageBytes(msg);
  return compute(optimizeCertPdfImageBytes, msg);
}

Future<Uint8List?> _fetchInstitutionalPastorSignatureBytes(
    String tenantId) async {
  final tid = tenantId.trim();
  if (tid.isEmpty) return null;
  if (_institutionalPastorSigRawCache.containsKey(tid)) {
    return _institutionalPastorSigRawCache[tid];
  }
  if (kIsWeb) {
    await PublicSiteMediaAuth.ensureWebAnonymousForStorage();
    try {
      await FirebaseAuth.instance.currentUser?.getIdToken();
    } catch (_) {}
  }
  for (final path in ChurchStorageLayout.pastorSignatureConfigPaths(tid)) {
    try {
      final b = await FirebaseStorage.instance
          .ref(path)
          .getData(5 * 1024 * 1024)
          .timeout(const Duration(seconds: 22), onTimeout: () => null);
      if (b != null && b.length > 32) {
        final out = Uint8List.fromList(b);
        _institutionalPastorSigRawCache[tid] = out;
        return out;
      }
    } catch (_) {}
  }
  _institutionalPastorSigRawCache[tid] = null;
  return null;
}

Future<void> _ensurePdfFontsLoaded() async {
  await Future.wait([
    () async {
      if (_fontMontserratCache == null) {
        try {
          final b = await rootBundle.load('assets/fonts/Roboto-Regular.ttf');
          _fontMontserratCache = b.buffer.asUint8List();
        } catch (_) {}
      }
    }(),
    () async {
      if (_fontGreatVibesCache == null) {
        try {
          final b = await rootBundle.load('assets/fonts/GreatVibes-Regular.ttf');
          _fontGreatVibesCache = b.buffer.asUint8List();
        } catch (_) {
          try {
            final b = await rootBundle.load('assets/fonts/Roboto-Italic.ttf');
            _fontGreatVibesCache = b.buffer.asUint8List();
          } catch (_) {}
        }
      }
    }(),
    () async {
      if (_fontUnifrakturCache == null) {
        try {
          final b =
              await rootBundle.load('assets/fonts/UnifrakturMaguntia-Book.ttf');
          _fontUnifrakturCache = b.buffer.asUint8List();
        } catch (_) {
          try {
            final b = await rootBundle.load('assets/fonts/Roboto-Bold.ttf');
            _fontUnifrakturCache = b.buffer.asUint8List();
          } catch (_) {}
        }
      }
    }(),
  ]);
}

Future<void> _ensureAllCertPdfFonts() async {
  await Future.wait([
    _ensurePdfFontsLoaded(),
    _ensureLuxuryPdfFontsLoaded(),
  ]);
}

/// Pré-carrega fontes dos certificados (chamar ao abrir a tela — “Gerar PDF” fica mais rápido).
Future<void> warmCertificatePdfFontAssets() => _ensureAllCertPdfFonts();

Future<Uint8List?> _fetchLogoBytesHighRes(String rawUrl) async {
  const logoTimeout = Duration(seconds: 10);
  final u = sanitizeImageUrl(rawUrl);
  final cacheKey = u.isNotEmpty ? u : rawUrl.trim();
  if (cacheKey.isNotEmpty && _logoBytesCache.containsKey(cacheKey)) {
    return _logoBytesCache[cacheKey];
  }
  final rawTrim = rawUrl.trim();
  if (rawTrim.toLowerCase().startsWith('gs://')) {
    try {
      final refGs = FirebaseStorage.instance.refFromURL(rawTrim);
      final b = await refGs
          .getData(8 * 1024 * 1024)
          .timeout(logoTimeout, onTimeout: () => null);
      if (b != null && b.length > 32) {
        if (cacheKey.isNotEmpty) _logoBytesCache[cacheKey] = b;
        return Uint8List.fromList(b);
      }
    } catch (_) {}
  }
  if (!isValidImageUrl(u)) {
    final looksStoragePath = rawTrim.isNotEmpty &&
        !rawTrim.toLowerCase().startsWith('http') &&
        !rawTrim.toLowerCase().startsWith('gs://');
    if (looksStoragePath) {
      try {
        final byPath = await FirebaseStorage.instance
            .ref(rawTrim)
            .getData(12 * 1024 * 1024)
            .timeout(logoTimeout, onTimeout: () => null);
        if (byPath != null && byPath.length > 32) {
          if (cacheKey.isNotEmpty) _logoBytesCache[cacheKey] = byPath;
          return Uint8List.fromList(byPath);
        }
      } catch (_) {}
    }
    return null;
  }
  try {
    final b = await firebaseStorageBytesFromDownloadUrl(
      u,
      maxBytes: 6 * 1024 * 1024,
    ).timeout(logoTimeout, onTimeout: () => null);
    if (b != null && b.length > 32) {
      if (cacheKey.isNotEmpty) _logoBytesCache[cacheKey] = b;
      return b;
    }
  } catch (_) {}
  /// Alguns hosts `*.firebasestorage.app` falham no primeiro [refFromURL]; repetir após refresh explícito.
  if (firebaseStorageMediaUrlLooksLike(u)) {
    try {
      await PublicSiteMediaAuth.ensureWebAnonymousForStorage();
      try {
        await FirebaseAuth.instance.currentUser?.getIdToken();
      } catch (_) {}
      final refreshed = await freshFirebaseStorageDisplayUrl(u)
          .timeout(logoTimeout, onTimeout: () => u);
      final u2 = sanitizeImageUrl(refreshed);
      if (u2.isNotEmpty && u2 != u && isValidImageUrl(u2)) {
        final b2 = await firebaseStorageBytesFromDownloadUrl(
          u2,
          maxBytes: 6 * 1024 * 1024,
        ).timeout(logoTimeout, onTimeout: () => null);
        if (b2 != null && b2.length > 32) {
          if (cacheKey.isNotEmpty) _logoBytesCache[cacheKey] = b2;
          return b2;
        }
      }
    } catch (_) {}
  }
  try {
    final response = await http
        .get(
          Uri.parse(u),
          headers: const {'Accept': 'image/*,*/*;q=0.8'},
        )
        .timeout(logoTimeout);
    if (response.statusCode == 200 && response.bodyBytes.length > 32) {
      final out = Uint8List.fromList(response.bodyBytes);
      if (cacheKey.isNotEmpty) _logoBytesCache[cacheKey] = out;
      return out;
    }
  } catch (_) {}
  /// Não cachear falha: token/rede podem liberar na tentativa seguinte (evita logo “presa” em branco).
  return null;
}

/// Último recurso: lê o objeto no Storage (mesmos caminhos que [FirebaseStorageService.getChurchLogoDownloadUrl]).
Future<Uint8List?> _tryChurchLogoBytesDirectFromStorage(
  String tenantId, {
  String? churchNameHint,
}) async {
  final tid = tenantId.trim();
  if (tid.isEmpty) return null;
  if (kIsWeb) {
    await PublicSiteMediaAuth.ensureWebAnonymousForStorage();
    try {
      await FirebaseAuth.instance.currentUser?.getIdToken();
    } catch (_) {}
  }
  Map<String, dynamic>? tenantHint;
  final hint = churchNameHint?.trim() ?? '';
  if (hint.isNotEmpty) {
    tenantHint = {'name': hint};
  }
  final paths = await FirebaseStorageService.getChurchLogoCandidateStoragePaths(
    tid,
    tenantData: tenantHint,
  );
  if (paths.isEmpty) return null;
  final chunks = await Future.wait(
    paths.map(
      (p) => FirebaseStorage.instance
          .ref(p)
          .getData(12 * 1024 * 1024)
          .timeout(const Duration(seconds: 4), onTimeout: () => null)
          .catchError((_) => null),
    ),
  );
  for (final b in chunks) {
    if (b != null && b.length > 32) return Uint8List.fromList(b);
  }
  return null;
}

Future<Uint8List?> _fetchSignatorySignatureBytes({
  required String tenantId,
  required String memberId,
  String? assinaturaUrlHint,
}) async {
  final cacheKey =
      '$tenantId|$memberId|${sanitizeImageUrl(assinaturaUrlHint ?? '').trim()}';
  if (_signatureBytesCache.containsKey(cacheKey)) {
    return _signatureBytesCache[cacheKey];
  }
  try {
    String raw;
    if (assinaturaUrlHint != null && assinaturaUrlHint.trim().isNotEmpty) {
      raw = assinaturaUrlHint.trim();
    } else {
      DocumentSnapshot<Map<String, dynamic>>? membroSnap;
      try {
        membroSnap = await FirebaseFirestore.instance
            .collection('igrejas')
            .doc(tenantId)
            .collection('membros')
            .doc(memberId)
            .get()
            .timeout(const Duration(seconds: 14));
      } on TimeoutException {
        membroSnap = null;
      } catch (_) {
        membroSnap = null;
      }
      raw = (membroSnap?.data()?['assinaturaUrl'] ??
              membroSnap?.data()?['assinatura_url'] ??
              '')
          .toString()
          .trim();
    }
    if (raw.isEmpty) {
      _signatureBytesCache[cacheKey] = null;
      return null;
    }

    if (isDataImageUrl(raw)) {
      final decoded = decodeDataImageBytes(raw);
      final out =
          (decoded != null && decoded.length > 32) ? decoded : null;
      _signatureBytesCache[cacheKey] = out;
      return out;
    }

    var url = sanitizeImageUrl(raw);

    /// Caminho Storage / gs:// — [firebaseStorageBytesFromDownloadUrl] só aceita http(s).
    Future<Uint8List?> tryBytesFromStorageRef() async {
      if (raw.toLowerCase().startsWith('gs://')) {
        try {
          final refGs = FirebaseStorage.instance.refFromURL(raw);
          final b = await refGs
              .getData(2 * 1024 * 1024)
              .timeout(const Duration(seconds: 14), onTimeout: () => null);
          if (b != null && b.length > 32) return Uint8List.fromList(b);
        } catch (_) {}
        return null;
      }
      final path = normalizeFirebaseStorageObjectPath(
          raw.replaceFirst(RegExp(r'^/+'), ''));
      final pathLooksStorage = !path.contains('://') &&
          path.isNotEmpty &&
          (firebaseStorageMediaUrlLooksLike(path) ||
              path.toLowerCase().contains('membros/') ||
              path.toLowerCase().contains('_assinatura'));
      if (!pathLooksStorage) return null;
      try {
        final b = await FirebaseStorage.instance
            .ref(path)
            .getData(2 * 1024 * 1024)
            .timeout(const Duration(seconds: 14), onTimeout: () => null);
        if (b != null && b.length > 32) return Uint8List.fromList(b);
      } catch (_) {}
      return null;
    }

    if (!isValidImageUrl(url)) {
      final fromRef = await tryBytesFromStorageRef();
      if (fromRef != null) {
        _signatureBytesCache[cacheKey] = fromRef;
        return fromRef;
      }
      try {
        final resolved = await freshFirebaseStorageDisplayUrl(raw)
            .timeout(const Duration(seconds: 22), onTimeout: () => '');
        url = sanitizeImageUrl(resolved);
      } catch (_) {}
    }

    if (!isValidImageUrl(url)) {
      final fromRef2 = await tryBytesFromStorageRef();
      if (fromRef2 != null) {
        _signatureBytesCache[cacheKey] = fromRef2;
        return fromRef2;
      }
      _signatureBytesCache[cacheKey] = null;
      return null;
    }

    Uint8List? bytes;
    try {
      bytes = await firebaseStorageBytesFromDownloadUrl(
        url,
        maxBytes: 2 * 1024 * 1024,
      ).timeout(const Duration(seconds: 10), onTimeout: () => null);
    } catch (_) {}
    if (bytes == null || bytes.length < 32) {
      if (isFirebaseStorageHttpUrl(url)) {
        try {
          final fresh = await refreshFirebaseStorageDownloadUrl(url)
              .timeout(const Duration(seconds: 8), onTimeout: () => null);
          if (fresh != null && fresh.isNotEmpty) {
            final u2 = sanitizeImageUrl(fresh);
            if (u2.isNotEmpty) {
              try {
                bytes = await firebaseStorageBytesFromDownloadUrl(
                  u2,
                  maxBytes: 2 * 1024 * 1024,
                ).timeout(const Duration(seconds: 10), onTimeout: () => null);
              } catch (_) {}
            }
          }
        } catch (_) {}
      }
    }
    if (bytes == null || bytes.length < 32) {
      try {
        final resp = await http
            .get(
              Uri.parse(url),
              headers: const {'Accept': 'image/*,*/*;q=0.8'},
            )
            .timeout(const Duration(seconds: 12));
        if (resp.statusCode == 200 && resp.bodyBytes.length > 32) {
          bytes = Uint8List.fromList(resp.bodyBytes);
        }
      } catch (_) {}
    }
    final out = (bytes != null && bytes.length > 32) ? bytes : null;
    _signatureBytesCache[cacheKey] = out;
    return out;
  } catch (_) {
    _signatureBytesCache[cacheKey] = null;
    return null;
  }
}

Future<Uint8List?> _signatureBytesFloatingPipeline(
  Uint8List b,
  String signCacheKey,
  int sigMaxW,
  int sigMaxH,
) async {
  try {
    final piped = kIsWeb
        ? carteirinhaPdfSignaturePipelineSync(b)
        : await compute(carteirinhaPdfSignaturePipelineForCompute, b);
    if (piped != null && piped.length > 32) {
      _signatureOptimizedBytesCache[signCacheKey] = piped;
      return piped;
    }
  } catch (_) {}
  final fallback = await _optimizeImageForPdf(b, sigMaxW, sigMaxH);
  _signatureOptimizedBytesCache[signCacheKey] = fallback;
  return fallback;
}

Future<Uint8List?> _optimizeImageForPdf(
  Uint8List bytes,
  int maxW,
  int maxH,
) async {
  final msg = CertPdfImageMaxMemoryMessage(
    bytes: bytes,
    maxW: maxW,
    maxH: maxH,
    maxOutputBytes: 512000,
  );
  if (kIsWeb) return optimizeCertPdfImageBytesMaxMemory(msg);
  return compute(optimizeCertPdfImageBytesMaxMemory, msg);
}

Future<Uint8List?> _optimizeLogoForCertificatePdf(Uint8List bytes) async {
  final msg = CertPdfLogoOptimizeMessage(bytes: bytes);
  if (kIsWeb) return optimizeCertPdfLogoBytes(msg);
  return compute(optimizeCertPdfLogoBytes, msg);
}

/// Baixa e otimiza logo, fundo e assinaturas uma vez (vários certificados podem reutilizar).
Future<CertPdfResolvedShared> _resolveCertificatePdfShared(
  CertPdfPipelineParams p, {
  void Function(String message, double progress01)? onProgress,
  int currentIndex = 1,
  int totalCount = 1,
}) async {
  void report(String templateMsg, double progress01) {
    final msg = totalCount > 1
        ? templateMsg.replaceFirst('1 de 1', '$currentIndex de $totalCount')
        : templateMsg;
    onProgress?.call(msg, progress01.clamp(0.0, 1.0));
  }

  report('Processando certificado 1 de 1 — carregando fontes e mídia…', 0.06);
  if (kIsWeb) {
    await PublicSiteMediaAuth.ensureWebAnonymousForStorage();
    try {
      await FirebaseAuth.instance.currentUser?.getIdToken();
    } catch (_) {}
  }

  final fontsFuture = _ensureAllCertPdfFonts();

  final tpl = certificateVisualTemplateById(p.visualTemplateId.trim()) ??
      kCertificateVisualTemplates.first;
  final bgFuture = _fetchCertificateTemplateBackgroundBytes(
    tenantId: p.tenantId,
    storageStem: tpl.storageStem,
  );
  final instSigFuture = p.includeInstitutionalPastorSignature &&
          p.useDigitalSignature
      ? _fetchInstitutionalPastorSignatureBytes(p.tenantId)
      : Future<Uint8List?>.value(null);

  final logoUrls = p.logoFetchCandidates.isNotEmpty
      ? p.logoFetchCandidates
      : (isValidImageUrl(p.logoUrlFallback)
          ? [p.logoUrlFallback]
          : <String>[]);

  Future<Uint8List?> fetchFirstLogoBytes() async {
    Uint8List? useIfRealLogo(Uint8List? b) {
      if (b == null || b.length <= 32) return null;
      if (ChurchStorageLayout.isIdentityStructurePlaceholderPng(b)) return null;
      return b;
    }

    if (logoUrls.isNotEmpty) {
      final refreshedUrls = await Future.wait(logoUrls.map((raw) async {
        final u = sanitizeImageUrl(raw.trim());
        if (!isValidImageUrl(u)) return raw.trim();
        if (u.startsWith('http://') || u.startsWith('https://')) {
          if (firebaseStorageMediaUrlLooksLike(u)) {
            try {
              final r = await AppStorageImageService.instance
                  .resolveImageUrl(imageUrl: u)
                  .timeout(
                    const Duration(seconds: 12),
                    onTimeout: () => null,
                  );
              final out = r != null ? sanitizeImageUrl(r) : '';
              if (out.isNotEmpty && isValidImageUrl(out)) return out;
            } catch (_) {}
          }
        }
        return raw.trim();
      }));
      // Só até acertar: o primeiro URL costuma ser o logo oficial — evita N downloads em paralelo.
      for (final candidate in refreshedUrls) {
        final bytes = await _fetchLogoBytesHighRes(candidate);
        final u = useIfRealLogo(bytes);
        if (u != null) return u;
      }
    }
    final tid = p.tenantId.trim();
    if (tid.isEmpty) return null;
    Map<String, dynamic>? tenantHint;
    final nm = p.nomeIgreja.trim();
    if (nm.isNotEmpty) {
      tenantHint = {'name': nm};
    }
    final defaultUrl = await FirebaseStorageService.getChurchLogoDownloadUrl(
      tid,
      tenantData: tenantHint,
    );
    final fallbackFutures = <Future<Uint8List?>>[
      if (defaultUrl != null && defaultUrl.isNotEmpty)
        _fetchLogoBytesHighRes(defaultUrl).then(useIfRealLogo)
      else
        Future<Uint8List?>.value(null),
      _tryChurchLogoBytesDirectFromStorage(
        tid,
        churchNameHint: p.nomeIgreja,
      ).then(useIfRealLogo),
      loadReportPdfBranding(tid)
          .then((br) => useIfRealLogo(br.logoBytes))
          .catchError((Object _, StackTrace __) => null),
    ];
    final triedFb = await Future.wait(fallbackFutures);
    for (final u in triedFb) {
      if (u != null) return u;
    }
    return null;
  }

  final logoFuture = fetchFirstLogoBytes();

  final Future<List<Uint8List?>> sigPackFuture;
  if (p.useDigitalSignature && p.signatoriesForPdf.isNotEmpty) {
    sigPackFuture = Future.wait(
      p.signatoriesForPdf
          .map(
            (s) => _fetchSignatorySignatureBytes(
              tenantId: p.tenantId,
              memberId: s.memberId,
              assinaturaUrlHint: s.assinaturaUrlHint,
            ).timeout(
              const Duration(seconds: 45),
              onTimeout: () => null,
            ),
          )
          .toList(),
    );
  } else {
    sigPackFuture =
        Future<List<Uint8List?>>.value(
            List<Uint8List?>.filled(p.signatoriesForPdf.length, null));
  }

  report('Processando certificado 1 de 1 — baixando imagens em paralelo…', 0.14);

  final packed = await Future.wait<Object?>([
    fontsFuture.then((_) => null),
    logoFuture,
    bgFuture,
    instSigFuture,
    sigPackFuture,
  ]).timeout(
    const Duration(minutes: 3),
    onTimeout: () => throw TimeoutException(
      'O carregamento de fontes, logo ou assinaturas excedeu o tempo limite. '
      'Verifique a rede e tente novamente. Se persistir, desative VPN ou troque de Wi‑Fi.',
    ),
  );
  final logoRaw = packed[1] as Uint8List?;
  final bgRaw = packed[2] as Uint8List?;
  final instSigRaw = packed[3] as Uint8List?;
  final sigRaw = packed[4] as List<Uint8List?>;

  report('Processando certificado 1 de 1 — otimizando fotos…', 0.38);

  const sigMaxW = 800;
  const sigMaxH = 400;

  final logoOptFuture = () {
    if (logoRaw == null) return Future<Uint8List?>.value(null);
    final baseKey = logoUrls.isNotEmpty ? logoUrls.first : p.logoUrlFallback;
    final logoCacheKey =
        baseKey.isNotEmpty ? '$baseKey|certLogoHiResAlpha' : '';
    if (logoCacheKey.isNotEmpty &&
        _logoOptimizedBytesCache.containsKey(logoCacheKey)) {
      return Future<Uint8List?>.value(_logoOptimizedBytesCache[logoCacheKey]);
    }
    return _optimizeLogoForCertificatePdf(logoRaw).then((opt) {
      if (logoCacheKey.isNotEmpty) _logoOptimizedBytesCache[logoCacheKey] = opt;
      return opt;
    });
  }();
  final sigOptFutures = <Future<Uint8List?>>[];
  for (var i = 0; i < sigRaw.length; i++) {
    final b = sigRaw[i];
    if (b == null) {
      sigOptFutures.add(Future<Uint8List?>.value(null));
      continue;
    }
    final signer = i < p.signatoriesForPdf.length ? p.signatoriesForPdf[i] : null;
    final signCacheKey = signer == null
        ? 'sig_$i'
        : '${p.tenantId}|${signer.memberId}|${sanitizeImageUrl(signer.assinaturaUrlHint ?? '')}';
    if (_signatureOptimizedBytesCache.containsKey(signCacheKey)) {
      sigOptFutures
          .add(Future<Uint8List?>.value(_signatureOptimizedBytesCache[signCacheKey]));
      continue;
    }
    sigOptFutures.add(
        _signatureBytesFloatingPipeline(b, signCacheKey, sigMaxW, sigMaxH));
  }

  final bgOptFuture = () async {
    if (bgRaw == null || bgRaw.length <= 64) return null;
    final bgOptKey =
        '${p.tenantId.trim()}|${tpl.storageStem.trim()}|pdfOptV1';
    if (_certificateBackgroundOptimizedCache.containsKey(bgOptKey)) {
      return _certificateBackgroundOptimizedCache[bgOptKey];
    }
    var bgOpt = await _optimizeBackgroundForPrintPdf(bgRaw);
    if (bgOpt == null || bgOpt.length <= 64) {
      bgOpt = bgRaw;
    }
    _certificateBackgroundOptimizedCache[bgOptKey] = bgOpt;
    return bgOpt;
  }();

  final instSigOptFuture = () async {
    if (instSigRaw == null || instSigRaw.length <= 32) return null;
    final tidOpt = p.tenantId.trim();
    if (tidOpt.isNotEmpty &&
        _institutionalPastorSigOptCache.containsKey(tidOpt)) {
      return _institutionalPastorSigOptCache[tidOpt];
    }
    Uint8List? instSigOpt;
    try {
      final piped = kIsWeb
          ? carteirinhaPdfSignaturePipelineSync(instSigRaw)
          : await compute(
              carteirinhaPdfSignaturePipelineForCompute,
              instSigRaw,
            );
      if (piped != null && piped.length > 32) {
        instSigOpt = piped;
      }
    } catch (_) {}
    instSigOpt ??= await _optimizeImageForPdf(instSigRaw, sigMaxW, sigMaxH);
    if (instSigOpt == null || instSigOpt.length <= 32) {
      instSigOpt = instSigRaw;
    }
    if (tidOpt.isNotEmpty) {
      _institutionalPastorSigOptCache[tidOpt] = instSigOpt;
    }
    return instSigOpt;
  }();

  // Logo, assinaturas, fundo e assinatura institucional em paralelo (CPU/isolate).
  final optPacked = await Future.wait<Object?>([
    logoOptFuture,
    Future.wait(sigOptFutures),
    bgOptFuture,
    instSigOptFuture,
  ]).timeout(
    const Duration(minutes: 2),
    onTimeout: () => throw TimeoutException(
      'A otimização de imagens do certificado excedeu o tempo limite. Tente novamente.',
    ),
  );
  Uint8List? logoOpt = optPacked[0] as Uint8List?;
  final sigOpt = optPacked[1] as List<Uint8List?>;
  final Uint8List? bgOpt = optPacked[2] as Uint8List?;
  final Uint8List? instSigOpt = optPacked[3] as Uint8List?;

  /// Certificados da igreja: nunca usar logo institucional da Gestão YAHWEH como fallback.
  if (logoOpt == null || logoOpt.length <= 32) {
    if (logoRaw != null && logoRaw.length > 32) {
      logoOpt = logoRaw;
    }
  }

  report('Processando certificado 1 de 1 — montando página…', 0.62);

  Uint8List? effectiveSignatureBytesForIndex(int i) {
    if (!p.useDigitalSignature || i >= sigOpt.length) return null;
    final o = sigOpt[i];
    if (o != null && o.length > 32) return o;
    if (i < sigRaw.length) {
      final r = sigRaw[i];
      if (r != null && r.length > 32) return r;
    }
    return null;
  }

  final pdfSignatories = <CertSignatoryPdfData>[
    for (var i = 0; i < p.signatoriesForPdf.length; i++)
      CertSignatoryPdfData(
        nome: p.signatoriesForPdf[i].nome,
        cargo: p.signatoriesForPdf[i].cargo,
        signatureImageBytes: effectiveSignatureBytesForIndex(i),
        cpfDigits: p.signatoriesForPdf[i].cpfDigits,
      ),
  ];
  if (p.includeInstitutionalPastorSignature &&
      p.useDigitalSignature &&
      instSigOpt != null &&
      instSigOpt.length > 32) {
    var nomeInst = p.institutionalPastorNome.trim();
    if (nomeInst.isEmpty) {
      nomeInst = p.pastorManual.trim();
    }
    if (nomeInst.isEmpty) {
      nomeInst = 'Assinatura institucional';
    }
    pdfSignatories.add(
      CertSignatoryPdfData(
        nome: nomeInst,
        cargo: p.institutionalPastorCargo.trim().isEmpty
            ? 'Assinatura institucional'
            : p.institutionalPastorCargo.trim(),
        signatureImageBytes: instSigOpt,
        cpfDigits: '',
      ),
    );
  }

  return CertPdfResolvedShared(
    logoOpt: logoOpt,
    bgOpt: bgOpt,
    pdfSignatories: pdfSignatories,
  );
}

/// Expõe a fase de rede/otimização para reutilizar em vários [runCertificatePdfPipeline] (ex.: ZIP em lote).
Future<CertPdfResolvedShared> resolveCertificatePdfShared(
  CertPdfPipelineParams p, {
  void Function(String message, double progress01)? onProgress,
  int currentIndex = 1,
  int totalCount = 1,
}) {
  return _resolveCertificatePdfShared(
    p,
    onProgress: onProgress,
    currentIndex: currentIndex,
    totalCount: totalCount,
  );
}

/// Baixa/otimiza imagens na isolate principal e gera bytes do PDF em [Isolate.run] (mobile/desktop).
Future<Uint8List> runCertificatePdfPipeline(
  CertPdfPipelineParams p, {
  void Function(String message, double progress01)? onProgress,
  int currentIndex = 1,
  int totalCount = 1,
  CertPdfResolvedShared? preResolvedShared,
}) async {
  void report(String templateMsg, double progress01) {
    final msg = totalCount > 1
        ? templateMsg.replaceFirst('1 de 1', '$currentIndex de $totalCount')
        : templateMsg;
    onProgress?.call(msg, progress01.clamp(0.0, 1.0));
  }

  final resolved = preResolvedShared ??
      await _resolveCertificatePdfShared(
        p,
        onProgress: onProgress,
        currentIndex: currentIndex,
        totalCount: totalCount,
      );

  final textoCorpo = p.textoAdicional.trim().isEmpty
      ? p.texto
      : '${p.texto.trim()}\n\n${p.textoAdicional.trim()}';

  final input = CertificatePdfInput(
    titulo: p.titulo,
    subtitulo: p.subtitulo,
    texto: textoCorpo,
    nomeMembro: p.nomeMembro,
    nomeMembroLinha2: p.nomeMembroLinha2,
    cpfFormatado: p.cpfFormatado,
    nomeIgreja: p.nomeIgreja,
    local: p.local,
    issuedDate: p.issuedDate,
    layoutId: p.layoutId.trim().isEmpty ? 'gala_luxo' : p.layoutId.trim(),
    fontStyleId: p.fontStyleId,
    colorPrimaryArgb: p.colorPrimaryArgb,
    colorTextArgb: p.colorTextArgb,
    pastorManual: p.pastorManual,
    cargoManual: p.cargoManual,
    logoBytes: resolved.logoOpt,
    fontMontserratBytes: _fontMontserratCache,
    fontGreatVibesBytes: _fontGreatVibesCache,
    fontUnifrakturBytes: _fontUnifrakturCache,
    fontCinzelDecorativeBytes: _fontCinzelDecorativeCache,
    fontPinyonScriptBytes: _fontPinyonScriptCache,
    fontLibreBaskervilleBytes: _fontLibreBaskervilleCache,
    signatories: resolved.pdfSignatories,
    qrValidationUrl: p.qrValidationUrl,
    backgroundTemplateBytes: resolved.bgOpt,
    visualTemplateId: p.visualTemplateId.trim().isEmpty
        ? 'classico_dourado'
        : p.visualTemplateId.trim(),
    useLuxuryPdfFonts: true,
    useDigitalSignatureStamp: p.useDigitalSignature,
    digitalSignatureDadosLine: p.digitalSignatureDadosLine.trim(),
  );

  report('Processando certificado 1 de 1 — compactando PDF…', 0.88);
  final pdfBytes =
      await runGeraPdfCertificadoIsolate(certificatePdfInputToMap(input));
  report('Concluído', 1.0);
  return pdfBytes;
}

/// Um PDF com várias páginas [gala_luxo] — logo/fundo/fontes/assinaturas descarregados uma vez.
Future<Uint8List> runCertificateGalaLuxoBatchPdfPipeline({
  required CertPdfPipelineParams shared,
  required List<CertPdfGalaBatchMemberSlice> members,
  void Function(String message, double progress01)? onProgress,
}) async {
  if (members.isEmpty) {
    throw ArgumentError('Lista de membros vazia');
  }
  final layout =
      shared.layoutId.trim().isEmpty ? 'gala_luxo' : shared.layoutId.trim();
  if (layout != 'gala_luxo') {
    throw UnsupportedError(
      'PDF único em lote suporta apenas layout gala_luxo',
    );
  }

  void report(String m, double p) => onProgress?.call(m, p.clamp(0.0, 1.0));

  report('Lote: a preparar imagens e fontes…', 0.06);
  final resolved = await _resolveCertificatePdfShared(
    shared,
    onProgress: (msg, pr) => report(msg, 0.06 + pr * 0.54),
  );

  report('Lote: a montar ${members.length} página(s)…', 0.65);
  final maps = <Map<String, dynamic>>[];
  final visualId = shared.visualTemplateId.trim().isEmpty
      ? 'classico_dourado'
      : shared.visualTemplateId.trim();
  for (final slice in members) {
    final textoCorpo = shared.textoAdicional.trim().isEmpty
        ? slice.texto
        : '${slice.texto.trim()}\n\n${shared.textoAdicional.trim()}';
    final titulo = slice.titulo ?? shared.titulo;
    final subtitulo = slice.subtitulo ?? shared.subtitulo;
    final sliceFs = slice.fontStyleId?.trim();
    final fontStyleId = (sliceFs != null && sliceFs.isNotEmpty)
        ? sliceFs
        : shared.fontStyleId;
    final colorPrimaryArgb = slice.colorPrimaryArgb ?? shared.colorPrimaryArgb;
    final colorTextArgb = slice.colorTextArgb ?? shared.colorTextArgb;
    final input = CertificatePdfInput(
      titulo: titulo,
      subtitulo: subtitulo,
      texto: textoCorpo,
      nomeMembro: slice.nomeMembro,
      nomeMembroLinha2: '',
      cpfFormatado: slice.cpfFormatado,
      nomeIgreja: shared.nomeIgreja,
      local: shared.local,
      issuedDate: shared.issuedDate,
      layoutId: 'gala_luxo',
      fontStyleId: fontStyleId,
      colorPrimaryArgb: colorPrimaryArgb,
      colorTextArgb: colorTextArgb,
      pastorManual: shared.pastorManual,
      cargoManual: shared.cargoManual,
      logoBytes: resolved.logoOpt,
      fontMontserratBytes: _fontMontserratCache,
      fontGreatVibesBytes: _fontGreatVibesCache,
      fontUnifrakturBytes: _fontUnifrakturCache,
      fontCinzelDecorativeBytes: _fontCinzelDecorativeCache,
      fontPinyonScriptBytes: _fontPinyonScriptCache,
      fontLibreBaskervilleBytes: _fontLibreBaskervilleCache,
      signatories: resolved.pdfSignatories,
      qrValidationUrl: slice.qrValidationUrl,
      backgroundTemplateBytes: resolved.bgOpt,
      visualTemplateId: visualId,
      useLuxuryPdfFonts: true,
      useDigitalSignatureStamp: shared.useDigitalSignature,
      digitalSignatureDadosLine: shared.digitalSignatureDadosLine.trim(),
    );
    maps.add(certificatePdfInputToMap(input));
  }

  report('Lote: a gerar PDF único…', 0.82);
  final out = await runGeraPdfCertificadoGalaMultiIsolate(maps);
  report('Concluído', 1.0);
  return out;
}
