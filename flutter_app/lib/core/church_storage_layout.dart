import 'dart:typed_data';

import 'package:gestao_yahweh/core/church_logo_storage_naming.dart';
import 'package:gestao_yahweh/core/yahweh_performance_v4.dart';
import 'package:gestao_yahweh/core/repositories/church_repository.dart';

/// Layout canônico do **Firebase Storage** por igreja (tenant = id do doc em `igrejas/{id}`).
///
/// ## Árvore consolidada (novos uploads)
/// ```
/// igrejas/{churchId}/
/// ├── membros/fotos/ + membros/thumbs/
/// ├── avisos/imagens/
/// ├── eventos/imagens/ + eventos/videos/ + eventos/thumbs/
/// ├── patrimonio/imagens/ + patrimonio/thumbs/
/// ├── financeiro/YYYY_MM/   (comprovantes de lançamentos)
/// └── chat_media/{images|videos|audio|docs}/ + chat_media/thumbs/
/// ```
///
/// Firestore guarda **só URLs**; listas usam **thumbs**; full só quando necessário.
/// Ver `.cursor/rules/igrejas-arquitetura-final.mdc`.
///
/// ## Módulos de mídia
/// | Módulo | Storage canónico |
/// |--------|------------------|
/// | membros | `membros/fotos/{id}.webp`, `membros/thumbs/{id}.webp` |
/// | avisos | `avisos/imagens/{postId}_*.webp` |
/// | eventos | `eventos/imagens/`, `eventos/videos/`, `eventos/thumbs/` |
/// | patrimonio | `patrimonio/imagens/`, `patrimonio/thumbs/` |
/// | financeiro | `financeiro/YYYY_MM/{lancamentoId}.jpg` (comprovantes) |
/// | chat_media | `chat_media/{tipo}/`, `chat_media/thumbs/` |
///
/// Legado (leitura): `membros/{id}/foto_perfil.jpg`, pastas por post/item — helpers `*Legacy()`.
///
/// Outros nós: `configuracoes/`, `logo/`, `cartao_membro/`, `certificados/`, `eventos/templates/`.
abstract final class ChurchStorageLayout {
  ChurchStorageLayout._();

  /// Tamanho mínimo (bytes) para tratar o ficheiro em `logo_igreja.png` como logo real e sincronizar URL no Firestore.
  /// Abaixo disso considera-se placeholder de estrutura (1×1 transparente).
  static const int kChurchIdentityLogoMinBytesForFirestoreSync = 400;

  /// PNG 1×1 transparente — materializa `configuracoes/` quando ainda não existe logo canónica.
  /// `true` se [b] for exatamente o PNG mínimo usado só para materializar a pasta no bucket.
  static bool isIdentityStructurePlaceholderPng(Uint8List b) {
    final p = kMinimalTransparentIdentityPng;
    if (b.length != p.length) return false;
    for (var i = 0; i < p.length; i++) {
      if (b[i] != p[i]) return false;
    }
    return true;
  }

  static final Uint8List kMinimalTransparentIdentityPng = Uint8List.fromList(<int>[
    0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D,
    0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
    0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, 0x89, 0x00, 0x00, 0x00,
    0x0A, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00,
    0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00, 0x00, 0x00, 0x00, 0x49,
    0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
  ]);

  /// Segmentos canônicos (nomes de pasta) sob `igrejas/{id}/`.
  static const String kSegMembros = 'membros';
  static const String kSegNoticias = 'noticias';
  static const String kSegAvisos = 'avisos';
  /// Cartão de membro (logo própria da carteirinha, não a logo institucional em `configuracoes/`).
  static const String kSegCartaoMembro = 'cartao_membro';
  /// Mídia dedicada ao módulo de certificados (logo própria; fundos HD ficam em [kSegCertificadosTemplates]).
  static const String kSegCertificadosMidia = 'certificados';
  static const String kSegEventos = 'eventos';
  static const String kSegPatrimonio = 'patrimonio';
  static const String kSegChatMedia = 'chat_media';
  static const String kSegImagens = 'imagens';
  static const String kSegVideos = 'videos';
  static const String kSegThumbs = 'thumbs';
  static const String kSegLogo = 'logo';

  /// Configurações diversas (ex.: assinatura do pastor para carteirinha digital).
  static const String kSegConfiguracoes = 'configuracoes';

  /// Capa no site de divulgação (aba Master «Igrejas cliente») — mesmo prefixo `igrejas/{tenantId}/` que o painel da igreja.
  static const String kSegMarketingDestaque = 'marketing_destaque';

  /// Comprovantes financeiros: `financeiro/YYYY_MM/{lancamentoId}.ext`
  static const String kSegFinanceiro = 'financeiro';

  /// Path canónico de comprovante (Controle Total): `/financeiro/ano_mes/id_registro`.
  static String financeComprovantePath({
    required String tenantId,
    required String lancamentoId,
    DateTime? referenceDate,
    String ext = 'jpg',
  }) {
    final tid = tenantId.trim();
    final id = _safeDocId(lancamentoId);
    final dt = referenceDate ?? DateTime.now();
    final ym = '${dt.year}_${dt.month.toString().padLeft(2, '0')}';
    final safeExt = ext.replaceAll('.', '').trim().isEmpty ? 'jpg' : ext.replaceAll('.', '');
    return '${churchRoot(tid)}/$kSegFinanceiro/${ym}/$id.$safeExt';
  }

  /// Materializa `igrejas/{id}/financeiro/` no bucket (placeholder PNG 1×1).
  static String financeiroFolderPlaceholderPath(String tenantId) {
    final tid = tenantId.trim();
    if (tid.isEmpty) return '';
    return '${churchRoot(tid)}/$kSegFinanceiro/_structure/placeholder.png';
  }

  /// Legado: `igrejas/{id}/comprovantes/{lancamentoId}.jpg`.
  static String financeComprovantePathLegacy({
    required String tenantId,
    required String lancamentoId,
    String ext = 'jpg',
  }) {
    final tid = tenantId.trim();
    final id = _safeDocId(lancamentoId);
    final safeExt = ext.replaceAll('.', '').trim().isEmpty ? 'jpg' : ext.replaceAll('.', '');
    return '${churchRoot(tid)}/comprovantes/$id.$safeExt';
  }

  static String churchRoot(String tenantId) {
    final tid = ChurchRepository.churchId(tenantId.trim());
    final id = tid.isNotEmpty ? tid : tenantId.trim();
    return 'igrejas/$id';
  }

  /// `igrejas/{tenantId}/marketing_destaque/capa.jpg` (único ficheiro; sem `thumb_*`).
  static String marketingClienteShowcaseCapaPath(String tenantId) {
    final tid = tenantId.trim();
    if (tid.isEmpty) return '';
    return '${churchRoot(tid)}/$kSegMarketingDestaque/capa.jpg';
  }

  static String _safeDocId(String id) {
    var s = id.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_').trim();
    s = s.replaceAll(RegExp(r'_+'), '_');
    return s.isEmpty ? 'doc' : s;
  }

  /// Foto principal canónica: `membros/fotos/{memberId}.webp` (1024×1024 @ 80%).
  static String memberProfilePhotoPath(
      String tenantId, String memberDocId) {
    final tid = tenantId.trim();
    final mid = _safeDocId(memberDocId);
    return '${churchRoot(tid)}/$kSegMembros/fotos/$mid.webp';
  }

  /// Miniatura canónica: `membros/thumbs/{memberId}.webp` (200×200 @ 70%).
  static String memberProfileThumbPath(
      String tenantId, String memberDocId) {
    final tid = tenantId.trim();
    final mid = _safeDocId(memberDocId);
    return '${churchRoot(tid)}/$kSegMembros/thumbs/$mid.webp';
  }

  /// Alias — use [memberProfilePhotoPath].
  static String memberCanonicalProfilePhotoPath(
          String tenantId, String memberDocId) =>
      memberProfilePhotoPath(tenantId, memberDocId);

  /// Alias — use [memberProfileThumbPath].
  static String memberProfileThumbWebpPath(
          String tenantId, String memberDocId) =>
      memberProfileThumbPath(tenantId, memberDocId);

  /// Legado: `membros/{memberDocId}/foto_perfil.jpg`.
  static String memberCanonicalProfilePhotoPathLegacy(
      String tenantId, String memberDocId) {
    final tid = tenantId.trim();
    final mid = _safeDocId(memberDocId);
    return '${churchRoot(tid)}/$kSegMembros/$mid/foto_perfil.jpg';
  }

  /// Miniatura típica da extensão **Resize Images** (legado).
  static String memberProfileResizeThumbPath(
      String tenantId, String memberDocId) {
    final tid = tenantId.trim();
    final mid = _safeDocId(memberDocId);
    return '${churchRoot(tid)}/$kSegMembros/$mid/thumb_foto_perfil.jpg';
  }

  /// Legado V4: `membros/{id}/profile_thumb.webp`.
  static String memberProfileThumbWebpPathLegacy(
      String tenantId, String memberDocId) {
    final tid = tenantId.trim();
    final mid = _safeDocId(memberDocId);
    return '${churchRoot(tid)}/$kSegMembros/$mid/${YahwehPerformanceV4.profileThumbFile}';
  }

  /// Legado V4: `membros/{id}/profile_medium.webp`.
  static String memberProfileMediumWebpPath(
      String tenantId, String memberDocId) {
    final tid = tenantId.trim();
    final mid = _safeDocId(memberDocId);
    return '${churchRoot(tid)}/$kSegMembros/$mid/${YahwehPerformanceV4.profileMediumFile}';
  }

  /// Post **evento** — canónico: `eventos/imagens/{postId}_banner.webp` (+ `galeria_XX`).
  static String eventPostPhotoPath(
      String tenantId, String postDocId, int slotIndex) {
    final tid = tenantId.trim();
    final pid = _safeDocId(postDocId);
    final root = '${churchRoot(tid)}/$kSegEventos/$kSegImagens';
    if (slotIndex <= 0) return '$root/${pid}_banner.webp';
    final n = slotIndex.toString().padLeft(2, '0');
    return '$root/${pid}_galeria_$n.webp';
  }

  /// Legado: `eventos/{postId}/banner_evento.jpg` …
  static String eventPostPhotoPathLegacy(
      String tenantId, String postDocId, int slotIndex) {
    final tid = tenantId.trim();
    final pid = _safeDocId(postDocId);
    final root = '${churchRoot(tid)}/$kSegEventos/$pid';
    if (slotIndex <= 0) return '$root/banner_evento.jpg';
    final n = slotIndex.toString().padLeft(2, '0');
    return '$root/galeria_$n.jpg';
  }

  /// Vídeo MP4 — `eventos/videos/{postId}_v0.mp4` (slot 0 ou 1).
  static String eventHostedVideoMp4Path(
      String tenantId, String postDocId, int videoSlot) {
    final tid = tenantId.trim();
    final pid = _safeDocId(postDocId);
    final s = videoSlot.clamp(0, 1);
    return '${churchRoot(tid)}/$kSegEventos/videos/${pid}_v$s.mp4';
  }

  /// Miniatura do vídeo — `eventos/thumbs/{postId}_v0.webp`.
  static String eventHostedVideoThumbPath(
      String tenantId, String postDocId, int videoSlot) {
    final tid = tenantId.trim();
    final pid = _safeDocId(postDocId);
    final s = videoSlot.clamp(0, 1);
    return '${churchRoot(tid)}/$kSegEventos/$kSegThumbs/${pid}_v$s.webp';
  }

  /// Legado: thumb junto ao vídeo em `eventos/videos/`.
  static String eventHostedVideoThumbPathLegacy(
      String tenantId, String postDocId, int videoSlot) {
    final tid = tenantId.trim();
    final pid = _safeDocId(postDocId);
    final s = videoSlot.clamp(0, 1);
    return '${churchRoot(tid)}/$kSegEventos/$kSegVideos/${pid}_v${s}_thumb.jpg';
  }

  /// Post **aviso** — canónico: `avisos/imagens/{postId}_capa.webp` (+ galeria).
  static String avisoPostPhotoPath(
      String tenantId, String postDocId, int slotIndex) {
    final tid = tenantId.trim();
    final pid = _safeDocId(postDocId);
    final root = '${churchRoot(tid)}/$kSegAvisos/$kSegImagens';
    if (slotIndex <= 0) return '$root/${pid}_capa.webp';
    final n = slotIndex.toString().padLeft(2, '0');
    return '$root/${pid}_galeria_$n.webp';
  }

  /// Legado: `avisos/{postId}/capa_aviso.jpg` …
  static String avisoPostPhotoPathLegacy(
      String tenantId, String postDocId, int slotIndex) {
    final tid = tenantId.trim();
    final pid = _safeDocId(postDocId);
    final root = '${churchRoot(tid)}/$kSegAvisos/$pid';
    if (slotIndex <= 0) return '$root/capa_aviso.jpg';
    final n = slotIndex.toString().padLeft(2, '0');
    return '$root/galeria_$n.jpg';
  }

  static String _avisoPostPhotoBase(
      String tenantId, String postDocId, int slotIndex) {
    final tid = tenantId.trim();
    final pid = _safeDocId(postDocId);
    final root = '${churchRoot(tid)}/$kSegAvisos/$kSegImagens';
    if (slotIndex <= 0) return '$root/${pid}_capa';
    final n = slotIndex.toString().padLeft(2, '0');
    return '$root/${pid}_galeria_$n';
  }

  /// Variante WebP do mural aviso (`thumb_300`, `medium_800`, `full_1920`).
  static String avisoPostPhotoVariantPath(
    String tenantId,
    String postDocId,
    int slotIndex,
    String tier,
  ) =>
      '${_avisoPostPhotoBase(tenantId, postDocId, slotIndex)}_${tier.trim()}.webp';

  static String eventPostPhotoVariantPath(
    String tenantId,
    String postDocId,
    int slotIndex,
    String tier,
  ) {
    final tid = tenantId.trim();
    final pid = _safeDocId(postDocId);
    final root = '${churchRoot(tid)}/$kSegEventos/$kSegImagens';
    final base = slotIndex <= 0
        ? '$root/${pid}_banner'
        : '$root/${pid}_galeria_${slotIndex.toString().padLeft(2, '0')}';
    return '${base}_${tier.trim()}.webp';
  }

  /// Chat: `…/chat_media/{threadId}/{uid}_{ts}_thumb_200.webp` (lista) + `_full_1920.webp`.
  static String chatMediaVariantPath(
    String tenantId,
    String threadId,
    String fileNameStem,
    String tier,
  ) =>
      '${churchRoot(tenantId)}/chat_media/${threadId.trim()}/${fileNameStem}_${tier.trim()}.webp';

  /// Subpasta por tipo: `images` | `videos` | `audio` | `docs` (legado: `documents`).
  static String chatMediaFolderForKind(String kind) => switch (kind) {
        'image' => 'images',
        'video' => 'videos',
        'audio' => 'audio',
        'pdf' || 'doc' || 'xls' || 'zip' || 'document' => 'docs',
        _ => 'docs',
      };

  /// `igrejas/{tenant}/chat_media/{folder}/{uid}_{ts}_{name}` — sem threadId (estilo WhatsApp).
  static String buildChatMediaObjectPath({
    required String tenantId,
    required String threadId,
    required String kind,
    required String uid,
    required int timestampMs,
    required String fileName,
  }) {
    final folder = chatMediaFolderForKind(kind);
    final safeName = fileName.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
    return '${churchRoot(tenantId)}/chat_media/$folder/${uid}_${timestampMs}_$safeName';
  }

  /// Miniatura centralizada: `igrejas/{tenant}/chat_media/thumbs/{uid}_{ts}_{suffix}.webp`
  static String buildChatMediaThumbPath({
    required String tenantId,
    required String uid,
    required int timestampMs,
    String suffix = 'thumb',
  }) =>
      '${churchRoot(tenantId)}/chat_media/thumbs/${uid}_${timestampMs}_$suffix.webp';

  /// @deprecated Use [buildChatMediaThumbPath]. Mantido para URLs legadas.
  static String buildChatVideoThumbPath({
    required String tenantId,
    required String threadId,
    required String uid,
    required int timestampMs,
  }) =>
      buildChatMediaThumbPath(
        tenantId: tenantId,
        uid: uid,
        timestampMs: timestampMs,
        suffix: 'video',
      );

  /// @deprecated Use [buildChatMediaThumbPath]. Mantido para URLs legadas.
  static String buildChatImageThumbPath({
    required String tenantId,
    required String threadId,
    required String uid,
    required int timestampMs,
  }) =>
      buildChatMediaThumbPath(
        tenantId: tenantId,
        uid: uid,
        timestampMs: timestampMs,
        suffix: 'image',
      );

  /// Caminhos tentados para assinatura institucional (`assinatura.png` / `.jpg`).
  static List<String> pastorSignatureConfigPaths(String tenantId) {
    final r = churchRoot(tenantId);
    return [
      '$r/$kSegConfiguracoes/assinatura.png',
      '$r/$kSegConfiguracoes/assinatura.jpg',
    ];
  }

  /// Logo institucional canónica (carteirinha, certificados, relatórios, site).
  /// Nome fixo para sobrescrever no Storage sem gerar ficheiros órfãos.
  static String churchIdentityLogoPath(String tenantId) =>
      '${churchRoot(tenantId)}/$kSegConfiguracoes/logo_igreja.png';

  /// Legado: tentativa `.jpg` na mesma pasta (antes da padronização PNG).
  static String churchIdentityLogoPathJpgLegacy(String tenantId) =>
      '${churchRoot(tenantId)}/$kSegConfiguracoes/logo_igreja.jpg';

  static String logoPrincipalPath(String tenantId) =>
      '${churchRoot(tenantId)}/$kSegLogo/logo_principal.jpg';

  /// Base sem extensão (variantes thumb/card/full).
  static String logoPrincipalBaseWithoutExt(String tenantId) =>
      '${churchRoot(tenantId)}/$kSegLogo/logo_principal';

  /// Logo nomeada: `igrejas/{id}/logo/logo_{nomeSanitizado}_{id}.jpg`.
  static String logoNamedPath(String tenantId, String churchName) {
    final stem = ChurchLogoStorageNaming.fileStemWithoutExt(
      churchName: churchName,
      tenantId: tenantId,
    );
    return '${churchRoot(tenantId)}/$kSegLogo/$stem.jpg';
  }

  /// Base sem extensão para variantes `_thumb` / `_card` / `_full`.
  static String logoNamedBaseWithoutExt(String tenantId, String churchName) {
    final stem = ChurchLogoStorageNaming.fileStemWithoutExt(
      churchName: churchName,
      tenantId: tenantId,
    );
    return '${churchRoot(tenantId)}/$kSegLogo/$stem';
  }

  /// Ordem de tentativa no Storage: identidade em [configuracoes], depois legados.
  static List<String> churchLogoObjectPathsToTry(
    String tenantId,
    String? churchName,
  ) {
    final tid = tenantId.trim();
    final out = <String>[
      churchIdentityLogoPath(tid),
      churchIdentityLogoPathJpgLegacy(tid),
      '${churchRoot(tid)}/$kSegCertificadosMidia/logo_atual.jpg',
      '${churchRoot(tid)}/$kSegCertificadosMidia/logo_atual.png',
    ];
    final n = churchName?.trim();
    if (n != null && n.isNotEmpty) {
      out.add(logoNamedPath(tid, n));
    }
    out.add(logoPrincipalPath(tid));
    out.addAll(legacyLogoObjectPaths(tid));
    return out;
  }

  /// Capa de **template** de culto/evento fixo (Firestore: `event_templates`).
  /// Fica em `eventos/templates/` para obedecer ao padrão `…/eventos/…`.
  ///
  /// [uniqueId] deve ser estável por doc quando possível (ex.: id do Firestore), para sobrescrever
  /// o mesmo arquivo ao trocar a imagem.
  static String eventTemplateCoverPath(String tenantId, String uniqueId) {
    final safe =
        uniqueId.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_').trim();
    final id = safe.isEmpty ? 'template' : safe;
    return '${churchRoot(tenantId)}/$kSegEventos/templates/$id.jpg';
  }

  /// Caminho legado da capa de template (antes de `eventos/templates/`).
  static String legacyEventTemplateCoverPath(String tenantId, String uniqueId) {
    final safe =
        uniqueId.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_').trim();
    final id = safe.isEmpty ? 'template' : safe;
    return '${churchRoot(tenantId)}/event_templates/$id.jpg';
  }

  /// Foto principal do membro no painel (mesmo padrão do cadastro público).
  static String memberMainPhotoPath(String tenantId, String memberId) =>
      '${churchRoot(tenantId)}/$kSegMembros/$memberId.jpg';

  /// Base sem extensão para variantes thumb/card/full do membro.
  static String memberMainPhotoBaseWithoutExt(String tenantId, String memberId) =>
      '${churchRoot(tenantId)}/$kSegMembros/$memberId';

  /// [stem] = ID do documento em `membros` (em geral CPF 11 dígitos) ou outro id estável.
  static String gestorMemberPhotoPath(String tenantId, String stem) {
    final s = stem.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
    return '${churchRoot(tenantId)}/$kSegMembros/${s}_gestor.jpg';
  }

  /// Espelho estável da foto do gestor (painel / URLs diretas) — além de `membros/…/foto_perfil.jpg`.
  static String gestorPublicProfilePhotoPath(String tenantId) =>
      '${churchRoot(tenantId)}/gestor/foto_perfil.jpg';

  /// ID sanitizado usado na pasta `patrimonio/{safeId}/` (igual ao doc Firestore quando já é seguro).
  static String patrimonioStorageSafeItemId(String itemDocId) =>
      _safeDocId(itemDocId);

  /// Prefixo `igrejas/{tenant}/patrimonio/{safeItemId}` (pasta do bem).
  static String patrimonioItemFolderPrefix(String tenantId, String itemDocId) {
    final safeId = _safeDocId(itemDocId);
    return '${churchRoot(tenantId)}/$kSegPatrimonio/$safeId';
  }

  /// Foto full: `patrimonio/imagens/{safeId}_01.webp` … `_05.webp`.
  static String patrimonioPhotoPath(String tenantId, String itemDocId, int slot) {
    final s = slot < 0 ? 0 : (slot > 4 ? 4 : slot);
    final safeId = _safeDocId(itemDocId);
    final n = (s + 1).toString().padLeft(2, '0');
    return '${churchRoot(tenantId)}/$kSegPatrimonio/$kSegImagens/${safeId}_$n.webp';
  }

  /// Legado: `patrimonio/{itemId}/galeria_01.webp`.
  static String patrimonioPhotoPathLegacy(
      String tenantId, String itemDocId, int slot) {
    final s = slot < 0 ? 0 : (slot > 4 ? 4 : slot);
    final safeId = _safeDocId(itemDocId);
    final root = '${churchRoot(tenantId)}/$kSegPatrimonio/$safeId';
    final n = (s + 1).toString().padLeft(2, '0');
    return '$root/galeria_$n.webp';
  }

  /// Miniatura: `patrimonio/thumbs/{safeId}_01.webp`.
  static String patrimonioThumbPath(String tenantId, String itemDocId, int slot) {
    final s = slot < 0 ? 0 : (slot > 4 ? 4 : slot);
    final safeId = _safeDocId(itemDocId);
    final n = (s + 1).toString().padLeft(2, '0');
    return '${churchRoot(tenantId)}/$kSegPatrimonio/thumbs/${safeId}_$n.webp';
  }

  /// Base sem extensão (limpeza) — path canónico em `patrimonio/imagens/`.
  static String patrimonioPhotoBaseWithoutExt(
      String tenantId, String itemDocId, int slot) {
    final s = slot < 0 ? 0 : (slot > 4 ? 4 : slot);
    final safeId = _safeDocId(itemDocId);
    final n = (s + 1).toString().padLeft(2, '0');
    return '${churchRoot(tenantId)}/$kSegPatrimonio/$kSegImagens/${safeId}_$n';
  }

  /// Paths a apagar ao substituir slot (canónico + legado).
  static List<String> patrimonioSlotDeletionPaths(
    String tenantId,
    String itemDocId,
    int slot,
  ) {
    final canonical = patrimonioPhotoPath(tenantId, itemDocId, slot);
    final thumb = patrimonioThumbPath(tenantId, itemDocId, slot);
    final legacy = patrimonioPhotoPathLegacy(tenantId, itemDocId, slot);
    final legacyBase =
        patrimonioPhotoBaseWithoutExtLegacy(tenantId, itemDocId, slot);
    return [
      canonical,
      thumb,
      legacy,
      '$legacyBase.jpg',
      '$legacyBase.webp',
      '${legacyBase}_thumb.jpg',
      '${legacyBase}_thumb.webp',
    ];
  }

  static String patrimonioPhotoBaseWithoutExtLegacy(
      String tenantId, String itemDocId, int slot) {
    final s = slot < 0 ? 0 : (slot > 4 ? 4 : slot);
    final safeId = _safeDocId(itemDocId);
    final root = '${churchRoot(tenantId)}/$kSegPatrimonio/$safeId';
    final n = (s + 1).toString().padLeft(2, '0');
    return '$root/galeria_$n';
  }

  /// Caminhos legados (EcoFire / versões anteriores) — podem ser removidos após novo upload.
  static List<String> legacyLogoObjectPaths(String tenantId) => [
        '${churchRoot(tenantId)}/branding/logo_igreja.jpg',
        '${churchRoot(tenantId)}/branding/logo_igreja.png',
      ];

  /// Logo fixa da carteirinha (sobrescreve no mesmo path).
  static String cartaoMembroLogoPath(String tenantId) =>
      '${churchRoot(tenantId)}/$kSegCartaoMembro/logo.jpg';

  /// Prefixo para limpar uploads da logo da carteirinha (`cartao_membro/`).
  static String cartaoMembroMediaPrefix(String tenantId) =>
      '${churchRoot(tenantId)}/$kSegCartaoMembro';

  /// Base sem extensão da logo dedicada dos certificados (ficheiro canónico `logo_atual.jpg`).
  static String certificadoDedicatedLogoBaseWithoutExt(String tenantId) =>
      '${churchRoot(tenantId)}/$kSegCertificadosMidia/logo_atual';

  /// Prefixo da pasta de mídia dos certificados (logo dedicada, etc.).
  static String certificadoDedicatedMediaPrefix(String tenantId) =>
      '${churchRoot(tenantId)}/$kSegCertificadosMidia';

  /// Fundos luxo para PDF: `igrejas/{id}/templates/certificados/{stem}.png|.jpg`.
  static const String kSegCertificadosTemplates = 'templates/certificados';

  static List<String> certificateTemplateBackgroundPaths(
    String tenantId,
    String storageStem,
  ) {
    final stem =
        storageStem.trim().replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
    if (stem.isEmpty) return const [];
    final base =
        '${churchRoot(tenantId)}/$kSegCertificadosTemplates/$stem';
    return ['$base.png', '$base.jpg'];
  }
}
