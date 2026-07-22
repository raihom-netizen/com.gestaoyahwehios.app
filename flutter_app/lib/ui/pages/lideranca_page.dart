import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:gestao_yahweh/core/church_panel_read_timeouts.dart';
import 'package:gestao_yahweh/core/repositories/church_repository.dart';
import 'package:gestao_yahweh/core/roles_permissions.dart';
import 'package:gestao_yahweh/core/yahweh_performance_v4.dart';
import 'package:gestao_yahweh/services/church_gallery_photo_warmup.dart';
import 'package:gestao_yahweh/services/church_tenant_resilient_reads.dart';
import 'package:gestao_yahweh/services/panel_dashboard_snapshot_service.dart';
import 'package:gestao_yahweh/ui/pages/church_leader_contact_page.dart';
import 'package:gestao_yahweh/ui/theme_clean_premium.dart';
import 'package:gestao_yahweh/ui/widgets/church_panel_ui_helpers.dart';
import 'package:gestao_yahweh/ui/widgets/church_wisdom_module_widgets.dart';
import 'package:gestao_yahweh/ui/widgets/foto_membro_widget.dart';
import 'package:gestao_yahweh/ui/widgets/safe_network_image.dart' show imageUrlFromMap;
import 'package:gestao_yahweh/ui/widgets/yahweh_super_premium_back_button.dart';
import 'package:gestao_yahweh/ui/widgets/yahweh_wisdom_visual_kit.dart';
import 'package:gestao_yahweh/core/data/church_ui_collections.dart';
import 'package:gestao_yahweh/utils/firestore_web_guard.dart';
import 'package:google_fonts/google_fonts.dart';

/// Organograma ministerial: cargos de liderança (diferente de «líderes de departamento» no painel).
class LiderancaPage extends StatefulWidget {
  final String tenantId;
  final String role;
  final String viewerCpfDigits;

  const LiderancaPage({
    super.key,
    required this.tenantId,
    required this.role,
    this.viewerCpfDigits = '',
  });

  @override
  State<LiderancaPage> createState() => _LiderancaPageState();
}

class _LiderancaPageState extends State<LiderancaPage> {
  static const Color _accent = Color(0xFFF43F5E);

  bool _loading = true;
  List<_LeaderRow> _rows = [];
  String _effectiveTenantId = '';
  bool _usedPanelCache = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      if (kIsWeb) {
        // Cap curto: não segurar o primeiro paint por causa do guard web.
        await FirestoreWebGuard.ensurePanelReadReady()
            .timeout(const Duration(seconds: 3), onTimeout: () {})
            .catchError((e, st) {
          debugPrint('Lideranca _load ensurePanelReadReady: $e\n$st');
        });
      }
      final tid = ChurchRepository.churchId(widget.tenantId).isNotEmpty
          ? ChurchRepository.churchId(widget.tenantId)
          : widget.tenantId.trim();
      _effectiveTenantId = tid;

      // Cache do painel com timeout curto — se demorar (server/callable),
      // cai direto para a consulta de membros em vez de segurar a tela.
      PanelDashboardSnapshot panel = const PanelDashboardSnapshot();
      try {
        panel = await PanelDashboardSnapshotService.readOnce(tid).timeout(
          const Duration(milliseconds: 3500),
          onTimeout: () => const PanelDashboardSnapshot(),
        );
      } catch (_) {}
      if (panel.homeLeaders.isNotEmpty) {
        final rows = panel.homeLeaders.map((lite) {
          final data = lite.toMemberDataMap();
          return _LeaderRow(
            memberId: lite.memberDocId,
            memberData: data,
            name: lite.displayName,
            photoUrl: lite.photoUrl ?? imageUrlFromMap(data),
            cargoLabel: lite.deptNames.isNotEmpty
                ? 'Líder · ${lite.deptNames.join(', ')}'
                : 'Liderança',
            rank: 50,
            sortKey: lite.displayName.toLowerCase(),
            deptNames: lite.deptNames,
          );
        }).toList();
        if (!mounted) return;
        setState(() {
          _rows = rows;
          _usedPanelCache = true;
          _loading = false;
        });
        return;
      }

      // Membros + hierarquia de cargos em PARALELO (antes era sequencial).
      final results = await Future.wait([
        ChurchTenantResilientReads.membrosRecent(
          tid,
          limit: YahwehPerformanceV4.dashboardStatsSampleLimit,
        ).timeout(ChurchPanelReadTimeouts.queryCap),
        _loadCargoHierarchy(tid),
      ]);
      final snap = results[0] as QuerySnapshot<Map<String, dynamic>>;
      final cargoMeta = results[1] as Map<String, Map<String, dynamic>>;
      final rows = <_LeaderRow>[];
      for (final d in snap.docs) {
        final m = d.data();
        final status =
            (m['STATUS'] ?? m['status'] ?? '').toString().toLowerCase();
        if (status.contains('inativ')) continue;
        final keys = _funcaoKeysFromMember(m);
        if (keys.isEmpty) continue;
        var bestRank = 0;
        String bestKey = keys.first;
        for (final k in keys) {
          final meta = cargoMeta[k] ?? cargoMeta[k.toLowerCase()];
          final r = meta?['hierarchy'] as int? ??
              ChurchRolePermissions.hierarchyRankForRoleKey(k);
          if (r > bestRank) {
            bestRank = r;
            bestKey = k;
          }
        }
        if (!ChurchRolePermissions.isLeadershipRoleKey(bestKey) &&
            bestRank < 40) {
          continue;
        }
        final nome = (m['NOME_COMPLETO'] ?? m['nome'] ?? 'Membro').toString();
        final foto = imageUrlFromMap(m);
        final label = _cargoDisplayLabel(m, bestKey, cargoMeta);
        rows.add(_LeaderRow(
          memberId: d.id,
          memberData: m,
          name: nome,
          photoUrl: foto,
          cargoLabel: label,
          rank: bestRank,
          sortKey: nome.toLowerCase(),
          deptNames: const [],
        ));
      }
      rows.sort((a, b) {
        final c = b.rank.compareTo(a.rank);
        if (c != 0) return c;
        return a.sortKey.compareTo(b.sortKey);
      });
      if (!mounted) return;
      setState(() {
        _rows = rows;
        _usedPanelCache = false;
        _loading = false;
      });
    } catch (e, st) {
      debugPrint('Lideranca _load: $e\n$st');
      if (mounted) setState(() => _loading = false);
    }
  }

  static List<String> _funcaoKeysFromMember(Map<String, dynamic> m) {
    final raw = m['FUNCOES'] ?? m['funcoes'];
    final out = <String>[];
    if (raw is List) {
      for (final e in raw) {
        final s = e.toString().trim();
        if (s.isNotEmpty && s.toLowerCase() != 'membro') out.add(s);
      }
    }
    if (out.isEmpty) {
      final f = (m['FUNCAO_PERMISSOES'] ??
              m['FUNCAO'] ??
              m['CARGO'] ??
              m['cargo'] ??
              '')
          .toString()
          .trim();
      if (f.isNotEmpty && f.toLowerCase() != 'membro') out.add(f);
    }
    return out;
  }

  static String _cargoDisplayLabel(
    Map<String, dynamic> m,
    String key,
    Map<String, Map<String, dynamic>> cargoMeta,
  ) {
    final meta = cargoMeta[key] ?? cargoMeta[key.toLowerCase()];
    final name = meta?['name']?.toString().trim();
    if (name != null && name.isNotEmpty) return name;
    final c = (m['CARGO'] ?? m['cargo'] ?? '').toString().trim();
    if (c.isNotEmpty) return c;
    return _prettyRoleKey(key);
  }

  static String _prettyRoleKey(String k) {
    final s = k.replaceAll('_', ' ').trim();
    if (s.isEmpty) return k;
    return s.split(' ').map((w) {
      if (w.isEmpty) return w;
      return w[0].toUpperCase() + w.substring(1).toLowerCase();
    }).join(' ');
  }

  static Future<Map<String, Map<String, dynamic>>> _loadCargoHierarchy(
      String tid) async {
    final map = <String, Map<String, dynamic>>{};
    try {
      final op = ChurchRepository.churchId(tid.trim());
      if (kIsWeb) {
        await FirestoreWebGuard.ensurePanelReadReady().catchError((e, st) {
          debugPrint(
            'Lideranca _loadCargoHierarchy ensurePanelReadReady: $e\n$st',
          );
        });
      }
      Future<QuerySnapshot<Map<String, dynamic>>> read() =>
          ChurchUiCollections.cargos(op).limit(100).get();
      final snap = kIsWeb
          ? await FirestoreWebGuard.runWithWebRecovery(
              read,
              maxAttempts: 4,
            ).timeout(ChurchPanelReadTimeouts.queryCap)
          : await read().timeout(ChurchPanelReadTimeouts.queryCap);
      for (final d in snap.docs) {
        final data = d.data();
        final key = (data['key'] ?? d.id).toString().trim().toLowerCase();
        if (key.isEmpty) continue;
        final h = data['hierarchyLevel'];
        final rank = h is int
            ? h
            : (h is num ? h.toInt() : null) ??
                ChurchRolePermissions.hierarchyRankForRoleKey(
                    (data['permissionTemplate'] ?? key).toString());
        map[key] = {
          'name': (data['name'] ?? '').toString(),
          'hierarchy': rank,
        };
      }
    } catch (e, st) {
      debugPrint('Lideranca _loadCargoHierarchy: $e\n$st');
    }
    return map;
  }

  static Color _rankAccent(int rank) {
    if (rank >= 80) return const Color(0xFF7C3AED);
    if (rank >= 60) return ThemeCleanPremium.primary;
    if (rank >= 40) return const Color(0xFF14B8A6);
    return _accent;
  }

  @override
  Widget build(BuildContext context) {
    final padding = ThemeCleanPremium.pagePadding(context);
    final tid = _effectiveTenantId.isNotEmpty
        ? _effectiveTenantId
        : widget.tenantId;

    if (!_loading && _rows.isNotEmpty) {
      ChurchGalleryPhotoWarmup.schedule(
        context: context,
        tenantId: tid,
        members: _rows.map(
          (r) => ChurchGalleryMemberPhotoRef(
            memberDocId: r.memberId,
            memberData: r.memberData,
            cpfDigits: (r.memberData['CPF'] ?? r.memberData['cpf'] ?? '')
                .toString()
                .replaceAll(RegExp(r'\D'), ''),
            authUid: (r.memberData['authUid'] ?? '').toString().trim().isEmpty
                ? null
                : (r.memberData['authUid'] ?? '').toString(),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        leadingWidth: 64,
        leading: YahwehSuperPremiumBackButton.appBarLeading(context),
        automaticallyImplyLeading: false,
        title: Text(
          'Organograma ministerial',
          style: GoogleFonts.inter(
            fontWeight: FontWeight.w800,
            letterSpacing: -0.2,
            fontSize: 17,
          ),
        ),
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
        flexibleSpace: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                _accent,
                Color.lerp(_accent, Colors.white, 0.22)!,
              ],
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
            ),
            boxShadow: [
              BoxShadow(
                color: _accent.withValues(alpha: 0.28),
                blurRadius: 10,
                offset: const Offset(0, 3),
              ),
            ],
          ),
        ),
      ),
      body: DecoratedBox(
        decoration: churchModuleBodyGradient(_accent),
        child: SafeArea(
          top: false,
          // Cabeçalho pinta imediatamente; só a lista espera o carregamento.
          child: RefreshIndicator(
                  onRefresh: _load,
                  child: CustomScrollView(
                    physics: const AlwaysScrollableScrollPhysics(
                      parent: BouncingScrollPhysics(),
                    ),
                    slivers: [
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: EdgeInsets.fromLTRB(
                            padding.left,
                            16,
                            padding.right,
                            12,
                          ),
                          child: YahwehWisdomSectionCard(
                            borderTint: _accent,
                            padding: const EdgeInsets.all(16),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                churchWisdomModuleIconLeading(
                                  icon: Icons.account_tree_rounded,
                                  accent: _accent,
                                  size: 48,
                                ),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Hierarquia ministerial',
                                        style: GoogleFonts.inter(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w800,
                                          color: const Color(0xFF0F172A),
                                        ),
                                      ),
                                      const SizedBox(height: 6),
                                      Text(
                                        _usedPanelCache
                                            ? 'Lista rápida do painel. Para cargos completos, atribua funções em Membros ou cadastre em Cargos.'
                                            : 'Membros com cargos de liderança — do maior nível hierárquico para o menor.',
                                        style: GoogleFonts.inter(
                                          fontSize: 13,
                                          height: 1.4,
                                          color: Colors.grey.shade700,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                      if (_rows.isNotEmpty) ...[
                                        const SizedBox(height: 10),
                                        Text(
                                          '${_rows.length} líder${_rows.length == 1 ? '' : 'es'}',
                                          style: GoogleFonts.inter(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w700,
                                            color: _accent,
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      if (_loading)
                        const SliverFillRemaining(
                          hasScrollBody: false,
                          child: Center(
                            child: Padding(
                              padding: EdgeInsets.only(bottom: 60),
                              child: SizedBox(
                                width: 30,
                                height: 30,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2.5),
                              ),
                            ),
                          ),
                        )
                      else if (_rows.isEmpty)
                        SliverFillRemaining(
                          hasScrollBody: false,
                          child: ChurchWisdomModuleEmptyState(
                            icon: Icons.account_tree_outlined,
                            title: 'Nenhum líder no organograma',
                            message:
                                'Atribua cargos em Membros > Editar ou cadastre cargos em Cargos.',
                            accent: _accent,
                          ),
                        )
                      else
                        SliverPadding(
                          padding: EdgeInsets.fromLTRB(
                            padding.left,
                            0,
                            padding.right,
                            padding.bottom + 24,
                          ),
                          sliver: SliverList(
                            delegate: SliverChildBuilderDelegate(
                              (context, i) {
                                final r = _rows[i];
                                final tierColor = _rankAccent(r.rank);
                                return ChurchWisdomModuleListCard(
                                  title: r.name,
                                  subtitle: r.cargoLabel,
                                  accent: tierColor,
                                  onTap: () => openChurchLeaderContactPage(
                                    context,
                                    memberData: r.memberData,
                                    departmentNames: r.deptNames,
                                    funcoes: const [],
                                    tenantId: tid,
                                    memberDocId: r.memberId,
                                    memberRole: widget.role,
                                    viewerCpfDigits: widget.viewerCpfDigits,
                                  ),
                                  leading: Stack(
                                    clipBehavior: Clip.none,
                                    children: [
                                      ClipRRect(
                                        borderRadius: BorderRadius.circular(14),
                                        child: FotoMembroWidget(
                                          tenantId: tid,
                                          memberId: r.memberId,
                                          memberData: r.memberData,
                                          imageUrl: r.photoUrl,
                                          size: 48,
                                          preferListThumbnail: true,
                                        ),
                                      ),
                                      Positioned(
                                        right: -4,
                                        bottom: -4,
                                        child: _LeaderRankBadge(
                                          rank: r.rank,
                                          color: tierColor,
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              },
                              childCount: _rows.length,
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

class _LeaderRankBadge extends StatelessWidget {
  const _LeaderRankBadge({required this.rank, required this.color});

  final int rank;
  final Color color;

  @override
  Widget build(BuildContext context) {
    if (rank <= 0) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white, width: 1.5),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.4),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Text(
        '$rank',
        style: GoogleFonts.inter(
          fontSize: 10,
          fontWeight: FontWeight.w800,
          color: Colors.white,
        ),
      ),
    );
  }
}

class _LeaderRow {
  final String memberId;
  final Map<String, dynamic> memberData;
  final String name;
  final String photoUrl;
  final String cargoLabel;
  final int rank;
  final String sortKey;
  final List<String> deptNames;

  _LeaderRow({
    required this.memberId,
    required this.memberData,
    required this.name,
    required this.photoUrl,
    required this.cargoLabel,
    required this.rank,
    required this.sortKey,
    this.deptNames = const [],
  });
}
