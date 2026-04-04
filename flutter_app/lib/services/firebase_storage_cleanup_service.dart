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

    for (final p in <String>[
      'igrejas/$tid/membros/$mid/foto_perfil.jpg',
      'igrejas/$tid/membros/$mid/foto_perfil.jpeg',
      'igrejas/$tid/membros/$mid/foto_perfil.png',
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
      'igrejas/$tid/membros/${mid}_thumb.jpg',
      'igrejas/$tid/membros/${mid}_card.jpg',
      'igrejas/$tid/membros/${mid}_full.jpg',
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

  /// Remove ficheiros gerados por extensões (Resize Images) ou legado `*_thumb`/`*_card`/`*_full`
  /// na pasta `igrejas/{tenant}/membros/{memberId}/`, mantendo `foto_perfil.jpg` (e `.png`/`.jpeg` canónicos).
  static Future<void> deleteGeneratedMemberProfileThumbnails({
    required String tenantId,
    required String memberId,
  }) async {
    final tid = tenantId.trim();
    final mid = memberId.trim();
    if (tid.isEmpty || mid.isEmpty) return;
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

  /// Remove foto principal + variantes do slot [0–4] de um bem de patrimônio (caminho estável `…/id_slot.jpg`).
  static Future<void> deletePatrimonioSlotArtifacts({
    required String tenantId,
    required String itemDocId,
    required int slot,
  }) async {
    if (slot < 0 || slot > 4) return;
    final tid = tenantId.trim();
    final iid = itemDocId.trim();
    if (tid.isEmpty || iid.isEmpty) return;
    final base =
        ChurchStorageLayout.patrimonioPhotoBaseWithoutExt(tid, iid, slot);
    final paths = <String>[
      '$base.jpg',
      '${base}_thumb.jpg',
      '${base}_card.jpg',
      '${base}_full.jpg',
      // Legado: ficheiro plano `igrejas/.../patrimonio/{itemId}_{slot}.jpg`
      'igrejas/$tid/patrimonio/${iid}_$slot.jpg',
    ];
    await Future.wait(paths.map((p) async {
      try {
        await FirebaseStorage.instance.ref(p).delete();
      } catch (_) {}
    }));
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
