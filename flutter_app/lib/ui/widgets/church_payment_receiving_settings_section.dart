import 'dart:async' show unawaited;

import 'package:flutter/material.dart';
import 'package:gestao_yahweh/core/repositories/church_repository.dart';
import 'package:gestao_yahweh/core/tenant/church_panel_tenant.dart';
import 'package:gestao_yahweh/services/church_payment_receiving_service.dart';
import 'package:gestao_yahweh/ui/theme_clean_premium.dart';
import 'package:gestao_yahweh/ui/widgets/mercado_pago_church_settings_section.dart';
import 'package:gestao_yahweh/debug/agent_debug_log.dart';

/// Configurações — Mercado Pago (PIX/cartão + credenciais).
class ChurchPaymentReceivingSettingsSection extends StatefulWidget {
  final String tenantId;
  final bool showMercadoPagoCredentials;

  const ChurchPaymentReceivingSettingsSection({
    super.key,
    required this.tenantId,
    this.showMercadoPagoCredentials = true,
  });

  @override
  State<ChurchPaymentReceivingSettingsSection> createState() =>
      _ChurchPaymentReceivingSettingsSectionState();
}

class _ChurchPaymentReceivingSettingsSectionState
    extends State<ChurchPaymentReceivingSettingsSection> {
  bool _loading = true;
  bool _saving = false;
  bool _mpEnabled = true;
  String? _operationalTenantId;

  String get _effectiveTenantId => ChurchPanelTenant.resolve(
        (_operationalTenantId ?? '').isNotEmpty
            ? _operationalTenantId
            : widget.tenantId,
      );

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _resolveOperationalTenant() async {
    final seed = widget.tenantId.trim();
    if (seed.isEmpty) return;
    _operationalTenantId = ChurchRepository.churchId(seed);
  }

  Future<void> _load() async {
    if (mounted) setState(() => _loading = true);
    final loadStarted = DateTime.now();
    try {
      try {
        await _resolveOperationalTenant().timeout(const Duration(seconds: 10));
      } catch (_) {}
      AgentDebugLog.log(
        location: 'church_payment_receiving_settings_section.dart:load',
        message: 'payment_receiving_resolve_done',
        hypothesisId: 'C',
        data: {
          'seed': widget.tenantId,
          'operational': _effectiveTenantId,
          'ms': DateTime.now().difference(loadStarted).inMilliseconds,
        },
      );
      final cfg = await ChurchPaymentReceivingService.read(_effectiveTenantId)
          .timeout(const Duration(seconds: 16));
      if (!mounted) return;
      _mpEnabled = cfg.mercadoPagoEnabled;
    } catch (e) {
      AgentDebugLog.log(
        location: 'church_payment_receiving_settings_section.dart:load_err',
        message: 'payment_receiving_load_error',
        hypothesisId: 'C',
        data: {
          'operational': _effectiveTenantId,
          'error': e.runtimeType.toString(),
          'ms': DateTime.now().difference(loadStarted).inMilliseconds,
        },
      );
    } finally {
      AgentDebugLog.log(
        location: 'church_payment_receiving_settings_section.dart:load_done',
        message: 'payment_receiving_load_finished',
        hypothesisId: 'C',
        data: {
          'operational': _effectiveTenantId,
          'mounted': mounted,
          'ms': DateTime.now().difference(loadStarted).inMilliseconds,
        },
      );
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _salvar() async {
    setState(() => _saving = true);
    try {
      await ChurchPaymentReceivingService.save(
        _effectiveTenantId,
        ChurchPaymentReceivingConfig(mercadoPagoEnabled: _mpEnabled),
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Mercado Pago salvo.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao salvar: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.all(20),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _SectionTitle(
          icon: Icons.payments_rounded,
          title: 'Recebimentos',
        ),
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(
            'Dízimos e ofertas via Mercado Pago. '
            'Android e web: PIX e cartão no módulo Doação. '
            'iPhone: site da igreja (App Store).',
            style: TextStyle(
              fontSize: 12.5,
              color: Colors.grey.shade700,
              height: 1.35,
            ),
          ),
        ),
        _Card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text(
                  'Mercado Pago (PIX e cartão)',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                subtitle: const Text(
                  'Única forma de recebimento integrada ao app.',
                  style: TextStyle(fontSize: 12),
                ),
                value: _mpEnabled,
                onChanged: (v) => setState(() => _mpEnabled = v),
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: _saving ? null : _salvar,
                icon: _saving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.save_rounded),
                label: Text(_saving ? 'Salvando…' : 'Salvar'),
                style: FilledButton.styleFrom(
                  backgroundColor: ThemeCleanPremium.primary,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
            ],
          ),
        ),
        if (widget.showMercadoPagoCredentials) ...[
          const SizedBox(height: 20),
          MercadoPagoChurchSettingsSection(tenantId: widget.tenantId),
        ],
      ],
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final IconData icon;
  final String title;
  const _SectionTitle({required this.icon, required this.title});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Icon(icon, color: ThemeCleanPremium.primary, size: 22),
          const SizedBox(width: 8),
          Text(
            title,
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
  }
}

class _Card extends StatelessWidget {
  final Widget child;
  const _Card({required this.child});

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusLg),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: Padding(padding: const EdgeInsets.all(16), child: child),
    );
  }
}
