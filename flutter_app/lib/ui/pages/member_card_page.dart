import 'dart:async' show unawaited;
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
import 'package:gestao_yahweh/core/carteirinha_consulta_url.dart';
import 'package:gestao_yahweh/services/firebase_storage_cleanup_service.dart';
import 'package:gestao_yahweh/services/tenant_resolver_service.dart';
import 'package:gestao_yahweh/services/certificado_digital_service.dart';
import 'package:gestao_yahweh/services/member_document_resolve.dart';
import 'package:gestao_yahweh/services/carteira_pades_signer.dart';
import 'package:gestao_yahweh/utils/carteirinha_zip_export.dart';
import 'package:gestao_yahweh/ui/pdf/verso_carteirinha_widget.dart';
import 'package:gestao_yahweh/ui/pdf/carteirinha_pvc_marks.dart';
import 'package:gestao_yahweh/ui/pdf/carteirinha_a4_cut_guides.dart';
import 'package:gestao_yahweh/ui/pdf/carteirinha_pdf_fonts.dart';
import 'package:gestao_yahweh/ui/widgets/foto_membro_widget.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:share_plus/share_plus.dart';
import 'package:gal/gal.dart';
import 'package:screenshot/screenshot.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:gestao_yahweh/ui/widgets/member_digital_wallet_card.dart';

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

({PdfPageFormat format, int cols, int rows, bool pvcCrop}) _pdfManyLayoutParams(
    _PdfManyLayout layout) {
  const cr80w = 85.6 * 72 / 25.4;
  const cr80h = 53.98 * 72 / 25.4;
  return switch (layout) {
    _PdfManyLayout.a4OnePerPage => (
        format: PdfPageFormat.a4,
        cols: 1,
        rows: 1,
        pvcCrop: false,
      ),
    _PdfManyLayout.a4Grid2x2 => (
        format: PdfPageFormat.a4,
        cols: 2,
        rows: 2,
        pvcCrop: false,
      ),
    _PdfManyLayout.a4Grid2x3 => (
        format: PdfPageFormat.a4,
        cols: 2,
        rows: 3,
        pvcCrop: false,
      ),
    _PdfManyLayout.a4Grid2x4 => (
        format: PdfPageFormat.a4,
        cols: 2,
        rows: 4,
        pvcCrop: false,
      ),
    _PdfManyLayout.a4Grid2x5 => (
        format: PdfPageFormat.a4,
        cols: 2,
        rows: 5,
        pvcCrop: false,
      ),
    _PdfManyLayout.cr80sheet => (
        format: PdfPageFormat(cr80w, cr80h),
        cols: 1,
        rows: 1,
        pvcCrop: false,
      ),
    _PdfManyLayout.cr80grafica => (
        format: CarteirinhaPvcMarks.pageFormat(),
        cols: 1,
        rows: 1,
        pvcCrop: true,
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

  const MemberCardPage({
    super.key,
    required this.tenantId,
    required this.role,
    this.memberId,
    this.cpf,
    this.onNavigateToMembers,
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

  /// Seleção na lista de membros (emissão / assinatura em bloco).
  final Set<String> _carteiraListaSelecionados = {};

  final ScreenshotController _walletScreenshotController = ScreenshotController();

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
    if (_isRestrictedMember) {
      _membersListFuture = Future.value([]);
      _loadFuture = _load();
    } else {
      _membersListFuture = _loadMembersList();
      _loadDepartmentsForCarteira().then((list) {
        if (mounted) setState(() => _deptFilterItems = list);
      });
      final hasMember =
          (widget.memberId != null && widget.memberId!.trim().isNotEmpty) ||
              (widget.cpf != null &&
                  widget.cpf!.replaceAll(RegExp(r'[^0-9]'), '').length >= 11);
      if (hasMember) {
        _loadFuture = _load();
      } else {
        _loadFuture = Future.value(null);
      }
    }
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

  bool get _canManage {
    final r = widget.role.toLowerCase();
    return r == 'adm' || r == 'admin' || r == 'gestor' || r == 'master';
  }

  /// Membro só vê e emite a própria carteirinha (acesso restrito).
  bool get _isRestrictedMember => widget.role.toLowerCase() == 'membro';

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
      tenant = tenantSnap.data() ?? {};
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
          if (cardCfg['bgColor'] == null && global['bgColor'] != null)
            cardCfg['bgColor'] = global['bgColor'];
          if (cardCfg['textColor'] == null && global['textColor'] != null)
            cardCfg['textColor'] = global['textColor'];
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

    if (memberDoc == null && cpf.length >= 11) {
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

  String _admissionBatismoLine(Map<String, dynamic> member) {
    final adm = _admissionForWallet(member);
    final bat = _fmtDate(_dateFromMember(member, 'DATA_BATISMO')).trim();
    if (adm.isNotEmpty && bat.isNotEmpty) {
      return 'Adm.: $adm  ·  Batismo: $bat';
    }
    if (adm.isNotEmpty) return 'Admissão: $adm';
    if (bat.isNotEmpty) return 'Batismo: $bat';
    return '';
  }

  String _congregacaoFromMember(Map<String, dynamic> m) {
    const keys = [
      'CONGREGACAO',
      'congregacao',
      'CONGREGAÇÃO',
      'igrejaLocal',
      'IGREJA_LOCAL',
      'SEDE',
      'sede',
    ];
    for (final k in keys) {
      final s = (m[k] ?? '').toString().trim();
      if (s.isNotEmpty) return s;
    }
    return '';
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
    var pdfLayout = _PdfManyLayout.a4OnePerPage;
    var pdfInkEconomy = true;
    var modalSearch = '';
    var modalGenero = 'todos';
    var modalFaixa = 'todas';
    var modalDept = 'todos';
    if (!context.mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
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

          return Container(
            constraints: BoxConstraints(
                maxHeight: MediaQuery.of(ctx).size.height * 0.85),
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(
                  top: Radius.circular(ThemeCleanPremium.radiusLg)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      const Text('Emitir várias carteirinhas',
                          style: TextStyle(
                              fontSize: 18, fontWeight: FontWeight.w700)),
                      const Spacer(),
                      TextButton(
                          onPressed: () => Navigator.pop(ctx),
                          child: const Text('Fechar')),
                    ],
                  ),
                ),
                if (signatoryOptions.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
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
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 10),
                      ),
                      items: signatoryOptions
                          .map((o) => DropdownMenuItem(
                              value: o,
                              child: Text('${o.nome} — ${o.cargo}',
                                  overflow: TextOverflow.ellipsis)))
                          .toList(),
                      onChanged: (v) => _refreshSignatoryFromFirestore(
                          ctx, setModal, v, (nv) => selectedSignatory = nv),
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: DropdownButtonFormField<_PdfManyLayout>(
                    value: pdfLayout,
                    isExpanded: true,
                    decoration: InputDecoration(
                      labelText: 'Papel / disposição na folha',
                      helperText:
                          'Grade no A4 para várias por página; CR80 = tamanho físico do cartão.',
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(
                              ThemeCleanPremium.radiusSm)),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 10),
                    ),
                    items: const [
                      DropdownMenuItem(
                          value: _PdfManyLayout.a4OnePerPage,
                          child: Text('A4 — 1 por folha (centralizada)')),
                      DropdownMenuItem(
                          value: _PdfManyLayout.a4Grid2x2,
                          child: Text('A4 — 4 por folha (grade 2×2)')),
                      DropdownMenuItem(
                          value: _PdfManyLayout.a4Grid2x3,
                          child: Text('A4 — 6 por folha (grade 2×3)')),
                      DropdownMenuItem(
                          value: _PdfManyLayout.a4Grid2x4,
                          child: Text('A4 — 8 por folha (grade 2×4, jato de tinta)')),
                      DropdownMenuItem(
                          value: _PdfManyLayout.a4Grid2x5,
                          child: Text('A4 — 10 por folha (grade 2×5)')),
                      DropdownMenuItem(
                          value: _PdfManyLayout.cr80sheet,
                          child: Text(
                              'Só cartão CR80 — 1 por folha (papel especial)')),
                      DropdownMenuItem(
                          value: _PdfManyLayout.cr80grafica,
                          child: Text(
                              'CR80 + marcas de corte (gráfica / PVC)')),
                    ],
                    onChanged: (v) => setModal(
                        () => pdfLayout = v ?? _PdfManyLayout.a4OnePerPage),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: () => setModal(() {
                        pdfLayout = _PdfManyLayout.a4Grid2x4;
                        pdfInkEconomy = true;
                      }),
                      icon: const Icon(Icons.grid_on_rounded, size: 20),
                      label: const Text(
                          'Predefinição: A4 com 8 cartões + menos tinta'),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: CheckboxListTile(
                    value: pdfInkEconomy,
                    onChanged: (v) =>
                        setModal(() => pdfInkEconomy = v ?? true),
                    title: const Text('Visual económico (menos tinta)'),
                    subtitle: const Text(
                        'PDF com fundo claro e bordas finas — ideal para impressora jato de tinta.'),
                    controlAffinity: ListTileControlAffinity.leading,
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text('Filtrar lista',
                          style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: Colors.grey.shade800)),
                      const SizedBox(height: 8),
                      TextField(
                        decoration: InputDecoration(
                          hintText: 'Nome ou CPF...',
                          prefixIcon:
                              const Icon(Icons.search_rounded, size: 22),
                          border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(
                                  ThemeCleanPremium.radiusSm)),
                          isDense: true,
                          filled: true,
                        ),
                        onChanged: (v) => setModal(() => modalSearch = v),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: DropdownButtonFormField<String>(
                              value: modalGenero,
                              isExpanded: true,
                              decoration: InputDecoration(
                                labelText: 'Gênero',
                                border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(
                                        ThemeCleanPremium.radiusSm)),
                                isDense: true,
                                contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 8),
                              ),
                              items: const [
                                DropdownMenuItem(
                                    value: 'todos', child: Text('Todos')),
                                DropdownMenuItem(
                                    value: 'masculino', child: Text('Homens')),
                                DropdownMenuItem(
                                    value: 'feminino', child: Text('Mulheres')),
                              ],
                              onChanged: (v) =>
                                  setModal(() => modalGenero = v ?? 'todos'),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: DropdownButtonFormField<String>(
                              value: modalFaixa,
                              isExpanded: true,
                              decoration: InputDecoration(
                                labelText: 'Faixa etária',
                                border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(
                                        ThemeCleanPremium.radiusSm)),
                                isDense: true,
                                contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 8),
                              ),
                              items: const [
                                DropdownMenuItem(
                                    value: 'todas', child: Text('Todas')),
                                DropdownMenuItem(
                                    value: 'criancas',
                                    child: Text('Crianças (<13)')),
                                DropdownMenuItem(
                                    value: 'adolescentes',
                                    child: Text('Adolescentes')),
                                DropdownMenuItem(
                                    value: 'adultos', child: Text('Adultos')),
                                DropdownMenuItem(
                                    value: 'idosos',
                                    child: Text('Idosos (60+)')),
                              ],
                              onChanged: (v) =>
                                  setModal(() => modalFaixa = v ?? 'todas'),
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
                              borderRadius: BorderRadius.circular(
                                  ThemeCleanPremium.radiusSm)),
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 10),
                        ),
                        items: [
                          const DropdownMenuItem(
                              value: 'todos', child: Text('Todos')),
                          ...deptsModal.map((d) => DropdownMenuItem(
                              value: d.id,
                              child: Text(d.name,
                                  overflow: TextOverflow.ellipsis))),
                        ],
                        onChanged: (v) =>
                            setModal(() => modalDept = v ?? 'todos'),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Mostrando ${visible.length} de ${emitMembers.length} membros',
                        style: TextStyle(
                            fontSize: 12, color: Colors.grey.shade600),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: visible.isEmpty
                      ? Center(
                          child: Text('Nenhum membro com esses filtros.',
                              style: TextStyle(color: Colors.grey.shade600)))
                      : ListView.builder(
                          itemCount: visible.length,
                          itemBuilder: (_, i) {
                            final m = visible[i];
                            final sel = selectedIds.contains(m.id);
                            return CheckboxListTile(
                              value: sel,
                              onChanged: (v) => setModal(() => v == true
                                  ? selectedIds.add(m.id)
                                  : selectedIds.remove(m.id)),
                              title:
                                  Text(m.name, overflow: TextOverflow.ellipsis),
                              secondary:
                                  const Icon(Icons.person_outline_rounded),
                            );
                          },
                        ),
                ),
                Padding(
                  padding: const EdgeInsets.all(16),
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
                                final lay = _pdfManyLayoutParams(pdfLayout);
                                final isA4Grid = pdfLayout ==
                                        _PdfManyLayout.a4Grid2x2 ||
                                    pdfLayout == _PdfManyLayout.a4Grid2x3 ||
                                    pdfLayout == _PdfManyLayout.a4Grid2x4 ||
                                    pdfLayout == _PdfManyLayout.a4Grid2x5;
                                final bytes = await _buildPdfMulti(
                                  list,
                                  lay.format,
                                  signatoryNome: selectedSignatory?.nome,
                                  signatoryCargo: selectedSignatory?.cargo,
                                  signatoryAssinaturaUrl:
                                      selectedSignatory?.assinaturaUrl,
                                  gridCols: lay.cols,
                                  gridRows: lay.rows,
                                  pvcCropMarks: lay.pvcCrop,
                                  inkEconomy: pdfInkEconomy,
                                );
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
                        (pdfLayout == _PdfManyLayout.a4Grid2x2 ||
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
              ],
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
    final cpf = (widget.cpf ?? '').replaceAll(RegExp(r'[^0-9]'), '');
    return mid.isEmpty && cpf.length < 11;
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
        final list = <_CardData>[];
        for (final id in ids) {
          final card = await _cardDataForMemberId(
              id, tpl.tenant, tpl.cardCfg, tpl.igrejaDocId);
          if (card == null) continue;
          await preLoadImages(card,
              signatoryAssinaturaUrl: signat.assinaturaUrl);
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
        final merged = await _buildPdfMulti(
          list,
          PdfPageFormat.a4,
          signatoryNome: signat.nome,
          signatoryCargo: signat.cargo,
          signatoryAssinaturaUrl: signat.assinaturaUrl,
          gridCols: 1,
          gridRows: 1,
        );
        if (context.mounted) {
          final r = await _firestoreAssinaturaLote(ids, signat);
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
          PdfPageFormat.a4,
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
              Text('PDF único — ${ids.length} carteirinha(s)',
                  style: const TextStyle(
                      fontSize: 18, fontWeight: FontWeight.w800)),
              const SizedBox(height: 8),
              Text(
                'Um PDF em A4: uma carteirinha por página (frente e verso alinhados). Abre primeiro para visualizar; imprimir ou compartilhar fica na tela do PDF.',
                style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
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

    final prog = ValueNotifier<int>(0);
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => ValueListenableBuilder<int>(
        valueListenable: prog,
        builder: (_, n, __) => PopScope(
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
                    value: ids.isEmpty ? null : n / ids.length),
                const SizedBox(height: 16),
                Text(
                  n == 0 ? 'Preparando…' : 'Gerando $n de ${ids.length}…',
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
      final signat = incluirAssinatura ? selected : null;

      final list = <_CardData>[];
      for (var i = 0; i < ids.length; i++) {
        final id = ids[i];
        final card = await _cardDataForMemberId(
            id, tpl.tenant, tpl.cardCfg, tpl.igrejaDocId);
        if (card == null) continue;
        await preLoadImages(card,
            signatoryAssinaturaUrl: signat?.assinaturaUrl);
        list.add(card);
        prog.value = i + 1;
      }

      if (list.isEmpty) {
        if (nav.canPop()) nav.pop();
        prog.dispose();
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text('Nenhum membro encontrado para gerar PDF.')));
        }
        return;
      }

      /// A4 vertical: uma carteirinha por folha (frente + verso empilhados, alinhados).
      final lay = _pdfManyLayoutParams(_PdfManyLayout.a4OnePerPage);
      final bytes = await _buildPdfMulti(
        list,
        lay.format,
        signatoryNome: signat?.nome,
        signatoryCargo: signat?.cargo,
        signatoryAssinaturaUrl: signat?.assinaturaUrl,
        gridCols: lay.cols,
        gridRows: lay.rows,
      );
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

  String _qrPayload(String tenantId, String memberId) {
    return CarteirinhaConsultaUrl.validationUrl(tenantId, memberId);
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
      tenant = tenantSnap.data() ?? {};
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
          if (cardCfg['bgColor'] == null && global['bgColor'] != null)
            cardCfg['bgColor'] = global['bgColor'];
          if (cardCfg['textColor'] == null && global['textColor'] != null)
            cardCfg['textColor'] = global['textColor'];
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
    await _pdfLogoProvider(cfg, data);
    if (cfg.showPhoto) {
      final u = await _resolvedMemberPhotoUrlForPdf(data.memberId, data.member,
          igrejaDocId: data.igrejaDocId);
      if (u.isNotEmpty) await _pdfImageProviderFromUrlCached(u);
    }
    final sig = (signatoryAssinaturaUrl ?? '').trim();
    if (sig.isNotEmpty) await _pdfImageProviderFromUrlCached(sig);
  }

  /// Alias explícito para pré-carregamento de imagens antes da montagem do PDF.
  Future<void> preLoadImages(_CardData data,
      {String? signatoryAssinaturaUrl}) async {
    await _prefetchPdfAssetsForCard(data,
        signatoryAssinaturaUrl: signatoryAssinaturaUrl);
  }

  /// Converte hex (6 chars, com ou sem #) para PdfColor. Usa 0xAARRGGBB (alpha=255) para
  /// coincidir exatamente com a cor exibida na tela (Flutter Color), evitando diferença ao imprimir/exportar.
  PdfColor _hexToPdfColor(String hex, PdfColor fallback) {
    final clean = hex.replaceAll('#', '').trim();
    if (clean.length != 6) return fallback;
    final v = int.tryParse(clean, radix: 16);
    if (v == null) return fallback;
    return PdfColor.fromInt(0xFF000000 | v);
  }

  /// Mesmo tamanho físico da frente e do verso (CR80 ~ ISO/IEC 7810).
  static const double _pdfCardSlotW = VersoCarteirinhaPdfWidget.cardWidthPt;
  static const double _pdfCardSlotH = VersoCarteirinhaPdfWidget.cardHeightPt;

  /// Cache de imagens na mesma geração de PDF (evita baixar a mesma foto/logo várias vezes).
  final Map<String, pw.ImageProvider?> _pdfImageSessionCache = {};
  final Map<String, Uint8List?> _pdfImageBytesSessionCache = {};

  void _clearPdfImageSessionCache() {
    _pdfImageSessionCache.clear();
    _pdfImageBytesSessionCache.clear();
  }

  Future<Uint8List?> _resizeForPdf(Uint8List bytes, {int maxSide = 300}) async {
    try {
      final decoded = img.decodeImage(bytes);
      if (decoded == null) return bytes;
      final w = decoded.width;
      final h = decoded.height;
      if (w <= maxSide && h <= maxSide) return bytes;
      final scale = w >= h ? (maxSide / w) : (maxSide / h);
      final rw = (w * scale).round().clamp(1, maxSide);
      final rh = (h * scale).round().clamp(1, maxSide);
      final resized = img.copyResize(decoded,
          width: rw, height: rh, interpolation: img.Interpolation.average);
      return Uint8List.fromList(img.encodeJpg(resized, quality: 78));
    } catch (_) {
      return bytes;
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
          _pdfImageBytesSessionCache[u] = out;
          return out;
        }
      } catch (_) {}
      _pdfImageBytesSessionCache[u] = null;
      return null;
    }
    try {
      final b = await ImageHelper.getBytesFromUrlOrNull(
        u,
        timeout: const Duration(seconds: 14),
      );
      if (b != null && b.length > 32) {
        final out = await _resizeForPdf(Uint8List.fromList(b));
        _pdfImageBytesSessionCache[u] = out;
        return out;
      }
    } catch (_) {}
    _pdfImageBytesSessionCache[u] = null;
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
    final tenant = data.tenant;
    final igrejaId = data.igrejaDocId.trim();
    final logoDataBase64 = cfg.logoDataBase64;
    final logoUrl = cfg.logoUrl;
    pw.ImageProvider? logo;
    try {
      if (logoDataBase64 != null && logoDataBase64.isNotEmpty) {
        logo = pw.MemoryImage(base64Decode(logoDataBase64));
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
            logo = pw.MemoryImage(lb);
          }
        } catch (_) {}
      }
    } catch (_) {}
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
    required String qr,

    /// Mesma linha da carteira digital (admissão / batismo).
    required String admissionLine,

    /// QR fica no verso; mantido na API por compatibilidade.
    bool showFrontQr = false,
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
    final pdfGold = CarteirinhaVisualTokens.accentGoldPdf;
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
        color: inkEco ? PdfColors.grey400 : pdfGold,
        width: 1,
      ),
    );
    final glassFill = inkEco ? PdfColors.grey200 : PdfColor(1, 1, 1, 0.14);
    final glassBorder =
        inkEco ? PdfColors.grey500 : PdfColor(1, 1, 1, 0.24);
    final adm =
        admissionLine.trim().isEmpty ? 'Admissão: —' : admissionLine.trim();

    final columnChildren = <pw.Widget>[
      pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Container(
            width: 44,
            height: 44,
            decoration: pw.BoxDecoration(
              color: inkEco ? PdfColors.grey100 : PdfColors.white,
              borderRadius: pw.BorderRadius.circular(10),
            ),
            padding: const pw.EdgeInsets.all(4),
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
                  border: pw.Border.all(color: pdfGold, width: 2),
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
              pw.SizedBox(width: 12),
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
                        color: PdfColor(pdfGold.red, pdfGold.green, pdfGold.blue,
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
    final validationUrl = _qrPayload(data.igrejaDocId, data.memberId);
    final barcodeData = '${data.igrejaDocId}|${data.memberId}';
    final igreja = cfg.title;
    final g1 = _hexToPdfColor(cfg.bgColor, PdfColor.fromHex('#004D40'));
    final g2 = cfg.bgColorSecondary != null
        ? _hexToPdfColor(cfg.bgColorSecondary!, PdfColors.blue900)
        : CarteirinhaVisualTokens.flutterColorToPdfColor(
            CarteirinhaVisualTokens.gradientEndFromPrimary(cfg.bgColorValue),
          );
    final fg = _hexToPdfColor(cfg.textColor, PdfColors.white);
    final validadePdf = _validityLabel(data.member).trim();
    final cong = _congregacaoFromMember(data.member);
    final frase = cfg.fraseRodape.trim();
    final cpfFmt = _formatCpfForCard(_memberCpfRaw(data.member));
    final nasc = _fmtDate(_dateFromMember(data.member, 'DATA_NASCIMENTO'));
    final filiacaoTxt = walletFiliacaoFromMember(data.member);
    final snIn = (signatoryNome ?? '').trim();
    final sn = snIn.isNotEmpty
        ? snIn
        : (data.member['carteirinhaAssinadaPorNome'] ?? '').toString().trim();
    final scIn = (signatoryCargo ?? '').trim();
    final sc = scIn.isNotEmpty
        ? scIn
        : (data.member['carteirinhaAssinadaPorCargo'] ?? '').toString().trim();
    return VersoCarteirinhaPdfWidget(
      validationUrl: validationUrl,
      nomeIgreja: igreja,
      regrasUso: cfg.versoRegrasUso,
      validadeDestaque: validadePdf.isNotEmpty ? validadePdf : null,
      barcodeData: barcodeData,
      gradientStart: g1,
      gradientEnd: g2,
      foregroundColor: fg,
      rodapeColor: PdfColor(
          fg.red, fg.green, fg.blue, (fg.alpha * 0.72).clamp(0.0, 1.0)),
      congregacao: cong.isNotEmpty ? cong : null,
      fraseInstitucional: frase.isNotEmpty ? frase : null,
      pdfInkEconomy: pdfInkEconomy,
      cpfDoc: cpfFmt,
      nascimentoDoc: nasc,
      filiacaoPaiMaeDoc: filiacaoTxt,
      assinaturaImage: signatoryImage,
      signatoryNome: sn,
      signatoryCargo: sc,
    );
  }

  Future<Uint8List> _buildPdf(_CardData data, PdfPageFormat format,
      {_CardConfig? configOverride,
      String? signatoryNome,
      String? signatoryCargo,
      String? signatoryAssinaturaUrl}) async {
    _clearPdfImageSessionCache();
    try {
      final doc = await _newCarteirinhaPdfDoc();
      final cfg = configOverride ?? _cardConfigForPdf(data);
      pw.ImageProvider? signatoryImage;
      if ((signatoryAssinaturaUrl ?? '').trim().isNotEmpty) {
        signatoryImage =
            await _pdfImageProviderFromUrlCached(signatoryAssinaturaUrl);
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
        sigImgVerso = await _pdfImageProviderFromUrlCached(su);
      }
    }
    final photoUrl = cfg.showPhoto
        ? await _resolvedMemberPhotoUrlForPdf(data.memberId, data.member,
            igrejaDocId: data.igrejaDocId)
        : '';
    final brandAccent = _hexToPdfColor(cfg.bgColor, PdfColors.blue800);
    final PdfColor bgColor;
    final PdfColor? bgColorSec;
    final PdfColor textColor;
    if (pdfInkEconomy) {
      bgColor = PdfColors.white;
      bgColorSec = null;
      textColor = PdfColors.grey900;
    } else {
      bgColor = _hexToPdfColor(cfg.bgColor, PdfColors.blue800);
      bgColorSec = cfg.bgColorSecondary != null
          ? _hexToPdfColor(cfg.bgColorSecondary!, PdfColors.blue900)
          : CarteirinhaVisualTokens.flutterColorToPdfColor(
              CarteirinhaVisualTokens.gradientEndFromPrimary(cfg.bgColorValue),
            );
      textColor = _hexToPdfColor(cfg.textColor, PdfColors.white);
    }
    final accentColor = brandAccent;
    final logo = await _pdfLogoProvider(cfg, data);
    pw.ImageProvider? photo;
    if (photoUrl.isNotEmpty) {
      photo = await _pdfImageProviderFromUrlCached(photoUrl);
    }
    final qr = _qrPayload(data.igrejaDocId, data.memberId);
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
      qr: qr,
      admissionLine: admissionLinePdf,
      cfg: cfg,
      bgColor: bgColor,
      bgColorSec: bgColorSec,
      textColor: textColor,
      accentColor: accentColor,
      logo: logo,
      photo: photo,
      showFrontQr: true,
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
      doc.addPage(
        pw.Page(
          pageFormat: format,
          build: (_) => pw.Center(child: face),
        ),
      );
      doc.addPage(
        pw.Page(
          pageFormat: format,
          build: (_) => pw.Center(child: versoSlot),
        ),
      );
      return;
    }
    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        build: (context) => pw.Center(
          child: pw.Column(
            mainAxisAlignment: pw.MainAxisAlignment.center,
            mainAxisSize: pw.MainAxisSize.min,
            children: [
              face,
              pw.SizedBox(height: 12),
              versoSlot,
            ],
          ),
        ),
      ),
    );
  }

  /// PDF com o **mesmo layout** da área “Carteira digital (Wallet)” na tela — captura
  /// [MemberDigitalWalletFront] + [MemberDigitalWalletBack] (logo [StableChurchLogo],
  /// foto [FotoMembroWidget]). Evita divergência do modelo só em PDF vetorial.
  Future<Uint8List> _buildPdfFromWalletScreenshot(BuildContext context) async {
    await Future<void>.delayed(const Duration(milliseconds: 80));
    await WidgetsBinding.instance.endOfFrame;
    if (!context.mounted) {
      throw StateError('Contexto inválido para exportar PDF.');
    }
    final pr = MediaQuery.devicePixelRatioOf(context).clamp(2.0, 4.0);
    final png = await _walletScreenshotController.capture(pixelRatio: pr);
    if (png == null || png.isEmpty) {
      throw StateError('Não foi possível capturar a carteirinha.');
    }
    final doc = await _newCarteirinhaPdfDoc();
    final img = pw.MemoryImage(png);
    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(20),
        build: (c) => pw.Center(
          child: pw.Image(img, fit: pw.BoxFit.contain),
        ),
      ),
    );
    return doc.save();
  }

  Future<Uint8List> _exportCarteirinhaPdfPreferringWalletModel(
    BuildContext context,
    _CardData data,
    PdfPageFormat format,
    _CardConfig cfg, {
    String? signatoryNome,
    String? signatoryCargo,
    String? signatoryAssinaturaUrl,
  }) async {
    try {
      return await _buildPdfFromWalletScreenshot(context);
    } catch (e, st) {
      debugPrint(
          'member_card: PDF raster (carteira na tela) indisponível, usando PDF vetorial: $e\n$st');
      return await _buildPdf(
        data,
        format,
        configOverride: cfg,
        signatoryNome: signatoryNome,
        signatoryCargo: signatoryCargo,
        signatoryAssinaturaUrl: signatoryAssinaturaUrl,
      );
    }
  }

  Future<void> _showGerarPdfComAssinatura(
      BuildContext context, _CardData data) async {
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
                                PdfPageFormat.a4,
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
          PdfPageFormat.a4,
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
            await _buildPdf(data, PdfPageFormat.a4, configOverride: cfg);
        if (context.mounted)
          await showPdfActions(context,
              bytes: bytes, filename: 'carteirinha_${data.memberId}.pdf');
      }
    }
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
  }) async {
    // Não limpar cache no início: [_gerarPdfUnicoLote] / assinatura em lote já rodaram
    // [preLoadImages] — limpar aqui obrigava a baixar logo/foto de novo (lento e falha na web).
    try {
      final doc = await _newCarteirinhaPdfDoc();
      pw.ImageProvider? signatoryImage;
      final sigUrl = (signatoryAssinaturaUrl ?? '').trim();
      if (sigUrl.isNotEmpty) {
        signatoryImage = await _pdfImageProviderFromUrlCached(sigUrl);
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

      const baseW = 360.0;
      final hasSig = (signatoryNome ?? '').trim().isNotEmpty;
      final baseH = hasSig ? 268.0 : 228.0;
      final slots = gridCols * gridRows;
      final multiCell = gridCols > 1 || gridRows > 1;
      final margin = (showCutGuides && multiCell) ? 22.0 : 18.0;
      final cellW = (format.width - margin * 2) / gridCols;
      final cellH = (format.height - margin * 2) / gridRows;
      final scale = min(cellW / baseW, cellH / baseH) * 0.92;

      for (var i = 0; i < list.length; i += slots) {
        final end = (i + slots > list.length) ? list.length : i + slots;
        final chunk = list.sublist(i, end);
        await Future.wait(chunk.map((d) async {
          final c0 = _cardConfigForPdf(d);
          if (!c0.showPhoto) return;
          final u = await _resolvedMemberPhotoUrlForPdf(d.memberId, d.member,
              igrejaDocId: d.igrejaDocId);
          if (u.isNotEmpty) await _pdfImageProviderFromUrlCached(u);
        }));

        final cells = <pw.Widget>[];

        for (var k = 0; k < slots; k++) {
          if (k < chunk.length) {
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
            final brandAccent =
                _hexToPdfColor(cfgRaw.bgColor, PdfColors.blue800);
            final PdfColor bgColor;
            final PdfColor? bgColorSec;
            final PdfColor textColor;
            if (inkEconomy) {
              bgColor = PdfColors.white;
              bgColorSec = null;
              textColor = PdfColors.grey900;
            } else {
              bgColor = _hexToPdfColor(cfg.bgColor, PdfColors.blue800);
              bgColorSec = cfg.bgColorSecondary != null
                  ? _hexToPdfColor(cfg.bgColorSecondary!, PdfColors.blue900)
                  : CarteirinhaVisualTokens.flutterColorToPdfColor(
                      CarteirinhaVisualTokens.gradientEndFromPrimary(
                          cfg.bgColorValue),
                    );
              textColor = _hexToPdfColor(cfg.textColor, PdfColors.white);
            }
            final accentColor = brandAccent;
            final logo = await _pdfLogoProvider(cfgRaw, data);
            pw.ImageProvider? photo;
            if (photoUrl.isNotEmpty) {
              photo = await _pdfImageProviderFromUrlCached(photoUrl);
            }
            final qr = _qrPayload(data.igrejaDocId, data.memberId);
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
              qr: qr,
              admissionLine: admissionLinePdf,
              cfg: cfg,
              bgColor: bgColor,
              bgColorSec: bgColorSec,
              textColor: textColor,
              accentColor: accentColor,
              logo: logo,
              photo: photo,
              showFrontQr: true,
              signatoryImage: signatoryImage,
              signatoryNome: signatoryNome,
              signatoryCargo: signatoryCargo,
            );
            cells.add(
              pw.Center(
                child: pw.Transform.scale(
                  alignment: pw.Alignment.center,
                  scale: scale,
                  child: face,
                ),
              ),
            );
          } else {
            cells.add(pw.SizedBox());
          }
        }

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

        final versoCells = <pw.Widget>[];
        const baseVersoW = VersoCarteirinhaPdfWidget.cardWidthPt;
        const baseVersoH = VersoCarteirinhaPdfWidget.cardHeightPt;
        final scaleV = min(cellW / baseVersoW, cellH / baseVersoH) * 0.92;

        for (var k = 0; k < slots; k++) {
          if (k < chunk.length) {
            final data = chunk[k];
            final cfgRaw = _cardConfigForPdf(data);
            pw.ImageProvider? sigIV = signatoryImage;
            if (sigIV == null) {
              final su = (data.member['carteirinhaAssinaturaUrl'] ?? '')
                  .toString()
                  .trim();
              if (su.isNotEmpty) {
                sigIV = await _pdfImageProviderFromUrlCached(su);
              }
            }
            versoCells.add(
              pw.Center(
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
              ),
            );
          } else {
            versoCells.add(pw.SizedBox());
          }
        }

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
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
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

      warm(memberPhoto);
      warm(signUrl);
      unawaited(() async {
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
      }());
    });
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
                      'PDF lote (${_carteiraListaSelecionados.length})',
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
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => Navigator.maybePop(context),
          tooltip: 'Voltar',
        ),
        title: const Text('Carteirinha digital',
            style: TextStyle(fontWeight: FontWeight.w700)),
        backgroundColor: ThemeCleanPremium.primary,
        foregroundColor: Colors.white,
        elevation: 0,
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
                  minimumSize: const Size(ThemeCleanPremium.minTouchTarget,
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
      body: SafeArea(
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
                            final hasMember = (widget.memberId != null &&
                                    widget.memberId!.trim().isNotEmpty) ||
                                (widget.cpf != null &&
                                    widget.cpf!
                                            .replaceAll(RegExp(r'[^0-9]'), '')
                                            .length >=
                                        11);
                            _loadFuture =
                                hasMember ? _load() : Future.value(null);
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
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.badge_rounded,
                            size: 64, color: Colors.grey.shade400),
                        const SizedBox(height: 16),
                        const Text(
                          'Minha Carteirinha',
                          style: TextStyle(
                              fontSize: 20, fontWeight: FontWeight.w700),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'Cadastro de membro não encontrado. Entre em contato com o gestor da igreja.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              fontSize: 15, color: Colors.grey.shade700),
                        ),
                        const SizedBox(height: 24),
                        FilledButton.icon(
                          onPressed: () =>
                              setState(() => _loadFuture = _load()),
                          icon: const Icon(Icons.refresh_rounded),
                          label: const Text('Tentar novamente'),
                        ),
                      ],
                    ),
                  ),
                );
              }
              return Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.badge_rounded,
                          size: 64, color: Colors.grey.shade400),
                      const SizedBox(height: 16),
                      const Text(
                        'Emissão de Carteirinha',
                        style: TextStyle(
                            fontSize: 20, fontWeight: FontWeight.w700),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Carteirinha digital: personalize cores, logo e modelo em “Configurar cor e logo”.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            fontSize: 13, color: Colors.grey.shade700),
                      ),
                      if (_canManage) ...[
                        const SizedBox(height: 12),
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
                        ),
                      ],
                      const SizedBox(height: 20),
                      Text(
                        'Selecione um membro abaixo para emitir a carteirinha ou use o botão para ir à lista completa.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            fontSize: 15, color: Colors.grey.shade700),
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        decoration: InputDecoration(
                          hintText: 'Buscar por nome ou CPF...',
                          prefixIcon:
                              const Icon(Icons.search_rounded, size: 22),
                          border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(
                                  ThemeCleanPremium.radiusMd)),
                          filled: true,
                          fillColor: Colors.white,
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 12),
                        ),
                        onChanged: (v) => setState(() => _memberSearch = v),
                      ),
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius:
                              BorderRadius.circular(ThemeCleanPremium.radiusMd),
                          boxShadow: ThemeCleanPremium.softUiCardShadow,
                          border: Border.all(color: const Color(0xFFF1F5F9)),
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
                                        color: Colors.grey.shade800)),
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
                          WidgetsBinding.instance.addPostFrameCallback((_) {
                            if (!context.mounted) return;
                            preloadNetworkImages(context, preloadUrls,
                                maxItems: 12);
                          });
                          if (filtered.isEmpty) {
                            return Padding(
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              child: Text(
                                all.isEmpty
                                    ? 'Nenhum membro cadastrado.'
                                    : 'Nenhum membro corresponde à busca e aos filtros.',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                    fontSize: 14, color: Colors.grey.shade600),
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
            final validade = _validityLabel(data.member);
            final qr = _qrPayload(data.igrejaDocId, data.memberId);
            _warmupCarteiraAssets(data, cfg);

            return Center(
              child: SingleChildScrollView(
                padding: EdgeInsets.symmetric(
                    horizontal: ThemeCleanPremium.spaceLg,
                    vertical: ThemeCleanPremium.spaceMd),
                child: Column(
                  children: [
                    Container(
                      width: 360,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 12),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius:
                            BorderRadius.circular(ThemeCleanPremium.radiusMd),
                        boxShadow: ThemeCleanPremium.softUiCardShadow,
                        border: Border.all(color: const Color(0xFFEAF0F7)),
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
                      child: FilledButton.icon(
                        onPressed: () async =>
                            _showGerarPdfComAssinatura(context, data),
                        icon: const Icon(Icons.picture_as_pdf_rounded),
                        label: const Text('Exportar PDF'),
                        style: FilledButton.styleFrom(
                          backgroundColor: ThemeCleanPremium.primary,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 24, vertical: 14),
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
                      'O PDF “Exportar PDF” usa esta mesma carteira (captura de ecrã): vidro (glass), borda dourada e QR no verso. '
                      'Cores em Configurar carteirinha. '
                      'Assinatura: Configurar carteirinha ou `igrejas/{id}/configuracoes/assinatura.png`.',
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
                        final sigUrl = memberSig.isNotEmpty
                            ? memberSig
                            : (snapPastor.data ?? '').trim();
                        final wCard = min(
                          360.0,
                          MediaQuery.sizeOf(context).width -
                              ThemeCleanPremium.spaceLg * 2,
                        ).clamp(280.0, 360.0);
                        final colorA = cfg.bgColorValue;
                        final colorB = cfg.bgColorSecondaryValue ??
                            CarteirinhaVisualTokens.gradientEndFromPrimary(
                                colorA);
                        final accentGold =
                            CarteirinhaVisualTokens.accentGoldFlutter;
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
                                imageUrl: cfg.logoUrl.trim().isNotEmpty
                                    ? cfg.logoUrl.trim()
                                    : null,
                                width: 44,
                                height: 44,
                                fit: BoxFit.contain,
                                memCacheWidth: 88,
                                memCacheHeight: 88,
                              );
                        final photoSlot = FotoMembroWidget(
                          imageUrl:
                              photoUrlPreview.isEmpty ? null : photoUrlPreview,
                          tenantId: data.igrejaDocId,
                          memberId: data.memberId,
                          cpfDigits:
                              cpfDigits.length == 11 ? cpfDigits : null,
                          memberData: data.member,
                          authUid: _memberAuthUidForCarteiraFoto(data.member),
                          size: 72,
                        );
                        final cpfFmt = _formatCpfForCard(cpf);
                        final filiacaoTxt =
                            walletFiliacaoFromMember(data.member);
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
                                      ),
                                      const SizedBox(height: 14),
                                      Text(
                                        'VERSO — validação & dados',
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w700,
                                          color: Colors.blueGrey.shade700,
                                          letterSpacing: 0.3,
                                        ),
                                      ),
                                      const SizedBox(height: 8),
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
                                        filiacaoPaiMae: filiacaoTxt.isEmpty
                                            ? '—'
                                            : filiacaoTxt,
                                        validade: validade.isEmpty
                                            ? '—'
                                            : validade,
                                        validationUrl: qr,
                                        signatureImageUrl:
                                            sigUrl.isEmpty ? null : sigUrl,
                                        signatoryName: (data.member[
                                                    'carteirinhaAssinadaPorNome'] ??
                                                '')
                                            .toString(),
                                        signatoryCargo: (data.member[
                                                    'carteirinhaAssinadaPorCargo'] ??
                                                '')
                                            .toString(),
                                        congregacao:
                                            _congregacaoFromMember(data.member),
                                        fraseRodape: cfg.fraseRodape,
                                      ),
                                    ],
                                  ),
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
      subject: 'Carteira digital — Gestão YAHWEH',
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
    final link =
        CarteirinhaConsultaUrl.validationUrl(widget.tenantId, data.memberId);
    final church =
        cfg.title.trim().isEmpty ? 'sua igreja' : cfg.title.trim();
    final caption =
        'Carteirinha digital — $church\nValidade: $validade\nConsulta: $link';
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
          text: caption,
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
      await Share.share(caption, subject: 'Carteirinha — $church');
      return;
    }
    final text = Uri.encodeComponent(
      'Olá! Sua carteirinha digital ($church).\n$caption',
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
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 14, color: fg),
          const SizedBox(width: 5),
          Text(
            label,
            style:
                TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: fg),
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
  final Widget? placeholder;
  final Widget? errorWidget;

  const _CarteiraLogoImage({
    required this.imageUrl,
    required this.width,
    required this.height,
    this.fit = BoxFit.contain,
    this.placeholder,
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
          placeholder: widget.placeholder,
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
      tenant = tenantSnap.data() ?? {};
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
