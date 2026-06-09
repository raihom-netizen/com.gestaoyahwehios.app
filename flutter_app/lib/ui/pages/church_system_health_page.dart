import 'dart:async' show unawaited;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:gestao_yahweh/core/repositories/church_repository.dart';
import 'package:gestao_yahweh/services/church_panel_health_service.dart';
import 'package:gestao_yahweh/services/system_health_service.dart';
import 'package:gestao_yahweh/ui/theme_clean_premium.dart';

/// Configurações → Saúde do Sistema (painel igreja).
class ChurchSystemHealthPage extends StatefulWidget {
  const ChurchSystemHealthPage({
    super.key,
    required this.tenantId,
  });

  final String tenantId;

  @override
  State<ChurchSystemHealthPage> createState() => _ChurchSystemHealthPageState();
}

class _ChurchSystemHealthPageState extends State<ChurchSystemHealthPage> {
  ChurchPanelHealthSnapshot? _snapshot;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_refresh());
  }

  Future<void> _refresh() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final snap = await ChurchPanelHealthService.probe(
        churchIdHint: widget.tenantId,
        requireAuth: true,
      );
      if (!mounted) return;
      setState(() {
        _snapshot = snap;
        _busy = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _busy = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final pad = ThemeCleanPremium.pagePadding(context);
    return Scaffold(
      backgroundColor: ThemeCleanPremium.surfaceVariant,
      appBar: ThemeCleanPremium.isMobile(context)
          ? null
          : AppBar(
              title: const Text('Saúde do Sistema'),
              backgroundColor: Colors.white,
              foregroundColor: Colors.black87,
              elevation: 0,
            ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _refresh,
          child: ListView(
            padding: pad,
            children: [
              if (ThemeCleanPremium.isMobile(context)) ...[
                const SizedBox(height: 8),
                const Text(
                  'Saúde do Sistema',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
              ],
              Text(
                'churchId: ${ChurchRepository.resolveChurchId(widget.tenantId)}',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
              ),
              const SizedBox(height: 16),
              if (_busy && _snapshot == null)
                const Center(
                  child: Padding(
                    padding: EdgeInsets.all(32),
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
              else if (_error != null)
                _ErrorCard(message: _error!, onRetry: _refresh)
              else if (_snapshot != null) ...[
                _StatusBanner(snapshot: _snapshot!),
                const SizedBox(height: 20),
                _SectionHeader(
                  icon: Icons.cloud_done_rounded,
                  title: 'Infraestrutura',
                ),
                const SizedBox(height: 8),
                ..._snapshot!.infraChecks.map(_infraTile),
                const SizedBox(height: 24),
                _SectionHeader(
                  icon: Icons.folder_copy_rounded,
                  title: 'Auditoria por módulo',
                  subtitle:
                      'Contagem 0 indica módulo vazio ou falha de leitura — compare com o Firestore.',
                ),
                const SizedBox(height: 8),
                ..._snapshot!.moduleRows.map(_moduleTile),
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: _busy ? null : () => unawaited(_refresh()),
                  icon: _busy
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.fact_check_outlined),
                  label: Text(
                    _busy ? 'Executando…' : 'Executar Auditoria Completa',
                  ),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(48),
                    backgroundColor: ThemeCleanPremium.primary,
                  ),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: _snapshot == null
                      ? null
                      : () {
                          final text = _snapshot!.audit.toReportTable();
                          Clipboard.setData(ClipboardData(text: text));
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Relatório copiado'),
                              behavior: SnackBarBehavior.floating,
                            ),
                          );
                        },
                  icon: const Icon(Icons.copy_all_outlined, size: 18),
                  label: const Text('Copiar relatório completo'),
                ),
              ],
              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }

  Widget _infraTile(SystemHealthCheck check) {
    return _HealthTile(
      label: _infraLabel(check.label),
      ok: check.ok,
      detail: check.detail,
    );
  }

  Widget _moduleTile(ChurchModuleHealthRow row) {
    final warnZero = row.ok && row.count == 0;
    return _HealthTile(
      label: row.label,
      ok: row.ok,
      count: row.count,
      detail: row.ok
          ? (warnZero ? '0 documentos — verificar seed ou permissões' : 'OK')
          : (row.detail.isNotEmpty ? row.detail : 'Indisponível'),
      warn: warnZero,
    );
  }

  static String _infraLabel(String raw) {
    switch (raw) {
      case 'Firebase Auth':
        return 'Auth';
      case 'FCM':
        return 'Push';
      default:
        return raw;
    }
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.icon,
    required this.title,
    this.subtitle,
  });

  final IconData icon;
  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 20, color: ThemeCleanPremium.primary),
            const SizedBox(width: 8),
            Text(
              title,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        if (subtitle != null) ...[
          const SizedBox(height: 4),
          Text(
            subtitle!,
            style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
          ),
        ],
      ],
    );
  }
}

class _StatusBanner extends StatelessWidget {
  const _StatusBanner({required this.snapshot});

  final ChurchPanelHealthSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final ok = snapshot.productionReady;
    final bg = ok ? const Color(0xFFECFDF5) : const Color(0xFFFEF2F2);
    final fg = ok ? const Color(0xFF047857) : ThemeCleanPremium.error;
    final icon = ok ? Icons.verified_rounded : Icons.warning_amber_rounded;
    final title = ok ? 'Sistema saudável' : 'Atenção necessária';
    final sub = ok
        ? 'Infraestrutura e módulos respondendo.'
        : 'Revise itens em vermelho ou com contagem 0 inesperada.';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(16),
        boxShadow: ThemeCleanPremium.cardShadow,
      ),
      child: Row(
        children: [
          Icon(icon, color: fg, size: 28),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    color: fg,
                    fontSize: 15,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  sub,
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _HealthTile extends StatelessWidget {
  const _HealthTile({
    required this.label,
    required this.ok,
    this.count,
    this.detail = '',
    this.warn = false,
  });

  final String label;
  final bool ok;
  final int? count;
  final String detail;
  final bool warn;

  @override
  Widget build(BuildContext context) {
    Color badgeBg;
    Color badgeFg;
    String badgeText;
    if (!ok) {
      badgeBg = const Color(0xFFFEE2E2);
      badgeFg = ThemeCleanPremium.error;
      badgeText = 'FALHA';
    } else if (warn) {
      badgeBg = const Color(0xFFFEF3C7);
      badgeFg = const Color(0xFFB45309);
      badgeText = '0';
    } else {
      badgeBg = const Color(0xFFD1FAE5);
      badgeFg = const Color(0xFF047857);
      badgeText = 'OK';
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: ThemeCleanPremium.cardShadow,
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  count != null ? '$label: $count' : label,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
                if (detail.isNotEmpty)
                  Text(
                    detail,
                    style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: badgeBg,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              badgeText,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                color: badgeFg,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorCard extends StatelessWidget {
  const _ErrorCard({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: ThemeCleanPremium.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            message,
            style: TextStyle(color: ThemeCleanPremium.error, fontSize: 13),
          ),
          const SizedBox(height: 12),
          OutlinedButton(
            onPressed: onRetry,
            child: const Text('Tentar novamente'),
          ),
        ],
      ),
    );
  }
}
