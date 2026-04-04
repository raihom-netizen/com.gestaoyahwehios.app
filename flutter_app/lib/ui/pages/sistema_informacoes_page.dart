import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:gestao_yahweh/app_version.dart';
import 'package:gestao_yahweh/ui/theme_clean_premium.dart';
import 'package:gestao_yahweh/ui/widgets/church_panel_ui_helpers.dart';

/// Tela de informações do sistema, resumo geral e sugestões/críticas.
class SistemaInformacoesPage extends StatefulWidget {
  final String tenantId;

  const SistemaInformacoesPage({super.key, required this.tenantId});

  @override
  State<SistemaInformacoesPage> createState() => _SistemaInformacoesPageState();
}

class _SistemaInformacoesPageState extends State<SistemaInformacoesPage> {
  final _textoController = TextEditingController();
  bool _loading = false;
  bool _enviado = false;

  @override
  void dispose() {
    _textoController.dispose();
    super.dispose();
  }

  Future<void> _enviarSugestao() async {
    final texto = _textoController.text.trim();
    if (texto.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Digite sua sugestão ou crítica.')),
      );
      return;
    }
    setState(() => _loading = true);
    try {
      final user = FirebaseAuth.instance.currentUser;
      await FirebaseFirestore.instance.collection('suggestions').add({
        'tenantId': widget.tenantId,
        'userId': user?.uid ?? '',
        'userEmail': user?.email ?? '',
        'userName': user?.displayName ?? '',
        'text': texto,
        'createdAt': FieldValue.serverTimestamp(),
        'status': 'pendente',
      });
      _textoController.clear();
      setState(() => _enviado = true);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Sua sugestão foi enviada. Obrigado!'), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao enviar: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = ThemeCleanPremium.isMobile(context);
    final padding = ThemeCleanPremium.pagePadding(context);
    return Scaffold(
      appBar: isMobile ? null : AppBar(
        title: const Text('Informações do Sistema'),
        backgroundColor: const Color(0xFF1E40AF),
        foregroundColor: Colors.white,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: padding,
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Card(
                  elevation: 2,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.info_outline_rounded, size: 40, color: Colors.blue.shade700),
                            const SizedBox(width: 16),
                            const Expanded(
                              child: Text(
                                'Gestão YAHWEH',
                                style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: Color(0xFF1E293B)),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 20),
                        const Text(
                          'Resumo do sistema',
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: Color(0xFF1E40AF)),
                        ),
                        const SizedBox(height: 12),
                        _buildFeatureItem(Icons.people_rounded, 'Membros', 'Cadastro completo, carteirinha digital com QR Code'),
                        _buildFeatureItem(Icons.groups_rounded, 'Departamentos', 'Organização por áreas e lideranças'),
                        _buildFeatureItem(Icons.event_rounded, 'Eventos e Escalas', 'Calendário, escalas semanais/mensais'),
                        _buildFeatureItem(Icons.account_balance_wallet_rounded, 'Financeiro', 'Receitas, despesas e gráficos'),
                        _buildFeatureItem(Icons.inventory_2_rounded, 'Patrimônio', 'Controle de bens e equipamentos'),
                        _buildFeatureItem(Icons.view_quilt_rounded, 'Mural', 'Avisos e notícias estilo feed'),
                        _buildFeatureItem(Icons.notifications_rounded, 'Notificações', 'Comunicados e lembretes'),
                        _buildFeatureItem(Icons.payment_rounded, 'Assinaturas', 'Planos, PIX e cartão via Mercado Pago'),
                        const SizedBox(height: 24),
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.blue.shade50,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.blue.shade200),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Agradecemos a confiança em nossa plataforma. '
                                'O Gestão YAHWEH foi desenvolvido para auxiliar igrejas na organização '
                                'de membros, eventos, finanças e comunicação. Seu feedback é muito importante para melhorarmos continuamente.',
                                style: TextStyle(fontSize: 14, height: 1.5, color: Colors.blue.shade900),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 20),
                        Center(
                          child: Column(
                            children: [
                              Text(
                                'Desenvolvido por Raihom Barbosa',
                                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Colors.grey.shade800),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Versão $appVersion',
                                style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 28),
                Card(
                  elevation: 2,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.feedback_rounded, size: 28, color: Colors.orange.shade700),
                            const SizedBox(width: 12),
                            const Text(
                              'Sugestões ou críticas',
                              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Envie sua opinião. Leitura e resposta são feitas pelo painel administrativo.',
                          style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
                        ),
                        const SizedBox(height: 16),
                        TextField(
                          controller: _textoController,
                          maxLines: 5,
                          decoration: const InputDecoration(
                            hintText: 'Digite sua sugestão, crítica ou elogio...',
                            border: OutlineInputBorder(),
                            alignLabelWithHint: true,
                          ),
                          enabled: !_loading,
                        ),
                        const SizedBox(height: 16),
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton.icon(
                            onPressed: _loading ? null : _enviarSugestao,
                            icon: _loading
                                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                                : const Icon(Icons.send_rounded, size: 20),
                            label: Text(_loading ? 'Enviando...' : 'Enviar'),
                            style: FilledButton.styleFrom(
                              backgroundColor: const Color(0xFF1E40AF),
                              padding: const EdgeInsets.symmetric(vertical: 14),
                            ),
                          ),
                        ),
                        if (_enviado)
                          Padding(
                            padding: const EdgeInsets.only(top: 12),
                            child: Row(
                              children: [
                                Icon(Icons.check_circle, color: Colors.green.shade700, size: 20),
                                const SizedBox(width: 8),
                                Expanded(child: Text('Obrigado! Você receberá um retorno em breve.', style: TextStyle(color: Colors.green.shade700, fontWeight: FontWeight.w600))),
                              ],
                            ),
                          ),
                        const SizedBox(height: 20),
                        const Text('Suas mensagens e respostas', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                        const SizedBox(height: 8),
                        _MinhasSugestoes(tenantId: widget.tenantId),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
    );
  }

  Widget _buildFeatureItem(IconData icon, String title, String desc) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: const Color(0xFF1E40AF)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
                Text(desc, style: TextStyle(fontSize: 12, color: Colors.grey.shade700)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MinhasSugestoes extends StatefulWidget {
  final String tenantId;

  const _MinhasSugestoes({required this.tenantId});

  @override
  State<_MinhasSugestoes> createState() => _MinhasSugestoesState();
}

class _MinhasSugestoesState extends State<_MinhasSugestoes> {
  int _streamKey = 0;

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    if (uid.isEmpty) return const SizedBox.shrink();
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      key: ValueKey(_streamKey),
      stream: FirebaseFirestore.instance
          .collection('suggestions')
          .where('userId', isEqualTo: uid)
          .limit(20)
          .snapshots(),
      builder: (context, snap) {
        if (snap.hasError) {
          return ChurchPanelErrorBody(
            title: 'Não foi possível carregar suas mensagens',
            error: snap.error,
            onRetry: () => setState(() => _streamKey++),
          );
        }
        if (!snap.hasData || snap.data!.docs.isEmpty) {
          return Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(8)),
            child: Text('Nenhuma mensagem enviada ainda.', style: TextStyle(color: Colors.grey.shade600)),
          );
        }
        final docs = snap.data!.docs.toList()
          ..sort((a, b) {
            final ta = a.data()['createdAt'] as Timestamp?;
            final tb = b.data()['createdAt'] as Timestamp?;
            if (ta == null && tb == null) return 0;
            if (ta == null) return 1;
            if (tb == null) return -1;
            return tb.compareTo(ta);
          });
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: docs.map((d) {
            final data = d.data();
            final response = (data['response'] ?? '').toString();
            final respondedAt = data['respondedAt'] as Timestamp?;
            String fmt(Timestamp? ts) {
              if (ts == null) return '—';
              final dt = ts.toDate();
              return '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year}';
            }
            return Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(response.isEmpty ? Icons.schedule : Icons.check_circle, size: 18, color: response.isEmpty ? Colors.orange : Colors.green),
                        const SizedBox(width: 8),
                        Text('${fmt(data['createdAt'] as Timestamp?)}', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(data['text'] ?? '', style: const TextStyle(fontSize: 14)),
                    if (response.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(color: Colors.green.shade50, borderRadius: BorderRadius.circular(8)),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Resposta: ${fmt(respondedAt)}', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.green.shade800)),
                            const SizedBox(height: 4),
                            Text(response, style: TextStyle(fontSize: 13, color: Colors.green.shade900)),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            );
          }).toList(),
        );
      },
    );
  }
}
