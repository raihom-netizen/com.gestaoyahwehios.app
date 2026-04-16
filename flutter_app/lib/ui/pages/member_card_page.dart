import 'dart:async' show unawaited, Timer;
import 'dart:convert';
import 'dart:math' show min;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:gestao_yahweh/core/church_storage_layout.dart';
import 'package:gestao_yahweh/core/carteirinha_visual_tokens.dart';
import 'package:gestao_yahweh/core/public_site_media_auth.dart';
import 'package:gestao_yahweh/ui/theme_clean_premium.dart';
import 'package:gestao_yahweh/services/firebase_storage_service.dart';
import 'package:gestao_yahweh/services/image_helper.dart';
import 'package:gestao_yahweh/services/media_upload_service.dart';
import 'package:gestao_yahweh/ui/widgets/safe_network_image.dart'
    show
        churchTenantLogoUrl,
        firebaseStorageBytesFromDownloadUrl,
        imageUrlFromMap,
        isDataImageUrl,
        isFirebaseStorageHttpUrl,
        isValidImageUrl,
        preloadNetworkImages,
        refreshFirebaseStorageDownloadUrl,
        SafeNetworkImage,
        sanitizeImageUrl;
import 'package:cached_network_image/cached_network_image.dart';
import 'package:gestao_yahweh/utils/pdf_actions_helper.dart';
import 'package:gestao_yahweh/utils/report_pdf_branding.dart';
import 'package:gestao_yahweh/utils/church_department_list.dart'
    show churchDepartmentNameFromDoc;
import 'package:gestao_yahweh/utils/member_signature_eligibility.dart';
import 'package:gestao_yahweh/ui/widgets/member_demographics_utils.dart';
import 'package:image/image.dart' as img;
import 'package:printing/printing.dart';
import 'package:gestao_yahweh/services/media_handler_service.dart';
import 'package:gestao_yahweh/core/entity_image_fields.dart';
import 'package:gestao_yahweh/core/services/app_storage_image_service.dart';
import 'package:gestao_yahweh/core/widgets/stable_storage_image.dart'
    show StableChurchLogo;
import 'package:gestao_yahweh/services/firebase_storage_cleanup_service.dart';
import 'package:gestao_yahweh/services/tenant_resolver_service.dart';
import 'package:gestao_yahweh/services/certificado_digital_service.dart';
import 'package:gestao_yahweh/services/member_document_resolve.dart';
import 'package:gestao_yahweh/services/carteira_pades_signer.dart';
import 'package:gestao_yahweh/utils/carteirinha_zip_export.dart';
import 'package:gestao_yahweh/utils/carteirinha_pdf_image_resize.dart';
import 'package:gestao_yahweh/utils/carteirinha_pdf_signature_enhance.dart';
import 'package:gestao_yahweh/ui/pdf/verso_carteirinha_widget.dart';
import 'package:gestao_yahweh/ui/pdf/carteirinha_pvc_marks.dart';
import 'package:gestao_yahweh/ui/pdf/carteirinha_a4_cut_guides.dart';
import 'package:gestao_yahweh/ui/pdf/carteirinha_pdf_fonts.dart';
import 'package:gestao_yahweh/ui/widgets/foto_membro_widget.dart';
import 'package:gestao_yahweh/ui/widgets/safe_member_profile_photo.dart'
    show memberPhotoDisplayCacheRevision;
import 'package:file_picker/file_picker.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:share_plus/share_plus.dart';
import 'package:gal/gal.dart';
import 'package:screenshot/screenshot.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:gestao_yahweh/ui/widgets/member_digital_wallet_card.dart';
import 'package:gestao_yahweh/services/app_permissions.dart';
import 'package:gestao_yahweh/core/roles_permissions.dart';
import 'package:intl/intl.dart';

/// Alinhado a [members_page] / [_memberAuthUidFromData]: foto no Storage pode estar em `membros/{authUid}/`.
String? _memberAuthUidForCarteiraFoto(Map<String, dynamic> d) {
  for (final k in [
    'authUid',
    'firebaseUid',
    'firebase_uid',
    'firebaseUserId',
    'userId',
    'user_id',
    'uid',
    'USUARIO_UID',
    'usuario_uid',
  ]) {
    final v = (d[k] ?? '').toString().trim();
    if (v.isNotEmpty) return v;
  }
  return null;
}

/// Layout ao emitir várias carteirinhas (PDF).
enum _PdfManyLayout {
  /// A4 com uma carteirinha centralizada por folha.
  a4OnePerPage,

  /// A4: 5 membros por folha — em cada linha, frente e verso lado a lado (economia de papel).
  a4FrenteVerso5PorFolha,

  /// A4: 2 membros/folha — frente sobre verso (igual à carteirinha digital no ecrã).
  a4FrenteSobreVerso2Digital,

  /// Grade 2×2 (4) no A4.
  a4Grid2x2,

  /// Grade 2×3 (6) no A4.
  a4Grid2x3,

  /// Grade 2×4 (8) no A4 — ideal para impressora jato de tinta.
  a4Grid2x4,

  /// Grade 2×5 (10) no A4.
  a4Grid2x5,

  /// Página no tamanho físico CR80 (~cartão PVC / papel fotográfico cortado).
  cr80sheet,

  /// CR80 com sangria e marcas de corte para gráfica.
  cr80grafica,
}

({
  PdfPageFormat format,
  int cols,
  int rows,
  bool pvcCrop,
  bool frontVersoPorLinha,
  bool digitalVerticalStack,
}) _pdfManyLayoutParams(
    _PdfManyLayout layout) {
  const cr80w = 85.6 * 72 / 25.4;
  const cr80h = 53.98 * 72 / 25.4;
  return switch (layout) {
    _PdfManyLayout.a4OnePerPage => (
        format: PdfPageFormat.a4,
        cols: 1,
        rows: 1,
        pvcCrop: false,
        frontVersoPorLinha: false,
        digitalVerticalStack: false,
      ),
    _PdfManyLayout.a4FrenteVerso5PorFolha => (
        format: PdfPageFormat.a4,
        cols: 2,
        rows: 5,
        pvcCrop: false,
        frontVersoPorLinha: true,
        digitalVerticalStack: false,
      ),
    _PdfManyLayout.a4FrenteSobreVerso2Digital => (
        format: PdfPageFormat.a4,
        cols: 2,
        rows: 2,
        pvcCrop: false,
        frontVersoPorLinha: true,
        digitalVerticalStack: true,
      ),
    _PdfManyLayout.a4Grid2x2 => (
        format: PdfPageFormat.a4,
        cols: 2,
        rows: 2,
        pvcCrop: false,
        frontVersoPorLinha: false,
        digitalVerticalStack: false,
      ),
    _PdfManyLayout.a4Grid2x3 => (
        format: PdfPageFormat.a4,
        cols: 2,
        rows: 3,
        pvcCrop: false,
        frontVersoPorLinha: false,
        digitalVerticalStack: false,
      ),
    _PdfManyLayout.a4Grid2x4 => (
        format: PdfPageFormat.a4,
        cols: 2,
        rows: 4,
        pvcCrop: false,
        frontVersoPorLinha: false,
        digitalVerticalStack: false,
      ),
    _PdfManyLayout.a4Grid2x5 => (
        format: PdfPageFormat.a4,
        cols: 2,
        rows: 5,
        pvcCrop: false,
        frontVersoPorLinha: false,
        digitalVerticalStack: false,
      ),
    _PdfManyLayout.cr80sheet => (
        format: PdfPageFormat(cr80w, cr80h),
        cols: 1,
        rows: 1,
        pvcCrop: false,
        frontVersoPorLinha: false,
        digitalVerticalStack: false,
      ),
    _PdfManyLayout.cr80grafica => (
        format: CarteirinhaPvcMarks.pageFormat(),
        cols: 1,
        rows: 1,
        pvcCrop: true,
        frontVersoPorLinha: false,
        digitalVerticalStack: false,
      ),
  };
}

class MemberCardPage extends StatefulWidget {
  final String tenantId;
  final String role;
  final String? memberId;
  final String? cpf;

  /// Chamado ao clicar em "Ir para Membros"; troca para a aba Membros no shell (evita pop que deslogava).
  final VoidCallback? onNavigateToMembers;

  /// Dentro de [IgrejaCleanShell]: sem AppBar duplicada; ações em barra compacta no corpo.
  final bool embeddedInShell;

  const MemberCardPage({
    super.key,
    required this.tenantId,
    required this.role,
    this.memberId,
    this.cpf,
    this.onNavigateToMembers,
    this.embeddedInShell = false,
  });

  @override
  State<MemberCardPage> createState() => _MemberCardPageState();
}

class _MemberItem {
  final String id;
  final String name;
  final String? photoUrl;

  /// Dados brutos do Firestore para filtros (gênero, idade, departamento, CPF).
  final Map<String, dynamic> data;
  _MemberItem(
      {required this.id,
      required this.name,
      this.photoUrl,
      Map<String, dynamic>? data})
      : data = data ?? const {};
}

class _MemberCardPageState extends State<MemberCardPage> {
  /// Tamanho físico CR80 — export único legível (evita folha A4 com cartão “gigante”).
  static final PdfPageFormat _kPdfCr80Export = PdfPageFormat(
    85.6 * 72 / 25.4,
    53.98 * 72 / 25.4,
  );

  Future<_CardData?>? _loadFuture;

  /// Doc `igrejas/{id}` após [resolveEffectiveTenantId] (cache por sessão desta página).
  String? _cachedIgrejaDocId;

  String _memberSearch = '';
  late Future<List<_MemberItem>> _membersListFuture;

  /// Departamentos da igreja (para filtro e correspondência com nome legado).
  List<({String id, String name})> _deptFilterItems = [];
  String? _lastWarmupKey;

  /// Gênero: todos | masculino | feminino
  String _filtroGeneroCarteira = 'todos';

  /// Faixa etária: todas | criancas | adolescentes | adultos | idosos
  String _filtroFaixaCarteira = 'todas';

  /// id do documento em departamentos ou 'todos'
  String _filtroDepartamentoCarteira = 'todos';

  /// Busca com debounce — evita setState a cada tecla (travava filtros/lista).
  late final TextEditingController _memberSearchController;
  Timer? _memberSearchDebounce;
  String? _memberListPreloadFingerprint;

  /// Seleção na lista de membros (emissão / assinatura em bloco).
  final Set<String> _carteiraListaSelecionados = {};

  final ScreenshotController _walletScreenshotController = ScreenshotController();

  /// Durante exportação PDF (captura da carteira): assinatura/nome no verso antes do [Screenshot].
  String? _walletPdfExportSigUrl;
  String? _walletPdfExportSignatoryNome;
  String? _walletPdfExportSignatoryCargo;

  /// Captura raster em lote (mesmo visual da carteira digital) — fora do ecrã.
  final ScreenshotController _rasterBatchScreenshotController =
      ScreenshotController();
  _CardData? _rasterBatchCard;
  String _rasterBatchSigUrl = '';
  String _rasterBatchSignatoryNome = '';
  String _rasterBatchSignatoryCargo = '';
  /// `true` = captura em lote com [MemberDigitalWalletFront] e [MemberDigitalWalletBack] na mesma linha.
  bool _rasterBatchLadoALado = false;

  /// Mesmas cores da [MemberDigitalWalletFront] / config — PDF vetorial não usa hex com fallback errado.
  ({PdfColor bg, PdfColor bgEnd, PdfColor fg}) _pdfCarteiraColors(
      _CardConfig cfg, bool inkEco) {
    if (inkEco) {
      return (
        bg: PdfColors.white,
        bgEnd: PdfColors.white,
        fg: PdfColors.grey900,
      );
    }
    final bg = CarteirinhaVisualTokens.flutterColorToPdfColor(cfg.bgColorValue);
    final bgEnd = cfg.bgColorSecondaryValue != null
        ? CarteirinhaVisualTokens.flutterColorToPdfColor(
            cfg.bgColorSecondaryValue!)
        : CarteirinhaVisualTokens.flutterColorToPdfColor(
            CarteirinhaVisualTokens.gradientEndFromPrimary(cfg.bgColorValue),
          );
    final fg =
        CarteirinhaVisualTokens.flutterColorToPdfColor(cfg.textColorValue);
    return (bg: bg, bgEnd: bgEnd, fg: fg);
  }

  Future<String> _effectiveIgrejaDocId() async {
    final hit = _cachedIgrejaDocId;
    if (hit != null && hit.isNotEmpty) return hit;
    final r =
        (await TenantResolverService.resolveEffectiveTenantId(widget.tenantId))
            .trim();
    final id = r.isNotEmpty ? r : widget.tenantId.trim();
    _cachedIgrejaDocId = id;
    return id;
  }

  @override
  void didUpdateWidget(covariant MemberCardPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.tenantId != widget.tenantId) {
      _cachedIgrejaDocId = null;
    }
    if (oldWidget.memberId != widget.memberId || oldWidget.cpf != widget.cpf) {
      setState(() {
        if (_isRestrictedMember) {
          _loadFuture = _load();
        } else {
          _loadFuture =
              _hasExplicitMemberTarget ? _load() : Future.value(null);
        }
      });
    }
  }

  Future<List<({String id, String name})>> _loadDepartmentsForCarteira() async {
    try {
      final tid = await _effectiveIgrejaDocId();
      final col = FirebaseFirestore.instance
          .collection('igrejas')
          .doc(tid)
          .collection('departamentos');
      final snap = await col.get();
      final list = snap.docs
          .map((d) => (
                id: d.id,
                name: churchDepartmentNameFromDoc(d),
              ))
          .where((e) => e.name.isNotEmpty)
          .toList();
      list.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      return list;
    } catch (_) {
      return [];
    }
  }

  Future<List<_MemberItem>> _loadMemberItemsForPicker({int limit = 200}) async {
    final db = FirebaseFirestore.instance;
    final tid = await _effectiveIgrejaDocId();
    final membersCol =
        db.collection('igrejas').doc(tid).collection('membros');
    final membersSnap = await membersCol.limit(limit).get();
    final list = <_MemberItem>[];
    for (final d in membersSnap.docs) {
      final data = Map<String, dynamic>.from(d.data());
      final name =
          (data['NOME_COMPLETO'] ?? data['nome'] ?? data['name'] ?? d.id)
              .toString();
      final url = imageUrlFromMap(data);
      list.add(_MemberItem(
          id: d.id,
          name: name,
          photoUrl: url.isNotEmpty ? url : null,
          data: data));
    }
    list.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return list;
  }

  Future<List<_MemberItem>> _loadMembersList() =>
      _loadMemberItemsForPicker(limit: 200);

  /// Filtro por departamento alinhado à página Membros (lista de ids ou campo texto legado).
  bool _memberMatchesDepartment(Map<String, dynamic> data, String deptDocId,
      List<({String id, String name})> deptList) {
    if (deptDocId == 'todos') return true;
    String? deptName;
    for (final e in deptList) {
      if (e.id == deptDocId) {
        deptName = e.name;
        break;
      }
    }
    final depts = data['DEPARTAMENTOS'] ?? data['departamentos'];
    if (depts is List) {
      if (depts.any((x) => x.toString() == deptDocId)) return true;
    }
    final deptIds = data['departamentosIds'];
    if (deptIds is List) {
      if (deptIds.any((x) => x.toString() == deptDocId)) return true;
    }
    final d =
        (data['departamento'] ?? data['DEPARTAMENTO'] ?? '').toString().trim();
    if (d == deptDocId) return true;
    if (deptName != null && d == deptName) return true;
    return false;
  }

  bool _memberMatchesCarteiraFilters(_MemberItem m) {
    final q = _memberSearch.trim().toLowerCase();
    if (q.isNotEmpty) {
      final name = m.name.toLowerCase();
      final idLow = m.id.toLowerCase();
      final cpfRaw = (m.data['CPF'] ?? m.data['cpf'] ?? '').toString();
      final cpfDigits = cpfRaw.replaceAll(RegExp(r'\D'), '');
      final qDigits = q.replaceAll(RegExp(r'\D'), '');
      final matchText = name.contains(q) || idLow.contains(q);
      final matchCpf = qDigits.length >= 3 && cpfDigits.contains(qDigits);
      if (!matchText && !matchCpf) return false;
    }
    if (_filtroGeneroCarteira != 'todos') {
      final g = genderCategoryFromMemberData(m.data);
      if (_filtroGeneroCarteira == 'masculino' && g != 'M') return false;
      if (_filtroGeneroCarteira == 'feminino' && g != 'F') return false;
    }
    if (_filtroFaixaCarteira != 'todas') {
      final idade = ageFromMemberData(m.data);
      if (idade == null) return false;
      if (_filtroFaixaCarteira == 'criancas' && idade >= 13) return false;
      if (_filtroFaixaCarteira == 'adolescentes' && (idade < 13 || idade >= 18))
        return false;
      if (_filtroFaixaCarteira == 'adultos' && (idade < 18 || idade >= 60))
        return false;
      if (_filtroFaixaCarteira == 'idosos' && idade < 60) return false;
    }
    if (!_memberMatchesDepartment(
        m.data, _filtroDepartamentoCarteira, _deptFilterItems)) {
      return false;
    }
    return true;
  }

  @override
  void initState() {
    super.initState();
    if (kIsWeb) {
      unawaited(PublicSiteMediaAuth.ensureWebAnonymousForStorage());
    }
    _memberSearchController = TextEditingController();
    if (_isRestrictedMember) {
      _membersListFuture = Future.value([]);
      _loadFuture = _load();
    } else {
      _membersListFuture = _loadMembersList();
      _loadDepartmentsForCarteira().then((list) {
        if (mounted) setState(() => _deptFilterItems = list);
      });
      _loadFuture =
          _hasExplicitMemberTarget ? _load() : Future.value(null);
    }
  }

  @override
  void dispose() {
    _memberSearchDebounce?.cancel();
    _memberSearchController.dispose();
    super.dispose();
  }

  /// Se a URL da assinatura não foi gravada no membro (fluxo antigo ou falha), busca em [membros/carteirinhaAssinadaPor].assinaturaUrl.
  Future<Map<String, dynamic>> _enrichMemberCarteirinhaSignatureFromSignatory(
    Map<String, dynamic> raw, {
    String? igrejaDocId,
  }) async {
    final out = Map<String, dynamic>.from(raw);
    final existing = (out['carteirinhaAssinaturaUrl'] ??
            out['carteirinha_assinatura_url'] ??
            '')
        .toString()
        .trim();
    if (existing.isNotEmpty) return out;
    final porId = (out['carteirinhaAssinadaPor'] ?? '').toString().trim();
    if (porId.isEmpty) return out;
    final db = FirebaseFirestore.instance;
    final tid = (igrejaDocId ?? widget.tenantId).trim();
    if (tid.isEmpty) return out;
    try {
      final snap = await db
          .collection('igrejas')
          .doc(tid)
          .collection('membros')
          .doc(porId)
          .get();
      if (snap.exists) {
        final d = snap.data() ?? {};
        final u =
            (d['assinaturaUrl'] ?? d['assinatura_url'] ?? '').toString().trim();
        if (u.isNotEmpty) out['carteirinhaAssinaturaUrl'] = u;
        return out;
      }
      final mq = await db
          .collection('igrejas')
          .doc(tid)
          .collection('membros')
          .where('authUid', isEqualTo: porId)
          .limit(1)
          .get();
      if (mq.docs.isNotEmpty) {
        final d = mq.docs.first.data();
        final u =
            (d['assinaturaUrl'] ?? d['assinatura_url'] ?? '').toString().trim();
        if (u.isNotEmpty) out['carteirinhaAssinaturaUrl'] = u;
      }
    } catch (_) {}
    return out;
  }

  /// Configurar carteirinha, seleção em lote e PDF em massa — alinhado a quem edita membros / perfil da igreja.
  /// Inclui pastores/secretários ([editAnyMember]) e corrige papéis compostos via [ChurchRolePermissions.normalize].
  bool get _canManage {
    if (AppPermissions.isRestrictedMember(widget.role)) return false;
    final n = ChurchRolePermissions.normalize(widget.role);
    if (n == ChurchRoleKeys.master ||
        n == ChurchRoleKeys.adm ||
        n == ChurchRoleKeys.gestor) {
      return true;
    }
    final s = ChurchRolePermissions.snapshotFor(widget.role);
    return s.editAnyMember || s.editChurchProfile;
  }

  /// Membro só vê e emite a própria carteirinha (acesso restrito).
  /// Perfil básico no painel: só a própria carteirinha (membro ou visitante com menu restrito).
  bool get _isRestrictedMember {
    final r = widget.role.toLowerCase();
    return r == 'membro' || r == 'visitante';
  }

  /// Gestor/admin só carrega ficha quando há [memberId] explícito.
  /// O CPF do usuário logado na shell não deve pré-selecionar membro (senão só emite a própria).
  bool get _hasExplicitMemberTarget =>
      widget.memberId != null && widget.memberId!.trim().isNotEmpty;

  Future<_CardData?> _load() async {
    final db = FirebaseFirestore.instance;
    final igrejaDocId = await _effectiveIgrejaDocId();
    final membersCol =
        db.collection('igrejas').doc(igrejaDocId).collection('membros');

    // Carrega tenant (obrigatório) e config do card (opcional)
    Map<String, dynamic> cardCfg = {};
    Map<String, dynamic> tenant = {};

    try {
      final tenantSnap =
          await db.collection('igrejas').doc(igrejaDocId).get();
      tenant = Map<String, dynamic>.from(tenantSnap.data() ?? {})
        ..['id'] = igrejaDocId;
    } catch (_) {}

    // Config por igreja (carteira editável: cor, logo)
    try {
      final carteiraSnap = await db
          .collection('igrejas')
          .doc(igrejaDocId)
          .collection('config')
          .doc('carteira')
          .get();
      if (carteiraSnap.exists && carteiraSnap.data() != null) {
        cardCfg.addAll(Map<String, dynamic>.from(carteiraSnap.data()!));
      }
    } catch (_) {}

    // Fallback: config global e depois tenant (logo pode ser logoUrl ou logoDataBase64)
    final hasLogo = (cardCfg['logoUrl'] ?? '').toString().trim().isNotEmpty ||
        ((cardCfg['logoDataBase64'] ?? '').toString().trim().isNotEmpty);
    if (cardCfg['title'] == null || !hasLogo) {
      try {
        final cfgSnap = await db.doc('config/memberCard').get();
        if (cfgSnap.exists && cfgSnap.data() != null) {
          final global = cfgSnap.data()!;
          if (cardCfg['title'] == null && global['title'] != null)
            cardCfg['title'] = global['title'];
          if (cardCfg['logoUrl'] == null && global['logoUrl'] != null)
            cardCfg['logoUrl'] = global['logoUrl'];
          if (cardCfg['bgColor'] == null && global['bgColor'] != null) {
            cardCfg['bgColor'] = global['bgColor'];
          }
          if (cardCfg['textColor'] == null && global['textColor'] != null) {
            cardCfg['textColor'] = global['textColor'];
          }
          if (cardCfg['bgColorSecondary'] == null &&
              global['bgColorSecondary'] != null) {
            cardCfg['bgColorSecondary'] = global['bgColorSecondary'];
          }
          if (cardCfg['accentColor'] == null && global['accentColor'] != null) {
            cardCfg['accentColor'] = global['accentColor'];
          }
          if (cardCfg['accentGold'] == null && global['accentGold'] != null) {
            cardCfg['accentGold'] = global['accentGold'];
          }
        }
      } catch (_) {}
    }
    if (cardCfg['title'] == null && tenant['name'] != null) {
      cardCfg['title'] = tenant['name'] ?? tenant['nome'] ?? 'Gestão YAHWEH';
    }
    if (cardCfg['logoUrl'] == null) {
      final u = churchTenantLogoUrl(tenant);
      if (u.isNotEmpty) cardCfg['logoUrl'] = u;
    }
    await _hydrateCardCfgLogoFromIdentityPathIfNeeded(cardCfg, igrejaDocId);
    cardCfg = _mergeChurchLogoIntoCardConfig(cardCfg, tenant);

    DocumentSnapshot<Map<String, dynamic>>? memberDoc;
    final isMembro = _isRestrictedMember;
    final cpf = (widget.cpf ?? '').replaceAll(RegExp(r'[^0-9]'), '');

    if (!isMembro &&
        widget.memberId != null &&
        widget.memberId!.trim().isNotEmpty) {
      try {
        memberDoc = await MemberDocumentResolve.findByHint(
          membersCol,
          widget.memberId!.trim(),
          cpfDigits: cpf,
        );
      } catch (_) {}
    }

    if (memberDoc == null && cpf.length >= 11 && isMembro) {
      try {
        final byId = await membersCol.doc(cpf).get();
        if (byId.exists) {
          memberDoc = byId;
        } else {
          final q =
              await membersCol.where('CPF', isEqualTo: cpf).limit(1).get();
          if (q.docs.isNotEmpty) memberDoc = q.docs.first;
        }
      } catch (_) {}
    }

    if (memberDoc == null && isMembro) {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid != null && uid.isNotEmpty) {
        try {
          final q =
              await membersCol.where('authUid', isEqualTo: uid).limit(1).get();
          if (q.docs.isNotEmpty) memberDoc = q.docs.first;
        } catch (_) {}
      }
    }

    if (memberDoc == null) return null;

    var memberMap = Map<String, dynamic>.from(memberDoc.data() ?? {});
    memberMap = await _enrichMemberCarteirinhaSignatureFromSignatory(memberMap,
        igrejaDocId: igrejaDocId);

    return _CardData(
      memberId: memberDoc.id,
      member: memberMap,
      cardConfig: cardCfg,
      tenant: tenant,
      igrejaDocId: igrejaDocId,
    );
  }

  String _fmtDate(dynamic raw) {
    if (raw is Timestamp) {
      final dt = raw.toDate();
      final d = dt.day.toString().padLeft(2, '0');
      final m = dt.month.toString().padLeft(2, '0');
      final y = dt.year.toString();
      return '$d/$m/$y';
    }
    if (raw is DateTime) {
      final d = raw.day.toString().padLeft(2, '0');
      final m = raw.month.toString().padLeft(2, '0');
      final y = raw.year.toString();
      return '$d/$m/$y';
    }
    return (raw ?? '').toString();
  }

  dynamic _dateFromMember(Map<String, dynamic> member, String key) {
    final tryKeys = <String>{key};
    if (key == 'DATA_NASCIMENTO') {
      tryKeys.addAll([
        'dataNascimento',
        'data_nascimento',
        'birthDate',
        'birth_date',
        'nascimento',
        'dataNasc',
      ]);
    } else if (key == 'DATA_BATISMO') {
      tryKeys.addAll([
        'dataBatismo',
        'data_batismo',
        'DATA_BATISMO',
        'batismo',
        'dataBatismoAgua',
      ]);
    } else if (key == 'DATA_CONSAGRACAO') {
      tryKeys.addAll([
        'dataConsagracao',
        'data_consagracao',
        'DATA_CONSAGRACAO',
        'consagracao',
      ]);
    }
    for (final k in tryKeys) {
      final a = member[k];
      if (a != null) return a;
    }
    return null;
  }

  String _admissionForWallet(Map<String, dynamic> member) {
    const keys = [
      'DATA_ADMISSAO',
      'dataAdmissao',
      'data_admissao',
      'DATA_ENTRADA',
      'dataEntrada',
      'data_entrada',
      'DATA_MEMBRO',
      'dataMembro',
    ];
    for (final k in keys) {
      final s = _fmtDate(member[k]).trim();
      if (s.isNotEmpty) return s;
    }
    return '';
  }

  String _estadoCivilFromMember(Map<String, dynamic> member) {
    return (member['ESTADO_CIVIL'] ??
            member['estadoCivil'] ??
            member['estado_civil'] ??
            '')
        .toString()
        .trim();
  }

  /// Frente da carteira: estado civil + admissão + batismo (uma linha; rótulos por extenso).
  String _admissionBatismoLine(Map<String, dynamic> member) {
    final parts = <String>[];
    final ec = _estadoCivilFromMember(member);
    if (ec.isNotEmpty) parts.add('Estado civil: $ec');
    final adm = _admissionForWallet(member);
    final bat = _fmtDate(_dateFromMember(member, 'DATA_BATISMO')).trim();
    if (adm.isNotEmpty) parts.add('Admissão: $adm');
    if (bat.isNotEmpty) parts.add('Batismo: $bat');
    if (parts.isEmpty) return '';
    return parts.join('  ·  ');
  }

  String _telefoneFromMember(Map<String, dynamic> m) {
    final s = (m['TELEFONES'] ??
            m['telefones'] ??
            m['telefone'] ??
            m['TELEFONE'] ??
            m['phone'] ??
            m['whatsapp'] ??
            '')
        .toString()
        .trim();
    return s;
  }

  String _emailFromMember(Map<String, dynamic> m) {
    return (m['EMAIL'] ?? m['email'] ?? '').toString().trim();
  }

  String _validityLabel(Map<String, dynamic> member) {
    if (member['CARTEIRA_PERMANENTE'] == true) return 'Permanente';
    final validadeCartao = member['validadeCartao'] ??
        member['VALIDADE_CARTAO'] ??
        member['validade_cartao'] ??
        member['validade'] ??
        member['VALIDADE'] ??
        member['dataValidade'] ??
        member['data_validade'];
    if (validadeCartao != null) {
      final txt = _fmtDate(validadeCartao).trim();
      if (txt.isNotEmpty) return txt;
    }
    final carteiraValidade =
        member['CARTEIRA_VALIDADE'] ?? member['carteiraValidade'];
    if (carteiraValidade != null) {
      final txt = _fmtDate(carteiraValidade).trim();
      if (txt.isNotEmpty) return txt;
    }
    final years = member['CARTEIRA_ANOS'];
    if (years is int && years > 0) {
      final now = DateTime.now();
      final dt = DateTime(now.year + years, now.month, now.day);
      return _fmtDate(dt);
    }
    final now = DateTime.now();
    return _fmtDate(DateTime(now.year + 1, now.month, now.day));
  }

  Future<void> _abrirEmitirVarios(BuildContext context) async {
    final db = FirebaseFirestore.instance;
    final tpl = await _loadCarteiraTemplateContext();
    final tenant = tpl.tenant;
    final cardCfg = Map<String, dynamic>.from(tpl.cardCfg);
    final membersCol =
        db.collection('igrejas').doc(tpl.igrejaDocId).collection('membros');

    final emitMembers = await _loadMemberItemsForPicker(limit: 500);
    if (emitMembers.isEmpty) {
      if (context.mounted)
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Nenhum membro encontrado.')));
      return;
    }
    final deptsModal = await _loadDepartmentsForCarteira();

    final signatoryOptions = await _loadSignatoryOptions();
    final selectedIds = <String>{};
    final defaultSigId =
        (cardCfg['defaultSignatoryMemberId'] ?? '').toString().trim();
    var selectedSignatory = _selectSignatory(
        signatoryOptions, defaultSigId.isEmpty ? null : defaultSigId);
    var pdfLayout = _PdfManyLayout.a4FrenteVerso5PorFolha;
    /// Igual à carteira digital na app (degradê + borda ouro). Só desligar para modo pouca tinta.
    var pdfInkEconomy = false;
    var modalSearch = '';
    var modalGenero = 'todos';
    var modalFaixa = 'todas';
    var modalDept = 'todos';
    if (!context.mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModal) {
          bool modalMatch(_MemberItem m) {
            final q = modalSearch.trim().toLowerCase();
            if (q.isNotEmpty) {
              final name = m.name.toLowerCase();
              final idLow = m.id.toLowerCase();
              final cpfRaw = (m.data['CPF'] ?? m.data['cpf'] ?? '').toString();
              final cpfDigits = cpfRaw.replaceAll(RegExp(r'\D'), '');
              final qDigits = q.replaceAll(RegExp(r'\D'), '');
              final matchText = name.contains(q) || idLow.contains(q);
              final matchCpf =
                  qDigits.length >= 3 && cpfDigits.contains(qDigits);
              if (!matchText && !matchCpf) return false;
            }
            if (modalGenero != 'todos') {
              final g = genderCategoryFromMemberData(m.data);
              if (modalGenero == 'masculino' && g != 'M') return false;
              if (modalGenero == 'feminino' && g != 'F') return false;
            }
            if (modalFaixa != 'todas') {
              final idade = ageFromMemberData(m.data);
              if (idade == null) return false;
              if (modalFaixa == 'criancas' && idade >= 13) return false;
              if (modalFaixa == 'adolescentes' && (idade < 13 || idade >= 18))
                return false;
              if (modalFaixa == 'adultos' && (idade < 18 || idade >= 60))
                return false;
              if (modalFaixa == 'idosos' && idade < 60) return false;
            }
            if (!_memberMatchesDepartment(m.data, modalDept, deptsModal))
              return false;
            return true;
          }

          final visible = emitMembers.where(modalMatch).toList();
          final mq = MediaQuery.sizeOf(ctx);
          final sheetH = (mq.height * 0.92).clamp(280.0, mq.height);
          final bottomInset = MediaQuery.viewInsetsOf(ctx).bottom;

          return Padding(
            padding: EdgeInsets.only(bottom: bottomInset),
            child: Align(
              alignment: Alignment.bottomCenter,
              child: Material(
                color: ThemeCleanPremium.surface,
                elevation: 16,
                shadowColor: Colors.black26,
                borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(ThemeCleanPremium.radiusXl)),
                clipBehavior: Clip.antiAlias,
                child: SizedBox(
                  height: sheetH,
                  width: double.infinity,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              ThemeCleanPremium.navSidebar.withOpacity(0.09),
                              ThemeCleanPremium.surface,
                            ],
                          ),
                        ),
                        child: Column(
                          children: [
                            Center(
                              child: Container(
                                width: 40,
                                height: 4,
                                margin: const EdgeInsets.only(bottom: 10),
                                decoration: BoxDecoration(
                                  color: Colors.grey.shade400,
                                  borderRadius: BorderRadius.circular(999),
                                ),
                              ),
                            ),
                            Padding(
                              padding:
                                  const EdgeInsets.fromLTRB(12, 0, 12, 12),
                              child: Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(10),
                                    decoration: BoxDecoration(
                                      color: ThemeCleanPremium.primary
                                          .withOpacity(0.12),
                                      borderRadius: BorderRadius.circular(
                                          ThemeCleanPremium.radiusMd),
                                    ),
                                    child: Icon(
                                      Icons.badge_outlined,
                                      color: ThemeCleanPremium.primary,
                                      size: 24,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        const Text(
                                          'Emitir várias carteirinhas',
                                          style: TextStyle(
                                            fontSize: 18,
                                            fontWeight: FontWeight.w800,
                                            letterSpacing: -0.3,
                                          ),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          'Selecione os membros e gere um único PDF.',
                                          style: TextStyle(
                                            fontSize: 13,
                                            color: Colors.grey.shade700,
                                            height: 1.25,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  TextButton(
                                    onPressed: () => Navigator.pop(ctx),
                                    child: const Text('Fechar'),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      Expanded(
                        child: CustomScrollView(
                          physics: const BouncingScrollPhysics(
                              parent: AlwaysScrollableScrollPhysics()),
                          slivers: [
                            if (signatoryOptions.isNotEmpty)
                              SliverToBoxAdapter(
                                child: Padding(
                                  padding:
                                      const EdgeInsets.fromLTRB(16, 8, 16, 12),
                                  child: DropdownButtonFormField<
                                      ({
                                        String memberId,
                                        String nome,
                                        String cargo,
                                        String? assinaturaUrl
                                      })>(
                                    value: selectedSignatory,
                                    isExpanded: true,
                                    decoration: InputDecoration(
                                      labelText: 'Assinatura (quem assina)',
                                      border: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(
                                              ThemeCleanPremium.radiusSm)),
                                      contentPadding:
                                          const EdgeInsets.symmetric(
                                              horizontal: 12, vertical: 10),
                                    ),
                                    items: signatoryOptions
                                        .map((o) => DropdownMenuItem(
                                            value: o,
                                            child: Text(
                                                '${o.nome} — ${o.cargo}',
                                                overflow:
                                                    TextOverflow.ellipsis)))
                                        .toList(),
                                    onChanged: (v) =>
                                        _refreshSignatoryFromFirestore(
                                            ctx,
                                            setModal,
                                            v,
                                            (nv) =>
                                                selectedSignatory = nv),
                                  ),
                                ),
                              ),
                            SliverToBoxAdapter(
                              child: Padding(
                                padding:
                                    const EdgeInsets.fromLTRB(16, 0, 16, 8),
                                child: DropdownButtonFormField<_PdfManyLayout>(
                                  value: pdfLayout,
                                  isExpanded: true,
                                  decoration: InputDecoration(
                                    labelText: 'Papel / disposição na folha',
                                    helperText:
                                        '“5 por folha” = modelo da carteira digital, frente e verso na mesma linha por membro. Grades 2×N = 1.ª folha só frentes, 2.ª só versos.',
                                    border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(
                                            ThemeCleanPremium.radiusSm)),
                                    contentPadding: const EdgeInsets.symmetric(
                                        horizontal: 12, vertical: 10),
                                  ),
                                  items: const [
                                    DropdownMenuItem(
                                        value:
                                            _PdfManyLayout.a4FrenteVerso5PorFolha,
                                        child: Text(
                                            'A4 — 5 por folha (frente e verso na mesma linha — modelo digital — predefinição)')),
                                    DropdownMenuItem(
                                        value: _PdfManyLayout
                                            .a4FrenteSobreVerso2Digital,
                                        child: Text(
                                            'A4 — 2 por folha (frente sobre verso, como no ecrã vertical)')),
                                    DropdownMenuItem(
                                        value: _PdfManyLayout.a4OnePerPage,
                                        child: Text(
                                            'A4 — 1 por folha (centralizada)')),
                                    DropdownMenuItem(
                                        value: _PdfManyLayout.a4Grid2x2,
                                        child: Text(
                                            'A4 — 4 por folha (grade 2×2)')),
                                    DropdownMenuItem(
                                        value: _PdfManyLayout.a4Grid2x3,
                                        child: Text(
                                            'A4 — 6 por folha (grade 2×3)')),
                                    DropdownMenuItem(
                                        value: _PdfManyLayout.a4Grid2x4,
                                        child: Text(
                                            'A4 — 8 por folha (grade 2×4, jato de tinta)')),
                                    DropdownMenuItem(
                                        value: _PdfManyLayout.a4Grid2x5,
                                        child: Text(
                                            'A4 — 10 por folha (grade 2×5)')),
                                    DropdownMenuItem(
                                        value: _PdfManyLayout.cr80sheet,
                                        child: Text(
                                            'Só cartão CR80 — 1 por folha (papel especial)')),
                                    DropdownMenuItem(
                                        value: _PdfManyLayout.cr80grafica,
                                        child: Text(
                                            'CR80 + marcas de corte (gráfica / PVC)')),
                                  ],
                                  onChanged: (v) => setModal(() => pdfLayout =
                                      v ??
                                      _PdfManyLayout.a4FrenteVerso5PorFolha),
                                ),
                              ),
                            ),
                            SliverToBoxAdapter(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Padding(
                                    padding: const EdgeInsets.fromLTRB(
                                        16, 0, 16, 4),
                                    child: Align(
                                      alignment: Alignment.centerLeft,
                                      child: TextButton.icon(
                                        onPressed: () => setModal(() {
                                          pdfLayout =
                                              _PdfManyLayout.a4Grid2x4;
                                          pdfInkEconomy = true;
                                        }),
                                        icon: const Icon(
                                            Icons.grid_on_rounded,
                                            size: 20),
                                        label: const Text(
                                            'Predefinição: A4 com 8 cartões + menos tinta'),
                                      ),
                                    ),
                                  ),
                                  Padding(
                                    padding: const EdgeInsets.fromLTRB(
                                        16, 0, 16, 8),
                                    child: CheckboxListTile(
                                      value: pdfInkEconomy,
                                      onChanged: (v) => setModal(
                                          () => pdfInkEconomy = v ?? false),
                                      title: const Text(
                                          'Visual econômico (menos tinta)'),
                                      subtitle: const Text(
                                          'Desligado = mesmo modelo da carteirinha digital (cores e degradê). Ligado = fundo claro, ideal para jato de tinta.'),
                                      controlAffinity:
                                          ListTileControlAffinity.leading,
                                      contentPadding: EdgeInsets.zero,
                                    ),
                                  ),
                                  Padding(
                                    padding: const EdgeInsets.fromLTRB(
                                        16, 0, 16, 10),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.stretch,
                                      children: [
                                        Row(
                                          children: [
                                            Icon(Icons.filter_list_rounded,
                                                size: 20,
                                                color: ThemeCleanPremium
                                                    .primary),
                                            const SizedBox(width: 8),
                                            Text('Filtrar lista',
                                                style: TextStyle(
                                                    fontSize: 14,
                                                    fontWeight:
                                                        FontWeight.w800,
                                                    color: Colors
                                                        .grey.shade800)),
                                          ],
                                        ),
                                        const SizedBox(height: 10),
                                        TextField(
                                          decoration: InputDecoration(
                                            hintText: 'Nome ou CPF...',
                                            prefixIcon: const Icon(
                                                Icons.search_rounded,
                                                size: 22),
                                            border: OutlineInputBorder(
                                                borderRadius:
                                                    BorderRadius.circular(
                                                        ThemeCleanPremium
                                                            .radiusSm)),
                                            isDense: true,
                                            filled: true,
                                            fillColor: ThemeCleanPremium
                                                .surfaceVariant
                                                .withOpacity(0.65),
                                          ),
                                          onChanged: (v) => setModal(
                                              () => modalSearch = v),
                                        ),
                                        const SizedBox(height: 10),
                                        Row(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Expanded(
                                              child:
                                                  DropdownButtonFormField<
                                                      String>(
                                                value: modalGenero,
                                                isExpanded: true,
                                                decoration: InputDecoration(
                                                  labelText: 'Gênero',
                                                  border: OutlineInputBorder(
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                              ThemeCleanPremium
                                                                  .radiusSm)),
                                                  isDense: true,
                                                  contentPadding:
                                                      const EdgeInsets
                                                          .symmetric(
                                                          horizontal: 10,
                                                          vertical: 8),
                                                ),
                                                items: const [
                                                  DropdownMenuItem(
                                                      value: 'todos',
                                                      child: Text('Todos')),
                                                  DropdownMenuItem(
                                                      value: 'masculino',
                                                      child: Text('Homens')),
                                                  DropdownMenuItem(
                                                      value: 'feminino',
                                                      child:
                                                          Text('Mulheres')),
                                                ],
                                                onChanged: (v) => setModal(
                                                    () => modalGenero =
                                                        v ?? 'todos'),
                                              ),
                                            ),
                                            const SizedBox(width: 8),
                                            Expanded(
                                              child:
                                                  DropdownButtonFormField<
                                                      String>(
                                                value: modalFaixa,
                                                isExpanded: true,
                                                decoration: InputDecoration(
                                                  labelText: 'Faixa etária',
                                                  border: OutlineInputBorder(
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                              ThemeCleanPremium
                                                                  .radiusSm)),
                                                  isDense: true,
                                                  contentPadding:
                                                      const EdgeInsets
                                                          .symmetric(
                                                          horizontal: 10,
                                                          vertical: 8),
                                                ),
                                                items: const [
                                                  DropdownMenuItem(
                                                      value: 'todas',
                                                      child: Text('Todas')),
                                                  DropdownMenuItem(
                                                      value: 'criancas',
                                                      child: Text(
                                                          'Crianças (<13)')),
                                                  DropdownMenuItem(
                                                      value: 'adolescentes',
                                                      child: Text(
                                                          'Adolescentes')),
                                                  DropdownMenuItem(
                                                      value: 'adultos',
                                                      child:
                                                          Text('Adultos')),
                                                  DropdownMenuItem(
                                                      value: 'idosos',
                                                      child: Text(
                                                          'Idosos (60+)')),
                                                ],
                                                onChanged: (v) => setModal(
                                                    () => modalFaixa =
                                                        v ?? 'todas'),
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 8),
                                        DropdownButtonFormField<String>(
                                          value: modalDept,
                                          isExpanded: true,
                                          decoration: InputDecoration(
                                            labelText: 'Departamento',
                                            border: OutlineInputBorder(
                                                borderRadius:
                                                    BorderRadius.circular(
                                                        ThemeCleanPremium
                                                            .radiusSm)),
                                            isDense: true,
                                            contentPadding:
                                                const EdgeInsets.symmetric(
                                                    horizontal: 12,
                                                    vertical: 10),
                                          ),
                                          items: [
                                            const DropdownMenuItem(
                                                value: 'todos',
                                                child: Text('Todos')),
                                            ...deptsModal.map(
                                                (d) => DropdownMenuItem(
                                                    value: d.id,
                                                    child: Text(d.name,
                                                        overflow: TextOverflow
                                                            .ellipsis))),
                                          ],
                                          onChanged: (v) => setModal(() =>
                                              modalDept = v ?? 'todos'),
                                        ),
                                        const SizedBox(height: 8),
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 12, vertical: 8),
                                          decoration: BoxDecoration(
                                            color: ThemeCleanPremium.primary
                                                .withOpacity(0.07),
                                            borderRadius:
                                                BorderRadius.circular(
                                                    ThemeCleanPremium
                                                        .radiusSm),
                                            border: Border.all(
                                                color: ThemeCleanPremium
                                                    .primary
                                                    .withOpacity(0.18)),
                                          ),
                                          child: Text(
                                            'Mostrando ${visible.length} de ${emitMembers.length} membros',
                                            style: TextStyle(
                                                fontSize: 13,
                                                fontWeight: FontWeight.w600,
                                                color:
                                                    ThemeCleanPremium.primary),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SliverToBoxAdapter(
                                child: Divider(height: 1)),
                            if (visible.isEmpty)
                              SliverFillRemaining(
                                hasScrollBody: false,
                                child: Center(
                                  child: Padding(
                                    padding: EdgeInsets.all(24),
                                    child: Text(
                                      'Nenhum membro com esses filtros.',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                          color: Colors.grey,
                                          fontSize: 15),
                                    ),
                                  ),
                                ),
                              )
                            else
                              SliverList(
                                delegate: SliverChildBuilderDelegate(
                                  (context, i) {
                                    final m = visible[i];
                                    final sel =
                                        selectedIds.contains(m.id);
                                    return Material(
                                      color: i.isEven
                                          ? Colors.transparent
                                          : ThemeCleanPremium.surfaceVariant
                                              .withOpacity(0.35),
                                      child: CheckboxListTile(
                                        value: sel,
                                        dense: true,
                                        onChanged: (v) => setModal(() =>
                                            v == true
                                                ? selectedIds.add(m.id)
                                                : selectedIds.remove(m.id)),
                                        title: Text(m.name,
                                            overflow:
                                                TextOverflow.ellipsis,
                                            style: const TextStyle(
                                                fontWeight:
                                                    FontWeight.w500)),
                                        secondary: Icon(
                                            Icons.person_outline_rounded,
                                            color: ThemeCleanPremium.primary
                                                .withOpacity(0.85)),
                                      ),
                                    );
                                  },
                                  childCount: visible.length,
                                ),
                              ),
                          ],
                        ),
                      ),
                Container(
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: ThemeCleanPremium.surface,
                    border: Border(
                      top: BorderSide(
                          color: ThemeCleanPremium.primary.withOpacity(0.12)),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.06),
                        blurRadius: 10,
                        offset: const Offset(0, -2),
                      ),
                    ],
                  ),
                  child: SafeArea(
                    top: false,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
                      child: SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                      onPressed: selectedIds.isEmpty
                          ? null
                          : () async {
                              Navigator.pop(ctx);
                              final ids = selectedIds.toList();
                              final list = <_CardData>[];
                              for (final id in ids) {
                                try {
                                  final doc = await membersCol.doc(id).get();
                                  if (doc.exists) {
                                    var m = Map<String, dynamic>.from(
                                        doc.data() ?? {});
                                    m = await _enrichMemberCarteirinhaSignatureFromSignatory(
                                        m,
                                        igrejaDocId: tpl.igrejaDocId);
                                    list.add(_CardData(
                                      memberId: doc.id,
                                      member: m,
                                      cardConfig: cardCfg,
                                      tenant: tenant,
                                      igrejaDocId: tpl.igrejaDocId,
                                    ));
                                  } else {
                                    final snap = await MemberDocumentResolve
                                        .findByHint(membersCol, id);
                                    if (snap == null || !snap.exists) continue;
                                    var m = Map<String, dynamic>.from(
                                        snap.data() ?? {});
                                    m = await _enrichMemberCarteirinhaSignatureFromSignatory(
                                        m,
                                        igrejaDocId: tpl.igrejaDocId);
                                    list.add(_CardData(
                                      memberId: snap.id,
                                      member: m,
                                      cardConfig: cardCfg,
                                      tenant: tenant,
                                      igrejaDocId: tpl.igrejaDocId,
                                    ));
                                  }
                                } catch (_) {}
                              }
                              if (list.isEmpty) {
                                if (context.mounted)
                                  ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                          content: Text(
                                              'Nenhum membro válido selecionado.')));
                                return;
                              }
                              try {
                                ({
                                  String memberId,
                                  String nome,
                                  String cargo,
                                  String? assinaturaUrl,
                                })? sigEmit = selectedSignatory;
                                if (sigEmit != null) {
                                  sigEmit =
                                      await _fetchSignatoryAssinaturaFresh(
                                          sigEmit);
                                }
                                final lay = _pdfManyLayoutParams(pdfLayout);
                                final isA4Grid = pdfLayout ==
                                        _PdfManyLayout.a4FrenteVerso5PorFolha ||
                                    pdfLayout ==
                                        _PdfManyLayout
                                            .a4FrenteSobreVerso2Digital ||
                                    pdfLayout == _PdfManyLayout.a4Grid2x2 ||
                                    pdfLayout == _PdfManyLayout.a4Grid2x3 ||
                                    pdfLayout == _PdfManyLayout.a4Grid2x4 ||
                                    pdfLayout == _PdfManyLayout.a4Grid2x5;
                                late final Uint8List bytes;
                                if (pdfLayout ==
                                    _PdfManyLayout.a4FrenteSobreVerso2Digital) {
                                  var pastorSig = '';
                                  try {
                                    pastorSig = (await FirebaseStorageService
                                                .getPastorSignatureConfigDownloadUrl(
                                                    list.first.igrejaDocId) ??
                                            '')
                                        .trim();
                                  } catch (_) {}
                                  try {
                                    bytes = await _buildPdfMultiWalletRaster(
                                      context,
                                      list,
                                      signatoryNome: sigEmit?.nome,
                                      signatoryCargo: sigEmit?.cargo,
                                      signatoryAssinaturaUrl:
                                          sigEmit?.assinaturaUrl,
                                      pastorSigFallback: pastorSig,
                                    );
                                  } catch (e, st) {
                                    debugPrint(
                                        'emitir vários: raster falhou, PDF vetorial: $e\n$st');
                                    bytes = await _buildPdfMulti(
                                      list,
                                      lay.format,
                                      signatoryNome: sigEmit?.nome,
                                      signatoryCargo: sigEmit?.cargo,
                                      signatoryAssinaturaUrl:
                                          sigEmit?.assinaturaUrl,
                                      gridCols: lay.cols,
                                      gridRows: lay.rows,
                                      pvcCropMarks: lay.pvcCrop,
                                      inkEconomy: pdfInkEconomy,
                                      frontVersoPorLinha:
                                          lay.frontVersoPorLinha,
                                      digitalVerticalStack:
                                          lay.digitalVerticalStack,
                                    );
                                  }
                                } else if (pdfLayout ==
                                        _PdfManyLayout.a4FrenteVerso5PorFolha &&
                                    !pdfInkEconomy) {
                                  var pastorSig = '';
                                  try {
                                    pastorSig = (await FirebaseStorageService
                                                .getPastorSignatureConfigDownloadUrl(
                                                    list.first.igrejaDocId) ??
                                            '')
                                        .trim();
                                  } catch (_) {}
                                  try {
                                    bytes =
                                        await _buildPdfMultiWalletRasterFrenteVersoLinhaA4(
                                      context,
                                      list,
                                      signatoryNome: sigEmit?.nome,
                                      signatoryCargo: sigEmit?.cargo,
                                      signatoryAssinaturaUrl:
                                          sigEmit?.assinaturaUrl,
                                      pastorSigFallback: pastorSig,
                                    );
                                  } catch (e, st) {
                                    debugPrint(
                                        'emitir vários: raster frente|verso falhou, PDF vetorial: $e\n$st');
                                    bytes = await _buildPdfMulti(
                                      list,
                                      lay.format,
                                      signatoryNome: sigEmit?.nome,
                                      signatoryCargo: sigEmit?.cargo,
                                      signatoryAssinaturaUrl:
                                          sigEmit?.assinaturaUrl,
                                      gridCols: lay.cols,
                                      gridRows: lay.rows,
                                      pvcCropMarks: lay.pvcCrop,
                                      inkEconomy: pdfInkEconomy,
                                      frontVersoPorLinha:
                                          lay.frontVersoPorLinha,
                                      digitalVerticalStack:
                                          lay.digitalVerticalStack,
                                    );
                                  }
                                } else {
                                  bytes = await _buildPdfMulti(
                                    list,
                                    lay.format,
                                    signatoryNome: sigEmit?.nome,
                                    signatoryCargo: sigEmit?.cargo,
                                    signatoryAssinaturaUrl: sigEmit?.assinaturaUrl,
                                    gridCols: lay.cols,
                                    gridRows: lay.rows,
                                    pvcCropMarks: lay.pvcCrop,
                                    inkEconomy: pdfInkEconomy,
                                    frontVersoPorLinha: lay.frontVersoPorLinha,
                                    digitalVerticalStack:
                                        lay.digitalVerticalStack,
                                  );
                                }
                                if (context.mounted)
                                  await showPdfActions(context,
                                      bytes: bytes,
                                      filename: isA4Grid
                                          ? 'carteirinhas_A4_${list.length}.pdf'
                                          : 'carteirinhas_${list.length}.pdf');
                              } catch (e) {
                                if (context.mounted)
                                  ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(content: Text('Erro: $e')));
                              }
                            },
                      icon: const Icon(Icons.picture_as_pdf_rounded),
                      label: Text(
                        (pdfLayout == _PdfManyLayout.a4FrenteVerso5PorFolha ||
                                pdfLayout ==
                                    _PdfManyLayout.a4FrenteSobreVerso2Digital ||
                                pdfLayout == _PdfManyLayout.a4Grid2x2 ||
                                pdfLayout == _PdfManyLayout.a4Grid2x3 ||
                                pdfLayout == _PdfManyLayout.a4Grid2x4 ||
                                pdfLayout == _PdfManyLayout.a4Grid2x5)
                            ? 'Gerar PDF para impressão (A4) — ${selectedIds.length}'
                            : 'Gerar PDF (${selectedIds.length} selecionados)',
                      ),
                      style: FilledButton.styleFrom(
                          backgroundColor: ThemeCleanPremium.primary),
                    ),
                      ),
                    ),
                  ),
                ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Future<({int ok, int fail, String? lastErr})> _firestoreAssinaturaLote(
    List<String> ids,
    ({
      String memberId,
      String nome,
      String cargo,
      String? assinaturaUrl
    }) signat,
  ) async {
    if (ids.isEmpty) return (ok: 0, fail: 0, lastErr: null);
    final db = FirebaseFirestore.instance;
    final membersCol =
        db.collection('igrejas').doc(widget.tenantId).collection('membros');
    final payload = <String, dynamic>{
      'carteirinhaAssinadaEm': FieldValue.serverTimestamp(),
      'carteirinhaAssinadaPor': signat.memberId,
      'carteirinhaAssinadaPorNome': signat.nome,
      'carteirinhaAssinadaPorCargo': signat.cargo,
      'carteirinhaAssinaturaUrl': signat.assinaturaUrl ?? FieldValue.delete(),
    };
    var ok = 0;
    var fail = 0;
    String? lastErr;
    const chunkSize = 400;
    for (var i = 0; i < ids.length; i += chunkSize) {
      final end = min(i + chunkSize, ids.length);
      final chunk = ids.sublist(i, end);
      final batch = db.batch();
      for (final id in chunk) {
        batch.set(membersCol.doc(id), payload, SetOptions(merge: true));
      }
      try {
        await batch.commit();
        ok += chunk.length;
      } catch (e, st) {
        debugPrint('Assinatura em lote (batch): $e\n$st');
        lastErr = e.toString();
        for (final id in chunk) {
          try {
            await membersCol.doc(id).set(payload, SetOptions(merge: true));
            ok++;
          } catch (e2, st2) {
            fail++;
            lastErr = e2.toString();
            debugPrint('Assinatura membro $id: $e2\n$st2');
          }
        }
      }
    }
    return (ok: ok, fail: fail, lastErr: lastErr);
  }

  void _snackFirestoreAssinaturaResult(
      BuildContext context, ({int ok, int fail, String? lastErr}) r) {
    if (!context.mounted) return;
    final lastErr = r.lastErr;
    final errTail = lastErr == null
        ? 'Verifique permissões e conexão.'
        : (lastErr.length > 120
            ? 'Último erro: ${lastErr.substring(0, 120)}…'
            : 'Último erro: $lastErr');
    final msg = r.fail == 0
        ? '${r.ok} carteirinha(s) assinada(s) com sucesso.'
        : '${r.ok} ok, ${r.fail} falha(s). $errTail';
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg), duration: const Duration(seconds: 6)));
  }

  Future<void> _abrirAssinarEmLote(BuildContext context) async {
    String? defaultSigId;
    try {
      final snap = await FirebaseFirestore.instance
          .collection('igrejas')
          .doc(widget.tenantId)
          .collection('config')
          .doc('carteira')
          .get();
      if (snap.exists && snap.data() != null) {
        final v =
            (snap.data()!['defaultSignatoryMemberId'] ?? '').toString().trim();
        if (v.isNotEmpty) defaultSigId = v;
      }
    } catch (_) {}

    final options = await _loadSignatoryOptions();
    if (options.isEmpty && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
              'Cadastre assinatura em Membros → Editar para quem tem cargo além de membro (pastor, tesoureiro, líder etc.).'),
        ),
      );
      return;
    }
    final db = FirebaseFirestore.instance;
    final membersCol =
        db.collection('igrejas').doc(widget.tenantId).collection('membros');
    final List<({String id, String name})> members = [];
    try {
      final snap = await membersCol.limit(500).get();
      for (final d in snap.docs) {
        final m = d.data();
        members.add((
          id: d.id,
          name: (m['NOME_COMPLETO'] ?? m['nome'] ?? d.id).toString()
        ));
      }
    } catch (_) {}
    if (members.isEmpty && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Nenhum membro encontrado.')));
      return;
    }
    if (!context.mounted) return;
    var selected = _selectSignatory(options, defaultSigId);
    Future<void> aplicarAssinaturaEmIds(
        List<String> ids,
        ({
          String memberId,
          String nome,
          String cargo,
          String? assinaturaUrl
        }) signat) async {
      final r = await _firestoreAssinaturaLote(ids, signat);
      _snackFirestoreAssinaturaResult(context, r);
    }

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModal) {
          final maxH = MediaQuery.of(ctx).size.height * 0.9;
          return Container(
            constraints: BoxConstraints(maxHeight: maxH),
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(
                  top: Radius.circular(ThemeCleanPremium.radiusLg)),
            ),
            child: SingleChildScrollView(
              padding: EdgeInsets.only(
                left: 24,
                right: 24,
                top: 24,
                bottom: 24 + MediaQuery.of(ctx).viewPadding.bottom,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text('Assinar carteirinhas em lote',
                      style:
                          TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 8),
                  Text(
                    'Escolha o signatário e assine todas ou por seleção. Os dados são gravados no Firestore em lotes (mais rápido e confiável).',
                    style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<
                      ({
                        String memberId,
                        String nome,
                        String cargo,
                        String? assinaturaUrl
                      })>(
                    value: selected,
                    isExpanded: true,
                    decoration: InputDecoration(
                      labelText: 'Quem assina',
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(
                              ThemeCleanPremium.radiusSm)),
                    ),
                    items: options
                        .map((o) => DropdownMenuItem(
                            value: o,
                            child: Text('${o.nome} — ${o.cargo}',
                                overflow: TextOverflow.ellipsis)))
                        .toList(),
                    onChanged: (v) => _refreshSignatoryFromFirestore(
                        ctx, setModal, v, (nv) => selected = nv),
                  ),
                  if (selected != null &&
                      (selected!.assinaturaUrl == null ||
                          selected!.assinaturaUrl!.trim().isEmpty))
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Text(
                        'Atenção: este signatário não tem imagem de assinatura no cadastro. O nome aparecerá no PDF, mas a imagem só após cadastrar a assinatura em Membros → Editar.',
                        style: TextStyle(
                            fontSize: 12, color: Colors.orange.shade800),
                      ),
                    ),
                  const SizedBox(height: 20),
                  FilledButton.icon(
                    onPressed: selected == null
                        ? null
                        : () async {
                            Navigator.pop(ctx);
                            await aplicarAssinaturaEmIds(
                                members.map((e) => e.id).toList(), selected!);
                          },
                    icon: const Icon(Icons.check_circle_rounded),
                    label: Text('Assinar todas (${members.length} membros)'),
                    style: FilledButton.styleFrom(
                        backgroundColor: ThemeCleanPremium.primary),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: selected == null
                        ? null
                        : () async {
                            Navigator.pop(ctx);
                            final selectedIds = <String>{};
                            await showModalBottomSheet<void>(
                              context: context,
                              isScrollControlled: true,
                              backgroundColor: Colors.transparent,
                              builder: (ctx2) => StatefulBuilder(
                                builder: (ctx2, setSel) => Container(
                                  constraints: BoxConstraints(
                                      maxHeight:
                                          MediaQuery.of(ctx2).size.height *
                                              0.72),
                                  decoration: const BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.vertical(
                                        top: Radius.circular(
                                            ThemeCleanPremium.radiusLg)),
                                  ),
                                  child: Column(
                                    children: [
                                      Padding(
                                        padding: const EdgeInsets.fromLTRB(
                                            16, 16, 8, 0),
                                        child: Row(
                                          children: [
                                            const Expanded(
                                              child: Text(
                                                  'Selecionar membros para assinar',
                                                  style: TextStyle(
                                                      fontSize: 16,
                                                      fontWeight:
                                                          FontWeight.w700)),
                                            ),
                                            TextButton(
                                                onPressed: () =>
                                                    Navigator.pop(ctx2),
                                                child: const Text('Fechar')),
                                          ],
                                        ),
                                      ),
                                      const Divider(),
                                      Expanded(
                                        child: ListView.builder(
                                          itemCount: members.length,
                                          itemBuilder: (_, i) {
                                            final m = members[i];
                                            final sel =
                                                selectedIds.contains(m.id);
                                            return CheckboxListTile(
                                              value: sel,
                                              onChanged: (v) => setSel(() =>
                                                  v == true
                                                      ? selectedIds.add(m.id)
                                                      : selectedIds
                                                          .remove(m.id)),
                                              title: Text(m.name),
                                            );
                                          },
                                        ),
                                      ),
                                      Padding(
                                        padding: const EdgeInsets.all(16),
                                        child: FilledButton.icon(
                                          onPressed: selectedIds.isEmpty
                                              ? null
                                              : () async {
                                                  Navigator.pop(ctx2);
                                                  await aplicarAssinaturaEmIds(
                                                      selectedIds.toList(),
                                                      selected!);
                                                },
                                          icon: const Icon(Icons.draw_rounded),
                                          label: Text(
                                              'Assinar selecionados (${selectedIds.length})'),
                                          style: FilledButton.styleFrom(
                                              backgroundColor:
                                                  ThemeCleanPremium.primary),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          },
                    icon: const Icon(Icons.list_rounded),
                    label: const Text('Assinar por seleção'),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  bool get _emModoListaGestor {
    if (!_canManage || _isRestrictedMember) return false;
    final mid = (widget.memberId ?? '').trim();
    return mid.isEmpty;
  }

  String _safeMemberFileStub(String id) {
    final s = id.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
    return s.isEmpty ? 'membro' : s.substring(0, s.length > 40 ? 40 : s.length);
  }

  /// Lista da tela inicial: assinatura em bloco com ZIP e opção certificado (PAdES = stub até integração).
  Future<void> _abrirAssinaturaBlocoSelecionados(BuildContext context) async {
    final ids = _carteiraListaSelecionados.toList();
    if (ids.isEmpty) return;

    final modo = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(
              top: Radius.circular(ThemeCleanPremium.radiusLg)),
        ),
        padding: EdgeInsets.fromLTRB(
            24, 20, 24, 24 + MediaQuery.of(ctx).padding.bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Assinar ${_carteiraListaSelecionados.length} selecionado(s)',
                style:
                    const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            Text(
                'Assinatura visual: um PDF único para visualizar (frente + verso por membro), depois gravamos a assinatura no cadastro. Certificado digital continua em ZIP com um PDF por membro.',
                style: TextStyle(fontSize: 13, color: Colors.grey.shade600)),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: () => Navigator.pop(ctx, 'visual'),
              icon: const Icon(Icons.draw_rounded),
              label: const Text('Assinatura visual (imagem do líder)'),
              style: FilledButton.styleFrom(
                  backgroundColor: ThemeCleanPremium.primary,
                  padding: const EdgeInsets.symmetric(vertical: 14)),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: () => Navigator.pop(ctx, 'cert'),
              icon: const Icon(Icons.verified_user_rounded),
              label: const Text(
                  'Certificado digital (A1 / A3 — PAdES em roadmap)'),
            ),
            const SizedBox(height: 8),
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancelar')),
          ],
        ),
      ),
    );
    if (!context.mounted || modo == null) return;

    final options = await _loadSignatoryOptions();
    if (modo == 'visual' && options.isEmpty) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text(
                  'Cadastre a assinatura visual dos líderes em Membros → Editar.')),
        );
      }
      return;
    }

    String? defaultSigId;
    try {
      final snap = await FirebaseFirestore.instance
          .collection('igrejas')
          .doc(widget.tenantId)
          .collection('config')
          .doc('carteira')
          .get();
      defaultSigId =
          (snap.data()?['defaultSignatoryMemberId'] ?? '').toString().trim();
    } catch (_) {}

    final defSig = (defaultSigId ?? '').trim();
    ({
      String memberId,
      String nome,
      String cargo,
      String? assinaturaUrl
    })? selected = modo == 'visual'
        ? _selectSignatory(options, defSig.isEmpty ? null : defSig)
        : null;

    if (modo == 'visual') {
      if (!context.mounted) return;
      final okPick = await showDialog<bool>(
        context: context,
        builder: (ctx2) => AlertDialog(
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusMd)),
          title: const Text('Quem assina?'),
          content: StatefulBuilder(
            builder: (ctx3, setLocal) {
              return DropdownButtonFormField<
                  ({
                    String memberId,
                    String nome,
                    String cargo,
                    String? assinaturaUrl
                  })>(
                value: selected,
                isExpanded: true,
                decoration: InputDecoration(
                  labelText: 'Signatário',
                  border: OutlineInputBorder(
                      borderRadius:
                          BorderRadius.circular(ThemeCleanPremium.radiusSm)),
                ),
                items: options
                    .map((o) => DropdownMenuItem(
                        value: o,
                        child: Text('${o.nome} — ${o.cargo}',
                            overflow: TextOverflow.ellipsis)))
                    .toList(),
                onChanged: (v) async {
                  if (v == null) return;
                  await _refreshSignatoryFromFirestore(
                      ctx3, setLocal, v, (nv) => selected = nv);
                  setLocal(() {});
                },
              );
            },
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx2, false),
                child: const Text('Cancelar')),
            FilledButton(
                onPressed: () => Navigator.pop(ctx2, true),
                child: const Text('Continuar')),
          ],
        ),
      );
      if (okPick != true || selected == null) return;
    }

    String certPin = '';
    if (modo == 'cert') {
      if (!context.mounted) return;
      const storage = FlutterSecureStorage();
      final keyPin = 'carteira_pfx_pin_${widget.tenantId}';
      String? saved;
      try {
        saved = await storage.read(key: keyPin);
      } catch (_) {}
      if (!context.mounted) return;
      final pinCtrl = TextEditingController(text: saved ?? '');
      var lembrarPin = false;
      final go = await showDialog<bool>(
        context: context,
        builder: (ctx2) => StatefulBuilder(
          builder: (ctx3, setSt) => AlertDialog(
            shape: RoundedRectangleBorder(
                borderRadius:
                    BorderRadius.circular(ThemeCleanPremium.radiusMd)),
            title: const Text('PIN do certificado (.p12)'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: pinCtrl,
                  obscureText: true,
                  decoration:
                      const InputDecoration(labelText: 'Senha do certificado'),
                ),
                CheckboxListTile(
                  value: lembrarPin,
                  onChanged: (v) => setSt(() => lembrarPin = v ?? false),
                  title: const Text(
                      'Lembrar neste aparelho (armazenamento seguro)'),
                  controlAffinity: ListTileControlAffinity.leading,
                  contentPadding: EdgeInsets.zero,
                ),
              ],
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx2, false),
                  child: const Text('Cancelar')),
              FilledButton(
                  onPressed: () => Navigator.pop(ctx2, true),
                  child: const Text('Processar')),
            ],
          ),
        ),
      );
      certPin = pinCtrl.text.trim();
      pinCtrl.dispose();
      if (go != true) return;
      if (lembrarPin && certPin.isNotEmpty) {
        try {
          await storage.write(key: keyPin, value: certPin);
        } catch (_) {}
      }
    }

    if (!context.mounted) return;
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctxP) => PopScope(
        canPop: false,
        child: AlertDialog(
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusMd)),
          content: Row(
            children: [
              const CircularProgressIndicator(),
              const SizedBox(width: 20),
              Expanded(
                  child: Text(modo == 'cert'
                      ? 'Gerando PDFs e preparando certificado…'
                      : 'Gerando PDFs e gravando assinaturas…')),
            ],
          ),
        ),
      ),
    );

    Uint8List? p12bytes;
    if (modo == 'cert') {
      final path = await CertificadoDigitalService.storagePathForCurrentUser();
      if (path != null && path.isNotEmpty) {
        p12bytes =
            await CertificadoDigitalService.downloadCertificateBytes(path);
      }
    }

    final zipEntries = <String, Uint8List>{};
    String? padesMsg;
    try {
      final tpl = await _loadCarteiraTemplateContext();
      final signat = selected;

      if (modo == 'visual' && signat != null) {
        final signatFresh = await _fetchSignatoryAssinaturaFresh(signat);
        final list = <_CardData>[];
        for (final id in ids) {
          final card = await _cardDataForMemberId(
              id, tpl.tenant, tpl.cardCfg, tpl.igrejaDocId);
          if (card == null) continue;
          await preLoadImages(card,
              signatoryAssinaturaUrl: signatFresh.assinaturaUrl);
          list.add(card);
        }
        if (context.mounted) Navigator.of(context).pop();
        if (list.isEmpty) {
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                content: Text('Nenhum PDF gerado (membros não encontrados).')));
          }
          return;
        }
        final layVisual =
            _pdfManyLayoutParams(_PdfManyLayout.a4FrenteSobreVerso2Digital);
        late final Uint8List merged;
        var pastorSig = '';
        try {
          pastorSig = (await FirebaseStorageService
                      .getPastorSignatureConfigDownloadUrl(
                          list.first.igrejaDocId) ??
                  '')
              .trim();
        } catch (_) {}
        try {
          merged = await _buildPdfMultiWalletRaster(
            context,
            list,
            signatoryNome: signatFresh.nome,
            signatoryCargo: signatFresh.cargo,
            signatoryAssinaturaUrl: signatFresh.assinaturaUrl,
            pastorSigFallback: pastorSig,
          );
        } catch (e, st) {
          debugPrint(
              'assinatura lote visual: raster falhou, vetor: $e\n$st');
          merged = await _buildPdfMulti(
            list,
            layVisual.format,
            signatoryNome: signatFresh.nome,
            signatoryCargo: signatFresh.cargo,
            signatoryAssinaturaUrl: signatFresh.assinaturaUrl,
            gridCols: layVisual.cols,
            gridRows: layVisual.rows,
            pvcCropMarks: layVisual.pvcCrop,
            inkEconomy: false,
            frontVersoPorLinha: layVisual.frontVersoPorLinha,
            digitalVerticalStack: layVisual.digitalVerticalStack,
          );
        }
        if (context.mounted) {
          final r = await _firestoreAssinaturaLote(ids, signatFresh);
          _snackFirestoreAssinaturaResult(context, r);
        }
        if (context.mounted) {
          await showPdfActions(
            context,
            bytes: merged,
            filename:
                'carteirinhas_assinadas_${list.length}_${DateTime.now().millisecondsSinceEpoch}.pdf',
          );
        }
        if (mounted) {
          setState(() {
            _carteiraListaSelecionados.clear();
            _loadFuture = _load();
          });
        }
        return;
      }

      for (final id in ids) {
        final card = await _cardDataForMemberId(
            id, tpl.tenant, tpl.cardCfg, tpl.igrejaDocId);
        if (card == null) continue;
        await preLoadImages(card);
        final cfgPdf = _cardConfigForPdf(card);
        var bytes = await _buildPdf(
          card,
          _kPdfCr80Export,
          configOverride: cfgPdf,
          signatoryNome: null,
          signatoryCargo: null,
          signatoryAssinaturaUrl: null,
        );
        if (modo == 'cert') {
          final out = await CarteiraPadesSigner.applyPadesIfPossible(
            pdfBytes: bytes,
            p12Bytes: p12bytes,
            certificatePassword: certPin,
          );
          bytes = out.pdfBytes;
          padesMsg ??= out.message;
        }
        zipEntries['carteirinha_${_safeMemberFileStub(id)}.pdf'] = bytes;
      }

      if (context.mounted) Navigator.of(context).pop();

      if (zipEntries.isEmpty) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text('Nenhum PDF gerado (membros não encontrados).')));
        }
        return;
      }

      final zipBytes = CarteirinhaZipExport.buildZip(zipEntries);
      final fname =
          'carteirinhas_${ids.length}_${DateTime.now().millisecondsSinceEpoch}.zip';
      await Share.shareXFiles(
          [XFile.fromData(zipBytes, name: fname, mimeType: 'application/zip')]);

      final pm = padesMsg;
      if (context.mounted && (pm != null && pm.isNotEmpty)) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(pm), duration: const Duration(seconds: 8)));
      }
      if (mounted) {
        setState(() {
          _carteiraListaSelecionados.clear();
          _loadFuture = _load();
        });
      }
    } catch (e, st) {
      debugPrint('_abrirAssinaturaBlocoSelecionados: $e\n$st');
      if (context.mounted) {
        if (Navigator.of(context).canPop()) Navigator.of(context).pop();
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Erro: $e')));
      }
    }
  }

  /// Um único PDF (frente + verso por membro) para gráfica ou WhatsApp — com progresso.
  Future<void> _gerarPdfUnicoLote(BuildContext context) async {
    final ids = List<String>.from(_carteiraListaSelecionados);
    if (ids.isEmpty || !_canManage) return;

    final options = await _loadSignatoryOptions();
    if (!context.mounted) return;

    String? defaultSigId;
    try {
      final snap = await FirebaseFirestore.instance
          .collection('igrejas')
          .doc(widget.tenantId)
          .collection('config')
          .doc('carteira')
          .get();
      defaultSigId =
          (snap.data()?['defaultSignatoryMemberId'] ?? '').toString().trim();
    } catch (_) {}

    final defSig = (defaultSigId ?? '').trim();
    var incluirAssinatura = options.isNotEmpty;
    var selected = _selectSignatory(options, defSig.isEmpty ? null : defSig);

    var pdfLayoutLote = _PdfManyLayout.a4FrenteVerso5PorFolha;
    final go = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModal) => Container(
          padding: EdgeInsets.fromLTRB(
              24, 20, 24, 24 + MediaQuery.of(ctx).viewInsets.bottom),
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(
                top: Radius.circular(ThemeCleanPremium.radiusLg)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('PDF em lote — ${ids.length} carteirinha(s)',
                  style: const TextStyle(
                      fontSize: 18, fontWeight: FontWeight.w800)),
              const SizedBox(height: 8),
              Text(
                'Um único PDF: por defeito, cada membro com frente e verso na mesma linha (até 5 por folha A4), igual ao modelo da carteira no módulo Membro.',
                style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<_PdfManyLayout>(
                value: pdfLayoutLote,
                isExpanded: true,
                decoration: InputDecoration(
                  labelText: 'Disposição no papel A4',
                  helperText:
                      'Predefinição: 5 por folha, frente e verso lado a lado (captura do ecrã). Grades 2×N: 1.ª folha só frentes, 2.ª só versos.',
                  border: OutlineInputBorder(
                      borderRadius:
                          BorderRadius.circular(ThemeCleanPremium.radiusSm)),
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 10),
                ),
                items: const [
                  DropdownMenuItem(
                      value: _PdfManyLayout.a4FrenteVerso5PorFolha,
                      child: Text(
                          '5 por folha — frente e verso na mesma linha (modelo digital — predefinição)')),
                  DropdownMenuItem(
                      value: _PdfManyLayout.a4FrenteSobreVerso2Digital,
                      child: Text(
                          '2 por folha — frente sobre verso (como no ecrã vertical)')),
                  DropdownMenuItem(
                      value: _PdfManyLayout.a4OnePerPage,
                      child: Text('1 por folha (maior no centro)')),
                  DropdownMenuItem(
                      value: _PdfManyLayout.a4Grid2x2,
                      child: Text('4 por folha — grelha 2×2')),
                  DropdownMenuItem(
                      value: _PdfManyLayout.a4Grid2x3,
                      child: Text('6 por folha — grelha 2×3')),
                  DropdownMenuItem(
                      value: _PdfManyLayout.a4Grid2x4,
                      child: Text('8 por folha — grelha 2×4')),
                  DropdownMenuItem(
                      value: _PdfManyLayout.a4Grid2x5,
                      child: Text('10 por folha — grelha 2×5')),
                ],
                onChanged: (v) => setModal(
                    () => pdfLayoutLote =
                        v ?? _PdfManyLayout.a4FrenteVerso5PorFolha),
              ),
              const SizedBox(height: 16),
              CheckboxListTile(
                value: incluirAssinatura,
                onChanged: options.isEmpty
                    ? null
                    : (v) => setModal(() {
                          incluirAssinatura = v ?? false;
                        }),
                title: const Text('Incluir assinatura visual do líder'),
                controlAffinity: ListTileControlAffinity.leading,
                contentPadding: EdgeInsets.zero,
              ),
              if (incluirAssinatura && options.isNotEmpty) ...[
                const SizedBox(height: 8),
                DropdownButtonFormField<
                    ({
                      String memberId,
                      String nome,
                      String cargo,
                      String? assinaturaUrl
                    })>(
                  value: selected,
                  isExpanded: true,
                  decoration: InputDecoration(
                    labelText: 'Quem assina',
                    border: OutlineInputBorder(
                        borderRadius:
                            BorderRadius.circular(ThemeCleanPremium.radiusSm)),
                  ),
                  items: options
                      .map((o) => DropdownMenuItem(
                          value: o,
                          child: Text('${o.nome} — ${o.cargo}',
                              overflow: TextOverflow.ellipsis)))
                      .toList(),
                  onChanged: (v) async {
                    if (v == null) return;
                    await _refreshSignatoryFromFirestore(
                        ctx, setModal, v, (nv) => selected = nv);
                    setModal(() {});
                  },
                ),
              ],
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                      child: OutlinedButton(
                          onPressed: () => Navigator.pop(ctx, false),
                          child: const Text('Cancelar'))),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () {
                        if (incluirAssinatura && selected == null) return;
                        Navigator.pop(ctx, true);
                      },
                      icon: const Icon(Icons.picture_as_pdf_rounded),
                      label: const Text('Gerar'),
                      style: FilledButton.styleFrom(
                          backgroundColor: ThemeCleanPremium.primary),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    if (go != true || !context.mounted) return;
    if (incluirAssinatura && selected == null) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Selecione quem assina.')));
      return;
    }

    final prog = ValueNotifier<double>(0);
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => ValueListenableBuilder<double>(
        valueListenable: prog,
        builder: (_, p, __) => PopScope(
          canPop: false,
          child: AlertDialog(
            shape: RoundedRectangleBorder(
                borderRadius:
                    BorderRadius.circular(ThemeCleanPremium.radiusMd)),
            title: const Text('Gerando PDF'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                LinearProgressIndicator(
                  value: ids.length <= 1
                      ? null
                      : (ids.isEmpty ? null : p.clamp(0.0, 1.0)),
                ),
                const SizedBox(height: 16),
                Text(
                  p < 0.14
                      ? 'A carregar membros e identidade visual (logo)…'
                      : (p < 0.24
                          ? 'A finalizar branding…'
                          : (p < 0.93
                              ? 'A preparar fotos (em paralelo)…'
                              : 'A montar o PDF…')),
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 14, color: Colors.grey.shade700),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    final nav = Navigator.of(context, rootNavigator: true);
    try {
      _clearPdfImageSessionCache();
      if (kIsWeb) {
        try {
          await PublicSiteMediaAuth.ensureWebAnonymousForStorage();
        } catch (_) {}
        try {
          await FirebaseAuth.instance.currentUser?.getIdToken(true);
        } catch (_) {}
      }
      final tpl = await _loadCarteiraTemplateContext();
      ({
        String memberId,
        String nome,
        String cargo,
        String? assinaturaUrl,
      })? signat = incluirAssinatura ? selected : null;
      if (signat != null) {
        signat = await _fetchSignatoryAssinaturaFresh(signat);
      }

      prog.value = 0.04;
      // Membros (Firestore) em paralelo com logo da igreja — reduz tempo em que o diálogo fica em “preparar logo”.
      final batch = await Future.wait<dynamic>([
        Future.wait(
          ids.map(
            (id) => _cardDataForMemberId(
              id,
              tpl.tenant,
              tpl.cardCfg,
              tpl.igrejaDocId,
            ),
          ),
        ),
        _prefetchLogoFromCarteiraContext(tpl),
      ]);
      final resolved = batch[0] as List<_CardData?>;
      final list = <_CardData>[];
      for (final c in resolved) {
        if (c != null) list.add(c);
      }
      prog.value = 0.16;

      if (list.isEmpty) {
        if (nav.canPop()) nav.pop();
        prog.dispose();
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text('Nenhum membro encontrado para gerar PDF.')));
        }
        return;
      }

      final sigUrl = signat?.assinaturaUrl;
      // Assinatura do líder (perfil Membros — URL fresca acima).
      await _prefetchSharedPdfBrandingForLote(list, signatoryAssinaturaUrl: sigUrl);
      prog.value = 0.24;

      // Só fotos por membro (logo já está em cache).
      const preloadBatch = 30;
      for (var i = 0; i < list.length; i += preloadBatch) {
        final end = min(i + preloadBatch, list.length);
        final chunk = list.sublist(i, end);
        await Future.wait(
          chunk.map(
            (card) => preLoadImages(
              card,
              signatoryAssinaturaUrl: sigUrl,
            ),
          ),
        );
        if (kIsWeb) await Future<void>.delayed(Duration.zero);
        prog.value = 0.2 + 0.72 * (end / list.length);
      }
      prog.value = 0.94;

      final lay = _pdfManyLayoutParams(pdfLayoutLote);
      late final Uint8List bytes;
      if (pdfLayoutLote ==
          _PdfManyLayout.a4FrenteSobreVerso2Digital) {
        var pastorSig = '';
        try {
          pastorSig = (await FirebaseStorageService
                      .getPastorSignatureConfigDownloadUrl(
                          list.first.igrejaDocId) ??
                  '')
              .trim();
        } catch (_) {}
        try {
          bytes = await _buildPdfMultiWalletRaster(
            context,
            list,
            signatoryNome: signat?.nome,
            signatoryCargo: signat?.cargo,
            signatoryAssinaturaUrl: signat?.assinaturaUrl,
            pastorSigFallback: pastorSig,
          );
        } catch (e, st) {
          debugPrint(
              '_gerarPdfUnicoLote: raster falhou, vetor: $e\n$st');
          bytes = await _buildPdfMulti(
            list,
            lay.format,
            signatoryNome: signat?.nome,
            signatoryCargo: signat?.cargo,
            signatoryAssinaturaUrl: signat?.assinaturaUrl,
            gridCols: lay.cols,
            gridRows: lay.rows,
            inkEconomy: false,
            frontVersoPorLinha: lay.frontVersoPorLinha,
            digitalVerticalStack: lay.digitalVerticalStack,
          );
        }
      } else if (pdfLayoutLote ==
          _PdfManyLayout.a4FrenteVerso5PorFolha) {
        var pastorSig = '';
        try {
          pastorSig = (await FirebaseStorageService
                      .getPastorSignatureConfigDownloadUrl(
                          list.first.igrejaDocId) ??
                  '')
              .trim();
        } catch (_) {}
        try {
          bytes =
              await _buildPdfMultiWalletRasterFrenteVersoLinhaA4(
            context,
            list,
            signatoryNome: signat?.nome,
            signatoryCargo: signat?.cargo,
            signatoryAssinaturaUrl: signat?.assinaturaUrl,
            pastorSigFallback: pastorSig,
          );
        } catch (e, st) {
          debugPrint(
              '_gerarPdfUnicoLote: raster frente|verso falhou, vetor: $e\n$st');
          bytes = await _buildPdfMulti(
            list,
            lay.format,
            signatoryNome: signat?.nome,
            signatoryCargo: signat?.cargo,
            signatoryAssinaturaUrl: signat?.assinaturaUrl,
            gridCols: lay.cols,
            gridRows: lay.rows,
            inkEconomy: false,
            frontVersoPorLinha: lay.frontVersoPorLinha,
            digitalVerticalStack: lay.digitalVerticalStack,
          );
        }
      } else {
        bytes = await _buildPdfMulti(
          list,
          lay.format,
          signatoryNome: signat?.nome,
          signatoryCargo: signat?.cargo,
          signatoryAssinaturaUrl: signat?.assinaturaUrl,
          gridCols: lay.cols,
          gridRows: lay.rows,
          inkEconomy: false,
          frontVersoPorLinha: lay.frontVersoPorLinha,
          digitalVerticalStack: lay.digitalVerticalStack,
        );
      }
      final produced = list.length;
      if (nav.canPop()) nav.pop();
      prog.dispose();
      if (!context.mounted) return;
      await showPdfActions(
        context,
        bytes: bytes,
        filename:
            'carteirinhas_lote_${produced}_${DateTime.now().millisecondsSinceEpoch}.pdf',
      );
      if (mounted) {
        setState(() => _carteiraListaSelecionados.clear());
      }
    } catch (e, st) {
      debugPrint('_gerarPdfUnicoLote: $e\n$st');
      if (nav.canPop()) nav.pop();
      prog.dispose();
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Erro: $e')));
      }
    } finally {
      _clearPdfImageSessionCache();
    }
  }

  Future<void> _setValidity(_CardData data, _ValidityOption option) async {
    final ref = FirebaseFirestore.instance
        .collection('igrejas')
        .doc(widget.tenantId)
        .collection('membros')
        .doc(data.memberId);

    if (option.permanent) {
      await ref.set(
        {
          'CARTEIRA_PERMANENTE': true,
          'CARTEIRA_ANOS': FieldValue.delete(),
          'CARTEIRA_VALIDADE': FieldValue.delete(),
          'CARTEIRA_ATUALIZADA_EM': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
      if (mounted) setState(() => _loadFuture = _load());
      return;
    }

    final now = DateTime.now();
    final exp = DateTime(now.year + option.years, now.month, now.day);
    await ref.set(
      {
        'CARTEIRA_PERMANENTE': false,
        'CARTEIRA_ANOS': option.years,
        'CARTEIRA_VALIDADE': Timestamp.fromDate(exp),
        'CARTEIRA_ATUALIZADA_EM': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
    if (mounted) setState(() => _loadFuture = _load());
  }

  /// Nome mascarado para o verso do PDF / validação pública.
  String _maskNomePublico(String nome) {
    final p =
        nome.trim().split(RegExp(r'\s+')).where((e) => e.isNotEmpty).toList();
    if (p.isEmpty) return '';
    if (p.length == 1) {
      final a = p[0];
      if (a.isEmpty) return '';
      return '${a.substring(0, 1)}***';
    }
    final last = p.last;
    final ini = last.isEmpty ? '' : last.substring(0, 1);
    return '${p.first} $ini.';
  }

  /// Contexto comum para gerar várias carteirinhas (tenant + config mesclada).
  Future<
          ({
            Map<String, dynamic> tenant,
            Map<String, dynamic> cardCfg,
            String igrejaDocId
          })>
      _loadCarteiraTemplateContext() async {
    final db = FirebaseFirestore.instance;
    final igrejaDocId = await _effectiveIgrejaDocId();
    Map<String, dynamic> cardCfg = {};
    Map<String, dynamic> tenant = {};
    try {
      final tenantSnap =
          await db.collection('igrejas').doc(igrejaDocId).get();
      tenant = Map<String, dynamic>.from(tenantSnap.data() ?? {})
        ..['id'] = igrejaDocId;
    } catch (_) {}
    try {
      final carteiraSnap = await db
          .collection('igrejas')
          .doc(igrejaDocId)
          .collection('config')
          .doc('carteira')
          .get();
      if (carteiraSnap.exists && carteiraSnap.data() != null) {
        cardCfg.addAll(Map<String, dynamic>.from(carteiraSnap.data()!));
      }
    } catch (_) {}
    final hasLogo = (cardCfg['logoUrl'] ?? '').toString().trim().isNotEmpty ||
        ((cardCfg['logoDataBase64'] ?? '').toString().trim().isNotEmpty);
    if (cardCfg['title'] == null || !hasLogo) {
      try {
        final cfgSnap = await db.doc('config/memberCard').get();
        if (cfgSnap.exists && cfgSnap.data() != null) {
          final global = cfgSnap.data()!;
          if (cardCfg['title'] == null && global['title'] != null)
            cardCfg['title'] = global['title'];
          if (cardCfg['logoUrl'] == null && global['logoUrl'] != null)
            cardCfg['logoUrl'] = global['logoUrl'];
          if (cardCfg['bgColor'] == null && global['bgColor'] != null) {
            cardCfg['bgColor'] = global['bgColor'];
          }
          if (cardCfg['textColor'] == null && global['textColor'] != null) {
            cardCfg['textColor'] = global['textColor'];
          }
          if (cardCfg['bgColorSecondary'] == null &&
              global['bgColorSecondary'] != null) {
            cardCfg['bgColorSecondary'] = global['bgColorSecondary'];
          }
          if (cardCfg['accentColor'] == null && global['accentColor'] != null) {
            cardCfg['accentColor'] = global['accentColor'];
          }
          if (cardCfg['accentGold'] == null && global['accentGold'] != null) {
            cardCfg['accentGold'] = global['accentGold'];
          }
        }
      } catch (_) {}
    }
    if (cardCfg['title'] == null && tenant['name'] != null) {
      cardCfg['title'] = tenant['name'] ?? tenant['nome'] ?? 'Gestão YAHWEH';
    }
    if (cardCfg['logoUrl'] == null) {
      final u = churchTenantLogoUrl(tenant);
      if (u.isNotEmpty) cardCfg['logoUrl'] = u;
    }
    await _hydrateCardCfgLogoFromIdentityPathIfNeeded(cardCfg, igrejaDocId);
    cardCfg = _mergeChurchLogoIntoCardConfig(cardCfg, tenant);
    return (tenant: tenant, cardCfg: cardCfg, igrejaDocId: igrejaDocId);
  }

  /// Se não houver URL no Firestore, tenta `configuracoes/logo_igreja.png` no Storage.
  Future<void> _hydrateCardCfgLogoFromIdentityPathIfNeeded(
    Map<String, dynamic> cardCfg,
    String igrejaDocId,
  ) async {
    final raw = (cardCfg['logoUrl'] ?? '').toString().trim();
    if (raw.isNotEmpty && isValidImageUrl(sanitizeImageUrl(raw))) return;
    try {
      if (kIsWeb) {
        await PublicSiteMediaAuth.ensureWebAnonymousForStorage();
        try {
          await FirebaseAuth.instance.currentUser?.getIdToken();
        } catch (_) {}
      }
      final ref = FirebaseStorage.instance
          .ref(ChurchStorageLayout.churchIdentityLogoPath(igrejaDocId));
      final u = await ref.getDownloadURL();
      if (u.isNotEmpty) cardCfg['logoUrl'] = u;
    } catch (_) {}
  }

  Future<_CardData?> _cardDataForMemberId(
    String memberId,
    Map<String, dynamic> tenant,
    Map<String, dynamic> cardCfg,
    String igrejaDocId,
  ) async {
    final mid = memberId.trim();
    if (mid.isEmpty) return null;
    final cfgCopy = Map<String, dynamic>.from(cardCfg);
    try {
      final col = FirebaseFirestore.instance
          .collection('igrejas')
          .doc(igrejaDocId)
          .collection('membros');
      final doc = await MemberDocumentResolve.findByHint(col, mid);
      if (doc != null && doc.exists) {
        var m = Map<String, dynamic>.from(doc.data() ?? {});
        m = await _enrichMemberCarteirinhaSignatureFromSignatory(m,
            igrejaDocId: igrejaDocId);
        return _CardData(
          memberId: doc.id,
          member: m,
          cardConfig: cfgCopy,
          tenant: tenant,
          igrejaDocId: igrejaDocId,
        );
      }
    } catch (_) {}
    return null;
  }

  Future<void> _prefetchPdfAssetsForCard(_CardData data,
      {String? signatoryAssinaturaUrl}) async {
    final cfg = _cardConfigForPdf(data);
    final cid = data.igrejaDocId.trim();
    if (cid.isEmpty || !_pdfLogoProviderMemo.containsKey(cid)) {
      await _pdfLogoProvider(cfg, data);
    }
    if (cfg.showPhoto) {
      final u = await _resolvedMemberPhotoUrlForPdf(data.memberId, data.member,
          igrejaDocId: data.igrejaDocId);
      if (u.isNotEmpty) await _pdfImageProviderFromUrlCached(u);
    }
    final sig = (signatoryAssinaturaUrl ?? '').trim();
    if (sig.isNotEmpty) await _pdfSignatureImageProviderFromUrlCached(sig);
  }

  /// Alias explícito para pré-carregamento de imagens antes da montagem do PDF.
  Future<void> preLoadImages(_CardData data,
      {String? signatoryAssinaturaUrl}) async {
    await _prefetchPdfAssetsForCard(data,
        signatoryAssinaturaUrl: signatoryAssinaturaUrl);
  }

  /// Pré-carrega o logo assim que existe contexto de template — corre em paralelo a [Future.wait] dos membros.
  Future<void> _prefetchLogoFromCarteiraContext(
    ({
      Map<String, dynamic> tenant,
      Map<String, dynamic> cardCfg,
      String igrejaDocId,
    }) tpl,
  ) async {
    final synthetic = _CardData(
      memberId: '__logo_prefetch__',
      member: const <String, dynamic>{},
      cardConfig: Map<String, dynamic>.from(tpl.cardCfg),
      tenant: tpl.tenant,
      igrejaDocId: tpl.igrejaDocId,
    );
    final cfg = _cardConfigForPdf(synthetic);
    await _pdfLogoProvider(cfg, synthetic);
  }

  /// Assinatura do líder + logo só se ainda não estiver em cache (após [_prefetchLogoFromCarteiraContext]).
  Future<void> _prefetchSharedPdfBrandingForLote(
    List<_CardData> list, {
    String? signatoryAssinaturaUrl,
  }) async {
    if (list.isEmpty) return;
    final any = list.first;
    final cid = any.igrejaDocId.trim();
    final cfg = _cardConfigForPdf(any);
    if (cid.isEmpty ||
        !_pdfLogoProviderMemo.containsKey(cid) ||
        _pdfLogoProviderMemo[cid] == null) {
      await _pdfLogoProvider(cfg, any);
    }
    final s = (signatoryAssinaturaUrl ?? '').trim();
    if (s.isNotEmpty) await _pdfSignatureImageProviderFromUrlCached(s);
  }

  /// Mesmo tamanho físico da frente e do verso (CR80 ~ ISO/IEC 7810).
  static const double _pdfCardSlotW = VersoCarteirinhaPdfWidget.cardWidthPt;
  static const double _pdfCardSlotH = VersoCarteirinhaPdfWidget.cardHeightPt;

  /// Cache de imagens na mesma geração de PDF (evita baixar a mesma foto/logo várias vezes).
  final Map<String, pw.ImageProvider?> _pdfImageSessionCache = {};
  final Map<String, Uint8List?> _pdfImageBytesSessionCache = {};
  /// Assinatura no PDF: bytes realçados (cache separado da URL genérica).
  final Map<String, pw.ImageProvider?> _pdfSignatureImageSessionCache = {};
  /// Logo resolvida uma vez por `igrejaDocId` — evita [loadReportPdfBranding] N vezes no lote.
  final Map<String, pw.ImageProvider?> _pdfLogoProviderMemo = {};

  void _clearPdfImageSessionCache() {
    _pdfImageSessionCache.clear();
    _pdfImageBytesSessionCache.clear();
    _pdfSignatureImageSessionCache.clear();
    _pdfLogoProviderMemo.clear();
  }

  /// Redimensiona fora da UI no mobile (decode JPEG/PNG é pesado); na web mantém na thread atual.
  Future<Uint8List?> _resizeForPdf(Uint8List bytes, {int maxSide = 200}) async {
    if (bytes.length < 33) return null;
    try {
      if (kIsWeb) {
        return _resizeForPdfOnMainIsolate(bytes, maxSide: maxSide);
      }
      final out = await compute(
        carteirinhaPdfResizeBytesForEmbed,
        <String, dynamic>{'b': bytes, 'm': maxSide, 'q': 68},
      );
      return out ?? _resizeForPdfOnMainIsolate(bytes, maxSide: maxSide);
    } catch (_) {
      return _resizeForPdfOnMainIsolate(bytes, maxSide: maxSide);
    }
  }

  Uint8List? _resizeForPdfOnMainIsolate(Uint8List bytes, {int maxSide = 200}) {
    try {
      final decoded = img.decodeImage(bytes);
      if (decoded == null) return null;
      final w = decoded.width;
      final h = decoded.height;
      img.Image toEncode = decoded;
      if (w > maxSide || h > maxSide) {
        final scale = w >= h ? (maxSide / w) : (maxSide / h);
        final rw = (w * scale).round().clamp(1, maxSide);
        final rh = (h * scale).round().clamp(1, maxSide);
        toEncode = img.copyResize(decoded,
            width: rw, height: rh, interpolation: img.Interpolation.average);
      }
      return Uint8List.fromList(img.encodeJpg(toEncode, quality: 68));
    } catch (_) {
      return null;
    }
  }

  Future<Uint8List?> _loadCachedImageBytes(String url) async {
    final u = sanitizeImageUrl(url);
    if (u.isEmpty || !isValidImageUrl(u)) return null;
    if (_pdfImageBytesSessionCache.containsKey(u)) {
      return _pdfImageBytesSessionCache[u];
    }
    // URLs do Firebase Storage: na web o HTTP direto costuma falhar (CORS) — SDK primeiro.
    if (isFirebaseStorageHttpUrl(u)) {
      try {
        if (kIsWeb) {
          try {
            await PublicSiteMediaAuth.ensureWebAnonymousForStorage();
          } catch (_) {}
          try {
            await FirebaseAuth.instance.currentUser?.getIdToken(true);
          } catch (_) {}
        }
        var fu = u;
        final fresh = await refreshFirebaseStorageDownloadUrl(u).timeout(
            const Duration(seconds: 8),
            onTimeout: () => u);
        if (fresh != null && fresh.isNotEmpty) fu = fresh;
        final bytes = await firebaseStorageBytesFromDownloadUrl(
          fu,
          maxBytes: 8 * 1024 * 1024,
        ).timeout(const Duration(seconds: 18), onTimeout: () => null);
        if (bytes != null && bytes.length > 32) {
          final out = await _resizeForPdf(bytes);
          if (out != null && out.length > 32) {
            _pdfImageBytesSessionCache[u] = out;
            return out;
          }
        }
      } catch (_) {}
      return null;
    }
    try {
      final b = await ImageHelper.getBytesFromUrlOrNull(
        u,
        timeout: const Duration(seconds: 14),
      );
      if (b != null && b.length > 32) {
        final out = await _resizeForPdf(Uint8List.fromList(b));
        if (out != null && out.length > 32) {
          _pdfImageBytesSessionCache[u] = out;
          return out;
        }
      }
    } catch (_) {}
    return null;
  }

  Future<pw.ImageProvider?> _pdfImageProviderFromUrlCached(
      String? rawUrl) async {
    var u = sanitizeImageUrl((rawUrl ?? '').trim());
    if (u.isEmpty || !isValidImageUrl(u)) return null;
    if (_pdfImageSessionCache.containsKey(u)) return _pdfImageSessionCache[u];
    final p = await _pdfImageProviderFromUrl(u);
    _pdfImageSessionCache[u] = p;
    return p;
  }

  /// Assinatura visual no PDF: realça traços (decode + `image` fora da UI em mobile/desktop).
  Future<pw.ImageProvider?> _pdfSignatureImageProviderFromUrlCached(
      String? rawUrl) async {
    var u = sanitizeImageUrl((rawUrl ?? '').trim());
    if (u.isEmpty || !isValidImageUrl(u)) return null;
    if (_pdfSignatureImageSessionCache.containsKey(u)) {
      return _pdfSignatureImageSessionCache[u];
    }
    final bytes = await _loadCachedImageBytes(u);
    if (bytes != null && bytes.length > 32) {
      Uint8List out = bytes;
      try {
        if (kIsWeb) {
          out = carteirinhaPdfEnhanceSignatureForCompute(bytes);
        } else {
          out = await compute(
            carteirinhaPdfEnhanceSignatureForCompute,
            bytes,
          );
        }
      } catch (_) {}
      final p = pw.MemoryImage(out);
      _pdfSignatureImageSessionCache[u] = p;
      return p;
    }
    try {
      final p = await networkImage(u);
      _pdfSignatureImageSessionCache[u] = p;
      return p;
    } catch (_) {
      return null;
    }
  }

  /// Só preenche logo a partir do cadastro da igreja quando a carteirinha não tem logo própria (URL ou base64).
  Map<String, dynamic> _mergeChurchLogoIntoCardConfig(
      Map<String, dynamic> cardCfg, Map<String, dynamic> tenant) {
    final m = Map<String, dynamic>.from(cardCfg);
    final url = (m['logoUrl'] ?? '').toString().trim();
    final b64 = (m['logoDataBase64'] ?? '').toString().trim();
    final hasExplicitLogo = b64.isNotEmpty ||
        (url.isNotEmpty && isValidImageUrl(sanitizeImageUrl(url)));
    if (hasExplicitLogo) return m;
    final u = churchTenantLogoUrl(tenant);
    if (u.isNotEmpty) {
      m['logoUrl'] = u;
      m['logoDataBase64'] = '';
    }
    return m;
  }

  /// Config efetiva para prévia e PDF (cores, logo e modelo visual da igreja).
  _CardConfig _cardConfigForPdf(_CardData data) {
    return _CardConfig.from(
        _mergeChurchLogoIntoCardConfig(data.cardConfig, data.tenant));
  }

  _CardConfig _effectiveCardConfig(_CardData data) => _cardConfigForPdf(data);

  Future<void> _refreshSignatoryFromFirestore(
    BuildContext modalContext,
    void Function(void Function()) setModal,
    ({String memberId, String nome, String cargo, String? assinaturaUrl})? v,
    void Function(
            ({
              String memberId,
              String nome,
              String cargo,
              String? assinaturaUrl
            })? value)
        setSelected,
  ) async {
    if (v == null) {
      setModal(() => setSelected(null));
      return;
    }
    try {
      final col = FirebaseFirestore.instance
          .collection('igrejas')
          .doc(widget.tenantId)
          .collection('membros');
      final doc =
          await MemberDocumentResolve.findByHint(col, v.memberId.trim());
      Map<String, dynamic> d = doc?.data() ?? {};
      if (doc == null || !doc.exists) d = {};
      var url =
          (d['assinaturaUrl'] ?? d['assinatura_url'] ?? '').toString().trim();
      final nome =
          (d['NOME_COMPLETO'] ?? d['nome'] ?? v.nome).toString().trim();
      final cargo = signatoryCargoDisplayLabel(d);
      if (!modalContext.mounted) return;
      setModal(() => setSelected((
            memberId: v.memberId,
            nome: nome.isEmpty ? v.nome : nome,
            cargo: cargo.isEmpty ? v.cargo : cargo,
            assinaturaUrl: url.isEmpty ? null : url,
          )));
    } catch (_) {
      if (modalContext.mounted) setModal(() => setSelected(v));
    }
  }

  Future<
      List<
          ({
            String memberId,
            String nome,
            String cargo,
            String? assinaturaUrl
          })>> _loadSignatoryOptions() async {
    final db = FirebaseFirestore.instance;
    final col =
        db.collection('igrejas').doc(widget.tenantId).collection('membros');
    final snap = await col.limit(500).get();
    final list = <({
      String memberId,
      String nome,
      String cargo,
      String? assinaturaUrl
    })>[];
    for (final doc in snap.docs) {
      final d = doc.data();
      if (!memberHasLeadershipForAssinatura(d)) continue;
      final nome = (d['NOME_COMPLETO'] ?? d['nome'] ?? '').toString().trim();
      if (nome.isEmpty) continue;
      final url =
          (d['assinaturaUrl'] ?? d['assinatura_url'] ?? '').toString().trim();
      list.add((
        memberId: doc.id,
        nome: nome,
        cargo: signatoryCargoDisplayLabel(d),
        assinaturaUrl: url.isEmpty ? null : url
      ));
    }
    return list;
  }

  /// Usa [defaultSignatoryMemberId] da config da carteirinha quando existir na lista.
  ({String memberId, String nome, String cargo, String? assinaturaUrl})?
      _selectSignatory(
    List<({String memberId, String nome, String cargo, String? assinaturaUrl})>
        options,
    String? preferredMemberId,
  ) {
    if (options.isEmpty) return null;
    final id = (preferredMemberId ?? '').trim();
    if (id.isNotEmpty) {
      for (final o in options) {
        if (o.memberId == id) return o;
      }
    }
    return options.first;
  }

  /// Garante [assinaturaUrl] atualizada a partir da ficha do membro (módulo Membros).
  Future<
      ({
        String memberId,
        String nome,
        String cargo,
        String? assinaturaUrl,
      })> _fetchSignatoryAssinaturaFresh(
    ({
      String memberId,
      String nome,
      String cargo,
      String? assinaturaUrl,
    }) s,
  ) async {
    try {
      final col = FirebaseFirestore.instance
          .collection('igrejas')
          .doc(widget.tenantId)
          .collection('membros');
      final doc = await MemberDocumentResolve.findByHint(col, s.memberId.trim());
      if (doc == null || !doc.exists) return s;
      final d = doc.data() ?? {};
      final urlFresh =
          (d['assinaturaUrl'] ?? d['assinatura_url'] ?? '').toString().trim();
      final urlFallback = (s.assinaturaUrl ?? '').trim();
      final url = urlFresh.isNotEmpty ? urlFresh : urlFallback;
      final nome = (d['NOME_COMPLETO'] ?? d['nome'] ?? s.nome).toString().trim();
      final cargo = signatoryCargoDisplayLabel(d);
      return (
        memberId: s.memberId,
        nome: nome.isEmpty ? s.nome : nome,
        cargo: cargo.isEmpty ? s.cargo : cargo,
        assinaturaUrl: url.isEmpty ? null : url,
      );
    } catch (_) {
      return s;
    }
  }

  /// PDF: [networkImage] do pacote `pdf` falha com frequência em URLs do Firebase Storage (web/token).
  /// Bytes vêm de [_loadCachedImageBytes] (SDK no Storage); último recurso [networkImage].
  Future<pw.ImageProvider?> _pdfImageProviderFromUrl(String? rawUrl) async {
    var u = sanitizeImageUrl((rawUrl ?? '').trim());
    if (u.isEmpty || !isValidImageUrl(u)) return null;
    final cached = await _loadCachedImageBytes(u);
    if (cached != null && cached.length > 32) {
      return pw.MemoryImage(cached);
    }
    try {
      return await networkImage(u);
    } catch (_) {
      return null;
    }
  }

  Future<pw.ImageProvider?> _pdfLogoProvider(
      _CardConfig cfg, _CardData data) async {
    final igrejaId = data.igrejaDocId.trim();
    if (igrejaId.isNotEmpty && _pdfLogoProviderMemo.containsKey(igrejaId)) {
      return _pdfLogoProviderMemo[igrejaId];
    }
    final tenant = data.tenant;
    final logoDataBase64 = cfg.logoDataBase64;
    final logoUrl = cfg.logoUrl;
    pw.ImageProvider? logo;
    try {
      if (logoDataBase64 != null && logoDataBase64.isNotEmpty) {
        try {
          final raw = Uint8List.fromList(base64Decode(logoDataBase64));
          final out = await _resizeForPdf(raw, maxSide: 400);
          if (out != null && out.length > 32) {
            logo = pw.MemoryImage(out);
          }
        } catch (_) {}
      } else if (logoUrl.isNotEmpty) {
        logo = await _pdfImageProviderFromUrlCached(logoUrl);
      }
      if (logo == null) {
        final fromTenant = churchTenantLogoUrl(tenant);
        if (fromTenant.isNotEmpty) {
          logo = await _pdfImageProviderFromUrlCached(fromTenant);
        }
      }
      if (logo == null && igrejaId.isNotEmpty) {
        final fromStorage =
            await FirebaseStorageService.getChurchLogoDownloadUrl(
          igrejaId,
          tenantData: tenant,
        );
        if (fromStorage != null && fromStorage.isNotEmpty) {
          logo = await _pdfImageProviderFromUrlCached(fromStorage);
        }
      }
      if (logo == null && igrejaId.isNotEmpty) {
        try {
          final branding = await loadReportPdfBranding(igrejaId);
          final lb = branding.logoBytes;
          if (lb != null && lb.length > 32) {
            final out = await _resizeForPdf(lb, maxSide: 400);
            if (out != null && out.length > 32) {
              logo = pw.MemoryImage(out);
            }
          }
        } catch (_) {}
      }
    } catch (_) {}
    if (igrejaId.isNotEmpty) {
      _pdfLogoProviderMemo[igrejaId] = logo;
    }
    return logo;
  }

  pw.Widget _pdfCardFace({
    required String name,
    required String cargo,
    required String cpf,
    required String nascimento,
    required String batismo,
    required String validade,
    required String nomePai,
    required String nomeMae,
    required String sexo,

    /// Mesma linha da carteira digital (admissão / batismo).
    required String admissionLine,

    required _CardConfig cfg,
    required PdfColor bgColor,
    required PdfColor? bgColorSec,
    required PdfColor textColor,
    required PdfColor accentColor,
    pw.ImageProvider? logo,
    pw.ImageProvider? photo,
    pw.ImageProvider? signatoryImage,
    String? signatoryNome,
    String? signatoryCargo,
    double width = 360,

    /// Quando preenchidos, o degradê cobre exatamente o retângulo CR80 (igual ao verso).
    double? outerSlotWidth,
    double? outerSlotHeight,
  }) {
    // Modelo único (igual à carteira digital): degradê, logo em caixa clara, painel vidro.
    const cardHeight = 228.0;
    final inkEco = bgColor == PdfColors.white && bgColorSec == null;
    final ac = accentColor;
    final secGrad = bgColorSec ?? bgColor;
    final deco = pw.BoxDecoration(
      color: inkEco ? PdfColors.white : null,
      gradient: !inkEco
          ? pw.LinearGradient(
              begin: pw.Alignment.topLeft,
              end: pw.Alignment.bottomRight,
              colors: [bgColor, secGrad],
            )
          : null,
      borderRadius: pw.BorderRadius.circular(16),
      border: pw.Border.all(
        color: inkEco ? PdfColors.grey400 : ac,
        width: 1,
      ),
    );
    final glassFill = inkEco ? PdfColors.grey200 : PdfColor(1, 1, 1, 0.14);
    final glassBorder =
        inkEco ? PdfColors.grey500 : PdfColor(1, 1, 1, 0.24);
    final adm =
        admissionLine.trim().isEmpty ? 'Admissão: —' : admissionLine.trim();

    final columnChildren = <pw.Widget>[
      if (!inkEco)
        pw.Container(
          width: width,
          height: 2.8,
          margin: const pw.EdgeInsets.only(bottom: 8),
          decoration: pw.BoxDecoration(
            borderRadius: pw.BorderRadius.circular(1.2),
            gradient: pw.LinearGradient(
              colors: [
                ac,
                PdfColor(1, 1, 1, 0.42),
              ],
            ),
          ),
        ),
      pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Container(
            width: 82,
            height: 82,
            decoration: pw.BoxDecoration(
              color: inkEco ? PdfColors.grey100 : PdfColors.white,
              borderRadius: pw.BorderRadius.circular(10),
            ),
            padding: const pw.EdgeInsets.all(3),
            child: logo != null
                ? pw.Center(child: pw.Image(logo, fit: pw.BoxFit.contain))
                : pw.Center(
                    child: pw.Text(
                      'LOGO',
                      style: pw.TextStyle(
                        color: PdfColors.grey500,
                        fontSize: 7,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                  ),
          ),
          pw.SizedBox(width: 10),
          pw.Expanded(
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  cfg.title.toUpperCase(),
                  maxLines: 2,
                  style: pw.TextStyle(
                    color: textColor,
                    fontSize: 10.5,
                    fontWeight: pw.FontWeight.bold,
                    height: 1.1,
                  ),
                ),
                pw.SizedBox(height: 2),
                pw.Text(
                  cfg.subtitle,
                  maxLines: 1,
                  style: pw.TextStyle(
                    color: PdfColor(
                        textColor.red, textColor.green, textColor.blue, 0.88),
                    fontSize: 7.5,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      pw.Spacer(),
      pw.Container(
        padding: const pw.EdgeInsets.all(10),
        decoration: pw.BoxDecoration(
          color: glassFill,
          borderRadius: pw.BorderRadius.circular(14),
          border: pw.Border.all(color: glassBorder, width: 0.8),
        ),
        child: pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.center,
          children: [
            if (cfg.showPhoto) ...[
              pw.Container(
                width: 72,
                height: 72,
                decoration: pw.BoxDecoration(
                  borderRadius: pw.BorderRadius.circular(36),
                  border: pw.Border.all(color: ac, width: 2),
                  color: inkEco ? PdfColors.white : PdfColor(1, 1, 1, 0.2),
                ),
                child: photo != null
                    ? pw.ClipRRect(
                        horizontalRadius: 36,
                        verticalRadius: 36,
                        child: pw.Image(photo, fit: pw.BoxFit.cover),
                      )
                    : pw.Center(
                        child: pw.Text(
                          'FOTO',
                          style: pw.TextStyle(
                            color: PdfColors.grey500,
                            fontSize: 9,
                            fontWeight: pw.FontWeight.bold,
                          ),
                        ),
                      ),
              ),
              pw.SizedBox(width: 10),
            ],
            pw.Expanded(
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  if (cargo.trim().isNotEmpty)
                    pw.Container(
                      padding: const pw.EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: pw.BoxDecoration(
                        color: PdfColor(ac.red, ac.green, ac.blue,
                            inkEco ? 0.35 : 0.22),
                        borderRadius: pw.BorderRadius.circular(8),
                      ),
                      child: pw.Text(
                        cargo.toUpperCase(),
                        style: pw.TextStyle(
                          color: textColor,
                          fontSize: 8,
                          fontWeight: pw.FontWeight.bold,
                          letterSpacing: 0.3,
                        ),
                      ),
                    ),
                  if (cargo.trim().isNotEmpty) pw.SizedBox(height: 6),
                  pw.Text(
                    name,
                    maxLines: 2,
                    style: pw.TextStyle(
                      color: textColor,
                      fontSize: 14,
                      fontWeight: pw.FontWeight.bold,
                      height: 1.12,
                    ),
                  ),
                  pw.SizedBox(height: 6),
                  pw.Text(
                    adm,
                    style: pw.TextStyle(
                      color: PdfColor(
                          textColor.red, textColor.green, textColor.blue, 0.9),
                      fontSize: 8.5,
                    ),
                  ),
                  pw.SizedBox(height: 4),
                  pw.Row(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(
                        'VALIDADE ',
                        style: pw.TextStyle(
                          color: PdfColor(textColor.red, textColor.green,
                              textColor.blue, 0.72),
                          fontSize: 6.2,
                          fontWeight: pw.FontWeight.bold,
                          letterSpacing: 0.4,
                        ),
                      ),
                      pw.Expanded(
                        child: pw.Text(
                          () {
                            final v = validade.trim();
                            if (v.isEmpty || v == '---') return '—';
                            return v;
                          }(),
                          maxLines: 1,
                          style: pw.TextStyle(
                            color: textColor,
                            fontSize: 10,
                            fontWeight: pw.FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      pw.SizedBox(height: 8),
    ];
    final ow = outerSlotWidth;
    final oh = outerSlotHeight;
    if (ow != null && oh != null) {
      final fitScale = min(ow / width, oh / cardHeight);
      final inner = pw.Container(
        width: width,
        height: cardHeight,
        padding: const pw.EdgeInsets.all(20),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: columnChildren,
        ),
      );
      return pw.Container(
        width: ow,
        height: oh,
        decoration: deco,
        child: pw.Center(
          child: pw.Transform.scale(
            alignment: pw.Alignment.center,
            scale: fitScale,
            child: inner,
          ),
        ),
      );
    }
    return pw.Container(
      width: width,
      height: cardHeight,
      padding: const pw.EdgeInsets.all(20),
      decoration: deco,
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: columnChildren,
      ),
    );
  }

  /// Documento com tema Roboto (UTF-8 / acentos) para frente e verso da carteirinha.
  Future<pw.Document> _newCarteirinhaPdfDoc() async {
    final theme = await CarteirinhaPdfFonts.loadThemeData();
    return theme != null ? pw.Document(theme: theme) : pw.Document();
  }

  pw.Widget _pwVersoCarteirinhaBody(
    _CardData data,
    _CardConfig cfg, {
    bool pdfInkEconomy = false,
    pw.ImageProvider? signatoryImage,
    String? signatoryNome,
    String? signatoryCargo,
  }) {
    final igreja = cfg.title;
    final pal = _pdfCarteiraColors(cfg, pdfInkEconomy);
    final g1 = pal.bg;
    final g2 = pal.bgEnd;
    final fg = pal.fg;
    final frase = cfg.fraseRodape.trim();
    final cpfFmt = _formatCpfForCard(_memberCpfRaw(data.member));
    final nasc = _fmtDate(_dateFromMember(data.member, 'DATA_NASCIMENTO'));
    final batismoPdf =
        _fmtDate(_dateFromMember(data.member, 'DATA_BATISMO')).trim();
    final filiacaoTxt = walletFiliacaoFromMember(data.member);
    final tel = _telefoneFromMember(data.member);
    final snIn = (signatoryNome ?? '').trim();
    final sn = snIn.isNotEmpty
        ? snIn
        : (data.member['carteirinhaAssinadaPorNome'] ?? '').toString().trim();
    final scIn = (signatoryCargo ?? '').trim();
    final sc = scIn.isNotEmpty
        ? scIn
        : (data.member['carteirinhaAssinadaPorCargo'] ?? '').toString().trim();
    return VersoCarteirinhaPdfWidget(
      nomeIgreja: igreja,
      regrasUso: cfg.versoRegrasUso,
      // Mesmo eixo que [MemberDigitalWalletBack]: [colorB, colorA] no degradê.
      gradientStart: g2,
      gradientEnd: g1,
      foregroundColor: fg,
      rodapeColor: PdfColor(
          fg.red, fg.green, fg.blue, (fg.alpha * 0.72).clamp(0.0, 1.0)),
      fraseInstitucional: frase.isNotEmpty ? frase : null,
      pdfInkEconomy: pdfInkEconomy,
      cpfDoc: cpfFmt,
      nascimentoDoc: nasc,
      batismoDoc: batismoPdf,
      filiacaoPaiMaeDoc: filiacaoTxt,
      telefoneDoc: tel,
      assinaturaImage: signatoryImage,
      signatoryNome: sn,
      signatoryCargo: sc,
      showRegrasUso: false,
    );
  }

  Future<Uint8List> _buildPdf(_CardData data, PdfPageFormat format,
      {_CardConfig? configOverride,
      String? signatoryNome,
      String? signatoryCargo,
      String? signatoryAssinaturaUrl}) async {
    try {
      final doc = await _newCarteirinhaPdfDoc();
      final cfg = configOverride ?? _cardConfigForPdf(data);
      pw.ImageProvider? signatoryImage;
      if ((signatoryAssinaturaUrl ?? '').trim().isNotEmpty) {
        signatoryImage =
            await _pdfSignatureImageProviderFromUrlCached(signatoryAssinaturaUrl);
      }
      if (signatoryImage == null) {
        final su = (data.member['carteirinhaAssinaturaUrl'] ?? '')
            .toString()
            .trim();
        if (su.isNotEmpty) {
          signatoryImage = await _pdfSignatureImageProviderFromUrlCached(su);
        }
      }
      await _addCardPageToDoc(doc, data, format, cfg,
          signatoryNome: signatoryNome,
          signatoryCargo: signatoryCargo,
          signatoryImage: signatoryImage);
      return doc.save();
    } finally {
      _clearPdfImageSessionCache();
    }
  }

  Future<void> _addCardPageToDoc(
      pw.Document doc, _CardData data, PdfPageFormat format, _CardConfig cfg,
      {String? signatoryNome,
      String? signatoryCargo,
      pw.ImageProvider? signatoryImage,
      bool pvcCropMarks = false,
      bool pdfInkEconomy = false}) async {
    final name = _memberNome(data.member);
    final cargo = _cargoDisplay(data.member, cfg);
    final cpf = _formatCpfForCard(_memberCpfRaw(data.member));
    final nascimento =
        _fmtDate(_dateFromMember(data.member, 'DATA_NASCIMENTO'));
    final batismo = _fmtDate(_dateFromMember(data.member, 'DATA_BATISMO'));
    final validade = _validityLabel(data.member).trim().isEmpty
        ? '---'
        : _validityLabel(data.member);
    final nomePai = _memberFatherName(data.member).trim().isEmpty
        ? '---'
        : _memberFatherName(data.member);
    final nomeMae = _memberMotherName(data.member).trim().isEmpty
        ? '---'
        : _memberMotherName(data.member);
    final sexo = _memberSexo(data.member);
    final admissionLinePdf = () {
      final s = _admissionBatismoLine(data.member).trim();
      return s.isEmpty ? 'Admissão: —' : s;
    }();
    pw.ImageProvider? sigImgVerso = signatoryImage;
    if (sigImgVerso == null) {
      final su =
          (data.member['carteirinhaAssinaturaUrl'] ?? '').toString().trim();
      if (su.isNotEmpty) {
        sigImgVerso = await _pdfSignatureImageProviderFromUrlCached(su);
      }
    }
    final photoUrl = cfg.showPhoto
        ? await _resolvedMemberPhotoUrlForPdf(data.memberId, data.member,
            igrejaDocId: data.igrejaDocId)
        : '';
    final pal = _pdfCarteiraColors(cfg, pdfInkEconomy);
    final PdfColor bgColor = pal.bg;
    final PdfColor? bgColorSec = pdfInkEconomy ? null : pal.bgEnd;
    final PdfColor textColor = pal.fg;
    final accentColor = cfg.accentPdfColor;
    final logo = await _pdfLogoProvider(cfg, data);
    pw.ImageProvider? photo;
    if (photoUrl.isNotEmpty) {
      photo = await _pdfImageProviderFromUrlCached(photoUrl);
    }
    final face = _pdfCardFace(
      name: name,
      cargo: cargo,
      cpf: cpf.isEmpty ? '---' : cpf,
      nascimento: nascimento.isEmpty ? '---' : nascimento,
      batismo: batismo.isEmpty ? '---' : batismo,
      validade: validade,
      nomePai: nomePai,
      nomeMae: nomeMae,
      sexo: sexo,
      admissionLine: admissionLinePdf,
      cfg: cfg,
      bgColor: bgColor,
      bgColorSec: bgColorSec,
      textColor: textColor,
      accentColor: accentColor,
      logo: logo,
      photo: photo,
      signatoryImage: signatoryImage,
      signatoryNome: signatoryNome,
      signatoryCargo: signatoryCargo,
      outerSlotWidth: _pdfCardSlotW,
      outerSlotHeight: _pdfCardSlotH,
    );
    final versoSlot = pw.SizedBox(
      width: _pdfCardSlotW,
      height: _pdfCardSlotH,
      child: _pwVersoCarteirinhaBody(
        data,
        cfg,
        pdfInkEconomy: pdfInkEconomy,
        signatoryImage: sigImgVerso,
        signatoryNome: signatoryNome,
        signatoryCargo: signatoryCargo,
      ),
    );
    if (pvcCropMarks) {
      final pf = CarteirinhaPvcMarks.pageFormat();
      doc.addPage(
        pw.Page(
          pageFormat: pf,
          build: (_) => CarteirinhaPvcMarks.wrapWithCropMarks(face),
        ),
      );
      doc.addPage(
        pw.Page(
          pageFormat: pf,
          build: (_) => CarteirinhaPvcMarks.wrapWithCropMarks(versoSlot),
        ),
      );
      return;
    }
    const cw = VersoCarteirinhaPdfWidget.cardWidthPt;
    const ch = VersoCarteirinhaPdfWidget.cardHeightPt;
    final compactCard =
        format.width <= cw + 1 && format.height <= ch + 1;
    if (compactCard) {
      /// CR80: frente sobre verso (igual à carteirinha digital e ao PNG exportado).
      const gap = 12.0;
      final tall = PdfPageFormat(cw, ch * 2 + gap);
      doc.addPage(
        pw.Page(
          pageFormat: tall,
          build: (_) => pw.Center(
            child: pw.Column(
              mainAxisAlignment: pw.MainAxisAlignment.center,
              crossAxisAlignment: pw.CrossAxisAlignment.center,
              mainAxisSize: pw.MainAxisSize.min,
              children: [
                face,
                pw.SizedBox(height: gap),
                versoSlot,
              ],
            ),
          ),
        ),
      );
      return;
    }
    const gapA4 = 14.0;
    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        build: (context) => pw.Center(
          child: pw.Column(
            mainAxisAlignment: pw.MainAxisAlignment.center,
            crossAxisAlignment: pw.CrossAxisAlignment.center,
            mainAxisSize: pw.MainAxisSize.min,
            children: [
              face,
              pw.SizedBox(height: gapA4),
              versoSlot,
            ],
          ),
        ),
      ),
    );
  }

  /// Frente + verso com os mesmos widgets da carteira digital (captura em lote fora do ecrã).
  Widget _walletDigitalFrontBackForRaster({
    required BuildContext context,
    required _CardData data,
    required _CardConfig cfg,
    required double wCard,
    required String sigUrl,
    required String signatoryNome,
    required String signatoryCargo,
    required bool ladoALado,
  }) {
    final name = _memberNome(data.member);
    final cpf = _memberCpfRaw(data.member);
    final cpfDigits = cpf.replaceAll(RegExp(r'[^0-9]'), '');
    final photoUrlPreview = sanitizeImageUrl(imageUrlFromMap(data.member));
    final nascimento =
        _fmtDate(_dateFromMember(data.member, 'DATA_NASCIMENTO'));
    final batismoFmt =
        _fmtDate(_dateFromMember(data.member, 'DATA_BATISMO')).trim();
    final validade = _validityLabel(data.member);
    final colorA = cfg.bgColorValue;
    final colorB = cfg.bgColorSecondaryValue ??
        CarteirinhaVisualTokens.gradientEndFromPrimary(colorA);
    final accentGold = cfg.accentColorValue;
    final logoSlot = (cfg.logoDataBase64 != null &&
            cfg.logoDataBase64!.isNotEmpty)
        ? Image.memory(
            base64Decode(cfg.logoDataBase64!),
            fit: BoxFit.contain,
            errorBuilder: (_, __, ___) => Image.asset(
              'assets/LOGO_GESTAO_YAHWEH.png',
              fit: BoxFit.contain,
            ),
          )
        : StableChurchLogo(
            tenantId: data.igrejaDocId,
            tenantData: data.tenant,
            storagePath: ChurchImageFields.logoStoragePath(data.tenant),
            imageUrl:
                cfg.logoUrl.trim().isNotEmpty ? cfg.logoUrl.trim() : null,
            width: 160,
            height: 160,
            fit: BoxFit.contain,
            memCacheWidth: 320,
            memCacheHeight: 320,
          );
    final photoSlot = FotoMembroWidget(
      key: ValueKey<String>(
        'raster_wallet_photo_${data.memberId}_${memberPhotoDisplayCacheRevision(data.member) ?? 0}',
      ),
      imageUrl: photoUrlPreview.isEmpty ? null : photoUrlPreview,
      tenantId: data.igrejaDocId,
      memberId: data.memberId,
      cpfDigits: cpfDigits.length == 11 ? cpfDigits : null,
      memberData: data.member,
      authUid: _memberAuthUidForCarteiraFoto(data.member),
      size: 72,
      memCacheWidth: 220,
      memCacheHeight: 220,
      imageCacheRevision: memberPhotoDisplayCacheRevision(data.member),
    );
    final cpfFmt = _formatCpfForCard(cpf);
    final filiacaoTxt = walletFiliacaoFromMember(data.member);
    final telM = _telefoneFromMember(data.member);
    final signatoryNameWallet = signatoryNome.trim().isNotEmpty
        ? signatoryNome.trim()
        : (data.member['carteirinhaAssinadaPorNome'] ?? '').toString();
    final signatoryCargoWallet = signatoryCargo.trim().isNotEmpty
        ? signatoryCargo.trim()
        : (data.member['carteirinhaAssinadaPorCargo'] ?? '').toString();
    final sigUrlUse = sigUrl.trim();

    final hCard = DigitalWalletCardLayout.cardHeight(wCard);
    final front = MemberDigitalWalletFront(
      width: wCard,
      colorA: colorA,
      colorB: colorB,
      textColor: cfg.textColorValue,
      accentGold: accentGold,
      churchTitle: cfg.title,
      churchSubtitle: cfg.subtitle,
      logoSlot: logoSlot,
      photoSlot: photoSlot,
      showPhoto: cfg.showPhoto,
      memberName: name,
      cargo: _cargoDisplay(data.member, cfg),
      admission: () {
        final a = _admissionBatismoLine(data.member);
        return a.isEmpty ? '—' : a;
      }(),
      validade: validade.isEmpty ? '—' : validade,
    );
    final back = MemberDigitalWalletBack(
      width: wCard,
      colorA: colorA,
      colorB: colorB,
      textColor: cfg.textColorValue,
      accentGold: accentGold,
      churchTitle: cfg.title,
      cpfOrDoc: cpfFmt.isEmpty ? '—' : cpfFmt,
      nascimento: nascimento.isEmpty ? '—' : nascimento,
      dataBatismo: batismoFmt.isEmpty ? '—' : batismoFmt,
      filiacaoPaiMae: filiacaoTxt.isEmpty ? '—' : filiacaoTxt,
      telefone: telM.isEmpty ? '—' : telM,
      signatureImageUrl: sigUrlUse.isEmpty ? null : sigUrlUse,
      signatoryName: signatoryNameWallet,
      signatoryCargo: signatoryCargoWallet,
      fraseRodape: cfg.fraseRodape,
    );
    if (!ladoALado) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          front,
          const SizedBox(height: 14),
          back,
        ],
      );
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        front,
        const SizedBox(width: 12),
        SizedBox(
          width: 1,
          height: hCard,
          child: DecoratedBox(
            decoration: BoxDecoration(
              border: Border(
                left: BorderSide(
                  color: Colors.grey.shade500,
                  width: 1,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 11),
        back,
      ],
    );
  }

  double? _aspectRatioFromPngBytes(Uint8List bytes) {
    final im = img.decodeImage(bytes);
    if (im == null || im.width <= 0) return null;
    return im.height / im.width;
  }

  /// Várias carteirinhas num único PDF — **mesmo visual** da carteira digital (captura raster),
  /// página A4 por membro (como o PDF único “Visualizar”).
  Future<Uint8List> _buildPdfMultiWalletRaster(
    BuildContext context,
    List<_CardData> list, {
    String? signatoryNome,
    String? signatoryCargo,
    String? signatoryAssinaturaUrl,
    String pastorSigFallback = '',
  }) async {
    if (list.isEmpty) {
      throw StateError('Lista vazia');
    }
    final doc = await _newCarteirinhaPdfDoc();
    const cardWPt = VersoCarteirinhaPdfWidget.cardWidthPt;
    final pr = MediaQuery.devicePixelRatioOf(context).clamp(1.25, 2.25);
    final batchSig = (signatoryAssinaturaUrl ?? '').trim();
    final batchNome = (signatoryNome ?? '').trim();
    final batchCargo = (signatoryCargo ?? '').trim();

    try {
      for (final data in list) {
        final cfg = _effectiveCardConfig(data);
        _warmupCarteiraAssets(data, cfg);
        final fromMember =
            (data.member['carteirinhaAssinaturaUrl'] ?? '').toString().trim();
        final resolvedSig = batchSig.isNotEmpty
            ? batchSig
            : (fromMember.isNotEmpty ? fromMember : pastorSigFallback.trim());
        final sn = batchNome.isNotEmpty
            ? batchNome
            : (data.member['carteirinhaAssinadaPorNome'] ?? '')
                .toString()
                .trim();
        final sc = batchCargo.isNotEmpty
            ? batchCargo
            : (data.member['carteirinhaAssinadaPorCargo'] ?? '')
                .toString()
                .trim();

        if (!mounted) throw StateError('contexto inválido');
        setState(() {
          _rasterBatchCard = data;
          _rasterBatchLadoALado = false;
          _rasterBatchSigUrl = resolvedSig;
          _rasterBatchSignatoryNome = sn;
          _rasterBatchSignatoryCargo = sc;
        });
        for (var j = 0; j < 6; j++) {
          await WidgetsBinding.instance.endOfFrame;
        }
        await Future<void>.delayed(const Duration(milliseconds: 140));
        if (resolvedSig.isNotEmpty) {
          await _precacheWalletSigForExport(context, resolvedSig);
          await Future<void>.delayed(const Duration(milliseconds: 220));
        }
        final png =
            await _rasterBatchScreenshotController.capture(pixelRatio: pr);
        if (png == null || png.isEmpty) {
          throw StateError('Falha ao capturar carteirinha (${data.memberId})');
        }
        final img = pw.MemoryImage(png);
        doc.addPage(
          pw.Page(
            pageFormat: PdfPageFormat.a4,
            margin: const pw.EdgeInsets.symmetric(horizontal: 36, vertical: 28),
            build: (c) => pw.Center(
              child: pw.Image(
                img,
                width: cardWPt,
                fit: pw.BoxFit.fitWidth,
              ),
            ),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _rasterBatchCard = null;
          _rasterBatchLadoALado = false;
          _rasterBatchSigUrl = '';
          _rasterBatchSignatoryNome = '';
          _rasterBatchSignatoryCargo = '';
        });
      }
    }
    return doc.save();
  }

  /// A4: até 5 membros por folha; **por membro**, frente e verso na mesma linha, com captura raster
  /// dos widgets da carteira digital (fidelidade ao ecrã).
  Future<Uint8List> _buildPdfMultiWalletRasterFrenteVersoLinhaA4(
    BuildContext context,
    List<_CardData> list, {
    String? signatoryNome,
    String? signatoryCargo,
    String? signatoryAssinaturaUrl,
    String pastorSigFallback = '',
  }) async {
    if (list.isEmpty) {
      throw StateError('Lista vazia');
    }
    const membersPerPage = 5;
    const marginH = 36.0;
    const marginV = 28.0;
    const gapBetweenRowsPt = 8.0;
    final doc = await _newCarteirinhaPdfDoc();
    final pageFormat = PdfPageFormat.a4;
    final innerW = pageFormat.width - marginH * 2;
    final innerH = pageFormat.height - marginV * 2;
    final pr = MediaQuery.devicePixelRatioOf(context).clamp(1.25, 2.25);
    final batchSig = (signatoryAssinaturaUrl ?? '').trim();
    final batchNome = (signatoryNome ?? '').trim();
    final batchCargo = (signatoryCargo ?? '').trim();

    try {
      for (var pageStart = 0;
          pageStart < list.length;
          pageStart += membersPerPage) {
        final end = min(pageStart + membersPerPage, list.length);
        final chunk = list.sublist(pageStart, end);
        final pngBytesList = <Uint8List>[];
        final aspects = <double>[];

        for (final data in chunk) {
          final cfg = _effectiveCardConfig(data);
          _warmupCarteiraAssets(data, cfg);
          final fromMember =
              (data.member['carteirinhaAssinaturaUrl'] ?? '').toString().trim();
          final resolvedSig = batchSig.isNotEmpty
              ? batchSig
              : (fromMember.isNotEmpty ? fromMember : pastorSigFallback.trim());
          final sn = batchNome.isNotEmpty
              ? batchNome
              : (data.member['carteirinhaAssinadaPorNome'] ?? '')
                  .toString()
                  .trim();
          final sc = batchCargo.isNotEmpty
              ? batchCargo
              : (data.member['carteirinhaAssinadaPorCargo'] ?? '')
                  .toString()
                  .trim();

          if (!mounted) throw StateError('contexto inválido');
          setState(() {
            _rasterBatchCard = data;
            _rasterBatchLadoALado = true;
            _rasterBatchSigUrl = resolvedSig;
            _rasterBatchSignatoryNome = sn;
            _rasterBatchSignatoryCargo = sc;
          });
          for (var j = 0; j < 6; j++) {
            await WidgetsBinding.instance.endOfFrame;
          }
          await Future<void>.delayed(const Duration(milliseconds: 140));
          if (resolvedSig.isNotEmpty) {
            await _precacheWalletSigForExport(context, resolvedSig);
            await Future<void>.delayed(const Duration(milliseconds: 220));
          }
          final png =
              await _rasterBatchScreenshotController.capture(pixelRatio: pr);
          if (png == null || png.isEmpty) {
            throw StateError('Falha ao capturar carteirinha (${data.memberId})');
          }
          final ar = _aspectRatioFromPngBytes(png);
          if (ar == null) {
            throw StateError('Imagem inválida após captura (${data.memberId})');
          }
          pngBytesList.add(png);
          aspects.add(ar);
        }

        var sumNaturalH = 0.0;
        for (final a in aspects) {
          sumNaturalH += innerW * a;
        }
        if (aspects.length > 1) {
          sumNaturalH += gapBetweenRowsPt * (aspects.length - 1);
        }
        final scale = sumNaturalH > innerH ? innerH / sumNaturalH : 1.0;

        final rowWidgets = <pw.Widget>[];
        for (var i = 0; i < pngBytesList.length; i++) {
          final wPdf = innerW * scale;
          final hPdf = innerW * aspects[i] * scale;
          rowWidgets.add(
            pw.SizedBox(
              width: wPdf,
              height: hPdf,
              child: pw.Image(
                pw.MemoryImage(pngBytesList[i]),
                fit: pw.BoxFit.fill,
              ),
            ),
          );
          if (i < pngBytesList.length - 1) {
            rowWidgets.add(pw.SizedBox(height: gapBetweenRowsPt * scale));
          }
        }

        doc.addPage(
          pw.Page(
            pageFormat: pageFormat,
            margin: const pw.EdgeInsets.symmetric(
                horizontal: marginH, vertical: marginV),
            build: (_) => pw.Center(
              child: pw.Column(
                mainAxisSize: pw.MainAxisSize.min,
                children: rowWidgets,
              ),
            ),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _rasterBatchCard = null;
          _rasterBatchLadoALado = false;
          _rasterBatchSigUrl = '';
          _rasterBatchSignatoryNome = '';
          _rasterBatchSignatoryCargo = '';
        });
      }
    }
    return doc.save();
  }

  /// PDF com o **mesmo layout** da área “Carteira digital (Wallet)” na tela — captura
  /// [MemberDigitalWalletFront] + [MemberDigitalWalletBack] (logo [StableChurchLogo],
  /// foto [FotoMembroWidget]). Evita divergência do modelo só em PDF vetorial.
  Future<Uint8List> _buildPdfFromWalletScreenshot(BuildContext context) async {
    // Aguarda pintura completa da carteira (glass/gradient) sem atraso fixo longo.
    for (var i = 0; i < 3; i++) {
      await WidgetsBinding.instance.endOfFrame;
    }
    if (!context.mounted) {
      throw StateError('Contexto inválido para exportar PDF.');
    }
    final pr = MediaQuery.devicePixelRatioOf(context).clamp(1.25, 2.25);
    final png = await _walletScreenshotController.capture(pixelRatio: pr);
    if (png == null || png.isEmpty) {
      throw StateError('Não foi possível capturar a carteirinha.');
    }
    final doc = await _newCarteirinhaPdfDoc();
    final img = pw.MemoryImage(png);
    const cardWPt = VersoCarteirinhaPdfWidget.cardWidthPt;
    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.symmetric(horizontal: 36, vertical: 28),
        build: (c) => pw.Center(
          child: pw.Image(
            img,
            width: cardWPt,
            fit: pw.BoxFit.fitWidth,
          ),
        ),
      ),
    );
    return doc.save();
  }

  Future<void> _precacheWalletSigForExport(
      BuildContext context, String? rawUrl) async {
    final u = (rawUrl ?? '').trim();
    if (u.isEmpty || !context.mounted) return;
    try {
      await precacheImage(NetworkImage(u), context);
    } catch (_) {}
  }

  /// PDF único: **prioriza** o mesmo layout da carteira na tela (captura raster).
  /// Recua para PDF vetorial se a captura falhar (ex.: widget ainda não pintado).
  Future<Uint8List> _exportCarteirinhaPdfPreferringWalletModel(
    BuildContext context,
    _CardData data,
    PdfPageFormat format,
    _CardConfig cfg, {
    String? signatoryNome,
    String? signatoryCargo,
    String? signatoryAssinaturaUrl,
  }) async {
    final urlO = (signatoryAssinaturaUrl ?? '').trim();
    final nomeO = (signatoryNome ?? '').trim();
    final cargoO = (signatoryCargo ?? '').trim();
    final hasOverrides =
        urlO.isNotEmpty || nomeO.isNotEmpty || cargoO.isNotEmpty;
    if (hasOverrides && mounted) {
      await _precacheWalletSigForExport(context, signatoryAssinaturaUrl);
      setState(() {
        _walletPdfExportSigUrl = urlO.isNotEmpty ? urlO : null;
        _walletPdfExportSignatoryNome = nomeO.isNotEmpty ? nomeO : null;
        _walletPdfExportSignatoryCargo = cargoO.isNotEmpty ? cargoO : null;
      });
      for (var i = 0; i < 8; i++) {
        await WidgetsBinding.instance.endOfFrame;
      }
      if (urlO.isNotEmpty) {
        await Future<void>.delayed(const Duration(milliseconds: 450));
      }
    }
    try {
      return await _buildPdfFromWalletScreenshot(context);
    } catch (e, st) {
      debugPrint(
          'member_card: captura da carteira falhou, usando PDF vetorial: $e\n$st');
      return await _buildPdf(
        data,
        format,
        configOverride: cfg,
        signatoryNome: signatoryNome,
        signatoryCargo: signatoryCargo,
        signatoryAssinaturaUrl: signatoryAssinaturaUrl,
      );
    } finally {
      if (hasOverrides && mounted) {
        setState(() {
          _walletPdfExportSigUrl = null;
          _walletPdfExportSignatoryNome = null;
          _walletPdfExportSignatoryCargo = null;
        });
      }
    }
  }

  Future<void> _showGerarPdfComAssinatura(
      BuildContext context, _CardData data) async {
    final assinadaEm = data.member['carteirinhaAssinadaEm'];
    final assinadaPorNome =
        (data.member['carteirinhaAssinadaPorNome'] ?? '').toString().trim();
    final assinaturaUrl = (data.member['carteirinhaAssinaturaUrl'] ?? '')
        .toString()
        .trim();
    final isSigned = assinadaEm != null ||
        assinadaPorNome.isNotEmpty ||
        assinaturaUrl.isNotEmpty;
    if (_isRestrictedMember && !_canManage && !isSigned) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Sua carteirinha ainda não está assinada. Solicite assinatura ao pastor/gestor para liberar a exportação.',
            ),
          ),
        );
      }
      return;
    }

    final cfg = _effectiveCardConfig(data);
    if (_canManage) {
      final options = await _loadSignatoryOptions();
      if (!context.mounted) return;
      final defaultSigId =
          (data.cardConfig['defaultSignatoryMemberId'] ?? '').toString().trim();
      var selected =
          _selectSignatory(options, defaultSigId.isEmpty ? null : defaultSigId);
      var gravarAssinatura = true;
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (ctx) => StatefulBuilder(
          builder: (ctx, setModal) => Container(
            padding:
                EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(
                  top: Radius.circular(ThemeCleanPremium.radiusLg)),
            ),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('Assinatura na carteirinha',
                      style: Theme.of(ctx)
                          .textTheme
                          .titleLarge
                          ?.copyWith(fontWeight: FontWeight.w800)),
                  const SizedBox(height: 8),
                  Text(
                    'Assinatura visual (imagem no cadastro) ou lote com certificado A1/A3 em Configurar carteirinha — PAdES completo via integração futura.',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                  ),
                  const SizedBox(height: 16),
                  if (options.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Text(
                        'Nenhuma pessoa com cargo de liderança (além de membro) encontrada. Atribua funções em Membros → Editar e cadastre a assinatura.',
                        style: TextStyle(
                            fontSize: 13, color: Colors.grey.shade700),
                      ),
                    )
                  else
                    DropdownButtonFormField<
                        ({
                          String memberId,
                          String nome,
                          String cargo,
                          String? assinaturaUrl
                        })>(
                      value: selected,
                      decoration: InputDecoration(
                        labelText: 'Quem assina',
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(
                                ThemeCleanPremium.radiusSm)),
                      ),
                      items: options
                          .map((o) => DropdownMenuItem(
                              value: o, child: Text('${o.nome} — ${o.cargo}')))
                          .toList(),
                      onChanged: (v) => _refreshSignatoryFromFirestore(
                          ctx, setModal, v, (nv) => selected = nv),
                    ),
                  const SizedBox(height: 12),
                  CheckboxListTile(
                    value: gravarAssinatura,
                    onChanged: (v) =>
                        setModal(() => gravarAssinatura = v ?? true),
                    title: const Text(
                        'Gravar assinatura na carteirinha do membro'),
                    subtitle: const Text(
                        'A carteirinha ficará assinada para o membro visualizar'),
                    controlAffinity: ListTileControlAffinity.leading,
                    contentPadding: EdgeInsets.zero,
                  ),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      Expanded(
                          child: OutlinedButton(
                              onPressed: () => Navigator.pop(ctx),
                              child: const Text('Cancelar'))),
                      const SizedBox(width: 12),
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: () async {
                            Navigator.pop(ctx);
                            try {
                              final nome = selected?.nome;
                              final cargo = selected?.cargo;
                              final url = selected?.assinaturaUrl;
                              final bytes =
                                  await _exportCarteirinhaPdfPreferringWalletModel(
                                context,
                                data,
                                _kPdfCr80Export,
                                cfg,
                                signatoryNome: nome,
                                signatoryCargo: cargo,
                                signatoryAssinaturaUrl: url,
                              );
                              if (context.mounted)
                                await showPdfActions(context,
                                    bytes: bytes,
                                    filename:
                                        'carteirinha_${data.memberId}.pdf');
                              if (gravarAssinatura &&
                                  selected != null &&
                                  context.mounted) {
                                final ref = FirebaseFirestore.instance
                                    .collection('igrejas')
                                    .doc(widget.tenantId)
                                    .collection('membros')
                                    .doc(data.memberId);
                                await ref.set({
                                  'carteirinhaAssinadaEm':
                                      FieldValue.serverTimestamp(),
                                  'carteirinhaAssinadaPor': selected!.memberId,
                                  'carteirinhaAssinadaPorNome': selected!.nome,
                                  'carteirinhaAssinadaPorCargo':
                                      selected!.cargo,
                                  'carteirinhaAssinaturaUrl':
                                      selected!.assinaturaUrl ??
                                          FieldValue.delete(),
                                }, SetOptions(merge: true));
                                setState(() => _loadFuture = _load());
                                if (context.mounted)
                                  ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                          content: Text(
                                              'Assinatura gravada na carteirinha.')));
                              }
                            } catch (e) {
                              if (context.mounted)
                                ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(content: Text('Erro: $e')));
                            }
                          },
                          icon: const Icon(Icons.picture_as_pdf_rounded),
                          label: const Text('Exportar PDF'),
                          style: FilledButton.styleFrom(
                              backgroundColor: ThemeCleanPremium.primary),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    } else {
      final storedUrl =
          (data.member['carteirinhaAssinaturaUrl'] ?? '').toString().trim();
      final storedNome =
          (data.member['carteirinhaAssinadaPorNome'] ?? '').toString().trim();
      final storedCargo =
          (data.member['carteirinhaAssinadaPorCargo'] ?? '').toString().trim();
      try {
        final bytes =
            await _exportCarteirinhaPdfPreferringWalletModel(
          context,
          data,
          _kPdfCr80Export,
          cfg,
          signatoryNome: storedNome.isNotEmpty ? storedNome : null,
          signatoryCargo: storedCargo,
          signatoryAssinaturaUrl: storedUrl.isNotEmpty ? storedUrl : null,
        );
        if (context.mounted)
          await showPdfActions(context,
              bytes: bytes, filename: 'carteirinha_${data.memberId}.pdf');
      } catch (e) {
        final bytes =
            await _buildPdf(data, _kPdfCr80Export, configOverride: cfg);
        if (context.mounted)
          await showPdfActions(context,
              bytes: bytes, filename: 'carteirinha_${data.memberId}.pdf');
      }
    }
  }

  /// Frente + verso PDF (sem escala) — mesmo modelo da carteira digital.
  Future<({pw.Widget face, pw.Widget verso})> _pdfMemberFaceVersoUnscaled(
    _CardData data, {
    required bool inkEconomy,
    pw.ImageProvider? signatoryImage,
    String? signatoryNome,
    String? signatoryCargo,
  }) async {
    final cfgRaw = _cardConfigForPdf(data);
    final cfg = cfgRaw;
    final name = _memberNome(data.member);
    final cargo = _cargoDisplay(data.member, cfg);
    final cpf = _formatCpfForCard(_memberCpfRaw(data.member));
    final nascimento =
        _fmtDate(_dateFromMember(data.member, 'DATA_NASCIMENTO'));
    final batismo = _fmtDate(_dateFromMember(data.member, 'DATA_BATISMO'));
    final validade = _validityLabel(data.member).trim().isEmpty
        ? '---'
        : _validityLabel(data.member);
    final nomePai = _memberFatherName(data.member).trim().isEmpty
        ? '---'
        : _memberFatherName(data.member);
    final nomeMae = _memberMotherName(data.member).trim().isEmpty
        ? '---'
        : _memberMotherName(data.member);
    final sexo = _memberSexo(data.member);
    final photoUrl = cfg.showPhoto
        ? await _resolvedMemberPhotoUrlForPdf(data.memberId, data.member,
            igrejaDocId: data.igrejaDocId)
        : '';
    final palGrid = _pdfCarteiraColors(cfg, inkEconomy);
    final PdfColor bgColor = palGrid.bg;
    final PdfColor? bgColorSec = inkEconomy ? null : palGrid.bgEnd;
    final PdfColor textColor = palGrid.fg;
    final accentColor = cfg.accentPdfColor;
    final logo = await _pdfLogoProvider(cfgRaw, data);
    pw.ImageProvider? photo;
    if (photoUrl.isNotEmpty) {
      photo = await _pdfImageProviderFromUrlCached(photoUrl);
    }
    final admissionLinePdf = () {
      final s = _admissionBatismoLine(data.member).trim();
      return s.isEmpty ? 'Admissão: —' : s;
    }();
    final face = _pdfCardFace(
      name: name,
      cargo: cargo,
      cpf: cpf.isEmpty ? '---' : cpf,
      nascimento: nascimento.isEmpty ? '---' : nascimento,
      batismo: batismo.isEmpty ? '---' : batismo,
      validade: validade,
      nomePai: nomePai,
      nomeMae: nomeMae,
      sexo: sexo,
      admissionLine: admissionLinePdf,
      cfg: cfg,
      bgColor: bgColor,
      bgColorSec: bgColorSec,
      textColor: textColor,
      accentColor: accentColor,
      logo: logo,
      photo: photo,
      signatoryImage: signatoryImage,
      signatoryNome: signatoryNome,
      signatoryCargo: signatoryCargo,
      outerSlotWidth: _pdfCardSlotW,
      outerSlotHeight: _pdfCardSlotH,
    );
    pw.ImageProvider? sigIV = signatoryImage;
    if (sigIV == null) {
      final su =
          (data.member['carteirinhaAssinaturaUrl'] ?? '').toString().trim();
      if (su.isNotEmpty) {
        sigIV = await _pdfSignatureImageProviderFromUrlCached(su);
      }
    }
    final verso = pw.SizedBox(
      width: _pdfCardSlotW,
      height: _pdfCardSlotH,
      child: _pwVersoCarteirinhaBody(
        data,
        cfgRaw,
        pdfInkEconomy: inkEconomy,
        signatoryImage: sigIV,
        signatoryNome: signatoryNome,
        signatoryCargo: signatoryCargo,
      ),
    );
    return (face: face, verso: verso);
  }

  Future<Uint8List> _buildPdfMulti(
    List<_CardData> list,
    PdfPageFormat format, {
    String? signatoryNome,
    String? signatoryCargo,
    String? signatoryAssinaturaUrl,
    int gridCols = 1,
    int gridRows = 1,
    bool pvcCropMarks = false,
    bool inkEconomy = false,
    bool showCutGuides = true,
    bool frontVersoPorLinha = false,
    bool digitalVerticalStack = false,
  }) async {
    // Não limpar cache no início: [_gerarPdfUnicoLote] / assinatura em lote já rodaram
    // [preLoadImages] — limpar aqui obrigava a baixar logo/foto de novo (lento e falha na web).
    try {
      final doc = await _newCarteirinhaPdfDoc();
      pw.ImageProvider? signatoryImage;
      final sigUrlParam = (signatoryAssinaturaUrl ?? '').trim();
      if (sigUrlParam.isNotEmpty) {
        signatoryImage =
            await _pdfSignatureImageProviderFromUrlCached(sigUrlParam);
      }
      // Só usa assinatura gravada na ficha do **membro** quando o PDF não pediu
      // assinatura explícita do líder (evita misturar outro signatário).
      if (signatoryImage == null &&
          sigUrlParam.isEmpty &&
          list.isNotEmpty) {
        final su = (list.first.member['carteirinhaAssinaturaUrl'] ?? '')
            .toString()
            .trim();
        if (su.isNotEmpty) {
          signatoryImage = await _pdfSignatureImageProviderFromUrlCached(su);
        }
      }

      if (frontVersoPorLinha) {
        final membersPerPage = digitalVerticalStack ? 2 : 5;
        const crW = VersoCarteirinhaPdfWidget.cardWidthPt;
        const crH = VersoCarteirinhaPdfWidget.cardHeightPt;
        const baseVersoW = VersoCarteirinhaPdfWidget.cardWidthPt;
        const baseVersoH = VersoCarteirinhaPdfWidget.cardHeightPt;
        final margin = showCutGuides ? 22.0 : 18.0;
        const gapMid = 5.0;
        const gapStack = 8.0;

        for (var pageStart = 0;
            pageStart < list.length;
            pageStart += membersPerPage) {
          final end = min(pageStart + membersPerPage, list.length);
          final chunk = list.sublist(pageStart, end);

          final innerW = format.width - margin * 2;
          final innerH = format.height - margin * 2;
          final nRows = chunk.length;
          final rowH = innerH / nRows;
          final halfW = (innerW - gapMid) / 2;

          // Paralelo: [_gerarPdfUnicoLote] já pré-carregou fotos; aqui só monta widgets (antes era sequencial).
          final pairs = await Future.wait([
            for (final data in chunk)
              _pdfMemberFaceVersoUnscaled(
                data,
                inkEconomy: inkEconomy,
                signatoryImage: signatoryImage,
                signatoryNome: signatoryNome,
                signatoryCargo: signatoryCargo,
              ),
          ]);

          final lineRows = <pw.Widget>[];
          for (var r = 0; r < nRows; r++) {
            final pair = pairs[r];
            if (digitalVerticalStack) {
              final stackH = crH + gapStack + baseVersoH;
              final scaleStack =
                  min(innerW / crW, (rowH - 6) / stackH) * 0.92;
              lineRows.add(
                pw.Expanded(
                  child: pw.Padding(
                    padding: const pw.EdgeInsets.symmetric(vertical: 2),
                    child: pw.Center(
                      child: pw.Transform.scale(
                        alignment: pw.Alignment.center,
                        scale: scaleStack,
                        child: pw.Column(
                          mainAxisSize: pw.MainAxisSize.min,
                          crossAxisAlignment: pw.CrossAxisAlignment.center,
                          children: [
                            pair.face,
                            pw.SizedBox(height: gapStack),
                            pair.verso,
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              );
            } else {
              final scaleF = min(halfW / crW, (rowH - 6) / crH) * 0.92;
              final scaleV =
                  min(halfW / baseVersoW, (rowH - 6) / baseVersoH) * 0.92;
              lineRows.add(
                pw.Expanded(
                  child: pw.Padding(
                    padding: const pw.EdgeInsets.symmetric(vertical: 2),
                    child: pw.Row(
                      crossAxisAlignment: pw.CrossAxisAlignment.center,
                      children: [
                        pw.Expanded(
                          child: pw.Center(
                            child: pw.Transform.scale(
                              alignment: pw.Alignment.center,
                              scale: scaleF,
                              child: pair.face,
                            ),
                          ),
                        ),
                        pw.SizedBox(width: gapMid),
                        pw.Expanded(
                          child: pw.Center(
                            child: pw.Transform.scale(
                              alignment: pw.Alignment.center,
                              scale: scaleV,
                              child: pair.verso,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }
          }

          pw.Widget body = pw.Column(children: lineRows);
          if (showCutGuides) {
            body = CarteirinhaA4CutGuides.overlayOnGrid(
              cols: 2,
              rows: nRows,
              child: body,
            );
          }
          doc.addPage(
            pw.Page(
              pageFormat: format,
              build: (_) => pw.Padding(
                padding: pw.EdgeInsets.all(margin),
                child: body,
              ),
            ),
          );
        }
        return doc.save();
      }

      if (gridCols <= 1 && gridRows <= 1) {
        for (final data in list) {
          final cfg = _cardConfigForPdf(data);
          await _addCardPageToDoc(doc, data, format, cfg,
              signatoryNome: signatoryNome,
              signatoryCargo: signatoryCargo,
              signatoryImage: signatoryImage,
              pvcCropMarks: pvcCropMarks,
              pdfInkEconomy: inkEconomy);
        }
        return doc.save();
      }

      // Mesmo tamanho físico CR80 que a folha “1 por página” / modelo no ecrã.
      const crW = VersoCarteirinhaPdfWidget.cardWidthPt;
      const crH = VersoCarteirinhaPdfWidget.cardHeightPt;
      final slots = gridCols * gridRows;
      final multiCell = gridCols > 1 || gridRows > 1;
      final margin = (showCutGuides && multiCell) ? 22.0 : 18.0;
      final cellW = (format.width - margin * 2) / gridCols;
      final cellH = (format.height - margin * 2) / gridRows;
      final scale = min(cellW / crW, cellH / crH) * 0.92;

      for (var i = 0; i < list.length; i += slots) {
        final end = (i + slots > list.length) ? list.length : i + slots;
        final chunk = list.sublist(i, end);

        Future<pw.Widget> buildGridFaceCell(int k) async {
          if (k >= chunk.length) return pw.SizedBox();
          final data = chunk[k];
          final cfgRaw = _cardConfigForPdf(data);
          final cfg = cfgRaw;
          final name = _memberNome(data.member);
          final cargo = _cargoDisplay(data.member, cfg);
          final cpf = _formatCpfForCard(_memberCpfRaw(data.member));
          final nascimento =
              _fmtDate(_dateFromMember(data.member, 'DATA_NASCIMENTO'));
          final batismo =
              _fmtDate(_dateFromMember(data.member, 'DATA_BATISMO'));
          final validade = _validityLabel(data.member).trim().isEmpty
              ? '---'
              : _validityLabel(data.member);
          final nomePai = _memberFatherName(data.member).trim().isEmpty
              ? '---'
              : _memberFatherName(data.member);
          final nomeMae = _memberMotherName(data.member).trim().isEmpty
              ? '---'
              : _memberMotherName(data.member);
          final sexo = _memberSexo(data.member);
          final photoUrl = cfg.showPhoto
              ? await _resolvedMemberPhotoUrlForPdf(
                  data.memberId, data.member,
                  igrejaDocId: data.igrejaDocId)
              : '';
          final palGrid = _pdfCarteiraColors(cfg, inkEconomy);
          final PdfColor bgColor = palGrid.bg;
          final PdfColor? bgColorSec = inkEconomy ? null : palGrid.bgEnd;
          final PdfColor textColor = palGrid.fg;
          final accentColor = cfg.accentPdfColor;
          final logo = await _pdfLogoProvider(cfgRaw, data);
          pw.ImageProvider? photo;
          if (photoUrl.isNotEmpty) {
            photo = await _pdfImageProviderFromUrlCached(photoUrl);
          }
          final admissionLinePdf = () {
            final s = _admissionBatismoLine(data.member).trim();
            return s.isEmpty ? 'Admissão: —' : s;
          }();
          final face = _pdfCardFace(
            name: name,
            cargo: cargo,
            cpf: cpf.isEmpty ? '---' : cpf,
            nascimento: nascimento.isEmpty ? '---' : nascimento,
            batismo: batismo.isEmpty ? '---' : batismo,
            validade: validade,
            nomePai: nomePai,
            nomeMae: nomeMae,
            sexo: sexo,
            admissionLine: admissionLinePdf,
            cfg: cfg,
            bgColor: bgColor,
            bgColorSec: bgColorSec,
            textColor: textColor,
            accentColor: accentColor,
            logo: logo,
            photo: photo,
            signatoryImage: signatoryImage,
            signatoryNome: signatoryNome,
            signatoryCargo: signatoryCargo,
            outerSlotWidth: _pdfCardSlotW,
            outerSlotHeight: _pdfCardSlotH,
          );
          return pw.Center(
            child: pw.Transform.scale(
              alignment: pw.Alignment.center,
              scale: scale,
              child: face,
            ),
          );
        }

        final cells =
            await Future.wait(List.generate(slots, buildGridFaceCell));

        final rowWidgets = <pw.Widget>[];
        for (var r = 0; r < gridRows; r++) {
          final rowChildren = <pw.Widget>[];
          for (var c = 0; c < gridCols; c++) {
            rowChildren.add(
              pw.Expanded(
                child: pw.Padding(
                  padding: const pw.EdgeInsets.all(3),
                  child: cells[r * gridCols + c],
                ),
              ),
            );
          }
          rowWidgets.add(
            pw.Expanded(
              child: pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.center,
                children: rowChildren,
              ),
            ),
          );
        }

        pw.Widget gridFace = pw.Column(children: rowWidgets);
        if (showCutGuides && multiCell) {
          gridFace = CarteirinhaA4CutGuides.overlayOnGrid(
            cols: gridCols,
            rows: gridRows,
            child: gridFace,
          );
        }
        doc.addPage(
          pw.Page(
            pageFormat: format,
            build: (_) => pw.Padding(
              padding: pw.EdgeInsets.all(margin),
              child: gridFace,
            ),
          ),
        );

        const baseVersoW = VersoCarteirinhaPdfWidget.cardWidthPt;
        const baseVersoH = VersoCarteirinhaPdfWidget.cardHeightPt;
        final scaleV = min(cellW / baseVersoW, cellH / baseVersoH) * 0.92;

        Future<pw.Widget> buildGridVersoCell(int k) async {
          if (k >= chunk.length) return pw.SizedBox();
          final data = chunk[k];
          final cfgRaw = _cardConfigForPdf(data);
          pw.ImageProvider? sigIV = signatoryImage;
          if (sigIV == null) {
            final su = (data.member['carteirinhaAssinaturaUrl'] ?? '')
                .toString()
                .trim();
            if (su.isNotEmpty) {
              sigIV = await _pdfSignatureImageProviderFromUrlCached(su);
            }
          }
          return pw.Center(
            child: pw.Transform.scale(
              alignment: pw.Alignment.center,
              scale: scaleV,
              child: pw.SizedBox(
                width: _pdfCardSlotW,
                height: _pdfCardSlotH,
                child: _pwVersoCarteirinhaBody(
                  data,
                  cfgRaw,
                  pdfInkEconomy: inkEconomy,
                  signatoryImage: sigIV,
                  signatoryNome: signatoryNome,
                  signatoryCargo: signatoryCargo,
                ),
              ),
            ),
          );
        }

        final versoCells =
            await Future.wait(List.generate(slots, buildGridVersoCell));

        final versoRowWidgets = <pw.Widget>[];
        for (var r = 0; r < gridRows; r++) {
          final rowChildren = <pw.Widget>[];
          for (var c = 0; c < gridCols; c++) {
            rowChildren.add(
              pw.Expanded(
                child: pw.Padding(
                  padding: const pw.EdgeInsets.all(3),
                  child: versoCells[r * gridCols + c],
                ),
              ),
            );
          }
          versoRowWidgets.add(
            pw.Expanded(
              child: pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.center,
                children: rowChildren,
              ),
            ),
          );
        }

        pw.Widget gridVerso = pw.Column(children: versoRowWidgets);
        if (showCutGuides && multiCell) {
          gridVerso = CarteirinhaA4CutGuides.overlayOnGrid(
            cols: gridCols,
            rows: gridRows,
            child: gridVerso,
          );
        }
        doc.addPage(
          pw.Page(
            pageFormat: format,
            build: (_) => pw.Padding(
              padding: pw.EdgeInsets.all(margin),
              child: gridVerso,
            ),
          ),
        );
      }

      return doc.save();
    } finally {
      _clearPdfImageSessionCache();
    }
  }

  String _val(Map<String, dynamic> data, String key, {String fallback = ''}) {
    return (data[key] ?? fallback).toString();
  }

  /// Mesmos aliases do cadastro — evita PDF/prévia com "Membro" genérico quando só existe [nome].
  String _memberNome(Map<String, dynamic> m) {
    final r = _memberNomeOrEmpty(m);
    return r.isNotEmpty ? r : 'Membro';
  }

  String _memberNomeOrEmpty(Map<String, dynamic> m) {
    for (final k in ['NOME_COMPLETO', 'nome', 'name']) {
      final s = (m[k] ?? '').toString().trim();
      if (s.isNotEmpty) return s;
    }
    return '';
  }

  String _memberCpfRaw(Map<String, dynamic> m) {
    for (final k in ['CPF', 'cpf', 'cpfDigits', 'documento']) {
      final v = m[k];
      if (v != null) {
        final s = v.toString().trim();
        if (s.isNotEmpty) return s;
      }
    }
    return '';
  }

  String _formatCpfForCard(String raw) {
    final d = raw.replaceAll(RegExp(r'\D'), '');
    if (d.length != 11) return raw.trim();
    return '${d.substring(0, 3)}.${d.substring(3, 6)}.${d.substring(6, 9)}-${d.substring(9)}';
  }

  String _memberFatherName(Map<String, dynamic> member) {
    for (final k in [
      'FILIACAO_PAI',
      'filiacaoPai',
      'filiacao_pai',
      'nomePai',
      'NOME_PAI',
      'pai',
      'PAI',
      'nome_do_pai'
    ]) {
      final s = (member[k] ?? '').toString().trim();
      if (s.isNotEmpty) return s;
    }
    return '';
  }

  String _memberMotherName(Map<String, dynamic> member) {
    for (final k in [
      'FILIACAO_MAE',
      'filiacaoMae',
      'filiacao_mae',
      'nomeMae',
      'NOME_MAE',
      'mae',
      'mãe',
      'MAE',
      'MÃE',
      'nome_da_mae',
      'nome_da_mãe'
    ]) {
      final s = (member[k] ?? '').toString().trim();
      if (s.isNotEmpty) return s;
    }
    return '';
  }

  String _memberSexo(Map<String, dynamic> m) {
    for (final k in ['SEXO', 'sexo', 'genero']) {
      final s = (m[k] ?? '').toString().trim();
      if (s.isNotEmpty) return s;
    }
    return '';
  }

  /// Foto do cadastro do membro — mesma lógica de [imageUrlFromMap] para não perder URL (Storage, defaultImageUrl, listas).
  String _photoUrlFromMember(Map<String, dynamic> member) {
    final s = imageUrlFromMap(member);
    return isValidImageUrl(s) ? s : '';
  }

  /// URL para PDF / impressão: path/`gs://`/https via [AppStorageImageService], depois `membros/{id}.jpg`.
  Future<String> _resolvedMemberPhotoUrlForPdf(
    String memberId,
    Map<String, dynamic> member, {
    String? igrejaDocId,
  }) async {
    final tid = (igrejaDocId ?? widget.tenantId).trim();
    final mid = memberId.trim();
    final cpf = _val(member, 'CPF').replaceAll(RegExp(r'[^0-9]'), '');
    final mapHttps = _photoUrlFromMember(member);
    final fromService = await AppStorageImageService.instance
        .resolveImageUrl(
          storagePath: MemberImageFields.photoStoragePath(member),
          gsUrl: MemberImageFields.gsPhotoUrl(member),
          imageUrl: mapHttps.isNotEmpty ? mapHttps : null,
        )
        .timeout(const Duration(seconds: 18), onTimeout: () => null);
    var primary = (fromService != null && fromService.isNotEmpty)
        ? sanitizeImageUrl(fromService)
        : '';
    if (primary.isNotEmpty && isValidImageUrl(primary)) {
      if (isFirebaseStorageHttpUrl(primary)) {
        final fresh = await refreshFirebaseStorageDownloadUrl(primary)
            .timeout(const Duration(seconds: 4), onTimeout: () => primary);
        primary = sanitizeImageUrl(fresh ?? primary);
      }
      if (isValidImageUrl(primary)) return primary;
    }
    if (tid.isEmpty || mid.isEmpty) return '';
    final authPdf =
        (member['authUid'] ?? '').toString().trim();
    final nomePdf = (member['NOME_COMPLETO'] ??
            member['nome'] ??
            member['name'] ??
            '')
        .toString();
    final fromStorage =
        await FirebaseStorageService.getMemberProfilePhotoDownloadUrl(
      tenantId: tid,
      memberId: mid,
      cpfDigits: cpf.length == 11 ? cpf : null,
      authUid: authPdf.isEmpty ? null : authPdf,
      nomeCompleto: nomePdf,
      memberFirestoreHint: member,
    ).timeout(const Duration(seconds: 14), onTimeout: () => null);
    return (fromStorage != null && fromStorage.isNotEmpty) ? fromStorage : '';
  }

  void _warmupCarteiraAssets(_CardData data, _CardConfig cfg) {
    final memberPhoto = sanitizeImageUrl(imageUrlFromMap(data.member));
    final signUrl = sanitizeImageUrl(
        (data.member['carteirinhaAssinaturaUrl'] ?? '').toString().trim());
    final cfgLogo = (cfg.logoDataBase64 != null &&
            cfg.logoDataBase64!.trim().isNotEmpty)
        ? ''
        : sanitizeImageUrl(cfg.logoUrl);
    final logoUrl = cfgLogo.isNotEmpty
        ? cfgLogo
        : sanitizeImageUrl(churchTenantLogoUrl(data.tenant));
    final warmKey = '${data.memberId}|$memberPhoto|$signUrl|$logoUrl';
    if (_lastWarmupKey == warmKey) return;
    _lastWarmupKey = warmKey;
    unawaited(() async {
      Future<void> warm(String u) async {
        if (u.isEmpty || !isValidImageUrl(u)) return;
        try {
          var resolved = u;
          if (isFirebaseStorageHttpUrl(u)) {
            final fresh = await refreshFirebaseStorageDownloadUrl(u).timeout(
              const Duration(seconds: 4),
              onTimeout: () => u,
            );
            resolved = sanitizeImageUrl(fresh ?? u);
          }
          if (!mounted) return;
          if (!isValidImageUrl(resolved)) return;
          await preloadNetworkImages(context, [resolved], maxItems: 1);
        } catch (_) {}
      }

      Future<void> warmLogo() async {
        var u = logoUrl;
        if (u.isEmpty || !isValidImageUrl(u)) {
          final r = await FirebaseStorageService.getChurchLogoDownloadUrl(
            data.igrejaDocId,
            tenantData: data.tenant,
          );
          u = sanitizeImageUrl(r ?? '');
        }
        if (!mounted) return;
        await warm(u);
      }

      await Future.wait<void>([
        warm(memberPhoto),
        warm(signUrl),
        warmLogo(),
      ]);
    }());
  }

  bool _showMemberFinanceHistory(_CardData data) {
    if (_isRestrictedMember) return true;
    if (_canManage) return true;
    return AppPermissions.canViewFinance(
      widget.role,
      memberCanViewFinance: data.member['podeVerFinanceiro'] == true,
      permissions: AppPermissions.normalizePermissions(
        data.member['permissions'] ?? data.member['PERMISSIONS'],
      ),
    );
  }

  Widget _buildMemberFinanceHistorySection(_CardData data) {
    final brl = NumberFormat.currency(locale: 'pt_BR', symbol: r'R$');
    final tid = data.igrejaDocId;
    final mid = data.memberId;
    final stream = FirebaseFirestore.instance
        .collection('igrejas')
        .doc(tid)
        .collection('finance')
        .where('memberDocId', isEqualTo: mid)
        .orderBy('createdAt', descending: true)
        .limit(40)
        .snapshots();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(ThemeCleanPremium.spaceLg),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusMd),
        boxShadow: ThemeCleanPremium.softUiCardShadow,
        border: Border.all(color: const Color(0xFFF1F5F9)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: ThemeCleanPremium.primary.withOpacity(0.08),
                  borderRadius:
                      BorderRadius.circular(ThemeCleanPremium.radiusSm),
                ),
                child: Icon(Icons.payments_rounded,
                    color: ThemeCleanPremium.primary, size: 22),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  'Histórico financeiro',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF1E293B),
                    letterSpacing: -0.2,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            _isRestrictedMember
                ? 'Lançamentos em que este cadastro é o titular (ex.: dízimos e recorrências).'
                : 'Lançamentos do financeiro que referenciam este membro (memberDocId).',
            style: TextStyle(
              fontSize: 12,
              height: 1.35,
              color: Colors.grey.shade600,
            ),
          ),
          const SizedBox(height: 12),
          StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: stream,
            builder: (context, snap) {
              if (snap.hasError) {
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(
                    'Não foi possível carregar o histórico. Verifique permissão ou conexão.',
                    style: TextStyle(fontSize: 13, color: Colors.orange.shade800),
                  ),
                );
              }
              if (snap.connectionState == ConnectionState.waiting &&
                  snap.data == null) {
                return const Padding(
                  padding: EdgeInsets.symmetric(vertical: 20),
                  child: Center(
                    child: SizedBox(
                      width: 28,
                      height: 28,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                );
              }
              final docs = snap.data?.docs ?? [];
              if (docs.isEmpty) {
                return Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    'Nenhum lançamento vinculado a este cadastro.',
                    style: TextStyle(fontSize: 14, color: Colors.grey.shade700),
                  ),
                );
              }
              return ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: docs.length,
                separatorBuilder: (_, __) => Divider(
                  height: 1,
                  color: Colors.grey.shade200,
                ),
                itemBuilder: (context, i) {
                  final m = docs[i].data();
                  final tipo =
                      (m['type'] ?? m['tipo'] ?? 'entrada').toString().toLowerCase();
                  final isEntrada =
                      tipo == 'entrada' || tipo == 'receita' || tipo == 'in';
                  final raw = m['amount'] ?? m['valor'] ?? 0;
                  final valor = raw is num
                      ? raw.toDouble()
                      : double.tryParse(raw.toString()) ?? 0;
                  final desc = (m['descricao'] ?? m['memo'] ?? '').toString();
                  final cat = (m['categoria'] ?? '').toString();
                  final comp = (m['competencia'] ?? '').toString();
                  Timestamp? ts = m['createdAt'] is Timestamp
                      ? m['createdAt'] as Timestamp
                      : null;
                  final dataStr = ts != null
                      ? '${ts.toDate().day.toString().padLeft(2, '0')}/${ts.toDate().month.toString().padLeft(2, '0')}/${ts.toDate().year}'
                      : '';
                  final valorStr =
                      '${isEntrada ? '+' : '−'} ${brl.format(valor.abs())}';
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (desc.isNotEmpty)
                                Text(
                                  desc,
                                  maxLines: 3,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 14,
                                  ),
                                ),
                              if (cat.isNotEmpty || comp.isNotEmpty)
                                Padding(
                                  padding: const EdgeInsets.only(top: 4),
                                  child: Text(
                                    [
                                      if (cat.isNotEmpty) cat,
                                      if (comp.isNotEmpty) 'Comp. $comp',
                                    ].join(' · '),
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey.shade700,
                                    ),
                                  ),
                                ),
                              if (dataStr.isNotEmpty)
                                Padding(
                                  padding: const EdgeInsets.only(top: 2),
                                  child: Text(
                                    dataStr,
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: Colors.grey.shade500,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          valorStr,
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 14,
                            color: isEntrada
                                ? const Color(0xFF166534)
                                : const Color(0xFF991B1B),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              );
            },
          ),
        ],
      ),
    );
  }

  String _cargoDisplay(Map<String, dynamic> member, _CardConfig cfg) {
    final c = _val(member, 'CARGO').trim();
    final f = _val(member, 'FUNCAO').trim();
    var base = c.isNotEmpty ? c : (f.isNotEmpty ? f : cfg.cargoLabel);
    final cons =
        _fmtDate(_dateFromMember(member, 'DATA_CONSAGRACAO')).trim();
    if (cons.isNotEmpty && base.trim().isNotEmpty) {
      return '$base · Consagração $cons';
    }
    if (cons.isNotEmpty) return 'Consagração $cons';
    return base;
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = ThemeCleanPremium.isMobile(context);
    final hideAppBarEmbedded = widget.embeddedInShell && isMobile;
    return Scaffold(
      backgroundColor: ThemeCleanPremium.surfaceVariant,
      floatingActionButton: _emModoListaGestor &&
              _carteiraListaSelecionados.isNotEmpty
          ? Padding(
              padding: EdgeInsets.only(
                  bottom: MediaQuery.paddingOf(context).bottom + 56),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  FloatingActionButton.extended(
                    heroTag: 'fab_carteira_pdf_lote',
                    onPressed: () => _gerarPdfUnicoLote(context),
                    icon: const Icon(Icons.picture_as_pdf_rounded,
                        color: Colors.white),
                    label: Text(
                      'Vários em PDF (${_carteiraListaSelecionados.length})',
                      style: const TextStyle(
                          color: Colors.white, fontWeight: FontWeight.w600),
                    ),
                    backgroundColor: ThemeCleanPremium.primary,
                    foregroundColor: Colors.white,
                  ),
                  const SizedBox(height: 12),
                  FloatingActionButton.extended(
                    heroTag: 'fab_carteira_assinar_lote',
                    onPressed: () => _abrirAssinaturaBlocoSelecionados(context),
                    icon: const Icon(Icons.draw_rounded, color: Colors.white),
                    label: Text(
                      'Assinar (${_carteiraListaSelecionados.length})',
                      style: const TextStyle(
                          color: Colors.white, fontWeight: FontWeight.w600),
                    ),
                    backgroundColor: ThemeCleanPremium.primary,
                    foregroundColor: Colors.white,
                  ),
                ],
              ),
            )
          : null,
      appBar: hideAppBarEmbedded
          ? null
          : AppBar(
              leading: IconButton(
                icon: const Icon(Icons.arrow_back_rounded),
                onPressed: () => Navigator.maybePop(context),
                tooltip: 'Voltar',
              ),
              title: const Text('Carteirinha digital',
                  style: TextStyle(
                      fontWeight: FontWeight.w800, letterSpacing: -0.3)),
              flexibleSpace: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      ThemeCleanPremium.primary,
                      ThemeCleanPremium.primary.withValues(alpha: 0.92),
                      ThemeCleanPremium.navSidebar,
                    ],
                  ),
                ),
              ),
              backgroundColor: Colors.transparent,
              foregroundColor: Colors.white,
              elevation: 0,
              scrolledUnderElevation: 0,
              surfaceTintColor: Colors.transparent,
              actions: [
                IconButton(
                  tooltip: 'Exportar PDF',
                  icon: const Icon(Icons.picture_as_pdf_rounded),
                  style: IconButton.styleFrom(
                      minimumSize: const Size(ThemeCleanPremium.minTouchTarget,
                          ThemeCleanPremium.minTouchTarget)),
                  onPressed: () async {
                    final future = _loadFuture;
                    if (future == null) return;
                    final data = await future;
                    if (data == null || !context.mounted) return;
                    await _showGerarPdfComAssinatura(context, data);
                  },
                ),
                if (_canManage)
                  IconButton(
                    tooltip: 'Configurar cor e logo',
                    icon: const Icon(Icons.palette_rounded),
                    style: IconButton.styleFrom(
                        minimumSize: const Size(
                            ThemeCleanPremium.minTouchTarget,
                            ThemeCleanPremium.minTouchTarget)),
                    onPressed: () async {
                      await Navigator.push<void>(
                        context,
                        MaterialPageRoute(
                          builder: (_) =>
                              _CarteiraConfigPage(tenantId: widget.tenantId),
                        ),
                      );
                      setState(() {
                        _loadFuture = _load();
                      });
                    },
                  ),
                const SizedBox(width: 8),
              ],
            ),
      body: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
          if (hideAppBarEmbedded)
            Material(
              color: ThemeCleanPremium.cardBackground,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(4, 4, 4, 2),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    IconButton(
                      tooltip: 'Exportar PDF',
                      icon: const Icon(Icons.picture_as_pdf_rounded),
                      color: ThemeCleanPremium.primary,
                      style: IconButton.styleFrom(
                          minimumSize: const Size(
                              ThemeCleanPremium.minTouchTarget,
                              ThemeCleanPremium.minTouchTarget)),
                      onPressed: () async {
                        final future = _loadFuture;
                        if (future == null) return;
                        final data = await future;
                        if (data == null || !context.mounted) return;
                        await _showGerarPdfComAssinatura(context, data);
                      },
                    ),
                    if (_canManage)
                      IconButton(
                        tooltip: 'Configurar cor e logo',
                        icon: const Icon(Icons.palette_rounded),
                        color: ThemeCleanPremium.primary,
                        style: IconButton.styleFrom(
                            minimumSize: const Size(
                                ThemeCleanPremium.minTouchTarget,
                                ThemeCleanPremium.minTouchTarget)),
                        onPressed: () async {
                          await Navigator.push<void>(
                            context,
                            MaterialPageRoute(
                              builder: (_) =>
                                  _CarteiraConfigPage(tenantId: widget.tenantId),
                            ),
                          );
                          setState(() {
                            _loadFuture = _load();
                          });
                        },
                      ),
                  ],
                ),
              ),
            ),
          Expanded(
            child: DecoratedBox(
        decoration: BoxDecoration(gradient: ThemeCleanPremium.churchPanelBodyGradient),
        child: SafeArea(
          top: !hideAppBarEmbedded,
          child: FutureBuilder<_CardData?>(
            future: _loadFuture,
            builder: (context, snap) {
            if (snap.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snap.hasError) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.error_outline_rounded,
                          size: 48, color: Colors.orange.shade700),
                      const SizedBox(height: 16),
                      Text(
                        snap.error.toString().replaceFirst('Exception: ', ''),
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 15),
                      ),
                      const SizedBox(height: 24),
                      FilledButton.icon(
                        onPressed: () => setState(() {
                          if (_isRestrictedMember) {
                            _loadFuture = _load();
                          } else {
                            _loadFuture = _hasExplicitMemberTarget
                                ? _load()
                                : Future.value(null);
                          }
                        }),
                        icon: const Icon(Icons.refresh_rounded),
                        label: const Text('Tentar novamente'),
                      ),
                    ],
                  ),
                ),
              );
            }
            final data = snap.data;
            if (data == null) {
              if (_isRestrictedMember) {
                return Center(
                  child: SingleChildScrollView(
                    padding: ThemeCleanPremium.pagePadding(context),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 420),
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                          horizontal: ThemeCleanPremium.spaceXl,
                          vertical: ThemeCleanPremium.spaceXxl,
                        ),
                        decoration: ThemeCleanPremium.premiumSurfaceCard,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.badge_rounded,
                              size: 56,
                              color: ThemeCleanPremium.primary
                                  .withValues(alpha: 0.38),
                            ),
                            const SizedBox(height: ThemeCleanPremium.spaceMd),
                            const Text(
                              'Minha Carteirinha',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w800,
                                color: ThemeCleanPremium.onSurface,
                                letterSpacing: 0.2,
                              ),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: ThemeCleanPremium.spaceSm),
                            Text(
                              'Cadastro de membro não encontrado. Entre em contato com o gestor da igreja.',
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                fontSize: 14,
                                height: 1.45,
                                color: ThemeCleanPremium.onSurfaceVariant,
                              ),
                            ),
                            const SizedBox(height: ThemeCleanPremium.spaceMd),
                            FilledButton.icon(
                              onPressed: () =>
                                  setState(() => _loadFuture = _load()),
                              icon: const Icon(Icons.refresh_rounded),
                              label: const Text('Tentar novamente'),
                              style: FilledButton.styleFrom(
                                backgroundColor: ThemeCleanPremium.primary,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: ThemeCleanPremium.spaceLg,
                                  vertical: ThemeCleanPremium.spaceSm,
                                ),
                                minimumSize: const Size(
                                  ThemeCleanPremium.minTouchTarget,
                                  ThemeCleanPremium.minTouchTarget,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(
                                    ThemeCleanPremium.radiusMd,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              }
              return Center(
                child: SingleChildScrollView(
                  padding: ThemeCleanPremium.pagePadding(context),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 520),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(ThemeCleanPremium.spaceLg),
                      decoration: ThemeCleanPremium.premiumSurfaceCard,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: ThemeCleanPremium.primary
                                      .withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                child: Icon(
                                  Icons.badge_rounded,
                                  size: 28,
                                  color: ThemeCleanPremium.primary,
                                ),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      'Emissão de Carteirinha',
                                      style: TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.w800,
                                        color: ThemeCleanPremium.onSurface,
                                        letterSpacing: -0.2,
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      'Carteirinha digital: personalize cores, logo e modelo em “Configurar cor e logo”.',
                                      style: TextStyle(
                                        fontSize: 13,
                                        height: 1.4,
                                        color: ThemeCleanPremium.onSurfaceVariant,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          if (_canManage) ...[
                            const SizedBox(height: 14),
                            OutlinedButton.icon(
                              onPressed: () async {
                                await Navigator.push<void>(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => _CarteiraConfigPage(
                                        tenantId: widget.tenantId),
                                  ),
                                );
                                setState(() => _loadFuture = _load());
                              },
                              icon: const Icon(Icons.palette_rounded, size: 20),
                              label: const Text(
                                  'Configurar cor e logo da carteirinha'),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: ThemeCleanPremium.primary,
                                side: BorderSide(
                                  color: ThemeCleanPremium.primary
                                      .withValues(alpha: 0.35),
                                ),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 12,
                                ),
                              ),
                            ),
                          ],
                          const SizedBox(height: 18),
                          Text(
                            'Selecione um membro abaixo para emitir a carteirinha ou use o botão para ir à lista completa.',
                            style: TextStyle(
                              fontSize: 14,
                              height: 1.45,
                              color: ThemeCleanPremium.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(height: 14),
                          TextField(
                        controller: _memberSearchController,
                        decoration: InputDecoration(
                          labelText: 'Buscar',
                          hintText: 'Nome ou CPF...',
                          prefixIcon: const Icon(Icons.search_rounded, size: 22),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(
                              ThemeCleanPremium.radiusMd,
                            ),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(
                              ThemeCleanPremium.radiusMd,
                            ),
                            borderSide: const BorderSide(
                              color: Color(0xFFE2E8F0),
                            ),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(
                              ThemeCleanPremium.radiusMd,
                            ),
                            borderSide: BorderSide(
                              color: ThemeCleanPremium.primary
                                  .withValues(alpha: 0.65),
                              width: 1.4,
                            ),
                          ),
                          filled: true,
                          fillColor: const Color(0xFFF8FAFC),
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 12),
                        ),
                        onChanged: (_) {
                          _memberSearchDebounce?.cancel();
                          _memberSearchDebounce = Timer(
                              const Duration(milliseconds: 280), () {
                            if (!mounted) return;
                            setState(() =>
                                _memberSearch = _memberSearchController.text);
                          });
                        },
                      ),
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF8FAFC),
                          borderRadius:
                              BorderRadius.circular(ThemeCleanPremium.radiusMd),
                          border: Border.all(color: const Color(0xFFE8EDF3)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Row(
                              children: [
                                Icon(Icons.filter_list_rounded,
                                    size: 20,
                                    color: ThemeCleanPremium.primary
                                        .withValues(alpha: 0.85)),
                                const SizedBox(width: 8),
                                Text('Filtros',
                                    style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w700,
                                        color: ThemeCleanPremium.onSurface)),
                                const Spacer(),
                                TextButton(
                                  onPressed: () => setState(() {
                                    _filtroGeneroCarteira = 'todos';
                                    _filtroFaixaCarteira = 'todas';
                                    _filtroDepartamentoCarteira = 'todos';
                                  }),
                                  child: const Text('Limpar filtros'),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: DropdownButtonFormField<String>(
                                    value: _filtroGeneroCarteira,
                                    isExpanded: true,
                                    decoration: InputDecoration(
                                      labelText: 'Gênero',
                                      border: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(
                                              ThemeCleanPremium.radiusSm)),
                                      isDense: true,
                                      contentPadding:
                                          const EdgeInsets.symmetric(
                                              horizontal: 12, vertical: 10),
                                    ),
                                    items: const [
                                      DropdownMenuItem(
                                          value: 'todos', child: Text('Todos')),
                                      DropdownMenuItem(
                                          value: 'masculino',
                                          child: Text('Homens')),
                                      DropdownMenuItem(
                                          value: 'feminino',
                                          child: Text('Mulheres')),
                                    ],
                                    onChanged: (v) => setState(() =>
                                        _filtroGeneroCarteira = v ?? 'todos'),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: DropdownButtonFormField<String>(
                                    value: _filtroFaixaCarteira,
                                    isExpanded: true,
                                    decoration: InputDecoration(
                                      labelText: 'Faixa etária',
                                      border: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(
                                              ThemeCleanPremium.radiusSm)),
                                      isDense: true,
                                      contentPadding:
                                          const EdgeInsets.symmetric(
                                              horizontal: 12, vertical: 10),
                                    ),
                                    items: const [
                                      DropdownMenuItem(
                                          value: 'todas', child: Text('Todas')),
                                      DropdownMenuItem(
                                          value: 'criancas',
                                          child: Text('Crianças')),
                                      DropdownMenuItem(
                                          value: 'adolescentes',
                                          child: Text('Adolescentes')),
                                      DropdownMenuItem(
                                          value: 'adultos',
                                          child: Text('Adultos')),
                                      DropdownMenuItem(
                                          value: 'idosos',
                                          child: Text('Idosos')),
                                    ],
                                    onChanged: (v) => setState(() =>
                                        _filtroFaixaCarteira = v ?? 'todas'),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            DropdownButtonFormField<String>(
                              value: _filtroDepartamentoCarteira,
                              isExpanded: true,
                              decoration: InputDecoration(
                                labelText: 'Departamento',
                                border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(
                                        ThemeCleanPremium.radiusSm)),
                                isDense: true,
                                contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 10),
                              ),
                              items: [
                                const DropdownMenuItem(
                                    value: 'todos', child: Text('Todos')),
                                ..._deptFilterItems.map((d) => DropdownMenuItem(
                                    value: d.id,
                                    child: Text(d.name,
                                        overflow: TextOverflow.ellipsis))),
                              ],
                              onChanged: (v) => setState(() =>
                                  _filtroDepartamentoCarteira = v ?? 'todos'),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      FutureBuilder<List<_MemberItem>>(
                        future: _membersListFuture,
                        builder: (context, snap) {
                          if (snap.hasError) {
                            return Padding(
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                      'Erro ao carregar membros: ${snap.error}',
                                      style: TextStyle(
                                          fontSize: 13,
                                          color: Colors.red.shade700),
                                      textAlign: TextAlign.center),
                                  const SizedBox(height: 8),
                                  TextButton.icon(
                                      onPressed: () => setState(() =>
                                          _membersListFuture =
                                              _loadMembersList()),
                                      icon: const Icon(Icons.refresh_rounded,
                                          size: 18),
                                      label: const Text('Tentar novamente')),
                                ],
                              ),
                            );
                          }
                          if (snap.connectionState == ConnectionState.waiting &&
                              !snap.hasData) {
                            return const Padding(
                                padding: EdgeInsets.all(24),
                                child:
                                    Center(child: CircularProgressIndicator()));
                          }
                          final all = snap.data ?? [];
                          final filtered =
                              all.where(_memberMatchesCarteiraFilters).toList();
                          final preloadUrls = filtered
                              .take(18)
                              .map((m) => (m.photoUrl ?? '').trim())
                              .where((u) => u.isNotEmpty)
                              .toList();
                          final fp =
                              '${filtered.length}|${_memberSearch.hashCode}|${preloadUrls.join('|')}';
                          if (fp != _memberListPreloadFingerprint) {
                            _memberListPreloadFingerprint = fp;
                            WidgetsBinding.instance.addPostFrameCallback((_) {
                              if (!context.mounted) return;
                              preloadNetworkImages(context, preloadUrls,
                                  maxItems: 12);
                            });
                          }
                          if (filtered.isEmpty) {
                            return Padding(
                              padding: const EdgeInsets.only(top: 8, bottom: 4),
                              child: Container(
                                width: double.infinity,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 22,
                                ),
                                decoration: BoxDecoration(
                                  color: ThemeCleanPremium.primary
                                      .withValues(alpha: 0.05),
                                  borderRadius: BorderRadius.circular(
                                    ThemeCleanPremium.radiusMd,
                                  ),
                                  border: Border.all(
                                    color: ThemeCleanPremium.primary
                                        .withValues(alpha: 0.14),
                                  ),
                                ),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      all.isEmpty
                                          ? Icons.people_outline_rounded
                                          : Icons.search_off_rounded,
                                      size: 40,
                                      color: ThemeCleanPremium.primary
                                          .withValues(alpha: 0.35),
                                    ),
                                    const SizedBox(height: 10),
                                    Text(
                                      all.isEmpty
                                          ? 'Nenhum membro cadastrado.'
                                          : 'Nenhum membro corresponde à busca e aos filtros.',
                                      textAlign: TextAlign.center,
                                      style: const TextStyle(
                                        fontSize: 14,
                                        height: 1.45,
                                        color: ThemeCleanPremium.onSurfaceVariant,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          }
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Padding(
                                padding: const EdgeInsets.only(bottom: 8),
                                child: Text(
                                  '${filtered.length} membro(s) na lista',
                                  style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey.shade600,
                                      fontWeight: FontWeight.w500),
                                ),
                              ),
                              if (_canManage &&
                                  _carteiraListaSelecionados.isNotEmpty) ...[
                                Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 14, vertical: 12),
                                  margin: const EdgeInsets.only(bottom: 10),
                                  decoration: BoxDecoration(
                                    color: ThemeCleanPremium.primary
                                        .withValues(alpha: 0.08),
                                    borderRadius: BorderRadius.circular(
                                        ThemeCleanPremium.radiusMd),
                                    border: Border.all(
                                      color: ThemeCleanPremium.primary
                                          .withValues(alpha: 0.22),
                                    ),
                                  ),
                                  child: Row(
                                    children: [
                                      Icon(Icons.checklist_rounded,
                                          color: ThemeCleanPremium.primary,
                                          size: 22),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Text(
                                          '${_carteiraListaSelecionados.length} selecionado(s) • ${filtered.length} visível(is) nesta lista',
                                          style: TextStyle(
                                            fontSize: 13,
                                            fontWeight: FontWeight.w700,
                                            color: ThemeCleanPremium.primary,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                              if (_canManage) ...[
                                Row(
                                  children: [
                                    TextButton(
                                      onPressed: () => setState(() {
                                        for (final x in filtered) {
                                          _carteiraListaSelecionados.add(x.id);
                                        }
                                      }),
                                      child: const Text('Marcar visíveis'),
                                    ),
                                    TextButton(
                                      onPressed: () => setState(
                                          _carteiraListaSelecionados.clear),
                                      child: const Text('Limpar seleção'),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 4),
                              ],
                              ConstrainedBox(
                                constraints:
                                    const BoxConstraints(maxHeight: 280),
                                child: ListView.builder(
                                  shrinkWrap: true,
                                  itemCount: filtered.length,
                                  itemBuilder: (_, i) {
                                    final m = filtered[i];
                                    final cpfLista =
                                        (m.data['CPF'] ?? m.data['cpf'] ?? '')
                                            .toString()
                                            .replaceAll(RegExp(r'\D'), '');
                                    final sel = _carteiraListaSelecionados
                                        .contains(m.id);
                                    return CheckboxListTile(
                                      value: sel,
                                      onChanged: !_canManage
                                          ? null
                                          : (v) => setState(() {
                                                if (v == true) {
                                                  _carteiraListaSelecionados
                                                      .add(m.id);
                                                } else {
                                                  _carteiraListaSelecionados
                                                      .remove(m.id);
                                                }
                                              }),
                                      secondary: InkWell(
                                        onTap: () {
                                          Navigator.of(context).push(
                                            MaterialPageRoute(
                                              builder: (_) => MemberCardPage(
                                                tenantId: widget.tenantId,
                                                role: widget.role,
                                                memberId: m.id,
                                                onNavigateToMembers:
                                                    widget.onNavigateToMembers,
                                              ),
                                            ),
                                          );
                                        },
                                        borderRadius: BorderRadius.circular(22),
                                        child: FotoMembroWidget(
                                          imageUrl: m.photoUrl,
                                          tenantId:
                                              _cachedIgrejaDocId ?? widget.tenantId,
                                          memberId: m.id,
                                          cpfDigits: cpfLista.length == 11
                                              ? cpfLista
                                              : null,
                                          memberData:
                                              m.data.isNotEmpty ? m.data : null,
                                          authUid: _memberAuthUidForCarteiraFoto(
                                              m.data),
                                          size: 44,
                                          backgroundColor: ThemeCleanPremium
                                              .primary
                                              .withOpacity(0.15),
                                          fallbackIcon: Icons.person_rounded,
                                          memCacheWidth: 150,
                                          memCacheHeight: 150,
                                        ),
                                      ),
                                      title: Text(m.name,
                                          style: const TextStyle(
                                              fontWeight: FontWeight.w600)),
                                      subtitle: !_canManage
                                          ? null
                                          : const Text(
                                              'Toque na foto para abrir a carteirinha'),
                                      controlAffinity:
                                          ListTileControlAffinity.leading,
                                    );
                                  },
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                      const SizedBox(height: 16),
                      FilledButton.icon(
                        onPressed: () {
                          if (widget.onNavigateToMembers != null) {
                            widget.onNavigateToMembers!();
                          } else {
                            Navigator.of(context).pop();
                          }
                        },
                        icon: const Icon(Icons.people_rounded),
                        label: const Text('Ir para Membros'),
                      ),
                      if (_canManage) ...[
                        const SizedBox(height: 12),
                        OutlinedButton.icon(
                          onPressed: () => _abrirEmitirVarios(context),
                          icon: const Icon(Icons.badge_outlined),
                          label: const Text('Emitir vários (gestor)'),
                        ),
                        const SizedBox(height: 8),
                        OutlinedButton.icon(
                          onPressed: () => _abrirAssinarEmLote(context),
                          icon: const Icon(Icons.draw_rounded),
                          label: const Text('Assinar carteirinhas em lote'),
                        ),
                      ],
                    ],
                  ),
                    ),
                  ),
                ),
              );
            }

            final cfg = _effectiveCardConfig(data);
            final name = _memberNome(data.member);
            final cpf = _memberCpfRaw(data.member);
            final cpfDigits = cpf.replaceAll(RegExp(r'[^0-9]'), '');
            final photoUrlPreview =
                sanitizeImageUrl(imageUrlFromMap(data.member));
            final nascimento =
                _fmtDate(_dateFromMember(data.member, 'DATA_NASCIMENTO'));
            final batismoFmt =
                _fmtDate(_dateFromMember(data.member, 'DATA_BATISMO')).trim();
            final validade = _validityLabel(data.member);
            _warmupCarteiraAssets(data, cfg);

            return Center(
              child: SingleChildScrollView(
                padding: EdgeInsets.symmetric(
                    horizontal: ThemeCleanPremium.spaceLg,
                    vertical: ThemeCleanPremium.spaceMd),
                child: Column(
                  children: [
                    if (_canManage) ...[
                      Align(
                        alignment: Alignment.center,
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 400),
                          child: Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 14),
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [
                                  Colors.white,
                                  ThemeCleanPremium.primary
                                      .withValues(alpha: 0.05),
                                ],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                              borderRadius:
                                  BorderRadius.circular(ThemeCleanPremium.radiusLg),
                              border: Border.all(
                                color: ThemeCleanPremium.primary
                                    .withValues(alpha: 0.2),
                              ),
                              boxShadow: ThemeCleanPremium.softUiCardShadow,
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(10),
                                  decoration: BoxDecoration(
                                    color: ThemeCleanPremium.primary
                                        .withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                  child: Icon(
                                    Icons.person_search_rounded,
                                    color: ThemeCleanPremium.primary,
                                    size: 24,
                                  ),
                                ),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Emissão para',
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                          color: Colors.grey.shade600,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        name,
                                        style: const TextStyle(
                                          fontSize: 17,
                                          fontWeight: FontWeight.w800,
                                          letterSpacing: -0.35,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                TextButton(
                                  onPressed: () =>
                                      Navigator.maybePop(context),
                                  child: const Text('Escolher outro'),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: ThemeCleanPremium.spaceMd),
                    ],
                    Container(
                      width: 360,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 14),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            Colors.white,
                            ThemeCleanPremium.primary.withValues(alpha: 0.03),
                          ],
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                        ),
                        borderRadius:
                            BorderRadius.circular(ThemeCleanPremium.radiusLg),
                        boxShadow: ThemeCleanPremium.softUiCardShadow,
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: _statusChip(
                              icon: Icons.account_circle_rounded,
                              label: 'Foto',
                              ok: photoUrlPreview.isNotEmpty,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: _statusChip(
                              icon: Icons.church_rounded,
                              label: 'Logo',
                              ok: cfg.logoDataBase64?.isNotEmpty == true ||
                                  cfg.logoUrl.trim().isNotEmpty ||
                                  churchTenantLogoUrl(data.tenant)
                                      .trim()
                                      .isNotEmpty,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: _statusChip(
                              icon: Icons.draw_rounded,
                              label: 'Assinatura',
                              ok: (data.member['carteirinhaAssinaturaUrl'] ??
                                      '')
                                  .toString()
                                  .trim()
                                  .isNotEmpty,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: ThemeCleanPremium.spaceMd),
                    Center(
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          onTap: () async =>
                              _showGerarPdfComAssinatura(context, data),
                          borderRadius:
                              BorderRadius.circular(ThemeCleanPremium.radiusLg),
                          child: Ink(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [
                                  ThemeCleanPremium.primary,
                                  ThemeCleanPremium.primary
                                      .withValues(alpha: 0.88),
                                  ThemeCleanPremium.navSidebar,
                                ],
                                begin: Alignment.centerLeft,
                                end: Alignment.centerRight,
                              ),
                              borderRadius: BorderRadius.circular(
                                  ThemeCleanPremium.radiusLg),
                              boxShadow: ThemeCleanPremium.cardShadowHover,
                            ),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 28, vertical: 16),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.picture_as_pdf_rounded,
                                      color: Colors.white, size: 22),
                                  const SizedBox(width: 10),
                                  const Text(
                                    'Exportar PDF',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w800,
                                      fontSize: 16,
                                      letterSpacing: -0.2,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Depois: imprimir, compartilhar ou salvar no dispositivo.',
                      style:
                          TextStyle(fontSize: 12, color: Colors.grey.shade600),
                      textAlign: TextAlign.center,
                    ),
                    if (!_canManage) ...[
                      const SizedBox(height: 12),
                      Builder(
                        builder: (ctx) {
                          final assinadaEm =
                              data.member['carteirinhaAssinadaEm'];
                          final assinadaPorNome =
                              (data.member['carteirinhaAssinadaPorNome'] ?? '')
                                  .toString();
                          if (assinadaEm != null) {
                            final dt = assinadaEm is Timestamp
                                ? assinadaEm.toDate()
                                : null;
                            return Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 14, vertical: 10),
                              decoration: BoxDecoration(
                                color:
                                    ThemeCleanPremium.primary.withOpacity(0.08),
                                borderRadius: BorderRadius.circular(
                                    ThemeCleanPremium.radiusSm),
                                border: Border.all(
                                    color: ThemeCleanPremium.primary
                                        .withOpacity(0.3)),
                              ),
                              child: Row(
                                children: [
                                  Icon(Icons.verified_rounded,
                                      color: ThemeCleanPremium.primary,
                                      size: 22),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Text(
                                      'Carteirinha assinada${dt != null ? ' em ${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year}' : ''}${assinadaPorNome.isNotEmpty ? ' por $assinadaPorNome' : ''}.',
                                      style: TextStyle(
                                          fontSize: 13,
                                          color: Colors.grey.shade800),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          }
                          return Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 12),
                            decoration: BoxDecoration(
                              color: Colors.amber.shade50,
                              borderRadius: BorderRadius.circular(
                                  ThemeCleanPremium.radiusSm),
                              border: Border.all(color: Colors.amber.shade200),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Carteirinha não assinada.',
                                    style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w600,
                                        color: Colors.grey.shade800)),
                                const SizedBox(height: 8),
                                FilledButton.tonalIcon(
                                  onPressed: () async {
                                    try {
                                      final ref = FirebaseFirestore.instance
                                          .collection('igrejas')
                                          .doc(widget.tenantId)
                                          .collection('membros')
                                          .doc(data.memberId);
                                      await ref.set({
                                        'solicitouAssinaturaCarteirinhaEm':
                                            FieldValue.serverTimestamp()
                                      }, SetOptions(merge: true));
                                      setState(() => _loadFuture = _load());
                                      if (context.mounted)
                                        ScaffoldMessenger.of(context)
                                            .showSnackBar(const SnackBar(
                                                content: Text(
                                                    'Solicitação enviada. O pastor/gestor irá assinar sua carteirinha.')));
                                    } catch (e) {
                                      if (context.mounted)
                                        ScaffoldMessenger.of(context)
                                            .showSnackBar(SnackBar(
                                                content: Text('Erro: $e')));
                                    }
                                  },
                                  icon:
                                      const Icon(Icons.draw_rounded, size: 18),
                                  label: const Text(
                                      'Solicitar assinatura ao pastor'),
                                  style: FilledButton.styleFrom(
                                      backgroundColor: ThemeCleanPremium.primary
                                          .withOpacity(0.15)),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ],
                    const SizedBox(height: 16),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Carteira digital (Wallet)',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: Colors.grey.shade900,
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Exportar PDF usa o mesmo visual da carteira abaixo (frente + verso); '
                      'visualização em folha A4 com largura de cartão CR80 para caber na tela. '
                      'PDF vetorial (se a captura falhar) usa páginas no tamanho do cartão. '
                      'Cores e destaque em Configurar carteirinha. '
                      'Assinatura: Configurar carteirinha ou assinatura no cadastro do signatário.',
                      style: TextStyle(
                        fontSize: 12,
                        height: 1.4,
                        color: Colors.grey.shade600,
                      ),
                    ),
                    const SizedBox(height: 12),
                    FutureBuilder<String?>(
                      key: ValueKey<String>(
                          'pastor_sig_cfg_${data.igrejaDocId}'),
                      future: FirebaseStorageService
                          .getPastorSignatureConfigDownloadUrl(
                              data.igrejaDocId),
                      builder: (context, snapPastor) {
                        final memberSig = (data.member['carteirinhaAssinaturaUrl'] ??
                                '')
                            .toString()
                            .trim();
                        final snapSig = (snapPastor.data ?? '').trim();
                        final exportSig = (_walletPdfExportSigUrl ?? '').trim();
                        final sigUrl = exportSig.isNotEmpty
                            ? exportSig
                            : (memberSig.isNotEmpty ? memberSig : snapSig);
                        final wCard = min(
                          360.0,
                          MediaQuery.sizeOf(context).width -
                              ThemeCleanPremium.spaceLg * 2,
                        ).clamp(280.0, 360.0);
                        final colorA = cfg.bgColorValue;
                        final colorB = cfg.bgColorSecondaryValue ??
                            CarteirinhaVisualTokens.gradientEndFromPrimary(
                                colorA);
                        final accentGold = cfg.accentColorValue;
                        final logoSlot = (cfg.logoDataBase64 != null &&
                                cfg.logoDataBase64!.isNotEmpty)
                            ? Image.memory(
                                base64Decode(cfg.logoDataBase64!),
                                fit: BoxFit.contain,
                                errorBuilder: (_, __, ___) => Image.asset(
                                  'assets/LOGO_GESTAO_YAHWEH.png',
                                  fit: BoxFit.contain,
                                ),
                              )
                            : StableChurchLogo(
                                tenantId: data.igrejaDocId,
                                tenantData: data.tenant,
                                storagePath:
                                    ChurchImageFields.logoStoragePath(data.tenant),
                                imageUrl: cfg.logoUrl.trim().isNotEmpty
                                    ? cfg.logoUrl.trim()
                                    : null,
                                // Tamanho lógico alto: [FittedBox] na carteira escala para o quadrado; cache maior = mais nítido.
                                width: 160,
                                height: 160,
                                fit: BoxFit.contain,
                                memCacheWidth: 320,
                                memCacheHeight: 320,
                              );
                        final photoSlot = FotoMembroWidget(
                          key: ValueKey<String>(
                            'wallet_photo_${data.memberId}_${memberPhotoDisplayCacheRevision(data.member) ?? 0}',
                          ),
                          imageUrl:
                              photoUrlPreview.isEmpty ? null : photoUrlPreview,
                          tenantId: data.igrejaDocId,
                          memberId: data.memberId,
                          cpfDigits:
                              cpfDigits.length == 11 ? cpfDigits : null,
                          memberData: data.member,
                          authUid: _memberAuthUidForCarteiraFoto(data.member),
                          size: 72,
                          memCacheWidth: 220,
                          memCacheHeight: 220,
                          imageCacheRevision:
                              memberPhotoDisplayCacheRevision(data.member),
                        );
                        final cpfFmt = _formatCpfForCard(cpf);
                        final filiacaoTxt =
                            walletFiliacaoFromMember(data.member);
                        final telM = _telefoneFromMember(data.member);
                        final signatoryNameWallet = (_walletPdfExportSignatoryNome ??
                                    '')
                                .trim()
                                .isNotEmpty
                            ? _walletPdfExportSignatoryNome!.trim()
                            : (data.member['carteirinhaAssinadaPorNome'] ?? '')
                                .toString();
                        final signatoryCargoWallet = (_walletPdfExportSignatoryCargo ??
                                    '')
                                .trim()
                                .isNotEmpty
                            ? _walletPdfExportSignatoryCargo!.trim()
                            : (data.member['carteirinhaAssinadaPorCargo'] ?? '')
                                .toString();
                        return Column(
                          children: [
                            Screenshot(
                              controller: _walletScreenshotController,
                              child: ColoredBox(
                                color: const Color(0xFFF8FAFC),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 12,
                                    horizontal: 8,
                                  ),
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      MemberDigitalWalletFront(
                                        width: wCard,
                                        colorA: colorA,
                                        colorB: colorB,
                                        textColor: cfg.textColorValue,
                                        accentGold: accentGold,
                                        churchTitle: cfg.title,
                                        churchSubtitle: cfg.subtitle,
                                        logoSlot: logoSlot,
                                        photoSlot: photoSlot,
                                        showPhoto: cfg.showPhoto,
                                        memberName: name,
                                        cargo: _cargoDisplay(data.member, cfg),
                                        admission: () {
                                          final a = _admissionBatismoLine(
                                              data.member);
                                          return a.isEmpty ? '—' : a;
                                        }(),
                                        validade: validade.isEmpty
                                            ? '—'
                                            : validade,
                                      ),
                                      const SizedBox(height: 14),
                                      MemberDigitalWalletBack(
                                        width: wCard,
                                        colorA: colorA,
                                        colorB: colorB,
                                        textColor: cfg.textColorValue,
                                        accentGold: accentGold,
                                        churchTitle: cfg.title,
                                        cpfOrDoc: cpfFmt.isEmpty ? '—' : cpfFmt,
                                        nascimento: nascimento.isEmpty
                                            ? '—'
                                            : nascimento,
                                        dataBatismo: batismoFmt.isEmpty
                                            ? '—'
                                            : batismoFmt,
                                        filiacaoPaiMae: filiacaoTxt.isEmpty
                                            ? '—'
                                            : filiacaoTxt,
                                        telefone:
                                            telM.isEmpty ? '—' : telM,
                                        signatureImageUrl:
                                            sigUrl.isEmpty ? null : sigUrl,
                                        signatoryName: signatoryNameWallet,
                                        signatoryCargo: signatoryCargoWallet,
                                        fraseRodape: cfg.fraseRodape,
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.only(top: 6),
                              child: Text(
                                'Verso — CPF, batismo, filiação, telefone e assinatura (no PDF/PNG acima)',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.blueGrey.shade600,
                                  letterSpacing: 0.2,
                                ),
                              ),
                            ),
                            const SizedBox(height: 12),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              alignment: WrapAlignment.center,
                              children: [
                                if (!kIsWeb)
                                  OutlinedButton.icon(
                                    onPressed: () =>
                                        _saveWalletImageToGallery(context),
                                    icon: const Icon(
                                        Icons.photo_library_outlined),
                                    label: const Text('Salvar na galeria'),
                                  ),
                                OutlinedButton.icon(
                                  onPressed: () => _shareWalletPng(context),
                                  icon: const Icon(Icons.ios_share_rounded),
                                  label: Text(
                                      kIsWeb ? 'Baixar / compartilhar PNG' : 'Compartilhar PNG'),
                                ),
                                FilledButton.icon(
                                  onPressed: () => _openWhatsAppCarteira(
                                    context,
                                    data,
                                    cfg,
                                    validade.isEmpty ? '—' : validade,
                                  ),
                                  icon: const Icon(Icons.chat_rounded),
                                  label: const Text(
                                      'Enviar imagem (WhatsApp / compart.)'),
                                  style: FilledButton.styleFrom(
                                    backgroundColor: const Color(0xFF25D366),
                                    foregroundColor: Colors.white,
                                  ),
                                ),
                              ],
                            ),
                            if (_maskNomePublico(name).isNotEmpty) ...[
                              const SizedBox(height: 10),
                              Text(
                                'Titular público (mascarado): ${_maskNomePublico(name)}',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.blueGrey.shade700,
                                ),
                              ),
                            ],
                          ],
                        );
                      },
                    ),
                    if (_showMemberFinanceHistory(data))
                      Padding(
                        padding: const EdgeInsets.only(top: 16),
                        child: _buildMemberFinanceHistorySection(data),
                      ),
                    if (_canManage)
                      Padding(
                        padding: const EdgeInsets.only(top: 16),
                        child: _ValidityEditor(
                          onSave: (opt) => _setValidity(data, opt),
                        ),
                      ),
                  ],
                ),
              ),
            );
          },
            ),
          ),
        ),
      ),
    ],
      ),
    ),
    if (_rasterBatchCard != null)
      Positioned(
        left: -12000,
        top: 0,
        child: SizedBox(
          width: _rasterBatchLadoALado ? 780 : 400,
          child: Screenshot(
            controller: _rasterBatchScreenshotController,
            child: ColoredBox(
              color: const Color(0xFFF8FAFC),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
                child: _walletDigitalFrontBackForRaster(
                  context: context,
                  data: _rasterBatchCard!,
                  cfg: _effectiveCardConfig(_rasterBatchCard!),
                  wCard: _rasterBatchLadoALado ? 352 : 360,
                  sigUrl: _rasterBatchSigUrl,
                  signatoryNome: _rasterBatchSignatoryNome,
                  signatoryCargo: _rasterBatchSignatoryCargo,
                  ladoALado: _rasterBatchLadoALado,
                ),
              ),
            ),
          ),
        ),
      ),
        ],
      ),
    );
  }

  Future<void> _saveWalletImageToGallery(BuildContext context) async {
    if (kIsWeb) {
      await _shareWalletPng(context);
      return;
    }
    try {
      final permitted = await Gal.hasAccess(toAlbum: true);
      if (!permitted && !await Gal.requestAccess(toAlbum: true)) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text('Permissão da galeria necessária para salvar.')),
          );
        }
        return;
      }
    } catch (_) {}
    if (!context.mounted) return;
    final pr = MediaQuery.devicePixelRatioOf(context).clamp(2.0, 4.0);
    final bytes = await _walletScreenshotController.capture(pixelRatio: pr);
    if (!context.mounted) return;
    if (bytes == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Não foi possível gerar a imagem.')),
      );
      return;
    }
    try {
      await Gal.putImageBytes(
        bytes,
        album: 'Gestão YAHWEH',
        name: 'carteira_yahweh_${DateTime.now().millisecondsSinceEpoch}',
      );
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Carteira salva na galeria de fotos.')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao salvar: $e')),
        );
      }
    }
  }

  Future<void> _shareWalletPng(BuildContext context) async {
    final pr = MediaQuery.devicePixelRatioOf(context).clamp(2.0, 4.0);
    final bytes = await _walletScreenshotController.capture(pixelRatio: pr);
    if (!context.mounted) return;
    if (bytes == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Não foi possível gerar a imagem.')),
      );
      return;
    }
    await Share.shareXFiles(
      [
        XFile.fromData(
          bytes,
          mimeType: 'image/png',
          name: 'carteira_digital.png',
        ),
      ],
    );
  }

  Future<void> _openWhatsAppCarteira(BuildContext context, _CardData data,
      _CardConfig cfg, String validade) async {
    final raw = (data.member['TELEFONES'] ??
            data.member['telefone'] ??
            data.member['TELEFONE'] ??
            '')
        .toString();
    var digits = raw.replaceAll(RegExp(r'\D'), '');
    if (digits.isEmpty) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
                'Cadastre o telefone do membro para sugerir o contato no WhatsApp.'),
          ),
        );
      }
    } else {
      if (!digits.startsWith('55') &&
          digits.length >= 10 &&
          digits.length <= 11) {
        digits = '55$digits';
      }
    }
    final church =
        cfg.title.trim().isEmpty ? 'sua igreja' : cfg.title.trim();
    try {
      final pr = MediaQuery.devicePixelRatioOf(context).clamp(2.0, 4.0);
      final bytes = await _walletScreenshotController.capture(pixelRatio: pr);
      if (!context.mounted) return;
      if (bytes != null && bytes.isNotEmpty) {
        await Share.shareXFiles(
          [
            XFile.fromData(
              bytes,
              mimeType: 'image/png',
              name: 'carteirinha_${data.memberId}.png',
            ),
          ],
        );
        if (context.mounted && digits.isNotEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Escolha WhatsApp e envie para +$digits (ou outro app).',
              ),
            ),
          );
        }
        return;
      }
    } catch (_) {}
    if (!context.mounted) return;
    if (digits.isEmpty) {
      await Share.share(
        'Carteirinha digital — $church. Validade: $validade',
        subject: 'Carteirinha — $church',
      );
      return;
    }
    final text = Uri.encodeComponent(
      'Olá! Segue a imagem da carteirinha digital ($church).',
    );
    final uri = Uri.parse('https://wa.me/$digits?text=$text');
    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Não foi possível compartilhar: $e')),
        );
      }
    }
  }

  Widget _statusChip({
    required IconData icon,
    required String label,
    required bool ok,
  }) {
    final bg = ok ? const Color(0xFFECFDF5) : const Color(0xFFFEF2F2);
    final fg = ok ? const Color(0xFF166534) : const Color(0xFF991B1B);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusSm),
        border: Border.all(
          color: ok
              ? const Color(0xFFBBF7D0).withValues(alpha: 0.9)
              : const Color(0xFFFECACA).withValues(alpha: 0.9),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 15, color: fg),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  fontSize: 11, fontWeight: FontWeight.w800, color: fg),
            ),
          ),
        ],
      ),
    );
  }
}

class _ValidityOption {
  final bool permanent;
  final int years;
  const _ValidityOption({required this.permanent, required this.years});
  const _ValidityOption.permanent()
      : permanent = true,
        years = 0;

  @override
  bool operator ==(Object other) {
    return other is _ValidityOption &&
        other.permanent == permanent &&
        other.years == years;
  }

  @override
  int get hashCode => Object.hash(permanent, years);
}

class _ValidityEditor extends StatefulWidget {
  final Future<void> Function(_ValidityOption option) onSave;
  const _ValidityEditor({required this.onSave});

  @override
  State<_ValidityEditor> createState() => _ValidityEditorState();
}

class _ValidityEditorState extends State<_ValidityEditor> {
  _ValidityOption _opt = _ValidityOption.permanent();
  bool _saving = false;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(ThemeCleanPremium.spaceLg),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusMd),
        boxShadow: ThemeCleanPremium.softUiCardShadow,
        border: Border.all(color: const Color(0xFFF1F5F9)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.verified_rounded,
                  size: 20, color: ThemeCleanPremium.primary),
              const SizedBox(width: 8),
              const Text(
                'Validade da carteirinha',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
              ),
            ],
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<_ValidityOption>(
            value: _opt,
            items: [
              const DropdownMenuItem(
                value: _ValidityOption(permanent: true, years: 0),
                child: Text('Permanente'),
              ),
              const DropdownMenuItem(
                value: _ValidityOption(permanent: false, years: 1),
                child: Text('01 ano'),
              ),
              const DropdownMenuItem(
                value: _ValidityOption(permanent: false, years: 2),
                child: Text('02 anos'),
              ),
              const DropdownMenuItem(
                value: _ValidityOption(permanent: false, years: 3),
                child: Text('03 anos'),
              ),
              const DropdownMenuItem(
                value: _ValidityOption(permanent: false, years: 5),
                child: Text('05 anos'),
              ),
            ],
            onChanged: (v) => setState(() => _opt = v ?? _opt),
            decoration: const InputDecoration(
              labelText: 'Tipo de validade',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _saving
                  ? null
                  : () async {
                      setState(() => _saving = true);
                      await widget.onSave(_opt);
                      if (mounted) setState(() => _saving = false);
                    },
              child: Text(_saving ? 'Salvando...' : 'Salvar validade'),
            ),
          ),
        ],
      ),
    );
  }
}

class _CardData {
  final String memberId;
  final Map<String, dynamic> member;
  final Map<String, dynamic> cardConfig;
  final Map<String, dynamic> tenant;

  /// Doc `igrejas/{id}` canónico (Storage + logo institucional).
  final String igrejaDocId;

  const _CardData({
    required this.memberId,
    required this.member,
    required this.cardConfig,
    required this.tenant,
    required this.igrejaDocId,
  });
}

class _CardConfig {
  final String title;
  final String subtitle;
  final String logoUrl;

  /// Logo em base64 (galeria); usado quando não há permissão no Storage.
  final String? logoDataBase64;
  final String bgColor;
  final String textColor;
  final String? bgColorSecondary;

  /// Hex 6 dígitos (sem #) — faixa dourada / detalhes; Firestore: `accentColor` ou `accentGold`.
  final String? accentColorHex;
  final String cargoLabel;
  final bool showPhoto;

  /// Regras do verso do PDF; `null` ou vazio usa [VersoCarteirinhaPdfWidget.kRegrasPadrao].
  /// Firestore: `regrasVerso`, `carteiraRegrasVerso` ou `regrasUsoVerso` (lista ou texto com linhas).
  final List<String>? versoRegrasUso;

  /// Legado Firestore; o app usa um único modelo visual (`padrao`).
  final String visualModel;

  /// Frase no rodapé do verso (PDF e carteira digital).
  final String fraseRodape;

  const _CardConfig({
    required this.title,
    required this.subtitle,
    required this.logoUrl,
    this.logoDataBase64,
    required this.bgColor,
    required this.textColor,
    this.bgColorSecondary,
    this.accentColorHex,
    this.cargoLabel = '',
    this.showPhoto = true,
    this.versoRegrasUso,
    this.visualModel = 'padrao',
    this.fraseRodape = '',
  });

  _CardConfig copyWith({String? visualModel}) {
    return _CardConfig(
      title: title,
      subtitle: subtitle,
      logoUrl: logoUrl,
      logoDataBase64: logoDataBase64,
      bgColor: bgColor,
      textColor: textColor,
      bgColorSecondary: bgColorSecondary,
      accentColorHex: accentColorHex,
      cargoLabel: cargoLabel,
      showPhoto: showPhoto,
      versoRegrasUso: versoRegrasUso,
      visualModel: visualModel ?? this.visualModel,
      fraseRodape: fraseRodape,
    );
  }

  static String _normVisualModel(dynamic _) => 'padrao';

  static List<String>? _parseVersoRegras(dynamic v) {
    if (v == null) return null;
    if (v is List) {
      final o =
          v.map((e) => e.toString().trim()).where((e) => e.isNotEmpty).toList();
      return o.isEmpty ? null : o;
    }
    if (v is String) {
      final o = v
          .split(RegExp(r'\r?\n'))
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList();
      return o.isEmpty ? null : o;
    }
    return null;
  }

  factory _CardConfig.from(Map<String, dynamic> data) {
    final b64 = (data['logoDataBase64'] ?? '').toString().trim();
    return _CardConfig(
      title: (data['title'] ?? 'Gestao YAHWEH').toString(),
      subtitle: (data['subtitle'] ?? 'Credencial de Membro').toString(),
      logoUrl: sanitizeImageUrl((data['logoUrl'] ?? '').toString()),
      logoDataBase64: b64.isEmpty ? null : b64,
      bgColor: (data['bgColor'] ?? '#0B2F6B').toString(),
      textColor: (data['textColor'] ?? '#FFFFFF').toString(),
      bgColorSecondary: _optHex(data['bgColorSecondary']),
      accentColorHex: _optHex(data['accentColor'] ??
          data['accentGold'] ??
          data['carteiraAccentColor']),
      cargoLabel: (data['cargoLabel'] ?? '').toString().trim(),
      showPhoto: data['showPhoto'] != false,
      versoRegrasUso: _parseVersoRegras(data['regrasVerso'] ??
          data['carteiraRegrasVerso'] ??
          data['regrasUsoVerso']),
      visualModel:
          _normVisualModel(data['visualModel'] ?? data['carteiraVisualModel']),
      fraseRodape: (data['fraseRodape'] ??
              data['fraseRodapeVerso'] ??
              data['mottoCarteira'] ??
              '')
          .toString()
          .trim(),
    );
  }

  static String? _optHex(dynamic v) {
    if (v == null) return null;
    final s = v.toString().replaceAll('#', '').trim();
    return s.length == 6 ? s : null;
  }

  Color get bgColorValue => _hexToColor(bgColor, const Color(0xFF0B2F6B));
  Color? get bgColorSecondaryValue => bgColorSecondary == null
      ? null
      : _hexToColor(bgColorSecondary!, const Color(0xFF1E3A5F));
  Color get textColorValue => _hexToColor(textColor, Colors.white);

  /// Cor de destaque (bordas, selo) — igual à carteirinha digital e ao PDF.
  Color get accentColorValue {
    if (accentColorHex == null || accentColorHex!.length != 6) {
      return CarteirinhaVisualTokens.accentGoldFlutter;
    }
    return _hexToColor('#${accentColorHex!}', CarteirinhaVisualTokens.accentGoldFlutter);
  }

  PdfColor get accentPdfColor =>
      CarteirinhaVisualTokens.flutterColorToPdfColor(accentColorValue);

  Color _hexToColor(String hex, Color fallback) {
    final clean = hex.replaceAll('#', '').trim();
    if (clean.length != 6) return fallback;
    final v = int.tryParse(clean, radix: 16);
    if (v == null) return fallback;
    return Color(0xFF000000 + v);
  }
}

/// Cores disponíveis para a carteirinha (fundo e texto).
const _carteiraCores = [
  Color(0xFF0B2F6B), // azul escuro (padrão)
  Color(0xFF1E3A5F),
  Color(0xFF2563EB),
  Color(0xFF16A34A),
  Color(0xFF059669),
  Color(0xFF7C3AED),
  Color(0xFF4338CA),
  Color(0xFFDC2626),
  Color(0xFFB45309),
  Color(0xFF1F2937),
  Color(0xFFFFFFFF),
  Color(0xFFF3F4F6),
];

/// Logo da carteirinha — mesmo pipeline que o restante do app para URLs Firebase Storage ([SafeNetworkImage]).
class _CarteiraLogoImage extends StatefulWidget {
  final String imageUrl;
  final double width;
  final double height;
  final BoxFit fit;
  final Widget? errorWidget;

  const _CarteiraLogoImage({
    required this.imageUrl,
    required this.width,
    required this.height,
    this.fit = BoxFit.contain,
    this.errorWidget,
  });

  @override
  State<_CarteiraLogoImage> createState() => _CarteiraLogoImageState();
}

class _CarteiraLogoImageState extends State<_CarteiraLogoImage> {
  late Future<String> _resolvedUrlFuture;

  @override
  void initState() {
    super.initState();
    _resolvedUrlFuture = _resolveUrl(widget.imageUrl);
  }

  @override
  void didUpdateWidget(covariant _CarteiraLogoImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.imageUrl != widget.imageUrl) {
      _resolvedUrlFuture = _resolveUrl(widget.imageUrl);
    }
  }

  Future<String> _resolveUrl(String raw) async {
    final u = sanitizeImageUrl(raw);
    if (u.isEmpty || !isValidImageUrl(u)) return '';
    if (!isFirebaseStorageHttpUrl(u)) return u;
    final fresh = await refreshFirebaseStorageDownloadUrl(u);
    final resolved = sanitizeImageUrl(fresh ?? u);
    return isValidImageUrl(resolved) ? resolved : '';
  }

  @override
  Widget build(BuildContext context) {
    final err = widget.errorWidget ??
        Icon(Icons.broken_image_rounded, color: Colors.grey.shade400);
    if (isDataImageUrl(widget.imageUrl)) {
      try {
        final bytes = base64Decode(
            widget.imageUrl.substring(widget.imageUrl.indexOf(',') + 1));
        if (bytes.length > 24) {
          return Image.memory(
            bytes,
            fit: widget.fit,
            width: widget.width,
            height: widget.height,
            errorBuilder: (_, __, ___) => err,
          );
        }
      } catch (_) {}
      return err;
    }
    return FutureBuilder<String>(
      future: _resolvedUrlFuture,
      builder: (context, snap) {
        final u = snap.data ?? '';
        if (u.isEmpty) return err;
        final mcW = (widget.width * MediaQuery.devicePixelRatioOf(context))
            .round()
            .clamp(48, 512);
        final mcH = (widget.height * MediaQuery.devicePixelRatioOf(context))
            .round()
            .clamp(48, 512);
        return SafeNetworkImage(
          imageUrl: u,
          fit: widget.fit,
          width: widget.width,
          height: widget.height,
          memCacheWidth: mcW,
          memCacheHeight: mcH,
          errorWidget: err,
        );
      },
    );
  }
}

class _CarteiraConfigPage extends StatefulWidget {
  final String tenantId;

  const _CarteiraConfigPage({required this.tenantId});

  @override
  State<_CarteiraConfigPage> createState() => _CarteiraConfigPageState();
}

class _CarteiraConfigPageState extends State<_CarteiraConfigPage> {
  final _tituloCtrl = TextEditingController();
  final _subtituloCtrl = TextEditingController();
  final _fraseRodapeCtrl = TextEditingController();
  final _cargoCtrl = TextEditingController();
  String _bgColor = '#0B2F6B';
  String _textColor = '#FFFFFF';
  String? _bgColorSecondary;
  /// Bordas / faixa superior / selo — mesmo valor na carteirinha e no PDF.
  String _accentColor = 'E8C478';
  bool _showPhoto = true;
  bool _loading = true;
  bool _saving = false;

  /// Membros com cargo além de "membro" (podem assinar carteirinha).
  List<MapEntry<String, String>> _signatoryChoices = [];

  /// Pré-seleção ao gerar PDF (Firestore: `defaultSignatoryMemberId`).
  String? _defaultSignatoryMemberId;

  /// URL da logo do cadastro (quando não usa galeria). Logo da galeria fica em base64.
  String? _customLogoUrl;

  /// Logo escolhida da galeria em base64 (evita Firebase Storage sem permissão).
  String? _customLogoBase64;
  String? _tenantLogoUrl;
  Map<String, dynamic> _tenantData = {};

  bool _uploadingLogo = false;
  bool _uploadingCert = false;

  /// Nome do .p12 no perfil do usuário logado (referência em Storage restrito).
  String? _certDisplayName;

  static String _colorToHex(Color c) {
    final r = c.red.toRadixString(16).padLeft(2, '0');
    final g = c.green.toRadixString(16).padLeft(2, '0');
    final b = c.blue.toRadixString(16).padLeft(2, '0');
    return '$r$g$b';
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _tituloCtrl.dispose();
    _subtituloCtrl.dispose();
    _fraseRodapeCtrl.dispose();
    _cargoCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickLogoFromGallery() async {
    final file =
        await MediaHandlerService.instance.pickAndProcessLogoFromGallery();
    if (file == null || !mounted) return;
    setState(() => _uploadingLogo = true);
    try {
      final raw = await file.readAsBytes();
      final compressed = await ImageHelper.compressImage(
        raw,
        minWidth: 800,
        minHeight: 600,
        quality: 70,
      );
      await FirebaseAuth.instance.currentUser?.getIdToken();
      final prevLogo = (_customLogoUrl ?? '').trim();
      if (prevLogo.isNotEmpty) {
        await FirebaseStorageCleanupService.deleteObjectAtDownloadUrl(
            sanitizeImageUrl(prevLogo));
      }
      await FirebaseStorageCleanupService.deleteAllObjectsUnderPrefix(
          ChurchStorageLayout.cartaoMembroMediaPrefix(widget.tenantId));
      await FirebaseStorageCleanupService.deleteAllObjectsUnderPrefix(
          'carteira_logos/${widget.tenantId}');
      final upload = await MediaUploadService.uploadBytesDetailed(
        storagePath: ChurchStorageLayout.cartaoMembroLogoPath(widget.tenantId),
        bytes: compressed,
        contentType: 'image/jpeg',
        skipClientPrepare: true,
      );
      final url = upload.downloadUrl;
      FirebaseStorageCleanupService.scheduleCleanupAfterCartaoMembroLogoUpload(
        tenantId: widget.tenantId,
      );
      await CachedNetworkImage.evictFromCache(url);
      AppStorageImageService.instance.invalidateStoragePrefix(
          ChurchStorageLayout.cartaoMembroMediaPrefix(widget.tenantId));
      if (!mounted) return;
      setState(() {
        _customLogoUrl = url;
        _customLogoBase64 = null;
        _uploadingLogo = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Logo selecionada (4K) — pronto para usar.')));
    } catch (e) {
      if (mounted) {
        setState(() => _uploadingLogo = false);
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Erro ao carregar imagem: $e')));
      }
    }
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final db = FirebaseFirestore.instance;
    Map<String, dynamic> cfg = {};
    Map<String, dynamic> tenant = {};
    try {
      final snap = await db
          .collection('igrejas')
          .doc(widget.tenantId)
          .collection('config')
          .doc('carteira')
          .get();
      if (snap.exists && snap.data() != null) cfg = snap.data()!;
      final tenantSnap =
          await db.collection('igrejas').doc(widget.tenantId).get();
      tenant = Map<String, dynamic>.from(tenantSnap.data() ?? {})
        ..['id'] = widget.tenantId;
      _tenantData = Map<String, dynamic>.from(tenant);
    } catch (_) {}
    final tenantLogo = churchTenantLogoUrl(tenant);
    _tenantLogoUrl = tenantLogo.isEmpty ? null : tenantLogo;
    final savedB64 = (cfg['logoDataBase64'] ?? '').toString().trim();
    _customLogoBase64 = savedB64.isEmpty ? null : savedB64;
    final savedLogo = (cfg['logoUrl'] ?? '').toString().trim();
    _customLogoUrl = savedLogo.isEmpty ? null : savedLogo;
    _tituloCtrl.text =
        (cfg['title'] ?? tenant['name'] ?? tenant['nome'] ?? 'Gestão YAHWEH')
            .toString();
    _subtituloCtrl.text =
        (cfg['subtitle'] ?? 'Credencial de Membro').toString();
    _fraseRodapeCtrl.text = (cfg['fraseRodape'] ??
            cfg['fraseRodapeVerso'] ??
            cfg['mottoCarteira'] ??
            '')
        .toString();
    _cargoCtrl.text = (cfg['cargoLabel'] ?? '').toString();
    _showPhoto = cfg['showPhoto'] != false;
    final bg =
        (cfg['bgColor'] ?? '#0B2F6B').toString().replaceAll('#', '').trim();
    final tx =
        (cfg['textColor'] ?? '#FFFFFF').toString().replaceAll('#', '').trim();
    _bgColor = bg.length == 6 ? bg : '0B2F6B';
    _textColor = tx.length == 6 ? tx : 'FFFFFF';
    final sec =
        (cfg['bgColorSecondary'] ?? '').toString().replaceAll('#', '').trim();
    _bgColorSecondary = sec.length == 6 ? sec : null;
    final ac = (cfg['accentColor'] ?? cfg['accentGold'] ?? 'E8C478')
        .toString()
        .replaceAll('#', '')
        .trim();
    _accentColor = ac.length == 6 ? ac : 'E8C478';
    final savedDef = (cfg['defaultSignatoryMemberId'] ?? '').toString().trim();
    _defaultSignatoryMemberId = savedDef.isEmpty ? null : savedDef;

    _signatoryChoices = [];
    try {
      final ms = await db
          .collection('igrejas')
          .doc(widget.tenantId)
          .collection('membros')
          .limit(500)
          .get();
      for (final doc in ms.docs) {
        final d = doc.data();
        if (!memberHasLeadershipForAssinatura(d)) continue;
        final nome = (d['NOME_COMPLETO'] ?? d['nome'] ?? '').toString().trim();
        if (nome.isEmpty) continue;
        final cargo = signatoryCargoDisplayLabel(d);
        _signatoryChoices.add(MapEntry(doc.id, '$nome — $cargo'));
      }
      _signatoryChoices.sort(
          (a, b) => a.value.toLowerCase().compareTo(b.value.toLowerCase()));
    } catch (_) {}
    if (_defaultSignatoryMemberId != null &&
        !_signatoryChoices.any((e) => e.key == _defaultSignatoryMemberId)) {
      _defaultSignatoryMemberId = null;
    }
    _certDisplayName = null;
    try {
      _certDisplayName =
          await CertificadoDigitalService.certificateFileNameForCurrentUser();
    } catch (_) {}
    setState(() => _loading = false);
  }

  Future<void> _pickP12Certificado() async {
    final res = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['p12', 'pfx'],
      withData: true,
    );
    if (!mounted || res == null || res.files.isEmpty) return;
    final f = res.files.first;
    final bytes = f.bytes;
    if (bytes == null || bytes.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Não foi possível ler o arquivo.')));
      return;
    }
    setState(() => _uploadingCert = true);
    try {
      await FirebaseAuth.instance.currentUser?.getIdToken(true);
      await CertificadoDigitalService.uploadPfxForCurrentUser(
        tenantId: widget.tenantId,
        bytes: bytes,
        originalFileName: f.name,
      );
      if (!mounted) return;
      setState(() {
        _certDisplayName = f.name;
        _uploadingCert = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text(
                'Certificado enviado ao Storage (acesso restrito). A senha do .p12 não é salva no Firestore — informe-a ao assinar em lote.')),
      );
    } catch (e) {
      if (mounted) {
        setState(() => _uploadingCert = false);
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Erro: $e')));
      }
    }
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await FirebaseAuth.instance.currentUser?.getIdToken(true);
      final ref = FirebaseFirestore.instance
          .collection('igrejas')
          .doc(widget.tenantId)
          .collection('config')
          .doc('carteira');
      final payload = <String, dynamic>{
        'logoUrl': _customLogoBase64 != null
            ? ''
            : (_customLogoUrl ?? _tenantLogoUrl ?? ''),
        'logoDataBase64': _customLogoBase64 ?? '',
        'title': _tituloCtrl.text.trim().isEmpty
            ? 'Gestão YAHWEH'
            : _tituloCtrl.text.trim(),
        'subtitle': _subtituloCtrl.text.trim().isEmpty
            ? 'Credencial de Membro'
            : _subtituloCtrl.text.trim(),
        'fraseRodape': _fraseRodapeCtrl.text.trim(),
        'cargoLabel': _cargoCtrl.text.trim(),
        'bgColor': _bgColor.length == 6 ? _bgColor : '0B2F6B',
        'textColor': _textColor.length == 6 ? _textColor : 'FFFFFF',
        'bgColorSecondary':
            _bgColorSecondary != null && _bgColorSecondary!.length == 6
                ? _bgColorSecondary
                : null,
        'accentColor': _accentColor.length == 6 ? _accentColor : 'E8C478',
        'showPhoto': _showPhoto,
        'visualModel': 'padrao',
        'carteiraVisualModel': 'padrao',
        'updatedAt': FieldValue.serverTimestamp(),
      };
      if (_defaultSignatoryMemberId != null &&
          _defaultSignatoryMemberId!.trim().isNotEmpty) {
        payload['defaultSignatoryMemberId'] = _defaultSignatoryMemberId!.trim();
      } else {
        payload['defaultSignatoryMemberId'] = FieldValue.delete();
      }
      await ref.set(payload, SetOptions(merge: true));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Aparência da carteirinha salva.')));
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Erro ao salvar: $e')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        appBar: AppBar(
            title: const Text('Configurar carteirinha'),
            backgroundColor: ThemeCleanPremium.primary,
            foregroundColor: Colors.white),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    final effectiveLogoUrl = _customLogoBase64 != null
        ? 'data:image/jpeg;base64,$_customLogoBase64'
        : (_customLogoUrl ?? _tenantLogoUrl ?? '');
    return Scaffold(
      backgroundColor: ThemeCleanPremium.surfaceVariant,
      appBar: AppBar(
        title: const Text('Cor e logo da carteirinha'),
        backgroundColor: ThemeCleanPremium.primary,
        foregroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
            icon: const Icon(Icons.arrow_back_rounded),
            onPressed: () => Navigator.pop(context)),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.symmetric(
              horizontal: ThemeCleanPremium.spaceLg,
              vertical: ThemeCleanPremium.spaceMd),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildPremiumCard(
                title: 'Logo da carteirinha',
                icon: Icons.image_rounded,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Use o logo do cadastro da igreja ou escolha outro da galeria.',
                      style: TextStyle(
                          fontSize: 13,
                          color: Colors.grey.shade600,
                          height: 1.35),
                    ),
                    const SizedBox(height: ThemeCleanPremium.spaceMd),
                    Row(
                      children: [
                        Container(
                          width: 72,
                          height: 72,
                          decoration: BoxDecoration(
                            color: Colors.grey.shade100,
                            borderRadius: BorderRadius.circular(
                                ThemeCleanPremium.radiusSm),
                            border: Border.all(color: Colors.grey.shade300),
                          ),
                          child: effectiveLogoUrl.isNotEmpty
                              ? ClipRRect(
                                  borderRadius: BorderRadius.circular(
                                      ThemeCleanPremium.radiusSm),
                                  child: _CarteiraLogoImage(
                                    imageUrl: effectiveLogoUrl,
                                    fit: BoxFit.contain,
                                    width: 72,
                                    height: 72,
                                    errorWidget: StableChurchLogo(
                                      tenantId: widget.tenantId,
                                      tenantData: _tenantData,
                                      width: 72,
                                      height: 72,
                                      fit: BoxFit.contain,
                                      memCacheWidth: 144,
                                      memCacheHeight: 144,
                                    ),
                                  ),
                                )
                              : ClipRRect(
                                  borderRadius: BorderRadius.circular(
                                      ThemeCleanPremium.radiusSm),
                                  child: StableChurchLogo(
                                    tenantId: widget.tenantId,
                                    tenantData: _tenantData,
                                    width: 72,
                                    height: 72,
                                    fit: BoxFit.contain,
                                    memCacheWidth: 144,
                                    memCacheHeight: 144,
                                  ),
                                ),
                        ),
                        const SizedBox(width: ThemeCleanPremium.spaceMd),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              FilledButton.tonalIcon(
                                onPressed: _uploadingLogo
                                    ? null
                                    : () => setState(() {
                                          _customLogoBase64 = null;
                                          _customLogoUrl = null;
                                        }),
                                icon:
                                    const Icon(Icons.church_rounded, size: 20),
                                label: const Text('Usar logo do cadastro'),
                                style: FilledButton.styleFrom(
                                  backgroundColor: (_customLogoBase64 == null &&
                                          _customLogoUrl == null)
                                      ? ThemeCleanPremium.primary
                                          .withOpacity(0.12)
                                      : null,
                                  foregroundColor: ThemeCleanPremium.primary,
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 12),
                                  shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(
                                          ThemeCleanPremium.radiusSm)),
                                ),
                              ),
                              const SizedBox(height: 8),
                              OutlinedButton.icon(
                                onPressed: _uploadingLogo
                                    ? null
                                    : _pickLogoFromGallery,
                                icon: _uploadingLogo
                                    ? const SizedBox(
                                        width: 18,
                                        height: 18,
                                        child: CircularProgressIndicator(
                                            strokeWidth: 2))
                                    : const Icon(Icons.photo_library_rounded,
                                        size: 20),
                                label: Text(_uploadingLogo
                                    ? 'Enviando...'
                                    : 'Escolher da galeria'),
                                style: OutlinedButton.styleFrom(
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 12),
                                  shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(
                                          ThemeCleanPremium.radiusSm)),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: ThemeCleanPremium.spaceMd),
              _buildPremiumCard(
                title: 'Texto da carteirinha',
                icon: Icons.text_fields_rounded,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildLabel('Título (nome da igreja)'),
                    const SizedBox(height: 6),
                    TextField(
                      controller: _tituloCtrl,
                      decoration: _inputDecoration(
                          hint: 'Ex: Assembleia de Deus - Sede'),
                    ),
                    const SizedBox(height: ThemeCleanPremium.spaceSm),
                    _buildLabel('Subtítulo'),
                    const SizedBox(height: 6),
                    TextField(
                      controller: _subtituloCtrl,
                      decoration:
                          _inputDecoration(hint: 'Ex: Credencial de Membro'),
                    ),
                    const SizedBox(height: ThemeCleanPremium.spaceSm),
                    _buildLabel('Frase oficial (rodapé do verso)'),
                    const SizedBox(height: 6),
                    TextField(
                      controller: _fraseRodapeCtrl,
                      maxLines: 2,
                      decoration: _inputDecoration(
                          hint:
                              'Ex: Uma igreja, uma fé, uma esperança — opcional'),
                    ),
                    const SizedBox(height: ThemeCleanPremium.spaceSm),
                    _buildLabel('Cargo / função padrão'),
                    const SizedBox(height: 6),
                    TextField(
                      controller: _cargoCtrl,
                      decoration: _inputDecoration(
                          hint:
                              'Ex: OBREIRO, MEMBRO (deixe vazio se cada membro tiver seu cargo)'),
                    ),
                    const SizedBox(height: ThemeCleanPremium.spaceSm),
                    SwitchListTile(
                      title: const Text('Mostrar foto do membro na carteirinha',
                          style: TextStyle(fontWeight: FontWeight.w600)),
                      subtitle: const Text(
                          'Desative para layout só com nome e dados',
                          style: TextStyle(fontSize: 12)),
                      value: _showPhoto,
                      onChanged: (v) => setState(() => _showPhoto = v),
                      contentPadding: EdgeInsets.zero,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(
                              ThemeCleanPremium.radiusSm)),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: ThemeCleanPremium.spaceMd),
              _buildPremiumCard(
                title: 'Assinatura padrão (PDF)',
                icon: Icons.draw_rounded,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Quem assina a carteirinha ao gerar o PDF: pastor, secretário ou qualquer cargo de liderança. O padrão pode ser alterado na hora de emitir.',
                      style: TextStyle(
                          fontSize: 13,
                          color: Colors.grey.shade600,
                          height: 1.35),
                    ),
                    const SizedBox(height: ThemeCleanPremium.spaceMd),
                    DropdownButtonFormField<String?>(
                      isExpanded: true,
                      value: _defaultSignatoryMemberId,
                      decoration: _inputDecoration(hint: 'Signatário padrão'),
                      items: [
                        const DropdownMenuItem<String?>(
                          value: null,
                          child: Text('Automático (primeiro da lista)'),
                        ),
                        ..._signatoryChoices.map(
                          (e) => DropdownMenuItem<String?>(
                            value: e.key,
                            child: Text(e.value,
                                maxLines: 2, overflow: TextOverflow.ellipsis),
                          ),
                        ),
                      ],
                      onChanged: (v) =>
                          setState(() => _defaultSignatoryMemberId = v),
                    ),
                    if (_signatoryChoices.isEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 10),
                        child: Text(
                          'Nenhum membro com cargo além de "membro". Atribua funções em Membros → Editar.',
                          style: TextStyle(
                              fontSize: 12, color: Colors.orange.shade800),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: ThemeCleanPremium.spaceMd),
              _buildPremiumCard(
                title: 'Certificado digital (A1 / A3)',
                icon: Icons.verified_user_rounded,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Envie o arquivo .p12 ou .pfx do gestor logado. O PAdES completo no PDF está em roadmap; o fluxo em lote já gera ZIP e orienta integração ICP-Brasil.',
                      style: TextStyle(
                          fontSize: 13,
                          color: Colors.grey.shade600,
                          height: 1.35),
                    ),
                    const SizedBox(height: 12),
                    if ((_certDisplayName ?? '').isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Text('Arquivo vinculado: $_certDisplayName',
                            style:
                                const TextStyle(fontWeight: FontWeight.w600)),
                      ),
                    OutlinedButton.icon(
                      onPressed: _uploadingCert ? null : _pickP12Certificado,
                      icon: _uploadingCert
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.upload_file_rounded),
                      label: Text(_uploadingCert
                          ? 'Enviando...'
                          : 'Selecionar .p12 / .pfx'),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: ThemeCleanPremium.spaceMd),
              _buildPremiumCard(
                title: 'Cores',
                icon: Icons.palette_rounded,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'O modelo na tela, o PNG exportado e o PDF são o mesmo: só mudam as cores que você escolher abaixo.',
                      style: TextStyle(
                        fontSize: 12,
                        height: 1.35,
                        color: Colors.grey.shade600,
                      ),
                    ),
                    const SizedBox(height: 12),
                    _buildLabel('Cor de fundo'),
                    const SizedBox(height: 10),
                    Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: _carteiraCores
                            .map((c) => _colorChip(
                                c,
                                _bgColor,
                                () =>
                                    setState(() => _bgColor = _colorToHex(c))))
                            .toList()),
                    const SizedBox(height: ThemeCleanPremium.spaceSm),
                    _buildLabel('Cor secundária (gradiente)'),
                    Text('Opcional. Se escolher, o fundo terá gradiente.',
                        style: TextStyle(
                            fontSize: 12, color: Colors.grey.shade600)),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        _colorChip(
                            null,
                            _bgColorSecondary == null
                                ? 'none'
                                : _bgColorSecondary!,
                            () => setState(() => _bgColorSecondary = null),
                            isNone: true),
                        ..._carteiraCores.map((c) => _colorChip(
                            c,
                            _bgColorSecondary ?? '',
                            () => setState(
                                () => _bgColorSecondary = _colorToHex(c)))),
                      ],
                    ),
                    const SizedBox(height: ThemeCleanPremium.spaceSm),
                    _buildLabel('Cor do texto'),
                    const SizedBox(height: 10),
                    Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: _carteiraCores
                            .map((c) => _colorChip(
                                c,
                                _textColor,
                                () => setState(
                                    () => _textColor = _colorToHex(c))))
                            .toList()),
                    const SizedBox(height: ThemeCleanPremium.spaceSm),
                    _buildLabel('Cor de destaque (bordas e faixa)'),
                    Text(
                      'Aplica na carteirinha digital e no PDF — ouro por defeito.',
                      style: TextStyle(
                          fontSize: 12, color: Colors.grey.shade600),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: _carteiraCores
                          .map((c) => _colorChip(
                              c,
                              _accentColor,
                              () => setState(
                                  () => _accentColor = _colorToHex(c))))
                          .toList(),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: ThemeCleanPremium.spaceLg),
              SizedBox(
                height: 52,
                child: FilledButton.icon(
                  onPressed: _saving ? null : _save,
                  icon: _saving
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.check_rounded),
                  label: Text(_saving ? 'Salvando...' : 'Salvar',
                      style: const TextStyle(
                          fontWeight: FontWeight.w700, fontSize: 15)),
                  style: FilledButton.styleFrom(
                    backgroundColor: ThemeCleanPremium.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius:
                            BorderRadius.circular(ThemeCleanPremium.radiusSm)),
                    elevation: 0,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPremiumCard(
      {required String title, required IconData icon, required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(ThemeCleanPremium.spaceLg),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusMd),
        boxShadow: ThemeCleanPremium.softUiCardShadow,
        border: Border.all(color: const Color(0xFFF1F5F9)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: ThemeCleanPremium.primary.withOpacity(0.08),
                  borderRadius:
                      BorderRadius.circular(ThemeCleanPremium.radiusSm),
                ),
                child: Icon(icon, color: ThemeCleanPremium.primary, size: 22),
              ),
              const SizedBox(width: 12),
              Text(title,
                  style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF1E293B),
                      letterSpacing: -0.2)),
            ],
          ),
          const SizedBox(height: ThemeCleanPremium.spaceMd),
          child,
        ],
      ),
    );
  }

  Widget _buildLabel(String text) {
    return Text(text,
        style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: Colors.grey.shade800));
  }

  InputDecoration _inputDecoration({String? hint}) {
    return InputDecoration(
      hintText: hint,
      filled: true,
      fillColor: const Color(0xFFF8FAFC),
      border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusSm)),
      enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusSm),
          borderSide: BorderSide(color: Colors.grey.shade300)),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    );
  }

  Widget _colorChip(Color? c, String selectedHex, VoidCallback onTap,
      {bool isNone = false}) {
    if (isNone) {
      final sel = selectedHex == 'none';
      return GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: Colors.grey.shade200,
            shape: BoxShape.circle,
            border: Border.all(
                color: sel ? ThemeCleanPremium.primary : Colors.grey.shade300,
                width: sel ? 3 : 1),
          ),
          child: const Center(
              child: Text('—',
                  style: TextStyle(fontSize: 16, color: Colors.black54))),
        ),
      );
    }
    final hex = _colorToHex(c!);
    final sel =
        selectedHex.toUpperCase().replaceAll('#', '') == hex.toUpperCase();
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: c,
          shape: BoxShape.circle,
          border: Border.all(
              color: sel ? ThemeCleanPremium.primary : Colors.grey.shade300,
              width: sel ? 3 : 1),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withOpacity(0.06),
                blurRadius: 6,
                offset: const Offset(0, 2))
          ],
        ),
      ),
    );
  }
}
