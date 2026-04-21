import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'dart:ui' show ImageByteFormat;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:image_picker/image_picker.dart';
import 'package:gestao_yahweh/core/app_constants.dart';
import 'package:gestao_yahweh/core/church_role_extensions.dart';
import 'package:gestao_yahweh/core/member_photo_storage_naming.dart';
import 'package:gestao_yahweh/core/roles_permissions.dart';
import 'package:gestao_yahweh/core/services/app_storage_image_service.dart';
import 'package:gestao_yahweh/ui/widgets/foto_membro_widget.dart';
import 'package:gestao_yahweh/ui/widgets/safe_member_profile_photo.dart'
    show memberPhotoDisplayCacheRevision;
import 'package:gestao_yahweh/ui/widgets/safe_network_image.dart'
    show
        ResilientNetworkImage,
        imageUrlFromMap,
        isValidImageUrl,
        sanitizeImageUrl,
        preloadNetworkImages;
import 'package:gestao_yahweh/services/firebase_storage_cleanup_service.dart';
import 'package:gestao_yahweh/services/firebase_storage_service.dart';
import 'package:gestao_yahweh/services/department_member_integration_service.dart';
import 'package:gestao_yahweh/services/media_upload_service.dart';
import 'package:gestao_yahweh/services/image_helper.dart';
import 'package:gestao_yahweh/ui/widgets/member_avatar_utils.dart'
    show avatarColorForMember;
import 'package:gestao_yahweh/ui/widgets/member_demographics_utils.dart';
import 'package:gestao_yahweh/core/global_upload_progress.dart';
import 'package:gestao_yahweh/services/high_res_image_pipeline.dart'
    show bytesLookLikeWebp;
import 'package:gestao_yahweh/services/media_handler_service.dart';
import 'package:gestao_yahweh/services/members_limit_service.dart';
import 'package:gestao_yahweh/ui/theme_clean_premium.dart';
import 'package:gestao_yahweh/utils/pdf_actions_helper.dart';
import 'package:gestao_yahweh/utils/pdf_super_premium_theme.dart';
import 'package:gestao_yahweh/utils/pdf_text_sanitize.dart';
import 'package:gestao_yahweh/utils/report_pdf_branding.dart';
import 'package:gestao_yahweh/utils/church_department_list.dart'
    show churchDepartmentNameFromDoc;
import 'package:gestao_yahweh/utils/member_signature_eligibility.dart';
import 'package:gestao_yahweh/ui/pages/plans/renew_plan_page.dart';
import 'package:gestao_yahweh/ui/widgets/skeleton_loader.dart';
import 'package:shimmer/shimmer.dart';
import 'package:gestao_yahweh/ui/widgets/church_panel_ui_helpers.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../services/app_permissions.dart';
import '../../services/church_funcoes_controle_service.dart';
import '../../services/tenant_resolver_service.dart';
import 'package:gestao_yahweh/services/cep_service.dart';
import 'igreja_cadastro_page.dart';
import 'member_card_page.dart';
import 'change_password_page.dart';
import 'public_member_signup_page.dart';
import 'internal_new_member_page.dart';
import 'aprovar_membros_pendentes_page.dart';
import 'funcoes_permissoes_page.dart';
import 'relatorios_page.dart' show openRelatorioMembrosAvancado;

class MembersPage extends StatefulWidget {
  final String tenantId;
  final String role;
  final Map<String, dynamic>? subscription;

  /// CPF do usuário logado (apenas dígitos ou formatado) — reconhece ficha em `membros/{cpf}` como "próprio".
  final String? linkedCpf;

  /// Filtro inicial ao abrir: 'todos' | 'masculino' | 'feminino'
  final String? initialFiltroGenero;

  /// Filtro inicial ao abrir: 'todas' | 'criancas' | 'adolescentes' | 'adultos' | 'idosos'
  final String? initialFiltroFaixaEtaria;

  /// Dentro de [IgrejaCleanShell]: sem AppBar duplicada; ações em barra compacta.
  final bool embeddedInShell;

  /// Pré-preenche o campo de busca (ex.: busca global Ctrl+K).
  final String? initialSearchQuery;

  /// Abre a ficha (bottom sheet) deste membro uma vez ao carregar (ex.: QR carteirinha → painel).
  final String? initialOpenMemberDocId;

  const MembersPage({
    super.key,
    required this.tenantId,
    required this.role,
    this.subscription,
    this.linkedCpf,
    this.initialFiltroGenero,
    this.initialFiltroFaixaEtaria,
    this.embeddedInShell = false,
    this.initialSearchQuery,
    this.initialOpenMemberDocId,
  });

  @override
  State<MembersPage> createState() => _MembersPageState();
}

class _DeptItem {
  final String id;
  final String name;
  const _DeptItem({required this.id, required this.name});
}

class _MemberDoc {
  final String id;
  final Map<String, dynamic> data;
  _MemberDoc(this.id, this.data);
  static _MemberDoc fromQueryDoc(
          QueryDocumentSnapshot<Map<String, dynamic>> d) =>
      _MemberDoc(d.id, d.data());
  static _MemberDoc fromUserDoc(QueryDocumentSnapshot<Map<String, dynamic>> d) {
    final raw = d.data();
    final data = Map<String, dynamic>.from(raw);
    final active = raw['active'] ?? raw['ativo'];
    if (data['STATUS'] == null && data['status'] == null && active != null) {
      data['status'] =
          (active == true || active == 'true') ? 'ativo' : 'inativo';
    }
    return _MemberDoc(d.id, data);
  }
}

class _MembersPageState extends State<MembersPage> {
  String _q = '';
  Timer? _searchDebounce;
  late final TextEditingController _searchCtrl;
  final ScrollController _membersScrollController = ScrollController();
  bool _didBootstrapOpenMemberSheet = false;
  bool _linkCardExpanded = false;

  /// Legado (acordeões removidos — mantido para não quebrar saves de estado).
  bool _filtrosExpanded = false;
  bool _buscaRapidosExpanded = false;
  bool _funcoesPermExpanded = false;

  /// 0 = lista + filtros; 1 = painel estatístico (gráficos e números).
  int _membersMainTabIndex = 0;

  /// Tenant ID efetivo (documento em tenants): resolvido por slug/alias quando o usuário tem igreja "Brasil para Cristo" etc.
  String? _resolvedTenantId;

  /// Cache da ligação igreja (alias/slug) para incluir em toda escrita de membro.
  Map<String, String>? _tenantLinkageCache;

  String get _effectiveTenantId => _resolvedTenantId ?? widget.tenantId;

  /// Usa o serviço centralizado para garantir mesmo path que AuthGate, dashboard e import/export.
  Future<String> _resolveEffectiveTenantId() async =>
      TenantResolverService.resolveEffectiveTenantId(widget.tenantId);

  void _invalidateMemberPhotoCaches(
    String tenantId,
    String memberId, [
    Map<String, dynamic>? memberData,
  ]) {
    final t = tenantId.trim();
    final m = memberId.trim();
    if (t.isEmpty || m.isEmpty) return;
    final au = (memberData?['authUid'] ?? '').toString().trim();
    FirebaseStorageService.invalidateMemberPhotoCache(
      tenantId: t,
      memberId: m,
      authUid: au.isEmpty ? null : au,
    );
    AppStorageImageService.instance
        .invalidateStoragePrefix('igrejas/$t/membros/$m');
    final d = memberData;
    if (d != null) {
      final nome =
          (d['NOME_COMPLETO'] ?? d['nome'] ?? d['name'] ?? '').toString();
      final auth = (d['authUid'] ?? '').toString().trim();
      final stem = MemberPhotoStorageNaming.profileFolderStem(
        nomeCompleto: nome,
        memberDocId: m,
        authUid: auth.isEmpty ? null : auth,
      );
      AppStorageImageService.instance
          .invalidateStoragePrefix('igrejas/$t/membros/$stem');
    }
  }

  /// Retorna alias e slug da igreja para amarrar o membro ao tenant (segurança entre igrejas).
  Future<Map<String, String>> _getTenantLinkage() async {
    if (_tenantLinkageCache != null) return _tenantLinkageCache!;
    final snap = await FirebaseFirestore.instance
        .collection('igrejas')
        .doc(_effectiveTenantId)
        .get();
    final d = snap.data();
    final id = snap.id;
    final alias = (d?['alias'] ?? d?['slug'] ?? id).toString().trim();
    final slug = (d?['slug'] ?? d?['alias'] ?? id).toString().trim();
    _tenantLinkageCache = {
      'alias': alias.isEmpty ? id : alias,
      'slug': slug.isEmpty ? id : slug
    };
    return _tenantLinkageCache!;
  }

  /// Retorna alias e slug de um tenant qualquer (ex.: ao mover membro para outra igreja).
  static Future<Map<String, String>> _getLinkageForTenant(
      String tenantId) async {
    final snap = await FirebaseFirestore.instance
        .collection('igrejas')
        .doc(tenantId)
        .get();
    final d = snap.data();
    final id = snap.id;
    final alias = (d?['alias'] ?? d?['slug'] ?? id).toString().trim();
    final slug = (d?['slug'] ?? d?['alias'] ?? id).toString().trim();
    return {
      'alias': alias.isEmpty ? id : alias,
      'slug': slug.isEmpty ? id : slug
    };
  }

  /// True se o usuário pode transferir membro para outra igreja (ADM total do sistema: MASTER, ADMIN, ADM ou raihom@gmail.com).
  bool get _canTransferMember {
    final r = (widget.role ?? '').toString().toUpperCase();
    if (r == 'MASTER' || r == 'ADMIN' || r == 'ADM') return true;
    final email =
        FirebaseAuth.instance.currentUser?.email?.trim().toLowerCase() ?? '';
    return email == 'raihom@gmail.com';
  }

  /// Carrega lista de igrejas (tenants) para o painel master (mudar igreja do membro).
  static Future<List<MapEntry<String, String>>> _loadTenantsForMove() async {
    final snap = await FirebaseFirestore.instance.collection('igrejas').get();
    final list = snap.docs.map((d) {
      final data = d.data();
      final name = (data['name'] ?? data['nome'] ?? d.id).toString();
      return MapEntry(d.id, name);
    }).toList();
    list.sort((a, b) => a.value.toLowerCase().compareTo(b.value.toLowerCase()));
    return list;
  }

  /// IDs de documento Firestore (`igrejas/{id}`) para um tenant, incluindo alias/slug duplicados.
  Future<Set<String>> _resolvedFirestoreTenantIds(String tenantKey) async {
    final t = tenantKey.trim();
    if (t.isEmpty) return {};
    final ids =
        await TenantResolverService.getAllTenantIdsWithSameSlugOrAlias(t);
    if (ids.isEmpty) return {t};
    return ids.toSet();
  }

  String _filtroGenero = 'todos'; // todos, masculino, feminino
  String _filtroDepartamento = 'todos';
  String _filtroStatus = 'todos'; // todos, ativos, inativos
  String _filtroFaixaEtaria =
      'todas'; // todas, criancas, adolescentes, adultos, idosos
  String _filtroDiaCadastro = 'todos'; // todos, hoje, semana, mes
  int? _filtroAniversarioMes; // null = todos, 1-12 = mês
  /// Seleção em massa no filtro "Pendentes" (aprovar vários).
  Set<String> _selectedPendingIds = {};
  List<_DeptItem> _departamentos = [];
  final MembersLimitService _limitService = MembersLimitService();
  late final Future<MembersLimitResult> _limitFuture;
  late final Future<void> _deptsFuture;

  /// Uma única leitura pontual (.get()) para evitar INTERNAL ASSERTION FAILED (web/mobile).
  late Future<List<QuerySnapshot<Map<String, dynamic>>>> _membersDataFuture;
  final List<StreamSubscription<dynamic>> _membersRealtimeSubs = [];
  Timer? _membersRealtimeDebounce;
  String _membersRealtimeTenant = '';

  /// UI otimista: some da lista após confirmar exclusão (reverte se falhar).
  final Set<String> _optimisticRemovedMemberIds = <String>{};

  /// Campos mesclados na lista ao fechar o diálogo de edição (Firestore em background).
  final Map<String, Map<String, dynamic>> _optimisticMemberOverlays =
      <String, Map<String, dynamic>>{};

  /// Foto recém-enviada por membro — cobre atraso do servidor e merge que mantinha URL antiga (ex.: Google).
  final Map<String, String> _uploadedPhotoUrls = {};

  /// Bytes JPEG/WebP já comprimidos — mostra a foto na lista antes do upload concluir.
  final Map<String, Uint8List> _optimisticProfilePhotoBytes = {};
  static const int _membersPageSize = 20;
  int _membersVisibleCount = _membersPageSize;

  static int? _parseIdade(dynamic raw) {
    if (raw == null) return null;
    DateTime? dt;
    if (raw is Timestamp)
      dt = raw.toDate();
    else if (raw is Map) {
      final sec = raw['seconds'] ?? raw['_seconds'];
      if (sec != null)
        dt = DateTime.fromMillisecondsSinceEpoch((sec as num).toInt() * 1000);
    }
    if (dt == null) return null;
    final now = DateTime.now();
    int age = now.year - dt.year;
    if (now.month < dt.month || (now.month == dt.month && now.day < dt.day))
      age--;
    return age;
  }

  /// [applySearch] false = painel estatístico ignora a caixa de busca (lista continua a usar).
  List<_MemberDoc> _aplicarFiltros(List<_MemberDoc> docs,
      {bool applySearch = true}) {
    var out = docs;
    if (applySearch && _q.isNotEmpty) {
      final qDigits = _q.replaceAll(RegExp(r'\D'), '');
      out = out.where((d) {
        final m = d.data;
        final name = (m['NOME_COMPLETO'] ?? m['nome'] ?? m['name'] ?? '')
            .toString()
            .toLowerCase();
        final email = (m['EMAIL'] ?? m['email'] ?? '').toString().toLowerCase();
        final cpf = (m['CPF'] ?? m['cpf'] ?? '').toString().toLowerCase();
        final phoneRaw = (m['TELEFONES'] ??
                m['TELEFONE'] ??
                m['telefone'] ??
                m['phone'] ??
                '')
            .toString();
        final phone = phoneRaw.toLowerCase().replaceAll(RegExp(r'\D'), '');
        if (name.contains(_q) || email.contains(_q) || cpf.contains(_q)) {
          return true;
        }
        if (phoneRaw.toLowerCase().contains(_q)) return true;
        if (qDigits.length >= 3 && phone.contains(qDigits)) return true;
        final cargo = (m['CARGO'] ??
                m['FUNCAO'] ??
                m['role'] ??
                m['FUNCAO_PERMISSOES'] ??
                '')
            .toString()
            .toLowerCase();
        if (cargo.contains(_q)) return true;
        final funcoes = m['FUNCOES'] ?? m['funcoes'];
        if (funcoes is List) {
          for (final e in funcoes) {
            if (e.toString().toLowerCase().contains(_q)) return true;
          }
        }
        return false;
      }).toList();
    }
    if (_filtroStatus != 'todos') {
      out = out.where((m) {
        final s = (m.data['STATUS'] ?? m.data['status'] ?? '')
            .toString()
            .toLowerCase();
        final pending = s.contains('pendente');
        final inativo = s.contains('inativ');
        switch (_filtroStatus) {
          case 'pendentes':
            return pending;
          case 'ativos':
            return !inativo && !pending;
          case 'inativos':
            return inativo;
          default:
            return true;
        }
      }).toList();
    }
    if (_filtroGenero != 'todos') {
      out = out.where((m) {
        final g = genderCategoryFromMemberData(m.data);
        return _filtroGenero == 'masculino' ? g == 'M' : g == 'F';
      }).toList();
    }
    if (_filtroDepartamento != 'todos') {
      out = out.where((m) {
        final depts = m.data['DEPARTAMENTOS'] ?? m.data['departamentos'];
        if (depts is List)
          return depts.any((x) => x.toString() == _filtroDepartamento);
        final d =
            (m.data['departamento'] ?? m.data['DEPARTAMENTO'] ?? '').toString();
        return d == _filtroDepartamento ||
            _departamentos
                .any((e) => e.id == _filtroDepartamento && e.name == d);
      }).toList();
    }
    if (_filtroFaixaEtaria != 'todas') {
      out = out.where((m) {
        final idade = ageFromMemberData(m.data);
        if (idade == null) return false;
        switch (_filtroFaixaEtaria) {
          case 'criancas':
            return idade < 13;
          case 'adolescentes':
            return idade >= 13 && idade < 18;
          case 'adultos':
            return idade >= 18 && idade < 60;
          case 'idosos':
            return idade >= 60;
          default:
            return true;
        }
      }).toList();
    }
    if (_filtroDiaCadastro != 'todos') {
      final now = DateTime.now();
      out = out.where((m) {
        final dt = _parseDate(m.data['CRIADO_EM'] ?? m.data['createdAt']);
        if (dt == null) return false;
        switch (_filtroDiaCadastro) {
          case 'hoje':
            return dt.year == now.year &&
                dt.month == now.month &&
                dt.day == now.day;
          case 'semana':
            return dt.isAfter(now.subtract(const Duration(days: 7)));
          case 'mes':
            return dt.year == now.year && dt.month == now.month;
          default:
            return true;
        }
      }).toList();
    }
    if (_filtroAniversarioMes != null) {
      out = out.where((m) {
        final dt = birthDateFromMemberData(m.data) ??
            _parseDate(m.data['DATA_NASCIMENTO'] ??
                m.data['dataNascimento'] ??
                m.data['birthDate']);
        return dt != null && dt.month == _filtroAniversarioMes;
      }).toList();
    }
    // Ordem alfabética sempre (por nome completo)
    out.sort((a, b) {
      final na =
          (a.data['NOME_COMPLETO'] ?? a.data['nome'] ?? a.data['name'] ?? '')
              .toString()
              .trim()
              .toLowerCase();
      final nb =
          (b.data['NOME_COMPLETO'] ?? b.data['nome'] ?? b.data['name'] ?? '')
              .toString()
              .trim()
              .toLowerCase();
      return na.compareTo(nb);
    });
    return out;
  }

  /// Quantidade de filtros avançados diferentes do padrão (badge na seção).
  int get _advancedFiltersActiveCount {
    var n = 0;
    if (_filtroGenero != 'todos') n++;
    if (_filtroFaixaEtaria != 'todas') n++;
    if (_filtroDiaCadastro != 'todos') n++;
    if (_filtroDepartamento != 'todos') n++;
    if (_filtroAniversarioMes != null) n++;
    return n;
  }

  @override
  void initState() {
    super.initState();
    _searchCtrl = TextEditingController();
    if (widget.initialSearchQuery != null &&
        widget.initialSearchQuery!.trim().isNotEmpty) {
      final s = widget.initialSearchQuery!.trim();
      _searchCtrl.text = s;
      _q = s.toLowerCase();
    }
    if (widget.initialFiltroGenero != null &&
        widget.initialFiltroGenero!.isNotEmpty) {
      _filtroGenero = widget.initialFiltroGenero!;
    }
    if (widget.initialFiltroFaixaEtaria != null &&
        widget.initialFiltroFaixaEtaria!.isNotEmpty) {
      _filtroFaixaEtaria = widget.initialFiltroFaixaEtaria!;
    }
    FirebaseAuth.instance.currentUser?.getIdToken(true);
    _limitFuture = _limitService.checkLimit(
      widget.tenantId,
      planIdOverride:
          (widget.subscription?['planId'] ?? '').toString().trim().isEmpty
              ? null
              : (widget.subscription?['planId'] ?? '').toString().trim(),
    );
    _membersDataFuture = _loadMembersData();
    _deptsFuture = _loadDeptsForFilter();
    // Resolve tenant o mais cedo possível para que _effectiveTenantId esteja correto em ações (add/edit).
    _resolveEffectiveTenantId().then((resolved) {
      if (mounted && _resolvedTenantId != resolved) {
        setState(() => _resolvedTenantId = resolved);
      }
      _startMembersRealtimeWatch(resolved.isNotEmpty ? resolved : widget.tenantId);
    });
  }

  @override
  void didUpdateWidget(MembersPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.tenantId != widget.tenantId) {
      _resolvedTenantId = null;
      _filtroStatus = 'todos';
      _filtroGenero = 'todos';
      _filtroFaixaEtaria = 'todas';
      _filtroDiaCadastro = 'todos';
      _filtroDepartamento = 'todos';
      _filtroAniversarioMes = null;
      _q = '';
      _searchCtrl.clear();
      _limitFuture = _limitService.checkLimit(
        widget.tenantId,
        planIdOverride:
            (widget.subscription?['planId'] ?? '').toString().trim().isEmpty
                ? null
                : (widget.subscription?['planId'] ?? '').toString().trim(),
      );
      _membersDataFuture = _loadMembersData();
      _deptsFuture = _loadDeptsForFilter();
      _resolveEffectiveTenantId().then((resolved) {
        if (mounted && _resolvedTenantId != resolved) {
          setState(() => _resolvedTenantId = resolved);
        }
        _startMembersRealtimeWatch(
            resolved.isNotEmpty ? resolved : widget.tenantId);
      });
    }
  }

  @override
  void dispose() {
    _membersRealtimeDebounce?.cancel();
    for (final sub in _membersRealtimeSubs) {
      sub.cancel();
    }
    _searchDebounce?.cancel();
    _searchCtrl.dispose();
    _membersScrollController.dispose();
    super.dispose();
  }

  void _scheduleMembersAutoRefresh() {
    _membersRealtimeDebounce?.cancel();
    _membersRealtimeDebounce = Timer(const Duration(milliseconds: 650), () {
      if (!mounted) return;
      _refreshMembers();
    });
  }

  void _startMembersRealtimeWatch(String tenantIdRaw) {
    final tenantId = tenantIdRaw.trim();
    if (tenantId.isEmpty) return;
    if (_membersRealtimeTenant == tenantId && _membersRealtimeSubs.isNotEmpty) {
      return;
    }
    for (final sub in _membersRealtimeSubs) {
      sub.cancel();
    }
    _membersRealtimeSubs.clear();
    _membersRealtimeTenant = tenantId;
    final db = FirebaseFirestore.instance;
    _membersRealtimeSubs.add(
      db
          .collection('igrejas')
          .doc(tenantId)
          .collection('membros')
          .limit(_membersLoadLimit)
          .snapshots()
          .listen((_) => _scheduleMembersAutoRefresh()),
    );
    _membersRealtimeSubs.add(
      db
          .collection('users')
          .where('tenantId', isEqualTo: tenantId)
          .limit(_membersLoadLimit)
          .snapshots()
          .listen((_) => _scheduleMembersAutoRefresh()),
    );
    _membersRealtimeSubs.add(
      db
          .collection('users')
          .where('igrejaId', isEqualTo: tenantId)
          .limit(_membersLoadLimit)
          .snapshots()
          .listen((_) => _scheduleMembersAutoRefresh()),
    );
  }

  Future<void> _loadDeptsForFilter() async {
    final depts = await _loadDepartments();
    if (mounted) setState(() => _departamentos = depts);
  }

  static const int _membersLoadLimit = 400;

  /// [forceServer] true ao recarregar após salvar/upload — evita cache e garante foto atualizada na lista.
  Future<List<QuerySnapshot<Map<String, dynamic>>>> _loadMembersData(
      {bool forceServer = false}) async {
    if (forceServer) {
      await FirebaseAuth.instance.currentUser?.getIdToken(true);
    }
    final resolved = await _resolveEffectiveTenantId();
    if (mounted) setState(() => _resolvedTenantId = resolved);
    final tenantId = resolved.isNotEmpty ? resolved : widget.tenantId;
    final originalId = widget.tenantId.trim();
    if (tenantId.isEmpty && originalId.isEmpty) {
      return Future.value(List<QuerySnapshot<Map<String, dynamic>>>.filled(
          7, _EmptyQuerySnapshot()));
    }
    final effectiveId = tenantId.isNotEmpty ? tenantId : originalId;

    final getOpts =
        GetOptions(source: forceServer ? Source.server : Source.serverAndCache);

    // Documentos igrejas/* ligados (slug/alias/_sistema/_bpc) — uma resolução, sem varrer 2× a coleção.
    final relatedIgrejaDocIds =
        await TenantResolverService.getAllRelatedIgrejaDocIds(effectiveId);
    final db = FirebaseFirestore.instance;

    // Padrão: igrejas/{id}/membros; também 'members' (legado). Leituras iniciais em paralelo (sem repetir a mesma query 4×).
    final membrosFuture = db
        .collection('igrejas')
        .doc(effectiveId)
        .collection('membros')
        .limit(_membersLoadLimit)
        .get(getOpts);
    final membersLegacyFuture = db
        .collection('igrejas')
        .doc(effectiveId)
        .collection('members')
        .limit(_membersLoadLimit)
        .get(getOpts);
    final usersTFuture = db
        .collection('users')
        .where('tenantId', isEqualTo: effectiveId)
        .limit(_membersLoadLimit)
        .get(getOpts);
    final usersIFuture = db
        .collection('users')
        .where('igrejaId', isEqualTo: effectiveId)
        .limit(_membersLoadLimit)
        .get(getOpts);
    final pendenteFuture = db
        .collection('igrejas')
        .doc(effectiveId)
        .collection('membros')
        .where('status', isEqualTo: 'pendente')
        .limit(500)
        .get(getOpts);

    final initial = await Future.wait<QuerySnapshot<Map<String, dynamic>>>([
      membrosFuture,
      membersLegacyFuture,
      usersTFuture,
      usersIFuture,
      pendenteFuture,
    ]);

    final membrosSnap = initial[0];
    final legacySnap = initial[1];
    final usersTSnap = initial[2];
    final usersISnap = initial[3];
    final pendenteSnap = initial[4];

    final mergedMembers = <QueryDocumentSnapshot<Map<String, dynamic>>>[
      ...membrosSnap.docs
    ];
    final mergedMembros = <QueryDocumentSnapshot<Map<String, dynamic>>>[
      ...membrosSnap.docs
    ];
    final mergedIgrejasMembers = <QueryDocumentSnapshot<Map<String, dynamic>>>[
      ...membrosSnap.docs
    ];
    final mergedIgrejasMembros = <QueryDocumentSnapshot<Map<String, dynamic>>>[
      ...membrosSnap.docs
    ];
    final seenMemberIds = <String>{...membrosSnap.docs.map((d) => d.id)};
    final seenIgrejasIds = <String>{...membrosSnap.docs.map((d) => d.id)};
    for (final d in legacySnap.docs) {
      if (seenMemberIds.add(d.id)) {
        mergedMembers.add(d);
        mergedMembros.add(d);
      }
      if (seenIgrejasIds.add(d.id)) {
        mergedIgrejasMembers.add(d);
        mergedIgrejasMembros.add(d);
      }
    }

    final allIdsToQuery = <String>{...relatedIgrejaDocIds};
    if (originalId.isNotEmpty) allIdsToQuery.add(originalId);

    final otherIds = allIdsToQuery.where((id) => id != effectiveId).toList();
    if (otherIds.isNotEmpty) {
      final extraPairs = await Future.wait(otherIds.map((id) async {
        try {
          final pair = await Future.wait<QuerySnapshot<Map<String, dynamic>>>([
            db
                .collection('igrejas')
                .doc(id)
                .collection('membros')
                .limit(_membersLoadLimit)
                .get(getOpts),
            db
                .collection('igrejas')
                .doc(id)
                .collection('members')
                .limit(_membersLoadLimit)
                .get(getOpts),
          ]);
          return (pair[0], pair[1]);
        } catch (_) {
          return null;
        }
      }));
      for (final p in extraPairs) {
        if (p == null) continue;
        final snap = p.$1;
        final legacy = p.$2;
        for (final d in snap.docs) {
          if (seenMemberIds.add(d.id)) {
            mergedMembers.add(d);
            mergedMembros.add(d);
          }
          if (seenIgrejasIds.add(d.id)) {
            mergedIgrejasMembers.add(d);
            mergedIgrejasMembros.add(d);
          }
        }
        for (final d in legacy.docs) {
          if (seenMemberIds.add(d.id)) {
            mergedMembers.add(d);
            mergedMembros.add(d);
          }
          if (seenIgrejasIds.add(d.id)) {
            mergedIgrejasMembers.add(d);
            mergedIgrejasMembros.add(d);
          }
        }
      }
    }

    // Usuários (users) com tenantId/igrejaId em qualquer um dos IDs — membros podem estar em users
    final allIdsForUsers = allIdsToQuery;
    final mergedUsersT = <QueryDocumentSnapshot<Map<String, dynamic>>>[
      ...usersTSnap.docs
    ];
    final mergedUsersI = <QueryDocumentSnapshot<Map<String, dynamic>>>[
      ...usersISnap.docs
    ];
    final seenUserIds = <String>{
      ...usersTSnap.docs.map((d) => d.id),
      ...usersISnap.docs.map((d) => d.id)
    };
    final otherUserIds =
        allIdsForUsers.where((id) => id != effectiveId).toList();
    if (otherUserIds.isNotEmpty) {
      final userPairs = await Future.wait(otherUserIds.map((id) async {
        try {
          final pair = await Future.wait<QuerySnapshot<Map<String, dynamic>>>([
            db
                .collection('users')
                .where('tenantId', isEqualTo: id)
                .limit(_membersLoadLimit)
                .get(getOpts),
            db
                .collection('users')
                .where('igrejaId', isEqualTo: id)
                .limit(_membersLoadLimit)
                .get(getOpts),
          ]);
          return (pair[0], pair[1]);
        } catch (_) {
          return null;
        }
      }));
      for (final p in userPairs) {
        if (p == null) continue;
        for (final d in p.$1.docs) {
          if (seenUserIds.add(d.id)) mergedUsersT.add(d);
        }
        for (final d in p.$2.docs) {
          if (seenUserIds.add(d.id)) mergedUsersI.add(d);
        }
      }
    }

    final selfOnlyMemberList = AppPermissions.isRestrictedMember(widget.role) &&
        !AppPermissions.canEditAnyChurchMember(widget.role);
    QuerySnapshot<Map<String, dynamic>> pendenteOut = pendenteSnap;
    if (selfOnlyMemberList) {
      bool keepSelf(QueryDocumentSnapshot<Map<String, dynamic>> d) {
        final uid = FirebaseAuth.instance.currentUser?.uid;
        if (uid == null) return false;
        if (d.id == uid) return true;
        final data = d.data();
        final authUid = (data['authUid'] ?? '').toString().trim();
        if (authUid.isNotEmpty && authUid == uid) return true;
        final cpfDigits =
            (widget.linkedCpf ?? '').replaceAll(RegExp(r'\D'), '');
        if (cpfDigits.length == 11) {
          final idDigits = d.id.replaceAll(RegExp(r'\D'), '');
          if (idDigits == cpfDigits) return true;
          final cpfDoc = (data['CPF'] ?? data['cpf'] ?? '')
              .toString()
              .replaceAll(RegExp(r'\D'), '');
          if (cpfDoc.length == 11 && cpfDoc == cpfDigits) return true;
        }
        return false;
      }

      mergedMembers.retainWhere(keepSelf);
      mergedMembros.retainWhere(keepSelf);
      mergedIgrejasMembers.retainWhere(keepSelf);
      mergedIgrejasMembros.retainWhere(keepSelf);
      final cu = FirebaseAuth.instance.currentUser?.uid;
      if (cu != null) {
        mergedUsersT.retainWhere((d) => d.id == cu);
        mergedUsersI.retainWhere((d) => d.id == cu);
      } else {
        mergedUsersT.clear();
        mergedUsersI.clear();
      }
      pendenteOut =
          _MergedQuerySnapshot(pendenteSnap.docs.where(keepSelf).toList());
    }

    return [
      _MergedQuerySnapshot(mergedMembers),
      _MergedQuerySnapshot(mergedMembros),
      _MergedQuerySnapshot(mergedIgrejasMembers),
      _MergedQuerySnapshot(mergedIgrejasMembros),
      _MergedQuerySnapshot(mergedUsersT),
      _MergedQuerySnapshot(mergedUsersI),
      pendenteOut,
    ];
  }

  /// Abre a lista em rota fullscreen (root) com botão Voltar aos filtros — melhor no telemóvel.
  void _recolherFiltrosMembros(
      MembersLimitResult? limitResult, bool addBlocked) {
    _openMembersFullscreenList(limitResult, addBlocked);
  }

  Future<void> _showAdvancedFiltersSheet(EdgeInsets padding) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: ThemeCleanPremium.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.72,
          minChildSize: 0.4,
          maxChildSize: 0.94,
          builder: (context, scrollCtrl) {
            return SingleChildScrollView(
              controller: scrollCtrl,
              padding: EdgeInsets.fromLTRB(
                padding.left,
                12,
                padding.right,
                12 + MediaQuery.paddingOf(context).bottom,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Icon(Icons.tune_rounded,
                          color: ThemeCleanPremium.primary, size: 26),
                      const SizedBox(width: 10),
                      const Expanded(
                        child: Text(
                          'Filtros avançados',
                          style: TextStyle(
                            fontWeight: FontWeight.w900,
                            fontSize: 18,
                            letterSpacing: -0.3,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Gênero, faixa etária, cadastro, departamento e aniversário.',
                    style: TextStyle(
                      fontSize: 13,
                      color: ThemeCleanPremium.onSurfaceVariant,
                      height: 1.35,
                    ),
                  ),
                  const SizedBox(height: 16),
                  _buildFiltrosSection(padding),
                  const SizedBox(height: 20),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _showLinkCadastroSheet() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: ThemeCleanPremium.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(
          ThemeCleanPremium.pagePadding(ctx).left,
          8,
          ThemeCleanPremium.pagePadding(ctx).right,
          16 + MediaQuery.paddingOf(ctx).bottom,
        ),
        child: _LinkCadastroPublicoCard(
          tenantId: _effectiveTenantId,
          role: widget.role,
        ),
      ),
    );
  }

  /// Faixa única: busca + ações + status — ultra premium, uma linha (com scroll horizontal no estreito).
  Widget _buildMembersUltraFilterStrip(
    EdgeInsets padding, {
    required MembersLimitResult? limitResult,
    required bool addBlocked,
  }) {
    final adv = _advancedFiltersActiveCount;
    return Padding(
      padding: EdgeInsets.fromLTRB(padding.left, 0, padding.right, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Colors.white,
                  ThemeCleanPremium.primary.withValues(alpha: 0.04),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: ThemeCleanPremium.primary.withValues(alpha: 0.12),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 18,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            padding: const EdgeInsets.fromLTRB(8, 10, 8, 10),
            child: LayoutBuilder(
              builder: (context, c) {
                final narrow = c.maxWidth < 720;
                final row = Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: _buildPremiumSearchField(EdgeInsets.zero),
                    ),
                    const SizedBox(width: 6),
                    Badge(
                      isLabelVisible: adv > 0,
                      label: Text('$adv',
                          style: const TextStyle(
                              fontSize: 11, fontWeight: FontWeight.w800)),
                      child: IconButton.filledTonal(
                        onPressed: () =>
                            unawaited(_showAdvancedFiltersSheet(padding)),
                        icon: const Icon(Icons.tune_rounded, size: 22),
                        tooltip: 'Filtros avançados',
                        style: IconButton.styleFrom(
                          minimumSize: const Size(44, 44),
                        ),
                      ),
                    ),
                    IconButton.filled(
                      onPressed: () =>
                          _recolherFiltrosMembros(limitResult, addBlocked),
                      icon: const Icon(Icons.open_in_full_rounded, size: 22),
                      tooltip: 'Lista em ecrã inteiro',
                      style: IconButton.styleFrom(
                        backgroundColor: ThemeCleanPremium.primary,
                        foregroundColor: Colors.white,
                        minimumSize: const Size(44, 44),
                      ),
                    ),
                    PopupMenuButton<String>(
                      tooltip: 'Mais opções',
                      icon: Icon(Icons.more_vert_rounded,
                          color: ThemeCleanPremium.onSurfaceVariant),
                      onSelected: (v) {
                        if (v == 'link') unawaited(_showLinkCadastroSheet());
                        if (v == 'funcoes') {
                          unawaited(Navigator.push(
                            context,
                            MaterialPageRoute<void>(
                              builder: (_) => FuncoesPermissoesPage(
                                tenantId: _effectiveTenantId,
                                role: widget.role,
                              ),
                            ),
                          ));
                        }
                      },
                      itemBuilder: (ctx) => [
                        if (_canManage)
                          const PopupMenuItem(
                            value: 'link',
                            child: ListTile(
                              dense: true,
                              leading: Icon(Icons.link_rounded),
                              title: Text('Link cadastro público'),
                              contentPadding: EdgeInsets.zero,
                            ),
                          ),
                        if (_canManage)
                          const PopupMenuItem(
                            value: 'funcoes',
                            child: ListTile(
                              dense: true,
                              leading: Icon(Icons.badge_rounded),
                              title: Text('Funções e permissões'),
                              contentPadding: EdgeInsets.zero,
                            ),
                          ),
                      ],
                    ),
                  ],
                );
                if (narrow) {
                  return SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    physics: const BouncingScrollPhysics(),
                    child: ConstrainedBox(
                      constraints: BoxConstraints(minWidth: c.maxWidth),
                      child: row,
                    ),
                  );
                }
                return row;
              },
            ),
          ),
          _buildPremiumStatusBar(padding),
        ],
      ),
    );
  }

  bool _onMembersScrollNotification(ScrollNotification n, int totalDocs) {
    if (n.metrics.axis != Axis.vertical) return false;
    final nearBottom =
        (n.metrics.maxScrollExtent - n.metrics.pixels) < 420;
    if (nearBottom && _membersVisibleCount < totalDocs) {
      setState(() {
        _membersVisibleCount =
            (_membersVisibleCount + _membersPageSize).clamp(0, totalDocs);
      });
    }
    return false;
  }

  void _openMembersFullscreenList(
      MembersLimitResult? limitResult, bool addBlocked) {
    Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (ctx) {
          final pad = ThemeCleanPremium.pagePadding(ctx);
          return Scaffold(
            backgroundColor: ThemeCleanPremium.surfaceVariant,
            appBar: AppBar(
              backgroundColor: ThemeCleanPremium.primary,
              foregroundColor: Colors.white,
              leading: IconButton(
                icon: const Icon(Icons.arrow_back_rounded),
                tooltip: 'Voltar aos filtros',
                onPressed: () => Navigator.pop(ctx),
              ),
              title: const Text('Membros'),
              actions: [
                if (_canManage)
                  IconButton(
                    icon: const Icon(Icons.picture_as_pdf_rounded),
                    tooltip: 'Exportar membros (PDF)',
                    onPressed: () => _exportPdf(ctx),
                  ),
                if (_canManage)
                  IconButton(
                    icon: const Icon(Icons.download_rounded),
                    tooltip: 'Exportar membros (CSV)',
                    onPressed: () => _exportCsv(ctx),
                  ),
                if (_canManage)
                  IconButton(
                    icon: Icon(Icons.person_add_rounded,
                        color: addBlocked ? Colors.white54 : null),
                    tooltip: addBlocked ? 'Limite atingido' : 'Novo membro',
                    onPressed: addBlocked ? null : () => _onAddMember(ctx),
                  ),
              ],
            ),
            body: SafeArea(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (limitResult != null && limitResult.planLimit > 0)
                    _MembersLimitBanner(result: limitResult),
                  Expanded(
                    child: _buildMembersListFutureColumn(
                      pad,
                      addBlocked: addBlocked,
                      limitResult: limitResult,
                      includeInlineFilters: false,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  void _refreshMembers({
    bool forceServer = false,
    String? clearOptimisticMemberOverlayId,
    String? clearOptimisticRemovedMemberId,
  }) {
    setState(() {
      _membersVisibleCount = _membersPageSize;
      if (clearOptimisticMemberOverlayId != null) {
        _optimisticMemberOverlays.remove(clearOptimisticMemberOverlayId);
      }
      if (clearOptimisticRemovedMemberId != null) {
        _optimisticRemovedMemberIds.remove(clearOptimisticRemovedMemberId);
      }
      _membersDataFuture = _loadMembersData(forceServer: forceServer);
    });
  }

  _MemberDoc _memberWithOptimisticOverlay(_MemberDoc m) {
    final o = _optimisticMemberOverlays[m.id];
    if (o == null || o.isEmpty) return m;
    return _MemberDoc(m.id, {...m.data, ...o});
  }

  void _applyOptimisticMemberEditOverlay(
      String memberId, Map<String, dynamic> r) {
    final patch = <String, dynamic>{};
    void put(List<String> keys, String v) {
      if (v.isEmpty) return;
      for (final k in keys) {
        patch[k] = v;
      }
    }

    put(
      ['NOME_COMPLETO', 'nome', 'name'],
      (r['name'] ?? '').toString().trim(),
    );
    put(['EMAIL', 'email'], (r['email'] ?? '').toString().trim());
    put(
      ['TELEFONES', 'telefone'],
      (r['phone'] ?? '').toString().trim(),
    );
    final st = (r['status'] ?? '').toString().trim();
    if (st.isNotEmpty) {
      patch['STATUS'] = st;
      patch['status'] = st;
    }
    put(['ENDERECO', 'endereco'], (r['endereco'] ?? '').toString().trim());
    put(['BAIRRO', 'bairro'], (r['bairro'] ?? '').toString().trim());
    put(['CIDADE', 'cidade'], (r['cidade'] ?? '').toString().trim());
    put(['CEP', 'cep'], (r['cep'] ?? '').toString().trim());
    put(['ESTADO', 'estado', 'uf'], (r['estado'] ?? '').toString().trim());
    put(
      [
        'QUADRA_LOTE_NUMERO',
        'quadraLoteNumero',
        'quadra_lote_numero',
      ],
      (r['quadraLoteNumero'] ?? '').toString().trim(),
    );
    put(
      ['ESCOLARIDADE', 'escolaridade'],
      (r['escolaridade'] ?? '').toString().trim(),
    );
    put(
      ['PROFISSAO', 'profissao'],
      (r['profissao'] ?? '').toString().trim(),
    );
    put(
      ['NOME_CONJUGE', 'nomeConjuge'],
      (r['conjuge'] ?? '').toString().trim(),
    );
    put(
      ['FILIACAO_PAI', 'filiacaoPai'],
      (r['filiacaoPai'] ?? '').toString().trim(),
    );
    put(
      ['FILIACAO_MAE', 'filiacaoMae'],
      (r['filiacaoMae'] ?? '').toString().trim(),
    );
    put(['SEXO', 'sexo'], (r['sexo'] ?? '').toString().trim());
    if (patch.isEmpty) return;
    setState(() {
      _optimisticMemberOverlays[memberId] = {
        ...?_optimisticMemberOverlays[memberId],
        ...patch,
      };
    });
  }

  /// URL da foto: overlay pós-upload + dados mesclados do Firestore.
  String _photoUrlForMember(String memberId, Map<String, dynamic> data) {
    final up = _uploadedPhotoUrls[memberId];
    if (up != null && up.trim().isNotEmpty) {
      final s = sanitizeImageUrl(up);
      if (isValidImageUrl(s)) return s;
    }
    return _photoUrlFromMemberData(data);
  }

  String _tenantIdForMemberData(Map<String, dynamic> data) {
    for (final k in const [
      'tenantId',
      'igrejaId',
      'tenant',
      'churchId',
      'igrejad'
    ]) {
      final v = (data[k] ?? '').toString().trim();
      if (v.isNotEmpty) return v;
    }
    return _effectiveTenantId;
  }

  /// Storage `igrejas/{id}/membros/…`: usa o tenant do painel quando existir, para não apontar pasta errada após merge com `users`.
  String _storageTenantIdForMemberPhotos(Map<String, dynamic> data) {
    final eff = _effectiveTenantId.trim();
    if (eff.isNotEmpty) return eff;
    return _tenantIdForMemberData(data).trim();
  }

  /// Carrega cargos da coleção cargos + roles de sistema (membro, adm, gestor). Usado no cadastro de membros.
  Future<List<({String key, String label})>> _loadCargosForMember() async {
    try {
      final fromPainel =
          await ChurchFuncoesControleService.loadOptionsForMemberPicker(
        _effectiveTenantId,
        _funcoesList,
        _funcaoLabel,
      );
      if (fromPainel.isNotEmpty) {
        return fromPainel.map((e) => (key: e.key, label: e.label)).toList();
      }
    } catch (_) {}
    try {
      final snap = await _cargosCol.orderBy('name').get();
      final list = <({String key, String label})>[];
      for (final d in snap.docs) {
        final data = d.data();
        final name = (data['name'] ?? d.id).toString().trim();
        final key = (data['key'] ?? d.id).toString().trim();
        if (key.isNotEmpty && name.isNotEmpty)
          list.add((key: key, label: name));
      }
      for (final k in ['membro', 'adm', 'gestor']) {
        if (!list.any((e) => e.key == k))
          list.add((key: k, label: _funcaoLabel(k)));
      }
      list.sort(
          (a, b) => a.label.toLowerCase().compareTo(b.label.toLowerCase()));
      return list.isEmpty
          ? _funcoesList.map((k) => (key: k, label: _funcaoLabel(k))).toList()
          : list;
    } catch (_) {
      return _funcoesList.map((k) => (key: k, label: _funcaoLabel(k))).toList();
    }
  }

  /// Gestão completa da lista (qualquer membro): admin, gestor, pastor, secretário, tesoureiro etc.
  bool get _canManage => AppPermissions.canEditAnyChurchMember(widget.role);

  bool _isSelfMember(_MemberDoc member) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return false;
    if (member.id == uid) return true;
    final authUid = (member.data['authUid'] ?? '').toString().trim();
    if (authUid.isNotEmpty && authUid == uid) return true;
    final cpfDigits = (widget.linkedCpf ?? '').replaceAll(RegExp(r'\D'), '');
    if (cpfDigits.length == 11) {
      final idDigits = member.id.replaceAll(RegExp(r'\D'), '');
      if (idDigits == cpfDigits) return true;
    }
    return false;
  }

  /// Editar ficha: equipe pode qualquer um; membro só a si mesmo.
  bool _canEditMemberRecord(_MemberDoc member) =>
      _canManage || _isSelfMember(member);

  /// Carteirinha digital: gestão vê todos; membro/visitante só a própria ficha.
  bool _canOpenCarteirinhaFor(_MemberDoc member) =>
      _canManage || _isSelfMember(member);

  bool _memberHasLogin(_MemberDoc member) =>
      (member.data['authUid'] ?? '').toString().trim().isNotEmpty;

  Future<void> _abrirAtualizarSenhaProprio(
      BuildContext context, _MemberDoc member) async {
    if (!_isSelfMember(member) || !_memberHasLogin(member)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          ThemeCleanPremium.feedbackSnackBar(
              'Conta de login não encontrada para este cadastro.'),
        );
      }
      return;
    }
    final raw =
        (member.data['CPF'] ?? member.data['cpf'] ?? widget.linkedCpf ?? '')
            .toString()
            .replaceAll(RegExp(r'\D'), '');
    final cpfLabel =
        raw.length == 11 ? _formatCpf(raw) : (raw.isNotEmpty ? raw : '—');
    await Navigator.push<void>(
      context,
      MaterialPageRoute<void>(
        builder: (_) => ChangePasswordPage(
          tenantId: _effectiveTenantId,
          cpf: cpfLabel,
          force: false,
        ),
      ),
    );
  }

  /// Pastor, secretário, presbítero, gestor, etc. — aprovar cadastros pendentes.
  bool get _canApprovePending => AppPermissions.canEditDepartments(widget.role);

  bool _memberDocIsPending(Map<String, dynamic> data) {
    final s = (data['STATUS'] ?? data['status'] ?? '').toString().toLowerCase();
    return s.contains('pendente');
  }

  Future<void> _aprovarMembrosPorIds(Set<String> ids) async {
    if (ids.isEmpty || !mounted) return;
    await FirebaseAuth.instance.currentUser?.getIdToken(true);
    final linkage = await _getTenantLinkage();
    final col = FirebaseFirestore.instance
        .collection('igrejas')
        .doc(_effectiveTenantId)
        .collection('membros');
    final batch = FirebaseFirestore.instance.batch();
    for (final id in ids) {
      batch.update(col.doc(id), {
        'alias': linkage['alias'],
        'slug': linkage['slug'],
        'tenantId': _effectiveTenantId,
        'status': 'ativo',
        'STATUS': 'ativo',
        'aprovadoEm': FieldValue.serverTimestamp(),
      });
    }
    await batch.commit();
    final fn = FirebaseFunctions.instanceFor(region: 'us-central1');
    for (final id in ids) {
      try {
        await fn
            .httpsCallable('setMemberApproved')
            .call({'tenantId': _effectiveTenantId, 'memberId': id});
      } catch (_) {}
    }
    if (mounted) {
      setState(() => _selectedPendingIds.removeWhere(ids.contains));
      ScaffoldMessenger.of(context).showSnackBar(
          ThemeCleanPremium.successSnackBar(
              '${ids.length} membro(s) aprovado(s).'));
      _refreshMembers();
    }
  }

  Future<void> _confirmAprovarTodosFiltrados(
      List<_MemberDoc> pendentesNaLista) async {
    if (pendentesNaLista.isEmpty || !mounted) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusLg)),
        title: const Text('Aprovar todos filtrados'),
        content: Text(
            'Aprovar ${pendentesNaLista.length} cadastro(s) pendente(s) exibido(s) na lista?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Aprovar todos')),
        ],
      ),
    );
    if (ok == true && mounted) {
      await _aprovarMembrosPorIds(pendentesNaLista.map((e) => e.id).toSet());
    }
  }

  CollectionReference<Map<String, dynamic>> get _members =>
      FirebaseFirestore.instance
          .collection('igrejas')
          .doc(_effectiveTenantId)
          .collection('membros');

  CollectionReference<Map<String, dynamic>> get _cargosCol =>
      FirebaseFirestore.instance
          .collection('igrejas')
          .doc(_effectiveTenantId)
          .collection('cargos');

  CollectionReference<Map<String, dynamic>> get _membros =>
      FirebaseFirestore.instance
          .collection('igrejas')
          .doc(_effectiveTenantId)
          .collection('membros');

  /// Igrejas: mesma estrutura para igrejas que usam collection igrejas (ex.: Brasil para Cristo)
  CollectionReference<Map<String, dynamic>> get _membersIgrejas =>
      FirebaseFirestore.instance
          .collection('igrejas')
          .doc(_effectiveTenantId)
          .collection('membros');

  CollectionReference<Map<String, dynamic>> get _membrosIgrejas =>
      FirebaseFirestore.instance
          .collection('igrejas')
          .doc(_effectiveTenantId)
          .collection('membros');

  CollectionReference<Map<String, dynamic>> get _departments =>
      FirebaseFirestore.instance
          .collection('igrejas')
          .doc(_effectiveTenantId)
          .collection('departamentos');

  // Usados apenas via _loadMembersData() (leitura pontual).

  // ─── Departamentos ────────────────────────────────────────────────────────
  Future<List<_DeptItem>> _loadDepartments() async {
    // Sem orderBy('name'): documentos só com id (ex.: ens_professores) não têm [name] e sumiam da query.
    final snap = await _departments.get();
    final list = snap.docs
        .map((d) => _DeptItem(
              id: d.id,
              name: churchDepartmentNameFromDoc(d),
            ))
        .where((d) => d.name.isNotEmpty)
        .toList();
    list.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return list;
  }

  Future<void> _editDepartments({
    required BuildContext context,
    required String memberId,
    required List<String> current,
    required Map<String, dynamic> memberData,
  }) async {
    if (!_canManage) return;
    final depts = await _loadDepartments();
    final selected = current.toSet();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusLg)),
        title: const Text('Vincular departamentos'),
        content: SizedBox(
          width: 420,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: depts.length,
            itemBuilder: (_, i) {
              final d = depts[i];
              final checked = selected.contains(d.id);
              return CheckboxListTile(
                value: checked,
                title: Text(d.name),
                onChanged: (v) {
                  if (v == true) {
                    selected.add(d.id);
                  } else {
                    selected.remove(d.id);
                  }
                  (ctx as Element).markNeedsBuild();
                },
              );
            },
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          FilledButton(
              onPressed: () {
                ThemeCleanPremium.hapticAction();
                Navigator.pop(ctx, true);
              },
              child: const Text('Salvar')),
        ],
      ),
    );
    if (ok != true) return;
    final linkage = await _getTenantLinkage();
    final listIds = selected.toList();
    final oldSet = current.toSet();
    final newSet = selected;
    final merged = Map<String, dynamic>.from(memberData);
    merged['DEPARTAMENTOS'] = listIds;
    merged['departamentosIds'] = listIds;
    try {
      await DepartmentMemberIntegrationService.syncMemberDepartmentLinks(
        tenantId: _effectiveTenantId,
        memberDocId: memberId,
        memberData: merged,
        previousDepartmentIds: oldSet,
        nextDepartmentIds: newSet,
        extraMemberFields: {
          'alias': linkage['alias'],
          'slug': linkage['slug'],
          'tenantId': _effectiveTenantId,
        },
      );
    } catch (_) {}
    _refreshMembers();
  }

  Future<void> _launchExternalUri(Uri uri) async {
    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    } catch (_) {}
  }

  String _whatsAppUriDigits(String phoneRaw) {
    var digits = phoneRaw.replaceAll(RegExp(r'\D'), '');
    if (digits.length == 11 && !digits.startsWith('55')) digits = '55$digits';
    if (digits.length == 10) digits = '55$digits';
    return digits;
  }

  // ─── Ver Detalhes do Membro ───────────────────────────────────────────────
  void _showMemberDetails(BuildContext context, _MemberDoc member) {
    final d = member.data;
    final name = _str(d, 'NOME_COMPLETO', 'nome', 'name');
    final email = _str(d, 'EMAIL', 'email');
    final phone = _str(d, 'TELEFONES', 'telefone');
    final cpf = _str(d, 'CPF', 'cpf');
    final sexo = _str(d, 'SEXO', 'sexo');
    final estadoCivil = _str(d, 'ESTADO_CIVIL', 'estadoCivil');
    final endereco = _str(d, 'ENDERECO', 'endereco');
    final quadraLoteNumero =
        _str(d, 'QUADRA_LOTE_NUMERO', 'quadraLoteNumero', 'quadra_lote_numero');
    final cep = _str(d, 'CEP', 'cep');
    final estado = _str(d, 'ESTADO', 'estado', 'uf');
    final cidade = _str(d, 'CIDADE', 'cidade');
    final bairro = _str(d, 'BAIRRO', 'bairro');
    final escolaridade = _str(d, 'ESCOLARIDADE', 'escolaridade');
    final conjuge = _str(d, 'NOME_CONJUGE', 'nomeConjuge');
    final filiacaoPai = _str(d, 'FILIACAO_PAI', 'filiacaoPai');
    final filiacaoMae = _str(d, 'FILIACAO_MAE', 'filiacaoMae');
    final filiacao = _str(d, 'FILIACAO', 'filiacao');
    final status = _str(d, 'STATUS', 'status').isEmpty
        ? 'ativo'
        : _str(d, 'STATUS', 'status');
    final photo = _photoUrlForMember(member.id, d);
    final nascimento = _parseDate(
        d['DATA_NASCIMENTO'] ?? d['dataNascimento'] ?? d['birthDate']);
    final criadoEm = _parseDate(d['CRIADO_EM'] ?? d['createdAt']);
    final isInativo = status.toLowerCase().contains('inativ');
    final isPending = _memberDocIsPending(d);
    final avatarColor = _avatarColor(
            d,
            photo.isNotEmpty ||
                _optimisticProfilePhotoBytes.containsKey(member.id)) ??
        ThemeCleanPremium.primary.withOpacity(0.1);
    final photoTenantId = _storageTenantIdForMemberPhotos(d);
    final profissao = _str(d, 'PROFISSAO', 'profissao');
    final dataBatismo =
        _parseDate(d['DATA_BATISMO'] ?? d['dataBatismo'] ?? d['data_batismo']);
    double? geoLat;
    double? geoLng;
    final rawLat = d['GEO_LAT'] ?? d['latitude'];
    final rawLng = d['GEO_LNG'] ?? d['longitude'];
    if (rawLat is num) {
      geoLat = rawLat.toDouble();
    } else {
      geoLat = double.tryParse('${rawLat ?? ''}'.trim().replaceAll(',', '.'));
    }
    if (rawLng is num) {
      geoLng = rawLng.toDouble();
    } else {
      geoLng = double.tryParse('${rawLng ?? ''}'.trim().replaceAll(',', '.'));
    }
    final coverRaw =
        (d['FOTO_CAPA_URL'] ?? d['fotoCapaUrl'] ?? '').toString().trim();
    final coverUrl = sanitizeImageUrl(coverRaw);
    final coverOk = isValidImageUrl(coverUrl);
    final canSensitive = widget.role.canViewMemberSensitiveFields;
    const coverH = 128.0;
    const avRadius = 48.0;
    final authUidSys = _str(d, 'authUid', 'auth_uid').trim();
    final docIdIsUidShape =
        member.id.length >= 20 && RegExp(r'^[A-Za-z0-9]+$').hasMatch(member.id);
    final sistemaFirebaseUid =
        authUidSys.isNotEmpty ? authUidSys : (docIdIsUidShape ? member.id : '');

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.85,
        maxChildSize: 0.95,
        minChildSize: 0.5,
        builder: (ctx, scrollCtrl) => SingleChildScrollView(
          controller: scrollCtrl,
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
          child: Column(
            children: [
              Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(2))),
              const SizedBox(height: 10),
              SizedBox(
                height: coverH + avRadius,
                child: Stack(
                  clipBehavior: Clip.none,
                  alignment: Alignment.topCenter,
                  children: [
                    Positioned(
                      top: 0,
                      left: 0,
                      right: 0,
                      height: coverH,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: coverOk
                            ? ResilientNetworkImage(
                                imageUrl: coverUrl,
                                fit: BoxFit.cover,
                                width: 720,
                                height: coverH,
                                memCacheWidth: 900,
                                memCacheHeight: 450,
                                errorWidget: Container(
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                      colors: [
                                        ThemeCleanPremium.primary
                                            .withOpacity(0.5),
                                        ThemeCleanPremium.primary
                                            .withOpacity(0.15),
                                      ],
                                    ),
                                  ),
                                ),
                              )
                            : Container(
                                width: double.infinity,
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                    colors: [
                                      ThemeCleanPremium.primary
                                          .withOpacity(0.5),
                                      ThemeCleanPremium.primary
                                          .withOpacity(0.14),
                                    ],
                                  ),
                                ),
                              ),
                      ),
                    ),
                    Positioned(
                      top: coverH - avRadius,
                      child: Container(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 3),
                          boxShadow: const [
                            BoxShadow(
                              color: Color(0x14000000),
                              blurRadius: 24,
                              offset: Offset(0, 10),
                            ),
                          ],
                        ),
                        child: Hero(
                          tag: 'member_profile_photo_${member.id}',
                          child: _MemberAvatar(
                            photoUrl: photo.isNotEmpty ? photo : null,
                            memoryPreviewBytes:
                                _optimisticProfilePhotoBytes[member.id],
                            memberData: d,
                            name: name,
                            radius: avRadius,
                            backgroundColor: avatarColor,
                            tenantId: photoTenantId,
                            memberId: member.id,
                            cpfDigits: _str(d, 'CPF', 'cpf'),
                            authUid: _memberAuthUidFromData(d),
                            memCacheMaxPx: 1400,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Text(name,
                  style: const TextStyle(
                      fontSize: 22, fontWeight: FontWeight.w800),
                  textAlign: TextAlign.center),
              const SizedBox(height: 6),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                decoration: BoxDecoration(
                  color: isPending
                      ? const Color(0xFFFFFBEB)
                      : (isInativo
                          ? const Color(0xFFFFEBEE)
                          : const Color(0xFFECFDF5)),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  status,
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                    color: isPending
                        ? const Color(0xFFB45309)
                        : (isInativo
                            ? const Color(0xFFB91C1C)
                            : const Color(0xFF047857)),
                  ),
                ),
              ),
              if (phone.isNotEmpty || email.isNotEmpty) ...[
                const SizedBox(height: 14),
                Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    if (phone.replaceAll(RegExp(r'\D'), '').length >= 10)
                      _ActionChip(
                        icon: Icons.chat_rounded,
                        label: 'WhatsApp',
                        color: const Color(0xFF25D366),
                        onTap: () {
                          final w = _whatsAppUriDigits(phone);
                          if (w.length >= 12) {
                            unawaited(_launchExternalUri(
                                Uri.parse('https://wa.me/$w')));
                          }
                        },
                      ),
                    if (email.isNotEmpty)
                      _ActionChip(
                        icon: Icons.mail_outline_rounded,
                        label: 'E-mail',
                        color: const Color(0xFF2563EB),
                        onTap: () {
                          unawaited(_launchExternalUri(Uri(
                            scheme: 'mailto',
                            path: email,
                            queryParameters: {'subject': 'Contato — $name'},
                          )));
                        },
                      ),
                    if (geoLat != null &&
                        geoLng != null &&
                        geoLat.abs() <= 90 &&
                        geoLng.abs() <= 180)
                      _ActionChip(
                        icon: Icons.map_rounded,
                        label: 'Mapa',
                        color: const Color(0xFFEA4335),
                        onTap: () {
                          unawaited(_launchExternalUri(Uri.parse(
                              'https://www.google.com/maps/search/?api=1&query=${geoLat!},${geoLng!}')));
                        },
                      )
                    else if (canSensitive &&
                        (endereco.isNotEmpty || cidade.isNotEmpty))
                      _ActionChip(
                        icon: Icons.map_rounded,
                        label: 'Mapa',
                        color: const Color(0xFFEA4335),
                        onTap: () {
                          final q = Uri.encodeComponent([
                            endereco,
                            bairro,
                            cidade,
                            estado,
                            cep,
                          ].where((e) => e.trim().isNotEmpty).join(', '));
                          if (q.isNotEmpty) {
                            unawaited(_launchExternalUri(Uri.parse(
                                'https://www.google.com/maps/search/?api=1&query=$q')));
                          }
                        },
                      ),
                  ],
                ),
              ],
              const SizedBox(height: 20),
              // Ações (aprovar pendente: secretariado/pastor; demais: gestor/adm)
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 12,
                runSpacing: 12,
                children: [
                  if (_canApprovePending && isPending)
                    _ActionChip(
                      icon: Icons.how_to_reg_rounded,
                      label: 'Aprovar cadastro',
                      color: const Color(0xFF059669),
                      onTap: () async {
                        Navigator.pop(ctx);
                        await _aprovarMembrosPorIds({member.id});
                      },
                    ),
                  if (_canEditMemberRecord(member))
                    _ActionChip(
                        icon: Icons.edit_rounded,
                        label: 'Editar',
                        color: ThemeCleanPremium.primary,
                        onTap: () {
                          Navigator.pop(ctx);
                          _editMember(context, member);
                        }),
                  if (_canOpenCarteirinhaFor(member))
                    _ActionChip(
                        icon: Icons.badge_rounded,
                        label: 'Carteirinha',
                        color: const Color(0xFF7C3AED),
                        onTap: () {
                          Navigator.pop(ctx);
                          Navigator.push(
                              context,
                              MaterialPageRoute(
                                  builder: (_) => MemberCardPage(
                                      tenantId: _effectiveTenantId,
                                      role: widget.role,
                                      memberId: member.id)));
                        }),
                  if (_isSelfMember(member) && _memberHasLogin(member))
                    _ActionChip(
                        icon: Icons.vpn_key_rounded,
                        label: 'Atualizar senha',
                        color: const Color(0xFFEA580C),
                        onTap: () {
                          Navigator.pop(ctx);
                          unawaited(
                              _abrirAtualizarSenhaProprio(context, member));
                        }),
                  if (_canManage) ...[
                    _ActionChip(
                        icon: Icons.delete_outline_rounded,
                        label: 'Excluir',
                        color: const Color(0xFFDC2626),
                        onTap: () {
                          Navigator.pop(ctx);
                          _deleteMember(context, member);
                        }),
                    if (member.data['authUid'] == null &&
                        ((member.data['EMAIL'] ?? '')
                                .toString()
                                .trim()
                                .isNotEmpty ||
                            (member.data['CPF'] ?? '')
                                    .toString()
                                    .replaceAll(RegExp(r'[^0-9]'), '')
                                    .length ==
                                11))
                      _ActionChip(
                          icon: Icons.login_rounded,
                          label: 'Gerar senha / login',
                          color: const Color(0xFF059669),
                          onTap: () {
                            Navigator.pop(ctx);
                            _criarLoginMembro(context, member);
                          }),
                    if (_memberHasLogin(member) && !_isSelfMember(member))
                      _ActionChip(
                          icon: Icons.lock_reset_rounded,
                          label: 'Redefinir senha',
                          color: Colors.orange.shade700,
                          onTap: () {
                            Navigator.pop(ctx);
                            _redefinirSenhaMembro(context, member);
                          }),
                  ],
                ],
              ),
              const SizedBox(height: 20),
              // Dados
              _DetailSection(title: 'Informações Pessoais', items: [
                if (filiacaoMae.isNotEmpty)
                  _DetailRow(
                      icon: Icons.family_restroom_rounded,
                      label: 'Filiação (mãe)',
                      value: filiacaoMae),
                if (filiacaoPai.isNotEmpty)
                  _DetailRow(
                      icon: Icons.family_restroom_rounded,
                      label: 'Filiação (pai)',
                      value: filiacaoPai),
                if (filiacaoPai.isEmpty &&
                    filiacaoMae.isEmpty &&
                    filiacao.isNotEmpty)
                  _DetailRow(
                      icon: Icons.family_restroom_rounded,
                      label: 'Filiação',
                      value: filiacao),
                if (cpf.isNotEmpty)
                  _DetailRow(
                      icon: Icons.badge_rounded,
                      label: 'CPF',
                      value: canSensitive ? _formatCpf(cpf) : '•••.•••.•••-••'),
                if (nascimento != null)
                  _DetailRow(
                      icon: Icons.cake_rounded,
                      label: 'Nascimento',
                      value: _fmtDate(nascimento)),
                if (dataBatismo != null)
                  _DetailRow(
                      icon: Icons.water_drop_rounded,
                      label: 'Batismo',
                      value: _fmtDate(dataBatismo)),
                if (profissao.isNotEmpty)
                  _DetailRow(
                      icon: Icons.work_outline_rounded,
                      label: 'Profissão',
                      value: profissao),
                if (sexo.isNotEmpty)
                  _DetailRow(
                      icon: Icons.person_rounded, label: 'Sexo', value: sexo),
                if (phone.isNotEmpty)
                  _DetailRow(
                      icon: Icons.phone_rounded,
                      label: 'Telefone',
                      value: phone),
                if (email.isNotEmpty)
                  _DetailRow(
                      icon: Icons.email_rounded, label: 'E-mail', value: email),
                if (estadoCivil.isNotEmpty)
                  _DetailRow(
                      icon: Icons.favorite_rounded,
                      label: 'Estado Civil',
                      value: estadoCivil),
                if (escolaridade.isNotEmpty)
                  _DetailRow(
                      icon: Icons.school_rounded,
                      label: 'Escolaridade',
                      value: escolaridade),
                if (conjuge.isNotEmpty)
                  _DetailRow(
                      icon: Icons.people_rounded,
                      label: 'Cônjuge',
                      value: conjuge),
              ]),
              if (cep.isNotEmpty ||
                  endereco.isNotEmpty ||
                  quadraLoteNumero.isNotEmpty ||
                  bairro.isNotEmpty ||
                  cidade.isNotEmpty ||
                  estado.isNotEmpty)
                _DetailSection(title: 'Endereço', items: [
                  if (canSensitive && cep.isNotEmpty)
                    _DetailRow(
                        icon: Icons.pin_drop_rounded, label: 'CEP', value: cep),
                  if (canSensitive && endereco.isNotEmpty)
                    _DetailRow(
                        icon: Icons.home_rounded,
                        label: 'Endereço',
                        value: endereco),
                  if (canSensitive && quadraLoteNumero.isNotEmpty)
                    _DetailRow(
                        icon: Icons.apartment_rounded,
                        label: 'Quadra, Lote e Número',
                        value: quadraLoteNumero),
                  if (canSensitive && bairro.isNotEmpty)
                    _DetailRow(
                        icon: Icons.location_city_rounded,
                        label: 'Bairro',
                        value: bairro),
                  if (cidade.isNotEmpty)
                    _DetailRow(
                        icon: Icons.map_rounded,
                        label: 'Cidade',
                        value: cidade),
                  if (estado.isNotEmpty)
                    _DetailRow(
                        icon: Icons.flag_rounded,
                        label: 'Estado',
                        value: estado),
                  if (!canSensitive && (cidade.isNotEmpty || estado.isNotEmpty))
                    _DetailRow(
                        icon: Icons.lock_outline_rounded,
                        label: 'Localização',
                        value:
                            'Endereço completo visível só para pastoral/secretariado.',
                        softWrapValue: true),
                ]),
              _DetailSection(title: 'Sistema', items: [
                _DetailRow(
                    icon: Icons.fingerprint_rounded,
                    label: 'UID (Firebase)',
                    value: sistemaFirebaseUid.isNotEmpty
                        ? sistemaFirebaseUid
                        : '— vincule login ou aprove o cadastro'),
                if (member.id.isNotEmpty && member.id != sistemaFirebaseUid)
                  _DetailRow(
                      icon: Icons.description_outlined,
                      label: 'ID do documento (legado)',
                      value: member.id),
                if (criadoEm != null)
                  _DetailRow(
                      icon: Icons.calendar_today_rounded,
                      label: 'Cadastrado em',
                      value: _fmtDate(criadoEm)),
              ]),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }

  // ─── Editar Membro ────────────────────────────────────────────────────────
  Future<void> _editMember(BuildContext context, _MemberDoc member) async {
    final staffEdit = AppPermissions.canEditAnyChurchMember(widget.role);
    if (!staffEdit && !_isSelfMember(member)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          ThemeCleanPremium.feedbackSnackBar(
              'Você só pode alterar o seu próprio cadastro.'),
        );
      }
      return;
    }
    final selfOnly = !staffEdit;
    final d = member.data;
    String selectedTenantIdForEdit = _tenantIdForMemberData(
        d); // painel master: permite mudar igreja do membro
    final nameCtrl =
        TextEditingController(text: _str(d, 'NOME_COMPLETO', 'nome', 'name'));
    final emailCtrl = TextEditingController(text: _str(d, 'EMAIL', 'email'));
    final phoneCtrl =
        TextEditingController(text: _str(d, 'TELEFONES', 'telefone'));
    final cpfCtrl = TextEditingController(text: _str(d, 'CPF', 'cpf'));
    final enderecoCtrl =
        TextEditingController(text: _str(d, 'ENDERECO', 'endereco'));
    final quadraLoteNumeroCtrl = TextEditingController(
      text: _str(
          d, 'QUADRA_LOTE_NUMERO', 'quadraLoteNumero', 'quadra_lote_numero'),
    );
    final cepCtrl = TextEditingController(text: _str(d, 'CEP', 'cep'));
    final estadoCtrl =
        TextEditingController(text: _str(d, 'ESTADO', 'estado', 'uf'));
    final cidadeCtrl = TextEditingController(text: _str(d, 'CIDADE', 'cidade'));
    final bairroCtrl = TextEditingController(text: _str(d, 'BAIRRO', 'bairro'));
    final estadoCivilInitial =
        _normalizeEstadoCivilValue(_str(d, 'ESTADO_CIVIL', 'estadoCivil'));
    const estadoCivilOptions = <String>[
      'Casado(a)',
      'Divorciado(a)',
      'Solteiro(a)',
      'Viúvo(a)',
    ];
    String estadoCivilSelected = estadoCivilOptions.contains(estadoCivilInitial)
        ? estadoCivilInitial
        : estadoCivilOptions.first;
    final escolaridadeCtrl =
        TextEditingController(text: _str(d, 'ESCOLARIDADE', 'escolaridade'));
    final conjugeCtrl =
        TextEditingController(text: _str(d, 'NOME_CONJUGE', 'nomeConjuge'));
    final filiacaoPaiVal = _str(d, 'FILIACAO_PAI', 'filiacaoPai');
    final filiacaoMaeVal = _str(d, 'FILIACAO_MAE', 'filiacaoMae');
    final filiacaoLegado = _str(d, 'FILIACAO', 'filiacao');
    final filiacaoPaiCtrl = TextEditingController(
        text: filiacaoPaiVal.isNotEmpty ? filiacaoPaiVal : filiacaoLegado);
    final filiacaoMaeCtrl = TextEditingController(text: filiacaoMaeVal);
    final passwordCtrl = TextEditingController();
    String sexo = _str(d, 'SEXO', 'sexo');
    String status = _str(d, 'STATUS', 'status');
    if (status.isEmpty) status = 'ativo';
    // Carregar funções/cargos como estão gravados (preservar cargos customizados da coleção cargos).
    final funcoesRaw = d['FUNCOES'] ?? d['funcoes'];
    List<String> funcoesSelecionadas = [];
    if (funcoesRaw is List) {
      funcoesSelecionadas = funcoesRaw
          .map((e) => (e ?? '').toString().trim())
          .where((s) => s.isNotEmpty)
          .toSet()
          .toList();
    }
    if (funcoesSelecionadas.isEmpty) {
      final f = _str(d, 'FUNCAO', 'funcao', 'CARGO', 'cargo', 'role').trim();
      if (f.isNotEmpty)
        funcoesSelecionadas = [f];
      else
        funcoesSelecionadas = [_normalizeFuncao(f)]; // fallback legado
    }
    if (funcoesSelecionadas.isEmpty) funcoesSelecionadas = ['membro'];
    final funcoesNotifier =
        ValueNotifier<List<String>>(List<String>.from(funcoesSelecionadas));
    DateTime? dataConsagracao =
        _parseDate(d['DATA_CONSAGRACAO'] ?? d['dataConsagracao']);
    var removeConsagracao = false;
    DateTime? nascimento = _parseDate(
        d['DATA_NASCIMENTO'] ?? d['dataNascimento'] ?? d['birthDate']);
    DateTime? dataBatismo =
        _parseDate(d['DATA_BATISMO'] ?? d['dataBatismo'] ?? d['data_batismo']);
    final profissaoCtrl =
        TextEditingController(text: _str(d, 'PROFISSAO', 'profissao'));
    XFile? newPhoto;
    Uint8List? newPhotoBytes;
    final currentPhoto = _photoUrlForMember(member.id, d);
    final photoTenantId = _storageTenantIdForMemberPhotos(d);
    final memberName = _str(d, 'NOME_COMPLETO', 'nome', 'name');
    Uint8List? newAssinaturaBytes;
    bool removeAssinatura = false;
    final currentAssinaturaUrl =
        (d['assinaturaUrl'] ?? d['assinatura_url'] ?? '').toString().trim();
    final keyAssinaturaPreview = GlobalKey();
    bool podeVerFinanceiro = d['podeVerFinanceiro'] == true;
    bool podeVerPatrimonio = d['podeVerPatrimonio'] == true;
    bool podeVerFornecedores = d['podeVerFornecedores'] == true;
    bool podeEmitirRelatoriosCompletos =
        d['podeEmitirRelatoriosCompletos'] == true;
    bool _loadingCep = false;
    bool _pickingProfilePhoto = false;

    /// Dados retornados ao salvar: funções lidas do ValueNotifier no momento do clique para garantir gravação correta.
    final result = await showDialog<Map<String, dynamic>?>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) {
          final isMob = MediaQuery.of(ctx).size.width < 600;
          final avatarBg = _avatarColor(d, currentPhoto.isNotEmpty) ??
              ThemeCleanPremium.primary.withOpacity(0.1);
          return Dialog(
            insetPadding: isMob
                ? const EdgeInsets.symmetric(horizontal: 8, vertical: 24)
                : const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
            shape: RoundedRectangleBorder(
                borderRadius:
                    BorderRadius.circular(ThemeCleanPremium.radiusLg)),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                  maxWidth: 520,
                  maxHeight:
                      MediaQuery.of(ctx).size.height * (isMob ? 0.9 : 0.85)),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Header
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: ThemeCleanPremium.primary.withOpacity(0.06),
                      borderRadius:
                          const BorderRadius.vertical(top: Radius.circular(20)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.edit_rounded,
                            color: ThemeCleanPremium.primary),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            selfOnly ? 'Meu cadastro' : 'Editar Membro',
                            style: const TextStyle(
                                fontSize: 18, fontWeight: FontWeight.w800),
                          ),
                        ),
                        IconButton(
                            icon: const Icon(Icons.close_rounded),
                            onPressed: () => Navigator.pop(ctx, false)),
                      ],
                    ),
                  ),
                  Flexible(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                      child: Column(
                        children: [
                          Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                              'Foto do perfil',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: ThemeCleanPremium.onSurfaceVariant,
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                          // Foto (toque para trocar)
                          GestureDetector(
                            onTap: () async {
                              if (_pickingProfilePhoto) return;
                              setDlg(() => _pickingProfilePhoto = true);
                              try {
                                final picked = await _pickImage(ctx);
                                if (picked != null) {
                                  // Sempre em memória: XFile pós-WebP pode ser fromData sem path válido no disco.
                                  newPhotoBytes = await picked.readAsBytes();
                                  newPhoto = picked;
                                }
                              } finally {
                                if (!ctx.mounted) return;
                                setDlg(() => _pickingProfilePhoto = false);
                              }
                            },
                            child: Stack(
                              alignment: Alignment.bottomRight,
                              children: [
                                if (newPhoto != null)
                                  CircleAvatar(
                                    radius: 45,
                                    backgroundColor: avatarBg,
                                    backgroundImage: () {
                                      if (newPhotoBytes != null &&
                                          newPhotoBytes!.isNotEmpty) {
                                        return MemoryImage(newPhotoBytes!);
                                      }
                                      final p = newPhoto!.path;
                                      if (p.isEmpty) return null;
                                      if (kIsWeb) {
                                        return NetworkImage(p);
                                      }
                                      return FileImage(File(p));
                                    }() as ImageProvider<Object>?,
                                  )
                                else
                                  _MemberAvatar(
                                    photoUrl: currentPhoto.isNotEmpty
                                        ? currentPhoto
                                        : null,
                                    memberData: d,
                                    name: memberName,
                                    radius: 45,
                                    backgroundColor: avatarBg,
                                    tenantId: photoTenantId,
                                    memberId: member.id,
                                    cpfDigits: _str(d, 'CPF', 'cpf'),
                                    authUid: _memberAuthUidFromData(d),
                                    memCacheMaxPx: 720,
                                  ),
                                Container(
                                  padding: const EdgeInsets.all(6),
                                  decoration: BoxDecoration(
                                      color: ThemeCleanPremium.primary,
                                      shape: BoxShape.circle,
                                      border: Border.all(
                                          color: Colors.white, width: 2)),
                                  child: const Icon(Icons.camera_alt_rounded,
                                      color: Colors.white, size: 16),
                                ),
                              ],
                            ),
                          ),
                          if (_pickingProfilePhoto)
                            const Padding(
                              padding: EdgeInsets.only(top: 10),
                              child: LinearProgressIndicator(minHeight: 3),
                            ),
                          const SizedBox(height: 16),
                          _EditField(
                              controller: nameCtrl,
                              label: 'Nome Completo',
                              icon: Icons.person_rounded),
                          _EditField(
                              controller: filiacaoMaeCtrl,
                              label: 'Filiação (mãe)',
                              icon: Icons.family_restroom_rounded),
                          _EditField(
                              controller: filiacaoPaiCtrl,
                              label: 'Filiação (pai)',
                              icon: Icons.family_restroom_rounded),
                          if (selfOnly)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: InputDecorator(
                                decoration: InputDecoration(
                                  labelText: 'CPF',
                                  border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(
                                          ThemeCleanPremium.radiusSm)),
                                  prefixIcon: const Icon(Icons.badge_rounded),
                                ),
                                child: Text(
                                  _formatCpf(cpfCtrl.text),
                                  style: TextStyle(
                                      color: Colors.grey.shade800,
                                      fontWeight: FontWeight.w600),
                                ),
                              ),
                            )
                          else
                            _EditField(
                                controller: cpfCtrl,
                                label: 'CPF',
                                icon: Icons.badge_rounded,
                                type: TextInputType.number),
                          // Nascimento
                          Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(
                                  ThemeCleanPremium.radiusSm),
                              onTap: () async {
                                final picked = await showDatePicker(
                                  context: ctx,
                                  initialDate: nascimento ?? DateTime(2000),
                                  firstDate: DateTime(1920),
                                  lastDate: DateTime.now(),
                                );
                                if (picked != null)
                                  setDlg(() => nascimento = picked);
                              },
                              child: InputDecorator(
                                decoration: InputDecoration(
                                  labelText: 'Data de Nascimento',
                                  border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(
                                          ThemeCleanPremium.radiusSm)),
                                  prefixIcon: const Icon(Icons.cake_rounded),
                                ),
                                child: Text(
                                    nascimento != null
                                        ? _fmtDate(nascimento!)
                                        : 'Selecionar...',
                                    style: TextStyle(
                                        color: nascimento != null
                                            ? null
                                            : Colors.grey.shade500)),
                              ),
                            ),
                          ),
                          // Sexo
                          Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: DropdownButtonFormField<String>(
                              value: sexo.isNotEmpty ? sexo : null,
                              decoration: InputDecoration(
                                labelText: 'Sexo',
                                border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(
                                        ThemeCleanPremium.radiusSm)),
                                prefixIcon: const Icon(Icons.wc_rounded),
                              ),
                              items: const [
                                DropdownMenuItem(
                                    value: 'Masculino',
                                    child: Text('Masculino')),
                                DropdownMenuItem(
                                    value: 'Feminino', child: Text('Feminino')),
                              ],
                              onChanged: (v) => setDlg(() => sexo = v ?? ''),
                            ),
                          ),
                          _EditField(
                              controller: phoneCtrl,
                              label: 'Telefone',
                              icon: Icons.phone_rounded,
                              type: TextInputType.phone),
                          _EditField(
                              controller: emailCtrl,
                              label: 'E-mail',
                              icon: Icons.email_rounded,
                              type: TextInputType.emailAddress),
                          // Ativo/Inativo — só equipe (arquiva sem apagar histórico)
                          if (staffEdit)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: Material(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(16),
                                child: SwitchListTile(
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(16),
                                    side: const BorderSide(
                                        color: Color(0xFFE2E8F0)),
                                  ),
                                  value:
                                      !status.toLowerCase().contains('inativ'),
                                  title: const Text('Membro ativo'),
                                  subtitle: const Text(
                                    'Desligue para inativar sem excluir dados.',
                                    style: TextStyle(fontSize: 12),
                                  ),
                                  activeThumbColor: ThemeCleanPremium.primary,
                                  onChanged: (v) => setDlg(() {
                                    status = v ? 'ativo' : 'inativo';
                                  }),
                                ),
                              ),
                            ),
                          // Igreja (ADM total do sistema: permite transferir membro para outra igreja)
                          if (staffEdit && _canTransferMember)
                            FutureBuilder<List<MapEntry<String, String>>>(
                              future: _loadTenantsForMove(),
                              builder: (ctx, snap) {
                                if (!snap.hasData)
                                  return const SizedBox(height: 0);
                                final tenants = snap.data!;
                                final hasCurrent = tenants.any(
                                    (e) => e.key == selectedTenantIdForEdit);
                                final list = hasCurrent
                                    ? tenants
                                    : [
                                        MapEntry(selectedTenantIdForEdit,
                                            'Igreja atual'),
                                        ...tenants
                                      ];
                                return Padding(
                                  padding: const EdgeInsets.only(bottom: 12),
                                  child: DropdownButtonFormField<String>(
                                    isExpanded: true,
                                    value: list.any((e) =>
                                            e.key == selectedTenantIdForEdit)
                                        ? selectedTenantIdForEdit
                                        : null,
                                    decoration: InputDecoration(
                                      labelText: 'Igreja (transferir membro)',
                                      hintText: 'Selecione a igreja do membro',
                                      border: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(
                                              ThemeCleanPremium.radiusSm)),
                                      prefixIcon:
                                          const Icon(Icons.church_rounded),
                                    ),
                                    selectedItemBuilder: (context) => list
                                        .map(
                                          (e) => Align(
                                            alignment: AlignmentDirectional
                                                .centerStart,
                                            child: Text(
                                              e.value,
                                              maxLines: 2,
                                              overflow: TextOverflow.ellipsis,
                                              style: const TextStyle(
                                                  fontSize: 14,
                                                  fontWeight: FontWeight.w600),
                                            ),
                                          ),
                                        )
                                        .toList(),
                                    items: list
                                        .map(
                                          (e) => DropdownMenuItem<String>(
                                            value: e.key,
                                            child: Text(
                                              e.value,
                                              maxLines: 3,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                        )
                                        .toList(),
                                    onChanged: (v) {
                                      if (v != null) {
                                        selectedTenantIdForEdit = v;
                                        setDlg(() {});
                                      }
                                    },
                                  ),
                                );
                              },
                            ),
                          // Funções (cargos) — só equipe
                          if (staffEdit)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('Funções (cargos)',
                                      style: TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w600,
                                          color: ThemeCleanPremium.onSurface)),
                                  const SizedBox(height: 6),
                                  Text(
                                      'O membro pode ter várias funções. A primeira define o nível de acesso no sistema. Cargos cadastrados em Pessoas > Cargos.',
                                      style: TextStyle(
                                          fontSize: 12,
                                          color: ThemeCleanPremium
                                              .onSurfaceVariant)),
                                  const SizedBox(height: 8),
                                  FutureBuilder<
                                      List<({String key, String label})>>(
                                    future: _loadCargosForMember(),
                                    builder: (ctx, snap) {
                                      final cargos = snap.data ??
                                          _funcoesList
                                              .map((k) => (
                                                    key: k,
                                                    label: _funcaoLabel(k)
                                                  ))
                                              .toList();
                                      return ValueListenableBuilder<
                                          List<String>>(
                                        valueListenable: funcoesNotifier,
                                        builder: (_, selList, __) => Wrap(
                                          spacing: 8,
                                          runSpacing: 6,
                                          children: cargos.map((c) {
                                            final selected =
                                                selList.contains(c.key);
                                            final col = Color(
                                                ChurchRolePermissions
                                                    .badgeColorForKey(c.key));
                                            return FilterChip(
                                              label: Text(c.label),
                                              selected: selected,
                                              checkmarkColor: Colors.white,
                                              labelStyle: TextStyle(
                                                color: selected
                                                    ? Colors.white
                                                    : ThemeCleanPremium
                                                        .onSurface,
                                                fontWeight: selected
                                                    ? FontWeight.w700
                                                    : FontWeight.w500,
                                                fontSize: 13,
                                              ),
                                              selectedColor: col,
                                              backgroundColor:
                                                  col.withValues(alpha: 0.12),
                                              side: BorderSide(
                                                  color: col.withValues(
                                                      alpha: 0.35)),
                                              onSelected: (sel) {
                                                setDlg(() {
                                                  final list =
                                                      List<String>.from(
                                                          funcoesNotifier
                                                              .value);
                                                  if (sel) {
                                                    if (!list.contains(c.key))
                                                      list.add(c.key);
                                                  } else {
                                                    list.remove(c.key);
                                                    if (list.isEmpty) {
                                                      list.add('membro');
                                                    }
                                                  }
                                                  funcoesNotifier.value = list;
                                                });
                                              },
                                            );
                                          }).toList(),
                                        ),
                                      );
                                    },
                                  ),
                                ],
                              ),
                            ),
                          if (staffEdit)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: Material(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(16),
                                child: ListTile(
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(16),
                                    side: BorderSide(
                                        color: const Color(0xFFE2E8F0)),
                                  ),
                                  leading: Icon(Icons.church_rounded,
                                      color: ThemeCleanPremium.primary),
                                  title: const Text('Data de consagração'),
                                  subtitle: Text(
                                    removeConsagracao
                                        ? 'Será removida ao salvar'
                                        : (dataConsagracao == null
                                            ? 'Opcional — pastores, diáconos, presbíteros…'
                                            : DateFormat('dd/MM/yyyy')
                                                .format(dataConsagracao!)),
                                    style: TextStyle(
                                        fontSize: 13,
                                        color: Colors.grey.shade700),
                                  ),
                                  trailing: Wrap(
                                    spacing: 4,
                                    children: [
                                      TextButton(
                                        onPressed: () async {
                                          final p = await showDatePicker(
                                            context: ctx,
                                            firstDate: DateTime(1940),
                                            lastDate: DateTime.now().add(
                                                const Duration(days: 365 * 3)),
                                            initialDate: dataConsagracao ??
                                                DateTime.now(),
                                          );
                                          if (p != null) {
                                            setDlg(() {
                                              dataConsagracao = p;
                                              removeConsagracao = false;
                                            });
                                          }
                                        },
                                        child: Text(dataConsagracao == null
                                            ? 'Definir'
                                            : 'Alterar'),
                                      ),
                                      if (dataConsagracao != null ||
                                          removeConsagracao)
                                        TextButton(
                                          onPressed: () => setDlg(() {
                                            dataConsagracao = null;
                                            removeConsagracao = true;
                                          }),
                                          child: const Text('Limpar'),
                                        ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          // Senha (opcional) — só equipe (membro troca senha em Configurações > Meu cadastro)
                          if (staffEdit)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  TextField(
                                    controller: passwordCtrl,
                                    obscureText: true,
                                    decoration: InputDecoration(
                                      labelText: 'Senha (opcional)',
                                      hintText:
                                          'Deixe em branco para não alterar',
                                      border: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(
                                              ThemeCleanPremium.radiusSm)),
                                      prefixIcon: const Icon(
                                          Icons.lock_outline_rounded),
                                    ),
                                    autofillHints: const [
                                      AutofillHints.newPassword
                                    ],
                                  ),
                                  if (d['authUid'] != null &&
                                      (d['authUid']?.toString().trim() ?? '')
                                          .isNotEmpty)
                                    Padding(
                                      padding: const EdgeInsets.only(top: 8),
                                      child: TextButton.icon(
                                        onPressed: () async {
                                          final confirm =
                                              await showDialog<bool>(
                                            context: ctx,
                                            builder: (c) => AlertDialog(
                                              shape: RoundedRectangleBorder(
                                                  borderRadius:
                                                      BorderRadius.circular(
                                                          ThemeCleanPremium
                                                              .radiusLg)),
                                              title: const Text('Limpar senha'),
                                              content: const Text(
                                                'Será definida uma nova senha temporária. O membro poderá usar "Esqueci minha senha" no login para criar uma nova. Deseja continuar?',
                                              ),
                                              actions: [
                                                TextButton(
                                                    onPressed: () =>
                                                        Navigator.pop(c, false),
                                                    child:
                                                        const Text('Cancelar')),
                                                FilledButton(
                                                    onPressed: () =>
                                                        Navigator.pop(c, true),
                                                    child: const Text(
                                                        'Gerar senha temporária')),
                                              ],
                                            ),
                                          );
                                          if (confirm != true) return;
                                          final tempPassword = List.generate(
                                              10,
                                              (_) =>
                                                  'abcdefghijklmnopqrstuvwxyz0123456789'[
                                                      Random()
                                                          .nextInt(36)]).join();
                                          try {
                                            await FirebaseAuth
                                                .instance.currentUser
                                                ?.getIdToken(true);
                                            final functions =
                                                FirebaseFunctions.instanceFor(
                                                    region: 'us-central1');
                                            await functions
                                                .httpsCallable(
                                                    'setMemberPassword')
                                                .call({
                                              'tenantId': _effectiveTenantId,
                                              'memberId': member.id,
                                              'newPassword': tempPassword,
                                            });
                                            if (!ctx.mounted) return;
                                            setDlg(() => passwordCtrl.clear());
                                            ScaffoldMessenger.of(context)
                                                .showSnackBar(ThemeCleanPremium
                                                    .successSnackBar(
                                                        'Senha redefinida. Senha temporária: $tempPassword — avise o membro ou peça que use "Esqueci minha senha".'));
                                          } catch (e) {
                                            if (ctx.mounted)
                                              ScaffoldMessenger.of(context)
                                                  .showSnackBar(
                                                      ThemeCleanPremium
                                                          .feedbackSnackBar(
                                                              'Erro: $e'));
                                          }
                                        },
                                        icon: const Icon(
                                            Icons.lock_reset_rounded,
                                            size: 18),
                                        label: const Text(
                                            'Limpar senha (gerar temporária)'),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          if (staffEdit)
                            ValueListenableBuilder<List<String>>(
                              valueListenable: funcoesNotifier,
                              builder: (_, funcList, __) {
                                if (!memberNeedsAssinaturaFieldFromFuncoes(
                                    funcList)) {
                                  return const SizedBox.shrink();
                                }
                                return Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    const SizedBox(height: 8),
                                    Container(
                                      padding: const EdgeInsets.all(16),
                                      decoration: BoxDecoration(
                                        color: Colors.white,
                                        borderRadius: BorderRadius.circular(16),
                                        boxShadow:
                                            ThemeCleanPremium.softUiCardShadow,
                                        border: Border.all(
                                            color: const Color(0xFFF1F5F9)),
                                      ),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            children: [
                                              Container(
                                                padding:
                                                    const EdgeInsets.all(8),
                                                decoration: BoxDecoration(
                                                  color: ThemeCleanPremium
                                                      .primary
                                                      .withOpacity(0.08),
                                                  borderRadius:
                                                      BorderRadius.circular(12),
                                                ),
                                                child: Icon(Icons.draw_rounded,
                                                    size: 20,
                                                    color: ThemeCleanPremium
                                                        .primary),
                                              ),
                                              const SizedBox(width: 10),
                                              Expanded(
                                                child: Column(
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.start,
                                                  children: [
                                                    Text(
                                                      'Assinatura (carteirinha e documentos)',
                                                      style: TextStyle(
                                                          fontSize: 14,
                                                          fontWeight:
                                                              FontWeight.w800,
                                                          color:
                                                              ThemeCleanPremium
                                                                  .onSurface),
                                                    ),
                                                    const SizedBox(height: 2),
                                                    Text(
                                                      'Obrigatório para quem tem cargo além de membro: envie uma imagem ou gere assinatura digital.',
                                                      style: TextStyle(
                                                          fontSize: 12,
                                                          color: Colors
                                                              .grey.shade600,
                                                          height: 1.3),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 14),
                                          if (currentAssinaturaUrl.isNotEmpty &&
                                              !removeAssinatura &&
                                              newAssinaturaBytes == null)
                                            Padding(
                                              padding: const EdgeInsets.only(
                                                  bottom: 10),
                                              child: Row(
                                                children: [
                                                  ClipRRect(
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                            12),
                                                    child: SizedBox(
                                                      height: 56,
                                                      width: 140,
                                                      child:
                                                          ResilientNetworkImage(
                                                        imageUrl: sanitizeImageUrl(
                                                            currentAssinaturaUrl),
                                                        fit: BoxFit.contain,
                                                        height: 56,
                                                        width: 140,
                                                        errorWidget: const Icon(
                                                            Icons
                                                                .broken_image_rounded,
                                                            size: 40),
                                                      ),
                                                    ),
                                                  ),
                                                  const SizedBox(width: 12),
                                                  Expanded(
                                                    child: Text(
                                                        'Assinatura cadastrada',
                                                        style: TextStyle(
                                                            fontSize: 13,
                                                            color: Colors.grey
                                                                .shade600)),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          if (newAssinaturaBytes != null)
                                            Padding(
                                              padding: const EdgeInsets.only(
                                                  bottom: 10),
                                              child: Row(
                                                children: [
                                                  ClipRRect(
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                            12),
                                                    child: Image.memory(
                                                        newAssinaturaBytes!,
                                                        height: 56,
                                                        width: 140,
                                                        fit: BoxFit.contain),
                                                  ),
                                                  const SizedBox(width: 12),
                                                  Expanded(
                                                    child: Text(
                                                        'Nova assinatura (salve para aplicar)',
                                                        style: TextStyle(
                                                            fontSize: 13,
                                                            color:
                                                                ThemeCleanPremium
                                                                    .primary,
                                                            fontWeight:
                                                                FontWeight
                                                                    .w600)),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          Wrap(
                                            spacing: 8,
                                            runSpacing: 8,
                                            children: [
                                              OutlinedButton.icon(
                                                onPressed: () async {
                                                  final picker = ImagePicker();
                                                  final file =
                                                      await picker.pickImage(
                                                          source: ImageSource
                                                              .gallery,
                                                          maxWidth: 600,
                                                          imageQuality: 90);
                                                  if (file == null ||
                                                      !ctx.mounted) return;
                                                  final bytes =
                                                      await file.readAsBytes();
                                                  setDlg(() {
                                                    newAssinaturaBytes = bytes;
                                                    removeAssinatura = false;
                                                  });
                                                },
                                                icon: const Icon(
                                                    Icons.upload_file_rounded,
                                                    size: 18),
                                                label: const Text(
                                                    'Imagem da assinatura'),
                                              ),
                                              OutlinedButton.icon(
                                                onPressed: () async {
                                                  WidgetsBinding.instance
                                                      .addPostFrameCallback(
                                                          (_) async {
                                                    final boundary =
                                                        keyAssinaturaPreview
                                                                .currentContext
                                                                ?.findRenderObject()
                                                            as RenderRepaintBoundary?;
                                                    if (boundary == null) {
                                                      if (ctx.mounted) {
                                                        ScaffoldMessenger.of(
                                                                context)
                                                            .showSnackBar(
                                                                ThemeCleanPremium
                                                                    .successSnackBar(
                                                                        'Aguarde o preview e tente novamente.'));
                                                      }
                                                      return;
                                                    }
                                                    final image =
                                                        await boundary.toImage(
                                                            pixelRatio: 2.0);
                                                    final byteData =
                                                        await image.toByteData(
                                                            format:
                                                                ImageByteFormat
                                                                    .png);
                                                    if (byteData != null &&
                                                        ctx.mounted) {
                                                      setDlg(() {
                                                        newAssinaturaBytes =
                                                            byteData.buffer
                                                                .asUint8List();
                                                        removeAssinatura =
                                                            false;
                                                      });
                                                    }
                                                  });
                                                },
                                                icon: const Icon(
                                                    Icons.auto_fix_high_rounded,
                                                    size: 18),
                                                label: const Text(
                                                    'Assinatura digital'),
                                              ),
                                              if ((currentAssinaturaUrl
                                                          .isNotEmpty ||
                                                      newAssinaturaBytes !=
                                                          null) &&
                                                  !removeAssinatura)
                                                TextButton.icon(
                                                  onPressed: () => setDlg(() {
                                                    newAssinaturaBytes = null;
                                                    removeAssinatura = true;
                                                  }),
                                                  icon: const Icon(
                                                      Icons
                                                          .delete_outline_rounded,
                                                      size: 18),
                                                  label: const Text('Remover'),
                                                ),
                                            ],
                                          ),
                                          RepaintBoundary(
                                            key: keyAssinaturaPreview,
                                            child: Container(
                                              margin: const EdgeInsets.only(
                                                  top: 14),
                                              padding: const EdgeInsets.all(14),
                                              decoration: BoxDecoration(
                                                color: const Color(0xFFF8FAFC),
                                                borderRadius:
                                                    BorderRadius.circular(16),
                                                border: Border.all(
                                                    color:
                                                        Colors.grey.shade200),
                                              ),
                                              child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  Text(
                                                      'Preview (assinatura digital)',
                                                      style: TextStyle(
                                                          fontSize: 11,
                                                          fontWeight:
                                                              FontWeight.w600,
                                                          color: Colors
                                                              .grey.shade600)),
                                                  const SizedBox(height: 8),
                                                  Text(memberName,
                                                      style: const TextStyle(
                                                          fontSize: 14,
                                                          fontWeight:
                                                              FontWeight.w800)),
                                                  Text(
                                                      'CPF: ${_formatCpf(cpfCtrl.text)}',
                                                      style: TextStyle(
                                                          fontSize: 12,
                                                          color: Colors
                                                              .grey.shade700)),
                                                  Text(
                                                    _funcaoLabel(
                                                        funcList.isNotEmpty
                                                            ? funcList.first
                                                            : 'membro'),
                                                    style: TextStyle(
                                                        fontSize: 12,
                                                        color: Colors
                                                            .grey.shade700),
                                                  ),
                                                  Text(
                                                    'Data/hora: ${DateFormat('dd/MM/yyyy HH:mm').format(DateTime.now())}',
                                                    style: TextStyle(
                                                        fontSize: 11,
                                                        color: Colors
                                                            .grey.shade500),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(height: 12),
                                  ],
                                );
                              },
                            ),
                          Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: DropdownButtonFormField<String>(
                              value: estadoCivilSelected,
                              decoration: InputDecoration(
                                labelText: 'Estado Civil',
                                border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(
                                        ThemeCleanPremium.radiusSm)),
                                prefixIcon: const Icon(Icons.favorite_rounded),
                              ),
                              items: estadoCivilOptions
                                  .map((s) => DropdownMenuItem(
                                      value: s, child: Text(s)))
                                  .toList(),
                              onChanged: (v) => setDlg(() =>
                                  estadoCivilSelected =
                                      (v ?? estadoCivilSelected)),
                            ),
                          ),
                          _EditField(
                              controller: escolaridadeCtrl,
                              label: 'Escolaridade',
                              icon: Icons.school_rounded),
                          _EditField(
                              controller: profissaoCtrl,
                              label: 'Profissão',
                              icon: Icons.work_outline_rounded),
                          Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(
                                  ThemeCleanPremium.radiusSm),
                              onTap: () async {
                                final picked = await showDatePicker(
                                  context: ctx,
                                  initialDate: dataBatismo ?? DateTime(2000),
                                  firstDate: DateTime(1920),
                                  lastDate: DateTime.now(),
                                );
                                if (picked != null) {
                                  setDlg(() => dataBatismo = picked);
                                }
                              },
                              child: InputDecorator(
                                decoration: InputDecoration(
                                  labelText: 'Data de batismo (opcional)',
                                  border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(
                                          ThemeCleanPremium.radiusSm)),
                                  prefixIcon:
                                      const Icon(Icons.water_drop_rounded),
                                ),
                                child: Text(
                                  dataBatismo != null
                                      ? _fmtDate(dataBatismo!)
                                      : 'Selecionar…',
                                  style: TextStyle(
                                    color: dataBatismo != null
                                        ? null
                                        : Colors.grey.shade500,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          if (dataBatismo != null)
                            Align(
                              alignment: Alignment.centerRight,
                              child: TextButton(
                                onPressed: () =>
                                    setDlg(() => dataBatismo = null),
                                child: const Text('Limpar batismo'),
                              ),
                            ),
                          _EditField(
                              controller: conjugeCtrl,
                              label: 'Cônjuge',
                              icon: Icons.people_rounded),
                          Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Expanded(
                                  child: TextField(
                                    controller: cepCtrl,
                                    keyboardType: TextInputType.number,
                                    decoration: InputDecoration(
                                      labelText: 'CEP',
                                      border: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(
                                              ThemeCleanPremium.radiusSm)),
                                      prefixIcon:
                                          const Icon(Icons.pin_drop_rounded),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                SizedBox(
                                  width: 140,
                                  height: 48,
                                  child: OutlinedButton.icon(
                                    onPressed: _loadingCep
                                        ? null
                                        : () async {
                                            final cepDigits = cepCtrl.text
                                                .trim()
                                                .replaceAll(
                                                    RegExp(r'[^0-9]'), '');
                                            if (cepDigits.length != 8) {
                                              ScaffoldMessenger.of(context)
                                                  .showSnackBar(
                                                SnackBar(
                                                  content: const Text(
                                                    'Informe um CEP válido (8 dígitos).',
                                                    style: TextStyle(
                                                        color: Colors.white,
                                                        fontWeight:
                                                            FontWeight.w600),
                                                  ),
                                                  backgroundColor:
                                                      ThemeCleanPremium.error,
                                                  behavior:
                                                      SnackBarBehavior.floating,
                                                  shape: RoundedRectangleBorder(
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                              ThemeCleanPremium
                                                                  .radiusSm)),
                                                ),
                                              );
                                              return;
                                            }
                                            setDlg(() => _loadingCep = true);
                                            try {
                                              final resultCep =
                                                  await fetchCep(cepDigits);
                                              if (!mounted) return;
                                              if (!resultCep.ok) {
                                                ScaffoldMessenger.of(context)
                                                    .showSnackBar(
                                                  ThemeCleanPremium
                                                      .feedbackSnackBar(
                                                          'CEP não encontrado. Verifique e tente novamente.'),
                                                );
                                                return;
                                              }
                                              setDlg(() {
                                                _loadingCep = false;
                                                cepCtrl.text =
                                                    (resultCep.cep ?? cepDigits)
                                                        .toString();
                                                enderecoCtrl.text =
                                                    resultCep.logradouro ?? '';
                                                bairroCtrl.text =
                                                    resultCep.bairro ?? '';
                                                cidadeCtrl.text =
                                                    resultCep.localidade ?? '';
                                                estadoCtrl.text =
                                                    resultCep.uf ?? '';
                                              });
                                              if (mounted) {
                                                ScaffoldMessenger.of(context)
                                                    .showSnackBar(
                                                  ThemeCleanPremium.successSnackBar(
                                                      'Endereço preenchido automaticamente pelo CEP.'),
                                                );
                                              }
                                            } catch (e) {
                                              if (mounted) {
                                                ScaffoldMessenger.of(context)
                                                    .showSnackBar(
                                                  ThemeCleanPremium
                                                      .feedbackSnackBar(
                                                          'Erro ao buscar CEP: $e'),
                                                );
                                              }
                                            } finally {
                                              if (mounted)
                                                setDlg(
                                                    () => _loadingCep = false);
                                            }
                                          },
                                    icon: const Icon(Icons.my_location_rounded,
                                        size: 18),
                                    label: Text(
                                      _loadingCep ? 'Buscando...' : 'Localizar',
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                          fontWeight: FontWeight.w600),
                                    ),
                                    style: OutlinedButton.styleFrom(
                                      backgroundColor: Colors.white,
                                      foregroundColor:
                                          ThemeCleanPremium.primary,
                                      side: BorderSide(
                                          color: ThemeCleanPremium.primary
                                              .withOpacity(0.25)),
                                      shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(
                                              ThemeCleanPremium.radiusSm)),
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 12),
                                      minimumSize: const Size(120, 48),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          _EditField(
                              controller: enderecoCtrl,
                              label: 'Endereço',
                              icon: Icons.home_rounded),
                          _EditField(
                              controller: quadraLoteNumeroCtrl,
                              label: 'Quadra, Lote e Número',
                              icon: Icons.apartment_rounded),
                          _EditField(
                              controller: bairroCtrl,
                              label: 'Bairro',
                              icon: Icons.location_city_rounded),
                          _EditField(
                              controller: cidadeCtrl,
                              label: 'Cidade',
                              icon: Icons.map_rounded),
                          _EditField(
                              controller: estadoCtrl,
                              label: 'Estado',
                              icon: Icons.flag_rounded),
                          if (staffEdit &&
                              funcoesNotifier.value
                                  .map((e) => e.toString().toLowerCase())
                                  .contains('membro')) ...[
                            const SizedBox(height: 12),
                            Container(
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF8FAFC),
                                borderRadius: BorderRadius.circular(16),
                                border:
                                    Border.all(color: const Color(0xFFE2E8F0)),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Row(
                                    children: [
                                      Icon(Icons.admin_panel_settings_rounded,
                                          size: 20,
                                          color: ThemeCleanPremium.primary),
                                      const SizedBox(width: 8),
                                      Text(
                                        'Módulos extras (só papel membro)',
                                        style: TextStyle(
                                            fontSize: 14,
                                            fontWeight: FontWeight.w800,
                                            color: ThemeCleanPremium.onSurface),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'Por padrão o membro não vê lista de membros, financeiro, patrimônio nem fornecedores. Libere abaixo se fizer sentido para este cadastro.',
                                    style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.grey.shade600,
                                        height: 1.35),
                                  ),
                                  const SizedBox(height: 10),
                                  CheckboxListTile(
                                    value: podeVerFinanceiro,
                                    onChanged: (v) => setDlg(() {
                                      podeVerFinanceiro = v ?? false;
                                    }),
                                    title: Text('Liberar Financeiro',
                                        style: TextStyle(
                                            fontSize: 14,
                                            fontWeight: FontWeight.w600)),
                                    subtitle: const Text(
                                        'Módulo Financeiro e relatórios financeiros.',
                                        style: TextStyle(fontSize: 12)),
                                    controlAffinity:
                                        ListTileControlAffinity.leading,
                                    contentPadding: EdgeInsets.zero,
                                    activeColor: ThemeCleanPremium.primary,
                                  ),
                                  CheckboxListTile(
                                    value: podeVerPatrimonio,
                                    onChanged: (v) => setDlg(() {
                                      podeVerPatrimonio = v ?? false;
                                    }),
                                    title: Text('Liberar Patrimônio',
                                        style: TextStyle(
                                            fontSize: 14,
                                            fontWeight: FontWeight.w600)),
                                    subtitle: const Text(
                                        'Inventário e bens da igreja.',
                                        style: TextStyle(fontSize: 12)),
                                    controlAffinity:
                                        ListTileControlAffinity.leading,
                                    contentPadding: EdgeInsets.zero,
                                    activeColor: ThemeCleanPremium.primary,
                                  ),
                                  CheckboxListTile(
                                    value: podeVerFornecedores,
                                    onChanged: (v) => setDlg(() {
                                      podeVerFornecedores = v ?? false;
                                    }),
                                    title: Text('Liberar Fornecedores',
                                        style: TextStyle(
                                            fontSize: 14,
                                            fontWeight: FontWeight.w600)),
                                    subtitle: const Text(
                                        'Cadastro de fornecedores/prestadores e hub vinculado ao financeiro.',
                                        style: TextStyle(fontSize: 12)),
                                    controlAffinity:
                                        ListTileControlAffinity.leading,
                                    contentPadding: EdgeInsets.zero,
                                    activeColor: ThemeCleanPremium.primary,
                                  ),
                                  CheckboxListTile(
                                    value: podeEmitirRelatoriosCompletos,
                                    onChanged: (v) => setDlg(() {
                                      podeEmitirRelatoriosCompletos =
                                          v ?? false;
                                    }),
                                    title: Text('Relatórios completos (PDF)',
                                        style: TextStyle(
                                            fontSize: 14,
                                            fontWeight: FontWeight.w600)),
                                    subtitle: const Text(
                                        'Membros, aniversariantes e outros PDFs no módulo Relatórios. Sem isto, só Relatório de Eventos.',
                                        style: TextStyle(fontSize: 12)),
                                    controlAffinity:
                                        ListTileControlAffinity.leading,
                                    contentPadding: EdgeInsets.zero,
                                    activeColor: ThemeCleanPremium.primary,
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                  // Footer
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
                    child: Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                              onPressed: () => Navigator.pop(ctx, null),
                              child: const Text('Cancelar')),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: FilledButton.icon(
                            onPressed: () {
                              final sel =
                                  List<String>.from(funcoesNotifier.value);
                              final funcaoSalvar =
                                  sel.isNotEmpty ? sel.first : 'membro';
                              Navigator.pop(ctx, {
                                'saved': true,
                                'selfOnly': selfOnly,
                                'funcao': funcaoSalvar,
                                'funcoesSelecionadas': sel,
                                'dataConsagracao': dataConsagracao,
                                'removeConsagracao': removeConsagracao,
                                'name': nameCtrl.text.trim(),
                                'email': emailCtrl.text.trim(),
                                'phone': phoneCtrl.text.trim(),
                                'cpf':
                                    cpfCtrl.text.replaceAll(RegExp(r'\D'), ''),
                                'sexo': sexo,
                                'status': status,
                                'estadoCivil': estadoCivilSelected.trim(),
                                'conjuge': conjugeCtrl.text.trim(),
                                'escolaridade': escolaridadeCtrl.text.trim(),
                                'profissao': profissaoCtrl.text.trim(),
                                'dataBatismo': dataBatismo,
                                'filiacaoPai': filiacaoPaiCtrl.text.trim(),
                                'filiacaoMae': filiacaoMaeCtrl.text.trim(),
                                'endereco': enderecoCtrl.text.trim(),
                                'bairro': bairroCtrl.text.trim(),
                                'cidade': cidadeCtrl.text.trim(),
                                'cep': cepCtrl.text.trim(),
                                'quadraLoteNumero':
                                    quadraLoteNumeroCtrl.text.trim(),
                                'estado': estadoCtrl.text.trim(),
                                'nascimento': nascimento,
                                'password': passwordCtrl.text.trim(),
                                'newTenantId': selectedTenantIdForEdit,
                                'podeVerFinanceiro': podeVerFinanceiro,
                                'podeVerPatrimonio': podeVerPatrimonio,
                                'podeVerFornecedores': podeVerFornecedores,
                                'podeEmitirRelatoriosCompletos':
                                    podeEmitirRelatoriosCompletos,
                              });
                            },
                            icon: const Icon(Icons.save_rounded),
                            label: const Text('Salvar'),
                            style: FilledButton.styleFrom(
                                backgroundColor: ThemeCleanPremium.primary),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );

    if (result == null || result['saved'] != true || !mounted) return;

    _applyOptimisticMemberEditOverlay(
        member.id, Map<String, dynamic>.from(result));

    /// Membro editando só a si: não altera cargo, status, CPF, senha de terceiros nem `users.role`.
    final selfOnlySave = result['selfOnly'] == true;
    if (selfOnlySave) {
      try {
        final targetTenantId = _tenantIdForMemberData(member.data);
        String? photoUrl;
        String? photoStoragePath;
        final pickedPhotoSelf = newPhoto;
        String? previousPhotoUrlForEvict;
        if (pickedPhotoSelf != null) {
          try {
            previousPhotoUrlForEvict =
                sanitizeImageUrl(imageUrlFromMap(member.data));
            final rawBytes =
                newPhotoBytes ?? await pickedPhotoSelf.readAsBytes();
            final compressedBytes =
                await ImageHelper.compressMemberProfileForUpload(rawBytes);
            if (mounted) {
              setState(() {
                _optimisticProfilePhotoBytes[member.id] = compressedBytes;
              });
              var nomeFoto = (result['name'] ?? '').toString().trim();
              if (nomeFoto.isEmpty) {
                nomeFoto =
                    (member.data['NOME_COMPLETO'] ?? '').toString().trim();
              }
              final authUidFoto =
                  (member.data['authUid'] ?? '').toString().trim();
              final photoPath = FirebaseStorageService.memberProfilePhotoPath(
                tenantId: targetTenantId,
                memberDocId: member.id,
                nomeCompleto: nomeFoto,
                authUid: authUidFoto.isEmpty ? null : authUidFoto,
              );
              GlobalUploadProgress.instance.start('A enviar…');
              try {
                final upload = await MediaUploadService.uploadBytesDetailed(
                  storagePath: photoPath,
                  bytes: compressedBytes,
                  contentType: bytesLookLikeWebp(compressedBytes)
                      ? 'image/webp'
                      : 'image/jpeg',
                  skipClientPrepare: true,
                  onProgress: GlobalUploadProgress.instance.update,
                  deleteFirebaseDownloadUrlsBefore: () {
                    final prev = previousPhotoUrlForEvict;
                    if (prev == null || prev.isEmpty) return null;
                    return <String>[prev];
                  }(),
                  useOfflineQueue: false,
                );
                photoUrl = upload.downloadUrl;
                photoStoragePath = upload.storagePath;
                FirebaseStorageCleanupService
                    .scheduleCleanupAfterMemberProfilePhotoUpload(
                  tenantId: targetTenantId,
                  memberId: FirebaseStorageService.memberProfileStorageFolderId(
                    member.id,
                    authUidFoto.isEmpty ? null : authUidFoto,
                  ),
                );
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                      ThemeCleanPremium.successSnackBar('Foto enviada.'));
                }
              } finally {
                GlobalUploadProgress.instance.end();
              }
            }
          } catch (e) {
            GlobalUploadProgress.instance.end();
            if (mounted) {
              setState(() {
                _optimisticProfilePhotoBytes.remove(member.id);
              });
              ScaffoldMessenger.of(context).showSnackBar(
                  ThemeCleanPremium.feedbackSnackBar(
                      'Erro ao enviar foto: $e'));
            }
          }
        }

        final nascRaw = result['nascimento'];
        DateTime? nascSaved;
        if (nascRaw is DateTime) {
          nascSaved = nascRaw;
        } else {
          nascSaved = nascimento;
        }
        int? idade;
        var faixa = '';
        if (nascSaved != null) {
          idade = _idadeFromBirthMemberEdit(nascSaved);
          faixa = _faixaEtariaFromIdadeMemberEdit(idade);
        }

        final updates = <String, dynamic>{
          'NOME_COMPLETO': (result['name'] ?? '').toString().trim(),
          'EMAIL': (result['email'] ?? '').toString().trim(),
          'TELEFONES': (result['phone'] ?? '').toString().trim(),
          'SEXO': (result['sexo'] ?? '').toString().trim(),
          'ESTADO_CIVIL': _normalizeEstadoCivilValue(
              (result['estadoCivil'] ?? '').toString().trim()),
          'NOME_CONJUGE': (result['conjuge'] ?? '').toString().trim(),
          'ESCOLARIDADE': (result['escolaridade'] ?? '').toString().trim(),
          'PROFISSAO': (result['profissao'] ?? '').toString().trim(),
          'FILIACAO_PAI': (result['filiacaoPai'] ?? '').toString().trim(),
          'FILIACAO_MAE': (result['filiacaoMae'] ?? '').toString().trim(),
          'FILIACAO': _buildFiliacaoLegado(
            (result['filiacaoPai'] ?? '').toString().trim(),
            (result['filiacaoMae'] ?? '').toString().trim(),
          ),
          'ENDERECO': (result['endereco'] ?? '').toString().trim(),
          'QUADRA_LOTE_NUMERO':
              (result['quadraLoteNumero'] ?? '').toString().trim(),
          'BAIRRO': (result['bairro'] ?? '').toString().trim(),
          'CIDADE': (result['cidade'] ?? '').toString().trim(),
          'CEP': (result['cep'] ?? '').toString().trim(),
          'ESTADO': (result['estado'] ?? '').toString().trim(),
          'ATUALIZADO_EM': FieldValue.serverTimestamp(),
        };
        if (nascSaved != null) {
          updates['DATA_NASCIMENTO'] = Timestamp.fromDate(nascSaved);
          updates['IDADE'] = idade ?? 0;
          updates['FAIXA_ETARIA'] = faixa;
        }
        if (result['dataBatismo'] is DateTime) {
          updates['DATA_BATISMO'] =
              Timestamp.fromDate(result['dataBatismo'] as DateTime);
        }
        if (photoUrl != null) {
          updates['foto_url'] = photoUrl;
          updates['FOTO_URL_OU_ID'] = photoUrl;
          updates['fotoUrl'] = photoUrl;
          updates['photoURL'] = photoUrl;
          updates['photoVariants'] = FieldValue.delete();
          updates['fotoUrlCacheRevision'] =
              DateTime.now().millisecondsSinceEpoch;
        }
        if (photoStoragePath != null)
          updates['photoStoragePath'] = photoStoragePath;

        final linkage = await _getTenantLinkage();
        updates['alias'] = linkage['alias'];
        updates['slug'] = linkage['slug'];
        updates['tenantId'] = targetTenantId;

        final db = FirebaseFirestore.instance;
        var allIds =
            await TenantResolverService.getAllTenantIdsWithSameSlugOrAlias(
                targetTenantId);
        if (allIds.isEmpty) allIds = [targetTenantId];
        await Future.wait(
          allIds.map((tid) async {
            try {
              await db
                  .collection('igrejas')
                  .doc(tid)
                  .collection('membros')
                  .doc(member.id)
                  .set(updates, SetOptions(merge: true));
            } catch (_) {}
          }),
        );

        var authUidSelf = member.data['authUid']?.toString().trim();
        final newEmSelf = (updates['EMAIL'] ?? '').toString();
        final prevEmSelf = _str(member.data, 'EMAIL', 'email');
        var signedOutAfterEmail = false;
        if (prevEmSelf.trim().toLowerCase() != newEmSelf.trim().toLowerCase() &&
            newEmSelf.trim().contains('@')) {
          final out = await _syncAuthAfterEmailChangeIfNeeded(
            tenantId: targetTenantId,
            memberDocId: member.id,
            previousEmail: prevEmSelf,
            newEmail: newEmSelf,
          );
          signedOutAfterEmail = out.signedOut;
          final nuSelf = out.newAuthUid?.trim();
          if (nuSelf != null && nuSelf.isNotEmpty) {
            authUidSelf = nuSelf;
          }
        }

        if (!signedOutAfterEmail &&
            authUidSelf != null &&
            authUidSelf.isNotEmpty) {
          try {
            await FirebaseFirestore.instance
                .collection('users')
                .doc(authUidSelf)
                .set({
              'nome': updates['NOME_COMPLETO'],
              'displayName': updates['NOME_COMPLETO'],
              'email': updates['EMAIL'],
              if (photoUrl != null) 'foto_url': photoUrl,
              if (photoUrl != null) 'photoURL': photoUrl,
              if (photoUrl != null) 'fotoUrl': photoUrl,
              if (photoUrl != null) 'FOTO_URL_OU_ID': photoUrl,
              'updatedAt': FieldValue.serverTimestamp(),
            }, SetOptions(merge: true));
          } catch (_) {}
          final cpfKey = (widget.linkedCpf ?? _str(member.data, 'CPF', 'cpf'))
              .replaceAll(RegExp(r'\D'), '');
          if (cpfKey.length == 11) {
            try {
              await FirebaseFirestore.instance
                  .collection('igrejas')
                  .doc(targetTenantId)
                  .collection('usersIndex')
                  .doc(cpfKey)
                  .set({
                'name': updates['NOME_COMPLETO'],
                'nome': updates['NOME_COMPLETO'],
                'email': updates['EMAIL'],
                'updatedAt': FieldValue.serverTimestamp(),
              }, SetOptions(merge: true));
            } catch (_) {}
          }
        }

        if (mounted) {
          if (!signedOutAfterEmail) {
            ScaffoldMessenger.of(context).showSnackBar(
                ThemeCleanPremium.successSnackBar(
                    'Seu cadastro foi atualizado.'));
          }
          if (photoUrl != null) {
            final u = photoUrl;
            final mid = member.id;
            setState(() {
              _uploadedPhotoUrls[mid] = u;
              _optimisticProfilePhotoBytes.remove(mid);
            });
            Future.delayed(const Duration(seconds: 20), () {
              if (!mounted) return;
              setState(() => _uploadedPhotoUrls.remove(mid));
            });
            final ev = previousPhotoUrlForEvict;
            if (ev != null && ev.isNotEmpty) {
              unawaited(FirebaseStorageCleanupService.evictImageCaches(ev));
            }
            unawaited(FirebaseStorageCleanupService.evictImageCaches(u));
            final mergedSelf = Map<String, dynamic>.from(member.data)
              ..addAll(updates);
            _invalidateMemberPhotoCaches(targetTenantId, member.id, mergedSelf);
          }
          _refreshMembers(clearOptimisticMemberOverlayId: member.id);
        }
        return;
      } catch (e) {
        setState(() => _optimisticMemberOverlays.remove(member.id));
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
              ThemeCleanPremium.feedbackSnackBar('Erro ao salvar: $e'));
        }
        return;
      }
    }

    // Preservar exatamente as funções/cargos selecionados (sem normalizar para 'membro'), para cargos customizados da coleção cargos.
    final savedFuncoes = result['funcoesSelecionadas'] as List<dynamic>?;
    List<String> funcoesSelecionadasFinal = savedFuncoes != null
        ? savedFuncoes
            .map((e) => (e ?? '').toString().trim())
            .where((s) => s.isNotEmpty)
            .toList()
        : <String>['membro'];
    if (funcoesSelecionadasFinal.isEmpty) funcoesSelecionadasFinal = ['membro'];
    final savedFuncao = (result['funcao'] ?? '').toString().trim();
    final funcaoFinal = savedFuncao.isNotEmpty
        ? savedFuncao
        : (funcoesSelecionadasFinal.isNotEmpty
            ? funcoesSelecionadasFinal.first
            : 'membro');

    final newTenantIdRaw = (result['newTenantId'] ?? '').toString().trim();
    final previousTenantId = _tenantIdForMemberData(member.data).trim();
    // Quem vê o dropdown de igreja (_canTransferMember) precisa gravar a troca;
    // antes só `role == master` e comparava com o painel — ADM/ADMIN ignorados e falso negativo se tenant do membro ≠ painel.
    final isMoveToOtherChurch = _canTransferMember &&
        newTenantIdRaw.isNotEmpty &&
        newTenantIdRaw != previousTenantId;
    final targetTenantId =
        isMoveToOtherChurch ? newTenantIdRaw : previousTenantId;

    var permBaseFinal = funcaoFinal.toLowerCase();
    try {
      permBaseFinal = await ChurchFuncoesControleService.resolvePermissionBase(
          targetTenantId, funcaoFinal);
    } catch (_) {}

    // Upload foto se necessário (web e app) — usa igreja de destino se estiver transferindo
    String? photoUrl;
    String? photoStoragePath;
    final pickedPhoto = newPhoto;
    String? previousPhotoUrlForEvictGestor;
    if (pickedPhoto != null) {
      try {
        previousPhotoUrlForEvictGestor =
            sanitizeImageUrl(imageUrlFromMap(member.data));
        final rawBytes = await pickedPhoto.readAsBytes();
        final compressedBytes =
            await ImageHelper.compressMemberProfileForUpload(rawBytes);
        if (mounted) {
          setState(() {
            _optimisticProfilePhotoBytes[member.id] = compressedBytes;
          });
          var nomeFotoGestor = (result['name'] ?? '').toString().trim();
          if (nomeFotoGestor.isEmpty) {
            nomeFotoGestor =
                (member.data['NOME_COMPLETO'] ?? '').toString().trim();
          }
          final authUidGestor =
              (member.data['authUid'] ?? '').toString().trim();
          final photoPath = FirebaseStorageService.memberProfilePhotoPath(
            tenantId: targetTenantId,
            memberDocId: member.id,
            nomeCompleto: nomeFotoGestor,
            authUid: authUidGestor.isEmpty ? null : authUidGestor,
          );
          GlobalUploadProgress.instance.start('A enviar…');
          try {
            final upload = await MediaUploadService.uploadBytesDetailed(
              storagePath: photoPath,
              bytes: compressedBytes,
              contentType: bytesLookLikeWebp(compressedBytes)
                  ? 'image/webp'
                  : 'image/jpeg',
              skipClientPrepare: true,
              onProgress: GlobalUploadProgress.instance.update,
              deleteFirebaseDownloadUrlsBefore: () {
                final prev = previousPhotoUrlForEvictGestor;
                if (prev == null || prev.isEmpty) return null;
                return <String>[prev];
              }(),
              useOfflineQueue: false,
            );
            photoUrl = upload.downloadUrl;
            photoStoragePath = upload.storagePath;
            FirebaseStorageCleanupService
                .scheduleCleanupAfterMemberProfilePhotoUpload(
              tenantId: targetTenantId,
              memberId: FirebaseStorageService.memberProfileStorageFolderId(
                member.id,
                authUidGestor.isEmpty ? null : authUidGestor,
              ),
            );
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                  ThemeCleanPremium.successSnackBar('Foto enviada.'));
            }
          } finally {
            GlobalUploadProgress.instance.end();
          }
        }
      } catch (e) {
        GlobalUploadProgress.instance.end();
        if (mounted) {
          setState(() {
            _optimisticProfilePhotoBytes.remove(member.id);
          });
          ScaffoldMessenger.of(context).showSnackBar(
              ThemeCleanPremium.feedbackSnackBar('Erro ao enviar foto: $e'));
        }
      }
    }

    final updates = <String, dynamic>{
      'NOME_COMPLETO': result['name'] ?? nameCtrl.text.trim(),
      'EMAIL': result['email'] ?? emailCtrl.text.trim(),
      'TELEFONES': result['phone'] ?? phoneCtrl.text.trim(),
      'CPF': (result['cpf'] ?? cpfCtrl.text)
          .toString()
          .replaceAll(RegExp(r'\D'), ''),
      'SEXO': result['sexo'] ?? sexo,
      'STATUS': result['status'] ?? status,
      'FUNCAO': funcaoFinal,
      'FUNCAO_PERMISSOES': permBaseFinal,
      'FUNCOES': funcoesSelecionadasFinal,
      'CARGO': funcaoFinal,
      'role': permBaseFinal,
      if (result['removeConsagracao'] == true)
        'DATA_CONSAGRACAO': FieldValue.delete()
      else if (result['dataConsagracao'] is DateTime)
        'DATA_CONSAGRACAO':
            Timestamp.fromDate(result['dataConsagracao'] as DateTime),
      'ESTADO_CIVIL': _normalizeEstadoCivilValue(
          (result['estadoCivil'] ?? estadoCivilSelected).toString().trim()),
      'NOME_CONJUGE': conjugeCtrl.text.trim(),
      'ESCOLARIDADE': escolaridadeCtrl.text.trim(),
      'PROFISSAO': profissaoCtrl.text.trim(),
      'FILIACAO_PAI': filiacaoPaiCtrl.text.trim(),
      'FILIACAO_MAE': filiacaoMaeCtrl.text.trim(),
      'FILIACAO': _buildFiliacaoLegado(
          filiacaoPaiCtrl.text.trim(), filiacaoMaeCtrl.text.trim()),
      'ENDERECO': enderecoCtrl.text.trim(),
      'QUADRA_LOTE_NUMERO': quadraLoteNumeroCtrl.text.trim(),
      'BAIRRO': bairroCtrl.text.trim(),
      'CIDADE': cidadeCtrl.text.trim(),
      'CEP': cepCtrl.text.trim(),
      'ESTADO': estadoCtrl.text.trim(),
      'ATUALIZADO_EM': FieldValue.serverTimestamp(),
    };
    if (result['dataBatismo'] is DateTime) {
      updates['DATA_BATISMO'] =
          Timestamp.fromDate(result['dataBatismo'] as DateTime);
    }
    if (permBaseFinal == 'membro') {
      if (result['podeVerFinanceiro'] != null) {
        updates['podeVerFinanceiro'] = result['podeVerFinanceiro'] == true;
      }
      if (result['podeVerPatrimonio'] != null) {
        updates['podeVerPatrimonio'] = result['podeVerPatrimonio'] == true;
      }
      if (result['podeVerFornecedores'] != null) {
        updates['podeVerFornecedores'] = result['podeVerFornecedores'] == true;
      }
      if (result['podeEmitirRelatoriosCompletos'] != null) {
        updates['podeEmitirRelatoriosCompletos'] =
            result['podeEmitirRelatoriosCompletos'] == true;
      }
    } else {
      updates['podeVerFinanceiro'] = false;
      updates['podeVerPatrimonio'] = false;
      updates['podeVerFornecedores'] = false;
      updates['podeEmitirRelatoriosCompletos'] = false;
    }
    if (nascimento != null)
      updates['DATA_NASCIMENTO'] = Timestamp.fromDate(nascimento!);
    if (photoUrl != null) {
      updates['foto_url'] = photoUrl;
      updates['FOTO_URL_OU_ID'] = photoUrl;
      updates['fotoUrl'] = photoUrl;
      updates['photoURL'] = photoUrl;
      updates['photoVariants'] = FieldValue.delete();
      updates['fotoUrlCacheRevision'] = DateTime.now().millisecondsSinceEpoch;
    }
    if (photoStoragePath != null)
      updates['photoStoragePath'] = photoStoragePath;
    if (newAssinaturaBytes != null) {
      try {
        ScaffoldMessenger.of(context).showSnackBar(
            ThemeCleanPremium.successSnackBar('Enviando assinatura...'));
        final oldAss = sanitizeImageUrl(
            (member.data['assinaturaUrl'] ?? '').toString().trim());
        if (oldAss.isNotEmpty) {
          await FirebaseStorageCleanupService.deleteObjectAtDownloadUrl(oldAss);
        }
        final ref = FirebaseStorage.instance
            .ref('igrejas/$targetTenantId/membros/${member.id}_assinatura.png');
        await ref.putData(
            newAssinaturaBytes!,
            SettableMetadata(
                contentType: 'image/png',
                cacheControl: 'public, max-age=31536000'));
        final url = await ref.getDownloadURL();
        updates['assinaturaUrl'] = url;
        if (mounted)
          ScaffoldMessenger.of(context).showSnackBar(
              ThemeCleanPremium.successSnackBar('Assinatura enviada.'));
      } catch (e) {
        if (mounted)
          ScaffoldMessenger.of(context).showSnackBar(
              ThemeCleanPremium.feedbackSnackBar(
                  'Erro ao enviar assinatura: $e'));
      }
    }
    if (removeAssinatura) {
      final uAss = sanitizeImageUrl(
          (member.data['assinaturaUrl'] ?? '').toString().trim());
      if (uAss.isNotEmpty) {
        await FirebaseStorageCleanupService.deleteObjectAtDownloadUrl(uAss);
      }
      updates['assinaturaUrl'] = FieldValue.delete();
    }
    final linkage = isMoveToOtherChurch
        ? await _getLinkageForTenant(targetTenantId)
        : await _getTenantLinkage();
    updates['alias'] = linkage['alias'];
    updates['slug'] = linkage['slug'];
    updates['tenantId'] = targetTenantId;

    try {
      final db = FirebaseFirestore.instance;
      List<String> allIds =
          await TenantResolverService.getAllTenantIdsWithSameSlugOrAlias(
              targetTenantId);
      if (allIds.isEmpty) allIds = [targetTenantId];
      await Future.wait(
        allIds.map((tid) async {
          try {
            await db
                .collection('igrejas')
                .doc(tid)
                .collection('membros')
                .doc(member.id)
                .set(updates, SetOptions(merge: true));
          } catch (_) {}
        }),
      );
      var authUid = member.data['authUid']?.toString().trim();
      final newEmGestor = (updates['EMAIL'] ?? '').toString();
      final prevEmGestor = _str(member.data, 'EMAIL', 'email');
      if (prevEmGestor.trim().toLowerCase() !=
              newEmGestor.trim().toLowerCase() &&
          newEmGestor.trim().contains('@')) {
        final out = await _syncAuthAfterEmailChangeIfNeeded(
          tenantId: targetTenantId,
          memberDocId: member.id,
          previousEmail: prevEmGestor,
          newEmail: newEmGestor,
        );
        final nu = out.newAuthUid?.trim();
        if (nu != null && nu.isNotEmpty) {
          authUid = nu;
        }
      }
      final rolesList = funcoesSelecionadasFinal
          .map((e) => e.toString().trim().toLowerCase())
          .where((s) => s.isNotEmpty)
          .toList();
      if (rolesList.isEmpty) rolesList.add('membro');
      if (authUid != null && authUid.isNotEmpty) {
        try {
          await FirebaseFirestore.instance
              .collection('users')
              .doc(authUid)
              .set({
            'role': permBaseFinal,
            'roles': rolesList,
            'nome': updates['NOME_COMPLETO'],
            'displayName': updates['NOME_COMPLETO'],
            'email': updates['EMAIL'],
            'funcao': funcaoFinal,
            'cargo': funcaoFinal,
            'FUNCOES': funcoesSelecionadasFinal,
            'CARGO': funcaoFinal,
            if (isMoveToOtherChurch) 'tenantId': targetTenantId,
            if (isMoveToOtherChurch) 'igrejaId': targetTenantId,
            if (photoUrl != null) 'foto_url': photoUrl,
            if (photoUrl != null) 'photoURL': photoUrl,
            if (photoUrl != null) 'fotoUrl': photoUrl,
            if (photoUrl != null) 'FOTO_URL_OU_ID': photoUrl,
          }, SetOptions(merge: true));
        } catch (_) {}
        try {
          final tenantUsersCol = FirebaseFirestore.instance
              .collection('igrejas')
              .doc(targetTenantId)
              .collection('users');
          await tenantUsersCol.doc(authUid).set({
            'role': permBaseFinal,
            'roles': rolesList,
            'nome': updates['NOME_COMPLETO'],
            'displayName': updates['NOME_COMPLETO'],
            'email': updates['EMAIL'],
            'funcao': funcaoFinal,
            'cargo': funcaoFinal,
            'FUNCOES': funcoesSelecionadasFinal,
            'CARGO': funcaoFinal,
            if (photoUrl != null) 'foto_url': photoUrl,
            if (photoUrl != null) 'photoURL': photoUrl,
            if (photoUrl != null) 'fotoUrl': photoUrl,
            if (photoUrl != null) 'FOTO_URL_OU_ID': photoUrl,
          }, SetOptions(merge: true));
        } catch (_) {}
        try {
          await FirebaseFunctions.instanceFor(region: 'us-central1')
              .httpsCallable('syncMemberRoleClaims')
              .call({
            'tenantId': targetTenantId,
            'memberId': member.id,
          });
        } catch (_) {}
        final curUid = FirebaseAuth.instance.currentUser?.uid;
        if (curUid != null && curUid == authUid) {
          try {
            await FirebaseAuth.instance.currentUser?.getIdToken(true);
          } catch (_) {}
        }
      }
      if (isMoveToOtherChurch) {
        final newResolved = await _resolvedFirestoreTenantIds(targetTenantId);
        final oldFromMember =
            await _resolvedFirestoreTenantIds(previousTenantId);
        final oldFromPanel =
            await _resolvedFirestoreTenantIds(_effectiveTenantId);
        final idsToRemove =
            {...oldFromMember, ...oldFromPanel}.difference(newResolved);
        for (final tid in idsToRemove) {
          try {
            await db
                .collection('igrejas')
                .doc(tid)
                .collection('membros')
                .doc(member.id)
                .delete();
          } catch (_) {}
          if (authUid != null && authUid.isNotEmpty) {
            try {
              await db
                  .collection('igrejas')
                  .doc(tid)
                  .collection('users')
                  .doc(authUid)
                  .delete();
            } catch (_) {}
          }
        }
        if (mounted)
          ScaffoldMessenger.of(context).showSnackBar(
              ThemeCleanPremium.successSnackBar(
                  'Membro transferido para a nova igreja. Atualize a lista.'));
      }
      final newPassword =
          (result['password'] ?? passwordCtrl.text).toString().trim();
      if (newPassword.length >= 6) {
        try {
          final functions =
              FirebaseFunctions.instanceFor(region: 'us-central1');
          final res = await functions.httpsCallable('setMemberPassword').call({
            'tenantId': targetTenantId,
            'memberId':
                (authUid != null && authUid.isNotEmpty) ? authUid : member.id,
            'newPassword': newPassword,
          });
          final map = res.data as Map?;
          final recreated = map?['recreated'] == true;
          if (mounted) {
            ScaffoldMessenger.of(context)
                .showSnackBar(ThemeCleanPremium.successSnackBar(
              recreated
                  ? 'Membro salvo. Conta de login recriada e senha definida.'
                  : 'Membro e senha atualizados!',
            ));
          }
        } on FirebaseFunctionsException catch (e) {
          if (mounted) {
            final detail = (e.message ?? '').trim();
            final short = detail.isNotEmpty
                ? detail
                : 'Não foi possível alterar a senha (${e.code}).';
            ScaffoldMessenger.of(context).showSnackBar(
                ThemeCleanPremium.feedbackSnackBar(
                    'Membro salvo, mas falha ao alterar senha: $short'));
          }
        } catch (_) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
                ThemeCleanPremium.feedbackSnackBar(
                    'Membro salvo, mas não foi possível alterar a senha.'));
          }
        }
      } else if (mounted && !isMoveToOtherChurch) {
        ScaffoldMessenger.of(context).showSnackBar(
            ThemeCleanPremium.successSnackBar('Membro atualizado!'));
      }
      if (photoUrl != null && mounted) {
        final u = photoUrl;
        final mid = member.id;
        setState(() {
          _uploadedPhotoUrls[mid] = u;
          _optimisticProfilePhotoBytes.remove(mid);
        });
        final mergedGestor = Map<String, dynamic>.from(member.data)
          ..addAll(updates);
        _invalidateMemberPhotoCaches(targetTenantId, mid, mergedGestor);
        Future.delayed(const Duration(seconds: 20), () {
          if (!mounted) return;
          setState(() => _uploadedPhotoUrls.remove(mid));
        });
        final ev = previousPhotoUrlForEvictGestor;
        if (ev != null && ev.isNotEmpty) {
          unawaited(FirebaseStorageCleanupService.evictImageCaches(ev));
        }
        unawaited(FirebaseStorageCleanupService.evictImageCaches(u));
      }
      if (mounted) {
        _refreshMembers(clearOptimisticMemberOverlayId: member.id);
      }
    } catch (e) {
      final msg = e.toString();
      if (mounted &&
          (msg.contains('INTERNAL ASSERTION') ||
              msg.contains('permission-denied'))) {
        try {
          final allIdsRetry =
              await TenantResolverService.getAllTenantIdsWithSameSlugOrAlias(
                  targetTenantId);
          final dbRetry = FirebaseFirestore.instance;
          await Future.wait(
            allIdsRetry.map((tid) async {
              try {
                await dbRetry
                    .collection('igrejas')
                    .doc(tid)
                    .collection('membros')
                    .doc(member.id)
                    .set(updates, SetOptions(merge: true));
              } catch (_) {}
            }),
          );
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
                ThemeCleanPremium.successSnackBar('Membro atualizado!'));
            if (photoUrl != null) {
              final u = photoUrl;
              final mid = member.id;
              setState(() {
                _uploadedPhotoUrls[mid] = u;
                _optimisticProfilePhotoBytes.remove(mid);
              });
              final mergedRetry = Map<String, dynamic>.from(member.data)
                ..addAll(updates);
              _invalidateMemberPhotoCaches(targetTenantId, mid, mergedRetry);
              Future.delayed(const Duration(seconds: 20), () {
                if (!mounted) return;
                setState(() => _uploadedPhotoUrls.remove(mid));
              });
            }
            _refreshMembers(clearOptimisticMemberOverlayId: member.id);
            final uidRetry = member.data['authUid']?.toString().trim() ?? '';
            if (uidRetry.isNotEmpty) {
              try {
                await FirebaseFunctions.instanceFor(region: 'us-central1')
                    .httpsCallable('syncMemberRoleClaims')
                    .call({
                  'tenantId': targetTenantId,
                  'memberId': member.id,
                });
              } catch (_) {}
              if (FirebaseAuth.instance.currentUser?.uid == uidRetry) {
                try {
                  await FirebaseAuth.instance.currentUser?.getIdToken(true);
                } catch (_) {}
              }
            }
          }
        } catch (e2) {
          if (mounted) {
            setState(() => _optimisticMemberOverlays.remove(member.id));
            ScaffoldMessenger.of(context).showSnackBar(
                ThemeCleanPremium.feedbackSnackBar('Erro ao salvar: $e2'));
          }
        }
      } else if (mounted) {
        setState(() => _optimisticMemberOverlays.remove(member.id));
        ScaffoldMessenger.of(context).showSnackBar(
            ThemeCleanPremium.feedbackSnackBar('Erro ao salvar: $e'));
      }
    }
  }

  /// Após gravar novo e-mail em [membros]: recria utilizador Auth (Cloud Function).
  /// [newAuthUid] quando a conta foi recriada (gestor deve usar ao atualizar `users/`).
  Future<({bool signedOut, String? newAuthUid})>
      _syncAuthAfterEmailChangeIfNeeded({
    required String tenantId,
    required String memberDocId,
    required String previousEmail,
    required String newEmail,
  }) async {
    final prev = previousEmail.trim().toLowerCase();
    final next = newEmail.trim().toLowerCase();
    if (prev == next || !next.contains('@')) {
      return (signedOut: false, newAuthUid: null);
    }
    try {
      await FirebaseAuth.instance.currentUser?.getIdToken(true);
      final res = await FirebaseFunctions.instanceFor(region: 'us-central1')
          .httpsCallable('recreateMemberAuthForNewEmail')
          .call({
        'tenantId': tenantId,
        'memberDocId': memberDocId,
      });
      final map = Map<String, dynamic>.from(res.data as Map? ?? {});
      if (map['skipped'] == true || map['unchanged'] == true) {
        return (signedOut: false, newAuthUid: null);
      }
      if (map['recreated'] == true) {
        final newUid = map['newUid']?.toString().trim();
        final prevUid = map['previousUid']?.toString();
        final cur = FirebaseAuth.instance.currentUser?.uid;
        if (prevUid != null &&
            prevUid.isNotEmpty &&
            cur != null &&
            cur == prevUid) {
          if (!mounted) {
            return (signedOut: true, newAuthUid: newUid);
          }
          ScaffoldMessenger.of(context).showSnackBar(
            ThemeCleanPremium.successSnackBar(
              'E-mail de login atualizado. Entre novamente com o novo e-mail e a senha 123456 (altere depois em Meu cadastro).',
            ),
          );
          await FirebaseAuth.instance.signOut();
          return (signedOut: true, newAuthUid: newUid);
        }
        if (mounted && (map['message'] ?? '').toString().trim().isNotEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            ThemeCleanPremium.successSnackBar(map['message'].toString()),
          );
        }
        return (signedOut: false, newAuthUid: newUid);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          ThemeCleanPremium.feedbackSnackBar(
            'E-mail salvo, mas não foi possível atualizar o login: $e',
          ),
        );
      }
    }
    return (signedOut: false, newAuthUid: null);
  }

  /// IDs de documento em `users/` costumam ser UID do Firebase Auth (28 chars alfanum.).
  static bool _docIdLooksLikeFirebaseAuthUid(String id) {
    final s = id.trim();
    if (s.length < 20 || s.length > 36) return false;
    return RegExp(r'^[a-zA-Z0-9]+$').hasMatch(s);
  }

  // ─── Excluir Membro ───────────────────────────────────────────────────────
  Future<void> _deleteMember(BuildContext context, _MemberDoc member) async {
    if (!_canManage) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          ThemeCleanPremium.feedbackSnackBar(
              'Apenas a equipe (gestores, pastores, secretários, tesoureiros…) pode excluir cadastros.'),
        );
      }
      return;
    }
    final name = _str(member.data, 'NOME_COMPLETO', 'nome', 'name');
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusLg)),
        title: const Row(
          children: [
            Icon(Icons.delete_outline_rounded,
                color: Color(0xFFDC2626), size: 28),
            SizedBox(width: 10),
            Text('Excluir Membro',
                style: TextStyle(fontWeight: FontWeight.w800)),
          ],
        ),
        content: Text(
            'Tem certeza que deseja excluir "$name"?\n\nEsta ação não pode ser desfeita.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFDC2626)),
            child: const Text('Excluir'),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;
    final mid = member.id.trim();
    setState(() => _optimisticRemovedMemberIds.add(mid));
    try {
      await FirebaseAuth.instance.currentUser?.getIdToken(true);
      await FirebaseStorageCleanupService.deleteMemberRelatedFiles(
        tenantId: _effectiveTenantId,
        memberId: mid,
        data: member.data,
      );
      final db = FirebaseFirestore.instance;
      final authUid = (member.data['authUid'] ?? member.data['auth_uid'] ?? '')
          .toString()
          .trim();
      final allTenantIds =
          await TenantResolverService.getAllTenantIdsWithSameSlugOrAlias(
              _effectiveTenantId);

      final refs = <DocumentReference<Map<String, dynamic>>>[];
      for (final tid in allTenantIds) {
        if (tid.isEmpty) continue;
        refs.add(
            db.collection('igrejas').doc(tid).collection('membros').doc(mid));
        refs.add(
            db.collection('igrejas').doc(tid).collection('members').doc(mid));
      }
      final userDocIds = <String>{};
      if (authUid.isNotEmpty) userDocIds.add(authUid);
      if (_docIdLooksLikeFirebaseAuthUid(mid)) userDocIds.add(mid);
      for (final uid in userDocIds) {
        refs.add(db.collection('users').doc(uid));
      }

      for (final r in refs) {
        try {
          await r.delete();
        } catch (e) {
          debugPrint('members_page._deleteMember skip ref=$r: $e');
        }
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            ThemeCleanPremium.successSnackBar('"$name" excluído.'));
        _refreshMembers(
          forceServer: true,
          clearOptimisticRemovedMemberId: mid,
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _optimisticRemovedMemberIds.remove(mid));
      ScaffoldMessenger.of(context).showSnackBar(
          ThemeCleanPremium.feedbackSnackBar('Erro ao excluir: $e'));
    }
  }

  // ─── Criar login para membro (cadastro público sem authUid) ─────────────────
  Future<void> _criarLoginMembro(
      BuildContext context, _MemberDoc member) async {
    if (!_canManage) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          ThemeCleanPremium.feedbackSnackBar(
              'Apenas a equipe pode criar login para outros membros.'),
        );
      }
      return;
    }
    try {
      ScaffoldMessenger.of(context)
          .showSnackBar(ThemeCleanPremium.successSnackBar('Criando login...'));
      final functions = FirebaseFunctions.instanceFor(region: 'us-central1');
      final res =
          await functions.httpsCallable('createMemberLoginFromPublic').call({
        'tenantId': _effectiveTenantId,
        'memberId': member.id,
      });
      final resMap = Map<String, dynamic>.from(res.data as Map? ?? {});
      final membroDocId =
          (resMap['membroFirestoreId'] ?? member.id).toString().trim();
      try {
        await functions.httpsCallable('setMemberPassword').call({
          'tenantId': _effectiveTenantId,
          'memberId': membroDocId,
          'newPassword': '123456',
        });
      } catch (_) {}
      final data = res.data as Map<dynamic, dynamic>?;
      final msg = (data?['message'] ??
              'Login criado. O membro pode acessar com o e-mail cadastrado e a senha padrão: 123456 (até aprovação do gestor). Se não lembrar a senha, use "Esqueci a senha" na tela de login para receber um link no e-mail.')
          .toString();
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(ThemeCleanPremium.successSnackBar(msg));
        _refreshMembers(forceServer: true);
      }
    } on FirebaseFunctionsException catch (e) {
      if (mounted) {
        final msg = e.code == 'failed-precondition'
            ? (e.message ??
                'Este cadastro não é de formulário público. Use "Redefinir senha" se o membro já tiver login.')
            : 'Erro: ${e.message ?? e.code}';
        ScaffoldMessenger.of(context)
            .showSnackBar(ThemeCleanPremium.feedbackSnackBar(msg));
      }
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
            ThemeCleanPremium.feedbackSnackBar('Erro ao criar login: $e'));
    }
  }

  // ─── Redefinir senha (gestor) ───────────────────────────────────────────────
  Future<void> _redefinirSenhaMembro(
      BuildContext context, _MemberDoc member) async {
    if (!_canManage) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          ThemeCleanPremium.feedbackSnackBar(
              'Para alterar a própria senha, use Configurações > Meu cadastro.'),
        );
      }
      return;
    }
    if ((member.data['authUid'] ?? '').toString().trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(ThemeCleanPremium.successSnackBar(
          'Este membro ainda não tem login. Use "Gerar senha / login" primeiro.'));
      return;
    }
    final newPasswordCtrl = TextEditingController();
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusLg)),
        title: const Row(children: [
          Icon(Icons.lock_reset_rounded, color: Colors.orange, size: 28),
          SizedBox(width: 10),
          Text('Redefinir senha', style: TextStyle(fontWeight: FontWeight.w800))
        ]),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
                'Nova senha para ${_str(member.data, 'NOME_COMPLETO', 'nome', 'name')} (mín. 6 caracteres):'),
            const SizedBox(height: 12),
            TextField(
              controller: newPasswordCtrl,
              obscureText: true,
              decoration: const InputDecoration(
                  labelText: 'Nova senha', border: OutlineInputBorder()),
              autofillHints: const [AutofillHints.newPassword],
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Alterar senha')),
        ],
      ),
    );
    if (confirm != true || !mounted) return;
    final newPassword = newPasswordCtrl.text.trim();
    if (newPassword.length < 6) {
      ScaffoldMessenger.of(context).showSnackBar(
          ThemeCleanPremium.successSnackBar(
              'A senha deve ter no mínimo 6 caracteres.'));
      return;
    }
    try {
      await FirebaseAuth.instance.currentUser?.getIdToken(true);
      final functions = FirebaseFunctions.instanceFor(region: 'us-central1');
      final res = await functions.httpsCallable('setMemberPassword').call({
        'tenantId': _effectiveTenantId,
        'memberId': member.id,
        'newPassword': newPassword,
      });
      final map = res.data as Map?;
      final recreated = map?['recreated'] == true;
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(ThemeCleanPremium.successSnackBar(
          recreated
              ? 'Conta de login recriada e senha definida. Avise o membro.'
              : 'Senha alterada. Avise o membro.',
        ));
      }
    } on FirebaseFunctionsException catch (e) {
      if (mounted) {
        final detail = e.message?.trim();
        final msg = (detail != null && detail.isNotEmpty)
            ? detail
            : 'Não foi possível redefinir a senha (código: ${e.code}).';
        ScaffoldMessenger.of(context)
            .showSnackBar(ThemeCleanPremium.feedbackSnackBar(msg));
      }
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
            ThemeCleanPremium.feedbackSnackBar('Erro ao redefinir senha: $e'));
    }
  }

  // ─── Selecionar Foto (web: arquivo; app: câmera ou galeria) ─────────────────
  Future<XFile?> _pickImage(BuildContext context) async {
    final ImageSource? source;
    if (kIsWeb) {
      source = ImageSource.gallery;
    } else {
      source = await showDialog<ImageSource>(
        context: context,
        builder: (ctx) => SimpleDialog(
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusLg)),
          title: const Text('Selecionar foto'),
          children: [
            SimpleDialogOption(
                onPressed: () => Navigator.pop(ctx, ImageSource.camera),
                child: const Row(children: [
                  Icon(Icons.camera_alt_rounded),
                  SizedBox(width: 12),
                  Text('Câmera')
                ])),
            SimpleDialogOption(
                onPressed: () => Navigator.pop(ctx, ImageSource.gallery),
                child: const Row(children: [
                  Icon(Icons.photo_library_rounded),
                  SizedBox(width: 12),
                  Text('Galeria')
                ])),
          ],
        ),
      );
    }
    if (source == null) return null;
    return MediaHandlerService.instance.pickCropEncodeMemberPhotoWebp(
      source: source,
      webCropContext: context,
    );
  }

  /// Rótulo + chave para cor (badges na lista).
  (String label, String key) _memberCargoBadgeParts(Map<String, dynamic> data) {
    final raw = data['FUNCOES'] ?? data['funcoes'];
    if (raw is List) {
      for (final e in raw) {
        final k = (e ?? '').toString().trim();
        if (k.isNotEmpty && k.toLowerCase() != 'membro') {
          return (_funcaoLabel(k), k);
        }
      }
    }
    final c = _str(data, 'CARGO', 'cargo', 'FUNCAO', 'funcao', 'role').trim();
    if (c.isNotEmpty && c.toLowerCase() != 'membro') {
      return (c, c);
    }
    return ('', 'membro');
  }

  // ─── Lista de Membros (sliver; scroll/paginação no [CustomScrollView] pai) ─
  Widget _buildMembersListSliver(List<_MemberDoc> docs) {
    final visibleCount = _membersVisibleCount.clamp(0, docs.length);
    final preloadUrls = docs
        .take((visibleCount + 12).clamp(0, docs.length))
        .map((m) => _photoUrlForMember(m.id, m.data))
        .where((u) => sanitizeImageUrl(u).isNotEmpty)
        .toList();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      preloadNetworkImages(context, preloadUrls, maxItems: 12);
    });
    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(ThemeCleanPremium.spaceMd, 0,
          ThemeCleanPremium.spaceMd, ThemeCleanPremium.spaceMd),
      sliver: SliverList(
        delegate: SliverChildBuilderDelegate(
          (context, i) {
          if (i >= visibleCount) {
            return Padding(
              padding: const EdgeInsets.fromLTRB(
                ThemeCleanPremium.spaceMd,
                8,
                ThemeCleanPremium.spaceMd,
                12,
              ),
              child: const SkeletonLoader(
                itemCount: 1,
                itemHeight: 72,
                padding: EdgeInsets.zero,
              ),
            );
          }
          final data = docs[i].data;
          final name = _str(data, 'NOME_COMPLETO', 'nome', 'name').isEmpty
              ? 'Membro'
              : _str(data, 'NOME_COMPLETO', 'nome', 'name');
          final email = _str(data, 'EMAIL', 'email');
          final phone = _str(data, 'TELEFONES', 'telefone');
          final status = _str(data, 'STATUS', 'status').isEmpty
              ? 'ativo'
              : _str(data, 'STATUS', 'status');
          final photo = _photoUrlForMember(docs[i].id, data);
          final optimisticBytes = _optimisticProfilePhotoBytes[docs[i].id];
          final isInativo = status.toLowerCase().contains('inativ');
          final isPendingRow = _memberDocIsPending(data);
          final avatarColor =
              _avatarColor(data, photo.isNotEmpty || optimisticBytes != null);
          final photoTenantId = _storageTenantIdForMemberPhotos(data);
          final cpfDigits = _str(data, 'CPF', 'cpf');
          const double avatarOuter = 56; // radius 28 * 2
          final showPendingCheckbox = _filtroStatus == 'pendentes' &&
              _canApprovePending &&
              isPendingRow;

          return Container(
            margin: const EdgeInsets.only(bottom: ThemeCleanPremium.spaceSm),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: ThemeCleanPremium.softUiCardShadow,
              border: Border.all(color: const Color(0xFFF1F5F9), width: 1),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (showPendingCheckbox)
                  Padding(
                    padding: const EdgeInsets.only(left: 4, top: 10),
                    child: SizedBox(
                      width: ThemeCleanPremium.minTouchTarget,
                      height: ThemeCleanPremium.minTouchTarget,
                      child: Checkbox(
                        value: _selectedPendingIds.contains(docs[i].id),
                        activeColor: ThemeCleanPremium.primary,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(6)),
                        onChanged: (v) => setState(() {
                          if (v == true) {
                            _selectedPendingIds.add(docs[i].id);
                          } else {
                            _selectedPendingIds.remove(docs[i].id);
                          }
                        }),
                      ),
                    ),
                  ),
                Expanded(
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: () => _showMemberDetails(context, docs[i]),
                      borderRadius: BorderRadius.circular(16),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: ThemeCleanPremium.spaceMd,
                            vertical: ThemeCleanPremium.spaceSm),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Hero(
                                  tag: 'member_profile_photo_${docs[i].id}',
                                  child: _MemberAvatar(
                                    photoUrl: photo.isNotEmpty ? photo : null,
                                    memoryPreviewBytes: optimisticBytes,
                                    memberData: data,
                                    name: name,
                                    radius: 28,
                                    backgroundColor: avatarColor ??
                                        ThemeCleanPremium.primary
                                            .withOpacity(0.1),
                                    tenantId: photoTenantId,
                                    memberId: docs[i].id,
                                    cpfDigits: cpfDigits,
                                    authUid: _memberAuthUidFromData(data),
                                    // Lista: decode ~200px — não puxar 4K para cada linha.
                                    memCacheMaxPx: 224,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        name,
                                        style: const TextStyle(
                                            fontWeight: FontWeight.w600,
                                            fontSize: 16,
                                            color: ThemeCleanPremium.onSurface,
                                            height: 1.2),
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      Builder(builder: (context) {
                                        final parts =
                                            _memberCargoBadgeParts(data);
                                        if (parts.$1.isEmpty) {
                                          return const SizedBox.shrink();
                                        }
                                        final col = Color(ChurchRolePermissions
                                            .badgeColorForKey(parts.$2));
                                        return Padding(
                                          padding:
                                              const EdgeInsets.only(top: 6),
                                          child: Align(
                                            alignment: Alignment.centerLeft,
                                            child: Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                      horizontal: 10,
                                                      vertical: 4),
                                              decoration: BoxDecoration(
                                                color:
                                                    col.withValues(alpha: 0.12),
                                                borderRadius:
                                                    BorderRadius.circular(20),
                                                border: Border.all(
                                                    color: col.withValues(
                                                        alpha: 0.28)),
                                              ),
                                              child: Text(
                                                parts.$1,
                                                style: TextStyle(
                                                  fontSize: 12,
                                                  fontWeight: FontWeight.w700,
                                                  color: col,
                                                ),
                                              ),
                                            ),
                                          ),
                                        );
                                      }),
                                      if (email.isNotEmpty ||
                                          phone.isNotEmpty) ...[
                                        const SizedBox(height: 4),
                                        Text(
                                          [
                                            if (email.isNotEmpty) email,
                                            if (phone.isNotEmpty) phone
                                          ].join(' • '),
                                          style: const TextStyle(
                                              fontSize: 13,
                                              color: ThemeCleanPremium
                                                  .onSurfaceVariant,
                                              height: 1.2),
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                                if (_canEditMemberRecord(docs[i]) ||
                                    (_canApprovePending && isPendingRow))
                                  PopupMenuButton<String>(
                                    icon: const Icon(Icons.more_vert_rounded,
                                        size: 22),
                                    padding: EdgeInsets.zero,
                                    constraints: const BoxConstraints(
                                        minWidth:
                                            ThemeCleanPremium.minTouchTarget,
                                        minHeight:
                                            ThemeCleanPremium.minTouchTarget),
                                    shape: RoundedRectangleBorder(
                                        borderRadius:
                                            BorderRadius.circular(12)),
                                    onSelected: (v) {
                                      if (v == 'edit')
                                        _editMember(context, docs[i]);
                                      if (v == 'delete')
                                        _deleteMember(context, docs[i]);
                                      if (v == 'approve')
                                        _aprovarMembrosPorIds({docs[i].id});
                                      if (v == 'card') {
                                        Navigator.push(
                                            context,
                                            MaterialPageRoute(
                                                builder: (_) => MemberCardPage(
                                                    tenantId:
                                                        _effectiveTenantId,
                                                    role: widget.role,
                                                    memberId: docs[i].id)));
                                      }
                                      if (v == 'password_self') {
                                        unawaited(_abrirAtualizarSenhaProprio(
                                            context, docs[i]));
                                      }
                                      if (v == 'dept') {
                                        final deptIds =
                                            (data['DEPARTAMENTOS'] as List?)
                                                    ?.map((e) => e.toString())
                                                    .toList() ??
                                                <String>[];
                                        _editDepartments(
                                            context: context,
                                            memberId: docs[i].id,
                                            current: deptIds,
                                            memberData:
                                                Map<String, dynamic>.from(
                                                    data));
                                      }
                                      if (v == 'password')
                                        _redefinirSenhaMembro(context, docs[i]);
                                    },
                                    itemBuilder: (_) => [
                                      if (_canApprovePending && isPendingRow)
                                        const PopupMenuItem(
                                          value: 'approve',
                                          child: Row(children: [
                                            Icon(Icons.how_to_reg_rounded,
                                                size: 18,
                                                color: Color(0xFF059669)),
                                            SizedBox(width: 8),
                                            Text('Aprovar cadastro',
                                                style: TextStyle(
                                                    color: Color(0xFF059669),
                                                    fontWeight:
                                                        FontWeight.w600))
                                          ]),
                                        ),
                                      if (_canEditMemberRecord(docs[i]))
                                        const PopupMenuItem(
                                            value: 'edit',
                                            child: Row(children: [
                                              Icon(Icons.edit_rounded,
                                                  size: 18),
                                              SizedBox(width: 8),
                                              Text('Editar')
                                            ])),
                                      if (_canOpenCarteirinhaFor(docs[i]))
                                        const PopupMenuItem(
                                            value: 'card',
                                            child: Row(children: [
                                              Icon(Icons.badge_rounded,
                                                  size: 18),
                                              SizedBox(width: 8),
                                              Text('Carteirinha')
                                            ])),
                                      if (_isSelfMember(docs[i]) &&
                                          _memberHasLogin(docs[i]))
                                        const PopupMenuItem(
                                            value: 'password_self',
                                            child: Row(children: [
                                              Icon(Icons.vpn_key_rounded,
                                                  size: 18,
                                                  color: Color(0xFFEA580C)),
                                              SizedBox(width: 8),
                                              Text('Atualizar senha',
                                                  style: TextStyle(
                                                      fontWeight:
                                                          FontWeight.w600))
                                            ])),
                                      if (_canManage) ...[
                                        const PopupMenuItem(
                                            value: 'delete',
                                            child: Row(children: [
                                              Icon(Icons.delete_outline_rounded,
                                                  size: 18,
                                                  color: Color(0xFFDC2626)),
                                              SizedBox(width: 8),
                                              Text('Excluir',
                                                  style: TextStyle(
                                                      color: Color(0xFFDC2626)))
                                            ])),
                                        const PopupMenuItem(
                                            value: 'dept',
                                            child: Row(children: [
                                              Icon(Icons.groups_rounded,
                                                  size: 18),
                                              SizedBox(width: 8),
                                              Text('Departamentos')
                                            ])),
                                        if (data['authUid'] != null &&
                                            !_isSelfMember(docs[i]))
                                          const PopupMenuItem(
                                              value: 'password',
                                              child: Row(children: [
                                                Icon(Icons.lock_reset_rounded,
                                                    size: 18),
                                                SizedBox(width: 8),
                                                Text('Redefinir senha')
                                              ])),
                                      ],
                                    ],
                                  ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Padding(
                              padding:
                                  const EdgeInsets.only(left: avatarOuter + 12),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 6),
                                decoration: BoxDecoration(
                                  color: isPendingRow
                                      ? const Color(0xFFFFFBEB)
                                      : (isInativo
                                          ? const Color(0xFFFFEBEE)
                                          : const Color(0xFFECFDF5)),
                                  borderRadius: BorderRadius.circular(999),
                                ),
                                child: Text(
                                  status,
                                  style: TextStyle(
                                    fontWeight: FontWeight.w500,
                                    fontSize: 12,
                                    color: isPendingRow
                                        ? const Color(0xFFB45309)
                                        : (isInativo
                                            ? const Color(0xFFB91C1C)
                                            : const Color(0xFF047857)),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
          },
          childCount: visibleCount + (visibleCount < docs.length ? 1 : 0),
        ),
      ),
    );
  }

  /// Linha da lista in-place no painel «Painel & números» (drill por sexo/faixa etária).
  Widget _buildMemberDrillListTile(BuildContext context, _MemberDoc member) {
    final data = member.data;
    final name = _str(data, 'NOME_COMPLETO', 'nome', 'name').isEmpty
        ? 'Membro'
        : _str(data, 'NOME_COMPLETO', 'nome', 'name');
    final email = _str(data, 'EMAIL', 'email');
    final phone = _str(data, 'TELEFONES', 'telefone');
    final status = _str(data, 'STATUS', 'status').isEmpty
        ? 'ativo'
        : _str(data, 'STATUS', 'status');
    final photo = _photoUrlForMember(member.id, data);
    final optimisticBytes = _optimisticProfilePhotoBytes[member.id];
    final isInativo = status.toLowerCase().contains('inativ');
    final isPendingRow = _memberDocIsPending(data);
    final avatarColor =
        _avatarColor(data, photo.isNotEmpty || optimisticBytes != null);
    final photoTenantId = _storageTenantIdForMemberPhotos(data);
    final cpfDigits = _str(data, 'CPF', 'cpf');
    const double avatarOuter = 56;

    return Container(
      margin: const EdgeInsets.only(bottom: ThemeCleanPremium.spaceSm),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: ThemeCleanPremium.softUiCardShadow,
        border: Border.all(color: const Color(0xFFF1F5F9), width: 1),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () => _showMemberDetails(context, member),
                borderRadius: BorderRadius.circular(16),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: ThemeCleanPremium.spaceMd,
                      vertical: ThemeCleanPremium.spaceSm),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Hero(
                            tag: 'member_profile_photo_${member.id}',
                            child: _MemberAvatar(
                              photoUrl: photo.isNotEmpty ? photo : null,
                              memoryPreviewBytes: optimisticBytes,
                              memberData: data,
                              name: name,
                              radius: 28,
                              backgroundColor: avatarColor ??
                                  ThemeCleanPremium.primary.withOpacity(0.1),
                              tenantId: photoTenantId,
                              memberId: member.id,
                              cpfDigits: cpfDigits,
                              authUid: _memberAuthUidFromData(data),
                              memCacheMaxPx: 224,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  name,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                      fontSize: 16,
                                      color: ThemeCleanPremium.onSurface,
                                      height: 1.2),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                Builder(builder: (context) {
                                  final parts = _memberCargoBadgeParts(data);
                                  if (parts.$1.isEmpty) {
                                    return const SizedBox.shrink();
                                  }
                                  final col = Color(
                                      ChurchRolePermissions.badgeColorForKey(
                                          parts.$2));
                                  return Padding(
                                    padding: const EdgeInsets.only(top: 6),
                                    child: Align(
                                      alignment: Alignment.centerLeft,
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 10, vertical: 4),
                                        decoration: BoxDecoration(
                                          color: col.withValues(alpha: 0.12),
                                          borderRadius:
                                              BorderRadius.circular(20),
                                          border: Border.all(
                                              color:
                                                  col.withValues(alpha: 0.28)),
                                        ),
                                        child: Text(
                                          parts.$1,
                                          style: TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w700,
                                            color: col,
                                          ),
                                        ),
                                      ),
                                    ),
                                  );
                                }),
                                if (email.isNotEmpty || phone.isNotEmpty) ...[
                                  const SizedBox(height: 4),
                                  Text(
                                    [
                                      if (email.isNotEmpty) email,
                                      if (phone.isNotEmpty) phone
                                    ].join(' • '),
                                    style: const TextStyle(
                                        fontSize: 13,
                                        color:
                                            ThemeCleanPremium.onSurfaceVariant,
                                        height: 1.2),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ],
                            ),
                          ),
                          if (_canEditMemberRecord(member) ||
                              (_canApprovePending && isPendingRow))
                            PopupMenuButton<String>(
                              icon:
                                  const Icon(Icons.more_vert_rounded, size: 22),
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(
                                  minWidth: ThemeCleanPremium.minTouchTarget,
                                  minHeight: ThemeCleanPremium.minTouchTarget),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12)),
                              onSelected: (v) {
                                if (v == 'edit') _editMember(context, member);
                                if (v == 'delete')
                                  _deleteMember(context, member);
                                if (v == 'approve') {
                                  _aprovarMembrosPorIds({member.id});
                                }
                                if (v == 'card') {
                                  Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                          builder: (_) => MemberCardPage(
                                              tenantId: _effectiveTenantId,
                                              role: widget.role,
                                              memberId: member.id)));
                                }
                                if (v == 'password_self') {
                                  unawaited(_abrirAtualizarSenhaProprio(
                                      context, member));
                                }
                                if (v == 'dept') {
                                  final deptIds =
                                      (data['DEPARTAMENTOS'] as List?)
                                              ?.map((e) => e.toString())
                                              .toList() ??
                                          <String>[];
                                  _editDepartments(
                                      context: context,
                                      memberId: member.id,
                                      current: deptIds,
                                      memberData:
                                          Map<String, dynamic>.from(data));
                                }
                                if (v == 'password') {
                                  _redefinirSenhaMembro(context, member);
                                }
                              },
                              itemBuilder: (_) => [
                                if (_canApprovePending && isPendingRow)
                                  const PopupMenuItem(
                                    value: 'approve',
                                    child: Row(children: [
                                      Icon(Icons.how_to_reg_rounded,
                                          size: 18, color: Color(0xFF059669)),
                                      SizedBox(width: 8),
                                      Text('Aprovar cadastro',
                                          style: TextStyle(
                                              color: Color(0xFF059669),
                                              fontWeight: FontWeight.w600))
                                    ]),
                                  ),
                                if (_canEditMemberRecord(member))
                                  const PopupMenuItem(
                                      value: 'edit',
                                      child: Row(children: [
                                        Icon(Icons.edit_rounded, size: 18),
                                        SizedBox(width: 8),
                                        Text('Editar')
                                      ])),
                                if (_canOpenCarteirinhaFor(member))
                                  const PopupMenuItem(
                                      value: 'card',
                                      child: Row(children: [
                                        Icon(Icons.badge_rounded, size: 18),
                                        SizedBox(width: 8),
                                        Text('Carteirinha')
                                      ])),
                                if (_isSelfMember(member) &&
                                    _memberHasLogin(member))
                                  const PopupMenuItem(
                                      value: 'password_self',
                                      child: Row(children: [
                                        Icon(Icons.vpn_key_rounded,
                                            size: 18, color: Color(0xFFEA580C)),
                                        SizedBox(width: 8),
                                        Text('Atualizar senha',
                                            style: TextStyle(
                                                fontWeight: FontWeight.w600))
                                      ])),
                                if (_canManage) ...[
                                  const PopupMenuItem(
                                      value: 'delete',
                                      child: Row(children: [
                                        Icon(Icons.delete_outline_rounded,
                                            size: 18, color: Color(0xFFDC2626)),
                                        SizedBox(width: 8),
                                        Text('Excluir',
                                            style: TextStyle(
                                                color: Color(0xFFDC2626)))
                                      ])),
                                  const PopupMenuItem(
                                      value: 'dept',
                                      child: Row(children: [
                                        Icon(Icons.groups_rounded, size: 18),
                                        SizedBox(width: 8),
                                        Text('Departamentos')
                                      ])),
                                  if (data['authUid'] != null &&
                                      !_isSelfMember(member))
                                    const PopupMenuItem(
                                        value: 'password',
                                        child: Row(children: [
                                          Icon(Icons.lock_reset_rounded,
                                              size: 18),
                                          SizedBox(width: 8),
                                          Text('Redefinir senha')
                                        ])),
                                ],
                              ],
                            ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Padding(
                        padding: const EdgeInsets.only(left: avatarOuter + 12),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: isPendingRow
                                ? const Color(0xFFFFFBEB)
                                : (isInativo
                                    ? const Color(0xFFFFEBEE)
                                    : const Color(0xFFECFDF5)),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            status,
                            style: TextStyle(
                              fontWeight: FontWeight.w500,
                              fontSize: 12,
                              color: isPendingRow
                                  ? const Color(0xFFB45309)
                                  : (isInativo
                                      ? const Color(0xFFB91C1C)
                                      : const Color(0xFF047857)),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ─── Adicionar Membro ─────────────────────────────────────────────────────
  void _onAddMember(BuildContext context) async {
    try {
      final result = await _limitService.checkLimit(
        _effectiveTenantId,
        planIdOverride:
            (widget.subscription?['planId'] ?? '').toString().trim().isEmpty
                ? null
                : (widget.subscription?['planId'] ?? '').toString().trim(),
      );
      if (result.isBlocked && context.mounted) {
        await showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Row(children: [
              Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 28),
              SizedBox(width: 10),
              Text('Limite do plano')
            ]),
            content: Text(result.blockedDialogMessage),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Entendi')),
              FilledButton(
                  onPressed: () {
                    Navigator.pop(ctx);
                    Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => const RenewPlanPage()));
                  },
                  child: const Text('Ver planos')),
            ],
          ),
        );
        return;
      }
    } catch (_) {
      // Se verificação de limite falhar, permite abrir o cadastro (limite será checado ao enviar).
    }
    if (!context.mounted) return;
    // Tela própria do sistema: cadastro interno pelo gestor/adm — salva como ativo (não usa formulário público).
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => InternalNewMemberPage(tenantId: _effectiveTenantId),
      ),
    ).then((_) => _refreshMembers());
  }

  Future<String?> _loadTenantSlug() async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection('igrejas')
          .doc(_effectiveTenantId)
          .get();
      return (snap.data()?['slug'] ?? snap.data()?['slugId'] ?? '')
          .toString()
          .trim();
    } catch (_) {
      return null;
    }
  }

  Future<void> _exportCsv(BuildContext context) async {
    try {
      final snapMembers = await _members.limit(500).get();
      final snapMembros = await _membros.limit(500).get();
      final snapMembersIgrejas = await _membersIgrejas.limit(500).get();
      final snapMembrosIgrejas = await _membrosIgrejas.limit(500).get();
      final snapUsersT = await FirebaseFirestore.instance
          .collection('users')
          .where('tenantId', isEqualTo: _effectiveTenantId)
          .limit(500)
          .get();
      final snapUsersI = await FirebaseFirestore.instance
          .collection('users')
          .where('igrejaId', isEqualTo: _effectiveTenantId)
          .limit(500)
          .get();
      final combined = <String, _MemberDoc>{};
      for (final d in snapMembers.docs)
        combined[d.id] = _MemberDoc.fromQueryDoc(d);
      for (final d in snapMembros.docs)
        combined.putIfAbsent(d.id, () => _MemberDoc.fromQueryDoc(d));
      for (final d in snapMembersIgrejas.docs)
        combined.putIfAbsent(d.id, () => _MemberDoc.fromQueryDoc(d));
      for (final d in snapMembrosIgrejas.docs)
        combined.putIfAbsent(d.id, () => _MemberDoc.fromQueryDoc(d));
      for (final d in snapUsersT.docs)
        combined.putIfAbsent(d.id, () => _MemberDoc.fromUserDoc(d));
      for (final d in snapUsersI.docs)
        combined.putIfAbsent(d.id, () => _MemberDoc.fromUserDoc(d));
      var docs = combined.values.toList();
      docs = _aplicarFiltros(docs);
      if (docs.isEmpty) {
        if (context.mounted)
          ScaffoldMessenger.of(context).showSnackBar(
              ThemeCleanPremium.successSnackBar(
                  'Nenhum membro para exportar.'));
        return;
      }
      const sep = ';';
      final sb =
          StringBuffer('Nome${sep}E-mail${sep}Telefone${sep}CPF${sep}Status\n');
      for (final d in docs) {
        final m = d.data;
        sb.writeln(
            '${(m['NOME_COMPLETO'] ?? m['nome'] ?? '').toString().replaceAll(sep, ',')}$sep${(m['EMAIL'] ?? m['email'] ?? '').toString().replaceAll(sep, ',')}$sep${(m['TELEFONES'] ?? m['telefone'] ?? '').toString().replaceAll(sep, ',')}$sep${(m['CPF'] ?? m['cpf'] ?? '')}$sep${(m['STATUS'] ?? m['status'] ?? '')}');
      }
      await Share.share(sb.toString(),
          subject: 'Membros - Gestão YAHWEH',
          sharePositionOrigin: const Rect.fromLTWH(0, 0, 1, 1));
      if (context.mounted)
        ScaffoldMessenger.of(context).showSnackBar(
            ThemeCleanPremium.successSnackBar(
                'Exportados ${docs.length} membros (CSV).'));
    } catch (e) {
      if (context.mounted)
        ScaffoldMessenger.of(context).showSnackBar(
            ThemeCleanPremium.feedbackSnackBar('Erro ao exportar: $e'));
    }
  }

  Future<void> _exportPdf(BuildContext context) async {
    try {
      final snapMembers = await _members.limit(500).get();
      final snapMembros = await _membros.limit(500).get();
      final snapMembersIgrejas = await _membersIgrejas.limit(500).get();
      final snapMembrosIgrejas = await _membrosIgrejas.limit(500).get();
      final snapUsersT = await FirebaseFirestore.instance
          .collection('users')
          .where('tenantId', isEqualTo: _effectiveTenantId)
          .limit(500)
          .get();
      final snapUsersI = await FirebaseFirestore.instance
          .collection('users')
          .where('igrejaId', isEqualTo: _effectiveTenantId)
          .limit(500)
          .get();
      final combined = <String, _MemberDoc>{};
      for (final d in snapMembers.docs)
        combined[d.id] = _MemberDoc.fromQueryDoc(d);
      for (final d in snapMembros.docs)
        combined.putIfAbsent(d.id, () => _MemberDoc.fromQueryDoc(d));
      for (final d in snapMembersIgrejas.docs)
        combined.putIfAbsent(d.id, () => _MemberDoc.fromQueryDoc(d));
      for (final d in snapMembrosIgrejas.docs)
        combined.putIfAbsent(d.id, () => _MemberDoc.fromQueryDoc(d));
      for (final d in snapUsersT.docs)
        combined.putIfAbsent(d.id, () => _MemberDoc.fromUserDoc(d));
      for (final d in snapUsersI.docs)
        combined.putIfAbsent(d.id, () => _MemberDoc.fromUserDoc(d));
      var docs = combined.values.toList();
      docs = _aplicarFiltros(docs);
      if (docs.isEmpty) {
        if (context.mounted)
          ScaffoldMessenger.of(context).showSnackBar(
              ThemeCleanPremium.successSnackBar(
                  'Nenhum membro para exportar.'));
        return;
      }
      final branding = await loadReportPdfBranding(_effectiveTenantId);
      final data = docs.asMap().entries.map((e) {
        final m = e.value.data;
        final st = (m['STATUS'] ?? m['status'] ?? '').toString().trim();
        final statusPdf = st.isEmpty
            ? ''
            : st
                .split(RegExp(r'\s+'))
                .where((w) => w.isNotEmpty)
                .map((w) =>
                    '${w[0].toUpperCase()}${w.length > 1 ? w.substring(1).toLowerCase() : ''}')
                .join(' ');
        return [
          '${e.key + 1}',
          (m['NOME_COMPLETO'] ?? m['nome'] ?? '').toString(),
          pdfEmailBreakOpportunities(
              (m['EMAIL'] ?? m['email'] ?? '').toString()),
          (m['TELEFONES'] ?? m['telefone'] ?? '').toString(),
          (m['CPF'] ?? m['cpf'] ?? '').toString(),
          statusPdf,
        ];
      }).toList();
      final pdf = await PdfSuperPremiumTheme.newPdfDocument();
      pdf.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4.landscape,
          margin: PdfSuperPremiumTheme.pageMargin,
          header: (ctx) => pw.Padding(
            padding: const pw.EdgeInsets.only(bottom: 12),
            child: PdfSuperPremiumTheme.header(
              'Relatório de Membros',
              branding: branding,
              extraLines: ['Total de membros: ${docs.length}'],
            ),
          ),
          footer: (ctx) => PdfSuperPremiumTheme.footer(
            ctx,
            churchName: branding.churchName,
          ),
          build: (ctx) => [
            PdfSuperPremiumTheme.fromTextArray(
              headers: const [
                '#',
                'Nome',
                'E-mail',
                'Telefone',
                'CPF',
                'Status'
              ],
              data: data,
              accent: branding.accent,
              columnWidths: PdfSuperPremiumTheme.columnWidthsMemberReport(
                const ['nome', 'email', 'telefone', 'cpf', 'status'],
              ),
            ),
          ],
        ),
      );
      final bytes = Uint8List.fromList(await pdf.save());
      if (context.mounted)
        await showPdfActions(context,
            bytes: bytes, filename: 'membros_relatorio.pdf');
    } catch (e) {
      if (context.mounted)
        ScaffoldMessenger.of(context).showSnackBar(
            ThemeCleanPremium.feedbackSnackBar('Erro ao exportar PDF: $e'));
    }
  }

  Widget _buildFiltrosSection(EdgeInsets padding) {
    final labelStyle = TextStyle(
      fontSize: 11,
      fontWeight: FontWeight.w800,
      letterSpacing: 0.6,
      color: ThemeCleanPremium.onSurfaceVariant,
    );
    final fieldDeco = InputDecoration(
      labelStyle: TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: ThemeCleanPremium.onSurfaceVariant.withValues(alpha: 0.9),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusMd),
        borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusMd),
        borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusMd),
        borderSide: BorderSide(
            color: ThemeCleanPremium.primary.withValues(alpha: 0.55),
            width: 1.4),
      ),
      filled: true,
      fillColor: Colors.white,
    );

    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('CRITÉRIOS RÁPIDOS', style: labelStyle),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusMd),
              border: Border.all(color: const Color(0xFFEEF2F6)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Gênero', style: labelStyle.copyWith(letterSpacing: 0.4)),
                const SizedBox(height: 8),
                _filterChip(
                    _filtroGenero,
                    ['todos', 'masculino', 'feminino'],
                    ['Todos', 'Masculino', 'Feminino'],
                    (v) => setState(() => _filtroGenero = v)),
                const SizedBox(height: 14),
                Text('Faixa etária',
                    style: labelStyle.copyWith(letterSpacing: 0.4)),
                const SizedBox(height: 8),
                _filterChip(
                    _filtroFaixaEtaria,
                    ['todas', 'criancas', 'adolescentes', 'adultos', 'idosos'],
                    [
                      'Todas',
                      'Crianças (<13)',
                      'Adol. (13-17)',
                      'Adultos (18-59)',
                      'Idosos (60+)'
                    ],
                    (v) => setState(() => _filtroFaixaEtaria = v)),
                const SizedBox(height: 14),
                Text('Cadastro',
                    style: labelStyle.copyWith(letterSpacing: 0.4)),
                const SizedBox(height: 8),
                _filterChip(
                    _filtroDiaCadastro,
                    ['todos', 'hoje', 'semana', 'mes'],
                    ['Todos', 'Hoje', 'Semana', 'Mês'],
                    (v) => setState(() => _filtroDiaCadastro = v)),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Text('LISTAS E DATAS', style: labelStyle),
          const SizedBox(height: 10),
          FutureBuilder<void>(
            future: _deptsFuture,
            builder: (context, snap) {
              return LayoutBuilder(
                builder: (context, c) {
                  final narrow = c.maxWidth < 500;
                  return Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      SizedBox(
                        width: narrow ? double.infinity : 220,
                        child: DropdownButtonFormField<String>(
                          value: _filtroDepartamento,
                          decoration: fieldDeco.copyWith(
                            labelText: 'Departamento',
                            prefixIcon: Icon(
                              Icons.groups_2_rounded,
                              size: 20,
                              color: ThemeCleanPremium.primary
                                  .withValues(alpha: 0.75),
                            ),
                          ),
                          items: [
                            const DropdownMenuItem(
                                value: 'todos', child: Text('Todos')),
                            ..._departamentos.map((d) => DropdownMenuItem(
                                value: d.id,
                                child: Text(d.name,
                                    overflow: TextOverflow.ellipsis))),
                          ],
                          onChanged: (v) => setState(
                              () => _filtroDepartamento = v ?? 'todos'),
                        ),
                      ),
                      SizedBox(
                        width: narrow ? double.infinity : 160,
                        child: DropdownButtonFormField<int?>(
                          value: _filtroAniversarioMes,
                          decoration: fieldDeco.copyWith(
                            labelText: 'Aniversário',
                            prefixIcon: Icon(
                              Icons.cake_rounded,
                              size: 20,
                              color: ThemeCleanPremium.primary
                                  .withValues(alpha: 0.75),
                            ),
                          ),
                          items: [
                            const DropdownMenuItem(
                                value: null, child: Text('Qualquer mês')),
                            ...List.generate(
                                12,
                                (i) => DropdownMenuItem(
                                    value: i + 1,
                                    child: Text([
                                      'Janeiro',
                                      'Fevereiro',
                                      'Março',
                                      'Abril',
                                      'Maio',
                                      'Junho',
                                      'Julho',
                                      'Agosto',
                                      'Setembro',
                                      'Outubro',
                                      'Novembro',
                                      'Dezembro'
                                    ][i]))),
                          ],
                          onChanged: (v) =>
                              setState(() => _filtroAniversarioMes = v),
                        ),
                      ),
                    ],
                  );
                },
              );
            },
          ),
        ],
      ),
    );
  }

  /// Altura do [Expanded] pai + scroll unificado (filtros + lista / vazio).
  Widget _wrapMembersListScroll({
    required Future<void> Function() onRefresh,
    required Widget scrollableChild,
  }) {
    return LayoutBuilder(
      builder: (context, constraints) {
        var scroll = scrollableChild;
        final h = constraints.maxHeight;
        if (h.isFinite && h > 0) {
          scroll = SizedBox(height: h, child: scroll);
        }
        return ScrollConfiguration(
          behavior: ScrollConfiguration.of(context).copyWith(
            dragDevices: {
              PointerDeviceKind.touch,
              PointerDeviceKind.mouse,
              PointerDeviceKind.trackpad,
              PointerDeviceKind.stylus,
            },
          ),
          child: kIsWeb
              ? scroll
              : RefreshIndicator(onRefresh: onRefresh, child: scroll),
        );
      },
    );
  }

  Widget _filterChip(String value, List<String> keys, List<String> labels,
      ValueChanged<String> onSelected) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: List.generate(keys.length, (i) {
        final sel = value == keys[i];
        return Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () {
              onSelected(keys[i]);
              ThemeCleanPremium.hapticAction();
            },
            borderRadius: BorderRadius.circular(20),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                color: sel ? Colors.white : Colors.white.withValues(alpha: 0.5),
                border: Border.all(
                  color: sel
                      ? ThemeCleanPremium.primary.withValues(alpha: 0.38)
                      : const Color(0xFFE2E8F0),
                  width: sel ? 1.2 : 1,
                ),
                boxShadow: sel ? ThemeCleanPremium.softUiCardShadow : null,
              ),
              child: Text(
                labels[i],
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: sel ? FontWeight.w800 : FontWeight.w600,
                  letterSpacing: -0.15,
                  color: sel
                      ? ThemeCleanPremium.primary
                      : ThemeCleanPremium.onSurfaceVariant,
                ),
              ),
            ),
          ),
        );
      }),
    );
  }

  String _buscaRapidosSectionSubtitle() {
    const statusLabels = <String, String>{
      'todos': 'Todos',
      'ativos': 'Ativos',
      'inativos': 'Inativos',
      'pendentes': 'Pendentes',
    };
    final st = statusLabels[_filtroStatus] ?? _filtroStatus;
    final q = _searchCtrl.text.trim();
    if (_buscaRapidosExpanded) {
      return 'Recolha para ampliar a lista na tela (útil no celular e no navegador).';
    }
    final bits = <String>['Toque para expandir'];
    bits.add('Status: $st');
    if (q.isNotEmpty) {
      final short = q.length > 26 ? '${q.substring(0, 26)}…' : q;
      bits.add('Busca: "$short"');
    }
    return bits.join(' · ');
  }

  Widget _buildPremiumSearchField(EdgeInsets padding) {
    return Padding(
      padding: EdgeInsets.fromLTRB(padding.left, 10, padding.right, 0),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusMd),
          boxShadow: ThemeCleanPremium.softUiCardShadow,
          border: Border.all(color: const Color(0xFFE8EDF3)),
        ),
        child: ValueListenableBuilder<TextEditingValue>(
          valueListenable: _searchCtrl,
          builder: (context, val, _) {
            return Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Padding(
                  padding: const EdgeInsets.only(left: 14, right: 4),
                  child: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: ThemeCleanPremium.primaryLighter
                          .withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      Icons.search_rounded,
                      color: ThemeCleanPremium.primary,
                      size: 22,
                    ),
                  ),
                ),
                Expanded(
                  child: TextField(
                    controller: _searchCtrl,
                    decoration: InputDecoration(
                      border: InputBorder.none,
                      hintText: 'Buscar por nome, e-mail, CPF ou telefone…',
                      hintStyle: TextStyle(
                        color: ThemeCleanPremium.onSurfaceVariant
                            .withValues(alpha: 0.55),
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                      ),
                      suffixIcon: val.text.isEmpty
                          ? null
                          : IconButton(
                              tooltip: 'Limpar busca',
                              onPressed: () {
                                _searchCtrl.clear();
                                setState(() => _q = '');
                              },
                              icon: Icon(
                                Icons.close_rounded,
                                color: ThemeCleanPremium.onSurfaceVariant
                                    .withValues(alpha: 0.55),
                              ),
                            ),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 16),
                    ),
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                      letterSpacing: -0.2,
                      color: ThemeCleanPremium.onSurface,
                    ),
                    onChanged: (_) {
                      _searchDebounce?.cancel();
                      _searchDebounce =
                          Timer(const Duration(milliseconds: 300), () {
                        if (mounted) {
                          setState(
                              () => _q = _searchCtrl.text.trim().toLowerCase());
                        }
                      });
                    },
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  static const _statusSegIcons = [
    Icons.grid_view_rounded,
    Icons.verified_rounded,
    Icons.person_off_rounded,
    Icons.schedule_rounded,
  ];
  static const _statusSegAccents = [
    Color(0xFF64748B),
    Color(0xFF16A34A),
    Color(0xFFEA580C),
    Color(0xFFD97706),
  ];

  Widget _buildPremiumStatusBar(EdgeInsets padding) {
    const keys = ['todos', 'ativos', 'inativos', 'pendentes'];
    const labels = ['Todos', 'Ativos', 'Inativos', 'Pendentes'];

    Widget seg(int i) {
      final key = keys[i];
      final selected = _filtroStatus == key;
      final accent = _statusSegAccents[i];
      final icon = _statusSegIcons[i];
      return Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {
            setState(() {
              _filtroStatus = key;
              _selectedPendingIds.clear();
            });
            ThemeCleanPremium.hapticAction();
          },
          borderRadius: BorderRadius.circular(12),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              color: selected
                  ? accent.withValues(alpha: 0.11)
                  : Colors.transparent,
              border: Border.all(
                color: selected
                    ? accent.withValues(alpha: 0.35)
                    : Colors.transparent,
                width: 1,
              ),
              boxShadow: selected
                  ? [
                      BoxShadow(
                        color: accent.withValues(alpha: 0.12),
                        blurRadius: 14,
                        offset: const Offset(0, 4),
                      ),
                    ]
                  : null,
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  icon,
                  size: 18,
                  color: selected ? accent : ThemeCleanPremium.onSurfaceVariant,
                ),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    labels[i],
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                    style: TextStyle(
                      fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                      fontSize: 13,
                      letterSpacing: -0.2,
                      color: selected
                          ? accent
                          : ThemeCleanPremium.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Padding(
      padding: EdgeInsets.fromLTRB(padding.left, 12, padding.right, 0),
      child: Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusMd),
          boxShadow: ThemeCleanPremium.softUiCardShadow,
          border: Border.all(color: const Color(0xFFEEF2F6)),
        ),
        child: LayoutBuilder(
          builder: (context, c) {
            final compact = c.maxWidth < 520;
            if (compact) {
              return SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                physics: const BouncingScrollPhysics(),
                child: Row(
                  children: [
                    for (var i = 0; i < 4; i++) ...[
                      if (i > 0) const SizedBox(width: 6),
                      seg(i),
                    ],
                  ],
                ),
              );
            }
            return Row(
              children: [
                for (var i = 0; i < 4; i++) ...[
                  if (i > 0) const SizedBox(width: 4),
                  Expanded(child: seg(i)),
                ],
              ],
            );
          },
        ),
      ),
    );
  }

  // ─── Build ────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return FutureBuilder<MembersLimitResult>(
      future: _limitFuture,
      builder: (context, limitSnap) {
        final limitResult = limitSnap.data;
        final addBlocked = limitResult?.isBlocked ?? false;
        final isMobile = ThemeCleanPremium.isMobile(context);
        final padding = ThemeCleanPremium.pagePadding(context);
        final showAppBar =
            !widget.embeddedInShell && (!isMobile || Navigator.canPop(context));
        return Scaffold(
          backgroundColor: ThemeCleanPremium.surfaceVariant,
          appBar: !showAppBar
              ? null
              : AppBar(
                  leading: Navigator.canPop(context)
                      ? IconButton(
                          icon: const Icon(Icons.arrow_back_rounded),
                          onPressed: () => Navigator.maybePop(context),
                          tooltip: 'Voltar',
                        )
                      : null,
                  backgroundColor: ThemeCleanPremium.primary,
                  foregroundColor: Colors.white,
                  title: const Text('Membros'),
                  actions: [
                    if (_canManage)
                      IconButton(
                        icon: const Icon(Icons.picture_as_pdf_rounded),
                        tooltip: 'Exportar membros (PDF)',
                        onPressed: () => _exportPdf(context),
                        style: IconButton.styleFrom(
                            minimumSize: const Size(48, 48)),
                      ),
                    if (_canManage)
                      IconButton(
                        icon: const Icon(Icons.download_rounded),
                        tooltip: 'Exportar membros (CSV)',
                        onPressed: () => _exportCsv(context),
                        style: IconButton.styleFrom(
                            minimumSize: const Size(48, 48)),
                      ),
                    if (_canManage)
                      IconButton(
                        icon: Icon(Icons.person_add_rounded,
                            color: addBlocked ? Colors.white54 : null),
                        tooltip: addBlocked ? 'Limite atingido' : 'Novo membro',
                        onPressed:
                            addBlocked ? null : () => _onAddMember(context),
                        style: IconButton.styleFrom(
                            minimumSize: const Size(48, 48)),
                      ),
                  ],
                ),
          body: SafeArea(
            top: !widget.embeddedInShell,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (limitResult != null && limitResult.planLimit > 0)
                  _MembersLimitBanner(result: limitResult),
                if (widget.embeddedInShell &&
                    !_canManage &&
                    AppPermissions.isRestrictedMember(widget.role))
                  Padding(
                    padding:
                        EdgeInsets.fromLTRB(padding.left, 8, padding.right, 4),
                    child: Material(
                      color: const Color(0xFFEFF6FF),
                      borderRadius: BorderRadius.circular(12),
                      child: ListTile(
                        dense: true,
                        leading: Icon(Icons.person_rounded,
                            color: ThemeCleanPremium.primary, size: 22),
                        title: Text(
                          'Seu cadastro',
                          style: TextStyle(
                              fontWeight: FontWeight.w700,
                              color: Colors.grey.shade900,
                              fontSize: 14),
                        ),
                        subtitle: Text(
                          'Altere seus dados e foto. Funções (gestor, ADM, etc.) só a equipe pode definir.',
                          style: TextStyle(
                              fontSize: 12,
                              height: 1.3,
                              color: Colors.grey.shade700),
                        ),
                      ),
                    ),
                  ),
                if (widget.embeddedInShell && _canManage)
                  Padding(
                    padding:
                        EdgeInsets.fromLTRB(padding.left, 4, padding.right, 2),
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: Material(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        elevation: 0,
                        shadowColor: Colors.transparent,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                          side: const BorderSide(color: Color(0xFFE8EEF4)),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: const Icon(Icons.picture_as_pdf_rounded,
                                    size: 22),
                                tooltip: 'Exportar membros (PDF)',
                                onPressed: () => _exportPdf(context),
                                style: IconButton.styleFrom(
                                    minimumSize: const Size(44, 44)),
                              ),
                              IconButton(
                                icon: const Icon(Icons.download_rounded,
                                    size: 22),
                                tooltip: 'Exportar membros (CSV)',
                                onPressed: () => _exportCsv(context),
                                style: IconButton.styleFrom(
                                    minimumSize: const Size(44, 44)),
                              ),
                              IconButton(
                                icon: Icon(Icons.person_add_rounded,
                                    size: 22,
                                    color: addBlocked
                                        ? ThemeCleanPremium.onSurfaceVariant
                                        : null),
                                tooltip: addBlocked
                                    ? 'Limite atingido'
                                    : 'Novo membro',
                                onPressed: addBlocked
                                    ? null
                                    : () => _onAddMember(context),
                                style: IconButton.styleFrom(
                                    minimumSize: const Size(44, 44)),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                // Abas: lista (filtros + membros) | painel com gráficos e totais.
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Padding(
                        padding: EdgeInsets.fromLTRB(
                            padding.left, 0, padding.right, 6),
                        child: _MembersPremiumTabSwitcher(
                          index: _membersMainTabIndex,
                          onChanged: (i) => setState(() {
                            _membersMainTabIndex = i;
                          }),
                        ),
                      ),
                      Expanded(
                        child: IndexedStack(
                          index: _membersMainTabIndex,
                          sizing: StackFit.expand,
                          children: [
                            _buildMembersListFutureColumn(
                              padding,
                              addBlocked: addBlocked,
                              limitResult: limitResult,
                              includeInlineFilters: true,
                            ),
                            _buildMembersStatsDashboard(
                                context, padding, limitResult),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// Lista de membros (mesmo FutureBuilder na aba principal e na rota fullscreen).
  Widget _buildMembersListFutureColumn(
    EdgeInsets padding, {
    required bool addBlocked,
    MembersLimitResult? limitResult,
    bool includeInlineFilters = true,
  }) {
    return FutureBuilder<List<QuerySnapshot<Map<String, dynamic>>>>(
      future: _membersDataFuture,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          if (includeInlineFilters) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildMembersUltraFilterStrip(
                  padding,
                  limitResult: limitResult,
                  addBlocked: addBlocked,
                ),
                const Expanded(child: SkeletonLoader(itemCount: 8)),
              ],
            );
          }
          return const SkeletonLoader(itemCount: 8);
        }
        if (snap.hasError) {
          return Padding(
            padding: const EdgeInsets.all(ThemeCleanPremium.spaceLg),
            child: ChurchPanelErrorBody(
              title: 'Não foi possível carregar os membros',
              error: snap.error,
              onRetry: _refreshMembers,
            ),
          );
        }
        final list = snap.data!;
        if (list.length < 7) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(ThemeCleanPremium.spaceLg),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.warning_amber_rounded,
                      size: 48, color: Colors.amber.shade700),
                  const SizedBox(height: ThemeCleanPremium.spaceMd),
                  Text(
                    'Resposta incompleta ao carregar membros (${list.length}/7).',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: ThemeCleanPremium.onSurfaceVariant),
                  ),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                      onPressed: _refreshMembers,
                      icon: const Icon(Icons.refresh_rounded),
                      label: const Text('Recarregar')),
                ],
              ),
            ),
          );
        }
        final pendCount = list[6].docs.length;
        final combined = <String, _MemberDoc>{};
        void putOrMerge(
            QueryDocumentSnapshot<Map<String, dynamic>> d,
            _MemberDoc Function(QueryDocumentSnapshot<Map<String, dynamic>>)
                map) {
          final doc = map(d);
          final cur = combined[doc.id];
          if (cur == null) {
            combined[doc.id] = doc;
          } else {
            combined[doc.id] =
                _MemberDoc(doc.id, _mergeMemberPhotoFields(cur.data, doc.data));
          }
        }

        // list[0]..[3] são mesmas fontes mescladas (membros igreja); um loop evita merge quadruplicado.
        for (final d in list[0].docs) putOrMerge(d, _MemberDoc.fromQueryDoc);
        for (final d in list[4].docs) putOrMerge(d, _MemberDoc.fromUserDoc);
        for (final d in list[5].docs) putOrMerge(d, _MemberDoc.fromUserDoc);
        final allDocs = combined.values
            .map(_memberWithOptimisticOverlay)
            .where((m) => !_optimisticRemovedMemberIds.contains(m.id))
            .toList();
        final docs = _aplicarFiltros(allDocs);
        final bootDocId = widget.initialOpenMemberDocId?.trim() ?? '';
        if (bootDocId.isNotEmpty && !_didBootstrapOpenMemberSheet) {
          _didBootstrapOpenMemberSheet = true;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            _MemberDoc? hit;
            for (final d in allDocs) {
              if (d.id == bootDocId) {
                hit = d;
                break;
              }
            }
            if (hit != null) {
              _showMemberDetails(context, hit);
            } else {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    'Membro não encontrado na lista (id: $bootDocId). Atualize ou verifique o cadastro.',
                  ),
                ),
              );
            }
          });
        }
        final pendentesNaLista =
            docs.where((d) => _memberDocIsPending(d.data)).toList();
        Widget? emptyListBody;
        if (docs.isEmpty) {
          final filteredOut = allDocs.isNotEmpty;
          if (_q.isNotEmpty) {
            emptyListBody = Center(
                child: Text('Nenhum membro encontrado para "$_q".',
                    style:
                        TextStyle(color: ThemeCleanPremium.onSurfaceVariant)));
          } else if (filteredOut) {
            emptyListBody = Center(
              child: Padding(
                padding: const EdgeInsets.all(ThemeCleanPremium.spaceLg),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.filter_alt_off_rounded,
                        size: 64, color: Colors.grey.shade400),
                    const SizedBox(height: ThemeCleanPremium.spaceMd),
                    Text(
                      'Nenhum membro corresponde aos filtros ativos.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: ThemeCleanPremium.onSurface),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Há ${allDocs.length} na lista bruta. Ajuste a aba Todos/Ativos/Inativos ou os filtros avançados.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          fontSize: 13,
                          height: 1.35,
                          color: ThemeCleanPremium.onSurfaceVariant),
                    ),
                    const SizedBox(height: 20),
                    FilledButton.icon(
                      onPressed: () => setState(() {
                        _filtroStatus = 'todos';
                        _filtroGenero = 'todos';
                        _filtroFaixaEtaria = 'todas';
                        _filtroDiaCadastro = 'todos';
                        _filtroDepartamento = 'todos';
                        _filtroAniversarioMes = null;
                      }),
                      icon: const Icon(Icons.restart_alt_rounded, size: 20),
                      label: const Text('Limpar filtros'),
                    ),
                  ],
                ),
              ),
            );
          } else if (!_canManage &&
              AppPermissions.isRestrictedMember(widget.role) &&
              allDocs.isEmpty) {
            emptyListBody = Center(
              child: Padding(
                padding: const EdgeInsets.all(ThemeCleanPremium.spaceLg),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.badge_outlined,
                        size: 64, color: Colors.grey.shade400),
                    const SizedBox(height: ThemeCleanPremium.spaceMd),
                    Text(
                      'Cadastro não encontrado para este login.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: ThemeCleanPremium.onSurface),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'O CPF do login deve coincidir com o cadastro ou a ficha precisa estar vinculada ao seu usuário. Em caso de dúvida, fale com o secretariado.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          fontSize: 13,
                          height: 1.35,
                          color: ThemeCleanPremium.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
            );
          } else {
            emptyListBody = Center(
              child: Padding(
                padding: const EdgeInsets.all(ThemeCleanPremium.spaceLg),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.people_outline_rounded,
                        size: 64, color: Colors.grey.shade400),
                    const SizedBox(height: ThemeCleanPremium.spaceMd),
                    Text('Nenhum membro cadastrado.',
                        style: TextStyle(
                            fontSize: 16,
                            color: ThemeCleanPremium.onSurfaceVariant)),
                    if (_canManage) ...[
                      const SizedBox(height: 16),
                      FilledButton.icon(
                        onPressed:
                            addBlocked ? null : () => _onAddMember(context),
                        icon: const Icon(Icons.person_add_rounded, size: 20),
                        label: Text(addBlocked
                            ? 'Limite do plano'
                            : 'Cadastrar novo membro'),
                      ),
                    ],
                  ],
                ),
              ),
            );
          }
        }
        final allPendIds = pendentesNaLista.map((e) => e.id).toSet();
        final allPendingSelected = allPendIds.isNotEmpty &&
            allPendIds.every(_selectedPendingIds.contains);
        final slivers = <Widget>[
          if (includeInlineFilters)
            SliverToBoxAdapter(
              child: _buildMembersUltraFilterStrip(
                padding,
                limitResult: limitResult,
                addBlocked: addBlocked,
              ),
            ),
          if (_filtroStatus == 'pendentes' &&
              _canApprovePending &&
              pendentesNaLista.isNotEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                    padding.horizontal, 0, padding.horizontal, 10),
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: ThemeCleanPremium.softUiCardShadow,
                    border: Border.all(color: const Color(0xFFF1F5F9)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFFFBEB),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Icon(Icons.pending_actions_rounded,
                                color: Colors.amber.shade800, size: 22),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '${pendentesNaLista.length} pendente(s) na lista',
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w800,
                                      fontSize: 15,
                                      letterSpacing: -0.2),
                                ),
                                Text(
                                  'Aprove um por um no menu ⋮, selecione vários ou todos de uma vez.',
                                  style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey.shade600,
                                      height: 1.3),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: [
                          OutlinedButton.icon(
                            onPressed: () => setState(() {
                              if (allPendingSelected) {
                                _selectedPendingIds
                                    .removeWhere(allPendIds.contains);
                              } else {
                                _selectedPendingIds = {
                                  ..._selectedPendingIds,
                                  ...allPendIds
                                };
                              }
                            }),
                            icon: Icon(
                                allPendingSelected
                                    ? Icons.deselect_rounded
                                    : Icons.select_all_rounded,
                                size: 18),
                            label: Text(allPendingSelected
                                ? 'Limpar seleção'
                                : 'Selecionar todos'),
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 14, vertical: 12),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12)),
                            ),
                          ),
                          FilledButton.icon(
                            onPressed: _selectedPendingIds.isEmpty
                                ? null
                                : () => _aprovarMembrosPorIds(Set<String>.from(
                                    _selectedPendingIds
                                        .intersection(allPendIds))),
                            icon: const Icon(Icons.check_circle_rounded,
                                size: 18),
                            label: Text(
                                'Aprovar selecionados (${_selectedPendingIds.intersection(allPendIds).length})'),
                            style: FilledButton.styleFrom(
                              backgroundColor: const Color(0xFF059669),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 16, vertical: 12),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12)),
                            ),
                          ),
                          FilledButton.tonalIcon(
                            onPressed: () =>
                                _confirmAprovarTodosFiltrados(pendentesNaLista),
                            icon: const Icon(Icons.done_all_rounded, size: 18),
                            label: const Text('Aprovar todos filtrados'),
                            style: FilledButton.styleFrom(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 16, vertical: 12),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12)),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          if (_canApprovePending && pendCount > 0)
            SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                    padding.horizontal, 0, padding.horizontal, 8),
                child: Material(
                  color: Colors.amber.shade50,
                  borderRadius:
                      BorderRadius.circular(ThemeCleanPremium.radiusSm),
                  child: InkWell(
                    onTap: () async {
                      await Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) => AprovarMembrosPendentesPage(
                                  tenantId: _effectiveTenantId,
                                  gestorRole: widget.role)));
                      if (mounted) _refreshMembers();
                    },
                    borderRadius:
                        BorderRadius.circular(ThemeCleanPremium.radiusSm),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 12),
                      child: Row(children: [
                        Icon(Icons.person_add_rounded,
                            color: Colors.amber.shade800, size: 22),
                        const SizedBox(width: 10),
                        Expanded(
                            child: Text(
                                '$pendCount cadastro(s) pendente(s) de aprovação',
                                style: TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 13,
                                    color: Colors.amber.shade900))),
                        Icon(Icons.arrow_forward_rounded,
                            color: Colors.amber.shade800, size: 20),
                      ]),
                    ),
                  ),
                ),
              ),
            ),
          if (docs.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: emptyListBody!,
            )
          else
            _buildMembersListSliver(docs),
        ];
        return NotificationListener<ScrollNotification>(
          onNotification: (n) {
            if (docs.isEmpty) return false;
            return _onMembersScrollNotification(n, docs.length);
          },
          child: _wrapMembersListScroll(
            onRefresh: () async => _refreshMembers(forceServer: true),
            scrollableChild: CustomScrollView(
              controller: _membersScrollController,
              physics: const AlwaysScrollableScrollPhysics(
                parent: BouncingScrollPhysics(),
              ),
              slivers: slivers,
            ),
          ),
        );
      },
    );
  }

  /// Painel com totais, sexo, faixas etárias e atalhos de relatório (mesma base de dados da lista).
  Widget _buildMembersStatsDashboard(
    BuildContext context,
    EdgeInsets padding,
    MembersLimitResult? limitResult,
  ) {
    return FutureBuilder<List<QuerySnapshot<Map<String, dynamic>>>>(
      future: _membersDataFuture,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snap.hasError) {
          return Padding(
            padding: const EdgeInsets.all(ThemeCleanPremium.spaceLg),
            child: ChurchPanelErrorBody(
              title: 'Não foi possível carregar os números',
              error: snap.error,
              onRetry: _refreshMembers,
            ),
          );
        }
        final list = snap.data!;
        if (list.length < 7) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(ThemeCleanPremium.spaceLg),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.warning_amber_rounded,
                      size: 48, color: Colors.amber.shade700),
                  const SizedBox(height: 12),
                  Text(
                    'Resposta incompleta (${list.length}/7).',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: _refreshMembers,
                    icon: const Icon(Icons.refresh_rounded),
                    label: const Text('Recarregar'),
                  ),
                ],
              ),
            ),
          );
        }
        final merged = _mergedMemberDocsFromSnapshots(list);
        final docsForStats = _aplicarFiltros(merged, applySearch: false);
        return _MembersPremiumStatsPanel(
          padding: padding,
          allDocs: docsForStats,
          searchQuery: _q,
          limitResult: limitResult,
          canManage: _canManage,
          canApprovePending: _canApprovePending,
          pendQueryCount: list[6].docs.length,
          buildMemberTile: (ctx, m) => _buildMemberDrillListTile(ctx, m),
          onExportPdf: () => _exportPdf(context),
          onExportCsv: () => _exportCsv(context),
          onRelatorioAvancado: _canManage
              ? () => openRelatorioMembrosAvancado(
                    context,
                    tenantId: _effectiveTenantId,
                    role: widget.role,
                  )
              : null,
          onOpenAprovar: _canApprovePending && list[6].docs.isNotEmpty
              ? () async {
                  await Navigator.push<void>(
                    context,
                    MaterialPageRoute<void>(
                      builder: (_) => AprovarMembrosPendentesPage(
                          tenantId: _effectiveTenantId,
                          gestorRole: widget.role),
                    ),
                  );
                  if (mounted) _refreshMembers();
                }
              : null,
        );
      },
    );
  }

  List<_MemberDoc> _mergedMemberDocsFromSnapshots(
      List<QuerySnapshot<Map<String, dynamic>>> list) {
    if (list.length < 7) return [];
    final combined = <String, _MemberDoc>{};
    void putOrMerge(
      QueryDocumentSnapshot<Map<String, dynamic>> d,
      _MemberDoc Function(QueryDocumentSnapshot<Map<String, dynamic>>) map,
    ) {
      final doc = map(d);
      final cur = combined[doc.id];
      if (cur == null) {
        combined[doc.id] = doc;
      } else {
        combined[doc.id] =
            _MemberDoc(doc.id, _mergeMemberPhotoFields(cur.data, doc.data));
      }
    }

    for (final d in list[0].docs) {
      putOrMerge(d, _MemberDoc.fromQueryDoc);
    }
    for (final d in list[4].docs) {
      putOrMerge(d, _MemberDoc.fromUserDoc);
    }
    for (final d in list[5].docs) {
      putOrMerge(d, _MemberDoc.fromUserDoc);
    }
    return combined.values
        .map(_memberWithOptimisticOverlay)
        .where((m) => !_optimisticRemovedMemberIds.contains(m.id))
        .toList();
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// Widgets auxiliares
// ═══════════════════════════════════════════════════════════════════════════════

/// Abas superior (lista vs painel) — alto contraste em mobile.
class _MembersPremiumTabSwitcher extends StatelessWidget {
  final int index;
  final ValueChanged<int> onChanged;

  const _MembersPremiumTabSwitcher({
    required this.index,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final primary = ThemeCleanPremium.primary;
    return Container(
      padding: const EdgeInsets.all(5),
      decoration: BoxDecoration(
        color: const Color(0xFFEFF6FF),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFBFDBFE)),
        boxShadow: ThemeCleanPremium.softUiCardShadow,
      ),
      child: Row(
        children: [
          Expanded(
            child: _tabChip(
              label: 'Lista',
              icon: Icons.people_rounded,
              selected: index == 0,
              primary: primary,
              onTap: () => onChanged(0),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _tabChip(
              label: 'Painel & números',
              icon: Icons.insights_rounded,
              selected: index == 1,
              primary: primary,
              onTap: () => onChanged(1),
            ),
          ),
        ],
      ),
    );
  }

  Widget _tabChip({
    required String label,
    required IconData icon,
    required bool selected,
    required Color primary,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            gradient: selected
                ? LinearGradient(
                    colors: [
                      primary,
                      Color.lerp(primary, Colors.black, 0.12)!,
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  )
                : null,
            color: selected ? null : Colors.white,
            border: Border.all(
              color: selected ? Colors.transparent : const Color(0xFFCBD5E1),
              width: 1.2,
            ),
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: primary.withValues(alpha: 0.35),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ]
                : null,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 20,
                color: selected ? Colors.white : const Color(0xFF475569),
              ),
              const SizedBox(width: 10),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                    letterSpacing: -0.2,
                    color: selected ? Colors.white : const Color(0xFF334155),
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

/// Filtro in-place no painel «Painel & números» (cartões e gráficos).
enum _StatsDrillKind {
  overview,
  genderMale,
  genderFemale,
  genderUnknown,
  ageChild,
  ageTeen,
  ageAdult,
  ageSenior,
  ageUnknown,
}

bool _memberMatchesStatsDrill(_MemberDoc m, _StatsDrillKind k) {
  if (k == _StatsDrillKind.overview) return true;
  final d = m.data;
  switch (k) {
    case _StatsDrillKind.genderMale:
      return genderCategoryFromMemberData(d) == 'M';
    case _StatsDrillKind.genderFemale:
      return genderCategoryFromMemberData(d) == 'F';
    case _StatsDrillKind.genderUnknown:
      final g = genderCategoryFromMemberData(d);
      return g != 'M' && g != 'F';
    case _StatsDrillKind.ageUnknown:
      return ageFromMemberData(d) == null;
    case _StatsDrillKind.ageChild:
      final idade = ageFromMemberData(d);
      return idade != null && idade < 13;
    case _StatsDrillKind.ageTeen:
      final idade = ageFromMemberData(d);
      return idade != null && idade >= 13 && idade < 18;
    case _StatsDrillKind.ageAdult:
      final idade = ageFromMemberData(d);
      return idade != null && idade >= 18 && idade < 60;
    case _StatsDrillKind.ageSenior:
      final idade = ageFromMemberData(d);
      return idade != null && idade >= 60;
    case _StatsDrillKind.overview:
      return true;
  }
}

String _statsDrillTitle(_StatsDrillKind k) {
  switch (k) {
    case _StatsDrillKind.overview:
      return 'Painel';
    case _StatsDrillKind.genderMale:
      return 'Homens';
    case _StatsDrillKind.genderFemale:
      return 'Mulheres';
    case _StatsDrillKind.genderUnknown:
      return 'Sexo não informado';
    case _StatsDrillKind.ageChild:
      return 'Crianças (<13 anos)';
    case _StatsDrillKind.ageTeen:
      return 'Adolescentes (13–17)';
    case _StatsDrillKind.ageAdult:
      return 'Adultos (18–59)';
    case _StatsDrillKind.ageSenior:
      return 'Idosos (60+)';
    case _StatsDrillKind.ageUnknown:
      return 'Sem idade registrada';
  }
}

_StatsDrillKind _statsAgeDrillFromBarIndex(int i) {
  const kinds = <_StatsDrillKind>[
    _StatsDrillKind.ageChild,
    _StatsDrillKind.ageTeen,
    _StatsDrillKind.ageAdult,
    _StatsDrillKind.ageSenior,
    _StatsDrillKind.ageUnknown,
  ];
  if (i < 0 || i >= kinds.length) return _StatsDrillKind.overview;
  return kinds[i];
}

/// Gráficos e cartões de totais (membros carregados no painel).
class _MembersPremiumStatsPanel extends StatefulWidget {
  final EdgeInsets padding;
  final List<_MemberDoc> allDocs;

  /// Texto da busca rápida (só afeta a lista; gráficos ignoram).
  final String searchQuery;
  final MembersLimitResult? limitResult;
  final bool canManage;
  final bool canApprovePending;
  final int pendQueryCount;

  /// Linha de membro (lista drill) — mesmas ações da aba Lista.
  final Widget Function(BuildContext context, _MemberDoc member)
      buildMemberTile;
  final VoidCallback onExportPdf;
  final VoidCallback onExportCsv;
  final VoidCallback? onRelatorioAvancado;
  final VoidCallback? onOpenAprovar;

  const _MembersPremiumStatsPanel({
    required this.padding,
    required this.allDocs,
    required this.searchQuery,
    required this.limitResult,
    required this.canManage,
    required this.canApprovePending,
    required this.pendQueryCount,
    required this.buildMemberTile,
    required this.onExportPdf,
    required this.onExportCsv,
    this.onRelatorioAvancado,
    this.onOpenAprovar,
  });

  @override
  State<_MembersPremiumStatsPanel> createState() =>
      _MembersPremiumStatsPanelState();
}

class _MembersPremiumStatsPanelState extends State<_MembersPremiumStatsPanel> {
  _StatsDrillKind _drill = _StatsDrillKind.overview;

  void _openDrill(_StatsDrillKind k) {
    if (k == _StatsDrillKind.overview) return;
    setState(() => _drill = k);
  }

  void _backToOverview() => setState(() => _drill = _StatsDrillKind.overview);

  @override
  Widget build(BuildContext context) {
    final n = widget.allDocs.length;
    var homens = 0, mulheres = 0, sexoNi = 0;
    var criancas = 0, adolescentes = 0, adultos = 0, idosos = 0, semIdade = 0;
    var ativos = 0, inativos = 0, pendentes = 0;
    for (final m in widget.allDocs) {
      final d = m.data;
      final g = genderCategoryFromMemberData(d);
      if (g == 'M') {
        homens++;
      } else if (g == 'F') {
        mulheres++;
      } else {
        sexoNi++;
      }
      final idade = ageFromMemberData(d);
      if (idade == null) {
        semIdade++;
      } else if (idade < 13) {
        criancas++;
      } else if (idade < 18) {
        adolescentes++;
      } else if (idade < 60) {
        adultos++;
      } else {
        idosos++;
      }
      final s = (d['STATUS'] ?? d['status'] ?? '').toString().toLowerCase();
      final pend = s.contains('pendente');
      final inat = s.contains('inativ');
      if (pend) {
        pendentes++;
      } else if (inat) {
        inativos++;
      } else {
        ativos++;
      }
    }

    final primary = ThemeCleanPremium.primary;

    if (_drill != _StatsDrillKind.overview) {
      final filtered = widget.allDocs
          .where((m) => _memberMatchesStatsDrill(m, _drill))
          .toList();
      return Container(
        color: ThemeCleanPremium.surfaceVariant,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(
                  widget.padding.left, 4, widget.padding.right, 0),
              child: _buildDrillHeader(primary, filtered.length),
            ),
            Expanded(
              child: filtered.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(28),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.people_outline_rounded,
                                size: 52, color: Colors.grey.shade400),
                            const SizedBox(height: 14),
                            Text(
                              'Nenhum membro neste grupo\ncom os filtros atuais da lista.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: Colors.grey.shade700,
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                                height: 1.35,
                              ),
                            ),
                            const SizedBox(height: 18),
                            OutlinedButton.icon(
                              onPressed: _backToOverview,
                              icon:
                                  const Icon(Icons.bar_chart_rounded, size: 20),
                              label: const Text('Voltar ao painel'),
                            ),
                          ],
                        ),
                      ),
                    )
                  : ListView.separated(
                      padding: EdgeInsets.fromLTRB(
                        widget.padding.left,
                        10,
                        widget.padding.right,
                        24 + widget.padding.bottom,
                      ),
                      itemCount: filtered.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 4),
                      itemBuilder: (context, i) =>
                          widget.buildMemberTile(context, filtered[i]),
                    ),
            ),
          ],
        ),
      );
    }

    return Container(
      color: ThemeCleanPremium.surfaceVariant,
      child: ListView(
        padding: EdgeInsets.fromLTRB(widget.padding.left, 4,
            widget.padding.right, 24 + widget.padding.bottom),
        children: [
          Text(
            'Visão geral (filtros da lista, exceto busca por texto)',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: Colors.grey.shade700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Sexo, idade e situação seguem status, gênero, departamento, etc. A caixa “Buscar” só restringe a tabela na aba Lista — não os totais abaixo.',
            style: TextStyle(
              fontSize: 12,
              height: 1.35,
              color: Colors.grey.shade600,
            ),
          ),
          if (widget.searchQuery.trim().isNotEmpty) ...[
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFFEFF6FF),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFBFDBFE)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.info_outline_rounded,
                      size: 20, color: ThemeCleanPremium.primary),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Há texto na busca da lista. Os números deste painel ignoram essa busca para não “sumirem” os irmãos. Limpe a busca se quiser a lista igual aos gráficos.',
                      style: TextStyle(
                        fontSize: 12,
                        height: 1.35,
                        color: Colors.grey.shade800,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 14),
          _statHeroCard(
            total: n,
            limit: widget.limitResult,
            ativos: ativos,
            pendentes: pendentes,
            inativos: inativos,
            primary: primary,
          ),
          if (widget.canApprovePending &&
              widget.pendQueryCount > 0 &&
              widget.onOpenAprovar != null) ...[
            const SizedBox(height: 12),
            Material(
              color: Colors.amber.shade50,
              borderRadius: BorderRadius.circular(14),
              child: InkWell(
                onTap: widget.onOpenAprovar,
                borderRadius: BorderRadius.circular(14),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  child: Row(
                    children: [
                      Icon(Icons.pending_actions_rounded,
                          color: Colors.amber.shade900),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          '${widget.pendQueryCount} cadastro(s) pendente(s) — abrir aprovações',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            color: Colors.amber.shade900,
                            fontSize: 13,
                          ),
                        ),
                      ),
                      Icon(Icons.chevron_right_rounded,
                          color: Colors.amber.shade900),
                    ],
                  ),
                ),
              ),
            ),
          ],
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _miniStat(
                  'Homens',
                  homens,
                  const Color(0xFF2563EB),
                  Icons.male_rounded,
                  tooltip: 'Ver lista de homens',
                  onTap: () => _openDrill(_StatsDrillKind.genderMale),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _miniStat(
                  'Mulheres',
                  mulheres,
                  const Color(0xFFDB2777),
                  Icons.female_rounded,
                  tooltip: 'Ver lista de mulheres',
                  onTap: () => _openDrill(_StatsDrillKind.genderFemale),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _miniStat(
            'Sexo não informado',
            sexoNi,
            const Color(0xFF64748B),
            Icons.help_outline_rounded,
            tooltip: 'Ver lista (sexo em branco ou não reconhecido)',
            onTap: () => _openDrill(_StatsDrillKind.genderUnknown),
          ),
          const SizedBox(height: 18),
          Text(
            'Faixa etária',
            style: TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 15,
              color: Colors.grey.shade900,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Toque numa barra para ver a lista daquela faixa.',
            style: TextStyle(
              fontSize: 12,
              height: 1.3,
              color: Colors.grey.shade600,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: const Color(0xFFE2E8F0)),
              boxShadow: ThemeCleanPremium.softUiCardShadow,
            ),
            child: SizedBox(
              height: 228,
              child: _ageBarChart(
                criancas: criancas,
                adolescentes: adolescentes,
                adultos: adultos,
                idosos: idosos,
                semIdade: semIdade,
                onBarSelected: (i) => _openDrill(_statsAgeDrillFromBarIndex(i)),
              ),
            ),
          ),
          const SizedBox(height: 18),
          Text(
            'Sexo (distribuição)',
            style: TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 15,
              color: Colors.grey.shade900,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Toque numa fatia do gráfico ou num item da legenda.',
            style: TextStyle(
              fontSize: 12,
              height: 1.3,
              color: Colors.grey.shade600,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: const Color(0xFFE2E8F0)),
              boxShadow: ThemeCleanPremium.softUiCardShadow,
            ),
            child: _genderPieChart(
              context: context,
              homens: homens,
              mulheres: mulheres,
              outros: sexoNi,
              onSliceSelected: (kind) => _openDrill(kind),
            ),
          ),
          const SizedBox(height: 20),
          if (widget.canManage) ...[
            Text(
              'Relatórios rápidos',
              style: TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 15,
                color: Colors.grey.shade900,
              ),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                FilledButton.icon(
                  onPressed: widget.onExportPdf,
                  icon: const Icon(Icons.picture_as_pdf_rounded, size: 20),
                  label: const Text('PDF — lista completa'),
                  style: FilledButton.styleFrom(
                    backgroundColor: primary,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 12),
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: widget.onExportCsv,
                  icon: const Icon(Icons.table_chart_rounded, size: 20),
                  label: const Text('CSV — exportar'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 12),
                    side: BorderSide(color: primary.withValues(alpha: 0.5)),
                  ),
                ),
                if (widget.onRelatorioAvancado != null)
                  FilledButton.tonalIcon(
                    onPressed: widget.onRelatorioAvancado,
                    icon: const Icon(Icons.tune_rounded, size: 20),
                    label: const Text('Relatório avançado (filtros e campos)'),
                    style: FilledButton.styleFrom(
                      foregroundColor: primary,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 12),
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildDrillHeader(Color primary, int count) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            primary,
            Color.lerp(primary, const Color(0xFF0F172A), 0.22)!,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: primary.withValues(alpha: 0.32),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Material(
            color: Colors.white.withValues(alpha: 0.14),
            shape: const CircleBorder(),
            child: IconButton(
              onPressed: _backToOverview,
              tooltip: 'Voltar ao painel',
              icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _statsDrillTitle(_drill),
                  style: const TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.w900,
                    color: Colors.white,
                    letterSpacing: -0.4,
                    height: 1.15,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '$count ${count == 1 ? 'membro' : 'membros'} · toque na linha para abrir a ficha ou use ⋮ para editar',
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: Colors.white.withValues(alpha: 0.88),
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _statHeroCard({
    required int total,
    required MembersLimitResult? limit,
    required int ativos,
    required int pendentes,
    required int inativos,
    required Color primary,
  }) {
    final lim = limit?.planLimit ?? 0;
    final used = limit?.currentCount ?? total;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            primary,
            Color.lerp(primary, const Color(0xFF0F172A), 0.25)!,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: primary.withValues(alpha: 0.35),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '$total',
                style: const TextStyle(
                  fontSize: 40,
                  fontWeight: FontWeight.w900,
                  color: Colors.white,
                  height: 1,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(
                    lim > 0
                        ? 'membros no painel (plano: $used / $lim)'
                        : 'membros no painel',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.92),
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _chip('Ativos', ativos, const Color(0xFF34D399)),
              _chip('Pendentes', pendentes, const Color(0xFFFBBF24)),
              _chip('Inativos', inativos, const Color(0xFF94A3B8)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _chip(String label, int v, Color c) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.22)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: c,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '$label: ',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.85),
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          Text(
            '$v',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _miniStat(
    String label,
    int v,
    Color color,
    IconData icon, {
    String? tooltip,
    VoidCallback? onTap,
  }) {
    final child = Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: ThemeCleanPremium.softUiCardShadow,
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 26),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey.shade700,
                  ),
                ),
                Text(
                  '$v',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: color,
                  ),
                ),
              ],
            ),
          ),
          Icon(Icons.touch_app_rounded, size: 18, color: Colors.grey.shade400),
        ],
      ),
    );
    if (onTap == null) return child;
    return Tooltip(
      message: tooltip ?? 'Ver lista filtrada',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: child,
        ),
      ),
    );
  }

  Widget _ageBarChart({
    required int criancas,
    required int adolescentes,
    required int adultos,
    required int idosos,
    required int semIdade,
    required void Function(int barGroupIndex) onBarSelected,
  }) {
    final vals = [criancas, adolescentes, adultos, idosos, semIdade];
    final maxV = vals.fold<int>(0, (a, b) => a > b ? a : b);
    final maxY = (maxV < 1 ? 1 : maxV) * 1.15;
    const labels = [
      'Crianças\n(<13)',
      'Adolesc.',
      'Adultos',
      'Idosos',
      'Sem idade'
    ];
    const colors = [
      Color(0xFF38BDF8),
      Color(0xFFA78BFA),
      Color(0xFF34D399),
      Color(0xFFFBBF24),
      Color(0xFF94A3B8),
    ];
    return Padding(
      padding: const EdgeInsets.only(right: 8, top: 8),
      child: BarChart(
        BarChartData(
          alignment: BarChartAlignment.spaceAround,
          maxY: maxY,
          barTouchData: BarTouchData(
            enabled: true,
            handleBuiltInTouches: true,
            touchCallback: (FlTouchEvent event, barTouchResponse) {
              if (!event.isInterestedForInteractions) return;
              if (event is! FlTapUpEvent) return;
              final spot = barTouchResponse?.spot;
              if (spot == null) return;
              final idx = spot.touchedBarGroupIndex;
              if (idx >= 0 && idx < 5) onBarSelected(idx);
            },
          ),
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            horizontalInterval: maxY > 5 ? maxY / 5 : 1,
            getDrawingHorizontalLine: (_) => FlLine(
              color: const Color(0xFFE2E8F0),
              strokeWidth: 1,
            ),
          ),
          titlesData: FlTitlesData(
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 36,
                getTitlesWidget: (v, meta) {
                  final i = v.toInt();
                  if (i < 0 || i >= labels.length) {
                    return const SizedBox.shrink();
                  }
                  return Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      labels[i],
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 9.5,
                        fontWeight: FontWeight.w700,
                        color: Colors.grey.shade700,
                        height: 1.1,
                      ),
                    ),
                  );
                },
              ),
            ),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 28,
                getTitlesWidget: (v, meta) => Text(
                  v.toInt().toString(),
                  style: TextStyle(fontSize: 10, color: Colors.grey.shade600),
                ),
              ),
            ),
            topTitles:
                const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles:
                const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          ),
          borderData: FlBorderData(show: false),
          barGroups: [
            for (var i = 0; i < 5; i++)
              BarChartGroupData(
                x: i,
                barRods: [
                  BarChartRodData(
                    toY: vals[i].toDouble(),
                    color: colors[i],
                    width: 18,
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(8),
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  /// Estilo alinhado ao painel principal ([IgrejaDashboardModerno]): legenda + rosca com total no centro.
  Widget _genderPieChart({
    required BuildContext context,
    required int homens,
    required int mulheres,
    required int outros,
    required void Function(_StatsDrillKind kind) onSliceSelected,
  }) {
    final total = homens + mulheres + outros;
    if (total == 0) {
      return SizedBox(
        height: 120,
        child: Center(
          child: Text(
            'Sem dados para o gráfico.',
            style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
          ),
        ),
      );
    }
    final narrow = MediaQuery.sizeOf(context).width < 560;
    final sections = <PieChartSectionData>[];
    final sliceDrills = <_StatsDrillKind>[];
    void addSlice(double v, Color color, _StatsDrillKind drill) {
      if (v <= 0) return;
      sliceDrills.add(drill);
      final share = v / total;
      final showPct = share >= 0.06;
      sections.add(
        PieChartSectionData(
          value: v,
          title: showPct ? '${(share * 100).round()}%' : '',
          color: color,
          radius: 62,
          titleStyle: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w800,
            color: Colors.white,
            shadows: const [
              Shadow(
                  offset: Offset(0, 1), blurRadius: 4, color: Colors.black54),
            ],
          ),
          borderSide: const BorderSide(color: Color(0xFFF8FAFC), width: 2),
        ),
      );
    }

    addSlice(
        homens.toDouble(), const Color(0xFF2563EB), _StatsDrillKind.genderMale);
    addSlice(mulheres.toDouble(), const Color(0xFFDB2777),
        _StatsDrillKind.genderFemale);
    addSlice(outros.toDouble(), const Color(0xFF64748B),
        _StatsDrillKind.genderUnknown);

    final chart = AspectRatio(
      aspectRatio: 1,
      child: LayoutBuilder(
        builder: (context, c) {
          final side = c.maxWidth.clamp(168.0, 228.0);
          return Center(
            child: SizedBox(
              width: side,
              height: side,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  PieChart(
                    PieChartData(
                      sections: sections,
                      sectionsSpace: 2.5,
                      centerSpaceRadius: side * 0.22,
                      pieTouchData: PieTouchData(
                        enabled: true,
                        touchCallback: (FlTouchEvent event, pieTouchResponse) {
                          if (!event.isInterestedForInteractions) return;
                          if (event is! FlTapUpEvent) return;
                          final idx = pieTouchResponse
                              ?.touchedSection?.touchedSectionIndex;
                          if (idx == null ||
                              idx < 0 ||
                              idx >= sliceDrills.length) {
                            return;
                          }
                          onSliceSelected(sliceDrills[idx]);
                        },
                      ),
                    ),
                    swapAnimationDuration: const Duration(milliseconds: 450),
                  ),
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '$total',
                        style: const TextStyle(
                          fontSize: 26,
                          fontWeight: FontWeight.w900,
                          color: Color(0xFF0F172A),
                          letterSpacing: -0.8,
                          height: 1.0,
                        ),
                      ),
                      Text(
                        'membros',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );

    Widget legendTile(
        String label, int count, Color color, _StatsDrillKind drill) {
      final pct = total > 0 ? count / total * 100 : 0.0;
      return Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          child: InkWell(
            onTap: () => onSliceSelected(drill),
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 12,
                    height: 12,
                    margin: const EdgeInsets.only(top: 3),
                    decoration: BoxDecoration(
                      color: color,
                      borderRadius: BorderRadius.circular(4),
                      boxShadow: [
                        BoxShadow(
                          color: color.withValues(alpha: 0.35),
                          blurRadius: 6,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text.rich(
                      TextSpan(
                        style: TextStyle(
                          fontSize: 13,
                          height: 1.35,
                          color: Colors.grey.shade700,
                        ),
                        children: [
                          TextSpan(
                            text: '$label\n',
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          TextSpan(
                            text: '${pct.toStringAsFixed(1)}%',
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 15,
                              color: Color(0xFF0F172A),
                            ),
                          ),
                          TextSpan(
                            text:
                                '  ·  $count ${count == 1 ? 'membro' : 'membros'}',
                            style: TextStyle(
                              fontWeight: FontWeight.w500,
                              fontSize: 12,
                              color: Colors.grey.shade600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  Icon(Icons.chevron_right_rounded,
                      size: 18, color: Colors.grey.shade400),
                ],
              ),
            ),
          ),
        ),
      );
    }

    final legend = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (homens > 0)
          legendTile('Homens', homens, const Color(0xFF2563EB),
              _StatsDrillKind.genderMale),
        if (mulheres > 0)
          legendTile('Mulheres', mulheres, const Color(0xFFDB2777),
              _StatsDrillKind.genderFemale),
        if (outros > 0)
          legendTile('Sexo não informado', outros, const Color(0xFF64748B),
              _StatsDrillKind.genderUnknown),
      ],
    );

    if (narrow) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          chart,
          const SizedBox(height: 14),
          legend,
        ],
      );
    }
    return SizedBox(
      height: 268,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            flex: 11,
            child: SingleChildScrollView(child: legend),
          ),
          Expanded(flex: 10, child: chart),
        ],
      ),
    );
  }
}

/// Seção recolhível (link cadastro, filtros) — melhora visualização dos membros
class _CollapsibleSection extends StatelessWidget {
  final String title;
  final String? subtitle;
  final IconData icon;
  final bool expanded;
  final VoidCallback onToggle;
  final Widget child;
  final int badgeCount;

  const _CollapsibleSection({
    required this.title,
    this.subtitle,
    required this.icon,
    required this.expanded,
    required this.onToggle,
    required this.child,
    this.badgeCount = 0,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusMd),
          boxShadow: ThemeCleanPremium.softUiCardShadow,
          border: Border.all(color: const Color(0xFFE8EEF4)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            InkWell(
              onTap: onToggle,
              borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusMd),
              child: Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: expanded ? 12 : 9,
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Container(
                      padding: EdgeInsets.all(expanded ? 10 : 8),
                      decoration: BoxDecoration(
                        color:
                            ThemeCleanPremium.primary.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(icon,
                          color: ThemeCleanPremium.primary,
                          size: expanded ? 22 : 20),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Flexible(
                                child: Text(
                                  title,
                                  style: TextStyle(
                                    fontSize: expanded ? 15 : 14,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: -0.2,
                                  ),
                                ),
                              ),
                              if (badgeCount > 0) ...[
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: ThemeCleanPremium.primary
                                        .withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(999),
                                  ),
                                  child: Text(
                                    '$badgeCount',
                                    style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w800,
                                      color: ThemeCleanPremium.primary,
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                          if (subtitle != null &&
                              subtitle!.trim().isNotEmpty &&
                              expanded) ...[
                            const SizedBox(height: 4),
                            Text(
                              subtitle!,
                              style: TextStyle(
                                fontSize: 12,
                                height: 1.3,
                                color: ThemeCleanPremium.onSurfaceVariant
                                    .withValues(alpha: 0.92),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Icon(
                        expanded
                            ? Icons.expand_less_rounded
                            : Icons.expand_more_rounded,
                        color: Colors.grey.shade600,
                        size: 24),
                  ],
                ),
              ),
            ),
            if (expanded)
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
                child: child,
              ),
          ],
        ),
      ),
    );
  }
}

class _ActionChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _ActionChip(
      {required this.icon,
      required this.label,
      required this.color,
      required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: color.withOpacity(0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withOpacity(0.2)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 18, color: color),
            const SizedBox(width: 6),
            Text(label,
                style: TextStyle(
                    fontSize: 12, fontWeight: FontWeight.w700, color: color)),
          ],
        ),
      ),
    );
  }
}

class _DetailSection extends StatelessWidget {
  final String title;
  final List<_DetailRow> items;

  const _DetailSection({required this.title, required this.items});

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 16, bottom: 8),
          child: Text(title,
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: Colors.grey.shade600,
                  letterSpacing: 0.5)),
        ),
        Container(
          decoration: BoxDecoration(
            color: const Color(0xFFF8FAFC),
            borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusMd),
          ),
          child: Column(
            children: [
              for (var i = 0; i < items.length; i++) ...[
                if (i > 0) Divider(height: 1, color: Colors.grey.shade200),
                items[i],
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _DetailRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final bool softWrapValue;

  const _DetailRow({
    required this.icon,
    required this.label,
    required this.value,
    this.softWrapValue = false,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon,
              size: 18, color: ThemeCleanPremium.primary.withOpacity(0.7)),
          const SizedBox(width: 12),
          SizedBox(
            width: 100,
            child: Text(label,
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey.shade600)),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
              softWrap: true,
              maxLines: softWrapValue ? 8 : 4,
              overflow:
                  softWrapValue ? TextOverflow.clip : TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

class _EditField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final IconData icon;
  final TextInputType type;

  const _EditField(
      {required this.controller,
      required this.label,
      required this.icon,
      this.type = TextInputType.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: controller,
        keyboardType: type,
        decoration: InputDecoration(
          labelText: label,
          border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusSm)),
          prefixIcon: Icon(icon),
        ),
      ),
    );
  }
}

class _LinkCadastroPublicoCard extends StatelessWidget {
  final String tenantId;
  final String role;

  const _LinkCadastroPublicoCard({required this.tenantId, required this.role});

  Future<String?> _loadSlug() async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection('igrejas')
          .doc(tenantId)
          .get();
      return (snap.data()?['slug'] ?? snap.data()?['slugId'] ?? '')
          .toString()
          .trim();
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final padding = ThemeCleanPremium.pagePadding(context);
    return FutureBuilder<String?>(
      future: _loadSlug(),
      builder: (context, snap) {
        final slug = snap.data;
        final hasSlug = slug != null && slug.isNotEmpty;
        final loading = snap.connectionState == ConnectionState.waiting;
        String url = '';
        if (hasSlug)
          url = '${AppConstants.publicWebBaseUrl}/igreja/$slug/cadastro-membro';
        return Padding(
          padding:
              EdgeInsets.fromLTRB(padding.horizontal, 8, padding.horizontal, 0),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusMd),
              boxShadow: ThemeCleanPremium.softUiCardShadow,
              border: Border.all(
                  color: ThemeCleanPremium.primary.withOpacity(0.15)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Icon(Icons.link_rounded,
                      color: ThemeCleanPremium.primary, size: 20),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'Link para cadastro público',
                      style:
                          TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
                    ),
                  ),
                ]),
                const SizedBox(height: 8),
                if (loading)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    child: Shimmer.fromColors(
                      baseColor: Colors.grey.shade300,
                      highlightColor: Colors.grey.shade100,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            height: 12,
                            width: 160,
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(6),
                            ),
                          ),
                          const SizedBox(height: 10),
                          Container(
                            height: 10,
                            width: double.infinity,
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(6),
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                else if (!hasSlug) ...[
                  Text(
                    'Membros podem se cadastrar sozinhos por um link. Defina um "slug" (ex: minha-igreja) no Cadastro da Igreja e o link será gerado aqui.',
                    style: TextStyle(
                        fontSize: 12, color: Colors.grey.shade700, height: 1.4),
                  ),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => IgrejaCadastroPage(
                                tenantId: tenantId, role: role))),
                    icon: const Icon(Icons.settings_rounded, size: 18),
                    label: const Text('Ir para Cadastro da Igreja'),
                    style: FilledButton.styleFrom(
                      backgroundColor: ThemeCleanPremium.primary,
                      minimumSize: const Size(48, 40),
                    ),
                  ),
                ] else ...[
                  Text(
                      'Compartilhe este link para novos membros se cadastrarem:',
                      style:
                          TextStyle(fontSize: 12, color: Colors.grey.shade700)),
                  const SizedBox(height: 6),
                  SelectableText(url,
                      style: const TextStyle(
                          fontSize: 13, fontWeight: FontWeight.w600),
                      maxLines: 2),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      OutlinedButton.icon(
                        onPressed: () {
                          if (url.isEmpty) return;
                          Clipboard.setData(ClipboardData(text: url));
                          ScaffoldMessenger.of(context).showSnackBar(
                              ThemeCleanPremium.successSnackBar(
                                  'Link copiado!'));
                        },
                        icon: const Icon(Icons.copy_rounded, size: 18),
                        label: const Text('Copiar link'),
                        style: OutlinedButton.styleFrom(
                            minimumSize: const Size(48, 36)),
                      ),
                      OutlinedButton.icon(
                        onPressed: () {
                          if (url.isEmpty) return;
                          Share.share(
                              'Cadastro de membro — preencha por este link:\n$url',
                              subject: 'Cadastro de membro',
                              sharePositionOrigin:
                                  const Rect.fromLTWH(0, 0, 1, 1));
                        },
                        icon: const Icon(Icons.share_rounded, size: 18),
                        label: const Text('Compartilhar'),
                        style: OutlinedButton.styleFrom(
                            minimumSize: const Size(48, 36)),
                      ),
                      FilledButton.icon(
                        onPressed: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (_) =>
                                    PublicMemberSignupPage(slug: slug))),
                        icon: const Icon(Icons.open_in_new_rounded, size: 18),
                        label: const Text('Abrir formulário'),
                        style: FilledButton.styleFrom(
                            backgroundColor: ThemeCleanPremium.primary,
                            minimumSize: const Size(48, 36)),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}

class _MembersLimitBanner extends StatelessWidget {
  final MembersLimitResult result;

  const _MembersLimitBanner({required this.result});

  @override
  Widget build(BuildContext context) {
    final isBlocked = result.isBlocked;
    final isWarning = result.isOverLimitWarning;
    Color bg;
    IconData icon;
    if (isBlocked) {
      bg = ThemeCleanPremium.error.withOpacity(0.15);
      icon = Icons.block_rounded;
    } else if (isWarning) {
      bg = Colors.orange.shade100;
      icon = Icons.warning_amber_rounded;
    } else {
      bg = ThemeCleanPremium.primary.withOpacity(0.08);
      icon = Icons.people_rounded;
    }
    return Material(
      color: bg,
      child: InkWell(
        onTap: () {
          if (isBlocked || isWarning) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text(result.shortMessage,
                  style: const TextStyle(
                      color: Colors.white, fontWeight: FontWeight.w600)),
              backgroundColor: ThemeCleanPremium.success,
              behavior: SnackBarBehavior.floating,
              action: isBlocked
                  ? SnackBarAction(
                      label: 'Ver planos',
                      textColor: Colors.white,
                      onPressed: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) => const RenewPlanPage())))
                  : null,
            ));
          }
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(
              horizontal: ThemeCleanPremium.spaceMd, vertical: 10),
          child: Row(
            children: [
              Icon(icon,
                  size: 22,
                  color: isBlocked
                      ? ThemeCleanPremium.error
                      : (isWarning
                          ? Colors.orange.shade800
                          : ThemeCleanPremium.primary)),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  result.shortMessage,
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: isBlocked
                          ? ThemeCleanPremium.error
                          : (isWarning
                              ? Colors.orange.shade900
                              : ThemeCleanPremium.onSurfaceVariant)),
                ),
              ),
              if (isBlocked || isWarning)
                Icon(Icons.arrow_forward_ios_rounded,
                    size: 14,
                    color: isBlocked
                        ? ThemeCleanPremium.error
                        : Colors.orange.shade800),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Funções (cargo/acesso) ────────────────────────────────────────────────────
const List<String> _funcoesList = [
  'membro',
  'adm',
  'gestor',
  'pastor',
  'pastora',
  'presbitero',
  'diacono',
  'secretario',
  'tesoureiro',
  'evangelista',
  'musico',
  'auxiliar',
  'divulgacao',
];

String _funcaoLabel(String value) {
  const labels = {
    'membro': 'Membro (acesso limitado)',
    'adm': 'Administrador',
    'gestor': 'Gestor',
    'pastor': 'Pastor(a)',
    'pastora': 'Pastora',
    'presbitero': 'Presbítero',
    'diacono': 'Diácono',
    'secretario': 'Secretário',
    'tesoureiro': 'Tesoureiro',
    'evangelista': 'Evangelista',
    'musico': 'Músico',
    'auxiliar': 'Auxiliar',
    'divulgacao': 'Divulgação',
  };
  return labels[value] ?? value;
}

String _normalizeFuncao(String v) {
  final lower = v
      .trim()
      .toLowerCase()
      .replaceAll('á', 'a')
      .replaceAll('í', 'i')
      .replaceAll('ó', 'o');
  if (lower.isEmpty) return 'membro';
  for (final f in _funcoesList) {
    if (lower == f || lower == v.trim().toLowerCase()) return f;
  }
  if (lower.contains('secretar')) return 'secretario';
  if (lower.contains('presbiter')) return 'presbitero';
  if (lower.contains('diacon')) return 'diacono';
  if (lower.contains('evangel')) return 'evangelista';
  if (lower.contains('music')) return 'musico';
  if (lower.contains('tesour')) return 'tesoureiro';
  if (lower.contains('divulga')) return 'divulgacao';
  if (lower.contains('auxiliar')) return 'auxiliar';
  if (lower == 'pastora') return 'pastora';
  if (lower.contains('pastor')) return 'pastor';
  if (lower.contains('adm') || lower.contains('admin')) return 'adm';
  if (lower.contains('gestor')) return 'gestor';
  return 'membro';
}

// ─── Helpers ──────────────────────────────────────────────────────────────────

/// Une mapas de membro: se [a] não tem URL de foto válida, copia campos de imagem de [b]
/// (ex.: foto em `users` e cadastro vazio em `membros`, ou cópias entre tenants).
///
/// **Importante:** não retornar [a] só porque já tem URL "válida" (ex. avatar Google em `photoURL`):
/// senão a [FOTO_URL_OU_ID] nova do Storage em [b] (membros) nunca entra na lista após salvar.
Map<String, dynamic> _mergeMemberPhotoFields(
    Map<String, dynamic> a, Map<String, dynamic> b) {
  bool hasFirebaseStorageMemberPhoto(Map<String, dynamic> m) {
    for (final k in [
      'foto_url',
      'FOTO_URL_OU_ID',
      'fotoUrl',
      'photoUrl',
      'photoURL'
    ]) {
      final u = sanitizeImageUrl((m[k] ?? '').toString());
      if (u.isNotEmpty &&
          isValidImageUrl(u) &&
          (u.toLowerCase().contains('firebasestorage.googleapis.com') ||
              u.toLowerCase().contains('.firebasestorage.app') ||
              u.toLowerCase().contains('storage.googleapis.com') ||
              u.toLowerCase().startsWith('gs://') ||
              u.toLowerCase().contains('igrejas/'))) {
        return true;
      }
    }
    return false;
  }

  if (hasFirebaseStorageMemberPhoto(b)) {
    final out = Map<String, dynamic>.from(a);
    const keys = [
      'foto_url',
      'FOTO_URL_OU_ID',
      'fotoUrl',
      'photoURL',
      'photoUrl',
      'avatarUrl',
      'foto',
      'photo',
      'imagemUrl',
      'imageUrl',
      'defaultImageUrl',
      'profilePhoto',
      'profilePhotoUrl',
      'picture',
      'pictureUrl',
      'imagemPerfil',
      'urlFoto',
      'fotoPerfil',
    ];
    for (final k in keys) {
      final v = b[k];
      if (v != null && v.toString().trim().isNotEmpty) out[k] = v;
    }
    return out;
  }

  // Sem foto nova no Storage em [b]: mantém [a] se já exibir algo válido.
  if (isValidImageUrl(imageUrlFromMap(a))) return Map<String, dynamic>.from(a);
  if (imageUrlFromMap(b).trim().isEmpty) return Map<String, dynamic>.from(a);
  final out2 = Map<String, dynamic>.from(a);
  const keys2 = [
    'foto_url',
    'FOTO_URL_OU_ID',
    'fotoUrl',
    'photoURL',
    'photoUrl',
    'avatarUrl',
    'foto',
    'photo',
    'imagemUrl',
    'imageUrl',
    'defaultImageUrl',
    'profilePhoto',
    'profilePhotoUrl',
    'picture',
    'pictureUrl',
    'imagemPerfil',
    'urlFoto',
    'fotoPerfil',
  ];
  for (final k in keys2) {
    final v = b[k];
    if (v != null && v.toString().trim().isNotEmpty) out2[k] = v;
  }
  return out2;
}

String _str(Map<String, dynamic> d, String key1,
    [String? key2, String? key3, String? key4, String? key5]) {
  final v = d[key1] ??
      (key2 != null ? d[key2] : null) ??
      (key3 != null ? d[key3] : null) ??
      (key4 != null ? d[key4] : null) ??
      (key5 != null ? d[key5] : null);
  return (v ?? '').toString();
}

/// UID do Firebase quando a foto no Storage foi salva com esse id (doc do membro pode ser CPF).
String? _memberAuthUidFromData(Map<String, dynamic> d) {
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

/// Extrai URL da foto do membro — usa extração centralizada (SafeNetworkImage) para evitar falhas de exibição.
String _photoUrlFromMemberData(Map<String, dynamic> d) => imageUrlFromMap(d);

int? _idadeFromBirthMemberEdit(DateTime birth) {
  final now = DateTime.now();
  var age = now.year - birth.year;
  if (now.month < birth.month ||
      (now.month == birth.month && now.day < birth.day)) age--;
  return age;
}

String _faixaEtariaFromIdadeMemberEdit(int? age) {
  if (age == null) return '';
  if (age <= 12) return '0-12';
  if (age <= 17) return '13-17';
  if (age <= 25) return '18-25';
  if (age <= 35) return '26-35';
  if (age <= 50) return '36-50';
  return '51+';
}

String _normalizeEstadoCivilValue(String raw) {
  final v = raw.trim().toLowerCase();
  if (v.contains('casad')) return 'Casado(a)';
  if (v.contains('divor')) return 'Divorciado(a)';
  if (v.contains('viuv') || v.contains('viúv')) return 'Viúvo(a)';
  if (v.contains('solteir')) return 'Solteiro(a)';
  return 'Solteiro(a)';
}

String _buildFiliacaoLegado(String pai, String mae) {
  if (pai.isEmpty && mae.isEmpty) return '';
  if (pai.isEmpty) return mae;
  if (mae.isEmpty) return pai;
  return '$pai e $mae';
}

Color? _avatarColor(Map<String, dynamic> d, bool hasPhoto) =>
    avatarColorForMember(d, hasPhoto: hasPhoto);

DateTime? _parseDate(dynamic raw) {
  if (raw == null) return null;
  if (raw is Timestamp) return raw.toDate();
  if (raw is DateTime) return raw;
  if (raw is Map) {
    final sec = raw['seconds'] ?? raw['_seconds'];
    if (sec != null)
      return DateTime.fromMillisecondsSinceEpoch((sec as num).toInt() * 1000);
  }
  return null;
}

String _fmtDate(DateTime dt) =>
    '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year}';

String _formatCpf(String cpf) {
  final d = cpf.replaceAll(RegExp(r'\D'), '');
  if (d.length != 11) return cpf;
  return '${d.substring(0, 3)}.${d.substring(3, 6)}.${d.substring(6, 9)}-${d.substring(9)}';
}

/// Avatar do membro: [FotoMembroWidget] com [memberData] para resolver path/`gs://` do cadastro gestor.
class _MemberAvatar extends StatelessWidget {
  final String? photoUrl;
  final Uint8List? memoryPreviewBytes;
  final Map<String, dynamic>? memberData;
  final String name;
  final double radius;
  final Color backgroundColor;
  final String? tenantId;
  final String? memberId;
  final String? cpfDigits;
  final String? authUid;

  /// Limite de decode em cache (lista ~600; detalhe/carteirinha maior).
  final int memCacheMaxPx;

  const _MemberAvatar({
    required this.photoUrl,
    required this.name,
    required this.radius,
    required this.backgroundColor,
    this.memoryPreviewBytes,
    this.memberData,
    this.tenantId,
    this.memberId,
    this.cpfDigits,
    this.authUid,
    this.memCacheMaxPx = 600,
  });

  Widget _letterAvatar() {
    final initial = (name.isNotEmpty ? name[0] : '?').toUpperCase();
    return CircleAvatar(
      radius: radius,
      backgroundColor: backgroundColor,
      child: Text(
        initial,
        style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w800,
            fontSize: radius * 0.9),
      ),
    );
  }

  static int _memCacheDim(BuildContext context, double radius, int maxPx) {
    final dpr = MediaQuery.maybeOf(context)?.devicePixelRatio ?? 1.0;
    return (radius * 2 * dpr).round().clamp(96, maxPx);
  }

  bool _canPreview(String urlKey, String tid, String mid) {
    if (urlKey.isNotEmpty) return true;
    return tid.isNotEmpty && mid.isNotEmpty;
  }

  void _openPreview(
    BuildContext context, {
    required String tid,
    required String mid,
    required String? cpf,
    required String? au,
    required String url,
  }) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => Scaffold(
          appBar: AppBar(
            title: const Text('Foto do perfil'),
            leading: IconButton(
              icon: const Icon(Icons.arrow_back_rounded),
              onPressed: () => Navigator.of(context).maybePop(),
              tooltip: 'Retornar',
            ),
          ),
          body: Center(
            child: InteractiveViewer(
              minScale: 1,
              maxScale: 5,
              child: FotoMembroWidget(
                imageUrl: url,
                size: 360,
                tenantId: tid.isNotEmpty ? tid : null,
                memberId: mid.isNotEmpty ? mid : null,
                cpfDigits: cpf,
                authUid: au,
                memberData: memberData,
                backgroundColor: backgroundColor,
                memCacheWidth: 1400,
                memCacheHeight: 1400,
                fallbackChild: _letterAvatar(),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tid = tenantId?.trim() ?? '';
    final mid = memberId?.trim() ?? '';
    final size = radius * 2;
    final mc = _memCacheDim(context, radius, memCacheMaxPx);
    final cpf = cpfDigits?.replaceAll(RegExp(r'\D'), '');
    final letter = _letterAvatar();
    final au = (authUid ?? '').trim();
    final md = memberData;
    final fromParent = (photoUrl ?? '').trim();
    final urlKey = sanitizeImageUrl(
      fromParent.isNotEmpty
          ? fromParent
          : (md != null ? imageUrlFromMap(md) : ''),
    );
    final rev = md != null ? (memberPhotoDisplayCacheRevision(md) ?? 0) : 0;

    final memberWidget = FotoMembroWidget(
      key: ValueKey<String>(
          'mav_${tid}_${mid}_${urlKey}_${rev}_${memoryPreviewBytes?.length ?? 0}'),
      imageUrl: photoUrl,
      memoryPreviewBytes: memoryPreviewBytes,
      size: size,
      tenantId: tid.isNotEmpty ? tid : null,
      memberId: mid.isNotEmpty ? mid : null,
      cpfDigits: (cpf != null && cpf.length == 11) ? cpf : null,
      authUid: au.isNotEmpty ? au : null,
      memberData: memberData,
      backgroundColor: backgroundColor,
      memCacheWidth: mc,
      memCacheHeight: mc,
      fallbackChild: letter,
    );
    if (!_canPreview(urlKey, tid, mid)) return memberWidget;
    return InkWell(
      customBorder: const CircleBorder(),
      onTap: () => _openPreview(
        context,
        tid: tid,
        mid: mid,
        cpf: (cpf != null && cpf.length == 11) ? cpf : null,
        au: au.isNotEmpty ? au : null,
        url: photoUrl ?? '',
      ),
      child: memberWidget,
    );
  }
}

/// Snapshot vazio para quando não há tenant (evita queries com path inválido).
class _EmptyQuerySnapshot implements QuerySnapshot<Map<String, dynamic>> {
  @override
  final List<QueryDocumentSnapshot<Map<String, dynamic>>> docs = [];
  @override
  List<DocumentChange<Map<String, dynamic>>> get docChanges => [];
  @override
  SnapshotMetadata get metadata => _EmptySnapshotMetadata();
  @override
  int get size => 0;
}

/// Snapshot que junta docs de várias queries (ex.: members de vários tenants com mesmo slug/alias).
class _MergedQuerySnapshot implements QuerySnapshot<Map<String, dynamic>> {
  @override
  final List<QueryDocumentSnapshot<Map<String, dynamic>>> docs;
  _MergedQuerySnapshot(this.docs);
  @override
  List<DocumentChange<Map<String, dynamic>>> get docChanges => [];
  @override
  SnapshotMetadata get metadata => _EmptySnapshotMetadata();
  @override
  int get size => docs.length;
}

class _EmptySnapshotMetadata implements SnapshotMetadata {
  @override
  bool get hasPendingWrites => false;
  @override
  bool get isFromCache => false;
}
