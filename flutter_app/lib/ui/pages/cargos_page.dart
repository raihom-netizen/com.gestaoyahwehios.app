import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:gestao_yahweh/services/app_permissions.dart';
import 'package:gestao_yahweh/services/church_funcoes_controle_service.dart';
import 'package:gestao_yahweh/services/church_tenant_resilient_reads.dart';
import 'package:gestao_yahweh/services/firestore_stream_utils.dart';
import 'package:gestao_yahweh/services/tenant_resolver_service.dart';
import 'package:gestao_yahweh/ui/pages/lideranca_page.dart';
import 'package:gestao_yahweh/ui/theme_clean_premium.dart';
import 'package:gestao_yahweh/ui/widgets/church_panel_ui_helpers.dart';
import 'package:gestao_yahweh/ui/widgets/foto_membro_widget.dart';
import 'package:gestao_yahweh/utils/firestore_read_resilience.dart';
import 'members_page.dart' show MembersPage;

/// Mesma faixa dourada dos cards em [DepartmentsPage] — identidade visual alinhada.
const Color _kCargoListGoldAccent = Color(0xFFF5C518);

/// Cache curto para evitar novo scan completo em `igrejas` a cada abertura da lista de membros do cargo.
final Map<String, ({DateTime at, List<String> ids})> _cargoMergeTenantIdsCache = {};
const Duration _kCargoMergeIdsTtl = Duration(minutes: 5);

/// `igrejas/{tenantId}/membros/...`
String? _tenantIdFromMembroDocRef(DocumentReference<Map<String, dynamic>> ref) {
  final p = ref.path.split('/');
  if (p.length >= 2 && p[0] == 'igrejas') return p[1];
  return null;
}

Future<List<String>> _cargoMemberMergeTenantIds(String seed) async {
  final now = DateTime.now();
  final cached = _cargoMergeTenantIdsCache[seed];
  if (cached != null && now.difference(cached.at) < _kCargoMergeIdsTtl) {
    return cached.ids;
  }
  var ids = await TenantResolverService.getAllTenantIdsWithSameSlugOrAlias(seed);
  if (ids.isEmpty) ids = [seed];
  _cargoMergeTenantIdsCache[seed] = (at: now, ids: List<String>.from(ids));
  return ids;
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

/// Cache RAM — lista de cargos instantânea ao reabrir o módulo.
abstract final class _CargosRamCache {
  _CargosRamCache._();

  static final Map<
      String,
      ({
        List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
        DateTime at,
      })> _byTenant = {};

  static const Duration _ttl = Duration(minutes: 20);

  static List<QueryDocumentSnapshot<Map<String, dynamic>>>? peek(String tenantId) {
    final key = tenantId.trim();
    if (key.isEmpty) return null;
    final hit = _byTenant[key];
    if (hit == null) return null;
    if (DateTime.now().difference(hit.at) > _ttl) {
      _byTenant.remove(key);
      return null;
    }
    return hit.docs;
  }

  static void put(
    String tenantId,
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) {
    final key = tenantId.trim();
    if (key.isEmpty || docs.isEmpty) return;
    _byTenant[key] = (docs: List.from(docs), at: DateTime.now());
  }
}

class _CargosPageState extends State<CargosPage> {
  String? _resolvedTenantId;
  late Future<QuerySnapshot<Map<String, dynamic>>> _cargosFuture;
  /// Evita loop ao criar cargos padrão automaticamente.
  bool _triedAutoSeed = false;

  /// Módulos “binários” (um chip) — [Membros], [Mural], [Eventos/Feed], [Agenda] e [Relatórios] têm secções dedicadas.
  static const List<(String key, String label)> _kCargoSimpleChips = [
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
    if (m.contains('eventos_avisos_edicao') || m.contains('eventos')) {
      return 2;
    }
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

  /// Monta a lista persistida em `modulePermissions` / fundida em `users.permissions`.
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

  /// Secção “Super Premium”: níveis Padrão / Ver / Editar para cargos.
  static Widget _cargoAccessTriTile({
    required String title,
    required String hint,
    required IconData icon,
    required int tri,
    required ValueChanged<int> onChanged,
    String label0 = 'Padrão',
    String label1 = 'Só ver',
    String label2 = 'Editar',
  }) {
    final primary = ThemeCleanPremium.primary;
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.white,
            Color.lerp(primary, Colors.white, 0.92)!,
          ],
        ),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: ThemeCleanPremium.softUiCardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(icon, size: 20, color: primary),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 14,
                    letterSpacing: -0.2,
                  ),
                ),
              ),
            ],
          ),
          if (hint.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              hint,
              style: TextStyle(fontSize: 11.5, height: 1.35, color: Colors.grey.shade600),
            ),
          ],
          const SizedBox(height: 10),
          SegmentedButton<int>(
            style: SegmentedButton.styleFrom(
              selectedForegroundColor: Colors.white,
              selectedBackgroundColor: primary,
              side: BorderSide(color: primary.withValues(alpha: 0.35)),
            ),
            segments: [
              ButtonSegment<int>(value: 0, label: Text(label0)),
              ButtonSegment<int>(value: 1, label: Text(label1)),
              ButtonSegment<int>(value: 2, label: Text(label2)),
            ],
            selected: {tri},
            onSelectionChanged: (s) {
              if (s.isEmpty) return;
              onChanged(s.first);
            },
          ),
        ],
      ),
    );
  }

  static IconData _iconForRelatorioPick(String id) {
    switch (id) {
      case 'eventos':
        return Icons.picture_as_pdf_rounded;
      case 'aniversariantes':
        return Icons.cake_rounded;
      case 'membros':
        return Icons.people_alt_rounded;
      case 'financeiro':
        return Icons.account_balance_wallet_rounded;
      case 'patrimonio':
        return Icons.inventory_2_rounded;
      case 'fornecedores':
        return Icons.handshake_rounded;
      default:
        return Icons.description_rounded;
    }
  }

  /// Mesmo vocabulário que [_cargoModulePermissionChip]. [FilterChip] M3 no diálogo
  /// gerava rótulos ilegíveis em alguns estados de cor.
  static Widget _cargoRelatorioPickChip({
    required String pickId,
    required String label,
    required bool selected,
    required bool enabled,
    required VoidCallback onTap,
  }) {
    final primary = ThemeCleanPremium.primary;
    Widget chip = Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(14),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: selected ? primary : Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: selected ? primary : const Color(0xFFE2E8F0),
              width: selected ? 1.5 : 1,
            ),
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: primary.withValues(alpha: 0.22),
                      blurRadius: 10,
                      offset: const Offset(0, 3),
                    ),
                  ]
                : ThemeCleanPremium.softUiCardShadow,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (selected)
                Container(
                  width: 3,
                  height: 22,
                  decoration: BoxDecoration(
                    color: _kCargoListGoldAccent,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              if (selected) const SizedBox(width: 8),
              Icon(
                _iconForRelatorioPick(pickId),
                size: 18,
                color: selected ? Colors.white : primary,
              ),
              const SizedBox(width: 8),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 200),
                child: Text(
                  label,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                    letterSpacing: -0.2,
                    color: selected ? Colors.white : ThemeCleanPremium.onSurface,
                  ),
                ),
              ),
              if (selected) ...[
                const SizedBox(width: 6),
                Icon(
                  Icons.check_circle_rounded,
                  size: 17,
                  color: Colors.white.withValues(alpha: 0.95),
                ),
              ],
            ],
          ),
        ),
      ),
    );
    if (!enabled) {
      chip = Opacity(opacity: 0.5, child: IgnorePointer(child: chip));
    }
    return chip;
  }

  static IconData _iconForCargoModule(String key) {
    switch (key) {
      case 'membros':
        return Icons.people_alt_rounded;
      case 'departamentos':
        return Icons.groups_rounded;
      case 'financeiro':
        return Icons.account_balance_wallet_rounded;
      case 'patrimonio':
        return Icons.inventory_2_rounded;
      case 'fornecedores':
        return Icons.handshake_rounded;
      case 'certificados':
        return Icons.workspace_premium_rounded;
      case 'cartas_transferencias':
        return Icons.description_rounded;
      case 'escalas':
        return Icons.event_available_rounded;
      case 'relatorios':
        return Icons.insights_rounded;
      default:
        return Icons.widgets_rounded;
    }
  }

  /// Chips com o mesmo vocabulário visual dos cards em [DepartmentsPage] (borda, sombra, faixa dourada ao ativo).
  static Widget _cargoModulePermissionChip({
    required String moduleKey,
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    final primary = ThemeCleanPremium.primary;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: selected ? primary : Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: selected ? primary : const Color(0xFFE2E8F0),
              width: selected ? 1.5 : 1,
            ),
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: primary.withValues(alpha: 0.22),
                      blurRadius: 10,
                      offset: const Offset(0, 3),
                    ),
                  ]
                : ThemeCleanPremium.softUiCardShadow,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (selected)
                Container(
                  width: 3,
                  height: 22,
                  decoration: BoxDecoration(
                    color: _kCargoListGoldAccent,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              if (selected) const SizedBox(width: 8),
              Icon(
                _iconForCargoModule(moduleKey),
                size: 18,
                color: selected ? Colors.white : primary,
              ),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                  letterSpacing: -0.2,
                  color: selected ? Colors.white : ThemeCleanPremium.onSurface,
                ),
              ),
              if (selected) ...[
                const SizedBox(width: 6),
                Icon(
                  Icons.check_circle_rounded,
                  size: 17,
                  color: Colors.white.withValues(alpha: 0.95),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

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

  CollectionReference<Map<String, dynamic>> get _col => FirebaseFirestore.instance
      .collection('igrejas')
      .doc(_tid)
      .collection('cargos');

  String get _tid {
    final r = (_resolvedTenantId ?? widget.tenantId).trim();
    return r.isEmpty ? widget.tenantId : r;
  }

  static String _cargosMemKey(String tenantId) =>
      '${tenantId.trim()}_cargos_120';

  bool get _canWrite =>
      AppPermissions.canEditAnyChurchMember(widget.role) ||
      AppPermissions.canEditDepartments(widget.role);

  Future<QuerySnapshot<Map<String, dynamic>>> _loadCargos({
    bool forceServer = false,
  }) async {
    final tid = _tid.trim();
    if (tid.isEmpty) {
      return _col.limit(1).get();
    }
    if (forceServer) {
      final snap = await FirestoreReadResilience.getQuery(
        FirebaseFirestore.instance
            .collection('igrejas')
            .doc(tid)
            .collection('cargos')
            .limit(120),
        cacheKey: _cargosMemKey(tid),
      );
      if (snap.docs.isNotEmpty) {
        _CargosRamCache.put(tid, snap.docs);
      }
      return snap;
    }
    return ChurchTenantResilientReads.cargos(tid);
  }

  Future<QuerySnapshot<Map<String, dynamic>>> _seedOrLoadCargos() {
    final seed = widget.tenantId.trim();
    if (seed.isEmpty) return _loadCargos();

    final ram = _CargosRamCache.peek(seed);
    if (ram != null && ram.isNotEmpty) {
      return Future.value(MergedFirestoreQuerySnapshot(ram));
    }

    final mem = FirestoreReadResilience.peekLastGoodQuery(_cargosMemKey(seed));
    if (mem != null && mem.docs.isNotEmpty) {
      return Future.value(mem);
    }

    return _loadCargos();
  }

  /// 1.º frame: RAM / memória; tenant operacional + rede em background.
  Future<void> _openCargosFast() async {
    final seed = widget.tenantId.trim();
    if (seed.isEmpty) return;

    try {
      final snap = await ChurchTenantResilientReads.cargos(seed).timeout(
        const Duration(milliseconds: 1800),
      );
      if (mounted && snap.docs.isNotEmpty) {
        _CargosRamCache.put(seed, snap.docs);
        setState(() {
          _cargosFuture = Future.value(snap);
        });
      }
    } catch (_) {}

    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      final op = await TenantResolverService.resolveOperationalChurchDocId(
        seed,
        userUid: uid,
      ).timeout(
        const Duration(seconds: 8),
        onTimeout: () => _resolvedTenantId ?? seed,
      );
      if (!mounted) return;
      if (op.isNotEmpty && op != (_resolvedTenantId ?? seed)) {
        setState(() => _resolvedTenantId = op);
      }
      final tid = _tid.trim();
      if (tid.isEmpty || tid == seed) {
        unawaited(_refreshCargosBackground());
        return;
      }
      final alt = await ChurchTenantResilientReads.cargos(tid).timeout(
        const Duration(seconds: 12),
      );
      if (!mounted) return;
      if (alt.docs.isNotEmpty) {
        _CargosRamCache.put(tid, alt.docs);
        setState(() {
          _cargosFuture = Future.value(alt);
        });
      }
    } catch (_) {}

    unawaited(_refreshCargosBackground());
  }

  Future<void> _refreshCargosBackground() async {
    try {
      final snap = await _loadCargos();
      if (!mounted || snap.docs.isEmpty) return;
      _CargosRamCache.put(_tid, snap.docs);
      setState(() {
        _cargosFuture = Future.value(snap);
      });
    } catch (_) {}
  }

  @override
  void initState() {
    super.initState();
    _resolvedTenantId = widget.tenantId;
    _cargosFuture = _seedOrLoadCargos();
    unawaited(_openCargosFast());
  }

  @override
  void didUpdateWidget(covariant CargosPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.tenantId != widget.tenantId) {
      _resolvedTenantId = widget.tenantId;
      _triedAutoSeed = false;
      _cargosFuture = _seedOrLoadCargos();
      unawaited(_openCargosFast());
    }
  }

  /// Cria na base os cargos padrão quando a coleção está vazia (novas igrejas).
  Future<void> _seedPadroes() async {
    try {
      final snap = await _col.limit(1).get();
      if (snap.docs.isNotEmpty) return;
      await FirebaseAuth.instance.currentUser?.getIdToken(true);
      final batch = FirebaseFirestore.instance.batch();
      for (var i = 0; i < _welcomeCargos.length; i++) {
        final row = _welcomeCargos[i];
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
          'modulePermissions': row.key == 'lider_departamento'
              ? AppPermissions.defaultDepartmentLeaderModulePermissions()
              : <String>[],
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }
      await batch.commit();
    } catch (e) {
      debugPrint('CargosPage _seedPadroes: $e');
    }
    if (mounted) {
      setState(() => _cargosFuture = _loadCargos());
    }
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
        return Color(int.parse(
            s.replaceFirst(RegExp(r'^0x', caseSensitive: false), ''),
            radix: 16));
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
    setState(() {
      _cargosFuture = _loadCargos(forceServer: forceServer);
    });
    try {
      await _cargosFuture;
    } catch (_) {}
  }

  Widget _buildCargosHubCard(EdgeInsets padding) {
    return Padding(
      padding: EdgeInsets.fromLTRB(padding.left, 0, padding.right, 12),
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              ThemeCleanPremium.primary.withValues(alpha: 0.08),
              ThemeCleanPremium.cardBackground,
              ThemeCleanPremium.primaryLighter.withValues(alpha: 0.12),
            ],
            stops: const [0.0, 0.5, 1.0],
          ),
          borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusLg),
          border: Border.all(
            color: ThemeCleanPremium.primary.withValues(alpha: 0.12),
          ),
          boxShadow: ThemeCleanPremium.softUiCardShadow,
        ),
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    ThemeCleanPremium.primary,
                    ThemeCleanPremium.primaryLight,
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: ThemeCleanPremium.primary.withValues(alpha: 0.28),
                    blurRadius: 10,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: const Padding(
                padding: EdgeInsets.all(9),
                child: Icon(
                  Icons.badge_rounded,
                  color: Colors.white,
                  size: 22,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Cargos',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: ThemeCleanPremium.onSurface,
                      letterSpacing: -0.4,
                      height: 1.15,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Toque num cargo para ver membros vinculados e alterar funções no cadastro.',
                    style: TextStyle(
                      fontSize: 12.5,
                      height: 1.35,
                      color: ThemeCleanPremium.onSurfaceVariant,
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

  Future<void> _restoreMissingDefaultCargos() async {
    if (!_canWrite) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusLg)),
        title: const Text('Restaurar cargos padrão'),
        content: Text(
          'Serão criados de novo os ${_welcomeCargos.length} cargos do kit oficial que ainda não existirem. '
          'Cargos personalizados não serão removidos.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Restaurar faltantes')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await FirebaseAuth.instance.currentUser?.getIdToken(true);
      final existing = await _col.get();
      final have = existing.docs.map((d) => d.id).toSet();
      var n = 0;
      final batch = FirebaseFirestore.instance.batch();
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
      await batch.commit();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('$n cargo(s) padrão criado(s).', style: const TextStyle(color: Colors.white)),
            backgroundColor: Colors.green,
          ),
        );
        _refresh();
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erro: $e')));
    }
  }

  Future<void> _addOrEdit({DocumentSnapshot<Map<String, dynamic>>? doc}) async {
    if (!_canWrite) return;
    final data = doc?.data() ?? {};
    final nameCtrl = TextEditingController(text: (data['name'] ?? '').toString());
    final keyCtrl = TextEditingController(text: (data['key'] ?? doc?.id ?? '').toString());
    final hierCtrl = TextEditingController(
        text: (data['hierarchyLevel'] ?? '').toString().trim().isEmpty
            ? '50'
            : '${data['hierarchyLevel']}');
    var template = (data['permissionTemplate'] ?? data['key'] ?? 'membro').toString().trim();
    if (template.isEmpty) template = 'membro';
    final modRaw = data['modulePermissions'] ?? data['module_permissions'];
    final moduleSel = <String>{
      if (modRaw is List)
        for (final e in modRaw) (e ?? '').toString().trim().toLowerCase(),
    };

    var membrosTri = _parseTriMembros(moduleSel);
    var muralTri = _parseTriMural(moduleSel);
    var eventosTri = _parseTriEventos(moduleSel);
    var agendaTri = _parseTriAgenda(moduleSel);
    final relParsed = _parseRelatorios(moduleSel);
    var relatoriosFull = relParsed.$1;
    var relatorioPicks = {...relParsed.$2};
    var simpleSel = <String>{
      for (final c in _kCargoSimpleChips)
        if (moduleSel.contains(c.$1)) c.$1,
    };
    final cargoKeyInitial =
        (data['key'] ?? doc?.id ?? '').toString().trim().toLowerCase();
    if (cargoKeyInitial == 'lider_departamento') {
      relatoriosFull = false;
      relatorioPicks.removeWhere((e) => e != 'eventos' && e != 'aniversariantes');
    }

    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) {
          final templates = ChurchFuncoesControleService.permissionTemplates;
          final templateValue =
              templates.any((t) => t.key == template) ? template : 'membro';
          final cargoKeyLive = keyCtrl.text.trim().toLowerCase();
          final isLiderDep = cargoKeyLive == 'lider_departamento';
          final primary = ThemeCleanPremium.primary;
          final chips = isLiderDep
              ? _kCargoSimpleChips
                  .where((c) =>
                      c.$1 != 'financeiro' &&
                      c.$1 != 'patrimonio' &&
                      c.$1 != 'fornecedores')
                  .toList()
              : _kCargoSimpleChips.toList();
          return AlertDialog(
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusLg)),
            backgroundColor: const Color(0xFFF8FAFC),
            title: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(Icons.workspace_premium_rounded, color: primary),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    doc == null ? 'Novo cargo' : 'Editar cargo',
                    style: GoogleFonts.manrope(
                      fontWeight: FontWeight.w800,
                      fontSize: 18,
                      letterSpacing: -0.3,
                    ),
                  ),
                ),
              ],
            ),
            content: SingleChildScrollView(
              child: SizedBox(
                width: 440,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: nameCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Nome do cargo',
                        prefixIcon: Icon(Icons.badge_rounded),
                      ),
                      textCapitalization: TextCapitalization.words,
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: keyCtrl,
                      onChanged: (_) => setDlg(() {}),
                      decoration: InputDecoration(
                        labelText: 'Chave técnica (única)',
                        prefixIcon: const Icon(Icons.key_rounded),
                        helperText: doc == null
                            ? 'Deixe vazio para gerar a partir do nome.'
                            : 'Usada em FUNÇÕES do membro.',
                      ),
                    ),
                    if (isLiderDep) ...[
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFF7ED),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                              color: const Color(0xFFFDBA74).withValues(alpha: 0.8)),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(Icons.shield_rounded,
                                size: 18, color: Colors.orange.shade800),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Líder de departamento: sem Financeiro, Patrimônio e Fornecedores; relatórios apenas Eventos e Aniversariantes.',
                                style: TextStyle(
                                  fontSize: 11.5,
                                  height: 1.35,
                                  color: Colors.grey.shade900,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: 12),
                    TextField(
                      controller: hierCtrl,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Nível hierárquico (0–100)',
                        prefixIcon: Icon(Icons.layers_rounded),
                      ),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      value: templateValue,
                      decoration: const InputDecoration(
                        labelText: 'Modelo de permissões base',
                        prefixIcon: Icon(Icons.security_rounded),
                      ),
                      items: templates
                          .map((t) =>
                              DropdownMenuItem(value: t.key, child: Text(t.label)))
                          .toList(),
                      onChanged: (v) => setDlg(() => template = v ?? 'membro'),
                    ),
                    const SizedBox(height: 18),
                    Text(
                      'Acesso fino ao painel',
                      style: GoogleFonts.manrope(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.2,
                        color: ThemeCleanPremium.onSurface,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Somam-se ao modelo base e podem ser fundidos em users.permissions ao vincular o membro.',
                      style: TextStyle(
                        fontSize: 11,
                        height: 1.35,
                        color: ThemeCleanPremium.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 12),
                    _cargoAccessTriTile(
                      title: 'Membros',
                      hint:
                          'Padrão = herda do modelo. «Só ver» limita edição da lista.',
                      icon: Icons.people_alt_rounded,
                      tri: membrosTri,
                      onChanged: (v) => setDlg(() => membrosTri = v),
                    ),
                    _cargoAccessTriTile(
                      title: 'Mural de avisos',
                      hint:
                          'Leitura = não publica. Publicar = criar/editar avisos.',
                      icon: Icons.campaign_rounded,
                      tri: muralTri,
                      onChanged: (v) => setDlg(() => muralTri = v),
                      label1: 'Leitura',
                      label2: 'Publicar',
                    ),
                    _cargoAccessTriTile(
                      title: 'Eventos (feed)',
                      hint:
                          'Alinhado ao Mural de Eventos — RSVP, feed e abas de gestão.',
                      icon: Icons.event_rounded,
                      tri: eventosTri,
                      onChanged: (v) => setDlg(() => eventosTri = v),
                    ),
                    _cargoAccessTriTile(
                      title: 'Agenda',
                      hint: 'Calendário unificado — cultos, agenda interna e feed.',
                      icon: Icons.calendar_month_rounded,
                      tri: agendaTri,
                      onChanged: (v) => setDlg(() => agendaTri = v),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Módulos adicionais',
                      style: GoogleFonts.manrope(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.2,
                        color: ThemeCleanPremium.onSurface,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            Colors.white,
                            Color.lerp(primary, Colors.white, 0.94)!,
                          ],
                        ),
                        borderRadius:
                            BorderRadius.circular(ThemeCleanPremium.radiusMd),
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                        boxShadow: ThemeCleanPremium.softUiCardShadow,
                      ),
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: chips.map((m) {
                          final sel = simpleSel.contains(m.$1);
                          return _cargoModulePermissionChip(
                            moduleKey: m.$1,
                            label: m.$2,
                            selected: sel,
                            onTap: () => setDlg(() {
                              if (sel) {
                                simpleSel.remove(m.$1);
                              } else {
                                simpleSel.add(m.$1);
                              }
                            }),
                          );
                        }).toList(),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            Colors.white,
                            Color.lerp(primary, Colors.white, 0.92)!,
                          ],
                        ),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                        boxShadow: ThemeCleanPremium.softUiCardShadow,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.picture_as_pdf_rounded,
                                  size: 20, color: primary),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  'Relatórios PDF',
                                  style: GoogleFonts.manrope(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: -0.2,
                                    color: ThemeCleanPremium.onSurface,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          SwitchListTile(
                            contentPadding: EdgeInsets.zero,
                            title: Text(
                              'Pacote completo',
                              style: GoogleFonts.manrope(
                                fontWeight: FontWeight.w700,
                                fontSize: 14,
                                color: ThemeCleanPremium.onSurface,
                              ),
                            ),
                            subtitle: Text(
                              'Todos os relatórios compatíveis com o modelo e com financeiro/patrimônio.',
                              style: TextStyle(
                                fontSize: 12,
                                height: 1.35,
                                color: ThemeCleanPremium.onSurfaceVariant,
                              ),
                            ),
                            value: relatoriosFull && !isLiderDep,
                            activeThumbColor: Colors.white,
                            activeTrackColor: primary,
                            onChanged: isLiderDep
                                ? null
                                : (v) => setDlg(() {
                                      relatoriosFull = v;
                                      if (v) relatorioPicks.clear();
                                    }),
                          ),
                          if (!relatoriosFull || isLiderDep) ...[
                            const SizedBox(height: 4),
                            Align(
                              alignment: Alignment.centerLeft,
                              child: Text(
                                isLiderDep
                                    ? 'Marque só os PDFs deste cargo (máx.: Eventos e Aniversariantes).'
                                    : 'Ou escolha relatórios específicos:',
                                style: TextStyle(
                                  fontSize: 11,
                                  height: 1.35,
                                  color: ThemeCleanPremium.onSurfaceVariant,
                                ),
                              ),
                            ),
                            const SizedBox(height: 10),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                for (final r in _kRelatorioPickIds)
                                  if (!isLiderDep ||
                                      r.$1 == 'eventos' ||
                                      r.$1 == 'aniversariantes')
                                    _cargoRelatorioPickChip(
                                      pickId: r.$1,
                                      label: r.$2,
                                      selected:
                                          relatorioPicks.contains(r.$1),
                                      enabled:
                                          !(relatoriosFull && !isLiderDep),
                                      onTap: () {
                                        setDlg(() {
                                          if (relatorioPicks
                                              .contains(r.$1)) {
                                            relatorioPicks.remove(r.$1);
                                          } else {
                                            relatorioPicks.add(r.$1);
                                          }
                                        });
                                      },
                                    ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            actions: [
              OutlinedButton(
                onPressed: () => Navigator.pop(ctx, false),
                style: OutlinedButton.styleFrom(
                  foregroundColor: ThemeCleanPremium.primary,
                  side: BorderSide(
                    color: ThemeCleanPremium.primary.withValues(alpha: 0.35),
                  ),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius:
                        BorderRadius.circular(ThemeCleanPremium.radiusMd),
                  ),
                ),
                child: const Text(
                  'Cancelar',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                style: FilledButton.styleFrom(
                  backgroundColor: ThemeCleanPremium.primary,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius:
                        BorderRadius.circular(ThemeCleanPremium.radiusMd),
                  ),
                ),
                child: const Text(
                  'Salvar',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                ),
              ),
            ],
          );
        },
      ),
    );
    if (saved != true) return;
    final name = nameCtrl.text.trim();
    if (name.isEmpty) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Informe o nome do cargo.')));
      return;
    }
    var key = keyCtrl.text.trim().toLowerCase();
    if (key.isEmpty) key = _nameToKey(name);
    if (key.isEmpty) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Chave inválida para o cargo.')));
      return;
    }
    final h = int.tryParse(hierCtrl.text.trim()) ?? 50;
    final mods = _serializeModulePermissions(
      cargoKey: key,
      membrosTri: membrosTri,
      muralTri: muralTri,
      eventosTri: eventosTri,
      agendaTri: agendaTri,
      simple: simpleSel,
      relatoriosFull: relatoriosFull,
      relatorioPicks: relatorioPicks,
    ).toList()
      ..sort();
    try {
      await FirebaseAuth.instance.currentUser?.getIdToken(true);
      final payload = <String, dynamic>{
        'name': name,
        'key': key,
        'permissionTemplate': template,
        'hierarchyLevel': h.clamp(0, 100),
        'modulePermissions': mods,
        'updatedAt': FieldValue.serverTimestamp(),
      };
      if (doc == null) {
        payload['order'] = 999;
        payload['createdAt'] = FieldValue.serverTimestamp();
        await _col.doc(key).set(payload);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text('Cargo cadastrado!', style: TextStyle(color: Colors.white)),
              backgroundColor: Colors.green));
        }
      } else {
        await doc.reference.update(payload);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text('Cargo atualizado!', style: TextStyle(color: Colors.white)),
              backgroundColor: Colors.green));
        }
      }
      _refresh();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erro ao salvar: $e')));
    }
  }

  Future<void> _delete(DocumentSnapshot<Map<String, dynamic>> doc) async {
    if (!_canWrite) return;
    final name = (doc.data()?['name'] ?? '').toString();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusLg)),
        title: const Row(children: [Icon(Icons.delete_outline_rounded, color: Color(0xFFDC2626)), SizedBox(width: 10), Text('Excluir cargo')]),
        content: Text('Excluir o cargo "$name"? Membros com este cargo continuarão com o valor no cadastro, mas o cargo não aparecerá mais na lista.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFFDC2626)),
            child: const Text('Excluir'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await FirebaseAuth.instance.currentUser?.getIdToken(true);
      await doc.reference.delete();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Cargo excluído.', style: TextStyle(color: Colors.white)), backgroundColor: Colors.green));
        _refresh();
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erro ao excluir: $e')));
    }
  }

  void _openCargoMembros(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? {};
    final name = (data['name'] ?? doc.id).toString();
    final key = (data['key'] ?? doc.id).toString();
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _CargoMembrosPage(
          tenantId: _resolvedTenantId ?? widget.tenantId,
          role: widget.role,
          cargoName: name,
          cargoKey: key,
          cargoRef: doc.reference,
          canWrite: _canWrite,
          onChanged: _refresh,
        ),
      ),
    ).then((_) => _refresh());
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
      backgroundColor: ThemeCleanPremium.surfaceVariant,
      appBar: null,
      body: SafeArea(
        top: !widget.embeddedInShell,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(padding.left, 4, padding.right, 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  if (widget.onOpenPanelCorpoAdministrativo != null)
                    IconButton(
                      tooltip: 'Corpo administrativo (painel)',
                      onPressed: widget.onOpenPanelCorpoAdministrativo,
                      icon: Icon(Icons.groups_rounded,
                          color: ThemeCleanPremium.primary),
                      style: IconButton.styleFrom(
                          minimumSize: const Size(
                              ThemeCleanPremium.minTouchTarget,
                              ThemeCleanPremium.minTouchTarget)),
                    ),
                  IconButton(
                    tooltip: 'Organograma ministerial',
                    onPressed: _openLideranca,
                    icon: Icon(Icons.account_tree_rounded,
                        color: ThemeCleanPremium.primary),
                    style: IconButton.styleFrom(
                        minimumSize: const Size(
                            ThemeCleanPremium.minTouchTarget,
                            ThemeCleanPremium.minTouchTarget)),
                  ),
                  IconButton(
                    tooltip: 'Atualizar lista',
                    onPressed: () => _refresh(forceServer: true),
                    icon: Icon(Icons.refresh_rounded,
                        color: ThemeCleanPremium.primary),
                    style: IconButton.styleFrom(
                        minimumSize: const Size(
                            ThemeCleanPremium.minTouchTarget,
                            ThemeCleanPremium.minTouchTarget)),
                  ),
                  if (_canWrite)
                    PopupMenuButton<String>(
                      tooltip: 'Mais opções',
                      icon: Icon(Icons.more_vert_rounded,
                          color: ThemeCleanPremium.primary),
                      onSelected: (v) {
                        if (v == 'restore') {
                          _restoreMissingDefaultCargos();
                        }
                      },
                      itemBuilder: (_) => const [
                        PopupMenuItem(
                          value: 'restore',
                          child: Text('Restaurar cargos padrão (faltantes)'),
                        ),
                      ],
                    ),
                  if (_canWrite)
                    IconButton(
                      tooltip: 'Novo cargo',
                      onPressed: () => _addOrEdit(),
                      icon: Icon(Icons.add_circle_outline_rounded,
                          color: ThemeCleanPremium.primary),
                      style: IconButton.styleFrom(
                          minimumSize: const Size(
                              ThemeCleanPremium.minTouchTarget,
                              ThemeCleanPremium.minTouchTarget)),
                    ),
                ],
              ),
            ),
            Expanded(
              child: FutureBuilder<QuerySnapshot<Map<String, dynamic>>>(
                future: _cargosFuture,
                builder: (context, snap) {
                  if (snap.connectionState == ConnectionState.waiting &&
                      !snap.hasData) {
                    return const ChurchPanelLoadingBody();
                  }
                  if (snap.hasError) {
                    return Padding(
                      padding: const EdgeInsets.all(24),
                      child: ChurchPanelErrorBody(
                        title: 'Não foi possível carregar os cargos',
                        error: snap.error,
                        onRetry: () => _refresh(forceServer: true),
                      ),
                    );
                  }
                  var docs = snap.data?.docs ?? [];
                  if (docs.isEmpty) {
                    if (_canWrite && !_triedAutoSeed) {
                      _triedAutoSeed = true;
                      WidgetsBinding.instance.addPostFrameCallback((_) async {
                        await _seedPadroes();
                        if (mounted) {
                          await _refresh();
                        }
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
                                    height: 1.35),
                                textAlign: TextAlign.center,
                              ),
                            ],
                          ),
                        ),
                      );
                    }
                    if (_canWrite) {
                      return Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                padding: const EdgeInsets.all(20),
                                decoration: BoxDecoration(
                                  color: ThemeCleanPremium.primary
                                      .withValues(alpha: 0.08),
                                  borderRadius: BorderRadius.circular(24),
                                ),
                                child: Icon(Icons.badge_rounded,
                                    size: 64,
                                    color: ThemeCleanPremium.primary
                                        .withValues(alpha: 0.7)),
                              ),
                              const SizedBox(height: 20),
                              Text(
                                'Nenhum cargo cadastrado',
                                style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w700,
                                    color: ThemeCleanPremium.onSurface),
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Não foi possível criar os padrões automaticamente. Tente de novo ou cadastre manualmente.',
                                style: TextStyle(
                                    fontSize: 14, color: Colors.grey.shade600),
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: 24),
                              FilledButton.icon(
                                onPressed: () async {
                                  await _seedPadroes();
                                  if (mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text('Cargos padrão criados!',
                                            style:
                                                TextStyle(color: Colors.white)),
                                        backgroundColor: Colors.green,
                                      ),
                                    );
                                  }
                                },
                                icon: const Icon(Icons.add_box_rounded),
                                label: const Text('Criar cargos padrão'),
                                style: FilledButton.styleFrom(
                                  backgroundColor: ThemeCleanPremium.primary,
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 24, vertical: 14),
                                  shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(
                                          ThemeCleanPremium.radiusSm)),
                                ),
                              ),
                              const SizedBox(height: 12),
                              OutlinedButton.icon(
                                onPressed: () => _addOrEdit(),
                                icon: const Icon(Icons.add_rounded),
                                label: const Text('Novo cargo manual'),
                              ),
                            ],
                          ),
                        ),
                      );
                    }
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          'Nenhum cargo cadastrado nesta igreja.',
                          style: TextStyle(
                              fontSize: 15,
                              color: ThemeCleanPremium.onSurfaceVariant),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    );
                  }
                  docs = List.from(docs)
                    ..sort((a, b) => ((a.data()['name'] ?? '')
                            .toString()
                            .toLowerCase())
                        .compareTo((b.data()['name'] ?? '')
                            .toString()
                            .toLowerCase()));

                  Widget scroll = CustomScrollView(
                    primary: false,
                    physics: const AlwaysScrollableScrollPhysics(),
                    slivers: [
                      SliverToBoxAdapter(child: _buildCargosHubCard(padding)),
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: EdgeInsets.fromLTRB(
                              padding.left, 0, padding.right, 8),
                          child: Row(
                            children: [
                              const Spacer(),
                              if (_canWrite)
                                FilledButton.icon(
                                  onPressed: () => _addOrEdit(),
                                  icon: const Icon(Icons.add_rounded, size: 20),
                                  label: const Text('Novo'),
                                  style: FilledButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 12, vertical: 10),
                                    backgroundColor: ThemeCleanPremium.primary,
                                    foregroundColor: Colors.white,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                      SliverPadding(
                        padding: EdgeInsets.fromLTRB(
                          listPad.left,
                          0,
                          listPad.right,
                          ThemeCleanPremium.spaceSm,
                        ),
                        sliver: SliverList(
                          delegate: SliverChildBuilderDelegate(
                            (context, i) {
                              final d = docs[i];
                              final name = (d.data()['name'] ?? d.id).toString();
                              final key = (d.data()['key'] ?? d.id).toString();
                              final accent =
                                  _cargoAccentColorFromData(d.data());
                              return Padding(
                                padding: EdgeInsets.only(
                                  bottom:
                                      i < docs.length - 1 ? 10 : 0,
                                ),
                                child: _CargoCardSuperPremium(
                                  cargoName: name,
                                  cargoKey: key,
                                  accentColor: accent,
                                  canWrite: _canWrite,
                                  onTap: () => _openCargoMembros(d),
                                  onEdit: () => _addOrEdit(doc: d),
                                  onDelete: () => _delete(d),
                                  onViewMembros: () => _openCargoMembros(d),
                                ),
                              );
                            },
                            childCount: docs.length,
                          ),
                        ),
                      ),
                      SliverToBoxAdapter(child: SizedBox(height: listPad.bottom)),
                    ],
                  );

                  if (kIsWeb) {
                    return SizedBox.expand(child: scroll);
                  }
                  return RefreshIndicator(
                    onRefresh: () => _refresh(forceServer: true),
                    color: ThemeCleanPremium.primary,
                    child: SizedBox.expand(child: scroll),
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

/// Card de cargo — mesmo padrão visual de [_buildPremiumDeptListTile] em [DepartmentsPage].
class _CargoCardSuperPremium extends StatelessWidget {
  final String cargoName;
  final String cargoKey;
  final Color accentColor;
  final bool canWrite;
  final VoidCallback onTap;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onViewMembros;

  const _CargoCardSuperPremium({
    required this.cargoName,
    required this.cargoKey,
    required this.accentColor,
    required this.canWrite,
    required this.onTap,
    required this.onEdit,
    required this.onDelete,
    required this.onViewMembros,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          decoration: BoxDecoration(
            color: ThemeCleanPremium.cardBackground,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFFE2E8F0)),
            boxShadow: ThemeCleanPremium.softUiCardShadow,
          ),
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  width: 4,
                  decoration: BoxDecoration(
                    color: _kCargoListGoldAccent,
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(13),
                      bottomLeft: Radius.circular(13),
                    ),
                  ),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(10, 12, 12, 12),
                    child: Row(
                      children: [
                        CircleAvatar(
                          radius: 22,
                          backgroundColor:
                              accentColor.withValues(alpha: 0.18),
                          child: Icon(
                            Icons.badge_rounded,
                            color: accentColor,
                            size: 22,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                cargoName,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 15,
                                  color: ThemeCleanPremium.onSurface,
                                  height: 1.2,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                cargoKey.isNotEmpty
                                    ? 'Chave: $cargoKey · toque para membros'
                                    : 'Toque para ver membros vinculados',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: ThemeCleanPremium.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Icon(
                          Icons.chevron_right_rounded,
                          color: ThemeCleanPremium.onSurfaceVariant
                              .withValues(alpha: 0.85),
                          size: 26,
                        ),
                        if (canWrite) ...[
                          const SizedBox(width: 2),
                          PopupMenuButton<String>(
                            icon: Icon(Icons.more_vert_rounded,
                                color: Colors.grey.shade600, size: 22),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(
                                    ThemeCleanPremium.radiusSm)),
                            onSelected: (v) {
                              if (v == 'edit') {
                                onEdit();
                              }
                              if (v == 'delete') {
                                onDelete();
                              }
                              if (v == 'view') {
                                onViewMembros();
                              }
                            },
                            itemBuilder: (_) => [
                              const PopupMenuItem(
                                value: 'view',
                                child: Row(children: [
                                  Icon(Icons.people_rounded, size: 20),
                                  SizedBox(width: 10),
                                  Text('Ver membros')
                                ]),
                              ),
                              const PopupMenuItem(
                                value: 'edit',
                                child: Row(children: [
                                  Icon(Icons.edit_rounded, size: 20),
                                  SizedBox(width: 10),
                                  Text('Editar')
                                ]),
                              ),
                              const PopupMenuItem(
                                value: 'delete',
                                child: Row(children: [
                                  Icon(Icons.delete_outline_rounded,
                                      size: 20, color: Color(0xFFDC2626)),
                                  SizedBox(width: 10),
                                  Text('Excluir',
                                      style:
                                          TextStyle(color: Color(0xFFDC2626)))
                                ]),
                              ),
                            ],
                          ),
                        ],
                      ],
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

  @override
  void initState() {
    super.initState();
    _loadMembers();
  }

  Future<void> _loadMembers() async {
    if (!mounted) return;
    setState(() => _loading = true);
    List<String> allIds;
    try {
      allIds = await _cargoMemberMergeTenantIds(widget.tenantId);
    } catch (_) {
      allIds = [widget.tenantId];
    }
    final db = FirebaseFirestore.instance;
    final seen = <String>{};
    final list = <_MemberWithRef>[];
    final cargoKeyNorm = widget.cargoKey.toLowerCase().trim();
    final cargoNameNorm = widget.cargoName.toLowerCase().trim();

    try {
      final snaps = await Future.wait(
        allIds.map(
          (tid) => db
              .collection('igrejas')
              .doc(tid)
              .collection('membros')
              .limit(500)
              .get(const GetOptions(source: Source.serverAndCache)),
        ),
      );
      for (final snap in snaps) {
        for (final doc in snap.docs) {
          if (seen.contains(doc.id)) continue;
          final d = doc.data();
          final funcoes = d['FUNCOES'] ?? d['funcoes'];
          final cargo =
              (d['CARGO'] ?? d['cargo'] ?? d['funcao'] ?? d['role'] ?? '').toString().trim().toLowerCase();
          var hasCargo = false;
          if (funcoes is List) {
            for (final f in funcoes) {
              final s = (f ?? '').toString().trim().toLowerCase();
              if (s == cargoKeyNorm || s == cargoNameNorm) {
                hasCargo = true;
                break;
              }
            }
          }
          if (!hasCargo && (cargo == cargoKeyNorm || cargo == cargoNameNorm)) hasCargo = true;
          if (hasCargo) {
            seen.add(doc.id);
            list.add(_MemberWithRef(id: doc.id, data: d, ref: doc.reference));
          }
        }
      }
    } catch (_) {}

    list.sort((a, b) {
      final na = _nome(a.data).toLowerCase();
      final nb = _nome(b.data).toLowerCase();
      return na.compareTo(nb);
    });
    if (mounted) {
      setState(() {
        _members = list;
        _loading = false;
      });
    }
  }

  static String _nome(Map<String, dynamic> d) =>
      (d['NOME_COMPLETO'] ?? d['nome'] ?? d['name'] ?? 'Membro').toString().trim();

  bool _memberHasCargo(Map<String, dynamic> d) {
    final cargoKeyNorm = widget.cargoKey.toLowerCase().trim();
    final cargoNameNorm = widget.cargoName.toLowerCase().trim();
    final funcoes = d['FUNCOES'] ?? d['funcoes'];
    if (funcoes is List) {
      for (final f in funcoes) {
        final s = (f ?? '').toString().trim().toLowerCase();
        if (s == cargoKeyNorm || s == cargoNameNorm) return true;
      }
    }
    final cargo =
        (d['CARGO'] ?? d['cargo'] ?? d['funcao'] ?? d['role'] ?? '').toString().trim().toLowerCase();
    return cargo == cargoKeyNorm || cargo == cargoNameNorm;
  }

  Future<List<_MemberWithRef>> _fetchAllMembersForPicker() async {
    List<String> allIds;
    try {
      allIds = await _cargoMemberMergeTenantIds(widget.tenantId);
    } catch (_) {
      allIds = [widget.tenantId];
    }
    final db = FirebaseFirestore.instance;
    final seen = <String>{};
    final list = <_MemberWithRef>[];
    try {
      final snaps = await Future.wait(
        allIds.map(
          (tid) => db
              .collection('igrejas')
              .doc(tid)
              .collection('membros')
              .limit(500)
              .get(const GetOptions(source: Source.serverAndCache)),
        ),
      );
      for (final snap in snaps) {
        for (final doc in snap.docs) {
          if (seen.contains(doc.id)) continue;
          seen.add(doc.id);
          list.add(_MemberWithRef(id: doc.id, data: doc.data(), ref: doc.reference));
        }
      }
    } catch (_) {}
    list.sort((a, b) => _nome(a.data).toLowerCase().compareTo(_nome(b.data).toLowerCase()));
    return list;
  }

  Future<void> _linkMemberToCargo(_MemberWithRef m) async {
    if (!_canWrite) return;
    await FirebaseAuth.instance.currentUser?.getIdToken(true);
    final cargoKey = widget.cargoKey.trim();
    if (cargoKey.isEmpty) return;

    final funcoesRaw = m.data['FUNCOES'] ?? m.data['funcoes'];
    var funcoes = funcoesRaw is List
        ? funcoesRaw.map((e) => (e ?? '').toString().trim()).where((s) => s.isNotEmpty).toList()
        : <String>[];
    final kNorm = cargoKey.toLowerCase();
    final nNorm = widget.cargoName.toLowerCase().trim();
    final already = funcoes.any((f) {
      final s = f.toLowerCase();
      return s == kNorm || s == nNorm;
    });
    if (already) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Este membro já possui este cargo.')),
        );
      }
      return;
    }
    funcoes = [...funcoes, cargoKey];

    final updates = <String, dynamic>{'FUNCOES': funcoes};
    final hadEmptyPrimary = (m.data['CARGO'] ?? m.data['cargo'] ?? '').toString().trim().isEmpty &&
        (m.data['funcao'] ?? '').toString().trim().isEmpty;
    if (hadEmptyPrimary && funcoes.isNotEmpty) {
      final primary = funcoes.first;
      updates['CARGO'] = primary;
      updates['funcao'] = primary;
      updates['role'] = primary.toLowerCase();
    }

    List<String> allIds;
    try {
      allIds = await _cargoMemberMergeTenantIds(widget.tenantId);
    } catch (_) {
      allIds = [widget.tenantId];
    }
    final db = FirebaseFirestore.instance;
    for (final tid in allIds) {
      try {
        await db.collection('igrejas').doc(tid).collection('membros').doc(m.id).set(updates, SetOptions(merge: true));
      } catch (_) {}
    }

    List<String> extraMods = [];
    try {
      final c = await widget.cargoRef.get();
      extraMods = AppPermissions.normalizePermissions(c.data()?['modulePermissions']);
    } catch (_) {}

    final authUid = (m.data['authUid'] ?? '').toString().trim();
    if (authUid.isNotEmpty) {
      try {
        final uref = db.collection('users').doc(authUid);
        final userPatch = <String, dynamic>{'FUNCOES': funcoes};
        if (extraMods.isNotEmpty) {
          final us = await uref.get();
          final cur = AppPermissions.normalizePermissions(us.data()?['permissions']);
          userPatch['permissions'] = {...cur, ...extraMods}.toList();
        }
        await uref.set(userPatch, SetOptions(merge: true));
      } catch (_) {}
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Membro vinculado ao cargo.', style: TextStyle(color: Colors.white)),
          backgroundColor: Colors.green,
        ),
      );
      widget.onChanged();
      _loadMembers();
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
          const SnackBar(content: Text('Todos os membros já têm este cargo ou não há membros cadastrados.')),
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
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erro: $e')));
    }
  }

  Future<void> _removeCargo(_MemberWithRef m) async {
    if (!widget.canWrite) return;
    final name = _nome(m.data);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusLg)),
        title: const Text('Remover cargo'),
        content: Text('Remover o cargo "${widget.cargoName}" de "$name"?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Remover')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await FirebaseAuth.instance.currentUser?.getIdToken(true);
      final funcoesRaw = m.data['FUNCOES'] ?? m.data['funcoes'];
      List<String> funcoes = funcoesRaw is List
          ? funcoesRaw.map((e) => (e ?? '').toString().trim()).where((s) => s.isNotEmpty).toList()
          : [];
      final cargoKeyNorm = widget.cargoKey.toLowerCase().trim();
      final cargoNameNorm = widget.cargoName.toLowerCase().trim();
      funcoes.removeWhere((f) {
        final s = f.toLowerCase();
        return s == cargoKeyNorm || s == cargoNameNorm;
      });
      if (funcoes.isEmpty) funcoes = ['membro'];
      final funcaoFinal = funcoes.first;
      final updates = <String, dynamic>{
        'FUNCOES': funcoes,
        'CARGO': funcaoFinal,
        'funcao': funcaoFinal,
        'role': funcaoFinal.toLowerCase(),
      };
      List<String> allIds;
      try {
        allIds = await _cargoMemberMergeTenantIds(widget.tenantId);
      } catch (_) {
        allIds = [widget.tenantId];
      }
      final db = FirebaseFirestore.instance;
      for (final tid in allIds) {
        try {
          await db.collection('igrejas').doc(tid).collection('membros').doc(m.id).set(updates, SetOptions(merge: true));
        } catch (_) {}
      }
      final authUid = (m.data['authUid'] ?? '').toString().trim();
      if (authUid.isNotEmpty) {
        try {
          await FirebaseFirestore.instance.collection('users').doc(authUid).set({
            'role': funcaoFinal.toLowerCase(),
            'funcao': funcaoFinal,
            'cargo': funcaoFinal,
            'FUNCOES': funcoes,
            'CARGO': funcaoFinal,
          }, SetOptions(merge: true));
        } catch (_) {}
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Cargo removido.', style: TextStyle(color: Colors.white)), backgroundColor: Colors.green));
        _loadMembers();
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erro: $e')));
    }
  }

  Future<void> _changeCargo(_MemberWithRef m) async {
    if (!_canWrite) return;
    final cargosSnap = await FirebaseFirestore.instance
        .collection('igrejas')
        .doc(widget.tenantId)
        .collection('cargos')
        .orderBy('name')
        .get();
    final cargos = cargosSnap.docs
        .map((d) => (key: (d.data()['key'] ?? d.id).toString(), name: (d.data()['name'] ?? d.id).toString()))
        .where((c) => c.key != widget.cargoKey)
        .toList();
    if (!mounted) return;
    if (cargos.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Não há outros cargos para alterar.')));
      return;
    }
    String? selectedKey;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusLg)),
          title: Text('Alterar cargo de ${_nome(m.data)}'),
          content: SizedBox(
            width: 320,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Selecione o novo cargo:', style: TextStyle(fontSize: 14, color: Colors.grey.shade700)),
                const SizedBox(height: 12),
                ...cargos.map((c) => RadioListTile<String>(
                      title: Text(c.name),
                      value: c.key,
                      groupValue: selectedKey,
                      onChanged: (v) {
                        selectedKey = v;
                        setDlg(() {});
                      },
                    )),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
            FilledButton(
              onPressed: selectedKey != null ? () => Navigator.pop(ctx, true) : null,
              child: const Text('Alterar'),
            ),
          ],
        ),
      ),
    );
    if (ok != true || selectedKey == null || !mounted) return;
    try {
      await FirebaseAuth.instance.currentUser?.getIdToken(true);
      final funcoesRaw = m.data['FUNCOES'] ?? m.data['funcoes'];
      List<String> funcoes = funcoesRaw is List
          ? funcoesRaw.map((e) => (e ?? '').toString().trim()).where((s) => s.isNotEmpty).toList()
          : [];
      final cargoKeyNorm = widget.cargoKey.toLowerCase().trim();
      funcoes.removeWhere((f) => f.toLowerCase() == cargoKeyNorm);
      funcoes.add(selectedKey!);
      final funcaoFinal = selectedKey!;
      final updates = <String, dynamic>{
        'FUNCOES': funcoes,
        'CARGO': funcaoFinal,
        'funcao': funcaoFinal,
        'role': funcaoFinal.toLowerCase(),
      };
      List<String> allIds;
      try {
        allIds = await _cargoMemberMergeTenantIds(widget.tenantId);
      } catch (_) {
        allIds = [widget.tenantId];
      }
      final db = FirebaseFirestore.instance;
      for (final tid in allIds) {
        try {
          await db.collection('igrejas').doc(tid).collection('membros').doc(m.id).set(updates, SetOptions(merge: true));
        } catch (_) {}
      }
      final authUid = (m.data['authUid'] ?? '').toString().trim();
      if (authUid.isNotEmpty) {
        try {
          await FirebaseFirestore.instance.collection('users').doc(authUid).set({
            'role': funcaoFinal.toLowerCase(),
            'funcao': funcaoFinal,
            'cargo': funcaoFinal,
            'FUNCOES': funcoes,
            'CARGO': funcaoFinal,
          }, SetOptions(merge: true));
        } catch (_) {}
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Cargo alterado.', style: TextStyle(color: Colors.white)), backgroundColor: Colors.green));
        _loadMembers();
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erro: $e')));
    }
  }

  bool get _canWrite => widget.canWrite;

  @override
  Widget build(BuildContext context) {
    final padding = ThemeCleanPremium.pagePadding(context);
    return Scaffold(
      backgroundColor: ThemeCleanPremium.surfaceVariant,
      appBar: AppBar(
        backgroundColor: ThemeCleanPremium.primary,
        foregroundColor: Colors.white,
        elevation: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.cargoName, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            Text('${_members.length} membro${_members.length != 1 ? 's' : ''} vinculado${_members.length != 1 ? 's' : ''}', style: TextStyle(fontSize: 12, color: Colors.white.withOpacity(0.9))),
          ],
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => Navigator.pop(context),
          tooltip: 'Voltar',
          style: IconButton.styleFrom(minimumSize: const Size(ThemeCleanPremium.minTouchTarget, ThemeCleanPremium.minTouchTarget)),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _loadMembers,
            tooltip: 'Atualizar',
            style: IconButton.styleFrom(minimumSize: const Size(ThemeCleanPremium.minTouchTarget, ThemeCleanPremium.minTouchTarget)),
          ),
        ],
      ),
      floatingActionButton: _canWrite
          ? FloatingActionButton.extended(
              onPressed: _pickAndLinkMember,
              backgroundColor: ThemeCleanPremium.primary,
              foregroundColor: Colors.white,
              icon: const Icon(Icons.person_add_alt_1_rounded),
              label: const Text('Vincular membro', style: TextStyle(fontWeight: FontWeight.w700)),
            )
          : null,
      body: _loading
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(width: 40, height: 40, child: CircularProgressIndicator(strokeWidth: 2.5, color: ThemeCleanPremium.primary)),
                  const SizedBox(height: 16),
                  Text('Carregando membros...', style: TextStyle(fontSize: 14, color: Colors.grey.shade600)),
                ],
              ),
            )
          : _members.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.people_outline_rounded, size: 64, color: Colors.grey.shade400),
                        const SizedBox(height: 16),
                        Text(
                          'Nenhum membro com este cargo',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Colors.grey.shade700),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Use o botão Vincular membro ou o cadastro em Membros.',
                          style: TextStyle(fontSize: 14, color: Colors.grey.shade500),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 24),
                        FilledButton.icon(
                          onPressed: _pickAndLinkMember,
                          icon: const Icon(Icons.person_add_alt_1_rounded),
                          label: const Text('Vincular membro'),
                          style: FilledButton.styleFrom(
                            backgroundColor: ThemeCleanPremium.primary,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusSm)),
                          ),
                        ),
                        const SizedBox(height: 12),
                        OutlinedButton.icon(
                          onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => MembersPage(tenantId: widget.tenantId, role: widget.role))),
                          icon: const Icon(Icons.people_rounded),
                          label: const Text('Ir para Membros'),
                        ),
                      ],
                    ),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _loadMembers,
                  color: ThemeCleanPremium.primary,
                  child: ListView.builder(
                    padding: EdgeInsets.fromLTRB(padding.left, 16, padding.right, padding.bottom + 24),
                    itemCount: _members.length,
                    itemBuilder: (_, i) {
                      final m = _members[i];
                      final tidPhoto =
                          _tenantIdFromMembroDocRef(m.ref) ?? widget.tenantId;
                      final cpfRaw =
                          (m.data['CPF'] ?? m.data['cpf'] ?? '').toString();
                      final cpfD = cpfRaw.replaceAll(RegExp(r'\D'), '');
                      final au =
                          (m.data['authUid'] ?? '').toString().trim();
                      return Container(
                        margin: const EdgeInsets.only(bottom: 10),
                        decoration: BoxDecoration(
                          color: ThemeCleanPremium.cardBackground,
                          borderRadius:
                              BorderRadius.circular(ThemeCleanPremium.radiusMd),
                          boxShadow: ThemeCleanPremium.softUiCardShadow,
                          border: Border.all(color: const Color(0xFFE2E8F0)),
                        ),
                        child: ClipRRect(
                          borderRadius:
                              BorderRadius.circular(ThemeCleanPremium.radiusMd),
                          child: IntrinsicHeight(
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
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
                                          ),
                                        ),
                                      ),
                                      borderRadius: BorderRadius.circular(
                                          ThemeCleanPremium.radiusMd),
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 16, vertical: 14),
                                        child: Row(
                                          children: [
                                            FotoMembroWidget(
                                              imageUrl: null,
                                              size: 52,
                                              tenantId: tidPhoto,
                                              memberId: m.id,
                                              cpfDigits: cpfD.length == 11
                                                  ? cpfD
                                                  : null,
                                              authUid:
                                                  au.isNotEmpty ? au : null,
                                              memberData: m.data,
                                              backgroundColor:
                                                  ThemeCleanPremium.primary
                                                      .withValues(
                                                          alpha: 0.12),
                                            ),
                                            const SizedBox(width: 14),
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  Text(
                                                    _nome(m.data),
                                                    style: TextStyle(
                                                      fontSize: 15,
                                                      fontWeight:
                                                          FontWeight.w800,
                                                      letterSpacing: -0.2,
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
                                                        TextOverflow.ellipsis,
                                                  ),
                                                ],
                                              ),
                                            ),
                                            if (_canWrite)
                                              PopupMenuButton<String>(
                                                icon: Icon(
                                                    Icons.more_vert_rounded,
                                                    color: Colors
                                                        .grey.shade600),
                                                shape:
                                                    RoundedRectangleBorder(
                                                  borderRadius:
                                                      BorderRadius.circular(
                                                          ThemeCleanPremium
                                                              .radiusSm),
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
                                                        builder: (_) =>
                                                            MembersPage(
                                                          tenantId: widget
                                                              .tenantId,
                                                          role: widget.role,
                                                        ),
                                                      ),
                                                    );
                                                  }
                                                },
                                                itemBuilder: (_) => [
                                                  const PopupMenuItem(
                                                    value: 'change',
                                                    child: Row(children: [
                                                      Icon(
                                                          Icons
                                                              .swap_horiz_rounded,
                                                          size: 20),
                                                      SizedBox(width: 10),
                                                      Text('Alterar cargo'),
                                                    ]),
                                                  ),
                                                  const PopupMenuItem(
                                                    value: 'remove',
                                                    child: Row(children: [
                                                      Icon(
                                                        Icons
                                                            .person_remove_rounded,
                                                        size: 20,
                                                        color: Color(
                                                            0xFFDC2626),
                                                      ),
                                                      SizedBox(width: 10),
                                                      Text(
                                                        'Remover cargo',
                                                        style: TextStyle(
                                                            color: Color(
                                                                0xFFDC2626)),
                                                      ),
                                                    ]),
                                                  ),
                                                  const PopupMenuItem(
                                                    value: 'edit',
                                                    child: Row(children: [
                                                      Icon(Icons.edit_rounded,
                                                          size: 20),
                                                      SizedBox(width: 10),
                                                      Text('Editar membro'),
                                                    ]),
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
                    },
                  ),
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
  State<_PickMemberForCargoBottomSheet> createState() => _PickMemberForCargoBottomSheetState();
}

class _PickMemberForCargoBottomSheetState extends State<_PickMemberForCargoBottomSheet> {
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
      (d['NOME_COMPLETO'] ?? d['nome'] ?? d['name'] ?? 'Membro').toString().trim();

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
    final cpfDigits =
        (d['CPF'] ?? d['cpf'] ?? '').toString().replaceAll(RegExp(r'\D'), '');
    final phoneDigits = (d['TELEFONES'] ?? d['telefone'] ?? d['TELEFONE'] ?? '')
        .toString()
        .replaceAll(RegExp(r'\D'), '');
    final qDigits = qqLower.replaceAll(RegExp(r'\D'), '');
    final emails = _emailCandidatesLower(d);
    final matchText = nome.contains(qqLower) ||
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
                              separatorBuilder: (_, __) =>
                                  const SizedBox(height: 10),
                              itemBuilder: (_, i) {
                                final m = filtered[i];
                                final tid = _tenantIdFromMembroDocRef(m.ref) ?? '';
                                final cpfRaw = (m.data['CPF'] ?? m.data['cpf'] ?? '')
                                    .toString();
                                final cpfD =
                                    cpfRaw.replaceAll(RegExp(r'\D'), '');
                                final au =
                                    (m.data['authUid'] ?? '').toString().trim();
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
                                            tenantId:
                                                tid.isNotEmpty ? tid : null,
                                            memberId: m.id,
                                            cpfDigits: cpfD.length == 11
                                                ? cpfD
                                                : null,
                                            authUid:
                                                au.isNotEmpty ? au : null,
                                            memberData: m.data,
                                            backgroundColor: primary
                                                .withValues(alpha: 0.12),
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
                                                    color: const Color(
                                                        0xFF0F172A),
                                                  ),
                                                  maxLines: 2,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                ),
                                                const SizedBox(height: 4),
                                                Text(
                                                  _email(m.data) ??
                                                      (cpfRaw.isNotEmpty
                                                          ? cpfRaw
                                                          : m.id),
                                                  style: GoogleFonts.inter(
                                                    fontSize: 13,
                                                    color: const Color(
                                                        0xFF64748B),
                                                    fontWeight: FontWeight.w500,
                                                  ),
                                                  maxLines: 1,
                                                  overflow:
                                                      TextOverflow.ellipsis,
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
