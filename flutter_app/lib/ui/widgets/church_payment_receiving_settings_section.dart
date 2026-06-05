import 'dart:async' show unawaited;

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:gestao_yahweh/services/church_payment_receiving_service.dart';
import 'package:gestao_yahweh/services/tenant_resolver_service.dart';
import 'package:gestao_yahweh/ui/theme_clean_premium.dart';
import 'package:gestao_yahweh/ui/widgets/mercado_pago_church_settings_section.dart';

/// Configurações — Mercado Pago (credenciais) + links InitPay/outros (simples).
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
  final _initPayCheckoutCtrl = TextEditingController();
  final _initPayPixCtrl = TextEditingController();
  final _otherNameCtrl = TextEditingController();
  final _otherUrlCtrl = TextEditingController();
  bool _loading = true;
  bool _saving = false;
  bool _mpEnabled = true;
  bool _initPayEnabled = false;
  String? _operationalTenantId;

  String get _effectiveTenantId {
    final op = (_operationalTenantId ?? widget.tenantId).trim();
    return op.isEmpty ? widget.tenantId.trim() : op;
  }

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _resolveOperationalTenant() async {
    final seed = widget.tenantId.trim();
    if (seed.isEmpty) return;
    final uid = FirebaseAuth.instance.currentUser?.uid;
    _operationalTenantId = await TenantResolverService
        .resolveOperationalChurchDocId(seed, userUid: uid)
        .timeout(const Duration(seconds: 10), onTimeout: () => seed);
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      await _resolveOperationalTenant();
    } catch (_) {}
    final cfg = await ChurchPaymentReceivingService.read(_effectiveTenantId);
    if (!mounted) return;
    _mpEnabled = cfg.mercadoPagoEnabled;
    _initPayEnabled = cfg.initPayEnabled;
    _initPayCheckoutCtrl.text = cfg.initPayCheckoutUrl;
    _initPayPixCtrl.text = cfg.initPayPixLink;
    _otherNameCtrl.text = cfg.otherProviderName;
    _otherUrlCtrl.text = cfg.otherCheckoutUrl;
    setState(() => _loading = false);
  }

  @override
  void dispose() {
    _initPayCheckoutCtrl.dispose();
    _initPayPixCtrl.dispose();
    _otherNameCtrl.dispose();
    _otherUrlCtrl.dispose();
    super.dispose();
  }

  Future<void> _salvarLinks() async {
    setState(() => _saving = true);
    try {
      await ChurchPaymentReceivingService.save(
        _effectiveTenantId,
        ChurchPaymentReceivingConfig(
          mercadoPagoEnabled: _mpEnabled,
          initPayEnabled: _initPayEnabled,
          initPayCheckoutUrl: _initPayCheckoutCtrl.text,
          initPayPixLink: _initPayPixCtrl.text,
          otherCheckoutUrl: _otherUrlCtrl.text,
          otherProviderName: _otherNameCtrl.text,
        ),
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Formas de recebimento salvas.')),
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
          icon: Icons.link_rounded,
          title: 'Links de recebimento',
        ),
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(
            'Configure como a igreja recebe dízimos e ofertas. '
            'Android e web: PIX e cartão no módulo Doação (cartão abre no Chrome). '
            'iPhone: apenas link para o site da igreja (App Store).',
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
                  'Android/web: módulo Doação. iPhone: site da igreja.',
                  style: TextStyle(fontSize: 12),
                ),
                value: _mpEnabled,
                onChanged: (v) => setState(() => _mpEnabled = v),
              ),
              const Divider(height: 20),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text(
                  'InitPay (link externo)',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                subtitle: const Text(
                  'Cole o link de checkout ou PIX do InitPay — usado na web e no iPhone.',
                  style: TextStyle(fontSize: 12),
                ),
                value: _initPayEnabled,
                onChanged: (v) => setState(() => _initPayEnabled = v),
              ),
              if (_initPayEnabled) ...[
                const SizedBox(height: 8),
                TextField(
                  controller: _initPayCheckoutCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Link InitPay (checkout)',
                    hintText: 'https://…',
                    border: OutlineInputBorder(),
                  ),
                  keyboardType: TextInputType.url,
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _initPayPixCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Link ou código PIX InitPay (opcional)',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
              const Divider(height: 20),
              TextField(
                controller: _otherNameCtrl,
                decoration: const InputDecoration(
                  labelText: 'Outro meio (nome)',
                  hintText: 'Ex.: Infinity Pay, banco, link pastoral',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _otherUrlCtrl,
                decoration: const InputDecoration(
                  labelText: 'Link de pagamento (opcional)',
                  border: OutlineInputBorder(),
                ),
                keyboardType: TextInputType.url,
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _saving ? null : _salvarLinks,
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
                label: Text(_saving ? 'Salvando…' : 'Salvar links'),
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
