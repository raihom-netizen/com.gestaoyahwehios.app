import 'package:cloud_functions/cloud_functions.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:gestao_yahweh/firebase_options.dart';

import 'package:gestao_yahweh/ui/theme_clean_premium.dart';

/// Bloco em Configurações: Mercado Pago da igreja + conta tesouraria modelo.
class MercadoPagoChurchSettingsSection extends StatefulWidget {
  final String tenantId;

  const MercadoPagoChurchSettingsSection({super.key, required this.tenantId});

  @override
  State<MercadoPagoChurchSettingsSection> createState() =>
      _MercadoPagoChurchSettingsSectionState();
}

class _MercadoPagoChurchSettingsSectionState
    extends State<MercadoPagoChurchSettingsSection> {
  final _tokenCtrl = TextEditingController();
  final _publicKeyCtrl = TextEditingController();
  final _clientIdCtrl = TextEditingController();
  final _clientSecretCtrl = TextEditingController();
  final _webhookSecretCtrl = TextEditingController();
  final _webhookCtrl = TextEditingController();
  bool _loading = true;
  bool _saving = false;
  bool _seeding = false;
  Map<String, dynamic>? _cfg;

  static String _defaultWebhookUrl() {
    final pid = DefaultFirebaseOptions.currentPlatform.projectId;
    if (pid.isEmpty) return '';
    return 'https://us-central1-$pid.cloudfunctions.net/mpWebhook';
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final d = await FirebaseFirestore.instance
          .collection('igrejas')
          .doc(widget.tenantId)
          .collection('config')
          .doc('mercado_pago')
          .get();
      _cfg = d.data();
      _publicKeyCtrl.text = (_cfg?['publicKey'] ?? '').toString();
      _clientIdCtrl.text = (_cfg?['clientId'] ?? '').toString();
      _webhookCtrl.text = (_cfg?['notificationWebhookUrl'] ?? '').toString();
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  @override
  void dispose() {
    _tokenCtrl.dispose();
    _publicKeyCtrl.dispose();
    _clientIdCtrl.dispose();
    _clientSecretCtrl.dispose();
    _webhookSecretCtrl.dispose();
    _webhookCtrl.dispose();
    super.dispose();
  }

  Future<void> _salvar() async {
    final tok = _tokenCtrl.text.trim();
    final hasPublicOnly = tok.isEmpty &&
        (_clientIdCtrl.text.trim().isNotEmpty ||
            _publicKeyCtrl.text.trim().isNotEmpty ||
            _webhookCtrl.text.trim().isNotEmpty);
    final hasSecretOnly = tok.isEmpty &&
        (_clientSecretCtrl.text.trim().isNotEmpty ||
            _webhookSecretCtrl.text.trim().isNotEmpty);
    if (tok.isEmpty && !hasPublicOnly && !hasSecretOnly) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Cole o Access Token (primeira vez), ou preencha Public Key / Client ID / Webhook, ou Client Secret / Assinatura webhook.',
          ),
        ),
      );
      return;
    }
    final wh = _webhookCtrl.text.trim();
    if (wh.isNotEmpty && !wh.toLowerCase().startsWith('https://')) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Webhook deve ser uma URL HTTPS (ex.: https://…).'),
        ),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      final callable = FirebaseFunctions.instanceFor(region: 'us-central1')
          .httpsCallable('saveChurchMercadoPagoCredentials');
      await callable.call(<String, dynamic>{
        'tenantId': widget.tenantId,
        'accessToken': tok,
        'publicKey': _publicKeyCtrl.text.trim(),
        'clientId': _clientIdCtrl.text.trim(),
        'notificationWebhookUrl': wh,
        'clientSecret': _clientSecretCtrl.text.trim(),
        'webhookSecret': _webhookSecretCtrl.text.trim(),
      });
      if (tok.isNotEmpty) _tokenCtrl.clear();
      if (_clientSecretCtrl.text.trim().isNotEmpty) _clientSecretCtrl.clear();
      if (_webhookSecretCtrl.text.trim().isNotEmpty) _webhookSecretCtrl.clear();
      if (mounted) {
        await _load();
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Credenciais salvas com segurança no servidor.'),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _seedContas() async {
    setState(() => _seeding = true);
    try {
      final callable = FirebaseFunctions.instanceFor(region: 'us-central1')
          .httpsCallable('ensureChurchTreasuryAccountPresets');
      final res =
          await callable.call(<String, dynamic>{'tenantId': widget.tenantId});
      final data = Map<String, dynamic>.from(res.data as Map? ?? {});
      final c = data['created'];
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Conta Mercado Pago na tesouraria: criadas $c. Ajuste detalhes em Financeiro → Contas, se precisar.',
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Erro: $e')));
      }
    } finally {
      if (mounted) setState(() => _seeding = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final u = FirebaseAuth.instance.currentUser;
    if (u == null) return const SizedBox.shrink();

    if (_loading) {
      return const Padding(
        padding: EdgeInsets.all(24),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    final defUrl = _defaultWebhookUrl();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SectionTitle(
            icon: Icons.account_balance_wallet_rounded,
            title: 'Pagamentos e doações'),
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(
            'Integração Mercado Pago da igreja: Access Token, Public Key, Client ID e Client Secret ficam apenas no servidor '
            '(documento privado). Depois de salvar, segredos não são exibidos de volta — apenas indicação “já configurado”.',
            style: TextStyle(
                fontSize: 12.5, color: Colors.grey.shade700, height: 1.35),
          ),
        ),
        _Card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: _tokenCtrl,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'Access Token',
                  helperText:
                      'Cole apenas ao cadastrar ou trocar; não é exibido depois.',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _publicKeyCtrl,
                decoration: const InputDecoration(
                  labelText: 'Public Key (opcional)',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _clientIdCtrl,
                decoration: const InputDecoration(
                  labelText: 'Client ID (opcional)',
                  helperText:
                      'ID da aplicação no painel Mercado Pago — referência para suporte e documentação.',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _clientSecretCtrl,
                obscureText: true,
                decoration: InputDecoration(
                  labelText: 'Client Secret (opcional)',
                  helperText: (_cfg?['hasClientSecret'] == true)
                      ? 'Já salvo no servidor — cole apenas para substituir.'
                      : 'Painel MP → Credenciais de produção — não é exibido depois de salvo.',
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _webhookSecretCtrl,
                obscureText: true,
                decoration: InputDecoration(
                  labelText: 'Assinatura secreta — Webhooks MP (opcional)',
                  helperText: (_cfg?['hasWebhookSecret'] == true)
                      ? 'Já salva no servidor — cole apenas para substituir.'
                      : 'Painel MP → Webhooks → Assinatura secreta (validação futura no backend).',
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _webhookCtrl,
                keyboardType: TextInputType.url,
                decoration: const InputDecoration(
                  labelText: 'Webhook (notificações MP)',
                  hintText: 'Opcional — HTTPS do seu endpoint ou deixe vazio',
                  helperText:
                      'Se vazio, o PIX usa o webhook da plataforma (recomendado).',
                  border: OutlineInputBorder(),
                ),
              ),
              if (defUrl.isNotEmpty) ...[
                const SizedBox(height: 10),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEFF6FF),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFBFDBFE)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Webhook padrão da plataforma (copie no painel do Mercado Pago, se pedir):',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: Colors.grey.shade800,
                        ),
                      ),
                      const SizedBox(height: 6),
                      SelectableText(
                        defUrl,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF1D4ED8),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _saving ? null : _salvar,
                icon: _saving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.save_rounded),
                label: Text(_saving ? 'Salvando...' : 'Salvar integração'),
                style: FilledButton.styleFrom(
                  backgroundColor: ThemeCleanPremium.primary,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
              if (_cfg?['enabled'] == true) ...[
                const SizedBox(height: 12),
                Text(
                  'Integração ativa (produção).',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.green.shade800,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 12),
        _Card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Conta tesouraria Mercado Pago',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
              ),
              const SizedBox(height: 6),
              Text(
                'Dízimos e ofertas via PIX usam só a conta Mercado Pago (código 323) para conciliação. '
                'Crie o rascunho aqui e complete dados em Financeiro → Contas, se precisar.',
                style: TextStyle(
                    fontSize: 12.5, color: Colors.grey.shade700, height: 1.35),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _seeding ? null : _seedContas,
                icon: _seeding
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.account_balance_rounded),
                label: Text(_seeding
                    ? 'Criando...'
                    : 'Criar conta Mercado Pago na tesouraria'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
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
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Icon(icon, color: ThemeCleanPremium.primary, size: 22),
          const SizedBox(width: 8),
          Text(
            title,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.2,
            ),
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
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: ThemeCleanPremium.cardBackground,
        borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusMd),
        boxShadow: ThemeCleanPremium.softUiCardShadow,
        border: Border.all(color: const Color(0xFFF1F5F9)),
      ),
      child: child,
    );
  }
}
