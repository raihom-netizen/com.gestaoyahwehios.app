import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';

import 'package:gestao_yahweh/core/church_storage_layout.dart';
import 'package:gestao_yahweh/core/member_photo_storage_naming.dart';
import 'package:gestao_yahweh/core/public_site_media_auth.dart';
import 'media_handler_service.dart';

/// Serviço de upload de mídia para Firebase Storage em alta resolução (Full HD).
/// Faz: seleção → compressão (90%, 1920×1080) → upload → retorna URL com token (getDownloadURL).
/// A URL retornada deve ser a única salva no Firestore para evitar "foto indisponível".
class FirebaseStorageService {
  FirebaseStorageService._();
  static final FirebaseStorageService instance = FirebaseStorageService._();

  final FirebaseStorage _storage = FirebaseStorage.instance;

  /// Caminho completo no bucket (`igrejas/.../foto.jpg`), não encadear [Reference.child]
  /// com pastas que contêm `/` — em alguns SDKs isso grava no sítio errado.
  Reference _refFullObjectPath(String folderPath, String fileName) {
    final dir = folderPath.trim().replaceAll(RegExp(r'/+$'), '');
    final name = fileName.trim().replaceAll(RegExp(r'^/+'), '');
    final full = dir.isEmpty ? name : '$dir/$name';
    return _storage.ref(full);
  }

  static final Map<String, String?> _memberPhotoUrlCache = {};
  static const int _cacheMaxSize = 200;

  static final Map<String, String?> _churchLogoUrlCache = {};
  static const int _churchLogoCacheMax = 64;

  /// Resolve nome da igreja para montar `logo/logo_{nome}_{id}.jpg` quando [tenantData] não veio preenchido.
  static Future<String?> _churchDisplayNameForLogoPath(
    String tenantId,
    Map<String, dynamic>? tenantData,
  ) async {
    var name = (tenantData != null
            ? (tenantData['name'] ?? tenantData['nome'] ?? '')
            : '')
        .toString()
        .trim();
    if (name.isNotEmpty) return name;
    final tid = tenantId.trim();
    if (tid.isEmpty) return null;
    try {
      final doc =
          await FirebaseFirestore.instance.collection('igrejas').doc(tid).get();
      if (!doc.exists) return null;
      final d = doc.data();
      name = (d?['name'] ?? d?['nome'] ?? '').toString().trim();
      return name.isEmpty ? null : name;
    } catch (_) {
      return null;
    }
  }

  /// Caminhos de objeto a testar (`configuracoes/logo_igreja.png` primeiro, depois legados `logo/` e `branding/`).
  static Future<List<String>> getChurchLogoCandidateStoragePaths(
    String tenantId, {
    Map<String, dynamic>? tenantData,
  }) async {
    final tid = tenantId.trim();
    if (tid.isEmpty) return const [];
    final churchName = await _churchDisplayNameForLogoPath(tid, tenantData);
    return ChurchStorageLayout.churchLogoObjectPathsToTry(tid, churchName);
  }

  /// Logo institucional quando o Firestore não tem URL — tenta identidade em `configuracoes/`, depois legados.
  static Future<String?> getChurchLogoDownloadUrl(
    String tenantId, {
    Map<String, dynamic>? tenantData,
  }) async {
    final tid = tenantId.trim();
    if (tid.isEmpty) return null;
    final hit = _churchLogoUrlCache[tid];
    if (hit != null && hit.isNotEmpty) return hit;
    if (kIsWeb) {
      await PublicSiteMediaAuth.ensureWebAnonymousForStorage();
      try {
        await FirebaseAuth.instance.currentUser?.getIdToken();
      } catch (_) {}
    }
    final paths = await getChurchLogoCandidateStoragePaths(tid, tenantData: tenantData);
    const timeout = Duration(seconds: 12);
    for (final p in paths) {
      try {
        final ref = FirebaseStorage.instance.ref(p);
        final url = await ref.getDownloadURL().timeout(timeout, onTimeout: () => '');
        if (url.isNotEmpty) {
          while (_churchLogoUrlCache.length >= _churchLogoCacheMax) {
            _churchLogoUrlCache.remove(_churchLogoUrlCache.keys.first);
          }
          _churchLogoUrlCache[tid] = url;
          return url;
        }
      } catch (e) {
        debugPrint('FirebaseStorageService.getChurchLogoDownloadUrl ($p): $e');
      }
    }
    // Não cachear falha: upload/regras/rede podem passar a permitir leitura na sessão seguinte.
    return null;
  }

  static void invalidateChurchLogoCache(String tenantId) {
    final t = tenantId.trim();
    if (t.isEmpty) return;
    _churchLogoUrlCache.remove(t);
  }

  /// Materializa `igrejas/{id}/configuracoes/` no bucket com [logo_igreja.png] mínimo **só se** ainda não
  /// existir PNG nem JPG canónicos. O upload pelo cadastro substitui o mesmo path (overwrite).
  /// Não grava Firestore — o painel só fica OK após URL/`logoPath` no doc ou logo real (> [kChurchIdentityLogoMinBytesForFirestoreSync]).
  static Future<void> ensureChurchConfigFolderPlaceholderIfAbsent(
      String tenantId) async {
    final tid = tenantId.trim();
    if (tid.isEmpty) return;
    final pngPath = ChurchStorageLayout.churchIdentityLogoPath(tid);
    final jpgPath = ChurchStorageLayout.churchIdentityLogoPathJpgLegacy(tid);
    for (final p in [pngPath, jpgPath]) {
      try {
        await FirebaseStorage.instance.ref(p).getMetadata();
        return;
      } catch (_) {}
    }
    if (kIsWeb) {
      await PublicSiteMediaAuth.ensureWebAnonymousForStorage();
      try {
        await FirebaseAuth.instance.currentUser?.getIdToken();
      } catch (_) {}
    }
    try {
      await FirebaseStorage.instance.ref(pngPath).putData(
            ChurchStorageLayout.kMinimalTransparentIdentityPng,
            SettableMetadata(contentType: 'image/png'),
          );
      invalidateChurchLogoCache(tid);
    } catch (e) {
      debugPrint(
          'FirebaseStorageService.ensureChurchConfigFolderPlaceholderIfAbsent: $e');
    }
  }

  static final Map<String, String?> _pastorSigConfigUrlCache = {};

  /// Assinatura do pastor em `igrejas/{id}/configuracoes/assinatura.png` (ou `.jpg`).
  static Future<String?> getPastorSignatureConfigDownloadUrl(
      String tenantId) async {
    final tid = tenantId.trim();
    if (tid.isEmpty) return null;
    if (_pastorSigConfigUrlCache.containsKey(tid)) {
      return _pastorSigConfigUrlCache[tid];
    }
    if (kIsWeb) {
      await PublicSiteMediaAuth.ensureWebAnonymousForStorage();
      try {
        await FirebaseAuth.instance.currentUser?.getIdToken();
      } catch (_) {}
    }
    const timeout = Duration(seconds: 10);
    for (final p in ChurchStorageLayout.pastorSignatureConfigPaths(tid)) {
      try {
        final ref = FirebaseStorage.instance.ref(p);
        final url = await ref.getDownloadURL().timeout(timeout, onTimeout: () => '');
        if (url.isNotEmpty) {
          _pastorSigConfigUrlCache[tid] = url;
          return url;
        }
      } catch (e) {
        debugPrint('FirebaseStorageService.getPastorSignatureConfigDownloadUrl ($p): $e');
      }
    }
    _pastorSigConfigUrlCache[tid] = null;
    return null;
  }

  /// Após upload/remoção de `configuracoes/assinatura.png` no cadastro da igreja.
  static void invalidatePastorSignatureCache(String tenantId) {
    final t = tenantId.trim();
    if (t.isEmpty) return;
    _pastorSigConfigUrlCache.remove(t);
  }

  /// Caminho canónico: `igrejas/{tenant}/membros/{idDocumento}/foto_perfil.jpg` (sobrescreve ao trocar foto).
  /// [nomeCompleto] / [authUid] ignorados — mantidos só para compatibilidade de chamadas antigas.
  static String memberProfilePhotoPath({
    required String tenantId,
    required String memberDocId,
    String? nomeCompleto,
    String? authUid,
  }) {
    return ChurchStorageLayout.memberCanonicalProfilePhotoPath(
        tenantId, memberDocId);
  }

  /// URL com token para a foto padrão do membro em Storage (`igrejas/{tenant}/membros/{id}.jpg` legado
  /// ou `.../foto_perfil.jpg`). Usado quando a URL no Firestore está vazia
  /// ou expirada — padrão alinhado ao Ecofire (fallback após falha de rede/cache).
  /// Cache em memória para evitar chamadas repetidas (lista de membros, modal, etc.).
  static Future<String?> getMemberProfilePhotoDownloadUrl({
    required String tenantId,
    required String memberId,
    String? cpfDigits,
    /// Quando o doc em `membros` usa outro id (ex.: CPF) mas a foto foi salva com `authUid`.
    String? authUid,
    /// [NOME_COMPLETO] para pasta `PrimeiroNome_uid` (padrão atual).
    String? nomeCompleto,
  }) async {
    final tid = tenantId.trim();
    final mid = memberId.trim();
    if (tid.isEmpty || mid.isEmpty) return null;
    final cpfNorm = (cpfDigits ?? '').replaceAll(RegExp(r'\D'), '');
    final authNorm = (authUid ?? '').trim();
    final nomeNorm = (nomeCompleto ?? '').trim();
    final stemNamed = MemberPhotoStorageNaming.profileFolderStem(
      nomeCompleto: nomeNorm,
      memberDocId: mid,
      authUid: authNorm.isNotEmpty ? authNorm : null,
    );
    final cacheKey =
        '$tid:$mid:$cpfNorm:${authNorm.isEmpty ? '-' : authNorm}:$stemNamed';
    if (_memberPhotoUrlCache.containsKey(cacheKey)) {
      return _memberPhotoUrlCache[cacheKey];
    }
    if (kIsWeb) {
      await PublicSiteMediaAuth.ensureWebAnonymousForStorage();
      try {
        await FirebaseAuth.instance.currentUser?.getIdToken();
      } catch (_) {}
    }
    final cpf = cpfNorm;
    final orderedStems = <String>[];
    void addStem(String s) {
      final x = s.trim();
      if (x.isEmpty) return;
      if (!orderedStems.contains(x)) orderedStems.add(x);
    }

    addStem(stemNamed);
    addStem(mid);
    if (cpf.length == 11) addStem(cpf);
    if (authNorm.isNotEmpty && authNorm != mid && authNorm != cpf) {
      addStem(authNorm);
    }

    final canon = ChurchStorageLayout.memberCanonicalProfilePhotoPath(tid, mid);
    final paths = <String>[
      canon,
      '${canon.substring(0, canon.length - 4)}.jpeg',
      '${canon.substring(0, canon.length - 4)}.png',
    ];
    for (final stem in orderedStems) {
      paths.addAll([
        'igrejas/$tid/membros/$stem/foto_perfil.jpg',
        'igrejas/$tid/membros/$stem/foto_perfil.jpeg',
        'igrejas/$tid/membros/$stem/foto_perfil.png',
        'igrejas/$tid/membros/$stem/foto_perfil_full.jpg',
        'igrejas/$tid/membros/$stem/foto_perfil_card.jpg',
        'igrejas/$tid/membros/$stem/foto_perfil_thumb.jpg',
        'igrejas/$tid/membros/${stem}_gestor.jpg',
        'igrejas/$tid/membros/$stem.jpg',
        'igrejas/$tid/membros/$stem.jpeg',
        'igrejas/$tid/membros/$stem.png',
        'igrejas/$tid/membros/${stem}_full.jpg',
        'igrejas/$tid/membros/${stem}_card.jpg',
        'igrejas/$tid/membros/${stem}_thumb.jpg',
        'igrejas/$tid/members/$stem.jpg',
        'igrejas/$tid/members/$stem.jpeg',
        'igrejas/$tid/members/$stem.png',
      ]);
    }
    const timeout = Duration(seconds: 8);
    for (final path in paths) {
      try {
        final ref = FirebaseStorage.instance.ref(path);
        final url = await ref.getDownloadURL().timeout(timeout);
        if (url.isNotEmpty) {
          while (_memberPhotoUrlCache.length >= _cacheMaxSize) {
            _memberPhotoUrlCache.remove(_memberPhotoUrlCache.keys.first);
          }
          _memberPhotoUrlCache[cacheKey] = url;
          return url;
        }
      } catch (e) {
        debugPrint('FirebaseStorageService.getMemberProfilePhotoDownloadUrl ($path): $e');
      }
    }
    // Não cachear falha: antes ficava null permanente e a lista nunca tentava de novo
    // (rede lenta, regras recém-publicadas, upload concluído depois).
    return null;
  }

  /// Após novo upload de foto do membro ou gestor — evita URL antiga em cache na lista/detalhes.
  static void invalidateMemberPhotoCache({
    required String tenantId,
    String? memberId,
  }) {
    final t = tenantId.trim();
    if (t.isEmpty) return;
    final m = memberId?.trim();
    if (m != null && m.isNotEmpty) {
      _memberPhotoUrlCache.removeWhere((k, _) => k.startsWith('$t:$m:'));
    } else {
      _memberPhotoUrlCache.removeWhere((k, _) => k.startsWith('$t:'));
    }
  }

  /// URL de `igrejas/{tenant}/gestor/foto_perfil.jpg` (espelho da foto do gestor no painel).
  static Future<String?> getGestorPublicMirrorPhotoUrl(String tenantId) async {
    final tid = tenantId.trim();
    if (tid.isEmpty) return null;
    if (kIsWeb) {
      await PublicSiteMediaAuth.ensureWebAnonymousForStorage();
      try {
        await FirebaseAuth.instance.currentUser?.getIdToken();
      } catch (_) {}
    }
    final path = ChurchStorageLayout.gestorPublicProfilePhotoPath(tid);
    try {
      final ref = FirebaseStorage.instance.ref(path);
      final url = await ref
          .getDownloadURL()
          .timeout(const Duration(seconds: 10), onTimeout: () => '');
      return url.isNotEmpty ? url : null;
    } catch (e) {
      debugPrint(
          'FirebaseStorageService.getGestorPublicMirrorPhotoUrl ($path): $e');
      return null;
    }
  }

  /// Caminho típico: "igrejas/{igrejaId}/membros" ou "members/{tenantId}" ou "tenants/{tenantId}/eventos".
  static const int quality = 90;
  static const int maxWidth = 1920;
  static const int maxHeight = 1080;
  static const int _uploadAttempts = 3;

  Future<String?> _putDataWithRetry(
    Reference ref,
    Uint8List bytes, {
    required String contentType,
  }) async {
    Object? lastError;
    for (var i = 1; i <= _uploadAttempts; i++) {
      try {
        final task = ref.putData(
          bytes,
          SettableMetadata(
            contentType: contentType,
            cacheControl: 'public, max-age=31536000',
          ),
        );
        final snap = await task;
        return await snap.ref.getDownloadURL();
      } catch (e) {
        lastError = e;
        if (i < _uploadAttempts) {
          await Future.delayed(Duration(milliseconds: 300 * i));
        }
      }
    }
    debugPrint('FirebaseStorageService._putDataWithRetry: $lastError');
    return null;
  }

  /// Seleciona imagem da galeria, comprime em alta resolução e envia para [folderPath].
  /// Retorna a URL pública com token (getDownloadURL) para salvar no Firestore.
  /// Sempre use essa URL no banco — evita erro de fotos não carregando.
  Future<String?> uploadChurchMedia(
    String folderPath, {
    ImageSource source = ImageSource.gallery,
    String? fileName,
  }) async {
    try {
      final XFile? picked = await MediaHandlerService.instance.pickAndProcessImage(
        source: source,
        imageQuality: quality,
        minWidth: maxWidth,
        minHeight: maxHeight,
      );
      if (picked == null) return null;

      final bytes = await picked.readAsBytes();
      final name = fileName ?? '${DateTime.now().millisecondsSinceEpoch}.jpg';
      final ref = _refFullObjectPath(folderPath, name);
      return await _putDataWithRetry(
        ref,
        bytes,
        contentType: picked.mimeType ?? 'image/jpeg',
      );
    } catch (e) {
      debugPrint('FirebaseStorageService.uploadChurchMedia: $e');
      return null;
    }
  }

  /// Upload a partir de bytes (ex.: já processado por MediaHandlerService em outro fluxo).
  /// Retorna a URL com token para salvar no Firestore.
  Future<String?> uploadBytes(
    String folderPath,
    Uint8List bytes, {
    String? fileName,
    String contentType = 'image/jpeg',
  }) async {
    try {
      if (kIsWeb) {
        await PublicSiteMediaAuth.ensureWebAnonymousForStorage();
        try {
          await FirebaseAuth.instance.currentUser?.getIdToken();
        } catch (_) {}
      }
      final name = fileName ?? '${DateTime.now().millisecondsSinceEpoch}.jpg';
      final ref = _refFullObjectPath(folderPath, name);
      return await _putDataWithRetry(ref, bytes, contentType: contentType);
    } catch (e) {
      debugPrint('FirebaseStorageService.uploadBytes: $e');
      return null;
    }
  }
}
