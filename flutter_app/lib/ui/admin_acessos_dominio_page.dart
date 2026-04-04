import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:gestao_yahweh/ui/theme_clean_premium.dart';

/// Gráficos de acessos ao domínio — exibe acessos/dia quando o backend grava em config/analytics ou analytics/daily_hits (estilo Controle Total).
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
        // key normalizado já deve ser lexicograficamente ordenável (ex.: YYYY-MM-DD / YYYY-MM / YYYY).
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

      DateTime? _tryParseKey(String raw) {
        final k = raw.trim();
        if (k.isEmpty) return null;
        final normalized = k.contains(' ') ? k.replaceFirst(' ', 'T') : k;
        return DateTime.tryParse(normalized);
      }

      bool _looksLikeHourKey(String raw) {
        final k = raw.trim();
        // YYYY-MM-DDTHH...
        return RegExp(r'^\d{4}-\d{2}-\d{2}[ T]\d{2}').hasMatch(k);
      }

      bool _looksLikeDayKey(String raw) => RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(raw.trim());
      bool _looksLikeMonthKey(String raw) => RegExp(r'^\d{4}-\d{2}$').hasMatch(raw.trim());
      bool _looksLikeYearKey(String raw) => RegExp(r'^\d{4}$').hasMatch(raw.trim());

      void addFromAccessKey(String rawKey, int value) {
        final k = rawKey.trim();
        if (k.isEmpty) return;

        // Caso o backend grave diretamente por hora/dia/mês/ano em `daily` (campo daily),
        // a gente tenta classificar pela chave.
        if (_looksLikeHourKey(k)) {
          final dt = _tryParseKey(k);
          if (dt != null) {
            final hourKey = '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}T${dt.hour.toString().padLeft(2, '0')}:00';
            final dayKey = '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
            final monthKey = '${dt.year}-${dt.month.toString().padLeft(2, '0')}';
            final yearKey = '${dt.year}';
            addCount(kind: 'hour', key: hourKey, value: value);
            addCount(kind: 'day', key: dayKey, value: value);
            addCount(kind: 'month', key: monthKey, value: value);
            addCount(kind: 'year', key: yearKey, value: value);
          }
          return;
        }
        if (_looksLikeDayKey(k)) {
          final dt = _tryParseKey(k);
          if (dt != null) {
            final dayKey = k;
            final monthKey = '${dt.year}-${dt.month.toString().padLeft(2, '0')}';
            final yearKey = '${dt.year}';
            addCount(kind: 'day', key: dayKey, value: value);
            addCount(kind: 'month', key: monthKey, value: value);
            addCount(kind: 'year', key: yearKey, value: value);
          }
          return;
        }
        if (_looksLikeMonthKey(k)) {
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
        if (_looksLikeYearKey(k)) {
          addCount(kind: 'year', key: k, value: value);
          return;
        }

        // Fallback: tenta parse de DateTime completo (se for datetime com hora)
        final dt = _tryParseKey(k);
        if (dt != null) {
          final dayKey = '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
          final monthKey = '${dt.year}-${dt.month.toString().padLeft(2, '0')}';
          final yearKey = '${dt.year}';
          addCount(kind: 'day', key: dayKey, value: value);
          addCount(kind: 'month', key: monthKey, value: value);
          addCount(kind: 'year', key: yearKey, value: value);
        }
      }

      // 1) Tentar config/analytics com mapa daily: { "YYYY-MM-DD": count }.
      try {
        final configSnap = await FirebaseFirestore.instance.doc('config/analytics').get();
        if (configSnap.exists) {
          final data = configSnap.data();
          final dynamic dailyObj = data?['daily'] ?? data?['daily_hits'] ?? data?['dailyHits'];
          final daily = dailyObj is Map ? Map<String, dynamic>.from(dailyObj as Map) : null;
          if (daily != null && daily.isNotEmpty) {
            for (final e in daily.entries) {
              final v = (e.value is num) ? e.value.toInt() : int.tryParse(e.value.toString()) ?? 0;
              addFromAccessKey(e.key, v);
            }
          }
        }
      } catch (_) {
        // permissão/erro: continua e tenta a collection
      }

      // 2) Tentar collection analytics/domain/daily_hits (docs: date e hits).
      // Se vierem com hora no campo date, o gráfico de hora também aparece.
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
      } catch (_) {
        // continua
      }

      // Converter mapas → listas ordenadas
      List<MapEntry<String, int>> _limitList(Map<String, int> map, int max) {
        final list = map.entries.map((e) => MapEntry(e.key, e.value)).toList()
          ..sort((a, b) => a.key.compareTo(b.key));
        if (list.length <= max) return list;
        return list.sublist(list.length - max);
      }

      int _isoWeekNumber(DateTime date) {
        // ISO week: semana começa na segunda e a semana 01 é a que contém a primeira quinta do ano.
        final thursday = date.add(Duration(days: 3 - date.weekday));
        final week1 = DateTime(thursday.year, 1, 4);
        return 1 + ((thursday.difference(week1).inDays) / 7).floor();
      }

      // Agrega semanal a partir de `dayMap`.
      for (final e in dayMap.entries) {
        final dt = _tryParseKey(e.key);
        if (dt == null) continue;
        final year = dt.year;
        final week = _isoWeekNumber(dt);
        final weekKey = '${year}-W${week.toString().padLeft(2, '0')}';
        weekMap[weekKey] = (weekMap[weekKey] ?? 0) + e.value;
      }

      final hourly = _limitList(hourMap, 24);
      final daily = _limitList(dayMap, 30);
      final weekly = _limitList(weekMap, 12);
      final monthly = _limitList(monthMap, 12);
      final yearly = _limitList(yearMap, 6);

      // Se a fonte foi só diário e não tinha horas, `_hourlyHits` vai ficar vazio, mas os outros devem aparecer.
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
      if (mounted) setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  bool get _isPermissionDenied =>
      _error != null && (_error!.contains('permission-denied') || _error!.contains('PERMISSION_DENIED'));

  @override
  Widget build(BuildContext context) {
    final padding = ThemeCleanPremium.pagePadding(context);
    return Scaffold(
      primary: false,
      backgroundColor: ThemeCleanPremium.surfaceVariant,
      body: SafeArea(
        child: ListView(
          padding: EdgeInsets.fromLTRB(padding.left, padding.top, padding.right, padding.bottom + ThemeCleanPremium.spaceXl),
          children: [
            Text(
              'Acessos ao domínio',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 20, color: ThemeCleanPremium.onSurface),
            ),
          const SizedBox(height: 8),
          Text(
            'Gráficos de acessos ao site/domínio (Hora, Dia, Semana, Mês e Ano). Os dados vêm do backend (config/analytics.daily e/ou analytics/domain/daily_hits).',
            style: TextStyle(color: Colors.grey.shade700, fontSize: 13),
          ),
          const SizedBox(height: 24),
          if (_loading)
            const Center(child: Padding(padding: EdgeInsets.all(32), child: CircularProgressIndicator()))
          else if (_error != null)
            Card(
              elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusMd)),
              child: Padding(
                padding: const EdgeInsets.all(ThemeCleanPremium.spaceLg),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.lock_outline_rounded, size: 56, color: ThemeCleanPremium.error),
                    const SizedBox(height: ThemeCleanPremium.spaceMd),
                    Text(
                      _isPermissionDenied
                          ? 'Sem permissão para acessar os dados de analytics.'
                          : 'Erro ao carregar',
                      style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16, color: ThemeCleanPremium.onSurface),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _isPermissionDenied
                          ? 'Faça login como administrador (Painel Master) e publique as regras do Firestore que permitem leitura de config/analytics e da collection analytics para usuários ADM/MASTER.'
                          : _error!,
                      style: TextStyle(fontSize: 13, color: ThemeCleanPremium.onSurfaceVariant),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: ThemeCleanPremium.spaceMd),
                    FilledButton.icon(
                      onPressed: _load,
                      icon: const Icon(Icons.refresh_rounded, size: 20),
                      label: const Text('Tentar novamente'),
                      style: FilledButton.styleFrom(
                        backgroundColor: ThemeCleanPremium.primary,
                        padding: const EdgeInsets.symmetric(horizontal: ThemeCleanPremium.spaceLg, vertical: ThemeCleanPremium.spaceSm),
                      ),
                    ),
                  ],
                ),
              ),
            )
          else if (_hourlyHits.isEmpty && _dailyHits.isEmpty && _weeklyHits.isEmpty && _monthlyHits.isEmpty && _yearlyHits.isEmpty)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  children: [
                    Icon(Icons.show_chart_rounded, size: 56, color: Colors.grey.shade400),
                    const SizedBox(height: 16),
                    Text(
                      'Nenhum dado de acesso ainda.',
                      style: TextStyle(fontWeight: FontWeight.w600, color: Colors.grey.shade700),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Configure no backend o registro de acessos ao domínio (ex.: gravar em config/analytics com campo daily: { "YYYY-MM-DD": quantidade }) ou na collection analytics/domain/daily_hits (documentos com date e hits) para exibir o gráfico aqui.',
                      style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    TextButton.icon(
                      onPressed: _load,
                      icon: const Icon(Icons.refresh_rounded),
                      label: const Text('Atualizar'),
                    ),
                  ],
                ),
              ),
            )
          else
            DefaultTabController(
              length: 5,
              child: Card(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusMd)),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Acessos', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                          TextButton.icon(
                            onPressed: _load,
                            icon: const Icon(Icons.refresh_rounded, size: 18),
                            label: const Text('Atualizar'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      TabBar(
                        isScrollable: true,
                        indicator: BoxDecoration(
                          color: ThemeCleanPremium.primary.withOpacity(0.15),
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
                      const SizedBox(height: 14),
                      SizedBox(
                        height: 320,
                        child: TabBarView(
                          children: [
                            _DomainHitsChartCard(
                              title: 'Acessos por hora',
                              accent: ThemeCleanPremium.primary,
                              data: _hourlyHits,
                              emptyMessage: 'Sem dados por hora. O backend pode estar gravando apenas por dia.',
                              labelFromKey: (k) {
                                if (k.contains('T') && k.length >= 16) {
                                  final day = k.substring(8, 10);
                                  final month = k.substring(5, 7);
                                  final hour = k.substring(11, 13);
                                  return '$day/$month $hour:00';
                                }
                                return k;
                              },
                            ),
                            _DomainHitsChartCard(
                              title: 'Acessos por dia',
                              accent: ThemeCleanPremium.primary,
                              data: _dailyHits,
                              emptyMessage: 'Sem dados por dia (ajuste o backend para preencher daily).',
                              labelFromKey: (k) {
                                if (k.length >= 10) return k.substring(5);
                                return k;
                              },
                            ),
                            _DomainHitsChartCard(
                              title: 'Acessos por semana',
                              accent: Colors.teal.shade600,
                              data: _weeklyHits,
                              emptyMessage: 'Sem dados por semana (agregação feita a partir do daily).',
                              labelFromKey: (k) => k.replaceFirst('-W', ' W'),
                            ),
                            _DomainHitsChartCard(
                              title: 'Acessos por mês',
                              accent: Colors.teal.shade600,
                              data: _monthlyHits,
                              emptyMessage: 'Sem dados por mês.',
                              labelFromKey: (k) {
                                if (k.length >= 7) return k.substring(5);
                                return k;
                              },
                            ),
                            _DomainHitsChartCard(
                              title: 'Acessos por ano',
                              accent: Colors.indigo.shade600,
                              data: _yearlyHits,
                              emptyMessage: 'Sem dados por ano.',
                              labelFromKey: (k) => k,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
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
      return Card(
        elevation: 0,
        color: ThemeCleanPremium.cardBackground,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.show_chart_rounded, size: 56, color: accent.withOpacity(0.35)),
              const SizedBox(height: 14),
              Text(title, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: ThemeCleanPremium.onSurface)),
              const SizedBox(height: 10),
              Text(emptyMessage, style: TextStyle(fontSize: 12, color: Colors.grey.shade600), textAlign: TextAlign.center),
            ],
          ),
        ),
      );
    }

    final maxY = data.map((e) => e.value).reduce((a, b) => a > b ? a : b).toDouble();
    final total = data.fold<int>(0, (a, e) => a + e.value);

    return Card(
      elevation: 0,
      color: ThemeCleanPremium.cardBackground,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: ThemeCleanPremium.onSurface)),
            const SizedBox(height: 10),
            SizedBox(
              height: 220,
              child: BarChart(
                BarChartData(
                  alignment: BarChartAlignment.spaceAround,
                  maxY: (maxY * 1.2) + 1,
                  barTouchData: BarTouchData(enabled: true),
                  titlesData: FlTitlesData(
                    leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 36)),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        getTitlesWidget: (v, meta) {
                          final i = v.toInt();
                          if (i >= 0 && i < data.length) {
                            final key = data[i].key;
                            return Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: Text(
                                labelFromKey(key),
                                style: TextStyle(fontSize: 9, color: Colors.grey.shade700),
                              ),
                            );
                          }
                          return const SizedBox();
                        },
                      ),
                    ),
                    topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  ),
                  gridData: FlGridData(show: true, drawVerticalLine: false),
                  borderData: FlBorderData(show: false),
                  barGroups: [
                    for (var i = 0; i < data.length; i++)
                      BarChartGroupData(
                        x: i,
                        barRods: [
                          BarChartRodData(
                            toY: data[i].value.toDouble(),
                            color: accent,
                            width: 12,
                            borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
                          ),
                        ],
                        showingTooltipIndicators: const [0],
                      )
                  ],
                ),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              'Total no período: $total acessos',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey.shade700),
            ),
          ],
        ),
      ),
    );
  }
}
