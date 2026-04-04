import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:gestao_yahweh/ui/theme_clean_premium.dart';

/// Painel Master — Customização do sistema. Super Premium, responsivo.
class AdminCustomizacaoPage extends StatefulWidget {
  const AdminCustomizacaoPage({super.key});

  @override
  State<AdminCustomizacaoPage> createState() => _AdminCustomizacaoPageState();
}

class _AdminCustomizacaoPageState extends State<AdminCustomizacaoPage> {
  bool _loading = false;
  String? _error;
  late TextEditingController _titulo;
  late TextEditingController _mensagemBoasVindas;
  late TextEditingController _temaCor;

  @override
  void initState() {
    super.initState();
    _titulo = TextEditingController();
    _mensagemBoasVindas = TextEditingController();
    _temaCor = TextEditingController();
    _load();
  }

  @override
  void dispose() {
    _titulo.dispose();
    _mensagemBoasVindas.dispose();
    _temaCor.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      // Server-first evita estados inconsistentes do cache/listeners no Firestore web (SDK 11.x).
      final snap = await FirebaseFirestore.instance
          .collection('config')
          .doc('sistema')
          .get(const GetOptions(source: Source.server));
      final data = snap.data() ?? {};
      if (mounted) {
        _titulo.text = (data['titulo'] ?? '').toString();
        _mensagemBoasVindas.text = (data['mensagemBoasVindas'] ?? '').toString();
        _temaCor.text = (data['temaCor'] ?? '').toString();
        setState(() { _loading = false; _error = null; });
      }
    } catch (e) {
      if (mounted) {
        final msg = e.toString();
        final isDenied = msg.contains('permission-denied') ||
            msg.contains('PERMISSION_DENIED') ||
            msg.contains('Missing or insufficient permissions');
        setState(() {
          _loading = false;
          _error = isDenied
              ? 'Sem permissão para config/sistema. Use usuário com role ADMIN/MASTER ou documento em admins/{seuUid}. Depois: firebase deploy --only firestore:rules'
              : 'Não foi possível carregar. Publique as regras do Firestore (inclui config/sistema), recarregue com Ctrl+F5 e tente de novo.\n\n$msg';
        });
      }
    }
  }

  Future<void> _salvar() async {
    setState(() => _loading = true);
    try {
      await FirebaseFirestore.instance.collection('config').doc('sistema').set({
        'titulo': _titulo.text.trim(),
        'mensagemBoasVindas': _mensagemBoasVindas.text.trim(),
        'temaCor': _temaCor.text.trim(),
      }, SetOptions(merge: true));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(ThemeCleanPremium.successSnackBar('Configurações salvas!'));
        _load();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erro ao salvar: $e'), backgroundColor: ThemeCleanPremium.error));
        setState(() => _loading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final padding = ThemeCleanPremium.pagePadding(context);
    final isMobile = ThemeCleanPremium.isMobile(context);

    return Scaffold(
      primary: false,
      backgroundColor: ThemeCleanPremium.surfaceVariant,
      body: SafeArea(
        child: _loading && _titulo.text.isEmpty && _error == null
            ? const Center(child: CircularProgressIndicator())
            : SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(padding.left, padding.top, padding.right, padding.bottom + ThemeCleanPremium.spaceXl),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (_error != null) ...[
                      _PremiumCard(
                        child: Row(
                          children: [
                            Icon(Icons.warning_amber_rounded, color: ThemeCleanPremium.error, size: 24),
                            const SizedBox(width: 12),
                            Expanded(child: Text(_error!, style: const TextStyle(color: ThemeCleanPremium.error, fontSize: 13))),
                            TextButton(onPressed: _load, child: const Text('Tentar novamente')),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],
                    _PremiumCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            'Customização do sistema',
                            style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700) ?? const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                          ),
                          const SizedBox(height: 16),
                          TextField(
                            controller: _titulo,
                            decoration: InputDecoration(
                              labelText: 'Título do sistema',
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusSm)),
                              filled: true,
                              fillColor: ThemeCleanPremium.cardBackground,
                            ),
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: _mensagemBoasVindas,
                            maxLines: 3,
                            decoration: InputDecoration(
                              labelText: 'Mensagem de boas-vindas',
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusSm)),
                              filled: true,
                              fillColor: ThemeCleanPremium.cardBackground,
                            ),
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: _temaCor,
                            decoration: InputDecoration(
                              labelText: 'Cor do tema (hex, ex: #1976D2)',
                              hintText: '#1976D2',
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusSm)),
                              filled: true,
                              fillColor: ThemeCleanPremium.cardBackground,
                            ),
                          ),
                          const SizedBox(height: 20),
                          FilledButton.icon(
                            onPressed: _loading ? null : _salvar,
                            icon: _loading ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.save_rounded),
                            label: Text(_loading ? 'Salvando...' : 'Salvar configurações'),
                            style: FilledButton.styleFrom(
                              backgroundColor: ThemeCleanPremium.primary,
                              minimumSize: isMobile ? const Size(0, ThemeCleanPremium.minTouchTarget) : null,
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
  }
}

class _PremiumCard extends StatelessWidget {
  const _PremiumCard({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(ThemeCleanPremium.spaceMd),
      decoration: BoxDecoration(
        color: ThemeCleanPremium.cardBackground,
        borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusMd),
        boxShadow: ThemeCleanPremium.softUiCardShadow,
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: child,
    );
  }
}
