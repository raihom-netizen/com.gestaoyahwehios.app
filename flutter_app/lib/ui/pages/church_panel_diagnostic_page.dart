import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:gestao_yahweh/services/church_aggregated_counters_service.dart';
import 'package:gestao_yahweh/services/church_context_service.dart';
import 'package:gestao_yahweh/services/church_module_firestore_audit.dart';
import 'package:gestao_yahweh/services/church_module_path_audit_service.dart';
import 'package:gestao_yahweh/services/church_operational_firestore_trace.dart';
import 'package:gestao_yahweh/services/panel_dashboard_snapshot_service.dart';
import 'package:gestao_yahweh/services/system_diagnostic_service.dart';
import 'package:gestao_yahweh/ui/theme_clean_premium.dart';

/// Configurações → Diagnóstico permanente (Firestore, Storage, tempos).
class ChurchPanelDiagnosticPage extends StatefulWidget {
  const ChurchPanelDiagnosticPage({
    super.key,
    required this.tenantId,
  });

  final String tenantId;

  @override
  State<ChurchPanelDiagnosticPage> createState() =>
      _ChurchPanelDiagnosticPageState();
}

class _ChurchPanelDiagnosticPageState extends State<ChurchPanelDiagnosticPage> {
  bool _loading = true;
  SystemDiagnosticSnapshot? _probe;
  ChurchAggregatedCounters? _counters;
  int? _dashboardMs;
  String? _error;
  List<ChurchModuleProbeResult> _moduleAudit = const [];

  @override
  void initState() {
    super.initState();
    unawaited(_runProbe());
  }

  Future<void> _runProbe() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final sw = Stopwatch()..start();
    try {
      final probe = await SystemDiagnosticService.probe(
        seedTenantId: widget.tenantId,
        userUid: FirebaseAuth.instance.currentUser?.uid,
      );
      ChurchAggregatedCounters? counters;
      int? dashMs;
      List<ChurchModuleProbeResult> moduleAudit = const [];
      try {
        final dsw = Stopwatch()..start();
        await PanelDashboardSnapshotService.readOnce(
          ChurchContextService.currentChurchId ?? widget.tenantId,
        ).timeout(const Duration(seconds: 15));
        dsw.stop();
        dashMs = dsw.elapsedMilliseconds;
        counters = await ChurchAggregatedCountersService.read(
          ChurchContextService.currentChurchId ?? widget.tenantId,
        );
      } catch (_) {}
      try {
        moduleAudit = await ChurchModulePathAuditService.probeAllModules(
          widget.tenantId,
        );
      } catch (_) {}
      if (!mounted) return;
      setState(() {
        _probe = probe;
        _counters = counters;
        _dashboardMs = dashMs;
        _moduleAudit = moduleAudit;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    } finally {
      sw.stop();
    }
  }

  Widget _row(String label, String value, {Color? valueColor}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 148,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 13,
                color: Colors.grey.shade600,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Expanded(
            child: SelectableText(
              value,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: valueColor ?? const Color(0xFF1A1A2E),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = ThemeCleanPremium.isMobile(context);
    return Scaffold(
      backgroundColor: ThemeCleanPremium.surfaceVariant,
      appBar: isMobile
          ? null
          : AppBar(
              title: const Text('Diagnóstico do painel'),
              actions: [
                IconButton(
                  icon: const Icon(Icons.refresh_rounded),
                  onPressed: _loading ? null : () => unawaited(_runProbe()),
                ),
              ],
            ),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : RefreshIndicator(
                onRefresh: _runProbe,
                child: ListView(
                  padding: ThemeCleanPremium.pagePadding(context),
                  children: [
                    if (isMobile) ...[
                      const SizedBox(height: 8),
                      Text(
                        'Diagnóstico do painel',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                      ),
                      const SizedBox(height: 16),
                    ],
                    if (_error != null)
                      Card(
                        color: Colors.red.shade50,
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Text(_error!, style: const TextStyle(color: Colors.red)),
                        ),
                      ),
                    _card(
                      'Sessão',
                      [
                        _row('churchId', _probe?.churchId ?? '—'),
                        _row('Firestore', _probe?.firestorePath ?? '—'),
                        _row('Storage', _probe?.storagePath ?? '—'),
                        _row(
                          'Contexto bound',
                          ChurchContextService.boundAt?.toIso8601String() ?? '—',
                        ),
                      ],
                    ),
                    _card(
                      'Serviços',
                      [
                        _row(
                          'Firestore',
                          (_probe?.churchId ?? '').isNotEmpty ? 'OK' : 'Pendente',
                          valueColor: (_probe?.churchId ?? '').isNotEmpty
                              ? Colors.green.shade700
                              : Colors.orange.shade800,
                        ),
                        _row('Storage', 'OK (path canónico)'),
                        _row(
                          'FCM',
                          FirebaseAuth.instance.currentUser != null
                              ? 'Sessão ativa'
                              : 'Sem login',
                        ),
                      ],
                    ),
                    _card(
                      'Tempos (ms)',
                      [
                        _row('Bootstrap', '${_probe?.bootstrapMs ?? '—'}'),
                        _row('Firestore leitura', '${_probe?.firestoreReadMs ?? '—'}'),
                        _row('Dashboard cache', '${_dashboardMs ?? '—'}'),
                        _row('Total probe', '${_probe?.loadDurationMs ?? '—'}'),
                      ],
                    ),
                    if (_counters != null)
                      _card(
                        'Contadores agregados',
                        [
                          _row('Membros', '${_counters!.membersCount}'),
                          _row('Ativos', '${_counters!.activeMembersCount}'),
                          _row('Eventos', '${_counters!.eventsCount}'),
                          _row('Avisos', '${_counters!.avisosCount}'),
                          _row('Departamentos', '${_counters!.departmentsCount}'),
                          _row('Fonte', _counters!.source),
                        ],
                      ),
                    if (_probe?.lastError != null)
                      _card(
                        'Último erro',
                        [_row('Erro', _probe!.lastError!)],
                      ),
                    if (_moduleAudit.isNotEmpty)
                      _card(
                        'Auditoria módulos (igrejas/{churchId})',
                        _moduleAudit
                            .map(
                              (m) => _row(
                                m.module,
                                m.ok
                                    ? '${m.collectionPath} · ${m.count ?? 0} docs · ${m.durationMs ?? '?'}ms'
                                    : '${m.collectionPath} · ERRO: ${m.error ?? '?'} · ${m.durationMs ?? '?'}ms',
                                valueColor: m.ok
                                    ? Colors.green.shade700
                                    : Colors.red.shade700,
                              ),
                            )
                            .toList(),
                      ),
                    if (ChurchOperationalFirestoreTrace.recent.isNotEmpty)
                      _card(
                        'Consultas recentes',
                        ChurchOperationalFirestoreTrace.recent
                            .take(8)
                            .map(
                              (t) => _row(
                                t.origin.split('.').last,
                                '${t.firestorePath} (${t.durationMs ?? '?'}ms)${t.error != null ? ' · ${t.error}' : ''}',
                              ),
                            )
                            .toList(),
                      ),
                    const SizedBox(height: 24),
                  ],
                ),
              ),
      ),
    );
  }

  Widget _card(String title, List<Widget> children) {
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusMd),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 15,
              ),
            ),
            const SizedBox(height: 8),
            ...children,
          ],
        ),
      ),
    );
  }
}
