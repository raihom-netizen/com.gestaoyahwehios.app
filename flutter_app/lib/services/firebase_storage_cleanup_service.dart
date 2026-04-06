import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

import 'package:gestao_yahweh/core/church_storage_layout.dart';
import 'package:gestao_yahweh/core/member_photo_storage_naming.dart';
import 'package:gestao_yahweh/ui/widgets/safe_network_image.dart'
    show
        imageUrlsFromVariantMap,
        isFirebaseStorageHttpUrl,
        isValidImageUrl,
        sanitizeImageUrl;

/// Remove objetos órfãos no Firebase Storage ao trocar ou excluir fotos (membros, patrimônio, logos).
class FirebaseStorageCleanupService {
  FirebaseStorageCleanupService._();

  /// Reapagar `thumb_*` / variantes da extensão **Resize Images**, que muitas vezes só aparecem **após** 90s.
  static const List<int> kResizeExtensionCleanupDelaySeconds =
      <int>[3, 10, 30, 90, 120, 180, 300];

  /// Pasta `membros/{id}/` no Storage: prioriza [authUid] do membro quando existir.
  static String _memberProfileStorageFolderFromMap(
    String memberDocId,
    Map<String, dynamic> data,
  ) {
    final auth =
        (data['authUid'] ?? data['auth_uid'] ?? '').toString().trim();
    if (auth.isNotEmpty) return auth;
    return memberDocId.trim();
  }

  /// Apaga o objeto referenciado por uma URL de download do Firebase Storage (token).
  static Future<void> deleteObjectAtDownloadUrl(String? downloadUrl) async {
    final u = sanitizeImageUrl((downloadUrl ?? '').trim());
    if (u.isEmpty || !isFirebaseStorageHttpUrl(u)) return;
    try {
      await FirebaseStorage.instance.refFromURL(u).delete();
    } catch (e) {
      debugPrint('FirebaseStorageCleanupService.deleteObjectAtDownloadUrl: $e');
    }
  }

  static Future<void> deleteObjectsAtDownloadUrls(Iterable<String?> urls) async {
    for (final x in urls) {
      await deleteObjectAtDownloadUrl(x);
    }
  }

  /// URL https do Storage, `gs://`, ou caminho relativo `igrejas/...`.
  static Future<void> deleteByUrlPathOrGs(String? raw) async {
    var s = sanitizeImageUrl((raw ?? '').trim());
    if (s.isEmpty || s.startsWith('data:')) return;
    try {
      if (isFirebaseStorageHttpUrl(s)) {
        await FirebaseStorage.instance.refFromURL(s).delete();
        return;
      }
      if (s.startsWith('gs://')) {
        await FirebaseStorage.instance.refFromURL(s).delete();
        return;
      }
      if (!s.startsWith('http') && s.contains('/')) {
        await FirebaseStorage.instance.ref(s).delete();
      }
    } catch (e) {
      debugPrint('FirebaseStorageCleanupService.deleteByUrlPathOrGs: $e');
    }
  }

  static Future<void> deleteManyByUrlPathOrGs(Iterable<String?> items) async {
    for (final x in items) {
      await deleteByUrlPathOrGs(x);
    }
  }

  /// Extrai URLs de mapas tipo `photoVariants` / `logoVariants`.
  static List<String> urlsFromVariantMap(dynamic v) => imageUrlsFromVariantMap(v);

  /// Caminhos Storage em mapas `{ thumb: { storagePath, url } }`.
  static List<String> storagePathsFromVariantMap(dynamic v) {
    if (v is! Map) return [];
    final out = <String>[];
    for (final e in v.values) {
      if (e is Map) {
        for (final k in const ['storagePath', 'path']) {
          final p = (e[k] ?? '').toString().trim();
          if (p.isNotEmpty && !out.contains(p)) out.add(p);
        }
      }
    }
    return out;
  }

  /// Lista e apaga **todos** os objetos sob o prefixo (inclui subpastas).
  static Future<void> deleteAllObjectsUnderPrefix(String prefix) async {
    final p = prefix.trim().replaceAll(RegExp(r'/+$'), '');
    if (p.isEmpty) return;
    try {
      await _deleteAllObjectsRecursive(FirebaseStorage.instance.ref(p));
    } catch (e) {
      debugPrint('FirebaseStorageCleanupService.deleteAllObjectsUnderPrefix: $e');
    }
  }

  static Future<void> _deleteAllObjectsRecursive(Reference ref) async {
    final list = await ref.listAll();
    for (final item in list.items) {
      try {
        await item.delete();
      } catch (e) {
        debugPrint('FirebaseStorageCleanupService.delete item ${item.fullPath}: $e');
      }
    }
    for (final sub in list.prefixes) {
      await _deleteAllObjectsRecursive(sub);
    }
  }

  /// Só **foto de perfil** (principal + variantes + URLs no map). Não remove assinatura/digital.
  static Future<void> deleteMemberProfilePhotoArtifactsBeforeReplace({
    required String tenantId,
    required String memberId,
    required Map<String, dynamic> data,
  }) async {
    final tid = tenantId.trim();
    final mid = memberId.trim();
    if (tid.isEmpty || mid.isEmpty) return;
    final storageMid = _memberProfileStorageFolderFromMap(mid, data);

    final refs = <String>[];
    void addRaw(String? s) {
      final t = (s ?? '').trim();
      if (t.isNotEmpty && !refs.contains(t)) refs.add(t);
    }

    for (final k in const [
      'foto_url',
      'FOTO_URL_OU_ID',
      'FOTO',
      'foto',
      'fotoUrl',
      'photoURL',
      'photoUrl',
      'photo',
      'photoStoragePath',
      'fotoStoragePath',
    ]) {
      addRaw(data[k]?.toString());
    }
    refs.addAll(urlsFromVariantMap(data['photoVariants']));
    refs.addAll(storagePathsFromVariantMap(data['photoVariants']));

    await deleteManyByUrlPathOrGs(refs);

    final cpf =
        (data['CPF'] ?? data['cpf'] ?? '').toString().replaceAll(RegExp(r'\D'), '');

    Iterable<String> membrosFixedPaths(String stem) => <String>[
      'igrejas/$tid/membros/$stem/foto_perfil.jpg',
      'igrejas/$tid/membros/$stem/foto_perfil.jpeg',
      'igrejas/$tid/membros/$stem/foto_perfil.png',
      'igrejas/$tid/membros/$stem/foto_perfil_thumb.jpg',
      'igrejas/$tid/membros/$stem/foto_perfil_card.jpg',
      'igrejas/$tid/membros/$stem/foto_perfil_full.jpg',
      'igrejas/$tid/membros/$stem/thumb_foto_perfil.jpg',
      'igrejas/$tid/membros/$stem/thumb_foto_perfil_thumb.jpg',
      'igrejas/$tid/membros/$stem/thumb_foto_perfil_card.jpg',
      'igrejas/$tid/membros/$stem/thumb_foto_perfil_full.jpg',
      'igrejas/$tid/membros/$stem.jpg',
      'igrejas/$tid/membros/$stem.jpeg',
      'igrejas/$tid/membros/$stem.png',
      'igrejas/$tid/membros/${stem}_thumb.jpg',
      'igrejas/$tid/membros/${stem}_card.jpg',
      'igrejas/$tid/membros/${stem}_full.jpg',
    ];

    for (final p in <String>[
      ...membrosFixedPaths(mid),
      if (storageMid != mid) ...membrosFixedPaths(storageMid),
      if (cpf.length == 11 && cpf != mid) ...[
        'igrejas/$tid/membros/$cpf/foto_perfil.jpg',
        'igrejas/$tid/membros/$cpf/foto_perfil_thumb.jpg',
        'igrejas/$tid/membros/$cpf/foto_perfil_card.jpg',
        'igrejas/$tid/membros/$cpf/foto_perfil_full.jpg',
        'igrejas/$tid/membros/$cpf/thumb_foto_perfil.jpg',
        'igrejas/$tid/membros/$cpf/thumb_foto_perfil_thumb.jpg',
        'igrejas/$tid/membros/$cpf/thumb_foto_perfil_card.jpg',
        'igrejas/$tid/membros/$cpf/thumb_foto_perfil_full.jpg',
        'igrejas/$tid/membros/$cpf.jpg',
        'igrejas/$tid/membros/$cpf.jpeg',
        'igrejas/$tid/membros/$cpf.png',
        'igrejas/$tid/membros/${cpf}_thumb.jpg',
        'igrejas/$tid/membros/${cpf}_card.jpg',
        'igrejas/$tid/membros/${cpf}_full.jpg',
      ],
    ]) {
      try {
        await FirebaseStorage.instance.ref(p).delete();
      } catch (_) {}
    }

    try {
      await _deleteAllObjectsRecursive(
          FirebaseStorage.instance.ref('igrejas/$tid/membros/$mid'));
    } catch (_) {}
    if (storageMid != mid) {
      try {
        await _deleteAllObjectsRecursive(
            FirebaseStorage.instance.ref('igrejas/$tid/membros/$storageMid'));
      } catch (_) {}
    }
    if (cpf.length == 11 && cpf != mid) {
      try {
        await _deleteAllObjectsRecursive(
            FirebaseStorage.instance.ref('igrejas/$tid/membros/$cpf'));
      } catch (_) {}
    }

    final nome =
        (data['NOME_COMPLETO'] ?? data['nome'] ?? data['name'] ?? '').toString();
    final auth =
        (data['authUid'] ?? data['uid'] ?? data['userId'] ?? '').toString();
    final stemAtual = MemberPhotoStorageNaming.profileFolderStem(
      nomeCompleto: nome,
      memberDocId: mid,
      authUid: auth.trim().isNotEmpty ? auth.trim() : null,
    );
    try {
      await _deleteAllObjectsRecursive(
          FirebaseStorage.instance.ref('igrejas/$tid/membros/$stemAtual'));
    } catch (_) {}

    for (final p in <String>[
      'igrejas/$tid/members/$mid.jpg',
      'igrejas/$tid/members/$mid.jpeg',
      'igrejas/$tid/members/$mid.png',
      if (cpf.length == 11 && cpf != mid) ...[
        'igrejas/$tid/members/$cpf.jpg',
        'igrejas/$tid/members/$cpf.jpeg',
        'igrejas/$tid/members/$cpf.png',
      ],
    ]) {
      try {
        await FirebaseStorage.instance.ref(p).delete();
      } catch (_) {}
    }
    for (final suffix in <String>['_thumb.jpg', '_card.jpg', '_full.jpg']) {
      try {
        await FirebaseStorage.instance
            .ref('igrejas/$tid/members/$mid$suffix')
            .delete();
      } catch (_) {}
      if (cpf.length == 11 && cpf != mid) {
        try {
          await FirebaseStorage.instance
              .ref('igrejas/$tid/members/$cpf$suffix')
              .delete();
        } catch (_) {}
      }
    }
  }

  /// Nomes fixos gerados pela extensão **Resize Images** (`thumb_foto_perfil.jpg`, etc.) ou legado.
  /// Política: só permanece `foto_perfil.jpg` (e `.jpeg`/`.png` canónicos).
  static const List<String> _memberProfileDerivativeFileNames = [
    'thumb_foto_perfil.jpg',
    'thumb_foto_perfil_thumb.jpg',
    'thumb_foto_perfil_card.jpg',
    'thumb_foto_perfil_full.jpg',
    'foto_perfil_thumb.jpg',
    'foto_perfil_card.jpg',
    'foto_perfil_full.jpg',
  ];

  static Future<void> _deleteFixedMemberProfileDerivativeFiles({
    required String tenantId,
    required String memberFolder,
  }) async {
    final tid = tenantId.trim();
    final stem = memberFolder.trim();
    if (tid.isEmpty || stem.isEmpty) return;
    for (final name in _memberProfileDerivativeFileNames) {
      try {
        await FirebaseStorage.instance
            .ref('igrejas/$tid/membros/$stem/$name')
            .delete();
      } catch (_) {}
    }
  }

  /// Após gravar `foto_perfil.jpg`: limpa miniaturas imediatamente e **repete** com atraso
  /// (a extensão Resize Images do Firebase cria `thumb_*` segundos depois).
  static void scheduleCleanupAfterMemberProfilePhotoUpload({
    required String tenantId,
    required String memberId,
  }) {
    Future<void> run() => deleteGeneratedMemberProfileThumbnails(
          tenantId: tenantId,
          memberId: memberId,
        );
    unawaited(run());
    for (final secs in kResizeExtensionCleanupDelaySeconds) {
      unawaited(
        Future<void>.delayed(Duration(seconds: secs), run),
      );
    }
  }

  static bool _isCanonicalGestorProfileFile(String name) {
    final n = name.toLowerCase();
    return n == 'foto_perfil.jpg' ||
        n == 'foto_perfil.jpeg' ||
        n == 'foto_perfil.png';
  }

  /// Em `igrejas/{tenant}/gestor/`: mantém só `foto_perfil.*`; remove `thumb_foto_perfil.jpg` e variantes da extensão Resize Images.
  static Future<void> deleteGeneratedGestorProfileThumbnails({
    required String tenantId,
  }) async {
    final tid = tenantId.trim();
    if (tid.isEmpty) return;
    final base = '${ChurchStorageLayout.churchRoot(tid)}/gestor';
    for (final name in _memberProfileDerivativeFileNames) {
      try {
        await FirebaseStorage.instance.ref('$base/$name').delete();
      } catch (_) {}
    }
    try {
      final list = await FirebaseStorage.instance.ref(base).listAll();
      for (final item in list.items) {
        if (_isCanonicalGestorProfileFile(item.name)) continue;
        final n = item.name.toLowerCase();
        if (n.contains('thumb') ||
            n.contains('resized_') ||
            n.contains('_card.') ||
            n.contains('_full.')) {
          try {
            await item.delete();
          } catch (e) {
            debugPrint(
                'FirebaseStorageCleanupService.deleteGestorThumb ${item.fullPath}: $e');
          }
        }
      }
    } catch (e) {
      debugPrint(
          'FirebaseStorageCleanupService.deleteGeneratedGestorProfileThumbnails: $e');
    }
  }

  /// Após upload em `gestor/foto_perfil.jpg` (cadastro igreja / espelho do gestor).
  static void scheduleCleanupAfterGestorProfilePhotoUpload({
    required String tenantId,
  }) {
    Future<void> run() => deleteGeneratedGestorProfileThumbnails(
          tenantId: tenantId,
        );
    unawaited(run());
    for (final secs in kResizeExtensionCleanupDelaySeconds) {
      unawaited(
        Future<void>.delayed(Duration(seconds: secs), run),
      );
    }
  }

  /// Miniaturas típicas ao lado de `logo_igreja.png` / `assinatura.png` (extensão Resize Images).
  static const List<String> _churchConfigDerivativeFileNames = [
    'thumb_logo_igreja.jpg',
    'thumb_logo_igreja.png',
    'thumb_logo_igreja_thumb.jpg',
    'thumb_logo_igreja_card.jpg',
    'thumb_logo_igreja_full.jpg',
    'logo_igreja_thumb.jpg',
    'logo_igreja_card.jpg',
    'logo_igreja_full.jpg',
    'thumb_assinatura.jpg',
    'thumb_assinatura.png',
    'thumb_assinatura_thumb.jpg',
    'assinatura_thumb.jpg',
    'assinatura_card.jpg',
    'assinatura_full.jpg',
  ];

  static bool _isCanonicalChurchConfigFile(String name) {
    final n = name.toLowerCase();
    return n == 'logo_igreja.png' ||
        n == 'logo_igreja.jpg' ||
        n == 'logo_igreja.jpeg' ||
        n == 'assinatura.png' ||
        n == 'assinatura.jpg' ||
        n == 'assinatura.jpeg';
  }

  /// Após upload em `igrejas/{tenant}/configuracoes/`: mantém só ficheiros canónicos (logo/assinatura), apaga `thumb_*` e variantes.
  static Future<void> deleteGeneratedChurchConfiguracoesThumbnails({
    required String tenantId,
  }) async {
    final tid = tenantId.trim();
    if (tid.isEmpty) return;
    final base = 'igrejas/$tid/configuracoes';
    for (final name in _churchConfigDerivativeFileNames) {
      try {
        await FirebaseStorage.instance.ref('$base/$name').delete();
      } catch (_) {}
    }
    try {
      final list = await FirebaseStorage.instance.ref(base).listAll();
      for (final item in list.items) {
        if (_isCanonicalChurchConfigFile(item.name)) continue;
        final n = item.name.toLowerCase();
        if (n.contains('thumb') ||
            n.contains('resized_') ||
            n.contains('_card.') ||
            n.contains('_full.')) {
          try {
            await item.delete();
          } catch (e) {
            debugPrint(
                'FirebaseStorageCleanupService.deleteChurchConfigThumb ${item.fullPath}: $e');
          }
        }
      }
    } catch (e) {
      debugPrint(
          'FirebaseStorageCleanupService.deleteGeneratedChurchConfiguracoesThumbnails: $e');
    }
  }

  /// Igual ao perfil do membro: a extensão cria `thumb_*` segundos depois do PUT.
  static void scheduleCleanupAfterChurchConfigImageUpload({
    required String tenantId,
  }) {
    Future<void> run() => deleteGeneratedChurchConfiguracoesThumbnails(
          tenantId: tenantId,
        );
    unawaited(run());
    for (final secs in kResizeExtensionCleanupDelaySeconds) {
      unawaited(
        Future<void>.delayed(Duration(seconds: secs), run),
      );
    }
  }

  /// Miniaturas ao lado de `capa_aviso.jpg` / `galeria_XX.jpg` (extensão Resize Images).
  static const List<String> _avisoPostCapaDerivativeFileNames = [
    'thumb_capa_aviso.jpg',
    'thumb_capa_aviso_thumb.jpg',
    'thumb_capa_aviso_card.jpg',
    'thumb_capa_aviso_full.jpg',
    'capa_aviso_thumb.jpg',
    'capa_aviso_card.jpg',
    'capa_aviso_full.jpg',
  ];

  static bool _isCanonicalAvisoPostFile(String name) {
    final n = name.toLowerCase();
    if (n == 'capa_aviso.jpg' ||
        n == 'capa_aviso.jpeg' ||
        n == 'capa_aviso.png') {
      return true;
    }
    return RegExp(r'^galeria_\d{2}\.(jpg|jpeg|png)$').hasMatch(n);
  }

  /// Em `igrejas/{tenant}/avisos/{postId}/`: mantém só `capa_aviso.*` e `galeria_XX.*`; apaga `thumb_*` e variantes.
  static Future<void> deleteGeneratedAvisoPostThumbnails({
    required String tenantId,
    required String postDocId,
  }) async {
    final tid = tenantId.trim();
    final pid = postDocId.trim();
    if (tid.isEmpty || pid.isEmpty) return;
    final base = '${ChurchStorageLayout.churchRoot(tid)}/${ChurchStorageLayout.kSegAvisos}/$pid';
    for (final name in _avisoPostCapaDerivativeFileNames) {
      try {
        await FirebaseStorage.instance.ref('$base/$name').delete();
      } catch (_) {}
    }
    for (final name in _avisoPostGaleriaDerivativeFileNames) {
      try {
        await FirebaseStorage.instance.ref('$base/$name').delete();
      } catch (_) {}
    }
    try {
      final list = await FirebaseStorage.instance.ref(base).listAll();
      for (final item in list.items) {
        if (_isCanonicalAvisoPostFile(item.name)) continue;
        final n = item.name.toLowerCase();
        if (n.contains('thumb') ||
            n.contains('resized_') ||
            n.contains('_card.') ||
            n.contains('_full.')) {
          try {
            await item.delete();
          } catch (e) {
            debugPrint(
                'FirebaseStorageCleanupService.deleteAvisoThumb ${item.fullPath}: $e');
          }
        }
      }
    } catch (e) {
      debugPrint(
          'FirebaseStorageCleanupService.deleteGeneratedAvisoPostThumbnails: $e');
    }
  }

  /// A extensão Firebase "Resize Images" pode criar `thumb_capa_aviso.jpg` após o PUT.
  /// O app só usa `capa_aviso.jpg` / `galeria_XX.*` — este agendamento remove derivados.
  /// Para **não** gerar miniaturas: no Console Firebase, exclua `igrejas/*/avisos/**` do caminho da extensão ou desative-a para avisos.
  static void scheduleCleanupAfterAvisoPostImageUpload({
    required String tenantId,
    required String postDocId,
  }) {
    Future<void> run() => deleteGeneratedAvisoPostThumbnails(
          tenantId: tenantId,
          postDocId: postDocId,
        );
    unawaited(run());
    for (final secs in kResizeExtensionCleanupDelaySeconds) {
      unawaited(
        Future<void>.delayed(Duration(seconds: secs), run),
      );
    }
  }

  /// Derivados típicos de `galeria_XX.jpg` nos avisos (slots 01–30).
  static final List<String> _avisoPostGaleriaDerivativeFileNames =
      List<String>.unmodifiable(_buildGaleriaJjDerivativeNames(30));

  /// Derivados típicos de `galeria_XX.jpg` nos eventos (lista + editor: até 25 fotos após a capa).
  static final List<String> _eventPostGaleriaDerivativeFileNames =
      List<String>.unmodifiable(_buildGaleriaJjDerivativeNames(25));

  static List<String> _buildGaleriaJjDerivativeNames(int maxSlotInclusive) {
    final out = <String>[];
    for (var s = 1; s <= maxSlotInclusive; s++) {
      final n = s.toString().padLeft(2, '0');
      out.addAll([
        'thumb_galeria_$n.jpg',
        'thumb_galeria_${n}_thumb.jpg',
        'thumb_galeria_${n}_card.jpg',
        'thumb_galeria_${n}_full.jpg',
        'galeria_${n}_thumb.jpg',
        'galeria_${n}_card.jpg',
        'galeria_${n}_full.jpg',
      ]);
    }
    return out;
  }

  static const List<String> _eventPostBannerDerivativeFileNames = [
    'thumb_banner_evento.jpg',
    'thumb_banner_evento_thumb.jpg',
    'thumb_banner_evento_card.jpg',
    'thumb_banner_evento_full.jpg',
    'banner_evento_thumb.jpg',
    'banner_evento_card.jpg',
    'banner_evento_full.jpg',
  ];

  static bool _isCanonicalEventPostFile(String name) {
    final n = name.toLowerCase();
    if (n == 'banner_evento.jpg' ||
        n == 'banner_evento.jpeg' ||
        n == 'banner_evento.png') {
      return true;
    }
    return RegExp(r'^galeria_\d{2}\.(jpg|jpeg|png)$').hasMatch(n);
  }

  /// `igrejas/{tenant}/eventos/{postId}/`: mantém `banner_evento.*` e `galeria_XX.*`.
  /// Não afeta `eventos/videos/` (miniatura funcional `*_vN_thumb.jpg` do vídeo hospedado).
  static Future<void> deleteGeneratedEventPostThumbnails({
    required String tenantId,
    required String postDocId,
  }) async {
    final tid = tenantId.trim();
    final pid = postDocId.trim();
    if (tid.isEmpty || pid.isEmpty) return;
    final base =
        '${ChurchStorageLayout.churchRoot(tid)}/${ChurchStorageLayout.kSegEventos}/$pid';
    for (final name in _eventPostBannerDerivativeFileNames) {
      try {
        await FirebaseStorage.instance.ref('$base/$name').delete();
      } catch (_) {}
    }
    for (final name in _eventPostGaleriaDerivativeFileNames) {
      try {
        await FirebaseStorage.instance.ref('$base/$name').delete();
      } catch (_) {}
    }
    try {
      final list = await FirebaseStorage.instance.ref(base).listAll();
      for (final item in list.items) {
        if (_isCanonicalEventPostFile(item.name)) continue;
        final n = item.name.toLowerCase();
        if (n.contains('thumb') ||
            n.contains('resized_') ||
            n.contains('_card.') ||
            n.contains('_full.')) {
          try {
            await item.delete();
          } catch (e) {
            debugPrint(
                'FirebaseStorageCleanupService.deleteEventPostThumb ${item.fullPath}: $e');
          }
        }
      }
    } catch (e) {
      debugPrint(
          'FirebaseStorageCleanupService.deleteGeneratedEventPostThumbnails: $e');
    }
  }

  static void scheduleCleanupAfterEventPostImageUpload({
    required String tenantId,
    required String postDocId,
  }) {
    Future<void> run() => deleteGeneratedEventPostThumbnails(
          tenantId: tenantId,
          postDocId: postDocId,
        );
    unawaited(run());
    for (final secs in kResizeExtensionCleanupDelaySeconds) {
      unawaited(Future<void>.delayed(Duration(seconds: secs), run));
    }
  }

  static bool _isCanonicalEventTemplateCoverFile(String fileName, String stem) {
    final n = fileName.toLowerCase();
    final s = stem.toLowerCase();
    return n == '$s.jpg' || n == '$s.jpeg' || n == '$s.png';
  }

  /// Capa em `eventos/templates/{id}.jpg` — remove `thumb_*` gerados pela extensão.
  static Future<void> deleteGeneratedEventTemplateCoverThumbnails({
    required String tenantId,
    required String templateUniqueId,
  }) async {
    final tid = tenantId.trim();
    if (tid.isEmpty) return;
    final fullPath =
        ChurchStorageLayout.eventTemplateCoverPath(tid, templateUniqueId);
    if (fullPath.isEmpty) return;
    final slash = fullPath.lastIndexOf('/');
    if (slash < 0) return;
    final dir = fullPath.substring(0, slash);
    final file = fullPath.substring(slash + 1);
    final stem = file.replaceAll(
      RegExp(r'\.(jpe?g|png)$', caseSensitive: false),
      '',
    );
    if (stem.isEmpty) return;
    final fixed = <String>[
      'thumb_$stem.jpg',
      'thumb_${stem}_thumb.jpg',
      'thumb_${stem}_card.jpg',
      'thumb_${stem}_full.jpg',
      '${stem}_thumb.jpg',
      '${stem}_card.jpg',
      '${stem}_full.jpg',
    ];
    for (final name in fixed) {
      try {
        await FirebaseStorage.instance.ref('$dir/$name').delete();
      } catch (_) {}
    }
    try {
      final list = await FirebaseStorage.instance.ref(dir).listAll();
      for (final item in list.items) {
        if (_isCanonicalEventTemplateCoverFile(item.name, stem)) continue;
        final n = item.name.toLowerCase();
        final sl = stem.toLowerCase();
        if (!n.startsWith(sl) && !n.startsWith('thumb_$sl')) continue;
        if (n.contains('thumb') ||
            n.contains('resized_') ||
            n.contains('_card.') ||
            n.contains('_full.')) {
          try {
            await item.delete();
          } catch (e) {
            debugPrint(
                'FirebaseStorageCleanupService.eventTemplateThumb ${item.fullPath}: $e');
          }
        }
      }
    } catch (e) {
      debugPrint(
          'FirebaseStorageCleanupService.deleteGeneratedEventTemplateCoverThumbnails: $e');
    }
  }

  static void scheduleCleanupAfterEventTemplateCoverUpload({
    required String tenantId,
    required String templateUniqueId,
  }) {
    Future<void> run() => deleteGeneratedEventTemplateCoverThumbnails(
          tenantId: tenantId,
          templateUniqueId: templateUniqueId,
        );
    unawaited(run());
    for (final secs in kResizeExtensionCleanupDelaySeconds) {
      unawaited(Future<void>.delayed(Duration(seconds: secs), run));
    }
  }

  static const List<String> _cartaoMembroLogoDerivativeFileNames = [
    'thumb_logo.jpg',
    'thumb_logo_thumb.jpg',
    'thumb_logo_card.jpg',
    'thumb_logo_full.jpg',
    'logo_thumb.jpg',
    'logo_card.jpg',
    'logo_full.jpg',
  ];

  /// `cartao_membro/logo.jpg` — remove `thumb_*` da extensão Resize Images.
  static Future<void> deleteGeneratedCartaoMembroLogoThumbnails({
    required String tenantId,
  }) async {
    final tid = tenantId.trim();
    if (tid.isEmpty) return;
    final base = ChurchStorageLayout.cartaoMembroMediaPrefix(tid);
    for (final name in _cartaoMembroLogoDerivativeFileNames) {
      try {
        await FirebaseStorage.instance.ref('$base/$name').delete();
      } catch (_) {}
    }
    try {
      final list = await FirebaseStorage.instance.ref(base).listAll();
      for (final item in list.items) {
        final n = item.name.toLowerCase();
        if (n == 'logo.jpg' || n == 'logo.jpeg' || n == 'logo.png') {
          continue;
        }
        if (n.contains('thumb') ||
            n.contains('resized_') ||
            n.contains('_card.') ||
            n.contains('_full.')) {
          try {
            await item.delete();
          } catch (e) {
            debugPrint(
                'FirebaseStorageCleanupService.cartaoMembroThumb ${item.fullPath}: $e');
          }
        }
      }
    } catch (e) {
      debugPrint(
          'FirebaseStorageCleanupService.deleteGeneratedCartaoMembroLogoThumbnails: $e');
    }
  }

  static void scheduleCleanupAfterCartaoMembroLogoUpload({
    required String tenantId,
  }) {
    Future<void> run() => deleteGeneratedCartaoMembroLogoThumbnails(
          tenantId: tenantId,
        );
    unawaited(run());
    for (final secs in kResizeExtensionCleanupDelaySeconds) {
      unawaited(Future<void>.delayed(Duration(seconds: secs), run));
    }
  }

  /// Apaga o par vídeo + miniatura canónico do slot (0 ou 1) antes de substituir ou ao remover do editor.
  static Future<void> deleteEventHostedVideoSlotFiles({
    required String tenantId,
    required String postDocId,
    required int videoSlot,
  }) async {
    final tid = tenantId.trim();
    final pid = postDocId.trim();
    if (tid.isEmpty || pid.isEmpty) return;
    final slot = videoSlot.clamp(0, 1);
    final paths = <String>[
      ChurchStorageLayout.eventHostedVideoMp4Path(tid, pid, slot),
      ChurchStorageLayout.eventHostedVideoThumbPath(tid, pid, slot),
    ];
    for (final p in paths) {
      try {
        await FirebaseStorage.instance.ref(p).delete();
      } catch (_) {}
    }
  }

  /// Remove ficheiros gerados por extensões (Resize Images) ou legado `*_thumb`/`*_card`/`*_full`
  /// na pasta `igrejas/{tenant}/membros/{memberId}/`, mantendo `foto_perfil.jpg` (e `.png`/`.jpeg` canónicos).
  static Future<void> deleteGeneratedMemberProfileThumbnails({
    required String tenantId,
    required String memberId,
  }) async {
    final tid = tenantId.trim();
    final mid = memberId.trim();
    if (tid.isEmpty || mid.isEmpty) return;
    await _deleteFixedMemberProfileDerivativeFiles(
      tenantId: tid,
      memberFolder: mid,
    );
    final prefixRef = FirebaseStorage.instance.ref('igrejas/$tid/membros/$mid');
    bool isCanonicalMain(String name) {
      final n = name.toLowerCase();
      return n == 'foto_perfil.jpg' ||
          n == 'foto_perfil.jpeg' ||
          n == 'foto_perfil.png';
    }

    bool shouldDeleteGenerated(String name) {
      final n = name.toLowerCase();
      if (isCanonicalMain(n)) return false;
      // Extensões / legado: qualquer objeto com "thumb" no nome (exceto canónico acima).
      if (n.contains('thumb')) return true;
      if (n.contains('foto_perfil_thumb') ||
          n.contains('foto_perfil_card') ||
          n.contains('foto_perfil_full')) {
        return true;
      }
      if (n.contains('_thumb.') ||
          n.contains('_card.') ||
          n.contains('_full.')) {
        return true;
      }
      if (n.contains('resized_')) return true;
      return false;
    }

    try {
      final list = await prefixRef.listAll();
      for (final item in list.items) {
        if (!shouldDeleteGenerated(item.name)) continue;
        try {
          await item.delete();
        } catch (e) {
          debugPrint(
              'FirebaseStorageCleanupService.deleteThumbs ${item.fullPath}: $e');
        }
      }
    } catch (e) {
      debugPrint(
          'FirebaseStorageCleanupService.deleteGeneratedMemberProfileThumbnails: $e');
    }
  }

  /// Logo dedicada dos certificados: URLs/paths do Firestore + limpa pasta (remove timestamps antigos).
  static Future<void> deleteCertificadoDedicatedLogoArtifacts({
    required String tenantId,
    Map<String, dynamic>? certConfig,
  }) async {
    final tid = tenantId.trim();
    if (tid.isEmpty) return;
    final c = certConfig ?? {};
    final refs = <String>[];
    void add(String? s) {
      final t = (s ?? '').trim();
      if (t.isNotEmpty && !refs.contains(t)) refs.add(t);
    }

    add(c['logoUrl']?.toString());
    add(c['logoPath']?.toString());
    add(c['storagePath']?.toString());
    refs.addAll(urlsFromVariantMap(c['logoVariants']));
    refs.addAll(storagePathsFromVariantMap(c['logoVariants']));
    await deleteManyByUrlPathOrGs(refs);
    await deleteAllObjectsUnderPrefix(
        ChurchStorageLayout.certificadoDedicatedMediaPrefix(tid));
    await deleteAllObjectsUnderPrefix('certificado_logos/$tid');
  }

  /// Limpa caches de imagem (lista / detalhe) após troca de URL.
  static Future<void> evictImageCaches(String? url) async {
    final u = sanitizeImageUrl((url ?? '').trim());
    if (u.isEmpty || !isValidImageUrl(u)) return;
    try {
      await CachedNetworkImage.evictFromCache(u);
    } catch (e) {
      debugPrint('FirebaseStorageCleanupService.evictImageCaches cached: $e');
    }
    try {
      PaintingBinding.instance.imageCache.evict(NetworkImage(u));
    } catch (e) {
      debugPrint('FirebaseStorageCleanupService.evictImageCaches network: $e');
    }
  }

  /// Fotos, assinatura, digital e variantes conhecidas — além de caminhos fixos comuns.
  static Future<void> deleteMemberRelatedFiles({
    required String tenantId,
    required String memberId,
    required Map<String, dynamic> data,
  }) async {
    final urls = <String>{};
    void add(String? u) {
      final s = sanitizeImageUrl((u ?? '').trim());
      if (s.isNotEmpty) urls.add(s);
    }

    for (final k in const [
      'foto_url',
      'FOTO_URL_OU_ID',
      'fotoUrl',
      'photoURL',
      'photoUrl',
      'assinaturaUrl',
      'carteirinhaAssinaturaUrl',
      'imagemDigitalUrl',
      'IMAGEM_DIGITAL_URL',
      'digitalImagemUrl',
    ]) {
      add(data[k]?.toString());
    }
    urls.addAll(urlsFromVariantMap(data['photoVariants']));

    await deleteManyByUrlPathOrGs(urls);

    final tid = tenantId.trim();
    final mid = memberId.trim();
    if (tid.isEmpty || mid.isEmpty) return;
    final storageMid = _memberProfileStorageFolderFromMap(mid, data);

    final paths = <String>[
      'igrejas/$tid/membros/$mid/foto_perfil.jpg',
      'igrejas/$tid/membros/$mid/foto_perfil_thumb.jpg',
      'igrejas/$tid/membros/$mid/foto_perfil_card.jpg',
      'igrejas/$tid/membros/$mid/foto_perfil_full.jpg',
      'igrejas/$tid/membros/$mid/thumb_foto_perfil.jpg',
      'igrejas/$tid/membros/$mid/thumb_foto_perfil_thumb.jpg',
      'igrejas/$tid/membros/$mid/thumb_foto_perfil_card.jpg',
      'igrejas/$tid/membros/$mid/thumb_foto_perfil_full.jpg',
      'igrejas/$tid/membros/$mid.jpg',
      'igrejas/$tid/membros/$mid.jpeg',
      'igrejas/$tid/membros/$mid.png',
      'igrejas/$tid/membros/${mid}_assinatura.png',
      'igrejas/$tid/membros/${mid}_digital.png',
      'igrejas/$tid/membros/${mid}_gestor.jpg',
      'igrejas/$tid/membros/${mid}_thumb.jpg',
      'igrejas/$tid/membros/${mid}_card.jpg',
      'igrejas/$tid/membros/${mid}_full.jpg',
    ];
    if (storageMid != mid) {
      paths.addAll([
        'igrejas/$tid/membros/$storageMid/foto_perfil.jpg',
        'igrejas/$tid/membros/$storageMid/foto_perfil_thumb.jpg',
        'igrejas/$tid/membros/$storageMid/foto_perfil_card.jpg',
        'igrejas/$tid/membros/$storageMid/foto_perfil_full.jpg',
        'igrejas/$tid/membros/$storageMid/thumb_foto_perfil.jpg',
        'igrejas/$tid/membros/$storageMid/thumb_foto_perfil_thumb.jpg',
        'igrejas/$tid/membros/$storageMid/thumb_foto_perfil_card.jpg',
        'igrejas/$tid/membros/$storageMid/thumb_foto_perfil_full.jpg',
        'igrejas/$tid/membros/$storageMid.jpg',
        'igrejas/$tid/membros/$storageMid.jpeg',
        'igrejas/$tid/membros/$storageMid.png',
        'igrejas/$tid/membros/${storageMid}_assinatura.png',
        'igrejas/$tid/membros/${storageMid}_digital.png',
        'igrejas/$tid/membros/${storageMid}_gestor.jpg',
        'igrejas/$tid/membros/${storageMid}_thumb.jpg',
        'igrejas/$tid/membros/${storageMid}_card.jpg',
        'igrejas/$tid/membros/${storageMid}_full.jpg',
      ]);
    }
    final cpf = (data['CPF'] ?? data['cpf'] ?? '').toString().replaceAll(RegExp(r'\D'), '');
    if (cpf.length == 11 && cpf != mid) {
      paths.addAll([
        'igrejas/$tid/membros/$cpf/foto_perfil.jpg',
        'igrejas/$tid/membros/$cpf/foto_perfil_thumb.jpg',
        'igrejas/$tid/membros/$cpf/foto_perfil_card.jpg',
        'igrejas/$tid/membros/$cpf/foto_perfil_full.jpg',
        'igrejas/$tid/membros/$cpf/thumb_foto_perfil.jpg',
        'igrejas/$tid/membros/$cpf/thumb_foto_perfil_thumb.jpg',
        'igrejas/$tid/membros/$cpf/thumb_foto_perfil_card.jpg',
        'igrejas/$tid/membros/$cpf/thumb_foto_perfil_full.jpg',
        'igrejas/$tid/membros/$cpf.jpg',
        'igrejas/$tid/membros/${cpf}_thumb.jpg',
        'igrejas/$tid/membros/${cpf}_card.jpg',
        'igrejas/$tid/membros/${cpf}_full.jpg',
        'igrejas/$tid/membros/${cpf}_gestor.jpg',
      ]);
    }
    for (final p in paths) {
      try {
        await FirebaseStorage.instance.ref(p).delete();
      } catch (_) {}
    }

    // Pasta legada em inglês (mesmo membro — um arquivo por id).
    for (final p in <String>[
      'igrejas/$tid/members/$mid.jpg',
      'igrejas/$tid/members/$mid.jpeg',
      'igrejas/$tid/members/$mid.png',
      if (cpf.length == 11 && cpf != mid) ...[
        'igrejas/$tid/members/$cpf.jpg',
        'igrejas/$tid/members/$cpf.jpeg',
        'igrejas/$tid/members/$cpf.png',
      ],
    ]) {
      try {
        await FirebaseStorage.instance.ref(p).delete();
      } catch (_) {}
    }
  }

  /// Remove foto principal + variantes do slot [0–4] de um bem de patrimônio (pasta `…/patrimonio/{id}/`).
  static Future<void> deletePatrimonioSlotArtifacts({
    required String tenantId,
    required String itemDocId,
    required int slot,
  }) async {
    if (slot < 0 || slot > 4) return;
    final tid = tenantId.trim();
    final iid = itemDocId.trim();
    if (tid.isEmpty || iid.isEmpty) return;
    final folder = ChurchStorageLayout.patrimonioItemFolderPrefix(tid, iid);
    final base =
        ChurchStorageLayout.patrimonioPhotoBaseWithoutExt(tid, iid, slot);
    final safe = ChurchStorageLayout.patrimonioStorageSafeItemId(iid);
    final paths = <String>[
      '$base.jpg',
      '${base}_thumb.jpg',
      '${base}_card.jpg',
      '${base}_full.jpg',
      // Legado: ficheiros planos `igrejas/.../patrimonio/{id}_{slot}*.jpg`
      'igrejas/$tid/patrimonio/${iid}_$slot.jpg',
      'igrejas/$tid/patrimonio/${iid}_${slot}_thumb.jpg',
      'igrejas/$tid/patrimonio/${iid}_${slot}_card.jpg',
      'igrejas/$tid/patrimonio/${iid}_${slot}_full.jpg',
      if (safe != iid) ...[
        'igrejas/$tid/patrimonio/${safe}_$slot.jpg',
        'igrejas/$tid/patrimonio/${safe}_${slot}_thumb.jpg',
        'igrejas/$tid/patrimonio/${safe}_${slot}_card.jpg',
        'igrejas/$tid/patrimonio/${safe}_${slot}_full.jpg',
      ],
      // Legado: primeira foto era `foto_item.jpg` (substituída por `galeria_01.jpg`).
      if (slot == 0) ...[
        '$folder/foto_item.jpg',
        '$folder/foto_item.jpeg',
        '$folder/foto_item.png',
        '$folder/thumb_foto_item.jpg',
        '$folder/thumb_foto_item_thumb.jpg',
        '$folder/thumb_foto_item_card.jpg',
        '$folder/thumb_foto_item_full.jpg',
      ],
    ];
    await Future.wait(paths.map((p) async {
      try {
        await FirebaseStorage.instance.ref(p).delete();
      } catch (_) {}
    }));
  }

  static bool _isCanonicalPatrimonioItemFile(String name) {
    final n = name.toLowerCase();
    /// [foto_item] e [galeria_01–04] antigos: não apagar até o utilizador voltar a gravar (nova galeria só 01–05).
    if (n == 'foto_item.jpg' ||
        n == 'foto_item.jpeg' ||
        n == 'foto_item.png') {
      return true;
    }
    return RegExp(r'^galeria_0[1-5]\.(jpg|jpeg|png)$').hasMatch(n);
  }

  /// Derivados típicos da extensão **Resize Images** junto a `galeria_01.jpg` … `galeria_05.jpg`.
  static final List<String> _patrimonioGaleriaDerivativeFileNames =
      List<String>.unmodifiable(_buildPatrimonioGaleriaDerivativeFileNames());

  static List<String> _buildPatrimonioGaleriaDerivativeFileNames() {
    final out = <String>[];
    for (var s = 1; s <= 5; s++) {
      final n = s.toString().padLeft(2, '0');
      out.addAll([
        'thumb_galeria_$n.jpg',
        'thumb_galeria_${n}_thumb.jpg',
        'thumb_galeria_${n}_card.jpg',
        'thumb_galeria_${n}_full.jpg',
        'galeria_${n}_thumb.jpg',
        'galeria_${n}_card.jpg',
        'galeria_${n}_full.jpg',
      ]);
    }
    return out;
  }

  static Future<void> _deleteFixedPatrimonioGaleriaDerivativeFiles({
    required String tenantId,
    required String itemFolderPrefix,
  }) async {
    final tid = tenantId.trim();
    final prefix = itemFolderPrefix.trim();
    if (tid.isEmpty || prefix.isEmpty) return;
    for (final name in _patrimonioGaleriaDerivativeFileNames) {
      try {
        await FirebaseStorage.instance.ref('$prefix/$name').delete();
      } catch (_) {}
    }
  }

  /// Na pasta do bem: mantém canónicos; apaga `thumb_*`, `galeria_06+`, etc.
  static Future<void> deleteGeneratedPatrimonioItemThumbnails({
    required String tenantId,
    required String itemDocId,
  }) async {
    final tid = tenantId.trim();
    final iid = itemDocId.trim();
    if (tid.isEmpty || iid.isEmpty) return;
    final prefix = ChurchStorageLayout.patrimonioItemFolderPrefix(tid, iid);
    await _deleteFixedPatrimonioGaleriaDerivativeFiles(
      tenantId: tid,
      itemFolderPrefix: prefix,
    );
    try {
      final list = await FirebaseStorage.instance.ref(prefix).listAll();
      for (final item in list.items) {
        if (_isCanonicalPatrimonioItemFile(item.name)) continue;
        final n = item.name.toLowerCase();
        var drop = false;
        if (n.contains('thumb') ||
            n.contains('resized_') ||
            n.contains('_card.') ||
            n.contains('_full.')) {
          drop = true;
        } else if (RegExp(r'^galeria_(0[6-9]|[1-9]\d)\.').hasMatch(n)) {
          drop = true;
        }
        if (!drop) continue;
        try {
          await item.delete();
        } catch (e) {
          debugPrint(
              'FirebaseStorageCleanupService.patrimonioFolder ${item.fullPath}: $e');
        }
      }
    } catch (e) {
      debugPrint(
          'FirebaseStorageCleanupService.deleteGeneratedPatrimonioItemThumbnails: $e');
    }
  }

  /// Na raiz `igrejas/…/patrimonio/`, remove só legado plano `{id}_{slot}_thumb|card|full.*` (não apaga `{id}_0.jpg` ainda usado).
  static Future<void> deleteFlatLegacyPatrimonioDerivativesForItem({
    required String tenantId,
    required String itemDocId,
  }) async {
    final tid = tenantId.trim();
    final raw = itemDocId.trim();
    if (tid.isEmpty || raw.isEmpty) return;
    final safe = ChurchStorageLayout.patrimonioStorageSafeItemId(raw);
    final alt = raw == safe
        ? RegExp.escape(raw)
        : '${RegExp.escape(raw)}|${RegExp.escape(safe)}';
    final re = RegExp(
      '^($alt)_\\d+_(thumb|card|full)\\.(jpg|jpeg|png|webp)\$',
      caseSensitive: false,
    );
    try {
      final list =
          await FirebaseStorage.instance.ref('igrejas/$tid/patrimonio').listAll();
      for (final item in list.items) {
        if (!re.hasMatch(item.name)) continue;
        try {
          await item.delete();
        } catch (e) {
          debugPrint(
              'FirebaseStorageCleanupService.flatPatrimonio ${item.fullPath}: $e');
        }
      }
    } catch (e) {
      debugPrint(
          'FirebaseStorageCleanupService.deleteFlatLegacyPatrimonioDerivativesForItem: $e');
    }
  }

  static Future<void> _patrimonioCleanupRun({
    required String tenantId,
    required String itemDocId,
  }) async {
    await deleteGeneratedPatrimonioItemThumbnails(
        tenantId: tenantId, itemDocId: itemDocId);
    await deleteFlatLegacyPatrimonioDerivativesForItem(
        tenantId: tenantId, itemDocId: itemDocId);
  }

  /// Após upload em `patrimonio/{id}/`: remove miniaturas da extensão Resize e ficheiros legados planos.
  /// Para não gerar `thumb_*`: exclua `igrejas/*/patrimonio/**` na extensão Resize Images (Console Firebase).
  static void scheduleCleanupAfterPatrimonioItemPhotoUpload({
    required String tenantId,
    required String itemDocId,
  }) {
    Future<void> run() => _patrimonioCleanupRun(
          tenantId: tenantId,
          itemDocId: itemDocId,
        );
    unawaited(run());
    for (final secs in kResizeExtensionCleanupDelaySeconds) {
      unawaited(Future<void>.delayed(Duration(seconds: secs), run));
    }
  }

  /// Remove logos legadas sob `igrejas/{id}/logo/` e `branding/`, e `configuracoes/logo_igreja.jpg`.
  /// Não apaga `configuracoes/assinatura.*` nem `configuracoes/logo_igreja.png` (substituído no upload).
  static Future<void> deleteLegacyChurchLogoMediaUnderTenant(String tenantId) async {
    final tid = tenantId.trim();
    if (tid.isEmpty) return;
    await deleteAllObjectsUnderPrefix('igrejas/$tid/logo');
    for (final p in ChurchStorageLayout.legacyLogoObjectPaths(tid)) {
      try {
        await FirebaseStorage.instance.ref(p).delete();
      } catch (_) {}
    }
    try {
      await FirebaseStorage.instance
          .ref(ChurchStorageLayout.churchIdentityLogoPathJpgLegacy(tid))
          .delete();
    } catch (_) {}
    await deleteOrphanChurchLogosInMembersFolder(tid);
  }

  /// Logos antigas em `igrejas/{id}/members/logo_<timestamp>.jpg` (EcoFire / fluxos antigos).
  /// A identidade canónica passa a ser `configuracoes/logo_igreja.png`.
  static Future<void> deleteOrphanChurchLogosInMembersFolder(String tenantId) async {
    final tid = tenantId.trim();
    if (tid.isEmpty) return;
    try {
      final ref = FirebaseStorage.instance.ref('igrejas/$tid/members');
      final list = await ref.listAll();
      for (final item in list.items) {
        final n = item.name.toLowerCase();
        if (n.startsWith('logo_') &&
            (n.endsWith('.jpg') ||
                n.endsWith('.jpeg') ||
                n.endsWith('.png') ||
                n.endsWith('.webp'))) {
          try {
            await item.delete();
          } catch (e) {
            debugPrint(
                'FirebaseStorageCleanupService.deleteOrphanChurchLogos: ${item.fullPath} $e');
          }
        }
      }
    } catch (e) {
      debugPrint(
          'FirebaseStorageCleanupService.deleteOrphanChurchLogosInMembersFolder: $e');
    }
  }
}
