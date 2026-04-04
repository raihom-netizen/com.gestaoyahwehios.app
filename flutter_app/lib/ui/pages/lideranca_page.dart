import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:gestao_yahweh/core/roles_permissions.dart';
import 'package:gestao_yahweh/services/tenant_resolver_service.dart';
import 'package:gestao_yahweh/ui/theme_clean_premium.dart';
import 'package:gestao_yahweh/ui/widgets/safe_network_image.dart'
    show ResilientNetworkImage, imageUrlFromMap, sanitizeImageUrl;

/// Organograma simples: líderes com foto, ordenados por hierarquia do cargo.
class LiderancaPage extends StatefulWidget {
  final String tenantId;
  final String role;

  const LiderancaPage({
    super.key,
    required this.tenantId,
    required this.role,
  });

  @override
  State<LiderancaPage> createState() => _LiderancaPageState();
}

class _LiderancaPageState extends State<LiderancaPage> {
  bool _loading = true;
  List<_LeaderRow> _rows = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
    });
    try {
      final tid =
          await TenantResolverService.resolveEffectiveTenantId(widget.tenantId);
      final snap = await FirebaseFirestore.instance
          .collection('igrejas')
          .doc(tid)
          .collection('membros')
          .limit(500)
          .get();
      final cargoMeta = await _loadCargoHierarchy(tid);
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
          name: nome,
          photoUrl: foto,
          cargoLabel: label,
          rank: bestRank,
          sortKey: nome.toLowerCase(),
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
        _loading = false;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
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
      final snap = await FirebaseFirestore.instance
          .collection('igrejas')
          .doc(tid)
          .collection('cargos')
          .get();
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
    } catch (_) {}
    return map;
  }

  @override
  Widget build(BuildContext context) {
    final padding = ThemeCleanPremium.pagePadding(context);
    return Scaffold(
      backgroundColor: ThemeCleanPremium.surfaceVariant,
      appBar: ThemeCleanPremium.isMobile(context)
          ? null
          : AppBar(
              title: const Text('Liderança'),
              backgroundColor: Colors.white,
              foregroundColor: ThemeCleanPremium.onSurface,
              elevation: 0,
            ),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : CustomScrollView(
                slivers: [
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(
                          padding.left, 16, padding.right, 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Liderança ministerial',
                            style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w800,
                              color: ThemeCleanPremium.onSurface,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Membros com cargos de liderança (pastores, tesoureiros, líderes de departamento, etc.), do maior nível hierárquico para o menor.',
                            style: TextStyle(
                              fontSize: 13,
                              height: 1.35,
                              color: ThemeCleanPremium.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (_rows.isEmpty)
                    SliverFillRemaining(
                      hasScrollBody: false,
                      child: Center(
                        child: Padding(
                          padding: padding,
                          child: Text(
                            'Nenhum líder encontrado. Atribua cargos em Membros > Editar ou cadastre cargos em Cargos.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: ThemeCleanPremium.onSurfaceVariant,
                              height: 1.35,
                            ),
                          ),
                        ),
                      ),
                    )
                  else
                    SliverPadding(
                      padding: EdgeInsets.fromLTRB(
                        padding.left,
                        8,
                        padding.right,
                        padding.bottom + 24,
                      ),
                      sliver: SliverList(
                        delegate: SliverChildBuilderDelegate(
                          (context, i) {
                            final r = _rows[i];
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: Material(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(16),
                                elevation: 0,
                                child: Container(
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(16),
                                    border: Border.all(
                                        color: const Color(0xFFE2E8F0)),
                                    boxShadow: ThemeCleanPremium.softUiCardShadow,
                                  ),
                                  child: ListTile(
                                    contentPadding: const EdgeInsets.symmetric(
                                        horizontal: 16, vertical: 10),
                                    leading: CircleAvatar(
                                      radius: 28,
                                      backgroundColor: const Color(0xFFF1F5F9),
                                      child: ClipOval(
                                        child: r.photoUrl.isNotEmpty
                                            ? ResilientNetworkImage(
                                                imageUrl: sanitizeImageUrl(
                                                    r.photoUrl),
                                                width: 56,
                                                height: 56,
                                                fit: BoxFit.cover,
                                                errorWidget: Icon(
                                                  Icons.person_rounded,
                                                  color: Colors.grey.shade400,
                                                ),
                                              )
                                            : Icon(
                                                Icons.person_rounded,
                                                color: Colors.grey.shade400,
                                                size: 32,
                                              ),
                                      ),
                                    ),
                                    title: Text(
                                      r.name,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w700,
                                        fontSize: 16,
                                      ),
                                    ),
                                    subtitle: Padding(
                                      padding: const EdgeInsets.only(top: 4),
                                      child: Text(
                                        r.cargoLabel,
                                        style: TextStyle(
                                          fontSize: 13,
                                          color: ThemeCleanPremium.primary,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
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
    );
  }
}

class _LeaderRow {
  final String name;
  final String photoUrl;
  final String cargoLabel;
  final int rank;
  final String sortKey;

  _LeaderRow({
    required this.name,
    required this.photoUrl,
    required this.cargoLabel,
    required this.rank,
    required this.sortKey,
  });
}
