import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'dart:async' show unawaited;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:gestao_yahweh/services/billing_license_service.dart';
import 'package:gestao_yahweh/services/master_dashboard_cache_service.dart';
import 'package:gestao_yahweh/services/panel_dashboard_snapshot_service.dart';
import 'package:gestao_yahweh/services/subscription_guard.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:gestao_yahweh/ui/admin_menu_lateral.dart';
import 'package:gestao_yahweh/ui/theme_clean_premium.dart';
import 'package:gestao_yahweh/ui/widgets/master_premium_surfaces.dart';
import 'package:intl/intl.dart';

/// Ficha Super Premium da igreja (ações, saúde, timeline, notas internas).
class MasterChurchDetailSheet extends StatefulWidget {
  const MasterChurchDetailSheet({
    super.key,
    required this.tenantId,
    required this.churchData,
    this.onNavigateTo,
  });

  final String tenantId;
  final Map<String, dynamic> churchData;
  final void Function(AdminMenuItem item)? onNavigateTo;

  static Future<void> show(
    BuildContext context, {
    required String tenantId,
    required Map<String, dynamic> churchData,
    void Function(AdminMenuItem item)? onNavigateTo,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: ThemeCleanPremium.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(ctx).bottom,
        ),
        child: SizedBox(
          height: MediaQuery.sizeOf(ctx).height * 0.85,
          child: MasterChurchDetailSheet(
            tenantId: tenantId,
            churchData: churchData,
            onNavigateTo: onNavigateTo,
          ),
        ),
      ),
    );
  }

  @override
  State<MasterChurchDetailSheet> createState() => _MasterChurchDetailSheetState();
}

class _MasterChurchDetailSheetState extends State<MasterChurchDetailSheet> {
  final _notesCtrl = TextEditingController();
  bool _busy = false;
  int? _membersTotal;
  String? _panelCacheLabel;
  bool _panelCacheStale = true;

  @override
  void initState() {
    super.initState();
    final n = (widget.churchData['masterNotes'] ?? '').toString();
    _notesCtrl.text = n;
    unawaited(_loadTechnicalHealth());
  }

  Future<void> _loadTechnicalHealth() async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection('igrejas')
          .doc(widget.tenantId)
          .get();
      final data = snap.data() ?? widget.churchData;
      final total = data['membersTotalCount'] ?? data['totalMembros'];
      int? members;
      if (total is num) {
        members = total.toInt();
      }

      final cache = await PanelDashboardSnapshotService.readOnce(
        widget.tenantId,
      );
      if (members == null && cache.membersTotalCount > 0) {
        members = cache.membersTotalCount;
      }
      String? label;
      var stale = true;
      if (cache.cacheUpdatedAt != null) {
        final dt = cache.cacheUpdatedAt!.toDate();
        final diff = DateTime.now().difference(dt);
        if (diff.inHours < 24) {
          label = diff.inMinutes < 120
              ? 'Painel igreja: há ${diff.inMinutes} min'
              : 'Painel igreja: há ${diff.inHours} h';
          stale = diff.inHours >= 24;
        } else {
          label = 'Painel igreja: desatualizado';
        }
      } else {
        label = 'Painel igreja: sem cache';
      }

      if (!mounted) return;
      setState(() {
        _membersTotal = members;
        _panelCacheLabel = label;
        _panelCacheStale = stale;
      });
    } catch (_) {}
  }

  Future<void> _warmPanelCache() async {
    setState(() => _busy = true);
    try {
      await MasterDashboardCacheService.warmChurchPanel(widget.tenantId);
      await _loadTechnicalHealth();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          ThemeCleanPremium.successSnackBar(
            'Cache do painel da igreja atualizado.',
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          ThemeCleanPremium.feedbackSnackBar('Erro ao atualizar painel: $e'),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _openChurchWeb() async {
    final slug = (widget.churchData['slug'] ??
            widget.churchData['slugId'] ??
            '')
        .toString()
        .trim();
    final url = slug.isNotEmpty
        ? Uri.parse('https://gestaoyahweh-21e23.web.app/igreja/$slug')
        : Uri.parse('https://gestaoyahweh-21e23.web.app');
    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    }
  }

  @override
  void dispose() {
    _notesCtrl.dispose();
    super.dispose();
  }

  String get _nome =>
      (widget.churchData['nome'] ?? widget.churchData['name'] ?? widget.tenantId)
          .toString();

  MasterChurchHealth _health() {
    final g = SubscriptionGuard.evaluate(church: widget.churchData);
    if (g.isFree) return MasterChurchHealth.free;
    if (g.adminBlocked || g.blocked) return MasterChurchHealth.critical;
    if (g.inGrace || g.statusAssinatura == 'overdue') {
      return MasterChurchHealth.warning;
    }
    return MasterChurchHealth.ok;
  }

  Future<void> _audit(String action, String details) async {
    try {
      final u = FirebaseAuth.instance.currentUser;
      await FirebaseFirestore.instance.collection('auditoria').add({
        'acao': action,
        'resource': 'master_church_detail',
        'tenantId': widget.tenantId,
        'details': details,
        'usuario': u?.email ?? u?.uid ?? 'master',
        'uid': u?.uid,
        'data': FieldValue.serverTimestamp(),
      });
    } catch (_) {}
  }

  Future<void> _setFree(bool free) async {
    setState(() => _busy = true);
    try {
      if (free) {
        await BillingLicenseService().setTenantFreeMaster(widget.tenantId);
      } else {
        await FirebaseFirestore.instance
            .collection('igrejas')
            .doc(widget.tenantId)
            .set({
          'license': {'isFree': false, 'updatedAt': FieldValue.serverTimestamp()},
        }, SetOptions(merge: true));
      }
      await _audit('master_set_free', 'free=$free');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          ThemeCleanPremium.successSnackBar(
            free ? 'Igreja marcada como FREE.' : 'FREE removido.',
          ),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          ThemeCleanPremium.feedbackSnackBar('Erro: $e'),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _saveNotes() async {
    setState(() => _busy = true);
    try {
      await FirebaseFirestore.instance
          .collection('igrejas')
          .doc(widget.tenantId)
          .set({
        'masterNotes': _notesCtrl.text.trim(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      await _audit('master_notes', 'len=${_notesCtrl.text.length}');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          ThemeCleanPremium.successSnackBar('Notas internas salvas.'),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final df = DateFormat('dd/MM/yyyy');
    final plano = (widget.churchData['plano'] ?? widget.churchData['planId'] ?? '—')
        .toString();
    final dv = widget.churchData['dataVencimento'] ?? widget.churchData['vencimento'];
    String venc = '—';
    if (dv is Timestamp) venc = df.format(dv.toDate());

    return Padding(
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
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: Text(
                  _nome,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 18,
                  ),
                ),
              ),
              MasterHealthChip(health: _health()),
            ],
          ),
          const SizedBox(height: 4),
          SelectableText(
            widget.tenantId,
            style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
          ),
          Text('Plano: $plano · Venc.: $venc',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade700)),
          if (_membersTotal != null)
            Text(
              'Membros (resumo): $_membersTotal',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
            ),
          if (_panelCacheLabel != null) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                Icon(
                  _panelCacheStale
                      ? Icons.warning_amber_rounded
                      : Icons.check_circle_outline_rounded,
                  size: 16,
                  color: _panelCacheStale
                      ? Colors.orange.shade800
                      : Colors.green.shade700,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    _panelCacheLabel!,
                    style: TextStyle(
                      fontSize: 12,
                      color: _panelCacheStale
                          ? Colors.orange.shade900
                          : Colors.green.shade800,
                    ),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.tonalIcon(
                onPressed: _busy ? null : () => _setFree(true),
                icon: const Icon(Icons.volunteer_activism_rounded, size: 18),
                label: const Text('FREE'),
              ),
              FilledButton.tonalIcon(
                onPressed: _busy ? null : () => _setFree(false),
                icon: const Icon(Icons.paid_rounded, size: 18),
                label: const Text('Remover FREE'),
              ),
              OutlinedButton.icon(
                onPressed: _busy
                    ? null
                    : () {
                        Navigator.pop(context);
                        widget.onNavigateTo?.call(AdminMenuItem.igrejasPlanos);
                      },
                icon: const Icon(Icons.credit_card_rounded, size: 18),
                label: const Text('Planos'),
              ),
              OutlinedButton.icon(
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: widget.tenantId));
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('ID copiado.')),
                    );
                  }
                },
                icon: const Icon(Icons.copy_rounded, size: 18),
                label: const Text('Copiar ID'),
              ),
              OutlinedButton.icon(
                onPressed: _busy ? null : _warmPanelCache,
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: const Text('Atualizar painel'),
              ),
              OutlinedButton.icon(
                onPressed: _openChurchWeb,
                icon: const Icon(Icons.open_in_new_rounded, size: 18),
                label: const Text('Abrir web'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _notesCtrl,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: 'Notas internas (só master)',
              border: OutlineInputBorder(),
            ),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: _busy ? null : _saveNotes,
              child: const Text('Salvar notas'),
            ),
          ),
          const SizedBox(height: 8),
          const Text('Timeline recente',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
          const SizedBox(height: 8),
          Expanded(
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: FirebaseFirestore.instance
                  .collection('auditoria')
                  .limit(80)
                  .snapshots(),
              builder: (context, snap) {
                final docs = (snap.data?.docs ?? [])
                    .where((d) {
                      final data = d.data();
                      final tid = (data['tenantId'] ?? '').toString();
                      final det = (data['details'] ?? '').toString();
                      return tid == widget.tenantId ||
                          det.contains(widget.tenantId);
                    })
                    .take(12)
                    .toList();
                if (docs.isEmpty) {
                  return Text(
                    'Sem eventos de auditoria para este tenant.',
                    style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
                  );
                }
                return ListView.separated(
                  itemCount: docs.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (_, i) {
                    final d = docs[i].data();
                    final ts = d['data'];
                    final when = ts is Timestamp
                        ? df.format(ts.toDate())
                        : '';
                    return ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        (d['acao'] ?? d['action'] ?? 'evento').toString(),
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                      ),
                      subtitle: Text(
                        '${d['details'] ?? ''}',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 12),
                      ),
                      trailing: Text(when, style: const TextStyle(fontSize: 11)),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
