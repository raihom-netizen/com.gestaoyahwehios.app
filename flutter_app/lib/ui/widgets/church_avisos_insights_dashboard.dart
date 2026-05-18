import 'dart:async' show unawaited;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:gestao_yahweh/core/church_tenant_posts_collections.dart';
import 'package:gestao_yahweh/ui/theme_clean_premium.dart';
import 'package:gestao_yahweh/ui/widgets/church_panel_ui_helpers.dart';

/// Painel premium de métricas do mural de **avisos** (curtidas e comentários).
class ChurchAvisosInsightsDashboard extends StatefulWidget {
  final String tenantId;
  final bool canModerateComments;

  const ChurchAvisosInsightsDashboard({
    super.key,
    required this.tenantId,
    this.canModerateComments = false,
  });

  @override
  State<ChurchAvisosInsightsDashboard> createState() =>
      _ChurchAvisosInsightsDashboardState();
}

class _AvisoInsight {
  final String id;
  final String title;
  final DateTime? createdAt;
  final int likes;
  final int comments;
  final DocumentReference<Map<String, dynamic>> ref;

  _AvisoInsight({
    required this.id,
    required this.title,
    this.createdAt,
    required this.likes,
    required this.comments,
    required this.ref,
  });
}

class _ChurchAvisosInsightsDashboardState
    extends State<ChurchAvisosInsightsDashboard> {
  static const int _maxPosts = 18;
  List<_AvisoInsight> _rows = [];
  bool _loading = true;
  String? _error;

  CollectionReference<Map<String, dynamic>> get _avisos =>
      FirebaseFirestore.instance
          .collection('igrejas')
          .doc(widget.tenantId.trim())
          .collection(ChurchTenantPostsCollections.avisos);

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      QuerySnapshot<Map<String, dynamic>> snap;
      try {
        snap = await _avisos
            .orderBy('createdAt', descending: true)
            .limit(80)
            .get();
      } catch (_) {
        snap = await _avisos.limit(100).get();
      }
      var docs = snap.docs.toList();
      if (docs.length > 1) {
        docs.sort((a, b) {
          final ta = a.data()['createdAt'];
          final tb = b.data()['createdAt'];
          if (ta is Timestamp && tb is Timestamp) return tb.compareTo(ta);
          return 0;
        });
      }
      docs = docs.take(_maxPosts).toList();
      final list = <_AvisoInsight>[];
      for (final d in docs) {
        final data = d.data();
        final title =
            (data['title'] ?? data['titulo'] ?? 'Aviso').toString().trim();
        final likes = (data['likes'] as List?)?.length ?? 0;
        final comments = (data['commentsCount'] is num)
            ? (data['commentsCount'] as num).toInt()
            : 0;
        final ca = data['createdAt'];
        final created = ca is Timestamp ? ca.toDate() : null;
        list.add(_AvisoInsight(
          id: d.id,
          title: title.isEmpty ? 'Aviso' : title,
          createdAt: created,
          likes: likes,
          comments: comments,
          ref: d.reference,
        ));
      }
      if (mounted) {
        setState(() {
          _rows = list;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  String _fmtDate(DateTime? d) {
    if (d == null) return 'Sem data';
    return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
  }

  BarChartData _bars(
    List<_AvisoInsight> rows,
    double Function(_AvisoInsight) val,
    Color color,
  ) {
    if (rows.isEmpty) {
      return BarChartData();
    }
    final maxY = rows.map(val).reduce((a, b) => a > b ? a : b);
    final top = (maxY + 1).clamp(3.0, 80.0);
    return BarChartData(
      alignment: BarChartAlignment.spaceAround,
      maxY: top,
      barGroups: rows.asMap().entries.map((e) {
        final v = val(e.value);
        return BarChartGroupData(
          x: e.key,
          barRods: [
            BarChartRodData(
              toY: v,
              gradient: LinearGradient(
                begin: Alignment.bottomCenter,
                end: Alignment.topCenter,
                colors: [
                  color.withValues(alpha: 0.45),
                  color,
                ],
              ),
              width: 15,
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(8)),
            ),
          ],
          showingTooltipIndicators: const [0],
        );
      }).toList(),
      titlesData: FlTitlesData(
        bottomTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: 40,
            getTitlesWidget: (v, _) {
              final i = v.toInt();
              if (i >= 0 && i < rows.length) {
                final t = rows[i].title;
                final label = t.length > 9 ? '${t.substring(0, 9)}…' : t;
                return Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    label,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 9.5,
                      fontWeight: FontWeight.w700,
                      color: Colors.grey.shade700,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                );
              }
              return const SizedBox();
            },
          ),
        ),
        leftTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: 28,
            getTitlesWidget: (v, _) => Text(
              v.toInt().toString(),
              style: TextStyle(fontSize: 10, color: Colors.grey.shade600),
            ),
          ),
        ),
        topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        rightTitles:
            const AxisTitles(sideTitles: SideTitles(showTitles: false)),
      ),
      gridData: FlGridData(
        show: true,
        drawVerticalLine: false,
        getDrawingHorizontalLine: (_) =>
            FlLine(color: Colors.grey.shade200, strokeWidth: 1),
      ),
      borderData: FlBorderData(show: false),
      barTouchData: BarTouchData(
        touchTooltipData: BarTouchTooltipData(
          getTooltipItem: (group, groupIndex, rod, rodIndex) {
            final i = group.x;
            if (i >= 0 && i < rows.length) {
              return BarTooltipItem(
                '${rows[i].title}\n${rod.toY.toInt()}',
                const TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              );
            }
            return null;
          },
        ),
      ),
    );
  }

  Future<void> _openEngagementMenu(BuildContext context, int index) async {
    if (index < 0 || index >= _rows.length) return;
    final s = _rows[index];
    final choice = await showModalBottomSheet<String>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
              ),
              Text(
                s.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 12),
              ListTile(
                leading: Icon(Icons.favorite_rounded, color: Colors.red.shade400),
                title: const Text('Curtidas'),
                subtitle: Text('${s.likes}'),
                onTap: () => Navigator.pop(ctx, 'likes'),
              ),
              ListTile(
                leading: const Icon(Icons.comment_rounded, color: Color(0xFF0EA5E9)),
                title: const Text('Comentários'),
                subtitle: Text('${s.comments}'),
                onTap: () => Navigator.pop(ctx, 'comments'),
              ),
            ],
          ),
        ),
      ),
    );
    if (choice == null || !context.mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => _AvisoEngagementSheet(
        aviso: s,
        type: choice,
        canDeleteComments: widget.canModerateComments,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading && _rows.isEmpty) {
      return const ChurchPanelLoadingBody();
    }
    if (_error != null) {
      return ChurchPanelErrorBody(
        title: 'Não foi possível carregar o painel de avisos',
        error: _error,
        onRetry: _load,
      );
    }
    if (_rows.isEmpty) {
      return ThemeCleanPremium.premiumEmptyState(
        icon: Icons.campaign_rounded,
        title: 'Nenhum aviso para métricas',
        subtitle:
            'Publique avisos no mural para ver curtidas e comentários agregados aqui.',
      );
    }
    final pad = ThemeCleanPremium.pagePadding(context);
    final sumL = _rows.fold<int>(0, (a, s) => a + s.likes);
    final sumC = _rows.fold<int>(0, (a, s) => a + s.comments);
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: EdgeInsets.fromLTRB(pad.left, pad.top, pad.right, 72),
        children: [
          _AvisosHeroCard(
            postCount: _rows.length,
            sumLikes: sumL,
            sumComments: sumC,
          ),
          const SizedBox(height: ThemeCleanPremium.spaceLg),
          _AvisoPanelChartCard(
            title: 'Curtidas por aviso',
            subtitle: 'Últimos avisos no mural da igreja',
            icon: Icons.favorite_rounded,
            color: const Color(0xFFEF4444),
            gradient: const LinearGradient(
              colors: [Color(0xFFF87171), Color(0xFFEF4444)],
            ),
            child: SizedBox(
              height: 280,
              child: BarChart(
                _bars(_rows, (e) => e.likes.toDouble(), const Color(0xFFEF4444)),
              ),
            ),
          ),
          const SizedBox(height: ThemeCleanPremium.spaceLg),
          _AvisoPanelChartCard(
            title: 'Comentários por aviso',
            subtitle: widget.canModerateComments
                ? 'Pode remover comentários inadequados na lista'
                : 'Leitura das interações na comunidade',
            icon: Icons.comment_rounded,
            color: const Color(0xFF0EA5E9),
            gradient: const LinearGradient(
              colors: [Color(0xFF38BDF8), Color(0xFF0EA5E9)],
            ),
            child: SizedBox(
              height: 280,
              child: BarChart(
                _bars(
                  _rows,
                  (e) => e.comments.toDouble(),
                  const Color(0xFF0EA5E9),
                ),
              ),
            ),
          ),
          const SizedBox(height: ThemeCleanPremium.spaceLg),
          _AvisoPanelChartCard(
            title: 'Lista por aviso',
            subtitle: 'Toque num cartão para ver curtidas ou comentários',
            icon: Icons.view_list_rounded,
            color: ThemeCleanPremium.primary,
            gradient: LinearGradient(
              colors: [
                ThemeCleanPremium.primary,
                ThemeCleanPremium.primaryLight,
              ],
            ),
            child: Column(
              children: [
                for (var i = 0; i < _rows.length; i++)
                  Padding(
                    padding: EdgeInsets.only(bottom: i == _rows.length - 1 ? 0 : 10),
                    child: _AvisoListTile(
                      index: i,
                      row: _rows[i],
                      dateLabel: _fmtDate(_rows[i].createdAt),
                      onTap: () => _openEngagementMenu(context, i),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }
}

class _AvisosHeroCard extends StatelessWidget {
  final int postCount;
  final int sumLikes;
  final int sumComments;

  const _AvisosHeroCard({
    required this.postCount,
    required this.sumLikes,
    required this.sumComments,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(18, 20, 18, 20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            const Color(0xFF0D9488),
            ThemeCleanPremium.primary,
            const Color(0xFF1E3A5F),
          ],
        ),
        boxShadow: [
          BoxShadow(
            color: ThemeCleanPremium.primary.withValues(alpha: 0.32),
            blurRadius: 22,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.35),
                  ),
                ),
                child: const Icon(Icons.campaign_rounded,
                    color: Colors.white, size: 26),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  'Painel de avisos',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    fontSize: 20,
                    letterSpacing: -0.4,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Curtidas e comentários dos avisos recentes',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.9),
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              _kpiChip(Icons.article_rounded, 'Avisos', '$postCount'),
              const SizedBox(width: 10),
              _kpiChip(Icons.favorite_rounded, 'Curtidas', '$sumLikes'),
              const SizedBox(width: 10),
              _kpiChip(Icons.forum_rounded, 'Comentários', '$sumComments'),
            ],
          ),
        ],
      ),
    );
  }

  static Widget _kpiChip(IconData icon, String label, String value) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white.withValues(alpha: 0.22)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: Colors.white, size: 20),
            const SizedBox(height: 6),
            Text(
              value,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w900,
                fontSize: 20,
              ),
            ),
            Text(
              label,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.82),
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AvisoPanelChartCard extends StatelessWidget {
  final String title;
  final String? subtitle;
  final IconData icon;
  final Color color;
  final LinearGradient gradient;
  final Widget child;

  const _AvisoPanelChartCard({
    required this.title,
    this.subtitle,
    required this.icon,
    required this.color,
    required this.gradient,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final sub = subtitle;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 18),
      decoration: BoxDecoration(
        color: ThemeCleanPremium.cardBackground,
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          ...ThemeCleanPremium.softUiCardShadow,
          BoxShadow(
            color: color.withValues(alpha: 0.08),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
        border: Border.all(color: color.withValues(alpha: 0.14)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(11),
                decoration: BoxDecoration(
                  gradient: gradient,
                  borderRadius:
                      BorderRadius.circular(ThemeCleanPremium.radiusMd),
                  boxShadow: [
                    BoxShadow(
                      color: color.withValues(alpha: 0.35),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Icon(icon, color: Colors.white, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                        color: ThemeCleanPremium.onSurface,
                      ),
                    ),
                    if (sub != null && sub.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        sub,
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          color: ThemeCleanPremium.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }
}

class _AvisoListTile extends StatelessWidget {
  final int index;
  final _AvisoInsight row;
  final String dateLabel;
  final VoidCallback onTap;

  const _AvisoListTile({
    required this.index,
    required this.row,
    required this.dateLabel,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            color: Colors.white.withValues(alpha: 0.55),
            border: Border.all(
              color: ThemeCleanPremium.primary.withValues(alpha: 0.12),
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 34,
                height: 34,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  gradient: LinearGradient(
                    colors: [
                      const Color(0xFF0D9488).withValues(alpha: 0.25),
                      ThemeCleanPremium.primary.withValues(alpha: 0.15),
                    ],
                  ),
                ),
                child: Text(
                  '${index + 1}',
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      row.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 14.5,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      dateLabel,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: ThemeCleanPremium.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      children: [
                        _pill(Icons.favorite_rounded, '${row.likes}', Colors.red.shade400),
                        _pill(Icons.comment_rounded, '${row.comments}',
                            const Color(0xFF0EA5E9)),
                      ],
                    ),
                  ],
                ),
              ),
              Icon(Icons.touch_app_rounded,
                  color: ThemeCleanPremium.primary.withValues(alpha: 0.7)),
            ],
          ),
        ),
      ),
    );
  }

  static Widget _pill(IconData i, String v, Color c) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        color: c.withValues(alpha: 0.1),
        border: Border.all(color: c.withValues(alpha: 0.28)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(i, size: 14, color: c),
          const SizedBox(width: 4),
          Text(v, style: TextStyle(fontWeight: FontWeight.w900, color: c)),
        ],
      ),
    );
  }
}

class _AvisoEngagementSheet extends StatefulWidget {
  final _AvisoInsight aviso;
  final String type;
  final bool canDeleteComments;

  const _AvisoEngagementSheet({
    required this.aviso,
    required this.type,
    required this.canDeleteComments,
  });

  @override
  State<_AvisoEngagementSheet> createState() => _AvisoEngagementSheetState();
}

class _AvisoEngagementSheetState extends State<_AvisoEngagementSheet> {
  List<String> _names = [];
  bool _loading = true;
  String? _error;
  int _commentsKey = 0;

  Future<void> _loadLikes() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final snap = await widget.aviso.ref.get();
      final data = snap.data() ?? {};
      final uids = <String>[];
      for (final e in (data['likes'] as List?) ?? const []) {
        final s = e?.toString().trim();
        if (s != null && s.isNotEmpty) {
          uids.add(s);
        }
      }
      final list = <String>[];
      for (final uid in uids) {
        try {
          final u =
              await FirebaseFirestore.instance.collection('users').doc(uid).get();
          final n = (u.data()?['nome'] ??
                  u.data()?['name'] ??
                  u.data()?['displayName'] ??
                  'Membro')
              .toString();
          list.add(n.isNotEmpty ? n : uid);
        } catch (_) {
          list.add(uid);
        }
      }
      if (mounted) {
        setState(() {
          _names = list;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  @override
  void initState() {
    super.initState();
    if (widget.type == 'likes') {
      unawaited(_loadLikes());
    } else {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.type == 'likes' ? 'Curtidas' : 'Comentários';
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.58,
      maxChildSize: 0.94,
      minChildSize: 0.38,
      builder: (ctx, scroll) {
        if (widget.type == 'likes') {
          if (_loading) {
            return const Center(child: Padding(
              padding: EdgeInsets.all(32),
              child: CircularProgressIndicator(),
            ));
          }
          if (_error != null) {
            return ChurchPanelErrorBody(
              title: 'Erro ao carregar curtidas',
              error: _error,
              onRetry: _loadLikes,
            );
          }
          return Column(
            children: [
              const SizedBox(height: 8),
              Text(t,
                  style: const TextStyle(
                      fontSize: 17, fontWeight: FontWeight.w900)),
              const SizedBox(height: 8),
              Expanded(
                child: ListView.builder(
                  controller: scroll,
                  padding: const EdgeInsets.all(16),
                  itemCount: _names.length,
                  itemBuilder: (_, i) => ListTile(
                    leading: const Icon(Icons.person_rounded),
                    title: Text(_names[i]),
                  ),
                ),
              ),
            ],
          );
        }
        return Column(
          children: [
            const SizedBox(height: 8),
            Text(t,
                style:
                    const TextStyle(fontSize: 17, fontWeight: FontWeight.w900)),
            const Divider(),
            Expanded(
              child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                key: ValueKey(_commentsKey),
                stream:
                    widget.aviso.ref.collection('comentarios').snapshots(),
                builder: (context, snap) {
                  if (snap.hasError) {
                    return ChurchPanelErrorBody(
                      title: 'Comentários',
                      error: snap.error,
                      onRetry: () => setState(() => _commentsKey++),
                    );
                  }
                  if (snap.connectionState == ConnectionState.waiting &&
                      !snap.hasData) {
                    return const ChurchPanelLoadingBody();
                  }
                  final raw = snap.data?.docs ?? [];
                  final docs = List<QueryDocumentSnapshot<Map<String, dynamic>>>.from(raw);
                  docs.sort((a, b) {
                    final ta = a.data()['createdAt'];
                    final tb = b.data()['createdAt'];
                    if (ta is Timestamp && tb is Timestamp) {
                      return ta.compareTo(tb);
                    }
                    return 0;
                  });
                  if (docs.isEmpty) {
                    return const Center(child: Text('Sem comentários.'));
                  }
                  return ListView.builder(
                    controller: scroll,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    itemCount: docs.length,
                    itemBuilder: (_, i) {
                      final d = docs[i];
                      final m = d.data();
                      final author =
                          (m['authorName'] ?? m['nome'] ?? 'Anónimo').toString();
                      final text =
                          (m['text'] ?? m['texto'] ?? '').toString().trim();
                      return Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        child: ListTile(
                          title: Text(author,
                              style:
                                  const TextStyle(fontWeight: FontWeight.w700)),
                          subtitle: Text(text),
                          trailing: widget.canDeleteComments
                              ? IconButton(
                                  icon: const Icon(Icons.delete_outline_rounded),
                                  onPressed: () async {
                                    await d.reference.delete();
                                  },
                                )
                              : null,
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }
}
