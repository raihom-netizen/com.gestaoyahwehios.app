import 'package:gestao_yahweh/core/data/yahweh_write_batch.dart';
import 'package:flutter/material.dart';
import 'package:gestao_yahweh/core/data/church_data_paths.dart';
import 'package:gestao_yahweh/core/firebase_bootstrap.dart';
import 'package:gestao_yahweh/ui/theme_clean_premium.dart';
import 'package:gestao_yahweh/core/data/yahweh_doc_write.dart';

class MasterChurch360Metrics extends StatefulWidget {
  const MasterChurch360Metrics({
    super.key,
    required this.tenantId,
    this.churchData,
    this.onOpenModule,
  });
  final String tenantId;
  final Map<String, dynamic>? churchData;
  final ValueChanged<String>? onOpenModule;

  @override
  State<MasterChurch360Metrics> createState() => _MasterChurch360MetricsState();
}

class _MasterChurch360MetricsState extends State<MasterChurch360Metrics> {
  late Future<Map<String, int?>> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  @override
  void didUpdateWidget(covariant MasterChurch360Metrics oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.tenantId != widget.tenantId) {
      _future = _load();
    }
  }

  Future<int?> _count(String tenantId, String subcollection) async {
    try {
      final snap = await firebaseDefaultFirestore
          .collection(ChurchDataPaths.rootCollection)
          .doc(tenantId)
          .collection(subcollection)
          .count()
          .get();
      return snap.count;
    } catch (_) {
      return null;
    }
  }

  Future<Map<String, int?>> _load() async {
    final tid = widget.tenantId.trim();
    if (tid.isEmpty) return <String, int?>{};
    final names = <String, String>{
      'Membros': ChurchDataPaths.membros,
      'Cartões de membro': ChurchDataPaths.cartoes,
      'Eventos': ChurchDataPaths.eventos,
      'Visitantes': 'visitantes',
      'Orações': ChurchDataPaths.pedidosOracao,
      'Patrimônio': ChurchDataPaths.patrimonio,
      'Financeiro': ChurchDataPaths.financeiro,
    };
    final entries = await Future.wait(
      names.entries.map(
        (e) async => MapEntry(e.key, await _count(tid, e.value)),
      ),
    );
    final output = <String, int?>{for (final e in entries) e.key: e.value};
    final data = widget.churchData ?? const <String, dynamic>{};
    output['Armazenamento'] = _storageBytes(data);
    return output;
  }

  int? _storageBytes(Map<String, dynamic> data) {
    for (final key in const [
      'storageBytes',
      'storageUsedBytes',
      'storageBytesTotal',
    ]) {
      final value = data[key];
      if (value is num) return value.toInt();
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, int?>>(
      future: _future,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting && !snap.hasData) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
          );
        }
        final values = snap.data ?? const <String, int?>{};
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Visão 360° da igreja',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: values.entries.map((entry) {
                final label = entry.key;
                final value = entry.value;
                final icon = _iconFor(label);
                return SizedBox(
                  width: 155,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(16),
                    onTap: widget.onOpenModule == null
                        ? null
                        : () => widget.onOpenModule!(label),
                    child: Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: ThemeCleanPremium.primary.withValues(
                            alpha: 0.10,
                          ),
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            icon,
                            color: ThemeCleanPremium.primary,
                            size: 20,
                          ),
                          const SizedBox(width: 9),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  label,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  _formatValue(label, value),
                                  style: const TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w800,
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
              }).toList(),
            ),
            if (snap.hasError) ...[
              const SizedBox(height: 8),
              Text(
                'Algumas métricas não puderam ser atualizadas agora.',
                style: TextStyle(fontSize: 12, color: Colors.orange),
              ),
            ],
          ],
        );
      },
    );
  }

  IconData _iconFor(String label) {
    switch (label) {
      case 'Membros':
        return Icons.groups_rounded;
      case 'Cartões de membro':
        return Icons.badge_rounded;
      case 'Eventos':
        return Icons.event_rounded;
      case 'Visitantes':
        return Icons.person_add_alt_1_rounded;
      case 'Orações':
        return Icons.volunteer_activism_rounded;
      case 'Patrimônio':
        return Icons.inventory_2_rounded;
      case 'Financeiro':
        return Icons.account_balance_wallet_rounded;
      default:
        return Icons.cloud_queue_rounded;
    }
  }

  String _formatValue(String label, int? value) {
    if (value == null) return '—';
    if (label != 'Armazenamento') return value.toString();
    if (value < 1024 * 1024) return '${(value / 1024).toStringAsFixed(0)} KB';
    if (value < 1024 * 1024 * 1024) {
      return '${(value / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(value / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }
}

abstract final class MasterPlanAlertPersistence {
  static Future<void> ensure({
    required String tenantId,
    required String plan,
    required int memberCount,
  }) async {
    final tid = tenantId.trim();
    if (tid.isEmpty) return;
    final limit = _limitFor(plan);
    if (limit == null) {
      return;
    }
    final remaining = limit - memberCount;
    final shouldWarn = remaining <= 5;
    final severity = remaining < 0
        ? 'blocked'
        : (shouldWarn ? 'near_limit' : 'normal');
    final message = remaining < 0
        ? 'O limite de membros do plano foi ultrapassado. A igreja precisa mudar de plano.'
        : shouldWarn
        ? 'Faltam $remaining membro(s) para atingir o limite do plano. Avalie a mudança de plano.'
        : 'Uso do plano dentro do limite.';
    final now = YahwehFv.serverTimestamp;
    final churchRef = firebaseDefaultFirestore
        .collection(ChurchDataPaths.rootCollection)
        .doc(tid)
        .collection('administrativo')
        .doc('plan_alerts');
    final masterRef = firebaseDefaultFirestore
        .collection('master_alerts')
        .doc('plan_$tid');
    final payload = <String, dynamic>{
      'tenantId': tid,
      'plan': plan,
      'memberCount': memberCount,
      'memberLimit': limit,
      'remaining': remaining,
      'severity': severity,
      'message': message,
      'active': shouldWarn,
      'updatedAt': now,
    };
    await Future.wait([
      YahwehDocWrite.set(churchRef, payload),
      YahwehDocWrite.set(masterRef, {
        ...payload,
        'audience': 'master',
      }),
    ]);
  }

  static int? _limitFor(String plan) {
    final p = plan.trim().toLowerCase();
    if (p.contains('ouro') || p.contains('gold')) return null;
    if (p.contains('prata') || p.contains('silver')) return 500;
    return 100;
  }
}
