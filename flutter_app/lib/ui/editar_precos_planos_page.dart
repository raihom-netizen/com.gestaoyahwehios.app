import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:gestao_yahweh/core/data/app_global_firestore_access.dart';
import 'package:gestao_yahweh/data/planos_oficiais.dart';
import 'package:gestao_yahweh/services/plan_price_service.dart';
import 'package:gestao_yahweh/ui/theme_clean_premium.dart';
import 'package:gestao_yahweh/ui/widgets/master_premium_surfaces.dart';
import 'package:gestao_yahweh/utils/br_input_formatters.dart';

/// Lista todos os planos oficiais (mesma lista do painel divulgação e painel igreja).
/// Permite ao master editar preços, nome exibido, texto de faixa de membros e limite máximo;
/// grava em `config/plans/items/{planId}` (campos opcionais vazios removem override no Firestore).
class EditarPrecosPlanosPage extends StatefulWidget {
  const EditarPrecosPlanosPage({super.key});

  @override
  State<EditarPrecosPlanosPage> createState() => _EditarPrecosPlanosPageState();
}

class _EditarPrecosPlanosPageState extends State<EditarPrecosPlanosPage> {
  bool _loading = false;
  String? _err;
  final Map<String, TextEditingController> _controllersMonthly = {};
  final Map<String, TextEditingController> _controllersAnnual = {};
  final Map<String, TextEditingController> _controllersName = {};
  final Map<String, TextEditingController> _controllersMembers = {};
  final Map<String, TextEditingController> _controllersMaxMembers = {};

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
    for (final c in _controllersName.values) {
      c.dispose();
    }
    for (final c in _controllersMembers.values) {
      c.dispose();
    }
    for (final c in _controllersMaxMembers.values) {
      c.dispose();
    }
    super.dispose();
  }

  void _disposeControllers() {
    for (final c in _controllersMonthly.values) {
      c.dispose();
    }
    for (final c in _controllersAnnual.values) {
      c.dispose();
    }
    for (final c in _controllersName.values) {
      c.dispose();
    }
    for (final c in _controllersMembers.values) {
      c.dispose();
    }
    for (final c in _controllersMaxMembers.values) {
      c.dispose();
    }
    _controllersMonthly.clear();
    _controllersAnnual.clear();
    _controllersName.clear();
    _controllersMembers.clear();
    _controllersMaxMembers.clear();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _err = null;
    });
    try {
      final snap = await AppGlobalFirestoreAccess.listPlanItems();

      final Map<String, Map<String, dynamic>> byId = {};
      for (final d in snap.docs) {
        byId[d.id] = d.data();
      }

      _disposeControllers();

      for (final plan in planosOficiais) {
        final merged = EffectivePlanConfig.merge(plan, byId[plan.id]);
        _controllersMonthly[plan.id] = TextEditingController(
          text: merged.monthlyPrice != null && merged.monthlyPrice! > 0
              ? formatBrCurrencyInitial(merged.monthlyPrice!)
              : '',
        );
        final ann = merged.annualPrice;
        _controllersAnnual[plan.id] = TextEditingController(
          text: ann != null && ann > 0 ? formatBrCurrencyInitial(ann) : '',
        );
        _controllersName[plan.id] = TextEditingController(text: merged.name);
        _controllersMembers[plan.id] = TextEditingController(text: merged.members);
        _controllersMaxMembers[plan.id] =
            TextEditingController(text: '${merged.maxMembers}');
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
    final ctrlName = _controllersName[id];
    final ctrlMem = _controllersMembers[id];
    final ctrlMax = _controllersMaxMembers[id];
    if (ctrlM == null ||
        ctrlA == null ||
        ctrlName == null ||
        ctrlMem == null ||
        ctrlMax == null) {
      return;
    }
    final base = planosOficiais.firstWhere(
      (p) => p.id == id,
      orElse: () => planosOficiais.first,
    );

    final valorM = parseBrCurrencyInput(ctrlM.text);
    final ar = ctrlA.text.trim();
    final valorA = ar.isEmpty ? null : parseBrCurrencyInput(ctrlA.text);

    final nameText = ctrlName.text.trim();
    final membersText = ctrlMem.text.trim();
    final maxText = ctrlMax.text.trim();

    Object maxMembersField = FieldValue.delete();
    if (maxText.isNotEmpty) {
      final parsedMax = int.tryParse(maxText);
      if (parsedMax == null) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Limite de membros inválido — use um número inteiro.')),
        );
        return;
      }
      if (parsedMax < 0) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Limite de membros não pode ser negativo.')),
        );
        return;
      }
      maxMembersField =
          parsedMax == base.maxMembers ? FieldValue.delete() : parsedMax;
    }

    final payload = <String, dynamic>{
      'priceMonthly': valorM,
      if (valorA != null) 'priceAnnual': valorA,
      if (nameText.isEmpty || nameText == base.name)
        'name': FieldValue.delete()
      else
        'name': nameText,
      if (membersText.isEmpty || membersText == base.members)
        'members': FieldValue.delete()
      else
        'members': membersText,
      'maxMembers': maxMembersField,
    };

    await AppGlobalFirestoreAccess.setPlanItem(id, payload);
    if (!mounted) return;
    PlanPriceService.invalidateCache();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Plano atualizado no banco (preços e limites).')),
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
                          Text('Erro: $_err',
                              style: const TextStyle(
                                  color: ThemeCleanPremium.error, fontSize: 13)),
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
                    padding: EdgeInsets.fromLTRB(padding.left, padding.top,
                        padding.right, padding.bottom + ThemeCleanPremium.spaceXl),
                    children: [
                      Text(
                        'Todos os planos (mesma lista do site, apps, login e «Atualizar plano» na web). '
                        'Alterações em `config/plans/items` propagam em tempo real para divulgação, '
                        'painel da igreja e fluxo Apple — sem nova versão da loja.',
                        style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
                      ),
                      const SizedBox(height: 16),
                      ...planosOficiais.map((plan) {
                        final ctrlM = _controllersMonthly[plan.id]!;
                        final ctrlA = _controllersAnnual[plan.id]!;
                        final ctrlN = _controllersName[plan.id]!;
                        final ctrlMem = _controllersMembers[plan.id]!;
                        final ctrlMax = _controllersMaxMembers[plan.id]!;
                        return MasterPremiumCard(
                          margin:
                              const EdgeInsets.only(bottom: ThemeCleanPremium.spaceMd),
                          padding: const EdgeInsets.all(ThemeCleanPremium.spaceMd),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'ID: ${plan.id}',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.grey.shade600,
                                ),
                              ),
                              const SizedBox(height: 8),
                              TextField(
                                controller: ctrlN,
                                decoration: const InputDecoration(
                                  labelText: 'Nome exibido',
                                  isDense: true,
                                  border: OutlineInputBorder(),
                                ),
                              ),
                              const SizedBox(height: 10),
                              TextField(
                                controller: ctrlMem,
                                decoration: const InputDecoration(
                                  labelText: 'Faixa de membros (texto)',
                                  hintText: 'Ex.: Até 100 membros',
                                  isDense: true,
                                  border: OutlineInputBorder(),
                                ),
                              ),
                              const SizedBox(height: 10),
                              TextField(
                                controller: ctrlMax,
                                keyboardType: TextInputType.number,
                                decoration: const InputDecoration(
                                  labelText: 'Limite máximo de membros',
                                  isDense: true,
                                  border: OutlineInputBorder(),
                                ),
                              ),
                              const SizedBox(height: 12),
                              Row(
                                children: [
                                  Expanded(
                                    child: TextField(
                                      controller: ctrlM,
                                      keyboardType: TextInputType.number,
                                      inputFormatters: [BrCurrencyInputFormatter()],
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
                                      keyboardType: TextInputType.number,
                                      inputFormatters: [BrCurrencyInputFormatter()],
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
                              const SizedBox(height: 6),
                              Text(
                                'Deixe nome/faixa/limite iguais ao padrão ou vazio para remover override no Firestore.',
                                style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                              ),
                            ],
                          ),
                        );
                      }),
                    ],
                  ),
      ),
    );
  }
}
