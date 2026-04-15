import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:gestao_yahweh/ui/theme_clean_premium.dart';
import 'package:google_fonts/google_fonts.dart';

/// Gráficos de acessos ao domínio — dados em config/analytics e/ou analytics/domain/daily_hits.
class AdminAcessosDominioPage extends StatefulWidget {
  const AdminAcessosDominioPage({super.key});

  @override
  State<AdminAcessosDominioPage> createState() => _AdminAcessosDominioPageState();
}

class _AdminAcessosDominioPageState extends State<AdminAcessosDominioPage> {
  List<MapEntry<String, int>> _hourlyHits = [];
  List<MapEntry<String, int>> _dailyHits = [];
  List<MapEntry<String, int>> _weeklyHits = [];
  List<MapEntry<String, int>> _monthlyHits = [];
  List<MapEntry<String, int>> _yearlyHits = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
      _hourlyHits = [];
      _dailyHits = [];
      _weeklyHits = [];
      _monthlyHits = [];
      _yearlyHits = [];
    });
    try {
      final Map<String, int> hourMap = {};
      final Map<String, int> dayMap = {};
      final Map<String, int> weekMap = {};
      final Map<String, int> monthMap = {};
      final Map<String, int> yearMap = {};

      void addCount({required String kind, required String key, required int value}) {
        if (value <= 0) return;
        if (kind == 'hour') {
          hourMap[key] = (hourMap[key] ?? 0) + value;
        } else if (kind == 'day') {
          dayMap[key] = (dayMap[key] ?? 0) + value;
        } else if (kind == 'month') {
          monthMap[key] = (monthMap[key] ?? 0) + value;
        } else if (kind == 'year') {
          yearMap[key] = (yearMap[key] ?? 0) + value;
        }
      }

      DateTime? tryParseKey(String raw) {
        final k = raw.trim();
        if (k.isEmpty) return null;
        final normalized = k.contains(' ') ? k.replaceFirst(' ', 'T') : k;
        return DateTime.tryParse(normalized);
      }

      bool looksLikeHourKey(String raw) {
        final k = raw.trim();
        return RegExp(r'^\d{4}-\d{2}-\d{2}[ T]\d{2}').hasMatch(k);
      }

      bool looksLikeDayKey(String raw) =>
          RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(raw.trim());
      bool looksLikeMonthKey(String raw) =>
          RegExp(r'^\d{4}-\d{2}$').hasMatch(raw.trim());
      bool looksLikeYearKey(String raw) =>
          RegExp(r'^\d{4}$').hasMatch(raw.trim());

      void addFromAccessKey(String rawKey, int value) {
        final k = rawKey.trim();
        if (k.isEmpty) return;

        if (looksLikeHourKey(k)) {
          final dt = tryParseKey(k);
          if (dt != null) {
            final hourKey =
                '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}T${dt.hour.toString().padLeft(2, '0')}:00';
            final dayKey =
                '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
            final monthKey =
                '${dt.year}-${dt.month.toString().padLeft(2, '0')}';
            final yearKey = '${dt.year}';
            addCount(kind: 'hour', key: hourKey, value: value);
            addCount(kind: 'day', key: dayKey, value: value);
            addCount(kind: 'month', key: monthKey, value: value);
            addCount(kind: 'year', key: yearKey, value: value);
          }
          return;
        }
        if (looksLikeDayKey(k)) {
          final dt = tryParseKey(k);
          if (dt != null) {
            final dayKey = k;
            final monthKey =
                '${dt.year}-${dt.month.toString().padLeft(2, '0')}';
            final yearKey = '${dt.year}';
            addCount(kind: 'day', key: dayKey, value: value);
            addCount(kind: 'month', key: monthKey, value: value);
            addCount(kind: 'year', key: yearKey, value: value);
          }
          return;
        }
        if (looksLikeMonthKey(k)) {
          final m = k.split('-');
          if (m.length == 2) {
            final year = int.tryParse(m[0]) ?? 0;
            final month = int.tryParse(m[1]) ?? 0;
            if (year > 0 && month > 0 && month <= 12) {
              addCount(kind: 'month', key: k, value: value);
              addCount(kind: 'year', key: '$year', value: value);
            }
          }
          return;
        }
        if (looksLikeYearKey(k)) {
          addCount(kind: 'year', key: k, value: value);
          return;
        }

        final dt = tryParseKey(k);
        if (dt != null) {
          final dayKey =
              '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
          final monthKey =
              '${dt.year}-${dt.month.toString().padLeft(2, '0')}';
          final yearKey = '${dt.year}';
          addCount(kind: 'day', key: dayKey, value: value);
          addCount(kind: 'month', key: monthKey, value: value);
          addCount(kind: 'year', key: yearKey, value: value);
        }
      }

      try {
        final configSnap =
            await FirebaseFirestore.instance.doc('config/analytics').get();
        if (configSnap.exists) {
          final data = configSnap.data();
          final dynamic dailyObj =
              data?['daily'] ?? data?['daily_hits'] ?? data?['dailyHits'];
          final daily = dailyObj is Map
              ? Map<String, dynamic>.from(dailyObj)
              : null;
          if (daily != null && daily.isNotEmpty) {
            for (final e in daily.entries) {
              final v = (e.value is num)
                  ? e.value.toInt()
                  : int.tryParse(e.value.toString()) ?? 0;
              addFromAccessKey(e.key, v);
            }
          }
        }
      } catch (_) {}

      try {
        final colSnap = await FirebaseFirestore.instance
            .collection('analytics')
            .doc('domain')
            .collection('daily_hits')
            .orderBy('date', descending: true)
            .limit(400)
            .get();

        if (colSnap.docs.isNotEmpty) {
          for (final d in colSnap.docs) {
            final d2 = d.data();
            final date = (d2['date'] ?? d2['day'] ?? d2['dt'] ?? '').toString();
            final rawHits = d2['hits'] ?? d2['count'] ?? d2['value'] ?? 0;
            final hits = (rawHits is num)
                ? rawHits.toInt()
                : int.tryParse(rawHits.toString()) ?? 0;
            addFromAccessKey(date, hits);
          }
        }
      } catch (_) {}

      List<MapEntry<String, int>> limitSortedList(Map<String, int> map, int max) {
        final list = map.entries.map((e) => MapEntry(e.key, e.value)).toList()
          ..sort((a, b) => a.key.compareTo(b.key));
        if (list.length <= max) return list;
        return list.sublist(list.length - max);
      }

      int isoWeekNumber(DateTime date) {
        final thursday = date.add(Duration(days: 3 - date.weekday));
        final week1 = DateTime(thursday.year, 1, 4);
        return 1 + ((thursday.difference(week1).inDays) / 7).floor();
      }

      for (final e in dayMap.entries) {
        final dt = tryParseKey(e.key);
        if (dt == null) continue;
        final year = dt.year;
        final week = isoWeekNumber(dt);
        final weekKey = '$year-W${week.toString().padLeft(2, '0')}';
        weekMap[weekKey] = (weekMap[weekKey] ?? 0) + e.value;
      }

      final hourly = limitSortedList(hourMap, 24);
      final daily = limitSortedList(dayMap, 30);
      final weekly = limitSortedList(weekMap, 12);
      final monthly = limitSortedList(monthMap, 12);
      final yearly = limitSortedList(yearMap, 6);

      if (mounted) {
        setState(() {
          _hourlyHits = hourly;
          _dailyHits = daily;
          _weeklyHits = weekly;
          _monthlyHits = monthly;
          _yearlyHits = yearly;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = e.toString();
        });
      }
    }
  }

  bool get _isPermissionDenied =>
      _error != null &&
      (_error!.contains('permission-denied') ||
          _error!.contains('PERMISSION_DENIED'));

  @override
  Widget build(BuildContext context) {
    final padding = ThemeCleanPremium.pagePadding(context);

    return Scaffold(
      primary: false,
      backgroundColor: ThemeCleanPremium.surfaceVariant,
      body: SafeArea(
        child: ListView(
          padding: EdgeInsets.fromLTRB(
            padding.left,
            padding.top,
            padding.right,
            padding.bottom + ThemeCleanPremium.spaceXl,
          ),
          children: [
            _PageHeader(),
            const SizedBox(height: 18),
            if (_loading)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(40),
                  child: CircularProgressIndicator(),
                ),
              )
            else if (_error != null)
              _PremiumErrorCard(
                isPermissionDenied: _isPermissionDenied,
                message: _error!,
                onRetry: _load,
              )
            else if (_hourlyHits.isEmpty &&
                _dailyHits.isEmpty &&
                _weeklyHits.isEmpty &&
                _monthlyHits.isEmpty &&
                _yearlyHits.isEmpty)
              _EmptyStateCard(onRefresh: _load)
            else
              _AnalyticsTabPanel(
                hourlyHits: _hourlyHits,
                dailyHits: _dailyHits,
                weeklyHits: _weeklyHits,
                monthlyHits: _monthlyHits,
                yearlyHits: _yearlyHits,
                onRefresh: _load,
              ),
          ],
        ),
      ),
    );
  }
}

class _PageHeader extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            ThemeCleanPremium.primary,
            ThemeCleanPremium.primary.withValues(alpha: 0.88),
          ],
        ),
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: ThemeCleanPremium.primary.withValues(alpha: 0.35),
            blurRadius: 20,
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
                ),
                child: const Icon(
                  Icons.public_rounded,
                  color: Colors.white,
                  size: 26,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Acessos ao domínio',
                  style: GoogleFonts.poppins(
                    fontWeight: FontWeight.w800,
                    fontSize: 20,
                    color: Colors.white,
                    letterSpacing: -0.3,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'Visualize tráfego do site por hora, dia, semana, mês e ano. '
            'Fontes: config/analytics (daily) e analytics/domain/daily_hits.',
            style: TextStyle(
              fontSize: 14,
              height: 1.45,
              fontWeight: FontWeight.w500,
              color: Colors.white.withValues(alpha: 0.92),
            ),
          ),
        ],
      ),
    );
  }
}

class _PremiumErrorCard extends StatelessWidget {
  final bool isPermissionDenied;
  final String message;
  final VoidCallback onRetry;

  const _PremiumErrorCard({
    required this.isPermissionDenied,
    required this.message,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: ThemeCleanPremium.premiumSurfaceCard.copyWith(
        color: ThemeCleanPremium.cardBackground,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.lock_outline_rounded,
              size: 52, color: ThemeCleanPremium.error),
          const SizedBox(height: 14),
          Text(
            isPermissionDenied
                ? 'Sem permissão para analytics'
                : 'Erro ao carregar',
            style: GoogleFonts.poppins(
              fontWeight: FontWeight.w700,
              fontSize: 17,
              color: ThemeCleanPremium.onSurface,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 10),
          Text(
            isPermissionDenied
                ? 'Use conta MASTER/ADM e regras Firestore para config/analytics e analytics/domain.'
                : message,
            style: TextStyle(
              fontSize: 14,
              height: 1.4,
              color: ThemeCleanPremium.onSurfaceVariant,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 18),
          FilledButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh_rounded, size: 20),
            label: const Text('Tentar novamente'),
            style: FilledButton.styleFrom(
              backgroundColor: ThemeCleanPremium.primary,
              padding: const EdgeInsets.symmetric(
                horizontal: 22,
                vertical: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyStateCard extends StatelessWidget {
  final VoidCallback onRefresh;

  const _EmptyStateCard({required this.onRefresh});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(28),
      decoration: ThemeCleanPremium.premiumSurfaceCard.copyWith(
        color: ThemeCleanPremium.cardBackground,
      ),
      child: Column(
        children: [
          Icon(Icons.analytics_outlined,
              size: 56, color: Colors.grey.shade400),
          const SizedBox(height: 16),
          Text(
            'Nenhum dado de acesso ainda',
            style: GoogleFonts.poppins(
              fontWeight: FontWeight.w700,
              fontSize: 17,
              color: ThemeCleanPremium.onSurface,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'Os acessos são registrados quando alguém abre o site (web). '
            'Após o primeiro visitante, toque em Atualizar.',
            style: TextStyle(
              fontSize: 14,
              height: 1.45,
              color: ThemeCleanPremium.onSurfaceVariant,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 18),
          FilledButton.icon(
            onPressed: onRefresh,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('Atualizar'),
            style: FilledButton.styleFrom(
              backgroundColor: ThemeCleanPremium.primary,
            ),
          ),
        ],
      ),
    );
  }
}

class _AnalyticsTabPanel extends StatelessWidget {
  final List<MapEntry<String, int>> hourlyHits;
  final List<MapEntry<String, int>> dailyHits;
  final List<MapEntry<String, int>> weeklyHits;
  final List<MapEntry<String, int>> monthlyHits;
  final List<MapEntry<String, int>> yearlyHits;
  final VoidCallback onRefresh;

  const _AnalyticsTabPanel({
    required this.hourlyHits,
    required this.dailyHits,
    required this.weeklyHits,
    required this.monthlyHits,
    required this.yearlyHits,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 5,
      child: Container(
        decoration: ThemeCleanPremium.premiumSurfaceCard.copyWith(
          color: ThemeCleanPremium.cardBackground,
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 16, 12, 0),
              child: Row(
                children: [
                  Icon(Icons.insights_rounded,
                      color: ThemeCleanPremium.primary, size: 24),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Volume de acessos',
                      style: GoogleFonts.poppins(
                        fontWeight: FontWeight.w800,
                        fontSize: 17,
                        color: ThemeCleanPremium.onSurface,
                      ),
                    ),
                  ),
                  IconButton.filledTonal(
                    onPressed: onRefresh,
                    icon: const Icon(Icons.refresh_rounded, size: 22),
                    tooltip: 'Atualizar',
                    style: IconButton.styleFrom(
                      backgroundColor:
                          ThemeCleanPremium.primary.withValues(alpha: 0.12),
                      foregroundColor: ThemeCleanPremium.primary,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 6),
            TabBar(
              isScrollable: true,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              labelPadding: const EdgeInsets.symmetric(horizontal: 14),
              indicatorSize: TabBarIndicatorSize.tab,
              dividerColor: Colors.transparent,
              labelColor: ThemeCleanPremium.primary,
              unselectedLabelColor: const Color(0xFF64748B),
              labelStyle: GoogleFonts.poppins(
                fontWeight: FontWeight.w700,
                fontSize: 14,
              ),
              unselectedLabelStyle: GoogleFonts.poppins(
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
              indicator: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    ThemeCleanPremium.primary.withValues(alpha: 0.18),
                    ThemeCleanPremium.primary.withValues(alpha: 0.08),
                  ],
                ),
                borderRadius: BorderRadius.circular(12),
              ),
              tabs: const [
                Tab(text: 'Hora'),
                Tab(text: 'Dia'),
                Tab(text: 'Semana'),
                Tab(text: 'Mês'),
                Tab(text: 'Ano'),
              ],
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 380,
              child: TabBarView(
                children: [
                  _DomainHitsChartCard(
                    title: 'Acessos por hora',
                    accent: ThemeCleanPremium.primary,
                    data: hourlyHits,
                    emptyMessage:
                        'Sem dados por hora. O backend pode gravar só por dia.',
                    labelFromKey: (k) {
                      if (k.contains('T') && k.length >= 16) {
                        final day = k.substring(8, 10);
                        final month = k.substring(5, 7);
                        final hour = k.substring(11, 13);
                        return '$day/$month\n$hour h';
                      }
                      return k;
                    },
                  ),
                  _DomainHitsChartCard(
                    title: 'Acessos por dia',
                    accent: const Color(0xFF0284C7),
                    data: dailyHits,
                    emptyMessage: 'Sem dados por dia.',
                    labelFromKey: (k) {
                      if (k.length >= 10) return k.substring(8);
                      return k;
                    },
                  ),
                  _DomainHitsChartCard(
                    title: 'Acessos por semana',
                    accent: const Color(0xFF0D9488),
                    data: weeklyHits,
                    emptyMessage: 'Sem dados por semana (derivado do daily).',
                    labelFromKey: (k) => k.replaceFirst('-W', ' · S'),
                  ),
                  _DomainHitsChartCard(
                    title: 'Acessos por mês',
                    accent: const Color(0xFF7C3AED),
                    data: monthlyHits,
                    emptyMessage: 'Sem dados por mês.',
                    labelFromKey: (k) {
                      if (k.length >= 7) return k.substring(5);
                      return k;
                    },
                  ),
                  _DomainHitsChartCard(
                    title: 'Acessos por ano',
                    accent: const Color(0xFF4F46E5),
                    data: yearlyHits,
                    emptyMessage: 'Sem dados por ano.',
                    labelFromKey: (k) => k,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

class _DomainHitsChartCard extends StatelessWidget {
  final String title;
  final Color accent;
  final List<MapEntry<String, int>> data;
  final String emptyMessage;
  final String Function(String key) labelFromKey;

  const _DomainHitsChartCard({
    required this.title,
    required this.accent,
    required this.data,
    required this.emptyMessage,
    required this.labelFromKey,
  });

  @override
  Widget build(BuildContext context) {
    if (data.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.show_chart_rounded,
                size: 48, color: accent.withValues(alpha: 0.4)),
            const SizedBox(height: 12),
            Text(
              title,
              style: GoogleFonts.poppins(
                fontWeight: FontWeight.w800,
                fontSize: 16,
                color: ThemeCleanPremium.onSurface,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              emptyMessage,
              style: TextStyle(
                fontSize: 14,
                height: 1.4,
                color: ThemeCleanPremium.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    final maxY =
        data.map((e) => e.value).reduce((a, b) => a > b ? a : b).toDouble();
    final total = data.fold<int>(0, (a, e) => a + e.value);
    final chartMaxY = maxY <= 0 ? 1.0 : (maxY * 1.18).ceilToDouble();
    final gridInterval = chartMaxY <= 5
        ? 1.0
        : (chartMaxY / 5).clamp(1.0, double.infinity);

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            title,
            style: GoogleFonts.poppins(
              fontWeight: FontWeight.w800,
              fontSize: 16,
              color: const Color(0xFF0F172A),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Passe o mouse ou toque nas barras para ver o valor.',
            style: TextStyle(
              fontSize: 13,
              color: ThemeCleanPremium.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 14),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                return BarChart(
                  BarChartData(
                    minY: 0,
                    maxY: chartMaxY,
                    alignment: BarChartAlignment.spaceAround,
                    barTouchData: BarTouchData(
                      enabled: true,
                      handleBuiltInTouches: true,
                      touchTooltipData: BarTouchTooltipData(
                        tooltipPadding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
                        tooltipMargin: 8,
                        tooltipBgColor: const Color(0xFF1E293B),
                        getTooltipItem: (group, groupIndex, rod, rodIndex) {
                          final i = group.x.toInt();
                          if (i < 0 || i >= data.length) return null;
                          final v = data[i].value;
                          return BarTooltipItem(
                            '$v acessos',
                            GoogleFonts.poppins(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                              fontSize: 13,
                            ),
                          );
                        },
                      ),
                    ),
                    titlesData: FlTitlesData(
                      show: true,
                      topTitles: const AxisTitles(
                        sideTitles: SideTitles(showTitles: false),
                      ),
                      rightTitles: const AxisTitles(
                        sideTitles: SideTitles(showTitles: false),
                      ),
                      leftTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          reservedSize: 46,
                          interval: gridInterval,
                          getTitlesWidget: (value, meta) {
                            if (value > chartMaxY + 0.01) {
                              return const SizedBox.shrink();
                            }
                            if (value < 0) return const SizedBox.shrink();
                            final v = value;
                            if ((v - v.roundToDouble()).abs() > 0.01 &&
                                chartMaxY > 10) {
                              return const SizedBox.shrink();
                            }
                            return Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: Text(
                                v == v.roundToDouble()
                                    ? v.toInt().toString()
                                    : v.toStringAsFixed(0),
                                style: GoogleFonts.poppins(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: const Color(0xFF64748B),
                                ),
                                textAlign: TextAlign.right,
                              ),
                            );
                          },
                        ),
                      ),
                      bottomTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          reservedSize: 48,
                          getTitlesWidget: (v, meta) {
                            final i = v.toInt();
                            if (i < 0 || i >= data.length) {
                              return const SizedBox.shrink();
                            }
                            final key = data[i].key;
                            final label = labelFromKey(key);
                            return Padding(
                              padding: const EdgeInsets.only(top: 10),
                              child: Text(
                                label,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                textAlign: TextAlign.center,
                                style: GoogleFonts.poppins(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  height: 1.2,
                                  color: const Color(0xFF475569),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                    gridData: FlGridData(
                      show: true,
                      drawVerticalLine: false,
                      horizontalInterval: gridInterval,
                      getDrawingHorizontalLine: (value) => FlLine(
                        color: const Color(0xFFE2E8F0),
                        strokeWidth: 1,
                      ),
                    ),
                    borderData: FlBorderData(show: false),
                    barGroups: [
                      for (var i = 0; i < data.length; i++)
                        BarChartGroupData(
                          x: i,
                          barRods: [
                            BarChartRodData(
                              toY: data[i].value.toDouble(),
                              width: data.length <= 4 ? 28 : 14,
                              borderRadius: const BorderRadius.vertical(
                                top: Radius.circular(8),
                              ),
                              gradient: LinearGradient(
                                begin: Alignment.bottomCenter,
                                end: Alignment.topCenter,
                                colors: [
                                  accent.withValues(alpha: 0.75),
                                  accent,
                                ],
                              ),
                              backDrawRodData: BackgroundBarChartRodData(
                                show: true,
                                toY: chartMaxY,
                                color: const Color(0xFFF1F5F9),
                              ),
                            ),
                          ],
                        ),
                    ],
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: ThemeCleanPremium.primary.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: ThemeCleanPremium.primary.withValues(alpha: 0.12),
              ),
            ),
            child: Row(
              children: [
                Icon(Icons.summarize_rounded,
                    color: ThemeCleanPremium.primary, size: 22),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Total no período: $total acessos',
                    style: GoogleFonts.poppins(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFF0F172A),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
