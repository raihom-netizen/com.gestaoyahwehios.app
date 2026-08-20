import 'package:gestao_yahweh/core/data/church_ui_collections.dart';
import 'package:gestao_yahweh/core/data/yahweh_doc_write.dart';
import 'dart:async' show unawaited;

import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:gestao_yahweh/core/tenant/church_panel_tenant.dart';
import 'package:gestao_yahweh/firebase_options.dart';
import 'package:gestao_yahweh/services/app_permissions.dart';
import 'package:gestao_yahweh/services/igreja_direct_firestore_reads.dart';
import 'package:gestao_yahweh/ui/theme_clean_premium.dart';
import 'package:gestao_yahweh/utils/firestore_rest_read.dart';
import 'package:gestao_yahweh/utils/firestore_web_guard.dart';

/// Tela «Integração» da conta Mercado Pago (Financeiro → Contas).
/// Credenciais (produção + teste) ficam só no servidor — nunca são reexibidas.
class MercadoPagoIntegrationPage extends StatefulWidget {
  const MercadoPagoIntegrationPage({
    super.key,
    required this.tenantId,
    required this.role,
    this.permissions,
  });

  final String tenantId;
  final String role;
  final List<String>? permissions;

  static Future<void> open(
    BuildContext context, {
    required String tenantId,
    required String role,
    List<String>? permissions,
  }) {
    return Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => MercadoPagoIntegrationPage(
          tenantId: tenantId,
          role: role,
          permissions: permissions,
        ),
      ),
    );
  }

  @override
  State<MercadoPagoIntegrationPage> createState() =>
      _MercadoPagoIntegrationPageState();
}

class _MercadoPagoIntegrationPageState
    extends State<MercadoPagoIntegrationPage> {
  final _tokenCtrl = TextEditingController();
  final _publicKeyCtrl = TextEditingController();
  final _clientIdCtrl = TextEditingController();
  final _clientSecretCtrl = TextEditingController();
  final _webhookSecretCtrl = TextEditingController();
  final _webhookCtrl = TextEditingController();
  final _tokenTestCtrl = TextEditingController();
  final _publicKeyTestCtrl = TextEditingController();
  final _clientIdTestCtrl = TextEditingController();
  final _clientSecretTestCtrl = TextEditingController();

  bool _loading = true;
  bool _saving = false;
  String _mode = 'production';
  Map<String, dynamic>? _cfg;
  String? _operationalTenantId;

  bool get _canManage => AppPermissions.canViewChurchMercadoPagoSettings(
        widget.role,
        permissions: widget.permissions,
      );

  String get _effectiveTenantId => ChurchPanelTenant.resolve(
        (_operationalTenantId ?? '').isNotEmpty
            ? _operationalTenantId
            : widget.tenantId,
      );

  static String _defaultWebhookUrl() {
    final pid = DefaultFirebaseOptions.currentPlatform.projectId;
    if (pid.isEmpty) return '';
    return 'https://us-central1-$pid.cloudfunctions.net/mpWebhook';
  }

  @override
  void initState() {
    super.initState();
    _operationalTenantId = ChurchPanelTenant.resolve(widget.tenantId.trim());
    if (_canManage) {
      unawaited(_load());
    } else {
      _loading = false;
    }
  }

  Future<void> _load() async {
    if (mounted) setState(() => _loading = true);
    try {
      final churchId = _effectiveTenantId;
      Map<String, dynamic>? data;
      // ? Web: lê a config por REST (não passa pelo watch stream do SDK, então
      // NÃO trava no cliente envenenado pela assertion). Timeout de 12s embutido.
      if (kIsWeb) {
        try {
          data = await firestoreRestGetDoc(
            'igrejas/$churchId/config/mercado_pago',
          );
        } catch (_) {}
      }
      // Fallback SDK — com TIMEOUT para NUNCA pendurar o formulário (era isso que
      // deixava a tela travada carregando).
      if (data == null) {
        final hit = await IgrejaDirectFirestoreReads.readIgrejaConfig(
          churchId,
          'mercado_pago',
        ).timeout(const Duration(seconds: 8), onTimeout: () => null);
        if (hit != null) {
          data = hit.data;
          _operationalTenantId = hit.docId;
        }
      }
      _cfg = data;
      _publicKeyCtrl.text = (_cfg?['publicKey'] ?? '').toString();
      _clientIdCtrl.text = (_cfg?['clientId'] ?? '').toString();
      _publicKeyTestCtrl.text = (_cfg?['publicKeyTest'] ?? '').toString();
      _clientIdTestCtrl.text = (_cfg?['clientIdTest'] ?? '').toString();
      _webhookCtrl.text = (_cfg?['notificationWebhookUrl'] ?? '').toString();
      _taxaComoDespesa = _cfg?['lancarTaxaComoDespesa'] == true;
      final cfgMode = (_cfg?['mode'] ?? 'production').toString().trim();
      _mode = cfgMode == 'test' ? 'test' : 'production';
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
    _tokenTestCtrl.dispose();
    _publicKeyTestCtrl.dispose();
    _clientIdTestCtrl.dispose();
    _clientSecretTestCtrl.dispose();
    super.dispose();
  }

  /// Lançar a taxa do Mercado Pago como despesa separada.
  ///
  /// Desligado: a receita e o **líquido** e a taxa fica só registada no
  /// lançamento. Ligado: a receita passa a ser o **bruto** e a taxa vira uma
  /// despesa em «Taxas e tarifas». O saldo dá o mesmo nos dois casos; a
  /// diferença é conseguir responder «quanto pagámos de taxa este ano».
  bool _taxaComoDespesa = false;

  Future<void> _guardarTaxaComoDespesa(bool v) async {
    setState(() => _taxaComoDespesa = v);
    try {
      // Gravacao pelo gateway (REST na web) — o `.set()` cru do SDK e o que
      // rebenta com a INTERNAL ASSERTION.
      await YahwehDocWrite.set(
        ChurchUiCollections.ref('config', churchIdHint: _effectiveTenantId)
            .doc('mercado_pago'),
        <String, dynamic>{'lancarTaxaComoDespesa': v},
        merge: true,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              v
                  ? 'A partir de agora a taxa entra como despesa e a receita '
                      'passa a ser o valor bruto.'
                  : 'A receita volta a ser o valor líquido; a taxa deixa de '
                      'gerar despesa.',
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _taxaComoDespesa = !v);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Não foi possível guardar: $e')),
        );
      }
    }
  }

  Future<void> _salvar() async {
    final tok = _tokenCtrl.text.trim();
    final tokTest = _tokenTestCtrl.text.trim();
    final anyField = tok.isNotEmpty ||
        tokTest.isNotEmpty ||
        _publicKeyCtrl.text.trim().isNotEmpty ||
        _clientIdCtrl.text.trim().isNotEmpty ||
        _clientSecretCtrl.text.trim().isNotEmpty ||
        _webhookSecretCtrl.text.trim().isNotEmpty ||
        _webhookCtrl.text.trim().isNotEmpty ||
        _publicKeyTestCtrl.text.trim().isNotEmpty ||
        _clientIdTestCtrl.text.trim().isNotEmpty ||
        _clientSecretTestCtrl.text.trim().isNotEmpty;
    if (!anyField) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Preencha ao menos um campo (produção ou teste) para salvar.'),
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
        'tenantId': _effectiveTenantId,
        'accessToken': tok,
        'accessTokenTest': tokTest,
        'publicKey': _publicKeyCtrl.text.trim(),
        'publicKeyTest': _publicKeyTestCtrl.text.trim(),
        'clientId': _clientIdCtrl.text.trim(),
        'clientIdTest': _clientIdTestCtrl.text.trim(),
        'notificationWebhookUrl': wh,
        'clientSecret': _clientSecretCtrl.text.trim(),
        'clientSecretTest': _clientSecretTestCtrl.text.trim(),
        'webhookSecret': _webhookSecretCtrl.text.trim(),
        'mode': _mode,
      });
      _tokenCtrl.clear();
      _tokenTestCtrl.clear();
      _clientSecretCtrl.clear();
      _clientSecretTestCtrl.clear();
      _webhookSecretCtrl.clear();
      if (mounted) {
        await _load();
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Integração salva com segurança no servidor.'),
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

  @override
  Widget build(BuildContext context) {
    if (!_canManage) {
      return Scaffold(
        appBar: AppBar(title: const Text('Integração Mercado Pago')),
        body: const Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'Só pastor, gestor, ADM ou tesoureiro pode configurar a integração Mercado Pago.',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }

    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Integração Mercado Pago')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    final defUrl = _defaultWebhookUrl();
    final u = FirebaseAuth.instance.currentUser;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Integração Mercado Pago'),
        backgroundColor: ThemeCleanPremium.primary,
        foregroundColor: Colors.white,
      ),
      body: u == null
          ? const SizedBox.shrink()
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text(
                  'Access Token, Public Key, Client ID e Client Secret ficam apenas no servidor '
                  '(documento privado). Depois de salvar, segredos não são exibidos de volta — só '
                  'a indicação de "já configurado".',
                  style: TextStyle(
                    fontSize: 12.5,
                    color: Colors.grey.shade700,
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: 16),
                _ModeSelector(
                  mode: _mode,
                  onChanged: (m) => setState(() => _mode = m),
                ),
                const SizedBox(height: 16),
                _Card(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text(
                        'Credenciais de produção',
                        style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                      ),
                      const SizedBox(height: 12),
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
                          labelText: 'Public Key',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: _clientIdCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Client ID',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: _clientSecretCtrl,
                        obscureText: true,
                        decoration: InputDecoration(
                          labelText: 'Client Secret',
                          helperText: (_cfg?['hasClientSecret'] == true)
                              ? 'Já salvo no servidor — cole apenas para substituir.'
                              : 'Painel MP ? Credenciais de produção.',
                          border: const OutlineInputBorder(),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                _Card(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text(
                        'Credenciais de teste (sandbox)',
                        style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Opcional — use para testar PIX/cartão sem afetar dinheiro real.',
                        style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _tokenTestCtrl,
                        obscureText: true,
                        decoration: const InputDecoration(
                          labelText: 'Access Token (teste)',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: _publicKeyTestCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Public Key (teste)',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: _clientIdTestCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Client ID (teste)',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: _clientSecretTestCtrl,
                        obscureText: true,
                        decoration: InputDecoration(
                          labelText: 'Client Secret (teste)',
                          helperText: (_cfg?['hasClientSecretTest'] == true)
                              ? 'Já salvo no servidor — cole apenas para substituir.'
                              : null,
                          border: const OutlineInputBorder(),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                _Card(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text(
                        'Webhook',
                        style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: _webhookSecretCtrl,
                        obscureText: true,
                        decoration: InputDecoration(
                          labelText: 'Assinatura secreta ? Webhooks MP (opcional)',
                          helperText: (_cfg?['hasWebhookSecret'] == true)
                              ? 'Já salva no servidor — cole apenas para substituir.'
                              : 'Painel MP ? Webhooks ? Assinatura secreta.',
                          border: const OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: _webhookCtrl,
                        keyboardType: TextInputType.url,
                        decoration: const InputDecoration(
                          labelText: 'Webhook (notificações MP)',
                          hintText: 'Opcional ? HTTPS do seu endpoint ou deixe vazio',
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
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                _Card(
                  child: SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: _taxaComoDespesa,
                    onChanged: _guardarTaxaComoDespesa,
                    title: const Text(
                      'Lançar a taxa como despesa',
                      style: TextStyle(fontWeight: FontWeight.w800),
                    ),
                    subtitle: const Text(
                      'Desligado: entra o valor líquido. Ligado: entra o valor '
                      'bruto e a taxa vira despesa em «Taxas e tarifas» — o '
                      'saldo é o mesmo, mas passa a dar para somar quanto se '
                      'pagou de taxa no período.',
                      style: TextStyle(fontSize: 12, height: 1.35),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
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
                    'Integração ativa (${_mode == 'test' ? 'teste' : 'produção'}).',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.green.shade800,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
                const SizedBox(height: 24),
              ],
            ),
    );
  }
}

class _ModeSelector extends StatelessWidget {
  const _ModeSelector({required this.mode, required this.onChanged});

  final String mode;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return SegmentedButton<String>(
      segments: const [
        ButtonSegment(
          value: 'production',
          label: Text('Produção'),
          icon: Icon(Icons.bolt_rounded),
        ),
        ButtonSegment(
          value: 'test',
          label: Text('Teste'),
          icon: Icon(Icons.science_outlined),
        ),
      ],
      selected: {mode},
      onSelectionChanged: (s) => onChanged(s.first),
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
