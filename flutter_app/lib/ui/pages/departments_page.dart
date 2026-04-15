import 'dart:async';
import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/gestures.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:gestao_yahweh/services/app_permissions.dart';
import 'package:gestao_yahweh/core/app_constants.dart';
import 'package:gestao_yahweh/core/church_department_visual_mapper.dart';
import 'package:gestao_yahweh/core/church_department_fa_icons.dart';
import 'package:gestao_yahweh/core/church_department_leaders.dart';
import 'package:gestao_yahweh/services/church_departments_bootstrap.dart';
import 'package:gestao_yahweh/services/department_member_integration_service.dart';
import 'package:gestao_yahweh/services/tenant_resolver_service.dart';
import 'package:gestao_yahweh/utils/church_department_list.dart'
    show
        churchDepartmentDocHasExplicitNameField,
        churchDepartmentDocIsActive,
        churchDepartmentFoldAsciiForDocId,
        churchDepartmentNameFromData,
        churchDepartmentNameFromDoc,
        churchDepartmentStableDocIdCandidate,
        dedupeChurchDepartmentDocumentsForHub,
        normalizeChurchDepartmentNameKey;
import 'package:gestao_yahweh/ui/theme_clean_premium.dart';
import 'package:gestao_yahweh/ui/widgets/church_panel_ui_helpers.dart';
import 'package:gestao_yahweh/ui/widgets/foto_membro_widget.dart';
import 'package:gestao_yahweh/ui/widgets/safe_network_image.dart'
    show
        imageUrlFromMap;
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';
import 'package:flutter/services.dart';
import 'package:flutter_staggered_animations/flutter_staggered_animations.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

class DepartmentsPage extends StatefulWidget {
  final String tenantId;
  final String role;
  /// Módulos extras (ex.: `departamentos`) vindos de `users.permissions` / painel do gestor.
  final List<String>? permissions;
  /// Dentro de [IgrejaCleanShell]: evita [SafeArea] superior extra sob o cartão do módulo.
  final bool embeddedInShell;
  const DepartmentsPage({
    super.key,
    required this.tenantId,
    required this.role,
    this.permissions,
    this.embeddedInShell = false,
  });

  @override
  State<DepartmentsPage> createState() => _DepartmentsPageState();
}

class _DepartmentsPageState extends State<DepartmentsPage> {
  /// Carregamento explícito: na web + IndexedStack o FutureBuilder às vezes não reconstrói após o .get() — área ficava em branco.
  bool _deptLoading = true;
  Object? _deptError;

  /// Snapshot do último `.get()` bem-sucedido. Na web o `snapshots()` pode emitir cache vazio antes do listener
  /// popular — evita hub sem cards até o stream alinhar.
  List<QueryDocumentSnapshot<Map<String, dynamic>>>? _hydratedDeptDocs;

  /// Evita loop em [StreamBuilder] quando cache veio vazio: uma leitura forçada no servidor.
  bool _emptyServerDeptFetchTried = false;

  /// O [snapshots] falhou (comum na web/offline) e o `.get()` de recuperação também falhou.
  bool _streamRecoveryFailed = false;

  bool _deptStreamRecoveryInFlight = false;

  /// ID do documento da igreja (resolve slug/alias) — mesmo path do dashboard.
  String _effectiveTenantId = '';

  /// Nomes de membros por CPF (11 dígitos) para exibir líderes nos cards.
  Map<String, String> _cpfToMemberName = const {};

  /// [true] após a primeira tentativa de montar o mapa (mesmo se vazio).
  bool _memberLookupDone = false;

  /// 0 = ativos, 1 = arquivados (inativos).
  int _deptListTab = 0;

  /// Membros por id do documento do departamento (pré-visualização na lista).
  Map<String, List<QueryDocumentSnapshot<Map<String, dynamic>>>> _membersByDeptId =
      const {};

  /// CPF canónico (11 dígitos) → doc em [membros] (foto do líder na lista).
  Map<String, QueryDocumentSnapshot<Map<String, dynamic>>> _memberDocByNormCpf =
      const {};

  String get _tid =>
      _effectiveTenantId.isNotEmpty ? _effectiveTenantId : widget.tenantId;

  @override
  void initState() {
    super.initState();
    _effectiveTenantId = widget.tenantId;
    _startDeptLoad();
  }

  @override
  void didUpdateWidget(covariant DepartmentsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.tenantId != widget.tenantId) {
      _effectiveTenantId = widget.tenantId;
      _hydratedDeptDocs = null;
      _cpfToMemberName = const {};
      _membersByDeptId = const {};
      _memberDocByNormCpf = const {};
      _deptListTab = 0;
      _memberLookupDone = false;
      _emptyServerDeptFetchTried = false;
      _streamRecoveryFailed = false;
      _startDeptLoad(forceServer: true);
    }
  }

  Future<void> _startDeptLoad({bool forceServer = false}) async {
    if (!mounted) return;
    setState(() {
      _deptLoading = true;
      _deptError = null;
      _streamRecoveryFailed = false;
    });
    try {
      final loaded = await _resolveTenantAndLoad(forceServer: forceServer);
      if (!mounted) return;
      setState(() {
        _deptLoading = false;
        _deptError = null;
        _hydratedDeptDocs = loaded.docs.isNotEmpty
            ? List<QueryDocumentSnapshot<Map<String, dynamic>>>.from(
                loaded.docs)
            : null;
      });
      unawaited(_loadMemberCpfLookup());
    } catch (e, st) {
      debugPrint('DepartmentsPage._startDeptLoad: $e\n$st');
      if (!mounted) return;
      setState(() {
        _deptLoading = false;
        _deptError = e;
        _hydratedDeptDocs = null;
      });
    }
  }

  /// Resolve tenant; para quem pode editar: kit vazio + **presets em falta** + backfill de metadados.
  /// O botão “Gravar no sistema” continua útil para forçar sincronização manual.
  Future<QuerySnapshot<Map<String, dynamic>>> _resolveTenantAndLoad(
      {bool forceServer = false}) async {
    // Mesmo doc canónico que Pastoral / Escalas: onde há `departamentos` preenchidos
    // (evita lista vazia no doc "principal" quando os dados estão no irmão _sistema/_bpc).
    try {
      _effectiveTenantId = await TenantResolverService
          .resolveChurchDocIdPreferringNonEmptyDepartments(widget.tenantId);
    } catch (_) {
      try {
        _effectiveTenantId =
            await TenantResolverService.resolveEffectiveTenantId(widget.tenantId);
      } catch (_) {
        _effectiveTenantId = widget.tenantId;
      }
    }
    final tid = _tid.trim();
    if (tid.isNotEmpty) {
      await _bootstrapDefaultDepartmentsIfAllowed(tid);
    }
    var loaded = await _loadDepartments(forceServer: forceServer);
    // Na web/PWA o cache pode estar vazio enquanto o servidor já tem os docs; o retry
    // seguinte só rodava para quem pode editar — leitura ficava em branco para outros papéis.
    if (loaded.docs.isEmpty && tid.isNotEmpty && !forceServer) {
      try {
        loaded = await _loadDepartments(forceServer: true);
      } catch (e) {
        debugPrint('DepartmentsPage fallback servidor (cache vazio): $e');
      }
    }
    // Igreja “irmã” (ex.: mesmo slug, doc _sistema/_bpc) pode ser onde os departamentos foram gravados.
    if (loaded.docs.isEmpty && tid.isNotEmpty) {
      try {
        final alt = await TenantResolverService
            .resolveChurchDocIdPreferringNonEmptyDepartments(tid);
        if (alt.isNotEmpty && alt != tid) {
          _effectiveTenantId = alt;
          loaded = await _loadDepartments(forceServer: true);
        }
      } catch (e) {
        debugPrint('DepartmentsPage resolve id com departamentos: $e');
      }
    }
    if (loaded.docs.isEmpty && tid.isNotEmpty) {
      final bootstrapTid = _tid.trim();
      if (bootstrapTid.isNotEmpty) {
        await _bootstrapDefaultDepartmentsIfAllowed(bootstrapTid);
      }
      try {
        loaded = await _loadDepartments(forceServer: true);
      } catch (e) {
        debugPrint('DepartmentsPage segunda tentativa após bootstrap: $e');
      }
    }
    return loaded;
  }

  CollectionReference<Map<String, dynamic>> _departamentosCol(String tid) =>
      FirebaseFirestore.instance
          .collection('igrejas')
          .doc(tid)
          .collection('departamentos');

  void _onDepartmentsBootstrapError(Object e) {
    if (!mounted) return;
    if (e is FirebaseException && e.code == 'permission-denied') {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text(
              'Sem permissão para criar o kit de departamentos. Atualize o app, publique as regras do Firebase e confira seu papel (Gestor/Pastor).',
              style: TextStyle(color: Colors.white),
            ),
            backgroundColor: const Color(0xFFB45309),
            duration: const Duration(seconds: 8),
          ),
        );
      });
    }
  }

  /// Garante os 11 padrões no servidor: subcoleção vazia (welcome kit) + ids de preset em falta + metadados.
  Future<void> _bootstrapDefaultDepartmentsIfAllowed(String tid) async {
    if (!AppPermissions.canEditDepartments(widget.role,
        permissions: widget.permissions)) {
      return;
    }
    final col = _departamentosCol(tid);
    try {
      await FirebaseAuth.instance.currentUser?.getIdToken(true);
    } catch (_) {}
    try {
      await ChurchDepartmentsBootstrap.ensureWelcomeKitDocuments(
        col,
        refreshToken: false,
        onError: _onDepartmentsBootstrapError,
      );
    } catch (e) {
      debugPrint('DepartmentsPage.ensureWelcomeKitDocuments: $e');
    }
    try {
      await ChurchDepartmentsBootstrap.ensureMissingPresetDocuments(
        col,
        refreshToken: false,
        onError: _onDepartmentsBootstrapError,
      );
    } catch (e) {
      debugPrint('DepartmentsPage.ensureMissingPresetDocuments: $e');
    }
    try {
      await ChurchDepartmentsBootstrap.backfillPresetMetadataWhereMissing(
        col,
        refreshToken: false,
      );
    } catch (e) {
      debugPrint('DepartmentsPage.backfillPresetMetadata: $e');
    }
  }

  /// Cria no Firestore cada preset cujo id ainda não existe (lógica compartilhada com Escalas).
  Future<bool> _ensureMissingPresetDocuments() async {
    if (!_canWrite) return false;
    try {
      await FirebaseAuth.instance.currentUser?.getIdToken(true);
    } catch (_) {}
    return ChurchDepartmentsBootstrap.ensureMissingPresetDocuments(_col,
        refreshToken: false);
  }

  /// Sem `orderBy` no Firestore: evita índice composto; ordena no cliente.
  /// Primeiro cache (rápido na reabertura); se vazio ou [forceServer], confirma no servidor.
  Future<QuerySnapshot<Map<String, dynamic>>> _loadDepartments(
      {bool forceServer = true}) async {
    if (!forceServer) {
      try {
        return await _col
            .get(const GetOptions(source: Source.serverAndCache))
            .timeout(const Duration(seconds: 20));
      } on TimeoutException catch (e) {
        debugPrint('DepartmentsPage._loadDepartments cache-only timeout: $e');
        return _col.get(const GetOptions(source: Source.serverAndCache));
      }
    }
    try {
      final cached = await _col
          .get(const GetOptions(source: Source.serverAndCache))
          .timeout(const Duration(seconds: 14));
      if (cached.docs.isNotEmpty) return cached;
    } on TimeoutException catch (e) {
      debugPrint('DepartmentsPage._loadDepartments cache-first timeout: $e');
    } catch (e) {
      debugPrint('DepartmentsPage._loadDepartments cache-first: $e');
    }
    try {
      return await _col
          .get(const GetOptions(source: Source.server))
          .timeout(const Duration(seconds: 28));
    } on TimeoutException catch (e) {
      debugPrint('DepartmentsPage._loadDepartments server timeout: $e');
      return _col
          .get(const GetOptions(source: Source.serverAndCache))
          .timeout(const Duration(seconds: 20));
    }
  }

  /// União stream + hidratação: evita lista só com o banner “Hub” quando o cache do stream vem vazio ou parcial.
  List<QueryDocumentSnapshot<Map<String, dynamic>>> _mergeDeptStreamAndHydrated(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> streamDocs,
    List<QueryDocumentSnapshot<Map<String, dynamic>>>? hydrated,
  ) {
    final byId = <String, QueryDocumentSnapshot<Map<String, dynamic>>>{};
    for (final d in hydrated ??
        const <QueryDocumentSnapshot<Map<String, dynamic>>>[]) {
      byId[d.id] = d;
    }
    for (final d in streamDocs) {
      byId[d.id] = d;
    }
    return byId.values.toList();
  }

  Future<void> _loadMemberCpfLookup() async {
    final tid = _tid.trim();
    if (tid.isEmpty) return;
    try {
      final snap = await FirebaseFirestore.instance
          .collection('igrejas')
          .doc(tid)
          .collection('membros')
          .limit(800)
          .get(const GetOptions(source: Source.serverAndCache));
      final map = <String, String>{};
      final byDept =
          <String, List<QueryDocumentSnapshot<Map<String, dynamic>>>>{};
      final byCpf = <String, QueryDocumentSnapshot<Map<String, dynamic>>>{};

      String memberSortKey(QueryDocumentSnapshot<Map<String, dynamic>> d) {
        final data = d.data();
        final t = (data['NOME_COMPLETO'] ??
                data['nome'] ??
                data['name'] ??
                '')
            .toString()
            .trim()
            .toLowerCase();
        return t.isEmpty ? d.id.toLowerCase() : t;
      }

      for (final d in snap.docs) {
        final data = d.data();
        final nome = (data['NOME_COMPLETO'] ??
                data['nome'] ??
                data['name'] ??
                '')
            .toString()
            .trim();
        final cpfRaw = (data['CPF'] ?? data['cpf'] ?? '').toString();
        final digits = cpfRaw.replaceAll(RegExp(r'\D'), '');
        if (digits.length >= 9 && digits.length <= 11) {
          final c = ChurchDepartmentLeaders.canonicalCpfDigits(digits);
          byCpf[c] = d;
          if (nome.isNotEmpty) {
            map[c] = nome;
          }
        }

        final deptIds = <String>{};
        void addDeptId(Object? raw) {
          final s = (raw ?? '').toString().trim();
          if (s.isNotEmpty) deptIds.add(s);
        }

        for (final e in (data['DEPARTAMENTOS'] as List?) ?? const []) {
          addDeptId(e);
        }
        for (final e in (data['departamentosIds'] as List?) ?? const []) {
          addDeptId(e);
        }
        for (final deptId in deptIds) {
          byDept.putIfAbsent(deptId, () => []).add(d);
        }
      }

      for (final e in byDept.entries) {
        e.value.sort(
            (a, b) => memberSortKey(a).compareTo(memberSortKey(b)));
        if (e.value.length > 48) {
          e.value.removeRange(48, e.value.length);
        }
      }

      if (!mounted) return;
      setState(() {
        _cpfToMemberName = map;
        _membersByDeptId = byDept;
        _memberDocByNormCpf = byCpf;
        _memberLookupDone = true;
      });
    } catch (e) {
      debugPrint('DepartmentsPage._loadMemberCpfLookup: $e');
      if (mounted) {
        setState(() => _memberLookupDone = true);
      }
    }
  }

  void _refreshDepartments({bool forceServer = false}) {
    _emptyServerDeptFetchTried = false;
    _startDeptLoad(forceServer: forceServer);
  }

  Future<void> _fetchDepartmentsFromServerOnce() async {
    if (_tid.trim().isEmpty) return;
    try {
      await FirebaseAuth.instance.currentUser?.getIdToken(true);
    } catch (_) {}
    try {
      final s = await _col
          .get(const GetOptions(source: Source.server))
          .timeout(const Duration(seconds: 28));
      if (!mounted) return;
      if (s.docs.isNotEmpty) {
        setState(() {
          _hydratedDeptDocs =
              List<QueryDocumentSnapshot<Map<String, dynamic>>>.from(s.docs);
        });
      }
    } catch (e) {
      debugPrint('DepartmentsPage._fetchDepartmentsFromServerOnce: $e');
    }
  }

  /// Quando [snapshots] emite erro (web/rede), tenta o mesmo path com [.get] no servidor.
  Future<void> _recoverDeptStreamFailure() async {
    if (!mounted || _tid.trim().isEmpty || _deptStreamRecoveryInFlight) return;
    _deptStreamRecoveryInFlight = true;
    try {
      await FirebaseAuth.instance.currentUser?.getIdToken(true);
    } catch (_) {}
    try {
      final s = await _col
          .get(const GetOptions(source: Source.server))
          .timeout(const Duration(seconds: 28));
      if (!mounted) return;
      setState(() {
        _hydratedDeptDocs =
            List<QueryDocumentSnapshot<Map<String, dynamic>>>.from(s.docs);
        _streamRecoveryFailed = false;
      });
    } catch (e, st) {
      debugPrint('DepartmentsPage._recoverDeptStreamFailure: $e\n$st');
      if (mounted) {
        setState(() => _streamRecoveryFailed = true);
      }
    } finally {
      _deptStreamRecoveryInFlight = false;
    }
  }

  /// [LayoutBuilder] + [SizedBox] com altura 0 (web/shell) deixava a lista invisível — ocupa todo o [Expanded].
  /// Na web não usa pull-to-refresh (há botão Atualizar).
  Widget _webSafeDeptScroller({
    required Future<void> Function() onRefresh,
    required List<Widget> slivers,
  }) {
    final effectiveSlivers = slivers.isEmpty
        ? <Widget>[
            SliverFillRemaining(
              hasScrollBody: false,
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: _emptyDepartmentsMessage(),
                ),
              ),
            ),
          ]
        : slivers;
    final scroll = CustomScrollView(
      primary: false,
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: effectiveSlivers,
    );
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
          : RefreshIndicator(
              onRefresh: onRefresh,
              child: scroll,
            ),
    );
  }

  /// Lista vazia / sem presets — mensagem estável (evita sensação de “tela quebrada”).
  Widget _emptyDepartmentsMessage() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          Icons.handshake_rounded,
          size: 52,
          color: ThemeCleanPremium.primary.withValues(alpha: 0.42),
        ),
        const SizedBox(height: 18),
        Text(
          'Nenhum departamento encontrado. Consagre seus planos ao Senhor.',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: ThemeCleanPremium.onSurface,
            fontSize: 16,
            fontWeight: FontWeight.w700,
            height: 1.4,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          'Toque em Atualizar ou em Gravar padrões.',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: ThemeCleanPremium.onSurfaceVariant,
            fontSize: 13,
            height: 1.35,
          ),
        ),
      ],
    );
  }

  /// Hub com cards — [CustomScrollView] + slivers (web + [IndexedStack]: mais estável que
  /// [SingleChildScrollView] + [SizedBox.expand], que às vezes deixava a área dos cards em branco).
  Widget _deptHubCustomScrollView({
    required Future<void> Function() onRefresh,
    required List<Widget> slivers,
    bool useStaggerOnList = false,
  }) {
    final scroll = CustomScrollView(
      primary: false,
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: slivers,
    );
    final limited =
        useStaggerOnList ? AnimationLimiter(child: scroll) : scroll;
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
          ? limited
          : RefreshIndicator(
              onRefresh: onRefresh,
              child: limited,
            ),
    );
  }

  Future<void> _manualEnsurePresets() async {
    if (!_canWrite || !mounted) return;
    try {
      await FirebaseAuth.instance.currentUser?.getIdToken();
    } catch (_) {}
    final added = await _ensureMissingPresetDocuments();
    final patched =
        await ChurchDepartmentsBootstrap.backfillPresetMetadataWhereMissing(
      _col,
      refreshToken: false,
    );
    if (!mounted) return;
    if (added || patched > 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        ThemeCleanPremium.successSnackBar(
          added
              ? 'Catálogo sincronizado: documentos criados ou atualizados.'
              : 'Metadados do catálogo atualizados nos departamentos existentes.',
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        ThemeCleanPremium.successSnackBar(
            'Todos os departamentos padrão já estão cadastrados.'),
      );
    }
    await _startDeptLoad(forceServer: true);
  }

  /// Abre sheet com lista de membros do departamento; permite remover membro (lançado errado).
  Future<void> _verMembrosDoDepartamento({
    required BuildContext context,
    required String deptId,
    required String deptName,
  }) async {
    final membrosSnap = await FirebaseFirestore.instance
        .collection('igrejas')
        .doc(_tid)
        .collection('membros')
        .where('DEPARTAMENTOS', arrayContains: deptId)
        .get();
    final membros = membrosSnap.docs;
    if (!context.mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => _VerMembrosSheet(
        tenantId: _tid,
        deptId: deptId,
        deptName: deptName,
        members: membros,
        membersCol: _membersCol,
        canRemove: _canWrite,
        onRemoved: () {
          _refreshDepartments(forceServer: true);
        },
      ),
    );
  }

  /// Exclui o departamento e remove o vínculo de todos os membros.
  Future<void> _excluirDepartamento(
      DocumentSnapshot<Map<String, dynamic>> doc) async {
    if (!_canWrite) return;
    final name = churchDepartmentNameFromData(doc.data() ?? {},
        docId: doc.id);
    var vinculados = 0;
    try {
      final q = await _membersCol
          .where('DEPARTAMENTOS', arrayContains: doc.id)
          .count()
          .get();
      vinculados = q.count ?? 0;
    } catch (_) {
      try {
        final snap = await _membersCol
            .where('DEPARTAMENTOS', arrayContains: doc.id)
            .limit(500)
            .get();
        vinculados = snap.size;
      } catch (_) {}
    }
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusLg)),
        title: const Row(children: [
          Icon(Icons.delete_outline_rounded, color: Color(0xFFDC2626)),
          SizedBox(width: 10),
          Text('Excluir departamento')
        ]),
        content: Text(
            'Excluir o departamento "$name"?\n\n'
            '${vinculados > 0 ? 'Há $vinculados membro(s) vinculado(s). ' : ''}'
            'Os vínculos serão removidos automaticamente.'),
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
    try {
      await FirebaseAuth.instance.currentUser?.getIdToken(true);
      await DepartmentMemberIntegrationService.deleteAllLinkedMembersDocs(
        tenantId: _tid,
        departmentId: doc.id,
      );
      final batch = FirebaseFirestore.instance.batch();
      final membersSnap = await _membersCol.get();
      for (final m in membersSnap.docs) {
        final depts = List<String>.from(
            (m.data()['DEPARTAMENTOS'] as List?)?.map((e) => e.toString()) ??
                []);
        if (depts.contains(doc.id)) {
          batch.update(_membersCol.doc(m.id), {
            'DEPARTAMENTOS': FieldValue.arrayRemove([doc.id]),
            'departamentosIds': FieldValue.arrayRemove([doc.id]),
            'DEPARTAMENTOS_ATUALIZADO_EM': FieldValue.serverTimestamp(),
          });
        }
      }
      batch.delete(doc.reference);
      await batch.commit();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Departamento excluído.',
                style: TextStyle(color: Colors.white)),
            backgroundColor: Colors.green));
        _refreshDepartments(forceServer: true);
      }
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Erro ao excluir: $e')));
    }
  }

  /// Abre tela para vincular/desvincular membros ao departamento (controle de escalas).
  Future<void> _openDepartmentInviteSheet({
    required String deptId,
    required String deptName,
  }) async {
    final link = AppConstants.departmentInviteUrl(_tid, deptId);
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        final bottom = MediaQuery.viewInsetsOf(ctx).bottom;
        return Padding(
          padding: EdgeInsets.fromLTRB(24, 16, 24, 24 + bottom),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Convidar — $deptName',
                  style: const TextStyle(
                      fontSize: 18, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 8),
                Text(
                  'O membro abre o link já logado na mesma igreja; a ficha (CPF) é vinculada a este departamento.',
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.grey.shade700,
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: 20),
                Center(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: ColoredBox(
                      color: Colors.white,
                      child: QrImageView(
                        data: link,
                        version: QrVersions.auto,
                        size: 200,
                        backgroundColor: Colors.white,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                SelectableText(
                  link,
                  style: TextStyle(fontSize: 12, color: Colors.blue.shade800),
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: () async {
                    await Clipboard.setData(ClipboardData(text: link));
                    if (ctx.mounted) {
                      ScaffoldMessenger.of(ctx).showSnackBar(
                        ThemeCleanPremium.successSnackBar('Link copiado'),
                      );
                    }
                  },
                  icon: const Icon(Icons.copy_rounded),
                  label: const Text('Copiar link'),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: () => Share.share(
                    'Entre no departamento "$deptName" pela Gestão YAHWEH:\n$link',
                    subject: 'Convite — $deptName',
                  ),
                  icon: const Icon(Icons.share_rounded),
                  label: const Text('Compartilhar'),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _vincularMembros({
    required BuildContext context,
    required String deptId,
    required String deptName,
  }) async {
    if (!_canWrite) return;
    try {
      final membersSnap = await _membersCol.get();
      final members = membersSnap.docs;
      if (members.isEmpty) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text(
                    'Não há membros cadastrados. Cadastre membros em Pessoas > Membros.')),
          );
        }
        return;
      }
      final selecionados = <String>{};
      for (final doc in members) {
        final depts = (doc.data()['DEPARTAMENTOS'] as List?)
                ?.map((e) => e.toString())
                .toList() ??
            [];
        if (depts.contains(deptId)) selecionados.add(doc.id);
      }
      if (!context.mounted) return;
      final result = await showModalBottomSheet<Set<String>>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
        builder: (ctx) => _VincularMembrosSheet(
          tenantId: _tid,
          deptName: deptName,
          members: members,
          selecionados: selecionados,
        ),
      );
      if (result == null || !mounted) return;
      await FirebaseAuth.instance.currentUser?.getIdToken(true);
      for (final doc in members) {
        final id = doc.id;
        final estava = selecionados.contains(id);
        final ficou = result.contains(id);
        if (estava == ficou) continue;
        final data = doc.data();
        if (ficou) {
          await DepartmentMemberIntegrationService.linkMember(
            tenantId: _tid,
            departmentId: deptId,
            memberDocId: id,
            memberData: data,
          );
        } else {
          await DepartmentMemberIntegrationService.unlinkMember(
            tenantId: _tid,
            departmentId: deptId,
            memberDocId: id,
            memberData: data,
          );
        }
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text(
                  'Membros atualizados. Use esse vínculo para escalas e reuniões.',
                  style: TextStyle(color: Colors.white)),
              backgroundColor: Colors.green),
        );
        _refreshDepartments(forceServer: true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao vincular membros: $e')),
        );
      }
    }
  }

  bool get _canWrite => AppPermissions.canEditDepartments(widget.role,
      permissions: widget.permissions);

  bool _hasDuplicateDepartmentNames(
      List<QueryDocumentSnapshot<Map<String, dynamic>>> docs) {
    final seen = <String>{};
    for (final d in docs) {
      final k = normalizeChurchDepartmentNameKey(
          churchDepartmentNameFromDoc(d));
      if (k.isEmpty) continue;
      if (seen.contains(k)) return true;
      seen.add(k);
    }
    return false;
  }

  CollectionReference<Map<String, dynamic>> get _col =>
      FirebaseFirestore.instance
          .collection('igrejas')
          .doc(_tid)
          .collection('departamentos');

  CollectionReference<Map<String, dynamic>> get _membersCol =>
      FirebaseFirestore.instance
          .collection('igrejas')
          .doc(_tid)
          .collection('membros');

  bool _deptIdPreferCanonical(String id) =>
      !RegExp(r'_\d+$').hasMatch(id.trim());

  /// Evita `add()` com ID aleatório e duplicatas (ex.: criancas + criancas_2 com o mesmo nome).
  /// Retorna `true` se atualizou documento já existente (mesmo nome ou id estável ocupado com nome vazio).
  Future<bool> _persistNewDepartment({
    required Map<String, dynamic> payload,
    required String iconKey,
  }) async {
    final nome = (payload['name'] ?? '').toString().trim();
    final norm = normalizeChurchDepartmentNameKey(nome);
    if (norm.isEmpty) return false;

    final snap =
        await _col.get(const GetOptions(source: Source.server));
    QueryDocumentSnapshot<Map<String, dynamic>>? sameNameBest;
    for (final d in snap.docs) {
      if (normalizeChurchDepartmentNameKey(churchDepartmentNameFromDoc(d)) !=
          norm) {
        continue;
      }
      if (sameNameBest == null) {
        sameNameBest = d;
        continue;
      }
      final a = d;
      final b = sameNameBest;
      if (_deptIdPreferCanonical(a.id) && !_deptIdPreferCanonical(b.id)) {
        sameNameBest = a;
      } else if (_deptIdPreferCanonical(a.id) == _deptIdPreferCanonical(b.id) &&
          a.id.length < b.id.length) {
        sameNameBest = a;
      }
    }
    if (sameNameBest != null) {
      await sameNameBest.reference.set(payload, SetOptions(merge: true));
      return true;
    }

    var id = churchDepartmentStableDocIdCandidate(nome, iconKey);
    if (id.isEmpty) id = 'departamento';
    final ref = _col.doc(id);
    final existing = await ref.get();
    if (!existing.exists) {
      await ref.set({
        ...payload,
        'createdAt': Timestamp.now(),
      });
      return false;
    }
    final exData = existing.data() ?? {};
    final exName =
        churchDepartmentNameFromData(exData, docId: existing.id).trim();
    if (normalizeChurchDepartmentNameKey(exName) == norm || exName.isEmpty) {
      await ref.set(payload, SetOptions(merge: true));
      return true;
    }
    final copy = Map<String, dynamic>.from(payload);
    copy['createdAt'] = Timestamp.now();
    await _col.add(copy);
    return false;
  }

  /// Opções de ícone para departamentos — ordem alfabética via _iconOptionsSorted.
  /// Inclui keys legadas (kids, men, women, welcome, youth, worship, prayer) para compatibilidade.
  static const _iconOptions = <Map<String, dynamic>>[
    {
      'key': 'auxiliares',
      'label': 'Auxiliares',
      'icon': Icons.support_rounded,
      'color': 0xFF6A1B9A
    },
    {
      'key': 'kids',
      'label': 'Crianças',
      'icon': Icons.child_care_rounded,
      'color': 0xFF4FC3F7
    },
    {
      'key': 'men',
      'label': 'Varões',
      'icon': Icons.groups_rounded,
      'color': 0xFF81C784
    },
    {
      'key': 'women',
      'label': 'Mulheres',
      'icon': Icons.people_rounded,
      'color': 0xFFE57373
    },
    {
      'key': 'welcome',
      'label': 'Recepção',
      'icon': Icons.waving_hand_rounded,
      'color': 0xFFFF8A65
    },
    {
      'key': 'youth',
      'label': 'Jovens',
      'icon': Icons.bolt_rounded,
      'color': 0xFFBA68C8
    },
    {
      'key': 'worship',
      'label': 'Louvor',
      'icon': Icons.music_note_rounded,
      'color': 0xFFFFB74D
    },
    {
      'key': 'prayer',
      'label': 'Oração',
      'icon': Icons.auto_awesome_rounded,
      'color': 0xFFAED581
    },
    {
      'key': 'comunicacao',
      'label': 'Comunicação',
      'icon': Icons.campaign_rounded,
      'color': 0xFF0097A7
    },
    {
      'key': 'criancas',
      'label': 'Crianças',
      'icon': Icons.child_care_rounded,
      'color': 0xFF4FC3F7
    },
    {
      'key': 'diaconal',
      'label': 'Diaconal',
      'icon': Icons.volunteer_activism_rounded,
      'color': 0xFF8D6E63
    },
    {
      'key': 'evangelismo',
      'label': 'Evangelismo',
      'icon': Icons.record_voice_over_rounded,
      'color': 0xFF7B1FA2
    },
    {
      'key': 'finance',
      'label': 'Financeiro',
      'icon': Icons.account_balance_wallet_rounded,
      'color': 0xFF90A4AE
    },
    {
      'key': 'escola_biblica',
      'label': 'Escola Bíblica',
      'icon': Icons.menu_book_rounded,
      'color': 0xFF00897B
    },
    {
      'key': 'intercessao',
      'label': 'Intercessão',
      'icon': Icons.favorite_rounded,
      'color': 0xFFD32F2F
    },
    {
      'key': 'jovens',
      'label': 'Jovens',
      'icon': Icons.bolt_rounded,
      'color': 0xFFBA68C8
    },
    {
      'key': 'louvor',
      'label': 'Louvor',
      'icon': Icons.music_note_rounded,
      'color': 0xFFFFB74D
    },
    {
      'key': 'media',
      'label': 'Mídia',
      'icon': Icons.videocam_rounded,
      'color': 0xFF64B5F6
    },
    {
      'key': 'missionarios',
      'label': 'Missionários',
      'icon': Icons.public_rounded,
      'color': 0xFF607D8B
    },
    {
      'key': 'mulheres',
      'label': 'Mulheres',
      'icon': Icons.people_rounded,
      'color': 0xFFE57373
    },
    {
      'key': 'obreiros',
      'label': 'Obreiros',
      'icon': Icons.construction_rounded,
      'color': 0xFF5D4037
    },
    {
      'key': 'oracao',
      'label': 'Oração',
      'icon': Icons.auto_awesome_rounded,
      'color': 0xFFAED581
    },
    {
      'key': 'pastoral',
      'label': 'Pastoral',
      'icon': Icons.church_rounded,
      'color': 0xFF4CAF50
    },
    {
      'key': 'presbiteros',
      'label': 'Presbíteros',
      'icon': Icons.gavel_rounded,
      'color': 0xFF1565C0
    },
    {
      'key': 'recepcao',
      'label': 'Recepção',
      'icon': Icons.waving_hand_rounded,
      'color': 0xFFFF8A65
    },
    {
      'key': 'secretarios',
      'label': 'Secretários',
      'icon': Icons.description_rounded,
      'color': 0xFF3949AB
    },
    {
      'key': 'social',
      'label': 'Social',
      'icon': Icons.volunteer_activism_rounded,
      'color': 0xFF00897B
    },
    {
      'key': 'tesouraria',
      'label': 'Tesouraria',
      'icon': Icons.savings_rounded,
      'color': 0xFF2E7D32
    },
    {
      'key': 'varoes',
      'label': 'Varões',
      'icon': Icons.groups_rounded,
      'color': 0xFF81C784
    },
  ];

  /// Keys legadas em inglês — mesma figura que a opção em PT; não repetir no grid.
  static const _legacyIconKeys = {
    'kids',
    'men',
    'women',
    'welcome',
    'youth',
    'worship',
    'prayer'
  };

  /// Uma opção por rótulo (evita Crianças/Jovens/etc. duplicados); prioriza chave em português.
  static List<Map<String, dynamic>> get _iconOptionsSorted {
    final byLabel = <String, Map<String, dynamic>>{};
    for (final e in _iconOptions) {
      final label = ((e['label'] as String).trim()).toLowerCase();
      final key = e['key'] as String;
      final cur = byLabel[label];
      if (cur == null) {
        byLabel[label] = e;
        continue;
      }
      final curKey = cur['key'] as String;
      final curLegacy = _legacyIconKeys.contains(curKey);
      final newLegacy = _legacyIconKeys.contains(key);
      if (curLegacy && !newLegacy) {
        byLabel[label] = e;
      } else if (curLegacy == newLegacy &&
          !newLegacy &&
          key.compareTo(curKey) < 0) {
        byLabel[label] = e;
      }
    }
    final list = byLabel.values.toList();
    list.sort((a, b) => (a['label'] as String)
        .toLowerCase()
        .compareTo((b['label'] as String).toLowerCase()));
    return list;
  }

  /// Cores de tema por iconKey (gradiente no card). Inclui keys antigas para compatibilidade.
  static const _themeOptions = <Map<String, dynamic>>[
    {'key': 'auxiliares', 'c1': 0xFF4A148C, 'c2': 0xFF6A1B9A},
    {'key': 'comunicacao', 'c1': 0xFF006064, 'c2': 0xFF0097A7},
    {'key': 'criancas', 'c1': 0xFF00BCD4, 'c2': 0xFF80DEEA},
    {'key': 'kids', 'c1': 0xFF00BCD4, 'c2': 0xFF80DEEA},
    {'key': 'diaconal', 'c1': 0xFF5D4037, 'c2': 0xFF8D6E63},
    {'key': 'evangelismo', 'c1': 0xFF6A1B9A, 'c2': 0xFF7B1FA2},
    {'key': 'escola_biblica', 'c1': 0xFF00695C, 'c2': 0xFF26A69A},
    {'key': 'finance', 'c1': 0xFF546E7A, 'c2': 0xFF90A4AE},
    {'key': 'intercessao', 'c1': 0xFFB71C1C, 'c2': 0xFFD32F2F},
    {'key': 'jovens', 'c1': 0xFF6A1B9A, 'c2': 0xFFAB47BC},
    {'key': 'youth', 'c1': 0xFF6A1B9A, 'c2': 0xFFAB47BC},
    {'key': 'louvor', 'c1': 0xFFF57C00, 'c2': 0xFFFFA726},
    {'key': 'worship', 'c1': 0xFFF57C00, 'c2': 0xFFFFA726},
    {'key': 'media', 'c1': 0xFF1976D2, 'c2': 0xFF64B5F6},
    {'key': 'missionarios', 'c1': 0xFF455A64, 'c2': 0xFF90A4AE},
    {'key': 'mulheres', 'c1': 0xFFC2185B, 'c2': 0xFFF48FB1},
    {'key': 'women', 'c1': 0xFFC2185B, 'c2': 0xFFF48FB1},
    {'key': 'obreiros', 'c1': 0xFF4E342E, 'c2': 0xFF795548},
    {'key': 'oracao', 'c1': 0xFF558B2F, 'c2': 0xFFAED581},
    {'key': 'prayer', 'c1': 0xFF558B2F, 'c2': 0xFFAED581},
    {'key': 'pastoral', 'c1': 0xFF2E7D32, 'c2': 0xFF81C784},
    {'key': 'presbiteros', 'c1': 0xFF0D47A1, 'c2': 0xFF1565C0},
    {'key': 'recepcao', 'c1': 0xFFE64A19, 'c2': 0xFFFF8A65},
    {'key': 'welcome', 'c1': 0xFFE64A19, 'c2': 0xFFFF8A65},
    {'key': 'secretarios', 'c1': 0xFF283593, 'c2': 0xFF3949AB},
    {'key': 'social', 'c1': 0xFF00695C, 'c2': 0xFF00897B},
    {'key': 'tesouraria', 'c1': 0xFF1B5E20, 'c2': 0xFF2E7D32},
    {'key': 'varoes', 'c1': 0xFF0D47A1, 'c2': 0xFF1976D2},
    {'key': 'men', 'c1': 0xFF0D47A1, 'c2': 0xFF1976D2},
  ];

  Map<String, dynamic> _themeByKey(String key) {
    return _themeOptions.firstWhere(
      (e) => e['key'] == key,
      orElse: () => _themeOptions.first,
    );
  }

  /// Firestore às vezes grava só RGB 24 bits (ex. 0xFFFFFF) → em Flutter vira ARGB com **alpha 0**
  /// (gradiente invisível + texto branco no fundo branco). Força opaco e valida contraste.
  static int _opaqueArgb32(int v) {
    if ((v & 0xFF000000) == 0) return 0xFF000000 | (v & 0xFFFFFF);
    return v;
  }

  static bool _luminanceTooHighForWhiteText(int argb) {
    return Color(_opaqueArgb32(argb)).computeLuminance() > 0.74;
  }

  /// Evita cast `as int` quebrar o card (Firestore às vezes devolve String ou double).
  (int, int) _deptCardGradientInts(Map<String, dynamic> m, String themeKey) {
    final th = _themeByKey(themeKey);
    final fallback1 = th['c1'] as int;
    final fallback2 = th['c2'] as int;
    final fromHex = ChurchDepartmentVisualMapper.gradientArgbPairFromDoc(
      m,
      fallback1: fallback1,
      fallback2: fallback2,
    );
    if (fromHex != null) {
      var a = _opaqueArgb32(fromHex.$1);
      var b = _opaqueArgb32(fromHex.$2);
      if (_luminanceTooHighForWhiteText(a) &&
          _luminanceTooHighForWhiteText(b)) {
        a = _opaqueArgb32(fallback1);
        b = _opaqueArgb32(fallback2);
      }
      return (a, b);
    }
    int parse(dynamic v, int fallback) {
      if (v == null) return fallback;
      if (v is int) return v;
      if (v is num) return v.toInt();
      final s = v.toString().trim();
      if (s.isEmpty) return fallback;
      if (s.startsWith('0x') || s.startsWith('0X')) {
        return int.tryParse(s.replaceFirst(RegExp(r'^0x', caseSensitive: false), ''), radix: 16) ??
            fallback;
      }
      return int.tryParse(s) ?? fallback;
    }

    var a = _opaqueArgb32(parse(m['bgColor1'], fallback1));
    var b = _opaqueArgb32(parse(m['bgColor2'], fallback2));
    // Só se **as duas** pontas forem claras (ex. branco no Firestore): usa tema do ícone.
    if (_luminanceTooHighForWhiteText(a) && _luminanceTooHighForWhiteText(b)) {
      a = _opaqueArgb32(fallback1);
      b = _opaqueArgb32(fallback2);
    }
    return (a, b);
  }

  /// Cores/ícones vindos do Firestore ou do mapa podem ter ARGB inválido — nunca deixar transparente.
  int _safeIconChipArgb(Map<String, dynamic> opt) {
    final raw = opt['color'];
    final base = raw is int ? raw : 0xFF0C3B8A;
    return _opaqueArgb32(base);
  }

  IconData _safeMaterialGlyph(Map<String, dynamic> opt) {
    final raw = opt['icon'];
    return raw is IconData ? raw : Icons.groups_rounded;
  }

  Widget _iconChip(String key, {double radius = 20}) {
    final opt = _iconOptions.firstWhere((e) => e['key'] == key,
        orElse: () => _iconOptions.first);
    final bg = Color(_safeIconChipArgb(opt));
    final mat = _safeMaterialGlyph(opt);
    final fa = churchDepartmentFaIcon(key);
    // Web (CanvasKit): FaIcon pode não pintar — usar sempre Material no hub web.
    if (kIsWeb) {
      return CircleAvatar(
        radius: radius,
        backgroundColor: bg,
        child: Icon(mat, color: Colors.white, size: radius * 1.15),
      );
    }
    return CircleAvatar(
      radius: radius,
      backgroundColor: bg,
      child: fa != null
          ? FaIcon(fa, color: Colors.white, size: radius * 1.05)
          : Icon(mat, color: Colors.white, size: radius * 1.15),
    );
  }

  /// Alinha ícone do Firestore ao catálogo e ao nome exibível (aliases temáticos).
  String _resolveVisualIconKey({
    required String iconKeyRaw,
    required String docId,
    String? displayName,
    Map<String, dynamic>? docData,
  }) {
    bool isKnown(String k) =>
        _iconOptions.any((e) => (e['key'] as String) == k);

    var effective = iconKeyRaw.trim().toLowerCase();
    if (docData != null) {
      final raw = ChurchDepartmentVisualMapper.rawIconStringFromDoc(docData);
      if (raw.isNotEmpty) {
        final mapped =
            ChurchDepartmentVisualMapper.mapIconNameToCanonicalKey(raw);
        if (mapped.isNotEmpty) effective = mapped;
      }
    }

    final k = effective;
    if (k.isNotEmpty && isKnown(k)) return k;

    final doc = docId.trim().toLowerCase();
    if (doc.isNotEmpty && isKnown(doc)) return doc;

    final slug = churchDepartmentFoldAsciiForDocId(displayName ?? '')
        .replaceAll(RegExp(r'_+'), '_');
    const aliases = <String, String>{
      'financeiro': 'finance',
      'tesouraria': 'tesouraria',
      'escola_biblica': 'escola_biblica',
      'ebd': 'escola_biblica',
      'diaconos': 'diaconal',
      'diaconal': 'diaconal',
      'filhas_de_siao': 'mulheres',
      'filhas_siao': 'mulheres',
      'evangelismo': 'evangelismo',
      'louvor': 'louvor',
      'jovens': 'jovens',
      'criancas': 'criancas',
      'infantil': 'criancas',
      'mulheres': 'mulheres',
      'varoes': 'varoes',
      'recepcao': 'recepcao',
      'intercessao': 'intercessao',
      'oracao': 'oracao',
      'midia': 'media',
      'media': 'media',
      'pastoral': 'pastoral',
      'missionarios': 'missionarios',
      'obreiros': 'obreiros',
      'comunicacao': 'comunicacao',
      'secretarios': 'secretarios',
      'social': 'social',
      'presbiteros': 'presbiteros',
      'auxiliares': 'auxiliares',
    };
    if (slug.isNotEmpty && aliases.containsKey(slug)) {
      return aliases[slug]!;
    }

    final n = (displayName ?? '').toLowerCase();
    if (n.contains('financeir') || n.contains('tesourar')) return 'finance';
    if (n.contains('infantil') ||
        n.contains('criança') ||
        n.contains('crianca')) return 'criancas';
    if (n.contains('escola') && n.contains('bibl')) return 'escola_biblica';
    if (n.contains('evangel')) return 'evangelismo';
    if (n.contains('intercess') || n.contains('oração') || n.contains('oracao')) {
      return 'intercessao';
    }
    if (n.contains('louvor') || n.contains('música') || n.contains('musica')) {
      return 'louvor';
    }
    if (n.contains('jovens')) return 'jovens';
    if (n.contains('mulher')) return 'mulheres';
    if (n.contains('varão') || n.contains('varao') || n.contains('homens')) {
      return 'varoes';
    }
    if (n.contains('recepç') || n.contains('recepc')) return 'recepcao';
    if (n.contains('mídia') || n.contains('midia') || n.contains('som')) {
      return 'media';
    }
    if (n.contains('diácon') || n.contains('diacon')) return 'diaconal';
    if (n.contains('sião') ||
        n.contains('siao') ||
        (n.contains('filhas') && n.contains('si'))) {
      return 'mulheres';
    }
    if (n.contains('ebd') || n.contains('dominical')) return 'escola_biblica';
    if (n.contains('pastor')) return 'pastoral';
    return 'pastoral';
  }

  Future<void> _openWhatsAppForMemberData(Map<String, dynamic> d) async {
    String digits = '';
    for (final k in [
      'whatsapp',
      'WHATSAPP',
      'whatsappIgreja',
      'celular',
      'CELULAR',
      'telefone',
      'TELEFONE',
    ]) {
      final s = (d[k] ?? '').toString().replaceAll(RegExp(r'[^0-9]'), '');
      if (s.length >= 10) {
        digits = s;
        break;
      }
    }
    if (digits.length < 10) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Telefone/WhatsApp não encontrado na ficha do membro.'),
          ),
        );
      }
      return;
    }
    final uri = Uri.parse('https://wa.me/$digits');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  void _openDepartmentHubSheet({
    required QueryDocumentSnapshot<Map<String, dynamic>> deptDoc,
  }) {
    final m = deptDoc.data();
    final hubName = churchDepartmentNameFromDoc(deptDoc);
    final rawIcon = (m['iconKey'] ?? '').toString();
    final rawTheme = (m['themeKey'] ?? '').toString();
    final resolvedIcon = _resolveVisualIconKey(
      iconKeyRaw: rawIcon.isNotEmpty ? rawIcon : rawTheme,
      docId: deptDoc.id,
      displayName: hubName,
      docData: m,
    );
    final (c1, c2) = _deptCardGradientInts(m, resolvedIcon);
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.42),
      builder: (ctx) => _DepartmentHubSheet(
        tenantId: _tid,
        deptId: deptDoc.id,
        deptName: hubName,
        accent1: c1,
        accent2: c2,
        deptIcon: _iconChip(resolvedIcon, radius: 22),
        membersCol: _membersCol,
        deptRef: _col.doc(deptDoc.id),
        canWrite: _canWrite,
        onWhatsApp: _openWhatsAppForMemberData,
        onEditDepartamento: () {
          Navigator.pop(ctx);
          _edit(doc: deptDoc);
        },
        onAddMember: () {
          Navigator.pop(ctx);
          _vincularMembros(
            context: context,
            deptId: deptDoc.id,
            deptName: churchDepartmentNameFromDoc(deptDoc),
          );
        },
        onAddLeader: () async {
          final cpf = await _pickMemberCpfDigitsForLeader();
          if (cpf == null || cpf.length != 11 || !mounted) return;
          try {
            await FirebaseAuth.instance.currentUser?.getIdToken(true);
            final snap = await _col.doc(deptDoc.id).get();
            final data = snap.data() ?? {};
            final cur = List<String>.from(
                ChurchDepartmentLeaders.cpfsFromDepartmentData(data));
            if (cur.contains(cpf)) return;
            cur.add(cpf);
            await _col.doc(deptDoc.id).update({
              ...ChurchDepartmentLeaders.firestoreFieldsFromCpfs(cur),
              'updatedAt': FieldValue.serverTimestamp(),
            });
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                ThemeCleanPremium.successSnackBar('Líder vinculado.'),
              );
            }
          } catch (e) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Erro ao vincular líder: $e')),
              );
            }
          }
        },
      ),
    );
  }

  /// Barra de ações premium: sempre visível (editar, incluir, membros, excluir).
  Widget _departmentActionRow({
    required BuildContext context,
    required DocumentSnapshot<Map<String, dynamic>> doc,
    required String deptName,
  }) {
    final minH = ThemeCleanPremium.minTouchTarget;
    Widget chip({
      required IconData icon,
      required String label,
      required VoidCallback onTap,
      bool danger = false,
    }) {
      return Material(
        color: danger
            ? const Color(0x4DFF5252)
            : Colors.white.withValues(alpha: 0.22),
        borderRadius: BorderRadius.circular(16),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: minH, minWidth: minH),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: 20, color: Colors.white),
                  const SizedBox(width: 8),
                  Text(
                    label,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                      letterSpacing: -0.1,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    if (!_canWrite) {
      return chip(
        icon: Icons.groups_rounded,
        label: 'Ver membros',
        onTap: () => _verMembrosDoDepartamento(
            context: context, deptId: doc.id, deptName: deptName),
      );
    }

    return Wrap(
      alignment: WrapAlignment.start,
      spacing: 8,
      runSpacing: 8,
      children: [
        chip(
            icon: Icons.edit_rounded,
            label: 'Editar',
            onTap: () => _edit(doc: doc)),
        chip(
          icon: Icons.person_add_rounded,
          label: 'Incluir membros',
          onTap: () => _vincularMembros(
              context: context, deptId: doc.id, deptName: deptName),
        ),
        chip(
          icon: Icons.qr_code_2_rounded,
          label: 'Convidar',
          onTap: () => _openDepartmentInviteSheet(
              deptId: doc.id, deptName: deptName),
        ),
        chip(
          icon: Icons.groups_rounded,
          label: 'Membros',
          onTap: () => _verMembrosDoDepartamento(
              context: context, deptId: doc.id, deptName: deptName),
        ),
        chip(
          icon: Icons.delete_outline_rounded,
          label: 'Excluir',
          danger: true,
          onTap: () => _excluirDepartamento(doc),
        ),
      ],
    );
  }

  static const List<BoxShadow> _deptCardShadow = [
    BoxShadow(
      color: Color(0x1A000000),
      blurRadius: 12,
      offset: Offset(0, 6),
      spreadRadius: -2,
    ),
    BoxShadow(
      color: Color(0x0D2563EB),
      blurRadius: 12,
      offset: Offset(0, 4),
      spreadRadius: -2,
    ),
  ];

  /// Rodapé quando o departamento é só sugestão (ainda não existe doc no Firestore).
  Widget _presetSuggestionActionRow({
    required BuildContext context,
    required String deptKey,
    required String deptName,
  }) {
    final minH = ThemeCleanPremium.minTouchTarget;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Material(
          color: Colors.white.withValues(alpha: 0.22),
          borderRadius: BorderRadius.circular(16),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () => _verMembrosDoDepartamento(
                context: context, deptId: deptKey, deptName: deptName),
            borderRadius: BorderRadius.circular(16),
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: minH),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.groups_rounded,
                        size: 20, color: Colors.white),
                    const SizedBox(width: 8),
                    Text(
                      'Ver membros',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          _canWrite
              ? 'Sugestão: ainda não está gravada nesta igreja. Use “Gravar padrões no sistema” no topo.'
              : 'Sugestão de referência. Um gestor pode gravar no sistema para usar em escalas e cadastros.',
          style: const TextStyle(color: Colors.white70, fontSize: 11, height: 1.35),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  /// Intro + grelha/lista de presets (lista vazia no Firestore ou “só registros sem nome”).
  List<Widget> _suggestedPresetsSlivers({
    required EdgeInsets padding,
    required EdgeInsets listPad,
    required bool wide,
  }) {
    final presets = ChurchDepartmentsBootstrap.presetsSorted;
    if (presets.isEmpty) return const <Widget>[];
    return [
      SliverToBoxAdapter(
        child: Padding(
          padding: EdgeInsets.fromLTRB(padding.left, 0, padding.right, 14),
          child: Container(
            padding: const EdgeInsets.all(ThemeCleanPremium.spaceMd),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusMd),
              boxShadow: ThemeCleanPremium.softUiCardShadow,
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Icon(Icons.layers_rounded,
                        color: ThemeCleanPremium.primary, size: 28),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Departamentos sugeridos (${presets.length})',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                          color: ThemeCleanPremium.onSurface,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  _canWrite
                      ? 'Lista enxuta para igrejas novas: Pastoral, Louvor, Jovens, Crianças, Evangelismo, Intercessão, Mídia, Recepção, Financeiro, Escola Bíblica e Varões. Toque em gravar para criar no Firestore (escalas e membros).'
                      : 'Referência do sistema. Um gestor pode gravar estes departamentos na igreja.',
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.4,
                    color: ThemeCleanPremium.onSurfaceVariant,
                  ),
                ),
                if (_canWrite) ...[
                  const SizedBox(height: ThemeCleanPremium.spaceMd),
                  FilledButton.icon(
                    onPressed: _manualEnsurePresets,
                    icon: const Icon(Icons.cloud_upload_rounded),
                    label: Text(
                        'Gravar ${ChurchDepartmentsBootstrap.uniquePresetCount} departamentos base'),
                    style: FilledButton.styleFrom(
                      backgroundColor: ThemeCleanPremium.primary,
                      padding: const EdgeInsets.symmetric(
                        horizontal: ThemeCleanPremium.spaceLg,
                        vertical: ThemeCleanPremium.spaceSm,
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  OutlinedButton.icon(
                    onPressed: () => _edit(),
                    icon: const Icon(Icons.add_rounded),
                    label: const Text('Novo departamento personalizado'),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
      if (wide)
        SliverPadding(
          padding: listPad.copyWith(top: 0),
          sliver: SliverGrid(
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              crossAxisSpacing: 14,
              mainAxisSpacing: 14,
              childAspectRatio: 1.32,
            ),
            delegate: SliverChildBuilderDelegate(
              (context, i) => _buildPresetSuggestionCard(
                    presets[i],
                  ),
              childCount: presets.length,
            ),
          ),
        )
      else
        SliverPadding(
          padding: listPad.copyWith(top: 0),
          sliver: SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, i) {
                return Padding(
                  padding: EdgeInsets.only(
                    bottom: i < presets.length - 1
                        ? ThemeCleanPremium.spaceSm
                        : 0,
                  ),
                  child: _buildPresetSuggestionCard(
                    presets[i],
                  ),
                );
              },
              childCount: presets.length,
            ),
          ),
        ),
    ];
  }

  /// Mesmo visual do card real, para lista padrão quando `departamentos` está vazio (todas as igrejas).
  Widget _buildPresetSuggestionCard(
    Map<String, dynamic> preset,
  ) {
    final key = (preset['key'] ?? '').toString();
    final name = (preset['label'] ?? '').toString().trim();
    final desc = (preset['description'] ?? '').toString().trim();
    final iconKey = (preset['iconKey'] ?? preset['key'] ?? 'pastoral').toString();
    final themeKey = iconKey;
    final th = _themeByKey(themeKey);
    var c1 = _opaqueArgb32((preset['c1'] ?? th['c1']) as int);
    var c2 = _opaqueArgb32((preset['c2'] ?? th['c2']) as int);
    if (_luminanceTooHighForWhiteText(c1) && _luminanceTooHighForWhiteText(c2)) {
      c1 = _opaqueArgb32(th['c1'] as int);
      c2 = _opaqueArgb32(th['c2'] as int);
    }
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Color(c1).withValues(alpha: 0.5),
          width: 1.1,
        ),
        boxShadow: _deptCardShadow,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 118),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Positioned.fill(
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [Color(c1), Color(c2)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                      ),
                    ),
                  ),
                  Positioned.fill(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            Color(c1).withValues(alpha: 0.78),
                            Color(c2).withValues(alpha: 0.78),
                          ],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    left: 12,
                    top: 12,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.35),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Text(
                        'Sugestão',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 40, 16, 12),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _iconChip(iconKey, radius: 24),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                name,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 18,
                                  color: Colors.white,
                                  letterSpacing: -0.3,
                                ),
                              ),
                              if (desc.isNotEmpty) ...[
                                const SizedBox(height: 6),
                                Text(
                                  desc,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                      color: Colors.white70,
                                      fontSize: 11,
                                      height: 1.25),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.28),
                border: const Border(
                  top: BorderSide(color: Color(0x33FFFFFF)),
                ),
              ),
              child: Row(
                children: [
                  const Icon(Icons.dashboard_customize_rounded,
                      color: Colors.white, size: 20),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'Equipe e escalas no painel após gravar',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 12.5,
                        height: 1.25,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.16),
                border: const Border(
                  top: BorderSide(color: Color(0x33FFFFFF)),
                ),
              ),
              child: _presetSuggestionActionRow(
                context: context,
                deptKey: key,
                deptName: name,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatLinkedMembersCount(Map<String, dynamic> m) {
    final n = ChurchDepartmentVisualMapper.membrosCountFromDoc(m);
    return n == 1 ? '1 membro vinculado' : '$n membros vinculados';
  }

  Future<void> _toggleDepartmentArchived(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
    bool archive,
  ) async {
    if (!_canWrite) return;
    try {
      await FirebaseAuth.instance.currentUser?.getIdToken(true);
      await doc.reference.set(
        {
          'active': !archive,
          'ativo': !archive,
          'updatedAt': FieldValue.serverTimestamp(),
          ChurchDepartmentFirestoreFields.ultimaAtualizacao:
              FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          ThemeCleanPremium.successSnackBar(
            archive ? 'Departamento arquivado.' : 'Departamento reativado.',
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro: $e')),
        );
      }
    }
  }

  Widget _deptSegmentedTabs() {
    const bg = Color(0xFFE4E9EF);
    final sel = _deptListTab;
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Expanded(
            child: _deptTabCell(label: 'Ativos', index: 0, selected: sel == 0),
          ),
          Expanded(
            child:
                _deptTabCell(label: 'Arquivados', index: 1, selected: sel == 1),
          ),
        ],
      ),
    );
  }

  Widget _deptTabCell({
    required String label,
    required int index,
    required bool selected,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          if (_deptListTab == index) return;
          setState(() => _deptListTab = index);
        },
        borderRadius: BorderRadius.circular(10),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: selected ? Colors.white : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            border: selected
                ? const Border(
                    top: BorderSide(color: Color(0xFF1565C0), width: 3),
                  )
                : null,
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.06),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : null,
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: TextStyle(
              fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
              fontSize: 13,
              color: selected
                  ? const Color(0xFF0C2D5C)
                  : const Color(0xFF64748B),
            ),
          ),
        ),
      ),
    );
  }

  /// Card temático premium (gradiente + ícone da categoria; sem foto de fundo).
  Widget _buildDepartmentCard(
    QueryDocumentSnapshot<Map<String, dynamic>> d,
  ) {
    try {
      return _buildDepartmentCardImpl(d);
    } catch (e, st) {
      debugPrint('DepartmentsPage._buildDepartmentCard falhou (${d.id}): $e\n$st');
      return _departmentCardBuildError(d.id, e);
    }
  }

  Widget _departmentCardBuildError(String docId, Object e) {
    return Material(
      color: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.orange.shade300),
          boxShadow: ThemeCleanPremium.softUiCardShadow,
        ),
        child: Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.orange.shade800, size: 28),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Departamento $docId',
                    style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Não foi possível montar o card (dados inválidos). Toque para tentar abrir ou edite no Firebase.',
                    style: TextStyle(fontSize: 12.5, color: Colors.grey.shade700, height: 1.3),
                  ),
                  if (kDebugMode) Text('$e', style: TextStyle(fontSize: 10, color: Colors.grey.shade500)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDepartmentCardImpl(
    QueryDocumentSnapshot<Map<String, dynamic>> d,
  ) {
    final m = d.data();
    final name = churchDepartmentNameFromDoc(d);
    final rawIcon = (m['iconKey'] ?? '').toString();
    final rawTheme = (m['themeKey'] ?? '').toString();
    final resolvedIcon = _resolveVisualIconKey(
      iconKeyRaw: rawIcon.isNotEmpty ? rawIcon : rawTheme,
      docId: d.id,
      displayName: name,
      docData: m,
    );
    final members = _membersByDeptId[d.id] ?? const [];
    final stored = ChurchDepartmentVisualMapper.membrosCountFromDoc(m);
    final total = math.max(stored, members.length);

    void openHub() => _openDepartmentHubSheet(deptDoc: d);

    const navy = Color(0xFF0C2D5C);
    final primaryAvatar = Container(
      width: 56,
      height: 56,
      decoration: BoxDecoration(
        color: const Color(0xFF0C3B8A),
        borderRadius: BorderRadius.circular(12),
      ),
      clipBehavior: Clip.antiAlias,
      alignment: Alignment.center,
      child: _iconChip(resolvedIcon, radius: 24),
    );

    late final Widget memberSection;
    if (total == 0) {
      memberSection = const Text(
        '*Sem participantes',
        style: TextStyle(
          fontStyle: FontStyle.italic,
          color: Color(0xFF94A3B8),
          fontSize: 12,
        ),
      );
    } else if (members.isEmpty) {
      memberSection = Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: const Color(0xFFE8EDF4),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          '+$total',
          style: const TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 12,
            color: Color(0xFF64748B),
          ),
        ),
      );
    } else {
      const maxVisible = 6;
      final shown = members.take(maxVisible).toList();
      final rest = math.max(0, total - shown.length);
      final stackW = 28.0 + (shown.length - 1) * 20.0 + (rest > 0 ? 28.0 : 0.0);

      memberSection = SizedBox(
        height: 32,
        width: stackW,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            for (var i = 0; i < shown.length; i++)
              Positioned(
                left: i * 20.0,
                child: Container(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 2),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.08),
                        blurRadius: 4,
                      ),
                    ],
                  ),
                  child: FotoMembroWidget(
                    size: 28,
                    tenantId: _tid,
                    memberId: shown[i].id,
                    imageUrl: imageUrlFromMap(shown[i].data()),
                    cpfDigits:
                        (shown[i].data()['CPF'] ?? shown[i].data()['cpf'] ?? '')
                            .toString(),
                    memberData: shown[i].data(),
                  ),
                ),
              ),
            if (rest > 0)
              Positioned(
                left: shown.length * 20.0,
                child: Container(
                  width: 28,
                  height: 28,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: const Color(0xFFE2E8F0),
                    border: Border.all(color: Colors.white, width: 2),
                  ),
                  child: Text(
                    '+$rest',
                    style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF475569),
                    ),
                  ),
                ),
              ),
          ],
        ),
      );
    }

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: openHub,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              primaryAvatar,
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      name,
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                        color: navy,
                        letterSpacing: -0.2,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (m['isWelcomeKit'] == true) ...[
                      const SizedBox(height: 4),
                      Text(
                        'Kit inicial',
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.grey.shade600,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Flexible(
                fit: FlexFit.loose,
                child: Align(
                  alignment: Alignment.centerRight,
                  child: memberSection,
                ),
              ),
              if (_canWrite) ...[
                const SizedBox(width: 2),
                PopupMenuButton<String>(
                  tooltip: 'Opções',
                  onSelected: (v) async {
                    if (v == 'edit') _edit(doc: d);
                    if (v == 'members') {
                      await _verMembrosDoDepartamento(
                        context: context,
                        deptId: d.id,
                        deptName: name,
                      );
                    }
                    if (v == 'link') {
                      await _vincularMembros(
                        context: context,
                        deptId: d.id,
                        deptName: name,
                      );
                    }
                    if (v == 'invite') {
                      await _openDepartmentInviteSheet(
                        deptId: d.id,
                        deptName: name,
                      );
                    }
                    if (v == 'archive') {
                      await _toggleDepartmentArchived(d, true);
                    }
                    if (v == 'restore') {
                      await _toggleDepartmentArchived(d, false);
                    }
                    if (v == 'delete') {
                      await _excluirDepartamento(d);
                    }
                  },
                  itemBuilder: (ctx) {
                    final active = churchDepartmentDocIsActive(m);
                    return [
                      const PopupMenuItem(value: 'edit', child: Text('Editar')),
                      const PopupMenuItem(
                        value: 'members',
                        child: Text('Ver membros'),
                      ),
                      const PopupMenuItem(
                        value: 'link',
                        child: Text('Incluir membros'),
                      ),
                      const PopupMenuItem(
                        value: 'invite',
                        child: Text('Convidar (QR)'),
                      ),
                      if (active)
                        const PopupMenuItem(
                          value: 'archive',
                          child: Text('Arquivar'),
                        )
                      else
                        const PopupMenuItem(
                          value: 'restore',
                          child: Text('Reativar'),
                        ),
                      const PopupMenuDivider(),
                      const PopupMenuItem(
                        value: 'delete',
                        child: Text(
                          'Excluir',
                          style: TextStyle(color: Color(0xFFDC2626)),
                        ),
                      ),
                    ];
                  },
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Future<String?> _pickMemberCpfDigitsForLeader() async {
    final tid = _tid.trim();
    if (tid.isEmpty || !mounted) return null;
    QuerySnapshot<Map<String, dynamic>> snap;
    try {
      snap = await FirebaseFirestore.instance
          .collection('igrejas')
          .doc(tid)
          .collection('membros')
          .limit(450)
          .get();
    } catch (_) {
      return null;
    }
    final docs = snap.docs.toList();
    final qCtrl = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) {
          final q = qCtrl.text.trim().toLowerCase();
          final qDigits = q.replaceAll(RegExp(r'\D'), '');
          final filtered = docs.where((d) {
            if (q.isEmpty) return true;
            final nome = (d.data()['NOME_COMPLETO'] ?? d.data()['nome'] ?? '')
                .toString()
                .toLowerCase();
            final cpf =
                (d.data()['CPF'] ?? d.data()['cpf'] ?? '').toString().replaceAll(RegExp(r'\D'), '');
            return nome.contains(q) ||
                (qDigits.length >= 3 && cpf.contains(qDigits));
          }).take(120).toList();
          return AlertDialog(
            title: const Text('Vincular líder ao departamento'),
            content: SizedBox(
              width: 340,
              height: 420,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(
                    controller: qCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Buscar nome ou CPF',
                      prefixIcon: Icon(Icons.search_rounded),
                    ),
                    onChanged: (_) => setS(() {}),
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: ListView.builder(
                      itemCount: filtered.length,
                      itemBuilder: (_, i) {
                        final d = filtered[i];
                        final nom = (d.data()['NOME_COMPLETO'] ??
                                d.data()['nome'] ??
                                'Membro')
                            .toString();
                        final cpf = (d.data()['CPF'] ?? d.data()['cpf'] ?? '')
                            .toString()
                            .replaceAll(RegExp(r'\D'), '');
                        return ListTile(
                          dense: true,
                          leading: const Icon(Icons.person_rounded),
                          title: Text(nom,
                              maxLines: 2, overflow: TextOverflow.ellipsis),
                          subtitle: Text(
                              cpf.length == 11 ? 'CPF $cpf' : 'Sem CPF válido'),
                          onTap: () =>
                              Navigator.pop(ctx, cpf.length == 11 ? cpf : null),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Cancelar')),
            ],
          );
        },
      ),
    );
  }

  Future<void> _edit({DocumentSnapshot<Map<String, dynamic>>? doc}) async {
    if (!_canWrite) return;
    final data = doc?.data() ?? {};
    final nameCtrl = TextEditingController(
        text: churchDepartmentNameFromData(data, docId: doc?.id));
    String iconKey = (data['iconKey'] ?? 'recepcao').toString();
    final leaderCpfs = List<String>.from(
        ChurchDepartmentLeaders.cpfsFromDepartmentData(data));

    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) {
          final grad = _themeByKey(iconKey);
          final c1Sheet = Color((data['bgColor1'] ?? grad['c1']) as int);
          final c2Sheet = Color((data['bgColor2'] ?? grad['c2']) as int);
          final seedColor = Color.lerp(c1Sheet, c2Sheet, 0.5)!;

          return Theme(
            data: Theme.of(ctx).copyWith(
              colorScheme: ColorScheme.fromSeed(
                seedColor: seedColor,
                brightness: Brightness.light,
              ),
            ),
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                  24, 20, 24, MediaQuery.of(ctx).viewInsets.bottom + 24),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Center(
                        child: Container(
                            width: 40,
                            height: 4,
                            decoration: BoxDecoration(
                                color: Colors.grey.shade300,
                                borderRadius: BorderRadius.circular(2)))),
                    const SizedBox(height: 16),
                    Text(
                        doc == null
                            ? 'Novo Departamento'
                            : 'Editar Departamento',
                        style: const TextStyle(
                            fontSize: 18, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 16),
                    TextField(
                        controller: nameCtrl,
                        decoration: const InputDecoration(
                            labelText: 'Nome',
                            prefixIcon: Icon(Icons.group_rounded))),
                    const SizedBox(height: 16),
                    Text('Escolher ícone',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: Colors.grey.shade700,
                        )),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: _iconOptionsSorted.map((e) {
                      final key = e['key'] as String;
                      final selected = iconKey == key;
                      return Material(
                        color: selected
                            ? ThemeCleanPremium.primary.withOpacity(0.12)
                            : Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(12),
                        child: InkWell(
                          onTap: () => setD(() => iconKey = key),
                          borderRadius: BorderRadius.circular(12),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 10),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                CircleAvatar(
                                  radius: 14,
                                  backgroundColor: Color(e['color'] as int),
                                  child: Icon(e['icon'] as IconData,
                                      size: 18, color: Colors.white),
                                ),
                                const SizedBox(width: 8),
                                Text(e['label'] as String,
                                    style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: selected
                                            ? FontWeight.w700
                                            : FontWeight.w500)),
                              ],
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 16),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Líderes do departamento',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: Colors.grey.shade700,
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Podem ser vários. Usados no painel, escalas e permissões de gestão do grupo.',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: leaderCpfs
                        .map(
                          (cpf) => InputChip(
                            label: Text(
                              cpf.length == 11
                                  ? '${cpf.substring(0, 3)}.${cpf.substring(3, 6)}.${cpf.substring(6, 9)}-${cpf.substring(9)}'
                                  : cpf,
                              style: const TextStyle(fontSize: 13),
                            ),
                            onDeleted: () =>
                                setD(() => leaderCpfs.remove(cpf)),
                          ),
                        )
                        .toList(),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: () async {
                      final c = await _pickMemberCpfDigitsForLeader();
                      if (c == null || c.length != 11) return;
                      setD(() {
                        if (!leaderCpfs.contains(c)) leaderCpfs.add(c);
                      });
                    },
                    icon: const Icon(Icons.person_add_rounded, size: 20),
                    label: const Text('Adicionar líder (membro com CPF)'),
                  ),
                  const SizedBox(height: 20),
                  Row(children: [
                    Expanded(
                        child: OutlinedButton(
                            onPressed: () => Navigator.pop(ctx, false),
                            child: const Text('Cancelar'))),
                    const SizedBox(width: 12),
                    Expanded(
                        child: FilledButton(
                      onPressed: () async {
                        Navigator.pop(ctx, true);
                      },
                      child: const Text('Salvar'),
                    )),
                  ]),
                ],
              ),
            ),
          ),
        );
        },
      ),
    );
    if (ok != true) return;

    final nome = nameCtrl.text.trim();
    if (nome.isEmpty) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Informe o nome do departamento.')));
      return;
    }

    final theme = _themeByKey(iconKey);
    final c1Argb = theme['c1'] as int;
    final c2Argb = theme['c2'] as int;
    final payload = <String, dynamic>{
      'name': nome,
      'iconKey': iconKey,
      'themeKey': iconKey,
      ChurchDepartmentFirestoreFields.iconName: iconKey,
      ChurchDepartmentFirestoreFields.colorHex:
          ChurchDepartmentVisualMapper.hexStringFromArgb(c1Argb),
      ChurchDepartmentFirestoreFields.colorHexSecondary:
          ChurchDepartmentVisualMapper.hexStringFromArgb(c2Argb),
      'bgColor1': c1Argb,
      'bgColor2': c2Argb,
      'bgImageUrl': '',
      ...ChurchDepartmentLeaders.firestoreFieldsFromCpfs(leaderCpfs),
      'updatedAt': Timestamp.now(),
      ChurchDepartmentFirestoreFields.ultimaAtualizacao:
          FieldValue.serverTimestamp(),
      'active': true,
    };
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Faça login para salvar.')));
      return;
    }

    Future<bool?> doWrite() async {
      await user.getIdToken(true);
      await Future.delayed(const Duration(milliseconds: 400));
      if (doc == null) {
        return _persistNewDepartment(payload: payload, iconKey: iconKey);
      }
      await doc.reference.update(payload);
      return null;
    }

    try {
      final mergedNew = await doWrite();
      if (mounted) {
        if (doc == null) {
          ScaffoldMessenger.of(context).showSnackBar(
            ThemeCleanPremium.successSnackBar(
              mergedNew == true
                  ? 'Departamento salvo (unificado com registro existente do mesmo nome).'
                  : 'Departamento cadastrado!',
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            ThemeCleanPremium.successSnackBar('Departamento atualizado!'),
          );
        }
        _refreshDepartments(forceServer: true);
      }
    } catch (e) {
      final isPermissionDenied = e.toString().contains('permission-denied') ||
          e.toString().contains('PERMISSION_DENIED');
      if (isPermissionDenied) {
        try {
          await Future.delayed(const Duration(milliseconds: 600));
          await user.getIdToken(true);
          await Future.delayed(const Duration(milliseconds: 400));
          if (doc == null) {
            final m = await _persistNewDepartment(
                payload: payload, iconKey: iconKey);
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                ThemeCleanPremium.successSnackBar(
                  m
                      ? 'Departamento salvo (unificado com registro existente do mesmo nome).'
                      : 'Departamento cadastrado!',
                ),
              );
            }
          } else {
            await doc.reference.update(payload);
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                  ThemeCleanPremium.successSnackBar('Departamento atualizado!'));
            }
          }
          if (mounted) {
            _refreshDepartments(forceServer: true);
          }
        } catch (e2) {
          if (mounted)
            ScaffoldMessenger.of(context)
                .showSnackBar(SnackBar(content: Text('Erro ao salvar: $e2')));
        }
      } else {
        if (mounted)
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text('Erro ao salvar: $e')));
      }
    }
  }

  Widget _buildDepartmentsListBody({
    required List<QueryDocumentSnapshot<Map<String, dynamic>>> docsForTab,
  }) {
    final listView = ListView.separated(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: EdgeInsets.zero,
      itemCount: docsForTab.length,
      separatorBuilder: (_, __) => const Divider(
        height: 1,
        thickness: 1,
        indent: 84,
        endIndent: 16,
        color: Color(0xFFE8EEF5),
      ),
      itemBuilder: (context, i) {
        final card = _buildDepartmentCard(docsForTab[i]);
        if (kIsWeb) return card;
        return AnimationConfiguration.staggeredList(
          position: i,
          duration: const Duration(milliseconds: 300),
          delay: Duration(milliseconds: (i % 14) * 30),
          child: SlideAnimation(
            verticalOffset: 16,
            child: FadeInAnimation(child: card),
          ),
        );
      },
    );

    final core =
        kIsWeb ? listView : AnimationLimiter(child: listView);

    if (kIsWeb) return core;
    return RefreshIndicator(
      onRefresh: () => _startDeptLoad(forceServer: true),
      child: core,
    );
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = ThemeCleanPremium.isMobile(context);
    final padding = ThemeCleanPremium.pagePadding(context);
    // Shell já exibe [ModuleHeaderPremium] com título — sem AppBar/barra duplicada.
    return Scaffold(
      backgroundColor: const Color(0xFFF1F4F8),
      appBar: null,
      body: SafeArea(
        top: !widget.embeddedInShell,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (!widget.embeddedInShell)
              Padding(
                padding: EdgeInsets.fromLTRB(padding.left, 12, padding.right, 4),
                child: const Text(
                  'Departamentos',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF0C2D5C),
                    letterSpacing: -0.4,
                  ),
                ),
              ),
            Expanded(
              child: Builder(
                builder: (context) {
                  if (_deptLoading) {
                    return const ChurchPanelLoadingBody();
                  }
                  if (_deptError != null) {
                    return Padding(
                      padding: EdgeInsets.symmetric(
                          horizontal: padding.horizontal,
                          vertical: ThemeCleanPremium.spaceLg),
                      child: ChurchPanelErrorBody(
                        title: 'Não foi possível carregar os departamentos',
                        error: _deptError,
                        onRetry: _canWrite
                            ? () =>
                                _refreshDepartments(forceServer: true)
                            : null,
                      ),
                    );
                  }
                  if (_tid.trim().isEmpty) {
                    return Center(
                      child: Padding(
                        padding: EdgeInsets.symmetric(
                            horizontal: padding.horizontal,
                            vertical: ThemeCleanPremium.spaceLg),
                        child: Text(
                          'Igreja não identificada. Entre novamente no painel ou selecione a igreja correta.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              color: ThemeCleanPremium.onSurfaceVariant,
                              height: 1.35),
                        ),
                      ),
                    );
                  }
                  // Só stream de departamentos — hub mais leve (sem escutar `membros`).
                  return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                    key: ValueKey<String>('dept_stream_$_tid'),
                    stream: _col.snapshots(),
                    builder: (context, deptSnap) {
                      final streamFailed = deptSnap.hasError;
                      final hasHydratedNonEmpty = _hydratedDeptDocs != null &&
                          _hydratedDeptDocs!.isNotEmpty;

                      if (streamFailed && _hydratedDeptDocs == null) {
                        if (_streamRecoveryFailed) {
                          return Padding(
                            padding: EdgeInsets.symmetric(
                                horizontal: padding.horizontal,
                                vertical: ThemeCleanPremium.spaceLg),
                            child: ChurchPanelErrorBody(
                              title:
                                  'Não foi possível carregar os departamentos',
                              error: deptSnap.error,
                              onRetry: () {
                                setState(() => _streamRecoveryFailed = false);
                                _refreshDepartments(forceServer: true);
                              },
                            ),
                          );
                        }
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          if (mounted) {
                            unawaited(_recoverDeptStreamFailure());
                          }
                        });
                        return const ChurchPanelLoadingBody();
                      }

                      if (deptSnap.connectionState ==
                              ConnectionState.waiting &&
                          !deptSnap.hasData &&
                          !hasHydratedNonEmpty) {
                        return const ChurchPanelLoadingBody();
                      }
                      int welcomeOrder(
                              QueryDocumentSnapshot<Map<String, dynamic>> d) {
                            final m = d.data();
                            if (m['isWelcomeKit'] == true) {
                              final w = m['welcomeKitOrder'];
                              // Firestore pode gravar número como double — evita falha no sort/compare.
                              if (w is int) return w;
                              if (w is num) return w.toInt();
                            }
                            return 1000;
                          }

                          // NUNCA descartar docs só porque hasError: o último snapshot válido pode
                          // ainda estar em deptSnap.data (e senão _hydratedDeptDocs cobre no merge).
                          final streamDocs = deptSnap.hasData
                              ? (deptSnap.data?.docs ??
                                  <QueryDocumentSnapshot<
                                      Map<String, dynamic>>>[])
                              : <QueryDocumentSnapshot<
                                  Map<String, dynamic>>>[];
                          final h = _hydratedDeptDocs;
                          // União stream + hidratação: o stream pode vir vazio/parcial no cache (web).
                          var docs = _mergeDeptStreamAndHydrated(
                            streamDocs,
                            h,
                          );
                          docs = List.from(docs)
                            ..sort((a, b) {
                              final oa = welcomeOrder(a);
                              final ob = welcomeOrder(b);
                              if (oa != ob) return oa.compareTo(ob);
                              return churchDepartmentNameFromDoc(a)
                                  .toLowerCase()
                                  .compareTo(churchDepartmentNameFromDoc(b)
                                      .toLowerCase());
                            });
                          final docsRawForDupCheck =
                              List<QueryDocumentSnapshot<Map<String, dynamic>>>.from(docs);
                          if (docs.isEmpty &&
                              _tid.isNotEmpty &&
                              !_emptyServerDeptFetchTried) {
                            _emptyServerDeptFetchTried = true;
                            WidgetsBinding.instance.addPostFrameCallback((_) {
                              if (mounted) _fetchDepartmentsFromServerOnce();
                            });
                          }
                          docs = dedupeChurchDepartmentDocumentsForHub(docs);
                          final docsVisible = docs;
                          final orphanNamelessCount = docs
                              .where((d) =>
                                  !churchDepartmentDocHasExplicitNameField(
                                      d.data()))
                              .length;

                          final listPadOrEmpty = EdgeInsets.fromLTRB(
                              padding.left,
                              padding.top,
                              padding.right,
                              isMobile ? 88 : padding.bottom);
                          final wideOrEmpty =
                              MediaQuery.sizeOf(context).width >= 720;

                          if (docs.isEmpty) {
                            final presets =
                                ChurchDepartmentsBootstrap.presetsSorted;
                            if (presets.isEmpty) {
                              return Center(
                                child: Padding(
                                  padding: const EdgeInsets.all(24),
                                  child: _emptyDepartmentsMessage(),
                                ),
                              );
                            }
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                if (_deptLoading)
                                  const LinearProgressIndicator(minHeight: 2),
                                Expanded(
                                  child: _webSafeDeptScroller(
                                    onRefresh: () =>
                                        _startDeptLoad(forceServer: true),
                                    slivers: _suggestedPresetsSlivers(
                                      padding: padding,
                                      listPad: listPadOrEmpty,
                                      wide: wideOrEmpty,
                                    ),
                                  ),
                                ),
                              ],
                            );
                          }

                          final listPad = EdgeInsets.fromLTRB(
                              padding.left,
                              padding.top,
                              padding.right,
                              isMobile ? 88 : padding.bottom);
                          final showDupBanner =
                              _hasDuplicateDepartmentNames(docsRawForDupCheck);
                          final docsForTab = docsVisible.where((d) {
                            final active = churchDepartmentDocIsActive(d.data());
                            return _deptListTab == 0 ? active : !active;
                          }).toList();

                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              if (_deptLoading)
                                const LinearProgressIndicator(minHeight: 2),
                              Padding(
                                padding: EdgeInsets.fromLTRB(
                                    padding.left, 8, padding.right, 8),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Expanded(child: _deptSegmentedTabs()),
                                    IconButton(
                                      tooltip: 'Atualizar lista',
                                      onPressed: () =>
                                          _refreshDepartments(forceServer: true),
                                      icon: Icon(Icons.refresh_rounded,
                                          color: ThemeCleanPremium.primary),
                                      style: IconButton.styleFrom(
                                        minimumSize: const Size(
                                          ThemeCleanPremium.minTouchTarget,
                                          ThemeCleanPremium.minTouchTarget,
                                        ),
                                      ),
                                    ),
                                    if (_canWrite) ...[
                                      const SizedBox(width: 4),
                                      FilledButton.icon(
                                        onPressed: () => _edit(),
                                        icon: const Icon(Icons.add_rounded,
                                            size: 20),
                                        label: const Text('+ Adicionar'),
                                        style: FilledButton.styleFrom(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 16,
                                            vertical: 12,
                                          ),
                                          backgroundColor:
                                              const Color(0xFF0C3B8A),
                                          foregroundColor: Colors.white,
                                          shape: RoundedRectangleBorder(
                                            borderRadius:
                                                BorderRadius.circular(12),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                              if (showDupBanner)
                                Padding(
                                  padding: EdgeInsets.fromLTRB(
                                      padding.left, 0, padding.right, 8),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 14, vertical: 12),
                                    decoration: BoxDecoration(
                                      color: Colors.amber.shade50,
                                      borderRadius: BorderRadius.circular(
                                        ThemeCleanPremium.radiusMd,
                                      ),
                                      border: Border.all(
                                        color: Colors.amber.shade200,
                                      ),
                                      boxShadow:
                                          ThemeCleanPremium.softUiCardShadow,
                                    ),
                                    child: Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Icon(Icons.copy_all_rounded,
                                            color: Colors.amber.shade900,
                                            size: 22),
                                        const SizedBox(width: 10),
                                        Expanded(
                                          child: Text(
                                            'Há departamentos com o mesmo nome. Exclua ou renomeie os duplicados — assim a Escala deixa de listar a mesma opção várias vezes.',
                                            style: TextStyle(
                                              fontSize: 13,
                                              height: 1.35,
                                              color: Colors.amber.shade900,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              if (orphanNamelessCount > 0)
                                Padding(
                                  padding: EdgeInsets.fromLTRB(
                                      padding.left, 0, padding.right, 8),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 14, vertical: 12),
                                    decoration: BoxDecoration(
                                      color: Colors.orange.shade50,
                                      borderRadius: BorderRadius.circular(
                                        ThemeCleanPremium.radiusMd,
                                      ),
                                      border: Border.all(
                                        color: Colors.orange.shade200,
                                      ),
                                    ),
                                    child: Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Icon(Icons.label_off_rounded,
                                            color: Colors.orange.shade900,
                                            size: 22),
                                        const SizedBox(width: 10),
                                        Expanded(
                                          child: Text(
                                            '$orphanNamelessCount departamento(s) sem campo de nome reconhecido — edite e preencha o nome.',
                                            style: TextStyle(
                                              fontSize: 13,
                                              height: 1.35,
                                              color: Colors.orange.shade900,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              Expanded(
                                child: Padding(
                                  padding: EdgeInsets.fromLTRB(
                                    listPad.left,
                                    0,
                                    listPad.right,
                                    listPad.bottom,
                                  ),
                                  child: DecoratedBox(
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      borderRadius: BorderRadius.circular(16),
                                      border: Border.all(
                                        color: const Color(0xFFE8EEF5),
                                      ),
                                      boxShadow:
                                          ThemeCleanPremium.softUiCardShadow,
                                    ),
                                    child: ClipRRect(
                                      borderRadius: BorderRadius.circular(16),
                                      child: docsForTab.isEmpty
                                          ? Center(
                                              child: Padding(
                                                padding:
                                                    const EdgeInsets.all(24),
                                                child: Text(
                                                  _deptListTab == 0
                                                      ? 'Nenhum departamento ativo nesta aba.'
                                                      : 'Nenhum departamento arquivado.',
                                                  textAlign: TextAlign.center,
                                                  style: TextStyle(
                                                    fontSize: 15,
                                                    fontWeight: FontWeight.w600,
                                                    color: ThemeCleanPremium
                                                        .onSurfaceVariant,
                                                    height: 1.35,
                                                  ),
                                                ),
                                              ),
                                            )
                                          : _buildDepartmentsListBody(
                                              docsForTab: docsForTab,
                                            ),
                                    ),
                                  ),
                                ),
                              ),
                              if (_canWrite && _deptListTab == 0)
                                Padding(
                                  padding: EdgeInsets.fromLTRB(
                                      padding.left, 6, padding.right, 10),
                                  child: Align(
                                    alignment: Alignment.centerRight,
                                    child: TextButton.icon(
                                      onPressed: _manualEnsurePresets,
                                      icon: const Icon(Icons.cloud_upload_rounded,
                                          size: 18),
                                      label: const Text('Instalar base'),
                                      style: TextButton.styleFrom(
                                        visualDensity: VisualDensity.compact,
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 10, vertical: 6),
                                        foregroundColor:
                                            ThemeCleanPremium.primary,
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Hub do departamento: liderança em destaque, membros em tempo real, WhatsApp.
class _DepartmentHubSheet extends StatelessWidget {
  final String tenantId;
  final String deptId;
  final String deptName;
  /// Mesmos tons do card na grelha (`_deptCardGradientInts`).
  final int accent1;
  final int accent2;
  final Widget deptIcon;
  final CollectionReference<Map<String, dynamic>> membersCol;
  final DocumentReference<Map<String, dynamic>> deptRef;
  final bool canWrite;
  final Future<void> Function(Map<String, dynamic>) onWhatsApp;
  final VoidCallback onEditDepartamento;
  final VoidCallback onAddMember;
  final Future<void> Function() onAddLeader;

  const _DepartmentHubSheet({
    required this.tenantId,
    required this.deptId,
    required this.deptName,
    required this.accent1,
    required this.accent2,
    required this.deptIcon,
    required this.membersCol,
    required this.deptRef,
    required this.canWrite,
    required this.onWhatsApp,
    required this.onEditDepartamento,
    required this.onAddMember,
    required this.onAddLeader,
  });

  Color get _cA => Color(accent1);
  Color get _cB => Color(accent2);

  static Color _onAccentFg(Color accent) =>
      accent.computeLuminance() > 0.55 ? const Color(0xFF0F172A) : Colors.white;

  Widget _sectionTitle(String label) {
    return Row(
      children: [
        Container(
          width: 4,
          height: 20,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(3),
            gradient: LinearGradient(
              colors: [_cA, _cB],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Text(
          label,
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w800,
            color: Colors.grey.shade900,
            letterSpacing: -0.2,
          ),
        ),
      ],
    );
  }

  static String _nomeMembro(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data();
    return (d['NOME_COMPLETO'] ?? d['nome'] ?? d['name'] ?? doc.id)
        .toString()
        .trim();
  }

  static String _cpfDigits(Map<String, dynamic> d) =>
      (d['CPF'] ?? d['cpf'] ?? '').toString().replaceAll(RegExp(r'\D'), '');

  static String _cpfMask(String cpf) {
    if (cpf.length != 11) return cpf;
    return '${cpf.substring(0, 3)}.${cpf.substring(3, 6)}.${cpf.substring(6, 9)}-${cpf.substring(9)}';
  }

  Future<void> _confirmRemoveLeader(BuildContext context, String cpfToRemove) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusLg)),
        title: const Text('Remover líder'),
        content: const Text(
            'Este CPF deixa de constar como líder do departamento. O vínculo como membro permanece, salvo se você removê-lo da lista abaixo.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Remover'),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    try {
      final dSnap = await deptRef.get();
      final leaders =
          ChurchDepartmentLeaders.cpfsFromDepartmentData(dSnap.data());
      final next = List<String>.from(leaders)..remove(cpfToRemove);
      await deptRef.update({
        ...ChurchDepartmentLeaders.firestoreFieldsFromCpfs(next),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          ThemeCleanPremium.successSnackBar('Líder removido.'),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Erro: $e')));
      }
    }
  }

  Future<void> _removerMembroHub(
    BuildContext context,
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) async {
    final nome = _nomeMembro(doc);
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusLg)),
        title: const Text('Remover do departamento'),
        content: Text('Remover "$nome" de $deptName?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFDC2626)),
            child: const Text('Remover'),
          ),
        ],
      ),
    );
    if (confirm != true || !context.mounted) return;
    try {
      await DepartmentMemberIntegrationService.unlinkMember(
        tenantId: tenantId,
        departmentId: deptId,
        memberDocId: doc.id,
        memberData: doc.data(),
      );
      final cpf = _cpfDigits(doc.data());
      if (cpf.length == 11) {
        final dSnap = await deptRef.get();
        final leaders =
            ChurchDepartmentLeaders.cpfsFromDepartmentData(dSnap.data());
        if (leaders.contains(cpf)) {
          final next = List<String>.from(leaders)..remove(cpf);
          await deptRef.update({
            ...ChurchDepartmentLeaders.firestoreFieldsFromCpfs(next),
            'updatedAt': FieldValue.serverTimestamp(),
          });
        }
      }
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('"$nome" removido.',
              style: const TextStyle(color: Colors.white)),
          backgroundColor: Colors.green,
        ));
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Erro ao remover: $e')));
      }
    }
  }

  Widget _leaderCard({
    required BuildContext context,
    required QueryDocumentSnapshot<Map<String, dynamic>> doc,
  }) {
    final data = doc.data();
    final nome = _nomeMembro(doc);
    final cpf = _cpfDigits(data);
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            _cA.withValues(alpha: 0.22),
            const Color(0xFFF59E0B).withValues(alpha: 0.15),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _cA.withValues(alpha: 0.42)),
        boxShadow: [
          BoxShadow(
            color: _cA.withValues(alpha: 0.12),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ListTile(
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        leading: FotoMembroWidget(
          size: 48,
          tenantId: tenantId,
          memberId: doc.id,
          imageUrl: imageUrlFromMap(data),
          cpfDigits: cpf,
          memberData: data,
        ),
        title: Row(
          children: [
            const FaIcon(FontAwesomeIcons.star,
                size: 14, color: Color(0xFFD97706)),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                nome,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
          ],
        ),
        subtitle: Text(
          'Líder',
          style: TextStyle(
            fontSize: 12,
            color: Colors.grey.shade800,
            fontWeight: FontWeight.w600,
          ),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              tooltip: 'WhatsApp',
              onPressed: () => onWhatsApp(data),
              icon: const FaIcon(FontAwesomeIcons.whatsapp,
                  color: Color(0xFF25D366), size: 22),
            ),
            if (canWrite && cpf.length == 11)
              IconButton(
                tooltip: 'Remover da liderança',
                onPressed: () => _confirmRemoveLeader(context, cpf),
                icon: const Icon(Icons.star_outline_rounded,
                    color: Color(0xFF92400E)),
              ),
          ],
        ),
      ),
    );
  }

  Widget _orphanLeaderTile(BuildContext context, String cpf) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.orange.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.orange.shade200),
      ),
      child: ListTile(
        leading:
            Icon(Icons.warning_amber_rounded, color: Colors.orange.shade800),
        title: Text(
          _cpfMask(cpf),
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        subtitle: const Text(
          'Líder gravado, mas sem membro vinculado a este departamento.',
        ),
        trailing: canWrite
            ? IconButton(
                tooltip: 'Remover da liderança',
                onPressed: () => _confirmRemoveLeader(context, cpf),
                icon: const Icon(Icons.close_rounded),
              )
            : null,
      ),
    );
  }

  Widget _memberRow(
      BuildContext context, QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data();
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: Color.lerp(Colors.white, _cA, 0.06) ?? Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _cA.withValues(alpha: 0.16)),
        boxShadow: [
          BoxShadow(
            color: _cA.withValues(alpha: 0.08),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ListTile(
        leading: FotoMembroWidget(
          size: 40,
          tenantId: tenantId,
          memberId: doc.id,
          imageUrl: imageUrlFromMap(data),
          cpfDigits: _cpfDigits(data),
          memberData: data,
        ),
        title: Text(_nomeMembro(doc)),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              tooltip: 'WhatsApp',
              onPressed: () => onWhatsApp(data),
              icon: const FaIcon(FontAwesomeIcons.whatsapp,
                  color: Color(0xFF25D366), size: 20),
            ),
            if (canWrite)
              IconButton(
                tooltip: 'Remover do departamento',
                onPressed: () => _removerMembroHub(context, doc),
                icon: const Icon(Icons.person_remove_rounded,
                    color: Color(0xFFDC2626), size: 22),
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.68,
      maxChildSize: 0.94,
      minChildSize: 0.38,
      expand: false,
      builder: (context, scrollController) {
        final surface = Theme.of(context).colorScheme.surface;
        final sheetBg =
            Color.lerp(surface, _cA, 0.035) ?? surface;
        return Material(
          color: sheetBg,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [_cA, _cB],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: _cA.withValues(alpha: 0.35),
                      blurRadius: 20,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: SafeArea(
                  bottom: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 10, 16, 18),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Center(
                          child: Container(
                            width: 40,
                            height: 4,
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.45),
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                        ),
                        const SizedBox(height: 14),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            deptIcon,
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    deptName,
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleLarge
                                        ?.copyWith(
                                          fontWeight: FontWeight.w800,
                                          color: Colors.white,
                                          letterSpacing: -0.35,
                                        ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'Hub do departamento',
                                    style: TextStyle(
                                      fontSize: 13,
                                      color: Colors.white.withValues(alpha: 0.88),
                                      fontWeight: FontWeight.w500,
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
                ),
              ),
              if (canWrite)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      OutlinedButton.icon(
                        onPressed: onEditDepartamento,
                        icon: Icon(Icons.edit_rounded,
                            size: 18, color: _cA),
                        label: Text('Editar', style: TextStyle(color: _cA)),
                        style: OutlinedButton.styleFrom(
                          side: BorderSide(color: _cA.withValues(alpha: 0.55)),
                          backgroundColor: Colors.white.withValues(alpha: 0.9),
                        ),
                      ),
                      FilledButton.tonalIcon(
                        onPressed: onAddMember,
                        icon: Icon(Icons.person_add_rounded,
                            size: 18, color: _cA),
                        label: const Text('Membro'),
                        style: FilledButton.styleFrom(
                          backgroundColor: _cB.withValues(alpha: 0.14),
                          foregroundColor: Colors.grey.shade900,
                        ),
                      ),
                      FilledButton.icon(
                        onPressed: () => onAddLeader(),
                        icon: Icon(Icons.star_rounded,
                            size: 18, color: _onAccentFg(_cA)),
                        label: Text('Líder',
                            style: TextStyle(color: _onAccentFg(_cA))),
                        style: FilledButton.styleFrom(
                          backgroundColor: _cA,
                          foregroundColor: _onAccentFg(_cA),
                        ),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 4),
              Expanded(
                child: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                  stream: deptRef.snapshots(),
                  builder: (context, dSnap) {
                    if (dSnap.hasError) {
                      return Center(child: Text('Erro: ${dSnap.error}'));
                    }
                    final deptData = dSnap.data?.data();
                    final leaderCpfs = ChurchDepartmentLeaders.cpfsFromDepartmentData(
                        deptData);
                    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                      stream: membersCol
                          .where('DEPARTAMENTOS', arrayContains: deptId)
                          .snapshots(),
                      builder: (context, mSnap) {
                        if (mSnap.hasError) {
                          return Center(child: Text('Erro: ${mSnap.error}'));
                        }
                        final loading = (dSnap.connectionState ==
                                    ConnectionState.waiting &&
                                !dSnap.hasData) ||
                            (mSnap.connectionState ==
                                    ConnectionState.waiting &&
                                !mSnap.hasData);
                        if (loading) {
                          return const Center(child: CircularProgressIndicator());
                        }
                        final docs = mSnap.data?.docs ?? [];
                        String cpfOf(
                            QueryDocumentSnapshot<Map<String, dynamic>> d) {
                          return (d.data()['CPF'] ?? d.data()['cpf'] ?? '')
                              .toString()
                              .replaceAll(RegExp(r'\D'), '');
                        }

                        final byCpf =
                            <String, QueryDocumentSnapshot<Map<String, dynamic>>>{};
                        for (final d in docs) {
                          final c = cpfOf(d);
                          if (c.length == 11) byCpf[c] = d;
                        }
                        final leaderDocs =
                            <QueryDocumentSnapshot<Map<String, dynamic>>>[];
                        final orphanCpfs = <String>[];
                        for (final cpf in leaderCpfs) {
                          final found = byCpf[cpf];
                          if (found != null) {
                            leaderDocs.add(found);
                          } else {
                            orphanCpfs.add(cpf);
                          }
                        }
                        final leaderSet = leaderCpfs.toSet();
                        final otherDocs = docs
                            .where((d) => !leaderSet.contains(cpfOf(d)))
                            .toList();
                        otherDocs.sort((a, b) => _nomeMembro(a)
                            .toLowerCase()
                            .compareTo(_nomeMembro(b).toLowerCase()));

                        return ListView(
                          controller: scrollController,
                          padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
                          children: [
                            _sectionTitle('Liderança'),
                            const SizedBox(height: 8),
                            if (leaderDocs.isEmpty && orphanCpfs.isEmpty)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 12),
                                child: Text(
                                  canWrite
                                      ? 'Nenhum líder. Use o botão “Líder” acima.'
                                      : 'Nenhum líder definido neste departamento.',
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: Colors.grey.shade600,
                                  ),
                                ),
                              ),
                            ...leaderDocs.map(
                              (doc) => _leaderCard(
                                context: context,
                                doc: doc,
                              ),
                            ),
                            ...orphanCpfs.map(
                              (cpf) => _orphanLeaderTile(context, cpf),
                            ),
                            const SizedBox(height: 16),
                            Row(
                              children: [
                                Expanded(child: _sectionTitle('Membros')),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 10, vertical: 4),
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                      colors: [
                                        _cA.withValues(alpha: 0.2),
                                        _cB.withValues(alpha: 0.14),
                                      ],
                                    ),
                                    borderRadius: BorderRadius.circular(999),
                                    border: Border.all(
                                      color: _cA.withValues(alpha: 0.28),
                                    ),
                                  ),
                                  child: Text(
                                    '${docs.length}',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w900,
                                      fontSize: 12,
                                      color: Colors.grey.shade900,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            if (docs.isEmpty)
                              Text(
                                'Nenhum membro vinculado.',
                                style: TextStyle(color: Colors.grey.shade600),
                              ),
                            ...otherDocs.map(
                              (doc) => _memberRow(context, doc),
                            ),
                          ],
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Sheet para ver membros do departamento e remover (quando lançado errado).
class _VerMembrosSheet extends StatefulWidget {
  final String tenantId;
  final String deptId;
  final String deptName;
  final List<QueryDocumentSnapshot<Map<String, dynamic>>> members;
  final CollectionReference<Map<String, dynamic>> membersCol;
  final bool canRemove;
  final VoidCallback? onRemoved;

  const _VerMembrosSheet({
    required this.tenantId,
    required this.deptId,
    required this.deptName,
    required this.members,
    required this.membersCol,
    this.canRemove = false,
    this.onRemoved,
  });

  @override
  State<_VerMembrosSheet> createState() => _VerMembrosSheetState();
}

class _VerMembrosSheetState extends State<_VerMembrosSheet> {
  late List<QueryDocumentSnapshot<Map<String, dynamic>>> _list;

  @override
  void initState() {
    super.initState();
    _list = List.from(widget.members);
  }

  String _memberName(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data();
    return (d['NOME_COMPLETO'] ?? d['nome'] ?? d['name'] ?? doc.id)
        .toString()
        .trim();
  }

  String _memberCpfDigits(Map<String, dynamic> d) =>
      (d['CPF'] ?? d['cpf'] ?? '').toString().replaceAll(RegExp(r'\D'), '');

  Future<void> _removerMembro(
      QueryDocumentSnapshot<Map<String, dynamic>> doc) async {
    final nome = _memberName(doc);
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusLg)),
        title: const Text('Remover do departamento'),
        content: Text('Remover "$nome" do departamento ${widget.deptName}?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFDC2626)),
            child: const Text('Remover'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      await DepartmentMemberIntegrationService.unlinkMember(
        tenantId: widget.tenantId,
        departmentId: widget.deptId,
        memberDocId: doc.id,
        memberData: doc.data(),
      );
      if (mounted) {
        setState(() => _list.removeWhere((e) => e.id == doc.id));
        widget.onRemoved?.call();
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('"$nome" removido do departamento.',
                style: const TextStyle(color: Colors.white)),
            backgroundColor: Colors.green));
      }
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Erro ao remover: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.5,
      maxChildSize: 0.9,
      minChildSize: 0.3,
      expand: false,
      builder: (context, scrollController) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Membros do departamento',
              style: Theme.of(context)
                  .textTheme
                  .titleLarge
                  ?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 4),
            Text(
              widget.deptName,
              style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: _list.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.people_outline_rounded,
                              size: 48, color: Colors.grey.shade400),
                          const SizedBox(height: 12),
                          Text('Nenhum membro neste departamento.',
                              style: TextStyle(color: Colors.grey.shade600)),
                        ],
                      ),
                    )
                  : ListView.builder(
                      controller: scrollController,
                      itemCount: _list.length,
                      itemBuilder: (context, i) {
                        final doc = _list[i];
                        final nome = _memberName(doc);
                        return Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(12),
                            boxShadow: [
                              BoxShadow(
                                  color: Colors.black.withOpacity(0.04),
                                  blurRadius: 8,
                                  offset: const Offset(0, 2))
                            ],
                          ),
                          child: ListTile(
                            leading: FotoMembroWidget(
                              size: 40,
                              tenantId: widget.tenantId,
                              memberId: doc.id,
                              imageUrl: imageUrlFromMap(doc.data()),
                              cpfDigits: _memberCpfDigits(doc.data()),
                              memberData: doc.data(),
                            ),
                            title: Text(nome),
                            trailing: widget.canRemove
                                ? IconButton(
                                    tooltip: 'Remover do departamento',
                                    onPressed: () => _removerMembro(doc),
                                    icon: const Icon(
                                        Icons.person_remove_rounded,
                                        color: Color(0xFFDC2626),
                                        size: 22),
                                    style: IconButton.styleFrom(
                                        minimumSize: const Size(
                                            ThemeCleanPremium.minTouchTarget,
                                            ThemeCleanPremium.minTouchTarget)),
                                  )
                                : null,
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Sheet para vincular membros ao departamento (escalas, reuniões).
class _VincularMembrosSheet extends StatefulWidget {
  final String tenantId;
  final String deptName;
  final List<QueryDocumentSnapshot<Map<String, dynamic>>> members;
  final Set<String> selecionados;

  const _VincularMembrosSheet({
    required this.tenantId,
    required this.deptName,
    required this.members,
    required this.selecionados,
  });

  @override
  State<_VincularMembrosSheet> createState() => _VincularMembrosSheetState();
}

class _VincularMembrosSheetState extends State<_VincularMembrosSheet> {
  late Set<String> _selected;

  @override
  void initState() {
    super.initState();
    _selected = Set<String>.from(widget.selecionados);
  }

  String _memberName(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data();
    return (d['NOME_COMPLETO'] ?? d['nome'] ?? d['name'] ?? doc.id)
        .toString()
        .trim();
  }

  String _memberCpfDigits(Map<String, dynamic> d) =>
      (d['CPF'] ?? d['cpf'] ?? '').toString().replaceAll(RegExp(r'\D'), '');

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      maxChildSize: 0.95,
      minChildSize: 0.3,
      expand: false,
      builder: (context, scrollController) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Vincular membros',
              style: Theme.of(context)
                  .textTheme
                  .titleLarge
                  ?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 4),
            Text(
              '${widget.deptName} — marque os membros que fazem parte para escalas e reuniões.',
              style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: ListView.builder(
                controller: scrollController,
                itemCount: widget.members.length,
                itemBuilder: (context, i) {
                  final doc = widget.members[i];
                  final id = doc.id;
                  final nome = _memberName(doc);
                  final checked = _selected.contains(id);
                  return CheckboxListTile(
                    value: checked,
                    title: Text(nome),
                    secondary: FotoMembroWidget(
                      size: 40,
                      tenantId: widget.tenantId,
                      memberId: id,
                      imageUrl: imageUrlFromMap(doc.data()),
                      cpfDigits: _memberCpfDigits(doc.data()),
                      memberData: doc.data(),
                    ),
                    controlAffinity: ListTileControlAffinity.leading,
                    onChanged: (v) {
                      setState(() {
                        if (v == true) {
                          _selected.add(id);
                        } else {
                          _selected.remove(id);
                        }
                      });
                    },
                  );
                },
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancelar'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () => Navigator.pop(context, _selected),
                    icon: const Icon(Icons.check_rounded, size: 20),
                    label: Text('Salvar (${_selected.length})'),
                    style: FilledButton.styleFrom(
                      backgroundColor: ThemeCleanPremium.primary,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
