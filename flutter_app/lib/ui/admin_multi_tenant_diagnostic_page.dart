import 'dart:async';

import 'package:flutter/material.dart';
import 'package:gestao_yahweh/core/firebase_bootstrap.dart';
import 'package:gestao_yahweh/services/multi_tenant_diagnostic_service.dart';
import 'package:gestao_yahweh/ui/theme_clean_premium.dart';
import 'package:gestao_yahweh/ui/widgets/master_premium_surfaces.dart';
import 'package:google_fonts/google_fonts.dart';

/// Diagnóstico Multi-Tenant — Painel Master (Regra 7).
class AdminMultiTenantDiagnosticPage extends StatefulWidget {
  const AdminMultiTenantDiagnosticPage({super.key});

  @override
  State<AdminMultiTenantDiagnosticPage> createState() =>
      _AdminMultiTenantDiagnosticPageState();
}

class _AdminMultiTenantDiagnosticPageState
    extends State<AdminMultiTenantDiagnosticPage> {
  final _churchCtrl = TextEditingController();
  List<MultiTenantCheckResult> _checks = [];
  bool _loading = false;

  @override
  void dispose() {
    _churchCtrl.dispose();
    super.dispose();
  }

  Future<void> _run() async {
    setState(() => _loading = true);
    try {
      final list = await MultiTenantDiagnosticService.runFull(
        churchSeedId: _churchCtrl.text.trim(),
      );
      if (!mounted) return;
      setState(() {
        _checks = list;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void initState() {
    super.initState();
    unawaited(_run());
  }

  Color _statusColor(MultiTenantCheckStatus s) {
    switch (s) {
      case MultiTenantCheckStatus.ok:
        return const Color(0xFF16A34A);
      case MultiTenantCheckStatus.warn:
        return const Color(0xFFD97706);
      case MultiTenantCheckStatus.error:
        return ThemeCleanPremium.error;
      case MultiTenantCheckStatus.loading:
        return Colors.grey;
    }
  }

  IconData _statusIcon(MultiTenantCheckStatus s) {
    switch (s) {
      case MultiTenantCheckStatus.ok:
        return Icons.check_circle_rounded;
      case MultiTenantCheckStatus.warn:
        return Icons.warning_amber_rounded;
      case MultiTenantCheckStatus.error:
        return Icons.error_rounded;
      case MultiTenantCheckStatus.loading:
        return Icons.hourglass_top_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    final pad = ThemeCleanPremium.pagePadding(context);
    final user = firebaseDefaultAuth.currentUser;
    final allOk = _checks.isNotEmpty &&
        _checks.every((c) => c.status == MultiTenantCheckStatus.ok);

    return SafeArea(
      child: RefreshIndicator(
        onRefresh: _run,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(
            parent: BouncingScrollPhysics(),
          ),
          slivers: [
            SliverPadding(
              padding: pad,
              sliver: SliverToBoxAdapter(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    MasterPremiumCard(
                      expandWidth: true,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    colors: [
                                      ThemeCleanPremium.primary,
                                      ThemeCleanPremium.primaryLight,
                                    ],
                                  ),
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                child: const Icon(
                                  Icons.hub_rounded,
                                  color: Colors.white,
                                  size: 26,
                                ),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Text(
                                  'Diagnóstico Multi-Tenant',
                                  style: GoogleFonts.poppins(
                                    fontWeight: FontWeight.w900,
                                    fontSize: 18,
                                  ),
                                ),
                              ),
                              if (_loading)
                                const SizedBox(
                                  width: 22,
                                  height: 22,
                                  child:
                                      CircularProgressIndicator(strokeWidth: 2),
                                ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Text(
                            'Valida Auth, users, alias, ID canónico, regras Firestore, cadastro, departamentos e cargos.',
                            style: TextStyle(
                              fontSize: 13,
                              color: ThemeCleanPremium.onSurfaceVariant,
                              height: 1.4,
                            ),
                          ),
                          if (user != null) ...[
                            const SizedBox(height: 8),
                            Text(
                              'Sessão: ${user.email ?? user.uid}',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey.shade600,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: _churchCtrl,
                      decoration: InputDecoration(
                        labelText: 'ID ou alias da igreja (teste)',
                        hintText: 'ex.: brasilparacristo_sistema',
                        filled: true,
                        fillColor: Colors.white,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    FilledButton.icon(
                      onPressed: _loading ? null : _run,
                      icon: const Icon(Icons.play_arrow_rounded),
                      label: const Text('Executar diagnóstico'),
                    ),
                    if (_checks.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 12,
                        ),
                        decoration: BoxDecoration(
                          color: allOk
                              ? const Color(0xFFDCFCE7)
                              : const Color(0xFFFFF7ED),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: allOk
                                ? const Color(0xFF86EFAC)
                                : const Color(0xFFFED7AA),
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              allOk
                                  ? Icons.verified_rounded
                                  : Icons.info_outline_rounded,
                              color: allOk
                                  ? const Color(0xFF166534)
                                  : const Color(0xFF9A3412),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                allOk
                                    ? 'Tudo verde — tenant e leituras OK.'
                                    : 'Revise itens amarelos/vermelhos abaixo.',
                                style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  color: allOk
                                      ? const Color(0xFF166534)
                                      : const Color(0xFF9A3412),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            SliverPadding(
              padding: EdgeInsets.fromLTRB(pad.left, 8, pad.right, pad.bottom + 24),
              sliver: SliverList.separated(
                itemCount: _checks.length,
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (context, i) {
                  final c = _checks[i];
                  final color = _statusColor(c.status);
                  return Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: ThemeCleanPremium.softUiCardShadow,
                      border: Border.all(
                        color: color.withValues(alpha: 0.35),
                        width: c.status == MultiTenantCheckStatus.ok ? 1 : 1.5,
                      ),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(_statusIcon(c.status), color: color, size: 26),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                c.label,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 15,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                c.detail,
                                style: TextStyle(
                                  fontSize: 12.5,
                                  height: 1.4,
                                  color: Colors.grey.shade700,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
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
