import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:gestao_yahweh/ui/theme_clean_premium.dart';

class MercadoPagoAdminPage extends StatefulWidget {
  /// Quando aberto dentro do painel master (drawer), evita conflito de [PrimaryScrollController].
  final bool embeddedInMaster;

  const MercadoPagoAdminPage({super.key, this.embeddedInMaster = false});

  @override
  State<MercadoPagoAdminPage> createState() => _MercadoPagoAdminPageState();
}

class _MercadoPagoAdminPageState extends State<MercadoPagoAdminPage> {
  final _publicKeyController = TextEditingController();
  final _clientIdController = TextEditingController();
  final _clientSecretController = TextEditingController();
  final _accessTokenController = TextEditingController();
  final _publicKeyTestController = TextEditingController();
  final _clientIdTestController = TextEditingController();
  final _clientSecretTestController = TextEditingController();
  final _accessTokenTestController = TextEditingController();
  final _webhookUrlController = TextEditingController();
  final _backUrlController = TextEditingController();

  bool _loading = false;
  bool _saving = false;
  bool _modoProducao = true; // padrão: produção
  String? _loadError;

  /// URL recomendada do webhook (Cloud Function `mpWebhook` — igual ao painel Mercado Pago).
  static const String _defaultWebhookUrl =
      'https://us-central1-gestaoyahweh-21e23.cloudfunctions.net/mpWebhook';

  static const String _legacyWebhookUrl =
      'https://us-central1-gestaoyahweh-21e23.cloudfunctions.net/mercadoPagoWebhook';

  static String _str(Map<String, dynamic>? data, String key, [String fallback = '']) {
    if (data == null) return fallback;
    final v = data[key] ?? data[_camelToSnake(key)] ?? data[key.toLowerCase()];
    return v?.toString().trim() ?? fallback;
  }

  static String _camelToSnake(String s) {
    return s.replaceAllMapped(RegExp(r'[A-Z]'), (m) => '_${m.group(0)!.toLowerCase()}');
  }

  @override
  void initState() {
    super.initState();
    _loadCredenciais();
  }

  Future<void> _loadCredenciais() async {
    setState(() { _loading = true; _loadError = null; });
    try {
      // Atualiza o token para garantir claims mais recentes (role ADMIN/MASTER)
      await FirebaseAuth.instance.currentUser?.getIdToken(true);
      final doc = await FirebaseFirestore.instance.collection('config').doc('mercado_pago').get();
      final data = doc.data();
      if (data != null && data.isNotEmpty) {
        _publicKeyController.text = _str(data, 'publicKey');
        _clientIdController.text = _str(data, 'clientId');
        _clientSecretController.text = _str(data, 'clientSecret');
        _accessTokenController.text = _str(data, 'accessToken');
        _publicKeyTestController.text = _str(data, 'publicKeyTest');
        _clientIdTestController.text = _str(data, 'clientIdTest');
        _clientSecretTestController.text = _str(data, 'clientSecretTest');
        _accessTokenTestController.text = _str(data, 'accessTokenTest');
        _webhookUrlController.text = _str(data, 'webhookUrl');
        if (_webhookUrlController.text.isEmpty) {
          _webhookUrlController.text = _str(data, 'webhook_url');
        }
        _backUrlController.text = _str(data, 'backUrl');
        if (_backUrlController.text.isEmpty) {
          _backUrlController.text = _str(data, 'back_url');
        }
        if (_backUrlController.text.isEmpty) {
          _backUrlController.text = _str(data, 'returnUrl');
        }
        final mode = (data['mode'] ?? data['modo'] ?? 'production').toString().toLowerCase();
        _modoProducao = mode != 'test' && mode != 'teste';
      }
      if (mounted) setState(() { _loading = false; _loadError = null; });
    } catch (e) {
      final msg = e.toString();
      final isPermissionDenied = msg.contains('permission-denied') || msg.contains('PERMISSION_DENIED');
      if (mounted) setState(() {
        _loading = false;
        _loadError = isPermissionDenied
            ? 'Sem permissão para ler config no Firebase. Verifique se seu usuário tem role ADMIN ou MASTER (custom claims ou documento users).'
            : msg;
      });
    }
  }

  Future<void> _salvarCredenciais() async {
    setState(() => _saving = true);
    final data = {
      'publicKey': _publicKeyController.text.trim(),
      'clientId': _clientIdController.text.trim(),
      'clientSecret': _clientSecretController.text.trim(),
      'accessToken': _accessTokenController.text.trim(),
      'publicKeyTest': _publicKeyTestController.text.trim(),
      'clientIdTest': _clientIdTestController.text.trim(),
      'clientSecretTest': _clientSecretTestController.text.trim(),
      'accessTokenTest': _accessTokenTestController.text.trim(),
      'webhookUrl': _webhookUrlController.text.trim(),
      'backUrl': _backUrlController.text.trim(),
      'mode': _modoProducao ? 'production' : 'test',
      'updatedAt': FieldValue.serverTimestamp(),
    };
    final ref = FirebaseFirestore.instance.collection('config').doc('mercado_pago');
    try {
      await FirebaseAuth.instance.currentUser?.getIdToken(true);
      await Future.delayed(const Duration(milliseconds: 300));
      await ref.set(data);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          ThemeCleanPremium.successSnackBar('Configurações do Mercado Pago salvas com sucesso!'),
        );
      }
    } catch (e) {
      final isPermissionDenied = e.toString().contains('permission-denied') || e.toString().contains('PERMISSION_DENIED');
      if (isPermissionDenied) {
        try {
          await Future.delayed(const Duration(milliseconds: 500));
          await FirebaseAuth.instance.currentUser?.getIdToken(true);
          await Future.delayed(const Duration(milliseconds: 300));
          await ref.set(data);
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              ThemeCleanPremium.successSnackBar('Configurações do Mercado Pago salvas com sucesso!'),
            );
          }
        } catch (e2) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Erro ao salvar: $e2'), backgroundColor: ThemeCleanPremium.error),
            );
          }
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Erro ao salvar: $e'), backgroundColor: ThemeCleanPremium.error),
          );
        }
      }
    }
    if (mounted) setState(() => _saving = false);
  }

  @override
  void dispose() {
    _publicKeyController.dispose();
    _clientIdController.dispose();
    _clientSecretController.dispose();
    _accessTokenController.dispose();
    _publicKeyTestController.dispose();
    _clientIdTestController.dispose();
    _clientSecretTestController.dispose();
    _accessTokenTestController.dispose();
    _webhookUrlController.dispose();
    _backUrlController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = ThemeCleanPremium.isMobile(context);
    final padding = ThemeCleanPremium.pagePadding(context);
    return Scaffold(
      primary: !widget.embeddedInMaster,
      backgroundColor: ThemeCleanPremium.surfaceVariant,
      appBar: isMobile ? null : AppBar(
        backgroundColor: ThemeCleanPremium.primary,
        foregroundColor: Colors.white,
        title: const Text('Integração Mercado Pago'),
      ),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(padding.left, padding.top, padding.right, padding.bottom + ThemeCleanPremium.spaceXl),
                child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (_loadError != null) ...[
                          _PremiumCard(
                            child: Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(10),
                                  decoration: BoxDecoration(
                                    color: ThemeCleanPremium.error.withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Icon(Icons.warning_amber_rounded, color: ThemeCleanPremium.error, size: 24),
                                ),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: Text(
                                    'Não foi possível carregar as configurações do banco. Você pode editar e salvar para gravar ou atualizar.',
                                    style: TextStyle(fontSize: 13, color: ThemeCleanPremium.onSurface),
                                  ),
                                ),
                                TextButton.icon(
                                  onPressed: _loading ? null : _loadCredenciais,
                                  icon: const Icon(Icons.refresh_rounded, size: 20),
                                  label: const Text('Recarregar'),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: ThemeCleanPremium.spaceMd),
                        ],
                        _PremiumCard(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(10),
                                    decoration: BoxDecoration(
                                      color: ThemeCleanPremium.primary.withOpacity(0.08),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Icon(Icons.info_outline_rounded, color: ThemeCleanPremium.primary, size: 24),
                                  ),
                                  const SizedBox(width: 12),
                                  Text(
                                    'Conta única para licenças',
                                    style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16, color: ThemeCleanPremium.onSurface, letterSpacing: 0.2),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 10),
                              Text(
                                'Por esta conta do Mercado Pago você recebe as licenças das igrejas. '
                                'As credenciais já gravadas no Firebase aparecem abaixo. Edite e clique em Salvar para atualizar.',
                                style: TextStyle(fontSize: 13, color: ThemeCleanPremium.onSurfaceVariant, height: 1.4),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: ThemeCleanPremium.spaceLg),
                        _PremiumCard(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Modo de operação',
                                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16, color: ThemeCleanPremium.onSurface, letterSpacing: 0.2),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                'Produção: pagamentos reais. Teste: credenciais de teste (sem valor real).',
                                style: TextStyle(color: ThemeCleanPremium.onSurfaceVariant, fontSize: 13),
                              ),
                              const SizedBox(height: 12),
                        LayoutBuilder(
                          builder: (_, c) => SegmentedButton<bool>(
                            segments: const [
                              ButtonSegment(value: true, label: Text('Produção'), icon: Icon(Icons.check_circle_rounded)),
                              ButtonSegment(value: false, label: Text('Teste'), icon: Icon(Icons.science_rounded)),
                            ],
                            selected: {_modoProducao},
                            onSelectionChanged: (Set<bool> s) => setState(() => _modoProducao = s.first),
                          ),
                        ),
                            ],
                          ),
                        ),
                        const SizedBox(height: ThemeCleanPremium.spaceLg),
                        _PremiumCard(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(8),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFECFDF5),
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: const Icon(Icons.credit_card_rounded, color: Color(0xFF047857), size: 22),
                                  ),
                                  const SizedBox(width: 12),
                                  Text(
                                    'Credenciais de Produção',
                                    style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16, color: ThemeCleanPremium.onSurface, letterSpacing: 0.2),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 16),
                              TextField(
                                controller: _publicKeyController,
                                decoration: InputDecoration(
                                  labelText: 'Public Key (produção)',
                                  hintText: 'APP_USR-...',
                                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusSm)),
                                  filled: true,
                                  fillColor: Colors.white,
                                ),
                              ),
                              const SizedBox(height: 12),
                              TextField(
                                controller: _clientIdController,
                                decoration: InputDecoration(
                                  labelText: 'Client ID (produção)',
                                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusSm)),
                                  filled: true,
                                  fillColor: Colors.white,
                                ),
                              ),
                              const SizedBox(height: 12),
                              TextField(
                                controller: _clientSecretController,
                                decoration: InputDecoration(
                                  labelText: 'Client Secret (produção)',
                                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusSm)),
                                  filled: true,
                                  fillColor: Colors.white,
                                ),
                              ),
                              const SizedBox(height: 12),
                              TextField(
                                controller: _accessTokenController,
                                decoration: InputDecoration(
                                  labelText: 'Access Token (produção)',
                                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusSm)),
                                  filled: true,
                                  fillColor: Colors.white,
                                ),
                                obscureText: true,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: ThemeCleanPremium.spaceLg),
                        _PremiumCard(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(8),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFFEF3C7),
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: const Icon(Icons.science_rounded, color: Color(0xFFB45309), size: 22),
                                  ),
                                  const SizedBox(width: 12),
                                  Text(
                                    'Credenciais de Teste (opcional)',
                                    style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16, color: ThemeCleanPremium.onSurface, letterSpacing: 0.2),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 16),
                              TextField(
                                controller: _publicKeyTestController,
                                decoration: InputDecoration(
                                  labelText: 'Public Key (teste)',
                                  hintText: 'TEST-...',
                                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusSm)),
                                  filled: true,
                                  fillColor: Colors.white,
                                ),
                              ),
                              const SizedBox(height: 12),
                              TextField(
                                controller: _clientIdTestController,
                                decoration: InputDecoration(
                                  labelText: 'Client ID (teste)',
                                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusSm)),
                                  filled: true,
                                  fillColor: Colors.white,
                                ),
                              ),
                              const SizedBox(height: 12),
                              TextField(
                                controller: _clientSecretTestController,
                                decoration: InputDecoration(
                                  labelText: 'Client Secret (teste)',
                                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusSm)),
                                  filled: true,
                                  fillColor: Colors.white,
                                ),
                              ),
                              const SizedBox(height: 12),
                              TextField(
                                controller: _accessTokenTestController,
                                decoration: InputDecoration(
                                  labelText: 'Access Token (teste)',
                                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusSm)),
                                  filled: true,
                                  fillColor: Colors.white,
                                ),
                                obscureText: true,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: ThemeCleanPremium.spaceLg),
                        _PremiumCard(
                          child: Wrap(
                            spacing: 12,
                            runSpacing: 12,
                            children: [
                              FilledButton.icon(
                                onPressed: (_saving || _loading) ? null : _salvarCredenciais,
                                icon: _saving
                                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                                    : const Icon(Icons.save_rounded),
                                label: Text(_saving ? 'Salvando...' : 'Salvar configurações'),
                                style: FilledButton.styleFrom(
                                  backgroundColor: ThemeCleanPremium.primary,
                                  padding: EdgeInsets.symmetric(
                                    horizontal: ThemeCleanPremium.spaceLg,
                                    vertical: isMobile ? 14 : 14,
                                  ),
                                  minimumSize: isMobile ? const Size(0, ThemeCleanPremium.minTouchTarget) : null,
                                ),
                              ),
                              OutlinedButton.icon(
                                onPressed: _loading ? null : _loadCredenciais,
                                icon: const Icon(Icons.refresh_rounded, size: 20),
                                label: const Text('Recarregar'),
                                style: isMobile
                                    ? OutlinedButton.styleFrom(
                                        minimumSize: const Size(0, ThemeCleanPremium.minTouchTarget),
                                      )
                                    : null,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: ThemeCleanPremium.spaceXl),
                        _PremiumCard(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(8),
                                    decoration: BoxDecoration(
                                      color: ThemeCleanPremium.primary.withOpacity(0.08),
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: Icon(Icons.webhook_rounded, color: ThemeCleanPremium.primary, size: 22),
                                  ),
                                  const SizedBox(width: 12),
                                  Text(
                                    'Notificações (Webhook) — Igrejas',
                                    style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16, color: ThemeCleanPremium.onSurface, letterSpacing: 0.2),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 10),
                              Text(
                                'Os pagamentos desta conta (igrejas) atualizam as licenças automaticamente quando o webhook é chamado. '
                                'No Mercado Pago: Developers > sua app > Notificações > Webhooks, use preferencialmente a URL abaixo (`mpWebhook`). '
                                'A função `mercadoPagoWebhook` continua ativa como alternativa legada.',
                                style: TextStyle(color: ThemeCleanPremium.onSurfaceVariant, fontSize: 13),
                              ),
                              const SizedBox(height: 12),
                              SelectableText(
                                _defaultWebhookUrl,
                                style: TextStyle(
                                  fontFamily: 'monospace',
                                  fontSize: 12,
                                  color: ThemeCleanPremium.primary,
                                ),
                              ),
                              const SizedBox(height: 6),
                              SelectableText(
                                _legacyWebhookUrl,
                                style: TextStyle(
                                  fontFamily: 'monospace',
                                  fontSize: 11,
                                  color: ThemeCleanPremium.onSurfaceVariant,
                                ),
                              ),
                              const SizedBox(height: 12),
                              TextField(
                                controller: _webhookUrlController,
                                decoration: InputDecoration(
                                  labelText: 'URL do Webhook (opcional — sobrescreve env MP_WEBHOOK_URL)',
                                  hintText: 'Ex.: $_defaultWebhookUrl',
                                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusSm)),
                                  filled: true,
                                  fillColor: Colors.white,
                                ),
                              ),
                              const SizedBox(height: 16),
                              TextField(
                                controller: _backUrlController,
                                decoration: InputDecoration(
                                  labelText: 'URL de retorno após pagamento (back_url — obrigatório no MP)',
                                  hintText: 'Ex.: https://gestaoyahweh.com.br/planos ou https://seu-projeto.web.app/planos',
                                  helperText: 'Onde o usuário volta após PIX/cartão. Vazio = app usa domínio padrão + /planos.',
                                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusSm)),
                                  filled: true,
                                  fillColor: Colors.white,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Salve as alterações para gravar webhook e URL de retorno no Firestore (config/mercado_pago).',
                                style: TextStyle(color: ThemeCleanPremium.onSurfaceVariant, fontSize: 12),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: ThemeCleanPremium.spaceXl),
                        Text(
                          'Cobranças e recebimentos (Mercado Pago)',
                          style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16, color: ThemeCleanPremium.onSurface, letterSpacing: 0.2),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Pagamentos (cartão/PIX) que caem no seu Mercado Pago aparecem aqui após o webhook.',
                          style: TextStyle(color: ThemeCleanPremium.onSurfaceVariant, fontSize: 13),
                        ),
                        const SizedBox(height: ThemeCleanPremium.spaceMd),
                        _SalesList(),
                        const SizedBox(height: ThemeCleanPremium.spaceLg),
                        Text(
                          'Controle de licenças (igrejas)',
                          style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16, color: ThemeCleanPremium.onSurface, letterSpacing: 0.2),
                        ),
                        const SizedBox(height: 6),
                        _LicensesSummary(),
                        const SizedBox(height: ThemeCleanPremium.spaceXl),
                      ],
                    ),
                  ),
      ),
    );
  }
}

/// Card branco estilo Super Premium: sombra suave, bordas 16px.
class _PremiumCard extends StatelessWidget {
  const _PremiumCard({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(ThemeCleanPremium.spaceMd),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusMd),
        border: Border.all(color: const Color(0xFFF1F5F9), width: 1),
        boxShadow: ThemeCleanPremium.softUiCardShadow,
      ),
      child: child,
    );
  }
}

class _SalesList extends StatelessWidget {
  static String _fmt(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('sales')
          .orderBy('createdAt', descending: true)
          .limit(50)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return _PremiumCard(
            child: Text('Erro: ${snapshot.error}', style: const TextStyle(color: ThemeCleanPremium.error, fontSize: 13)),
          );
        }
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return _PremiumCard(
            child: Text(
              'Nenhuma cobrança registrada ainda. Ao receber pagamentos via Mercado Pago (cartão ou PIX), o webhook grava aqui.',
              style: TextStyle(color: ThemeCleanPremium.onSurfaceVariant, fontSize: 14),
            ),
          );
        }
        final docs = snapshot.data!.docs;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: List.generate(docs.length, (i) {
            final d = docs[i].data();
            final tenantId = d['tenantId'] ?? '';
            final amount = (d['amount'] ?? 0).toDouble();
            final status = (d['status'] ?? '').toString();
            final type = (d['type'] ?? 'payment').toString();
            final createdAt = d['createdAt'] is Timestamp
                ? (d['createdAt'] as Timestamp).toDate()
                : null;
            return Padding(
              padding: const EdgeInsets.only(bottom: ThemeCleanPremium.spaceSm),
              child: _PremiumCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.payment_rounded, color: Colors.green.shade700, size: 22),
                        const SizedBox(width: ThemeCleanPremium.spaceSm),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                'Igreja: $tenantId',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 15,
                                  color: ThemeCleanPremium.onSurface,
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '${type == 'preapproval' ? 'Assinatura' : 'Pagamento'} • R\$ ${amount.toStringAsFixed(2)} • $status'
                                '${createdAt != null ? ' • ${_fmt(createdAt)}' : ''}',
                                style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                              ),
                            ],
                          ),
                        ),
                        Text(
                          'R\$ ${amount.toStringAsFixed(2)}',
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 15,
                            color: Color(0xFF2E7D32),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          }),
        );
      },
    );
  }
}

class _LicensesSummary extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance.collection('igrejas').limit(100).snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return _PremiumCard(
            child: Text('Erro: ${snapshot.error}', style: const TextStyle(color: ThemeCleanPremium.error, fontSize: 13)),
          );
        }
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return _PremiumCard(
            child: Text(
              'Nenhuma licença ativa no momento. Licenças são atualizadas quando o webhook do Mercado Pago confirma o pagamento.',
              style: TextStyle(color: ThemeCleanPremium.onSurfaceVariant, fontSize: 14),
            ),
          );
        }
        final docs = snapshot.data!.docs;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: List.generate(docs.length, (i) {
            final d = docs[i].data();
            final name = (d['name'] ?? d['nome'] ?? docs[i].id).toString();
            final license = d['license'] as Map<String, dynamic>?;
            final status = (license?['status'] ?? 'active').toString();
            final billing = d['billing'] as Map<String, dynamic>?;
            final billingStatus = (billing?['status'] ?? '-').toString();
            return Padding(
              padding: const EdgeInsets.only(bottom: ThemeCleanPremium.spaceSm),
              child: _PremiumCard(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    CircleAvatar(
                      radius: 20,
                      backgroundColor: const Color(0xFF2E7D32),
                      child: const Icon(Icons.check_rounded, color: Colors.white, size: 20),
                    ),
                    const SizedBox(width: ThemeCleanPremium.spaceSm),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            name,
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 15,
                              color: ThemeCleanPremium.onSurface,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Licença: $status • Cobrança: $billingStatus',
                            style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          }),
        );
      },
    );
  }
}
