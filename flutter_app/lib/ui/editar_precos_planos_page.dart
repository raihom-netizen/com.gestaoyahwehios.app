import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:gestao_yahweh/data/planos_oficiais.dart';
import 'package:gestao_yahweh/services/plan_price_service.dart';
import 'package:gestao_yahweh/ui/theme_clean_premium.dart';

/// Lista todos os planos oficiais (mesma lista do painel divulgação e painel igreja).
/// Permite ao master editar preço mensal e anual; grava em config/plans/items/{planId}.
class EditarPrecosPlanosPage extends StatefulWidget {
  const EditarPrecosPlanosPage({super.key});

  @override
  State<EditarPrecosPlanosPage> createState() => _EditarPrecosPlanosPageState();
}

class _EditarPrecosPlanosPageState extends State<EditarPrecosPlanosPage> {
  bool _loading = false;
  String? _err;
  /// Preços carregados do Firestore (planId -> { priceMonthly, priceAnnual }).
  final Map<String, double?> _priceMonthly = {};
  final Map<String, double?> _priceAnnual = {};
  final Map<String, TextEditingController> _controllersMonthly = {};
  final Map<String, TextEditingController> _controllersAnnual = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final c in _controllersMonthly.values) {
      c.dispose();
    }
    for (final c in _controllersAnnual.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _err = null; });
    try {
      final snap = await FirebaseFirestore.instance
          .collection('config')
          .doc('plans')
          .collection('items')
          .get();

      final Map<String, Map<String, dynamic>> byId = {};
      for (final d in snap.docs) {
        byId[d.id] = d.data();
      }

      _controllersMonthly.clear();
      _controllersAnnual.clear();
      _priceMonthly.clear();
      _priceAnnual.clear();

      for (final plan in planosOficiais) {
        final data = byId[plan.id];
        final m = (data != null && data['priceMonthly'] != null)
            ? (data['priceMonthly'] is num ? (data['priceMonthly'] as num).toDouble() : null)
            : plan.monthlyPrice;
        final a = (data != null && data['priceAnnual'] != null)
            ? (data['priceAnnual'] is num ? (data['priceAnnual'] as num).toDouble() : null)
            : plan.annualPrice;
        _priceMonthly[plan.id] = m;
        _priceAnnual[plan.id] = a;
        _controllersMonthly[plan.id] = TextEditingController(text: m?.toStringAsFixed(2) ?? '');
        _controllersAnnual[plan.id] = TextEditingController(text: a?.toStringAsFixed(2) ?? '');
      }
    } catch (e) {
      _err = e.toString();
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<void> _salvar(String id) async {
    final ctrlM = _controllersMonthly[id];
    final ctrlA = _controllersAnnual[id];
    if (ctrlM == null || ctrlA == null) return;
    final valorM = double.tryParse(ctrlM.text.replaceAll(',', '.')) ?? 0;
    final valorA = double.tryParse(ctrlA.text.replaceAll(',', '.'));
    await FirebaseFirestore.instance
        .collection('config')
        .doc('plans')
        .collection('items')
        .doc(id)
        .set({
      'priceMonthly': valorM,
      if (valorA != null) 'priceAnnual': valorA,
      'name': planosOficiais.firstWhere((p) => p.id == id, orElse: () => planosOficiais.first).name,
    }, SetOptions(merge: true));
    if (!mounted) return;
    PlanPriceService.invalidateCache();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Preços gravados no banco!')),
    );
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final padding = ThemeCleanPremium.pagePadding(context);
    return Scaffold(
      primary: false,
      backgroundColor: ThemeCleanPremium.surfaceVariant,
      body: SafeArea(
        child: _loading
          ? const Center(child: CircularProgressIndicator())
          : _err != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('Erro: $_err', style: const TextStyle(color: ThemeCleanPremium.error, fontSize: 13)),
                        const SizedBox(height: 16),
                        FilledButton(
                          onPressed: _load,
                          child: const Text('Tentar novamente'),
                        ),
                      ],
                    ),
                  ),
                )
              : ListView(
                  padding: EdgeInsets.fromLTRB(padding.left, padding.top, padding.right, padding.bottom + ThemeCleanPremium.spaceXl),
                  children: [
                    Text(
                      'Todos os planos (mesma lista do painel divulgação e painel igreja). '
                      'Altere os valores e salve para atualizar no sistema.',
                      style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
                    ),
                    const SizedBox(height: 16),
                    ...planosOficiais.map((plan) {
                      final ctrlM = _controllersMonthly[plan.id]!;
                      final ctrlA = _controllersAnnual[plan.id]!;
                      return Card(
                        margin: const EdgeInsets.only(bottom: 12),
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                plan.name,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 16,
                                ),
                              ),
                              Text(
                                '${plan.members} • ID: ${plan.id}',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey.shade600,
                                ),
                              ),
                              const SizedBox(height: 12),
                              Row(
                                children: [
                                  Expanded(
                                    child: TextField(
                                      controller: ctrlM,
                                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                      decoration: const InputDecoration(
                                        labelText: 'Mensal (R\$)',
                                        isDense: true,
                                        border: OutlineInputBorder(),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: TextField(
                                      controller: ctrlA,
                                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                      decoration: const InputDecoration(
                                        labelText: 'Anual (R\$)',
                                        isDense: true,
                                        border: OutlineInputBorder(),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  IconButton(
                                    icon: const Icon(Icons.save_rounded),
                                    tooltip: 'Gravar no banco',
                                    onPressed: () => _salvar(plan.id),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      );
                    }),
                  ],
                ),
      ),
    );
  }
}
