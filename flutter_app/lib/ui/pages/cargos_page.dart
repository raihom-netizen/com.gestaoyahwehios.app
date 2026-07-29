import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:gestao_yahweh/core/cache/yahweh_module_caches.dart';
import 'package:gestao_yahweh/services/app_permissions.dart';
import 'package:gestao_yahweh/services/church_funcoes_controle_service.dart';
import 'package:gestao_yahweh/services/firestore_stream_utils.dart';
import 'package:gestao_yahweh/core/firebase_paths.dart';
import 'package:gestao_yahweh/core/repositories/church_repository.dart';
import 'package:gestao_yahweh/ui/pages/lideranca_page.dart';
import 'package:gestao_yahweh/ui/theme_clean_premium.dart';
import 'package:gestao_yahweh/core/panel/panel_resilient_load.dart';
import 'package:gestao_yahweh/ui/widgets/church_panel_ui_helpers.dart';
import 'package:gestao_yahweh/ui/widgets/foto_membro_widget.dart';
import 'package:gestao_yahweh/ui/pages/members_page.dart' show MembersPage;
import 'package:gestao_yahweh/utils/church_module_query_probe.dart';
import 'package:gestao_yahweh/utils/firestore_publish_recovery.dart';
import 'package:gestao_yahweh/utils/firestore_read_resilience.dart';
import 'package:gestao_yahweh/utils/firestore_web_guard.dart';
import 'package:gestao_yahweh/services/church_cargos_load_service.dart';
import 'package:gestao_yahweh/services/church_cargo_members_load_service.dart';
import 'package:gestao_yahweh/core/church_panel_read_timeouts.dart';
import 'package:gestao_yahweh/core/firebase_bootstrap.dart';
import 'package:gestao_yahweh/core/roles_permissions.dart';
import 'package:gestao_yahweh/core/tenant/church_panel_tenant.dart';
import 'package:gestao_yahweh/services/igreja_direct_firestore_reads.dart';
import 'package:gestao_yahweh/ui/widgets/church_wisdom_module_widgets.dart';
import 'package:gestao_yahweh/ui/widgets/yahweh_wisdom_visual_kit.dart';
import 'package:flutter_staggered_animations/flutter_staggered_animations.dart';

/// Mesma faixa dourada dos cards em [DepartmentsPage] — identidade visual alinhada.
const Color _kCargoListGoldAccent = Color(0xFFF5C518);

/// `igrejas/{tenantId}/membros/...`
String? _tenantIdFromMembroDocRef(DocumentReference<Map<String, dynamic>> ref) {
  final p = ref.path.split('/');
  if (p.length >= 2 && p[0] == 'igrejas') return p[1];
  return null;
}

/// Chave principal de cargo/função — alinhado a [MembersPage] (`FUNCAO`, `FUNCAO_PERMISSOES`, `CARGO`).
String _memberPrimaryCargoKey(Map<String, dynamic> d) =>
    ChurchCargoMembersLoadService.memberPrimaryCargoKey(d);

Future<Map<String, dynamic>> _memberRolePatchForFuncao({
  required String tenantId,
  required String funcaoFinal,
  required List<String> funcoes,
}) async {
  var permBase = funcaoFinal.toLowerCase();
  try {
    permBase = await ChurchFuncoesControleService.resolvePermissionBase(
      tenantId,
      funcaoFinal,
    );
  } catch (_) {}
  return {
    'FUNCAO': funcaoFinal,
    'FUNCAO_PERMISSOES': permBase,
    'FUNCOES': funcoes,
    'CARGO': funcaoFinal,
    'funcao': funcaoFinal,
    'role': permBase,
  };
}

Future<void> _writeMembroDocMergeResilient({
  required String churchId,
  required String memberDocId,
  required Map<String, dynamic> updates,
}) async {
  final cid = ChurchPanelTenant.forFirestore(churchId);
  if (cid.isEmpty || memberDocId.trim().isEmpty) {
    throw StateError('Igreja ou membro não identificado.');
  }
  if (kIsWeb) {
    await FirestoreWebGuard.ensurePanelReadReady().catchError((_) {});
    await FirestoreWebGuard.prepareForPublishWrite().catchError((_) {});
  }
  final ref = ChurchUiCollections.membros(cid).doc(memberDocId.trim());
  await FirestoreWebGuard.runWithWebRecovery(
    () => runFirestorePublishWithRecovery(
      () => ref.set(updates, SetOptions(merge: true)),
      maxAttempts: 4,
    ),
    maxAttempts: 4,
  );
}

Future<void> _writeUsersDocMergeResilient({
  required String authUid,
  required Map<String, dynamic> patch,
}) async {
  final uid = authUid.trim();
  if (uid.isEmpty) return;
  if (kIsWeb) {
    await FirestoreWebGuard.prepareForPublishWrite().catchError((_) {});
  }
  await FirestoreWebGuard.runWithWebRecovery(
    () => runFirestorePublishWithRecovery(
      () => firebaseDefaultFirestore
          .collection('users')
          .doc(uid)
          .set(patch, SetOptions(merge: true)),
      maxAttempts: 4,
    ),
    maxAttempts: 4,
  );
}

class _WelcomeCargoRow {
  final String docId;
  final String name;
  final String key;
  final String permissionTemplate;
  final int hierarchyLevel;
  final int accentColor;
  final bool requiresConsecrationDate;

  const _WelcomeCargoRow({
    required this.docId,
    required this.name,
    required this.key,
    required this.permissionTemplate,
    required this.hierarchyLevel,
    required this.accentColor,
    required this.requiresConsecrationDate,
  });
}

/// Chip informativo usado nos cards de cargo (nível, permissões, status).
class _CargoInfoChip extends StatelessWidget {
  const _CargoInfoChip({
    required this.icon,
    required this.label,
    required this.accent,
  });

  final IconData icon;
  final String label;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: accent.withValues(alpha: 0.25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: accent),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              color: accent.withValues(alpha: 0.9),
            ),
          ),
        ],
      ),
    );
  }
}

/// Cargos (funções) da igreja — cadastro em Pessoas.
/// Super Premium: cards clicáveis, lista de membros vinculados, remover/alterar cargo.
class CargosPage extends StatefulWidget {
  final String tenantId;
  final String role;

  /// Dentro de [IgrejaCleanShell]: evita [SafeArea] superior extra sob o cartão do módulo.
  final bool embeddedInShell;
  final VoidCallback? onOpenPanelCorpoAdministrativo;

  const CargosPage({
    super.key,
    required this.tenantId,
    required this.role,
    this.embeddedInShell = false,
    this.onOpenPanelCorpoAdministrativo,
  });

  @override
  State<CargosPage> createState() => _CargosPageState();
}

class _CargosPageState extends State<CargosPage> {
  String? _resolvedTenantId;
  late Future<QuerySnapshot<Map<String, dynamic>>> _cargosFuture;

  /// Evita loop ao criar cargos padrão automaticamente.
  bool _triedAutoSeed = false;
  int _cargosLoadRetryGen = 0;
  bool _cargosLoadPending = true;
  String? _cargosLoadSoftError;

  /// 0 = cadastro, 1 = ativos, 2 = arquivados.
  int _cargoListTab = 0;

  /// Busca rápida na lista de cargos.
  final TextEditingController _cargoSearchController = TextEditingController();
  Timer? _cargoSearchDebounce;
  String _cargoSearchQuery = '';

  // Helpers de formulário movidos para [_CargoFormPage].

  static const _welcomeCargos = <_WelcomeCargoRow>[
    _WelcomeCargoRow(
      docId: 'welcome_pastor_presidente',
      name: 'Pastor Presidente / Administrador',
      key: 'pastor_presidente',
      permissionTemplate: 'pastor_presidente',
      hierarchyLevel: 100,
      accentColor: 0xFF1565C0,
      requiresConsecrationDate: true,
    ),
    _WelcomeCargoRow(
      docId: 'welcome_pastor_auxiliar',
      name: 'Pastor Auxiliar / Ministerial',
      key: 'pastor_auxiliar',
      permissionTemplate: 'pastor_auxiliar',
      hierarchyLevel: 88,
      accentColor: 0xFF5E35B1,
      requiresConsecrationDate: true,
    ),
    _WelcomeCargoRow(
      docId: 'welcome_secretario',
      name: 'Secretário(a)',
      key: 'secretario',
      permissionTemplate: 'secretario',
      hierarchyLevel: 72,
      accentColor: 0xFF00897B,
      requiresConsecrationDate: false,
    ),
    _WelcomeCargoRow(
      docId: 'welcome_tesoureiro',
      name: 'Tesoureiro(a)',
      key: 'tesoureiro',
      permissionTemplate: 'tesoureiro',
      hierarchyLevel: 65,
      accentColor: 0xFF2E7D32,
      requiresConsecrationDate: false,
    ),
    _WelcomeCargoRow(
      docId: 'welcome_lider_departamento',
      name: 'Líder de Departamento',
      key: 'lider_departamento',
      permissionTemplate: 'lider_departamento',
      hierarchyLevel: 55,
      accentColor: 0xFF6A1B9A,
      requiresConsecrationDate: false,
    ),
    _WelcomeCargoRow(
      docId: 'welcome_membro',
      name: 'Membro / Congregado',
      key: 'membro',
      permissionTemplate: 'membro',
      hierarchyLevel: 12,
      accentColor: 0xFF78909C,
      requiresConsecrationDate: false,
    ),
  ];

  CollectionReference<Map<String, dynamic>> get _col =>
      ChurchUiCollections.cargos(_loadChurchId);

  String get _loadChurchId => ChurchPanelTenant.forFirestore(
    _resolvedTenantId?.trim().isNotEmpty == true
        ? _resolvedTenantId
        : widget.tenantId,
  );

  Timer? _webLoadCap;

  void _onCargoSearchChanged() {
    _cargoSearchDebounce?.cancel();
    _cargoSearchDebounce = Timer(const Duration(milliseconds: 250), () {
      if (!mounted) return;
      final q = _cargoSearchController.text.trim().toLowerCase();
      if (_cargoSearchQuery != q) setState(() => _cargoSearchQuery = q);
    });
  }

  void _startWebLoadingCap() {
    if (!kIsWeb) return;
    _webLoadCap?.cancel();
    _webLoadCap = Timer(PanelResilientLoad.webLoadingCap, () {
      if (!mounted || !_cargosLoadPending) return;
      final fallback = _peekInstantCargosSnap();
      setState(() {
        _cargosLoadPending = false;
        if (fallback != null && fallback.docs.isNotEmpty) {
          _cargosFuture = Future.value(fallback);
        }
      });
      _scheduleCargosRetry();
    });
  }

  QuerySnapshot<Map<String, dynamic>>? _peekInstantCargosSnap() {
    final seed = _loadChurchId;
    if (seed.isEmpty) return null;

    final moduleDocs = YahwehModuleCaches.cargos.docs;
    if (moduleDocs.isNotEmpty) {
      return MergedFirestoreQuerySnapshot(moduleDocs);
    }

    final ram =
        ChurchCargosLoadService.peekRamAny(seed) ??
        ChurchCargosLoadService.peekRam(seed);
    if (ram != null && ram.isNotEmpty) {
      return MergedFirestoreQuerySnapshot(ram);
    }

    final mem = FirestoreReadResilience.peekLastGoodQuery(
      ChurchCargosLoadService.cacheKey(seed),
    );
    if (mem != null && mem.docs.isNotEmpty) return mem;
    return null;
  }

  Future<QuerySnapshot<Map<String, dynamic>>> _loadCargosWithCap({
    bool forceServer = false,
  }) async {
    _cargosLoadSoftError = null;
    try {
      return await _loadCargos(forceServer: forceServer).timeout(
        kIsWeb ? const Duration(seconds: 14) : ChurchPanelReadTimeouts.queryCap,
      );
    } catch (e) {
      final fallback = _peekInstantCargosSnap();
      if (fallback != null && fallback.docs.isNotEmpty) {
        _cargosLoadSoftError = e.toString();
        return fallback;
      }
      _cargosLoadSoftError = e is TimeoutException
          ? 'Demorou demais a carregar. Verifique a rede e toque em Tentar novamente.'
          : e.toString();
      return const MergedFirestoreQuerySnapshot([]);
    } finally {
      if (mounted) {
        _webLoadCap?.cancel();
        _cargosLoadPending = false;
      }
    }
  }

  Future<void> _tryIndexedDbCacheFirst() async {
    if (_peekInstantCargosSnap() != null) return;
    try {
      await _prepareCargosRead();
      final cacheSnap = await FirestoreWebGuard.runWithWebRecovery(
        () => ChurchUiCollections.cargos(_loadChurchId)
            .limit(ChurchCargosLoadService.kLimit)
            .get(const GetOptions(source: Source.cache)),
        maxAttempts: 3,
      ).timeout(const Duration(seconds: 3));
      if (cacheSnap.docs.isEmpty || !mounted || !_cargosLoadPending) return;
      setState(() {
        _cargosFuture = Future.value(cacheSnap);
        _cargosLoadPending = false;
      });
      _webLoadCap?.cancel();
    } catch (_) {}
  }

  void _scheduleCargosRetry() {
    final gen = ++_cargosLoadRetryGen;
    for (final delay in const [2, 6, 14]) {
      Future<void>.delayed(Duration(seconds: delay), () async {
        if (!mounted || gen != _cargosLoadRetryGen) return;
        try {
          final snap = await _loadCargosWithCap(
            forceServer: !kIsWeb && delay >= 6,
          );
          if (!mounted || gen != _cargosLoadRetryGen) return;
          if (snap.docs.isNotEmpty) {
            setState(() => _cargosFuture = Future.value(snap));
          }
        } catch (_) {}
      });
    }
  }

  Future<void> _prepareCargosRead() async {
    if (!kIsWeb) return;
    await ensureFirebaseReadyForPanelRead().catchError((_) {});
    await FirestoreWebGuard.ensurePanelReadReady().catchError((_) {});
  }

  bool get _canWrite {
    final s = ChurchRolePermissions.snapshotFor(widget.role);
    return s.manageCargosCatalog ||
        s.editAnyMember ||
        AppPermissions.canEditDepartments(widget.role);
  }

  Future<QuerySnapshot<Map<String, dynamic>>> _loadCargos({
    bool forceServer = false,
  }) async {
    if (kIsWeb) {
      await _prepareCargosRead();
    }
    final churchId = _loadChurchId;
    if (churchId.isEmpty) {
      return const MergedFirestoreQuerySnapshot([]);
    }
    final path = FirebasePaths.cargos(churchId);

    try {
      Future<ChurchCargosLoadResult> runLoad({
        required String seed,
        required bool server,
      }) => FirestoreWebGuard.runWithWebRecovery(
        () => ChurchCargosLoadService.load(
          seedTenantId: seed,
          forceServer: server,
          forceRefresh: server,
        ),
        maxAttempts: 4,
      );

      var result = await runLoad(
        seed: widget.tenantId.trim().isNotEmpty
            ? widget.tenantId.trim()
            : churchId,
        server: forceServer,
      );

      if (result.docs.isNotEmpty) {
        ChurchCargosLoadService.putRam(result.churchId, result.docs);
        unawaited(ChurchCargosLoadService.persistAfterLoad(result));
        ChurchModuleQueryProbe.logSuccess(
          module: 'Cargos',
          churchId: result.churchId,
          path: path,
          totalDocs: result.docs.length,
        );
        return result.snapshot;
      }

      if (result.softError != null) {
        ChurchModuleQueryProbe.logError(
          module: 'Cargos',
          churchId: churchId,
          path: path,
          error: result.softError!,
        );
        // Erro de leitura ≠ coleção vazia — sem isto a UI concluía «0 cargos»
        // e oferecia recriar os padrões com dados reais no servidor.
        _cargosLoadSoftError = result.softError;
      } else {
        ChurchModuleQueryProbe.logSuccess(
          module: 'Cargos',
          churchId: churchId,
          path: path,
          totalDocs: 0,
        );
      }
      return result.snapshot;
    } catch (e) {
      final fallback = _peekInstantCargosSnap();
      if (fallback != null && fallback.docs.isNotEmpty) {
        _cargosLoadSoftError = e.toString();
        return fallback;
      }
      rethrow; // _loadCargosWithCap regista o erro (nunca vazio silencioso).
    }
  }

  Future<void> _refreshCargosBackground({bool forceServer = false}) async {
    try {
      if (kIsWeb) {
        await _prepareCargosRead();
      }
      final snap = await _loadCargosWithCap(forceServer: forceServer);
      if (!mounted || snap.docs.isEmpty) return;
      setState(() {
        _cargosFuture = Future.value(snap);
        _cargosLoadPending = false;
      });
    } catch (_) {}
  }

  @override
  void initState() {
    super.initState();
    _resolvedTenantId = ChurchPanelTenant.forFirestore(widget.tenantId);
    _cargoSearchController.addListener(_onCargoSearchChanged);
    unawaited(YahwehModuleCaches.cargos.warmUp(_loadChurchId));
    final instant = _peekInstantCargosSnap();
    if (instant != null) {
      _cargosFuture = Future.value(instant);
      _cargosLoadPending = false;
      unawaited(_refreshCargosBackground());
    } else {
      _cargosFuture = _loadCargosWithCap();
      unawaited(_tryIndexedDbCacheFirst());
      unawaited(YahwehModuleCaches.cargos.ensureLoaded(_loadChurchId));
    }
    _startWebLoadingCap();
  }

  @override
  void dispose() {
    _cargoSearchDebounce?.cancel();
    _cargoSearchController.removeListener(_onCargoSearchChanged);
    _cargoSearchController.dispose();
    _webLoadCap?.cancel();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant CargosPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.tenantId != widget.tenantId) {
      _cargosLoadRetryGen++;
      _resolvedTenantId = ChurchPanelTenant.forFirestore(widget.tenantId);
      _triedAutoSeed = false;
      _cargosLoadPending = true;
      unawaited(YahwehModuleCaches.cargos.warmUp(_loadChurchId));
      final instant = _peekInstantCargosSnap();
      if (instant != null) {
        _cargosFuture = Future.value(instant);
        _cargosLoadPending = false;
        unawaited(_refreshCargosBackground());
      } else {
        _cargosFuture = _loadCargosWithCap();
        unawaited(_tryIndexedDbCacheFirst());
        unawaited(YahwehModuleCaches.cargos.ensureLoaded(_loadChurchId));
      }
      _startWebLoadingCap();
    }
  }

  Future<void> _commitCargosBatch(WriteBatch batch) async {
    if (kIsWeb) {
      await FirestoreWebGuard.ensurePanelReadReady().catchError((_) {});
      await FirestoreWebGuard.prepareForPublishWrite().catchError((_) {});
    }
    await FirestoreWebGuard.runWithWebRecovery(
      () =>
          runFirestorePublishWithRecovery(() => batch.commit(), maxAttempts: 4),
      maxAttempts: 4,
    );
  }

  /// Cria na base os cargos padrão quando a coleção está vazia (novas igrejas).
  Future<void> _seedPadroes() async {
    try {
      if (kIsWeb) {
        await _prepareCargosRead();
      }
      final churchId = _loadChurchId;
      if (churchId.isEmpty) return;
      final col = ChurchUiCollections.cargos(churchId);
      final snap = await FirestoreWebGuard.runWithWebRecovery(
        () => col.limit(1).get(),
        maxAttempts: 3,
      );
      if (snap.docs.isNotEmpty) return;
      final batch = firebaseDefaultFirestore.batch();
      for (var i = 0; i < _welcomeCargos.length; i++) {
        final row = _welcomeCargos[i];
        batch.set(col.doc(row.docId), <String, dynamic>{
          'name': row.name,
          'key': row.key,
          'permissionTemplate': row.permissionTemplate,
          'hierarchyLevel': row.hierarchyLevel,
          'accentColor': row.accentColor,
          'requiresConsecrationDate': row.requiresConsecrationDate,
          'order': i,
          'isDefaultPreset': true,
          'isWelcomeKit': true,
          'modulePermissions': row.key == 'lider_departamento'
              ? AppPermissions.defaultDepartmentLeaderModulePermissions()
              : <String>[],
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }
      await _commitCargosBatch(batch);
    } catch (e) {
      debugPrint('CargosPage _seedPadroes: $e');
    }
    if (mounted) {
      unawaited(_refreshCargosBackground());
    }
  }

  Color _cargoAccentColorFromData(Map<String, dynamic> m) {
    final v = m['accentColor'];
    if (v is int) {
      return Color(v);
    }
    if (v is num) {
      return Color(v.toInt());
    }
    final s = v?.toString().trim() ?? '';
    if (s.isEmpty) {
      return ThemeCleanPremium.primary;
    }
    try {
      if (s.startsWith('0x') || s.startsWith('0X')) {
        return Color(
          int.parse(
            s.replaceFirst(RegExp(r'^0x', caseSensitive: false), ''),
            radix: 16,
          ),
        );
      }
      final n = int.tryParse(s);
      if (n != null) {
        return Color(n);
      }
    } catch (_) {}
    return ThemeCleanPremium.primary;
  }

  Future<void> _refresh({bool forceServer = false}) async {
    if (!mounted) return;
    final server = forceServer && !kIsWeb;
    _cargosLoadRetryGen++;
    _cargosLoadPending = true;
    _startWebLoadingCap();
    setState(() {
      _cargosLoadSoftError = null;
      _cargosFuture = _loadCargosWithCap(forceServer: server);
    });
    try {
      await _cargosFuture;
    } catch (_) {
    } finally {
      if (mounted) _cargosLoadPending = false;
      _webLoadCap?.cancel();
    }
  }

  Widget _buildCargosHubCard(EdgeInsets padding) {
    return Padding(
      padding: EdgeInsets.fromLTRB(padding.left, 0, padding.right, 12),
      child: YahwehWisdomSectionCard(
        borderTint: YahwehWisdomVisualKit.tealAccent,
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            churchWisdomModuleIconLeading(
              icon: Icons.badge_rounded,
              accent: YahwehWisdomVisualKit.tealAccent,
              moduleAssetKey: 'cargos',
              size: 52,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Funções ministeriais',
                    style: GoogleFonts.inter(
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                      color: ThemeCleanPremium.onSurface,
                      letterSpacing: -0.3,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Toque num cargo para ver e vincular membros. Use + Novo para criar funções personalizadas.',
                    style: GoogleFonts.inter(
                      fontSize: 12.5,
                      height: 1.35,
                      fontWeight: FontWeight.w600,
                      color: Colors.grey.shade600,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTopActionRow({required EdgeInsets padding}) {
    if (!_canWrite) return const SizedBox.shrink();
    return Padding(
      padding: EdgeInsets.fromLTRB(padding.left, 8, padding.right, 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              'Organize as funções e permissões da igreja',
              style: TextStyle(
                fontSize: 13,
                color: ThemeCleanPremium.onSurfaceVariant,
              ),
            ),
          ),
          FilledButton.icon(
            onPressed: () => _addOrEdit(),
            icon: const Icon(Icons.add_rounded, size: 18),
            label: const Text('Novo cargo'),
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              backgroundColor: ThemeCleanPremium.primary,
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  Widget _cargoTabCell(String label, int index, bool selected) {
    return Expanded(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => setState(() => _cargoListTab = index),
          borderRadius: BorderRadius.circular(10),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(
              color: selected ? ThemeCleanPremium.primary : Colors.transparent,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              label,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.5,
                color: selected
                    ? Colors.white
                    : ThemeCleanPremium.onSurfaceVariant,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCargoTabs({required EdgeInsets padding}) {
    return Padding(
      padding: EdgeInsets.fromLTRB(padding.left, 4, padding.right, 12),
      child: Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: Colors.grey.shade100,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            _cargoTabCell('CADASTRO', 0, _cargoListTab == 0),
            _cargoTabCell('ATIVOS', 1, _cargoListTab == 1),
            _cargoTabCell('ARQUIVADOS', 2, _cargoListTab == 2),
          ],
        ),
      ),
    );
  }

  Widget _buildCargoSearchBar({required EdgeInsets padding}) {
    return Padding(
      padding: EdgeInsets.fromLTRB(padding.left, 0, padding.right, 12),
      child: TextField(
        controller: _cargoSearchController,
        textInputAction: TextInputAction.search,
        decoration: InputDecoration(
          hintText: 'Buscar cargo por nome ou chave...',
          prefixIcon: const Icon(Icons.search_rounded, size: 22),
          suffixIcon: ValueListenableBuilder<TextEditingValue>(
            valueListenable: _cargoSearchController,
            builder: (context, value, child) {
              if (value.text.isEmpty) return const SizedBox.shrink();
              return IconButton(
                icon: const Icon(Icons.close_rounded, size: 20),
                tooltip: 'Limpar busca',
                onPressed: () {
                  _cargoSearchController.clear();
                  if (_cargoSearchQuery.isNotEmpty) {
                    setState(() => _cargoSearchQuery = '');
                  }
                },
              );
            },
          ),
          filled: true,
          fillColor: Colors.white,
          contentPadding: const EdgeInsets.symmetric(vertical: 12),
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
            borderSide: BorderSide(color: ThemeCleanPremium.primary, width: 2),
          ),
        ),
      ),
    );
  }

  Widget _buildCreateCallSliver({required EdgeInsets padding}) {
    return SliverToBoxAdapter(
      child: Padding(
        padding: EdgeInsets.fromLTRB(padding.left, 0, padding.right, 16),
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                ThemeCleanPremium.primary,
                ThemeCleanPremium.primary.withValues(alpha: 0.82),
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusLg),
            boxShadow: [
              BoxShadow(
                color: ThemeCleanPremium.primary.withValues(alpha: 0.25),
                blurRadius: 16,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Material(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusLg),
            child: InkWell(
              onTap: () => _addOrEdit(),
              borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusLg),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: const Icon(
                        Icons.add_circle_outline_rounded,
                        color: Colors.white,
                        size: 26,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Criar novo cargo',
                            style: GoogleFonts.manrope(
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Defina nome, chave técnica, hierarquia e permissões de acesso.',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.white.withValues(alpha: 0.9),
                              height: 1.35,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Icon(
                      Icons.chevron_right_rounded,
                      color: Colors.white.withValues(alpha: 0.8),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPresetRestoreSliver({required EdgeInsets padding}) {
    return SliverToBoxAdapter(
      child: Padding(
        padding: EdgeInsets.fromLTRB(padding.left, 0, padding.right, 16),
        child: YahwehWisdomSectionCard(
          borderTint: YahwehWisdomVisualKit.tealAccent,
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              churchWisdomModuleIconLeading(
                icon: Icons.auto_fix_high_rounded,
                accent: YahwehWisdomVisualKit.tealAccent,
                moduleAssetKey: 'cargos',
                size: 46,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Cargos padrão do kit oficial',
                      style: GoogleFonts.inter(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: ThemeCleanPremium.onSurface,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Restaure os ${_welcomeCargos.length} cargos iniciais que ainda não existirem.',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade600,
                        height: 1.35,
                      ),
                    ),
                    const SizedBox(height: 10),
                    FilledButton.icon(
                      onPressed: _restoreMissingDefaultCargos,
                      icon: const Icon(Icons.add_box_rounded, size: 18),
                      label: const Text('Restaurar faltantes'),
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 10,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCargoCard(DocumentSnapshot<Map<String, dynamic>> d) {
    final data = d.data() ?? {};
    final name = (data['name'] ?? d.id).toString();
    final key = (data['key'] ?? d.id).toString();
    final hierarchy = (data['hierarchyLevel'] as num?)?.toInt();
    final accent = _cargoAccentColorFromData(data);
    final mods = data['modulePermissions'] ?? data['module_permissions'];
    final modCount = mods is List ? mods.length : 0;
    final isArchived = data['active'] == false;

    Widget actionChip({
      required IconData icon,
      required String label,
      required VoidCallback onTap,
      bool danger = false,
    }) {
      return Material(
        color: danger ? const Color(0xFFFFF5F5) : Colors.grey.shade50,
        borderRadius: BorderRadius.circular(10),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  icon,
                  size: 16,
                  color: danger
                      ? const Color(0xFFDC2626)
                      : Colors.grey.shade700,
                ),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: danger
                        ? const Color(0xFFDC2626)
                        : Colors.grey.shade700,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: ThemeCleanPremium.cardBackground,
        borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusMd),
        boxShadow: ThemeCleanPremium.softUiCardShadow,
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusMd),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                width: 5,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [accent, accent.withValues(alpha: 0.65)],
                  ),
                ),
              ),
              Expanded(
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: () => _openCargoMembros(d),
                    borderRadius: BorderRadius.circular(
                      ThemeCleanPremium.radiusMd,
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 14,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              churchWisdomModuleIconLeading(
                                icon: Icons.badge_rounded,
                                accent: accent,
                                moduleAssetKey: 'cargos',
                                size: 46,
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                            name,
                                            style: TextStyle(
                                              fontSize: 15,
                                              fontWeight: FontWeight.w800,
                                              letterSpacing: -0.2,
                                              color: isArchived
                                                  ? Colors.grey.shade500
                                                  : ThemeCleanPremium.onSurface,
                                              decoration: isArchived
                                                  ? TextDecoration.lineThrough
                                                  : null,
                                            ),
                                          ),
                                        ),
                                        if (isArchived)
                                          Container(
                                            margin: const EdgeInsets.only(
                                              left: 8,
                                            ),
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 8,
                                              vertical: 3,
                                            ),
                                            decoration: BoxDecoration(
                                              color: Colors.grey.shade200,
                                              borderRadius:
                                                  BorderRadius.circular(8),
                                            ),
                                            child: Text(
                                              'ARQUIVADO',
                                              style: TextStyle(
                                                fontSize: 9,
                                                fontWeight: FontWeight.w800,
                                                color: Colors.grey.shade600,
                                                letterSpacing: 0.5,
                                              ),
                                            ),
                                          ),
                                      ],
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      key.isNotEmpty
                                          ? 'Chave: $key'
                                          : 'Toque para ver membros vinculados',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color:
                                            ThemeCleanPremium.onSurfaceVariant,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              if (hierarchy != null)
                                _CargoInfoChip(
                                  icon: Icons.layers_rounded,
                                  label: 'Nível $hierarchy',
                                  accent: accent,
                                ),
                              if (modCount > 0)
                                _CargoInfoChip(
                                  icon: Icons.verified_user_rounded,
                                  label:
                                      '$modCount permissão${modCount == 1 ? '' : 'es'}',
                                  accent: accent,
                                ),
                              if (isArchived)
                                const _CargoInfoChip(
                                  icon: Icons.archive_rounded,
                                  label: 'Inativo',
                                  accent: Colors.grey,
                                ),
                            ],
                          ),
                          if (_canWrite) ...[
                            const SizedBox(height: 10),
                            const Divider(height: 1),
                            const SizedBox(height: 10),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                actionChip(
                                  icon: Icons.people_rounded,
                                  label: 'Membros',
                                  onTap: () => _openCargoMembros(d),
                                ),
                                actionChip(
                                  icon: Icons.edit_rounded,
                                  label: 'Editar',
                                  onTap: () => _addOrEdit(doc: d),
                                ),
                                actionChip(
                                  icon: isArchived
                                      ? Icons.unarchive_rounded
                                      : Icons.archive_rounded,
                                  label: isArchived ? 'Reativar' : 'Arquivar',
                                  onTap: () => _toggleArchive(d),
                                ),
                                actionChip(
                                  icon: Icons.delete_outline_rounded,
                                  label: 'Excluir',
                                  danger: true,
                                  onTap: () => _delete(d),
                                ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCadastroTabBody({required EdgeInsets padding}) {
    return CustomScrollView(
      primary: false,
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: [
        SliverToBoxAdapter(child: _buildCargosHubCard(padding)),
        _buildCreateCallSliver(padding: padding),
        _buildPresetRestoreSliver(padding: padding),
        SliverToBoxAdapter(child: SizedBox(height: padding.bottom)),
      ],
    );
  }

  Widget _buildEmptyCargosList({
    required EdgeInsets padding,
    required bool archived,
    String searchQuery = '',
  }) {
    final hasSearch = searchQuery.trim().isNotEmpty;
    final title = hasSearch
        ? 'Nenhum cargo encontrado'
        : (archived ? 'Nenhum cargo arquivado' : 'Nenhum cargo ativo');
    final message = hasSearch
        ? 'Nenhum resultado para "$searchQuery". Ajuste o termo ou limpe a busca.'
        : (archived
              ? 'Cargos arquivados aparecerão aqui. Você pode reativá-los quando quiser.'
              : 'Cadastre cargos na aba CADASTRO ou use o botão Novo cargo.');
    return Center(
      child: Padding(
        padding: EdgeInsets.fromLTRB(padding.left, 32, padding.right, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: ThemeCleanPremium.primary.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(24),
              ),
              child: Icon(
                archived ? Icons.archive_rounded : Icons.badge_outlined,
                size: 56,
                color: ThemeCleanPremium.primary.withValues(alpha: 0.7),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              title,
              style: const TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w800,
                color: ThemeCleanPremium.onSurface,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              message,
              style: TextStyle(
                fontSize: 13,
                color: Colors.grey.shade600,
                height: 1.35,
              ),
              textAlign: TextAlign.center,
            ),
            if (!archived && _canWrite) ...[
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: () => _addOrEdit(),
                icon: const Icon(Icons.add_rounded),
                label: const Text('Criar primeiro cargo'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _restoreMissingDefaultCargos() async {
    if (!_canWrite) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusLg),
        ),
        title: const Text('Restaurar cargos padrão'),
        content: Text(
          'Serão criados de novo os ${_welcomeCargos.length} cargos do kit oficial que ainda não existirem. '
          'Cargos personalizados não serão removidos.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Restaurar faltantes'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      if (kIsWeb) await _prepareCargosRead();
      final existing = await FirestoreWebGuard.runWithWebRecovery(
        () => _col.get(),
        maxAttempts: 4,
      );
      final have = existing.docs.map((d) => d.id).toSet();
      var n = 0;
      final batch = firebaseDefaultFirestore.batch();
      for (var i = 0; i < _welcomeCargos.length; i++) {
        final row = _welcomeCargos[i];
        if (have.contains(row.docId)) continue;
        batch.set(_col.doc(row.docId), <String, dynamic>{
          'name': row.name,
          'key': row.key,
          'permissionTemplate': row.permissionTemplate,
          'hierarchyLevel': row.hierarchyLevel,
          'accentColor': row.accentColor,
          'requiresConsecrationDate': row.requiresConsecrationDate,
          'order': i,
          'isDefaultPreset': true,
          'isWelcomeKit': true,
          'modulePermissions': <String>[],
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        });
        n++;
      }
      if (n == 0) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Todos os cargos padrão já existem.')),
          );
        }
        return;
      }
      await _commitCargosBatch(batch);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '$n cargo(s) padrão criado(s).',
              style: const TextStyle(color: Colors.white),
            ),
            backgroundColor: Colors.green,
          ),
        );
        unawaited(_refreshCargosBackground());
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Erro: $e')));
      }
    }
  }

  Future<void> _addOrEdit({DocumentSnapshot<Map<String, dynamic>>? doc}) async {
    if (!_canWrite) return;
    final saved =
        await Navigator.of(
          context,
          rootNavigator: widget.embeddedInShell,
        ).push<bool>(
          MaterialPageRoute<bool>(
            builder: (_) => _CargoFormPage(
              tenantId: _resolvedTenantId ?? widget.tenantId,
              doc: doc,
            ),
          ),
        );
    if (saved == true && mounted) {
      final msg = doc == null ? 'Cargo cadastrado!' : 'Cargo atualizado!';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(msg, style: const TextStyle(color: Colors.white)),
          backgroundColor: Colors.green,
        ),
      );
      unawaited(_refreshCargosBackground());
    }
  }

  Future<void> _toggleArchive(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) async {
    if (!_canWrite) return;
    final data = doc.data() ?? {};
    final isActive = data['active'] != false;
    final name = (data['name'] ?? doc.id).toString();
    final action = isActive ? 'arquivar' : 'reativar';
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusLg),
        ),
        title: Text('${isActive ? 'Arquivar' : 'Reativar'} cargo'),
        content: Text(
          'Deseja $action o cargo "$name"?${isActive ? ' Cargos arquivados ficam na aba Arquivados.' : ''}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(isActive ? 'Arquivar' : 'Reativar'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ChurchCargosLoadService.updateCargo(
        ref: doc.reference,
        payload: {
          'active': !isActive,
          'updatedAt': FieldValue.serverTimestamp(),
        },
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              isActive ? 'Cargo arquivado.' : 'Cargo reativado.',
              style: const TextStyle(color: Colors.white),
            ),
            backgroundColor: Colors.green,
          ),
        );
        unawaited(_refreshCargosBackground());
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Erro ao $action: $e')));
      }
    }
  }

  Future<void> _delete(DocumentSnapshot<Map<String, dynamic>> doc) async {
    if (!_canWrite) return;
    final name = (doc.data()?['name'] ?? '').toString();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusLg),
        ),
        title: const Row(
          children: [
            Icon(Icons.delete_outline_rounded, color: Color(0xFFDC2626)),
            SizedBox(width: 10),
            Text('Excluir cargo'),
          ],
        ),
        content: Text(
          'Excluir o cargo "$name"? Membros com este cargo continuarão com o valor no cadastro, mas o cargo não aparecerá mais na lista.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFDC2626),
            ),
            child: const Text('Excluir'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ChurchCargosLoadService.deleteCargo(doc.reference);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Cargo excluído.',
              style: TextStyle(color: Colors.white),
            ),
            backgroundColor: Colors.green,
          ),
        );
        unawaited(_refreshCargosBackground());
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Erro ao excluir: $e')));
      }
    }
  }

  void _openCargoMembros(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? {};
    final name = (data['name'] ?? doc.id).toString();
    final key = (data['key'] ?? doc.id).toString();
    final tenant = ChurchPanelTenant.forFirestore(
      _resolvedTenantId ?? widget.tenantId,
    );
    Navigator.of(context, rootNavigator: widget.embeddedInShell)
        .push(
          MaterialPageRoute<void>(
            builder: (_) => _CargoMembrosPage(
              tenantId: tenant,
              role: widget.role,
              cargoName: name,
              cargoKey: key,
              cargoRef: doc.reference,
              canWrite: _canWrite,
              onChanged: _refresh,
            ),
          ),
        )
        .then((_) => _refresh());
  }

  void _openLideranca() {
    Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => LiderancaPage(
          tenantId: _resolvedTenantId ?? widget.tenantId,
          role: widget.role,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = ThemeCleanPremium.isMobile(context);
    final padding = ThemeCleanPremium.pagePadding(context);
    final listPad = EdgeInsets.fromLTRB(
      padding.left,
      padding.top,
      padding.right,
      isMobile ? 88 : padding.bottom,
    );
    // Alinhado a [DepartmentsPage]: shell com [ModuleHeaderPremium] — sem AppBar duplicada.
    return Scaffold(
      backgroundColor: widget.embeddedInShell
          ? Colors.transparent
          : ThemeCleanPremium.surfaceVariant,
      appBar: null,
      body: SafeArea(
        top: !widget.embeddedInShell,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(padding.left, 4, padding.right, 0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  if (widget.onOpenPanelCorpoAdministrativo != null)
                    IconButton(
                      tooltip: 'Corpo administrativo (painel)',
                      onPressed: widget.onOpenPanelCorpoAdministrativo,
                      icon: Icon(
                        Icons.groups_rounded,
                        color: ThemeCleanPremium.primary,
                      ),
                      style: IconButton.styleFrom(
                        minimumSize: const Size(
                          ThemeCleanPremium.minTouchTarget,
                          ThemeCleanPremium.minTouchTarget,
                        ),
                      ),
                    ),
                  IconButton(
                    tooltip: 'Organograma ministerial',
                    onPressed: _openLideranca,
                    icon: Icon(
                      Icons.account_tree_rounded,
                      color: ThemeCleanPremium.primary,
                    ),
                    style: IconButton.styleFrom(
                      minimumSize: const Size(
                        ThemeCleanPremium.minTouchTarget,
                        ThemeCleanPremium.minTouchTarget,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Atualizar lista',
                    onPressed: () => _refresh(forceServer: true),
                    icon: Icon(
                      Icons.refresh_rounded,
                      color: ThemeCleanPremium.primary,
                    ),
                    style: IconButton.styleFrom(
                      minimumSize: const Size(
                        ThemeCleanPremium.minTouchTarget,
                        ThemeCleanPremium.minTouchTarget,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            _buildTopActionRow(padding: padding),
            _buildCargoTabs(padding: padding),
            if (_cargoListTab != 0) _buildCargoSearchBar(padding: padding),
            Expanded(
              child: FutureBuilder<QuerySnapshot<Map<String, dynamic>>>(
                future: _cargosFuture,
                builder: (context, snap) {
                  final isWaiting =
                      snap.connectionState == ConnectionState.waiting &&
                      !snap.hasData &&
                      !snap.hasError;
                  final cargosLoadFailed =
                      snap.hasError ||
                      (_cargosLoadSoftError != null &&
                          (snap.data?.docs.isEmpty ?? true));

                  // CADASTRO: opções de criação independentes dos dados.
                  if (_cargoListTab == 0) {
                    Widget body = _buildCadastroTabBody(padding: padding);
                    if (isWaiting) {
                      body = Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Padding(
                            padding: EdgeInsets.fromLTRB(
                              padding.left,
                              0,
                              padding.right,
                              8,
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(4),
                              child: LinearProgressIndicator(
                                minHeight: 3,
                                backgroundColor: ThemeCleanPremium.primary
                                    .withValues(alpha: 0.12),
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  ThemeCleanPremium.primary,
                                ),
                              ),
                            ),
                          ),
                          Expanded(child: body),
                        ],
                      );
                    }
                    if (cargosLoadFailed) {
                      body = Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Padding(
                            padding: EdgeInsets.fromLTRB(
                              padding.left,
                              8,
                              padding.right,
                              8,
                            ),
                            child: ChurchPanelResilientLoadBanner(
                              hasLocalData: false,
                              isSyncing: _cargosLoadPending,
                              errorTitle: 'Não foi possível carregar os cargos',
                              error: snap.error ?? _cargosLoadSoftError,
                              onRetry: () => _refresh(forceServer: true),
                            ),
                          ),
                          Expanded(child: body),
                        ],
                      );
                    }
                    return body;
                  }

                  if (isWaiting) {
                    return const ChurchPanelLoadingBody(itemCount: 4);
                  }

                  if (cargosLoadFailed) {
                    final fallback = _peekInstantCargosSnap();
                    if (fallback == null || fallback.docs.isEmpty) {
                      return Padding(
                        padding: const EdgeInsets.all(24),
                        child: ChurchPanelResilientLoadBanner(
                          hasLocalData: false,
                          isSyncing: _cargosLoadPending,
                          errorTitle: 'Não foi possível carregar os cargos',
                          error: snap.error ?? _cargosLoadSoftError,
                          onRetry: () => _refresh(forceServer: true),
                        ),
                      );
                    }
                  }

                  var docs = cargosLoadFailed
                      ? (_peekInstantCargosSnap()?.docs ?? [])
                      : (snap.data?.docs ?? []);

                  // Auto-seed só na aba ATIVOS e com leitura confirmada vazia.
                  if (_cargoListTab == 1 && docs.isEmpty) {
                    if (_canWrite &&
                        !_triedAutoSeed &&
                        !cargosLoadFailed &&
                        _cargosLoadSoftError == null) {
                      _triedAutoSeed = true;
                      WidgetsBinding.instance.addPostFrameCallback((_) async {
                        await _seedPadroes();
                        if (mounted) await _refresh();
                      });
                      return Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              SizedBox(
                                width: 48,
                                height: 48,
                                child: CircularProgressIndicator(
                                  strokeWidth: 3,
                                  color: ThemeCleanPremium.primary,
                                ),
                              ),
                              const SizedBox(height: 20),
                              Text(
                                'Preparando cargos padrão…',
                                style: TextStyle(
                                  fontSize: 17,
                                  fontWeight: FontWeight.w700,
                                  color: ThemeCleanPremium.onSurface,
                                ),
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: 8),
                              Text(
                                '${_welcomeCargos.length} cargos com hierarquia e permissões. Você pode editar ou excluir depois.',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: Colors.grey.shade600,
                                  height: 1.35,
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ],
                          ),
                        ),
                      );
                    }
                  }

                  final archived = _cargoListTab == 2;
                  docs = docs
                      .where((d) {
                        final active = d.data()['active'] != false;
                        return archived ? !active : active;
                      })
                      .toList(growable: false);

                  if (_cargoSearchQuery.isNotEmpty) {
                    final q = _cargoSearchQuery;
                    docs = docs
                        .where((d) {
                          final data = d.data();
                          final name = (data['name'] ?? '')
                              .toString()
                              .toLowerCase();
                          final key = (data['key'] ?? '')
                              .toString()
                              .toLowerCase();
                          return name.contains(q) || key.contains(q);
                        })
                        .toList(growable: false);
                  }

                  if (docs.isEmpty) {
                    return _buildEmptyCargosList(
                      padding: padding,
                      archived: archived,
                      searchQuery: _cargoSearchQuery,
                    );
                  }

                  // Docs já ordenados pelo serviço: order + hierarchy + name.
                  final listView = ListView.builder(
                    padding: EdgeInsets.fromLTRB(
                      listPad.left,
                      0,
                      listPad.right,
                      listPad.bottom,
                    ),
                    itemCount: docs.length,
                    itemBuilder: (_, i) {
                      final card = _buildCargoCard(docs[i]);
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
                  Widget list = kIsWeb
                      ? listView
                      : AnimationLimiter(child: listView);

                  if (cargosLoadFailed) {
                    list = Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Padding(
                          padding: EdgeInsets.fromLTRB(
                            padding.left,
                            8,
                            padding.right,
                            8,
                          ),
                          child: ChurchPanelResilientLoadBanner(
                            hasLocalData: true,
                            isSyncing: false,
                            showStaleCache: true,
                            errorTitle: 'Não foi possível carregar os cargos',
                            onRetry: () => _refresh(forceServer: true),
                          ),
                        ),
                        Expanded(child: list),
                      ],
                    );
                  }

                  if (kIsWeb) return SizedBox.expand(child: list);
                  return RefreshIndicator(
                    onRefresh: () => _refresh(forceServer: true),
                    color: ThemeCleanPremium.primary,
                    child: SizedBox.expand(child: list),
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

/// Formulário full-screen para criar/editar cargo — topo voltar, base Salvar/Cancelar.
class _CargoFormPage extends StatefulWidget {
  final String tenantId;
  final DocumentSnapshot<Map<String, dynamic>>? doc;

  const _CargoFormPage({required this.tenantId, this.doc});

  @override
  State<_CargoFormPage> createState() => _CargoFormPageState();
}

class _CargoFormPageState extends State<_CargoFormPage> {
  late final TextEditingController _nameCtrl;
  late final TextEditingController _keyCtrl;
  late final TextEditingController _hierCtrl;
  late String _template;
  late int _membrosTri;
  late int _muralTri;
  late int _eventosTri;
  late int _agendaTri;
  late bool _relatoriosFull;
  late Set<String> _relatorioPicks;
  late Set<String> _simpleSel;

  static const List<(String key, String label)> _kSimpleChips = [
    ('departamentos', 'Departamentos'),
    ('financeiro', 'Financeiro'),
    ('patrimonio', 'Patrimônio'),
    ('fornecedores', 'Fornecedores'),
    ('certificados', 'Certificados'),
    ('cartas_transferencias', 'Cartas e transferências'),
    ('escalas', 'Escalas'),
  ];

  static const List<(String id, String label)> _kRelatorioPickIds = [
    ('eventos', 'Eventos (PDF)'),
    ('aniversariantes', 'Aniversariantes'),
    ('membros', 'Membros'),
    ('financeiro', 'Financeiro / dashboard'),
    ('patrimonio', 'Patrimônio'),
    ('fornecedores', 'Fornecedores e prestadores'),
  ];

  @override
  void initState() {
    super.initState();
    final data = widget.doc?.data() ?? {};
    _nameCtrl = TextEditingController(text: (data['name'] ?? '').toString());
    _keyCtrl = TextEditingController(
      text: (data['key'] ?? widget.doc?.id ?? '').toString(),
    );
    _hierCtrl = TextEditingController(
      text: (data['hierarchyLevel'] ?? '').toString().trim().isEmpty
          ? '50'
          : '${data['hierarchyLevel']}',
    );
    _template = (data['permissionTemplate'] ?? data['key'] ?? 'membro')
        .toString()
        .trim();
    if (_template.isEmpty) _template = 'membro';

    final modRaw = data['modulePermissions'] ?? data['module_permissions'];
    final moduleSel = <String>{
      if (modRaw is List)
        for (final e in modRaw) (e ?? '').toString().trim().toLowerCase(),
    };

    _membrosTri = _parseTriMembros(moduleSel);
    _muralTri = _parseTriMural(moduleSel);
    _eventosTri = _parseTriEventos(moduleSel);
    _agendaTri = _parseTriAgenda(moduleSel);
    final relParsed = _parseRelatorios(moduleSel);
    _relatoriosFull = relParsed.$1;
    _relatorioPicks = {...relParsed.$2};
    _simpleSel = <String>{
      for (final c in _kSimpleChips)
        if (moduleSel.contains(c.$1)) c.$1,
    };

    final cargoKeyInitial = (data['key'] ?? widget.doc?.id ?? '')
        .toString()
        .trim()
        .toLowerCase();
    if (cargoKeyInitial == 'lider_departamento') {
      _relatoriosFull = false;
      _relatorioPicks.removeWhere(
        (e) => e != 'eventos' && e != 'aniversariantes',
      );
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _keyCtrl.dispose();
    _hierCtrl.dispose();
    super.dispose();
  }

  static int _parseTriMembros(Set<String> m) {
    if (m.contains('membros_edicao') ||
        (m.contains('membros') && !m.contains('membros_ver'))) {
      return 2;
    }
    if (m.contains('membros_ver')) return 1;
    return 0;
  }

  static int _parseTriMural(Set<String> m) {
    if (m.contains('mural_avisos_edicao')) return 2;
    if (m.contains('mural_avisos_somente_leitura')) return 1;
    return 0;
  }

  static int _parseTriEventos(Set<String> m) {
    if (m.contains('eventos_avisos_edicao') || m.contains('eventos')) return 2;
    if (m.contains('eventos_avisos_ver')) return 1;
    return 0;
  }

  static int _parseTriAgenda(Set<String> m) {
    if (m.contains('agenda_edicao')) return 2;
    if (m.contains('agenda_ver')) return 1;
    return 0;
  }

  static (bool full, Set<String> picks) _parseRelatorios(Set<String> m) {
    if (m.contains('relatorios')) return (true, <String>{});
    final picks = <String>{};
    for (final k in m) {
      if (k.startsWith('relatorio_')) {
        picks.add(k.substring(10));
      }
    }
    return (false, picks);
  }

  static Set<String> _serializeModulePermissions({
    required String cargoKey,
    required int membrosTri,
    required int muralTri,
    required int eventosTri,
    required int agendaTri,
    required Set<String> simple,
    required bool relatoriosFull,
    required Set<String> relatorioPicks,
  }) {
    final out = <String>{...simple};
    if (membrosTri == 1) out.add('membros_ver');
    if (membrosTri == 2) {
      out
        ..add('membros_ver')
        ..add('membros_edicao')
        ..add('membros');
    }
    if (muralTri == 1) out.add('mural_avisos_somente_leitura');
    if (muralTri == 2) out.add('mural_avisos_edicao');
    if (eventosTri == 1) out.add('eventos_avisos_ver');
    if (eventosTri == 2) {
      out
        ..add('eventos_avisos_ver')
        ..add('eventos_avisos_edicao')
        ..add('eventos');
    }
    if (agendaTri == 1) out.add('agenda_ver');
    if (agendaTri == 2) {
      out
        ..add('agenda_ver')
        ..add('agenda_edicao');
    }
    final isLiderDep = cargoKey.trim().toLowerCase() == 'lider_departamento';
    if (isLiderDep) {
      out.removeAll({'financeiro', 'patrimonio', 'fornecedores', 'relatorios'});
      out.removeWhere((k) => k.startsWith('relatorio_'));
      for (final id in relatorioPicks) {
        if (id == 'eventos' || id == 'aniversariantes') {
          out.add('relatorio_$id');
        }
      }
    } else {
      if (relatoriosFull) {
        out.add('relatorios');
      } else {
        for (final id in relatorioPicks) {
          out.add('relatorio_$id');
        }
      }
    }
    return out;
  }

  static String _nameToKey(String name) {
    return name
        .toLowerCase()
        .replaceAll(RegExp(r'[áàâã]'), 'a')
        .replaceAll(RegExp(r'[éèê]'), 'e')
        .replaceAll(RegExp(r'[íì]'), 'i')
        .replaceAll(RegExp(r'[óòôõ]'), 'o')
        .replaceAll(RegExp(r'[úù]'), 'u')
        .replaceAll(RegExp(r'[^a-z0-9]'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_|_$'), '');
  }

  static Widget _cargoAccessTriDropdown({
    required String title,
    required IconData icon,
    required int tri,
    required ValueChanged<int> onChanged,
    String label0 = 'Padrão',
    String label1 = 'Só ver',
    String label2 = 'Editar',
  }) {
    final primary = ThemeCleanPremium.primary;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Icon(icon, size: 18, color: primary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 13,
                letterSpacing: -0.2,
              ),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 118,
            child: DropdownButtonFormField<int>(
              initialValue: tri,
              isExpanded: true,
              isDense: true,
              decoration: InputDecoration(
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 8,
                ),
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                ),
              ),
              items: [
                DropdownMenuItem(value: 0, child: Text(label0)),
                DropdownMenuItem(value: 1, child: Text(label1)),
                DropdownMenuItem(value: 2, child: Text(label2)),
              ],
              onChanged: (v) {
                if (v != null) onChanged(v);
              },
            ),
          ),
        ],
      ),
    );
  }

  static String _multiSelectSummary(
    Set<String> selected,
    List<(String id, String label)> options,
    String emptyLabel,
  ) {
    if (selected.isEmpty) return emptyLabel;
    if (selected.length == 1) {
      final id = selected.first;
      for (final o in options) {
        if (o.$1 == id) return o.$2;
      }
      return id;
    }
    return '${selected.length} selecionados';
  }

  static Future<Set<String>?> _showMultiSelectSheet(
    BuildContext context, {
    required String title,
    required List<(String id, String label)> options,
    required Set<String> initial,
  }) {
    return showModalBottomSheet<Set<String>>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      backgroundColor: const Color(0xFFF8FAFC),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        var temp = {...initial};
        return StatefulBuilder(
          builder: (ctx, setS) {
            final maxH = MediaQuery.sizeOf(ctx).height * 0.72;
            return Padding(
              padding: EdgeInsets.fromLTRB(
                16,
                0,
                16,
                16 + MediaQuery.paddingOf(ctx).bottom,
              ),
              child: ConstrainedBox(
                constraints: BoxConstraints(maxHeight: maxH),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      title,
                      style: GoogleFonts.manrope(
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                        letterSpacing: -0.2,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Flexible(
                      child: ListView(
                        shrinkWrap: true,
                        children: [
                          for (final o in options)
                            CheckboxListTile(
                              value: temp.contains(o.$1),
                              onChanged: (v) => setS(() {
                                if (v == true) {
                                  temp.add(o.$1);
                                } else {
                                  temp.remove(o.$1);
                                }
                              }),
                              title: Text(
                                o.$2,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 14,
                                ),
                              ),
                              dense: true,
                              controlAffinity: ListTileControlAffinity.leading,
                              contentPadding: EdgeInsets.zero,
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => Navigator.pop(ctx),
                            child: const Text('Cancelar'),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: FilledButton(
                            onPressed: () => Navigator.pop(ctx, temp),
                            child: const Text('Aplicar'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  static Widget _cargoMultiSelectDropdown({
    required BuildContext context,
    required String label,
    required IconData icon,
    required List<(String id, String label)> options,
    required Set<String> selected,
    required ValueChanged<Set<String>> onChanged,
    String emptyLabel = 'Nenhum',
    bool enabled = true,
  }) {
    final summary = _multiSelectSummary(selected, options, emptyLabel);
    return InkWell(
      onTap: !enabled
          ? null
          : () async {
              final picked = await _showMultiSelectSheet(
                context,
                title: label,
                options: options,
                initial: selected,
              );
              if (picked != null) onChanged(picked);
            },
      borderRadius: BorderRadius.circular(12),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: Icon(icon, size: 20),
          suffixIcon: const Icon(Icons.keyboard_arrow_down_rounded),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 10,
          ),
          isDense: true,
          filled: true,
          fillColor: enabled ? Colors.white : Colors.grey.shade100,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
          ),
        ),
        child: Text(
          summary,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 13,
            color: enabled
                ? ThemeCleanPremium.onSurface
                : ThemeCleanPremium.onSurfaceVariant,
          ),
        ),
      ),
    );
  }

  Future<void> _save() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Informe o nome do cargo.')));
      return;
    }
    var key = _keyCtrl.text.trim().toLowerCase();
    if (key.isEmpty) key = _nameToKey(name);
    if (key.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Chave inválida para o cargo.')),
      );
      return;
    }
    final h = int.tryParse(_hierCtrl.text.trim()) ?? 50;
    final mods = _serializeModulePermissions(
      cargoKey: key,
      membrosTri: _membrosTri,
      muralTri: _muralTri,
      eventosTri: _eventosTri,
      agendaTri: _agendaTri,
      simple: _simpleSel,
      relatoriosFull: _relatoriosFull,
      relatorioPicks: _relatorioPicks,
    ).toList()..sort();

    final payload = <String, dynamic>{
      'name': name,
      'key': key,
      'permissionTemplate': _template,
      'hierarchyLevel': h.clamp(0, 100),
      'modulePermissions': mods,
      'updatedAt': FieldValue.serverTimestamp(),
    };

    final churchId = ChurchPanelTenant.forFirestore(widget.tenantId);
    try {
      if (widget.doc == null) {
        payload['order'] = 999;
        payload['createdAt'] = FieldValue.serverTimestamp();
        await ChurchCargosLoadService.createCargo(
          churchId: churchId,
          docId: key,
          payload: payload,
        );
      } else {
        await ChurchCargosLoadService.updateCargo(
          ref: widget.doc!.reference,
          payload: payload,
        );
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Erro ao salvar: $e')));
      }
    }
  }

  Widget _buildFormBody() {
    final templates = ChurchFuncoesControleService.permissionTemplates;
    final templateValue = templates.any((t) => t.key == _template)
        ? _template
        : 'membro';
    final cargoKeyLive = _keyCtrl.text.trim().toLowerCase();
    final isLiderDep = cargoKeyLive == 'lider_departamento';
    final primary = ThemeCleanPremium.primary;
    final chips = isLiderDep
        ? _kSimpleChips
              .where(
                (c) =>
                    c.$1 != 'financeiro' &&
                    c.$1 != 'patrimonio' &&
                    c.$1 != 'fornecedores',
              )
              .toList()
        : _kSimpleChips.toList();
    final relatorioOptions = [
      for (final r in _kRelatorioPickIds)
        if (!isLiderDep || r.$1 == 'eventos' || r.$1 == 'aniversariantes') r,
    ];

    return ListView(
      padding: ThemeCleanPremium.pagePadding(context).copyWith(bottom: 24),
      children: [
        TextField(
          controller: _nameCtrl,
          decoration: const InputDecoration(
            labelText: 'Nome do cargo',
            prefixIcon: Icon(Icons.badge_rounded),
            isDense: true,
          ),
          textCapitalization: TextCapitalization.words,
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _keyCtrl,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            labelText: 'Chave técnica (única)',
            prefixIcon: const Icon(Icons.key_rounded),
            isDense: true,
            helperText: widget.doc == null
                ? 'Deixe vazio para gerar a partir do nome.'
                : 'Usada em FUNÇÕES do membro.',
            helperMaxLines: 2,
          ),
        ),
        if (isLiderDep) ...[
          const SizedBox(height: 8),
          Text(
            'Líder de departamento: relatórios limitados a Eventos e Aniversariantes.',
            style: TextStyle(fontSize: 11, color: Colors.orange.shade800),
          ),
        ],
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _hierCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Nível (0–100)',
                  prefixIcon: Icon(Icons.layers_rounded),
                  isDense: true,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              flex: 2,
              child: DropdownButtonFormField<String>(
                initialValue: templateValue,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Modelo base',
                  prefixIcon: Icon(Icons.security_rounded),
                  isDense: true,
                ),
                items: templates
                    .map(
                      (t) => DropdownMenuItem(
                        value: t.key,
                        child: Text(t.label, overflow: TextOverflow.ellipsis),
                      ),
                    )
                    .toList(),
                onChanged: (v) => setState(() => _template = v ?? 'membro'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Text(
          'Acesso ao painel',
          style: GoogleFonts.manrope(
            fontSize: 13,
            fontWeight: FontWeight.w800,
            color: ThemeCleanPremium.onSurface,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          child: Column(
            children: [
              _cargoAccessTriDropdown(
                title: 'Membros',
                icon: Icons.people_alt_rounded,
                tri: _membrosTri,
                onChanged: (v) => setState(() => _membrosTri = v),
              ),
              _cargoAccessTriDropdown(
                title: 'Mural de avisos',
                icon: Icons.campaign_rounded,
                tri: _muralTri,
                onChanged: (v) => setState(() => _muralTri = v),
                label1: 'Leitura',
                label2: 'Publicar',
              ),
              _cargoAccessTriDropdown(
                title: 'Eventos (feed)',
                icon: Icons.event_rounded,
                tri: _eventosTri,
                onChanged: (v) => setState(() => _eventosTri = v),
              ),
              _cargoAccessTriDropdown(
                title: 'Agenda',
                icon: Icons.calendar_month_rounded,
                tri: _agendaTri,
                onChanged: (v) => setState(() => _agendaTri = v),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _cargoMultiSelectDropdown(
          context: context,
          label: 'Módulos adicionais',
          icon: Icons.widgets_rounded,
          options: chips,
          selected: _simpleSel,
          emptyLabel: 'Nenhum módulo',
          onChanged: (v) => setState(() {
            _simpleSel
              ..clear()
              ..addAll(v);
          }),
        ),
        const SizedBox(height: 12),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          dense: true,
          title: const Text(
            'Pacote completo de PDFs',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
          ),
          value: _relatoriosFull && !isLiderDep,
          activeThumbColor: Colors.white,
          activeTrackColor: primary,
          onChanged: isLiderDep
              ? null
              : (v) => setState(() {
                  _relatoriosFull = v;
                  if (v) _relatorioPicks.clear();
                }),
        ),
        if (!_relatoriosFull || isLiderDep)
          _cargoMultiSelectDropdown(
            context: context,
            label: 'Relatórios PDF',
            icon: Icons.picture_as_pdf_rounded,
            options: relatorioOptions,
            selected: _relatorioPicks,
            emptyLabel: 'Escolher relatórios',
            enabled: !(_relatoriosFull && !isLiderDep),
            onChanged: (v) => setState(() {
              _relatorioPicks
                ..clear()
                ..addAll(v);
            }),
          ),
        const SizedBox(height: 24),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.doc == null ? 'Novo cargo' : 'Editar cargo';
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: ThemeCleanPremium.onSurface,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => Navigator.pop(context, false),
        ),
        title: Text(
          title,
          style: GoogleFonts.manrope(fontWeight: FontWeight.w800, fontSize: 17),
        ),
      ),
      bottomNavigationBar: Container(
        padding: EdgeInsets.fromLTRB(
          ThemeCleanPremium.pagePadding(context).left,
          12,
          ThemeCleanPremium.pagePadding(context).right,
          12,
        ),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border(top: BorderSide(color: Colors.grey.shade200)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 12,
              offset: const Offset(0, -4),
            ),
          ],
        ),
        child: SafeArea(
          top: false,
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Cancelar'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  onPressed: _save,
                  child: const Text('Salvar'),
                ),
              ),
            ],
          ),
        ),
      ),
      body: _buildFormBody(),
    );
  }
}

/// Página de membros vinculados a um cargo — remover ou alterar cargo
class _CargoMembrosPage extends StatefulWidget {
  final String tenantId;
  final String role;
  final String cargoName;
  final String cargoKey;
  final DocumentReference<Map<String, dynamic>> cargoRef;
  final bool canWrite;
  final VoidCallback onChanged;

  const _CargoMembrosPage({
    required this.tenantId,
    required this.role,
    required this.cargoName,
    required this.cargoKey,
    required this.cargoRef,
    required this.canWrite,
    required this.onChanged,
  });

  @override
  State<_CargoMembrosPage> createState() => _CargoMembrosPageState();
}

class _CargoMembrosPageState extends State<_CargoMembrosPage> {
  List<_MemberWithRef> _members = [];
  bool _loading = true;
  String? _loadError;

  final TextEditingController _memberSearchController = TextEditingController();
  Timer? _memberSearchDebounce;
  String _memberSearchQuery = '';

  String get _loadChurchId =>
      ChurchPanelTenant.forFirestore(widget.tenantId.trim());

  void _onMemberSearchChanged() {
    _memberSearchDebounce?.cancel();
    _memberSearchDebounce = Timer(const Duration(milliseconds: 250), () {
      if (!mounted) return;
      final q = _memberSearchController.text.trim().toLowerCase();
      if (_memberSearchQuery != q) setState(() => _memberSearchQuery = q);
    });
  }

  @override
  void initState() {
    super.initState();
    _memberSearchController.addListener(_onMemberSearchChanged);
    unawaited(_loadMembers());
  }

  @override
  void dispose() {
    _memberSearchDebounce?.cancel();
    _memberSearchController.removeListener(_onMemberSearchChanged);
    _memberSearchController.dispose();
    super.dispose();
  }

  _MemberWithRef _rowToMember(ChurchCargoMemberRow row) =>
      _MemberWithRef(id: row.id, data: row.data, ref: row.ref);

  Future<void> _loadMembers({bool forceRefresh = false}) async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final result = await ChurchCargoMembersLoadService.loadLinked(
        seedTenantId: _loadChurchId,
        cargoKey: widget.cargoKey,
        cargoName: widget.cargoName,
        forceRefresh: forceRefresh,
      );
      if (!mounted) return;
      setState(() {
        _members = result.members.map(_rowToMember).toList();
        _loadError = result.members.isEmpty ? result.softError : null;
      });
    } catch (e) {
      if (mounted) {
        setState(() => _loadError = e.toString());
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  static String _nome(Map<String, dynamic> d) =>
      (d['NOME_COMPLETO'] ?? d['nome'] ?? d['name'] ?? 'Membro')
          .toString()
          .trim();

  static String? _emailOf(Map<String, dynamic> d) {
    final e = (d['EMAIL'] ?? d['email'] ?? '').toString().trim();
    return e.isEmpty ? null : e;
  }

  static bool _memberMatchesQuery(String q, _MemberWithRef m) {
    if (q.isEmpty) return true;
    final d = m.data;
    final nome = _nome(d).toLowerCase();
    final idLow = m.id.toLowerCase();
    final email = (_emailOf(d) ?? '').toLowerCase();
    final cpf = (d['CPF'] ?? d['cpf'] ?? '').toString().replaceAll(
      RegExp(r'\D'),
      '',
    );
    final phone = (d['TELEFONES'] ?? d['telefone'] ?? d['TELEFONE'] ?? '')
        .toString()
        .replaceAll(RegExp(r'\D'), '');
    final qDigits = q.replaceAll(RegExp(r'\D'), '');
    final textMatch =
        nome.contains(q) || idLow.contains(q) || email.contains(q);
    final cpfMatch = qDigits.length >= 3 && cpf.contains(qDigits);
    final phoneMatch = qDigits.length >= 4 && phone.contains(qDigits);
    return textMatch || cpfMatch || phoneMatch;
  }

  List<_MemberWithRef> get _filteredMembers {
    final q = _memberSearchQuery;
    if (q.isEmpty) return _members;
    return _members.where((m) => _memberMatchesQuery(q, m)).toList();
  }

  bool _memberHasCargo(Map<String, dynamic> d) =>
      ChurchCargoMembersLoadService.memberMatchesCargo(
        d,
        cargoKey: widget.cargoKey,
        cargoName: widget.cargoName,
      );

  Future<List<_MemberWithRef>> _fetchAllMembersForPicker() async {
    final result = await ChurchCargoMembersLoadService.loadAllForPicker(
      seedTenantId: _loadChurchId,
    );
    return result.members.map(_rowToMember).toList();
  }

  Future<void> _linkMemberToCargo(_MemberWithRef m) async {
    if (!_canWrite) return;
    final churchId = ChurchPanelTenant.forFirestore(widget.tenantId);
    if (churchId.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Igreja não identificada.')),
        );
      }
      return;
    }
    final cargoKey = widget.cargoKey.trim();
    if (cargoKey.isEmpty) return;

    final funcoesRaw = m.data['FUNCOES'] ?? m.data['funcoes'];
    var funcoes = funcoesRaw is List
        ? funcoesRaw
              .map((e) => (e ?? '').toString().trim())
              .where((s) => s.isNotEmpty)
              .toList()
        : <String>[];
    if (ChurchCargoMembersLoadService.memberMatchesCargo(
      m.data,
      cargoKey: cargoKey,
      cargoName: widget.cargoName,
    )) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Este membro já possui este cargo.')),
        );
      }
      return;
    }
    funcoes = [...funcoes, cargoKey];

    final updates = <String, dynamic>{'FUNCOES': funcoes};
    final hadEmptyPrimary = _memberPrimaryCargoKey(m.data).isEmpty;
    if (hadEmptyPrimary && funcoes.isNotEmpty) {
      final primary = funcoes.first;
      updates.addAll(
        await _memberRolePatchForFuncao(
          tenantId: widget.tenantId,
          funcaoFinal: primary,
          funcoes: funcoes,
        ),
      );
    }

    try {
      await _writeMembroDocMergeResilient(
        churchId: churchId,
        memberDocId: m.id,
        updates: updates,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Erro ao vincular membro: $e')));
      }
      return;
    }

    List<String> extraMods = [];
    try {
      final c = await widget.cargoRef.get();
      extraMods = AppPermissions.normalizePermissions(
        c.data()?['modulePermissions'],
      );
    } catch (_) {}

    final authUid = (m.data['authUid'] ?? '').toString().trim();
    if (authUid.isNotEmpty) {
      try {
        final uref = firebaseDefaultFirestore.collection('users').doc(authUid);
        final userPatch = <String, dynamic>{'FUNCOES': funcoes};
        if (hadEmptyPrimary && funcoes.isNotEmpty) {
          final rolePatch = await _memberRolePatchForFuncao(
            tenantId: widget.tenantId,
            funcaoFinal: funcoes.first,
            funcoes: funcoes,
          );
          userPatch['role'] = rolePatch['role'];
          userPatch['funcao'] = rolePatch['FUNCAO'];
          userPatch['cargo'] = rolePatch['CARGO'];
          userPatch['FUNCAO'] = rolePatch['FUNCAO'];
          userPatch['FUNCAO_PERMISSOES'] = rolePatch['FUNCAO_PERMISSOES'];
        }
        if (extraMods.isNotEmpty) {
          final us = await uref.get();
          final cur = AppPermissions.normalizePermissions(
            us.data()?['permissions'],
          );
          userPatch['permissions'] = {...cur, ...extraMods}.toList();
        }
        await _writeUsersDocMergeResilient(authUid: authUid, patch: userPatch);
      } catch (_) {}
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Membro vinculado ao cargo.',
            style: TextStyle(color: Colors.white),
          ),
          backgroundColor: Colors.green,
        ),
      );
      widget.onChanged();
      unawaited(_loadMembers(forceRefresh: true));
    }
  }

  Future<void> _pickAndLinkMember() async {
    if (!_canWrite) return;
    try {
      final all = await _fetchAllMembersForPicker();
      final candidates = all.where((m) => !_memberHasCargo(m.data)).toList();
      if (!mounted) return;
      if (candidates.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Todos os membros já têm este cargo ou não há membros cadastrados.',
            ),
          ),
        );
        return;
      }
      final chosen = await showModalBottomSheet<_MemberWithRef>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        builder: (ctx) => _PickMemberForCargoBottomSheet(
          cargoLabel: widget.cargoName,
          candidates: candidates,
        ),
      );
      if (chosen == null || !mounted) return;
      await _linkMemberToCargo(chosen);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Erro: $e')));
      }
    }
  }

  Future<void> _removeCargo(_MemberWithRef m) async {
    if (!widget.canWrite) return;
    final name = _nome(m.data);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusLg),
        ),
        title: const Text('Remover cargo'),
        content: Text('Remover o cargo "${widget.cargoName}" de "$name"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Remover'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final churchId = ChurchPanelTenant.forFirestore(widget.tenantId);
    if (churchId.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Igreja não identificada.')),
        );
      }
      return;
    }
    try {
      final funcoesRaw = m.data['FUNCOES'] ?? m.data['funcoes'];
      List<String> funcoes = funcoesRaw is List
          ? funcoesRaw
                .map((e) => (e ?? '').toString().trim())
                .where((s) => s.isNotEmpty)
                .toList()
          : [];
      funcoes.removeWhere((f) {
        final s = f.trim();
        if (s.isEmpty) return false;
        return ChurchCargoMembersLoadService.memberMatchesCargo(
          {
            'FUNCOES': [s],
            'FUNCAO': s,
            'CARGO': s,
          },
          cargoKey: widget.cargoKey,
          cargoName: widget.cargoName,
        );
      });
      if (funcoes.isEmpty &&
          ChurchCargoMembersLoadService.memberMatchesCargo(
            m.data,
            cargoKey: widget.cargoKey,
            cargoName: widget.cargoName,
          )) {
        funcoes = ['membro'];
      }
      if (funcoes.isEmpty) funcoes = ['membro'];
      final funcaoFinal = funcoes.first;
      final updates = await _memberRolePatchForFuncao(
        tenantId: widget.tenantId,
        funcaoFinal: funcaoFinal,
        funcoes: funcoes,
      );
      await _writeMembroDocMergeResilient(
        churchId: churchId,
        memberDocId: m.id,
        updates: updates,
      );
      final authUid = (m.data['authUid'] ?? '').toString().trim();
      if (authUid.isNotEmpty) {
        try {
          await _writeUsersDocMergeResilient(
            authUid: authUid,
            patch: {
              'role': updates['role'],
              'funcao': updates['FUNCAO'],
              'cargo': updates['CARGO'],
              'FUNCAO': updates['FUNCAO'],
              'FUNCAO_PERMISSOES': updates['FUNCAO_PERMISSOES'],
              'FUNCOES': funcoes,
              'CARGO': updates['CARGO'],
            },
          );
        } catch (_) {}
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Cargo removido.',
              style: TextStyle(color: Colors.white),
            ),
            backgroundColor: Colors.green,
          ),
        );
        unawaited(_loadMembers(forceRefresh: true));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Erro: $e')));
      }
    }
  }

  Future<void> _changeCargo(_MemberWithRef m) async {
    if (!_canWrite) return;
    final cargosSnap = await IgrejaDirectFirestoreReads.listSubcollection(
      _loadChurchId,
      'cargos',
      moduleLabel: 'Cargos',
      limit: 120,
    );
    final cargos = cargosSnap.docs
        .map(
          (d) => (
            key: (d.data()['key'] ?? d.id).toString(),
            name: (d.data()['name'] ?? d.id).toString(),
          ),
        )
        .where((c) => c.key != widget.cargoKey)
        .toList();
    if (!mounted) return;
    if (cargos.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Não há outros cargos para alterar.')),
      );
      return;
    }
    String? selectedKey;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusLg),
          ),
          title: Text('Alterar cargo de ${_nome(m.data)}'),
          content: SizedBox(
            width: 320,
            child: RadioGroup<String>(
              groupValue: selectedKey,
              onChanged: (v) {
                selectedKey = v;
                setDlg(() {});
              },
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Selecione o novo cargo:',
                    style: TextStyle(fontSize: 14, color: Colors.grey.shade700),
                  ),
                  const SizedBox(height: 12),
                  ...cargos.map(
                    (c) => RadioListTile<String>(
                      title: Text(c.name),
                      value: c.key,
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: selectedKey != null
                  ? () => Navigator.pop(ctx, true)
                  : null,
              child: const Text('Alterar'),
            ),
          ],
        ),
      ),
    );
    if (ok != true || selectedKey == null || !mounted) return;
    final churchId = ChurchPanelTenant.forFirestore(widget.tenantId);
    if (churchId.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Igreja não identificada.')),
        );
      }
      return;
    }
    try {
      final funcoesRaw = m.data['FUNCOES'] ?? m.data['funcoes'];
      List<String> funcoes = funcoesRaw is List
          ? funcoesRaw
                .map((e) => (e ?? '').toString().trim())
                .where((s) => s.isNotEmpty)
                .toList()
          : [];
      funcoes.removeWhere((f) {
        final s = f.trim();
        if (s.isEmpty) return false;
        return ChurchCargoMembersLoadService.memberMatchesCargo(
          {
            'FUNCOES': [s],
            'FUNCAO': s,
            'CARGO': s,
          },
          cargoKey: widget.cargoKey,
          cargoName: widget.cargoName,
        );
      });
      funcoes.add(selectedKey!);
      final funcaoFinal = selectedKey!;
      final updates = await _memberRolePatchForFuncao(
        tenantId: widget.tenantId,
        funcaoFinal: funcaoFinal,
        funcoes: funcoes,
      );
      await _writeMembroDocMergeResilient(
        churchId: churchId,
        memberDocId: m.id,
        updates: updates,
      );
      final authUid = (m.data['authUid'] ?? '').toString().trim();
      if (authUid.isNotEmpty) {
        try {
          await _writeUsersDocMergeResilient(
            authUid: authUid,
            patch: {
              'role': updates['role'],
              'funcao': updates['FUNCAO'],
              'cargo': updates['CARGO'],
              'FUNCAO': updates['FUNCAO'],
              'FUNCAO_PERMISSOES': updates['FUNCAO_PERMISSOES'],
              'FUNCOES': funcoes,
              'CARGO': updates['CARGO'],
            },
          );
        } catch (_) {}
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Cargo alterado.',
              style: TextStyle(color: Colors.white),
            ),
            backgroundColor: Colors.green,
          ),
        );
        unawaited(_loadMembers(forceRefresh: true));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Erro: $e')));
      }
    }
  }

  bool get _canWrite => widget.canWrite;

  Widget _buildMemberSearchBar({required EdgeInsets padding}) {
    return Padding(
      padding: EdgeInsets.fromLTRB(padding.left, 12, padding.right, 0),
      child: TextField(
        controller: _memberSearchController,
        textInputAction: TextInputAction.search,
        decoration: InputDecoration(
          hintText: 'Buscar membro por nome, CPF, telefone ou e-mail...',
          prefixIcon: const Icon(Icons.search_rounded, size: 22),
          suffixIcon: ValueListenableBuilder<TextEditingValue>(
            valueListenable: _memberSearchController,
            builder: (context, value, child) {
              if (value.text.isEmpty) return const SizedBox.shrink();
              return IconButton(
                icon: const Icon(Icons.close_rounded, size: 20),
                tooltip: 'Limpar busca',
                onPressed: () {
                  _memberSearchController.clear();
                  if (_memberSearchQuery.isNotEmpty) {
                    setState(() => _memberSearchQuery = '');
                  }
                },
              );
            },
          ),
          filled: true,
          fillColor: Colors.white,
          contentPadding: const EdgeInsets.symmetric(vertical: 12),
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
            borderSide: BorderSide(color: ThemeCleanPremium.primary, width: 2),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final padding = ThemeCleanPremium.pagePadding(context);
    return Scaffold(
      backgroundColor: const Color(0xFFF4F7FB),
      appBar: AppBar(
        backgroundColor: YahwehWisdomVisualKit.tealAccent,
        foregroundColor: Colors.white,
        elevation: 0,
        flexibleSpace: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                YahwehWisdomVisualKit.tealAccent,
                ThemeCleanPremium.primary,
              ],
            ),
          ),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.cargoName,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
            ),
            Text(
              '${_members.length} membro${_members.length != 1 ? 's' : ''} vinculado${_members.length != 1 ? 's' : ''}',
              style: TextStyle(
                fontSize: 12,
                color: Colors.white.withValues(alpha: 0.9),
              ),
            ),
          ],
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => Navigator.pop(context),
          tooltip: 'Voltar',
          style: IconButton.styleFrom(
            minimumSize: const Size(
              ThemeCleanPremium.minTouchTarget,
              ThemeCleanPremium.minTouchTarget,
            ),
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: () => _loadMembers(forceRefresh: true),
            tooltip: 'Atualizar',
            style: IconButton.styleFrom(
              minimumSize: const Size(
                ThemeCleanPremium.minTouchTarget,
                ThemeCleanPremium.minTouchTarget,
              ),
            ),
          ),
        ],
      ),
      floatingActionButton: _canWrite
          ? FloatingActionButton.extended(
              onPressed: _pickAndLinkMember,
              backgroundColor: ThemeCleanPremium.primary,
              foregroundColor: Colors.white,
              icon: const Icon(Icons.person_add_alt_1_rounded),
              label: const Text(
                'Vincular membro',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
            )
          : null,
      body: _loading
          ? const ChurchPanelLoadingBody(itemCount: 5)
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_loadError != null && _loadError!.trim().isNotEmpty)
                  Padding(
                    padding: EdgeInsets.fromLTRB(
                      padding.left,
                      8,
                      padding.right,
                      0,
                    ),
                    child: ChurchPanelResilientLoadBanner(
                      hasLocalData: _members.isNotEmpty,
                      isSyncing: false,
                      showStaleCache: _members.isNotEmpty,
                      errorTitle: 'Não foi possível carregar todos os membros',
                      error: _loadError,
                      onRetry: () => _loadMembers(forceRefresh: true),
                    ),
                  ),
                _buildMemberSearchBar(padding: padding),
                Expanded(
                  child: _filteredMembers.isEmpty
                      ? ChurchWisdomModuleEmptyState(
                          icon: Icons.people_outline_rounded,
                          title: _memberSearchQuery.isNotEmpty
                              ? 'Nenhum membro encontrado'
                              : 'Nenhum membro com este cargo',
                          message: _memberSearchQuery.isNotEmpty
                              ? 'Nenhum resultado para "$_memberSearchQuery". Ajuste o termo ou limpe a busca.'
                              : 'Use o botão Vincular membro ou o cadastro em Membros.',
                          actionLabel: _canWrite && _memberSearchQuery.isEmpty
                              ? 'Vincular membro'
                              : null,
                          onAction: _canWrite && _memberSearchQuery.isEmpty
                              ? _pickAndLinkMember
                              : null,
                          accent: YahwehWisdomVisualKit.tealAccent,
                        )
                      : RefreshIndicator(
                          onRefresh: () => _loadMembers(forceRefresh: true),
                          color: ThemeCleanPremium.primary,
                          child: AnimationLimiter(
                            child: ListView.builder(
                              padding: EdgeInsets.fromLTRB(
                                padding.left,
                                16,
                                padding.right,
                                padding.bottom + 24,
                              ),
                              itemCount: _filteredMembers.length,
                              itemBuilder: (_, i) {
                                final m = _filteredMembers[i];
                                final tidPhoto =
                                    _tenantIdFromMembroDocRef(m.ref) ??
                                    widget.tenantId;
                                final cpfRaw =
                                    (m.data['CPF'] ?? m.data['cpf'] ?? '')
                                        .toString();
                                final cpfD = cpfRaw.replaceAll(
                                  RegExp(r'\D'),
                                  '',
                                );
                                final au = (m.data['authUid'] ?? '')
                                    .toString()
                                    .trim();
                                final memberCard = Container(
                                  margin: const EdgeInsets.only(bottom: 10),
                                  decoration: BoxDecoration(
                                    color: ThemeCleanPremium.cardBackground,
                                    borderRadius: BorderRadius.circular(
                                      ThemeCleanPremium.radiusMd,
                                    ),
                                    boxShadow:
                                        ThemeCleanPremium.softUiCardShadow,
                                    border: Border.all(
                                      color: const Color(0xFFE2E8F0),
                                    ),
                                  ),
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(
                                      ThemeCleanPremium.radiusMd,
                                    ),
                                    child: IntrinsicHeight(
                                      child: Row(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.stretch,
                                        children: [
                                          Container(
                                            width: 4,
                                            decoration: const BoxDecoration(
                                              color: _kCargoListGoldAccent,
                                            ),
                                          ),
                                          Expanded(
                                            child: Material(
                                              color: Colors.transparent,
                                              child: InkWell(
                                                onTap: () => Navigator.push(
                                                  context,
                                                  MaterialPageRoute(
                                                    builder: (_) => MembersPage(
                                                      tenantId: widget.tenantId,
                                                      role: widget.role,
                                                      initialOpenMemberDocId:
                                                          m.id,
                                                    ),
                                                  ),
                                                ),
                                                borderRadius:
                                                    BorderRadius.circular(
                                                      ThemeCleanPremium
                                                          .radiusMd,
                                                    ),
                                                child: Padding(
                                                  padding:
                                                      const EdgeInsets.symmetric(
                                                        horizontal: 16,
                                                        vertical: 14,
                                                      ),
                                                  child: Row(
                                                    children: [
                                                      FotoMembroWidget(
                                                        imageUrl: null,
                                                        size: 52,
                                                        tenantId: tidPhoto,
                                                        memberId: m.id,
                                                        cpfDigits:
                                                            cpfD.length == 11
                                                            ? cpfD
                                                            : null,
                                                        authUid: au.isNotEmpty
                                                            ? au
                                                            : null,
                                                        memberData: m.data,
                                                        backgroundColor:
                                                            ThemeCleanPremium
                                                                .primary
                                                                .withValues(
                                                                  alpha: 0.12,
                                                                ),
                                                      ),
                                                      const SizedBox(width: 14),
                                                      Expanded(
                                                        child: Column(
                                                          crossAxisAlignment:
                                                              CrossAxisAlignment
                                                                  .start,
                                                          children: [
                                                            Text(
                                                              _nome(m.data),
                                                              style: TextStyle(
                                                                fontSize: 15,
                                                                fontWeight:
                                                                    FontWeight
                                                                        .w800,
                                                                letterSpacing:
                                                                    -0.2,
                                                                color: ThemeCleanPremium
                                                                    .onSurface,
                                                              ),
                                                            ),
                                                            Text(
                                                              (m.data['EMAIL'] ??
                                                                      m.data['email'] ??
                                                                      '')
                                                                  .toString(),
                                                              style: TextStyle(
                                                                fontSize: 12,
                                                                color: ThemeCleanPremium
                                                                    .onSurfaceVariant,
                                                              ),
                                                              overflow:
                                                                  TextOverflow
                                                                      .ellipsis,
                                                            ),
                                                          ],
                                                        ),
                                                      ),
                                                      if (_canWrite)
                                                        PopupMenuButton<String>(
                                                          icon: Icon(
                                                            Icons
                                                                .more_vert_rounded,
                                                            color: Colors
                                                                .grey
                                                                .shade600,
                                                          ),
                                                          shape: RoundedRectangleBorder(
                                                            borderRadius:
                                                                BorderRadius.circular(
                                                                  ThemeCleanPremium
                                                                      .radiusSm,
                                                                ),
                                                          ),
                                                          onSelected: (v) {
                                                            if (v == 'remove') {
                                                              _removeCargo(m);
                                                            }
                                                            if (v == 'change') {
                                                              _changeCargo(m);
                                                            }
                                                            if (v == 'edit') {
                                                              Navigator.push(
                                                                context,
                                                                MaterialPageRoute(
                                                                  builder: (_) => MembersPage(
                                                                    tenantId: widget
                                                                        .tenantId,
                                                                    role: widget
                                                                        .role,
                                                                  ),
                                                                ),
                                                              );
                                                            }
                                                          },
                                                          itemBuilder: (_) => [
                                                            const PopupMenuItem(
                                                              value: 'change',
                                                              child: Row(
                                                                children: [
                                                                  Icon(
                                                                    Icons
                                                                        .swap_horiz_rounded,
                                                                    size: 20,
                                                                  ),
                                                                  SizedBox(
                                                                    width: 10,
                                                                  ),
                                                                  Text(
                                                                    'Alterar cargo',
                                                                  ),
                                                                ],
                                                              ),
                                                            ),
                                                            const PopupMenuItem(
                                                              value: 'remove',
                                                              child: Row(
                                                                children: [
                                                                  Icon(
                                                                    Icons
                                                                        .person_remove_rounded,
                                                                    size: 20,
                                                                    color: Color(
                                                                      0xFFDC2626,
                                                                    ),
                                                                  ),
                                                                  SizedBox(
                                                                    width: 10,
                                                                  ),
                                                                  Text(
                                                                    'Remover cargo',
                                                                    style: TextStyle(
                                                                      color: Color(
                                                                        0xFFDC2626,
                                                                      ),
                                                                    ),
                                                                  ),
                                                                ],
                                                              ),
                                                            ),
                                                            const PopupMenuItem(
                                                              value: 'edit',
                                                              child: Row(
                                                                children: [
                                                                  Icon(
                                                                    Icons
                                                                        .edit_rounded,
                                                                    size: 20,
                                                                  ),
                                                                  SizedBox(
                                                                    width: 10,
                                                                  ),
                                                                  Text(
                                                                    'Editar membro',
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
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                );
                                if (kIsWeb) return memberCard;
                                return AnimationConfiguration.staggeredList(
                                  position: i,
                                  duration: const Duration(milliseconds: 300),
                                  delay: Duration(milliseconds: (i % 14) * 30),
                                  child: SlideAnimation(
                                    verticalOffset: 16,
                                    child: FadeInAnimation(child: memberCard),
                                  ),
                                );
                              },
                            ),
                          ),
                        ),
                ),
              ],
            ),
    );
  }
}

class _PickMemberForCargoBottomSheet extends StatefulWidget {
  final String cargoLabel;
  final List<_MemberWithRef> candidates;

  const _PickMemberForCargoBottomSheet({
    required this.cargoLabel,
    required this.candidates,
  });

  @override
  State<_PickMemberForCargoBottomSheet> createState() =>
      _PickMemberForCargoBottomSheetState();
}

class _PickMemberForCargoBottomSheetState
    extends State<_PickMemberForCargoBottomSheet> {
  final TextEditingController _q = TextEditingController();

  void _onQueryChanged() {
    if (mounted) setState(() {});
  }

  @override
  void initState() {
    super.initState();
    // Na web, só [onChanged] + [StatefulBuilder] interno às vezes não reconstrói a lista.
    _q.addListener(_onQueryChanged);
  }

  @override
  void dispose() {
    _q.removeListener(_onQueryChanged);
    _q.dispose();
    super.dispose();
  }

  static String _nome(Map<String, dynamic> d) =>
      (d['NOME_COMPLETO'] ?? d['nome'] ?? d['name'] ?? 'Membro')
          .toString()
          .trim();

  static String? _email(Map<String, dynamic> d) {
    final e = (d['EMAIL'] ?? d['email'] ?? '').toString().trim();
    return e.isEmpty ? null : e;
  }

  /// Todos os campos que podem carregar e-mail (Firestore varia por migração / login).
  static List<String> _emailCandidatesLower(Map<String, dynamic> d) {
    final keys = <String>[
      'EMAIL',
      'email',
      'emailLogin',
      'loginEmail',
      'corporateEmail',
      'EMAIL_CORPORATIVO',
      'usuario',
      'login',
    ];
    final out = <String>[];
    for (final k in keys) {
      final v = (d[k] ?? '').toString().trim().toLowerCase();
      if (v.isNotEmpty && v.contains('@')) out.add(v);
    }
    return out;
  }

  /// Evita `cpf.contains('')` — em Dart isso é sempre true e quebrava o filtro por nome.
  static bool _matchesQuery(String qqLower, _MemberWithRef m) {
    if (qqLower.isEmpty) return true;
    final d = m.data;
    final nome = _nome(d).toLowerCase();
    final idLow = m.id.toLowerCase();
    final cpfDigits = (d['CPF'] ?? d['cpf'] ?? '').toString().replaceAll(
      RegExp(r'\D'),
      '',
    );
    final phoneDigits = (d['TELEFONES'] ?? d['telefone'] ?? d['TELEFONE'] ?? '')
        .toString()
        .replaceAll(RegExp(r'\D'), '');
    final qDigits = qqLower.replaceAll(RegExp(r'\D'), '');
    final emails = _emailCandidatesLower(d);
    final matchText =
        nome.contains(qqLower) ||
        idLow.contains(qqLower) ||
        emails.any((e) => e.contains(qqLower));
    final matchCpf = qDigits.length >= 3 && cpfDigits.contains(qDigits);
    final matchPhone = qDigits.length >= 4 && phoneDigits.contains(qDigits);
    return matchText || matchCpf || matchPhone;
  }

  @override
  Widget build(BuildContext context) {
    final pad = MediaQuery.paddingOf(context);
    final inset = MediaQuery.viewInsetsOf(context);
    final primary = ThemeCleanPremium.primary;
    final qq = _q.text.trim().toLowerCase();
    final filtered = qq.isEmpty
        ? widget.candidates
        : widget.candidates.where((m) => _matchesQuery(qq, m)).toList();

    return Padding(
      padding: EdgeInsets.only(bottom: inset.bottom),
      child: DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.68,
        minChildSize: 0.38,
        maxChildSize: 0.94,
        builder: (ctx, scrollCtrl) {
          return DecoratedBox(
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              boxShadow: [
                BoxShadow(
                  color: Color(0x180F172A),
                  blurRadius: 24,
                  offset: Offset(0, -4),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: EdgeInsets.fromLTRB(20, 12 + pad.top * 0.25, 20, 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
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
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: primary.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: primary.withValues(alpha: 0.35),
                                width: 1.5,
                              ),
                            ),
                            child: Icon(
                              Icons.person_add_alt_1_rounded,
                              color: primary,
                              size: 22,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Vincular membro',
                                  style: GoogleFonts.poppins(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: const Color(0xFF64748B),
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  widget.cargoLabel,
                                  style: GoogleFonts.poppins(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w800,
                                    color: const Color(0xFF0F172A),
                                    height: 1.2,
                                  ),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Container(
                        decoration: BoxDecoration(
                          color: const Color(0xFFF8FAFC),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: const Color(0xFF64748B),
                            width: 1.5,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.05),
                              blurRadius: 12,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: TextField(
                          controller: _q,
                          textInputAction: TextInputAction.search,
                          style: GoogleFonts.inter(
                            fontSize: 15,
                            fontWeight: FontWeight.w500,
                          ),
                          decoration: InputDecoration(
                            hintText:
                                'Nome, e-mail, telefone, CPF ou ID do documento',
                            hintStyle: TextStyle(
                              color: Colors.grey.shade500,
                              fontSize: 14,
                            ),
                            prefixIcon: Icon(
                              Icons.search_rounded,
                              color: primary,
                            ),
                            border: InputBorder.none,
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 14,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: filtered.isEmpty
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.search_off_rounded,
                                  size: 48,
                                  color: Colors.grey.shade400,
                                ),
                                const SizedBox(height: 12),
                                Text(
                                  'Nenhum membro encontrado',
                                  textAlign: TextAlign.center,
                                  style: GoogleFonts.poppins(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w700,
                                    color: const Color(0xFF475569),
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  'Ajuste o termo ou limpe a busca.',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: Colors.grey.shade600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        )
                      : ListView.separated(
                          controller: scrollCtrl,
                          physics: const BouncingScrollPhysics(),
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 28),
                          itemCount: filtered.length,
                          separatorBuilder: (_, _) =>
                              const SizedBox(height: 10),
                          itemBuilder: (_, i) {
                            final m = filtered[i];
                            final tid = _tenantIdFromMembroDocRef(m.ref) ?? '';
                            final cpfRaw =
                                (m.data['CPF'] ?? m.data['cpf'] ?? '')
                                    .toString();
                            final cpfD = cpfRaw.replaceAll(RegExp(r'\D'), '');
                            final au = (m.data['authUid'] ?? '')
                                .toString()
                                .trim();
                            return Material(
                              color: Colors.white,
                              elevation: 0,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                                side: const BorderSide(
                                  color: Color(0xFFCBD5E1),
                                  width: 1.5,
                                ),
                              ),
                              shadowColor: Colors.black.withValues(alpha: 0.08),
                              child: InkWell(
                                onTap: () => Navigator.pop(context, m),
                                borderRadius: BorderRadius.circular(14),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 10,
                                  ),
                                  child: Row(
                                    children: [
                                      FotoMembroWidget(
                                        imageUrl: null,
                                        size: 48,
                                        tenantId: tid.isNotEmpty ? tid : null,
                                        memberId: m.id,
                                        cpfDigits: cpfD.length == 11
                                            ? cpfD
                                            : null,
                                        authUid: au.isNotEmpty ? au : null,
                                        memberData: m.data,
                                        backgroundColor: primary.withValues(
                                          alpha: 0.12,
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              _nome(m.data),
                                              style: GoogleFonts.poppins(
                                                fontSize: 15,
                                                fontWeight: FontWeight.w800,
                                                color: const Color(0xFF0F172A),
                                              ),
                                              maxLines: 2,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                            const SizedBox(height: 4),
                                            Text(
                                              _email(m.data) ??
                                                  (cpfRaw.isNotEmpty
                                                      ? cpfRaw
                                                      : m.id),
                                              style: GoogleFonts.inter(
                                                fontSize: 13,
                                                color: const Color(0xFF64748B),
                                                fontWeight: FontWeight.w500,
                                              ),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ],
                                        ),
                                      ),
                                      Icon(
                                        Icons.chevron_right_rounded,
                                        color: Colors.grey.shade400,
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _MemberWithRef {
  final String id;
  final Map<String, dynamic> data;
  final DocumentReference<Map<String, dynamic>> ref;
  _MemberWithRef({required this.id, required this.data, required this.ref});
}
