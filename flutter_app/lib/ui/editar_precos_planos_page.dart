import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:gestao_yahweh/core/data/app_global_firestore_access.dart';
import 'package:gestao_yahweh/core/firebase_bootstrap.dart';
import 'package:gestao_yahweh/data/planos_oficiais.dart';
import 'package:gestao_yahweh/services/plan_price_service.dart';
import 'package:gestao_yahweh/ui/theme_clean_premium.dart';
import 'package:gestao_yahweh/utils/br_input_formatters.dart';

/// Painel Master — planos e preços.
///
/// Grava em `config/plans/items/{planId}`; campos iguais ao padrão (ou vazios)
/// removem o override. O botão **Sincronizar** grava todos os planos de uma vez
/// e carimba `config/plans` com uma versão nova — é o que faz a web, o iOS e o
/// Android recarregarem o catálogo sem publicar versão nova na loja.
class EditarPrecosPlanosPage extends StatefulWidget {
  const EditarPrecosPlanosPage({super.key});

  @override
  State<EditarPrecosPlanosPage> createState() => _EditarPrecosPlanosPageState();
}

class _EditarPrecosPlanosPageState extends State<EditarPrecosPlanosPage> {
  /// Uma cor forte por plano — cada cartão fica visualmente distinto.
  static const List<Color> _paleta = [
    Color(0xFF4F46E5), // índigo
    Color(0xFF0D9488), // teal
    Color(0xFFD97706), // âmbar
    Color(0xFFDB2777), // rosa
    Color(0xFF2563EB), // azul
    Color(0xFF16A34A), // verde
    Color(0xFF7C3AED), // violeta
    Color(0xFFEA580C), // laranja
  ];
  static const Color _cSlate = Color(0xFF64748B);

  bool _loading = false;
  bool _sincronizando = false;
  String? _err;
  String? _ok;

  final Map<String, TextEditingController> _controllersMonthly = {};
  final Map<String, TextEditingController> _controllersAnnual = {};
  final Map<String, TextEditingController> _controllersName = {};
  final Map<String, TextEditingController> _controllersMembers = {};
  final Map<String, TextEditingController> _controllersMaxMembers = {};

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void dispose() {
    _disposeControllers();
    super.dispose();
  }

  void _disposeControllers() {
    for (final map in [
      _controllersMonthly,
      _controllersAnnual,
      _controllersName,
      _controllersMembers,
      _controllersMaxMembers,
    ]) {
      for (final c in map.values) {
        c.dispose();
      }
      map.clear();
    }
  }

  Color _cor(int i) => _paleta[i % _paleta.length];

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _err = null;
    });
    try {
      final snap = await AppGlobalFirestoreAccess.listPlanItems();
      final byId = <String, Map<String, dynamic>>{};
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
        _controllersMembers[plan.id] = TextEditingController(
          text: merged.members,
        );
        _controllersMaxMembers[plan.id] = TextEditingController(
          text: '${merged.maxMembers}',
        );
      }
    } catch (e) {
      _err = 'Não foi possível carregar os planos agora.';
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Monta o payload de um plano. Devolve `null` quando há erro de validação
  /// (a mensagem já foi mostrada ao utilizador).
  Map<String, dynamic>? _payload(String id, {bool silencioso = false}) {
    final ctrlM = _controllersMonthly[id];
    final ctrlName = _controllersName[id];
    final ctrlMem = _controllersMembers[id];
    final ctrlMax = _controllersMaxMembers[id];
    if (ctrlM == null || ctrlName == null || ctrlMem == null ||
        ctrlMax == null) {
      return null;
    }
    final base = planosOficiais.firstWhere(
      (p) => p.id == id,
      orElse: () => planosOficiais.first,
    );

    final valorM = parseBrCurrencyInput(ctrlM.text);
    final valorA = valorM > 0 ? valorM * 10 : null;
    final nameText = ctrlName.text.trim();
    final membersText = ctrlMem.text.trim();
    final maxText = ctrlMax.text.trim();

    Object maxMembersField = FieldValue.delete();
    if (maxText.isNotEmpty) {
      final parsedMax = int.tryParse(maxText);
      if (parsedMax == null || parsedMax < 0) {
        if (!silencioso && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Limite de membros inválido em "${base.name}" — '
                'use um número inteiro.',
              ),
              backgroundColor: ThemeCleanPremium.error,
            ),
          );
        }
        return null;
      }
      maxMembersField = parsedMax == base.maxMembers
          ? FieldValue.delete()
          : parsedMax;
    }

    return <String, dynamic>{
      'priceMonthly': valorM,
      'priceAnnual': ?valorA,
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
  }

  Future<void> _salvar(String id) async {
    final payload = _payload(id);
    if (payload == null) return;
    try {
      await AppGlobalFirestoreAccess.setPlanItem(id, payload);
      PlanPriceService.invalidateCache();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        ThemeCleanPremium.successSnackBar('Plano gravado no banco.'),
      );
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(formatFirebaseErrorForUser(e, logToCrashlytics: false)),
          backgroundColor: ThemeCleanPremium.error,
        ),
      );
    }
  }

  /// Grava TODOS os planos e carimba a versão do catálogo.
  Future<void> _sincronizarTudo() async {
    if (_sincronizando) return;
    setState(() {
      _sincronizando = true;
      _ok = null;
      _err = null;
    });
    var gravados = 0;
    final falhas = <String>[];
    for (final plan in planosOficiais) {
      final payload = _payload(plan.id, silencioso: true);
      if (payload == null) {
        falhas.add(plan.name);
        continue;
      }
      try {
        await AppGlobalFirestoreAccess.setPlanItem(plan.id, payload);
        gravados++;
      } catch (_) {
        falhas.add(plan.name);
      }
    }

    // Carimbo de versão: os clientes que guardam catálogo em cache comparam
    // este valor e recarregam — é o que faz web/iOS/Android atualizarem sem
    // nova versão de loja.
    try {
      await AppGlobalFirestoreAccess.configDoc('plans').set({
        'plansVersion': DateTime.now().millisecondsSinceEpoch,
        'syncedAt': FieldValue.serverTimestamp(),
        'itemsCount': planosOficiais.length,
      }, SetOptions(merge: true));
    } catch (_) {
      // O carimbo é um extra: os planos já foram gravados acima.
    }

    PlanPriceService.invalidateCache();
    if (!mounted) return;
    setState(() {
      _sincronizando = false;
      _ok = falhas.isEmpty
          ? '$gravados plano(s) sincronizados — web, iOS e Android já leem os '
                'novos valores.'
          : '$gravados sincronizados. Reveja: ${falhas.join(', ')}.';
    });
    await _load();
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
            : ListView(
                padding: EdgeInsets.fromLTRB(
                  padding.left,
                  padding.top,
                  padding.right,
                  padding.bottom + ThemeCleanPremium.spaceXl,
                ),
                children: [
                  _cabecalho(),
                  const SizedBox(height: 14),
                  if (_err != null) ...[
                    _banner(_err!, ThemeCleanPremium.error,
                        Icons.error_outline_rounded),
                    const SizedBox(height: 12),
                  ],
                  if (_ok != null) ...[
                    _banner(_ok!, const Color(0xFF16A34A),
                        Icons.check_circle_rounded),
                    const SizedBox(height: 12),
                  ],
                  for (var i = 0; i < planosOficiais.length; i++)
                    _cartaoPlano(planosOficiais[i], _cor(i)),
                ],
              ),
      ),
    );
  }

  Widget _cabecalho() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF4F46E5), Color(0xFF0D9488)],
        ),
        borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusLg),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF4F46E5).withValues(alpha: 0.26),
            blurRadius: 18,
            offset: const Offset(0, 7),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 50,
                height: 50,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.20),
                  borderRadius: BorderRadius.circular(15),
                ),
                child: const Icon(
                  Icons.sell_rounded,
                  color: Colors.white,
                  size: 26,
                ),
              ),
              const SizedBox(width: 13),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Planos e preços',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    SizedBox(height: 3),
                    Text(
                      'A mesma lista do site, do login e do «Atualizar plano». '
                      'Sincronizar propaga na hora — sem versão nova de loja.',
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 12.5,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          FilledButton.icon(
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(48),
              backgroundColor: Colors.white,
              foregroundColor: const Color(0xFF4F46E5),
              textStyle: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w800,
              ),
            ),
            onPressed: _sincronizando ? null : () => unawaited(_sincronizarTudo()),
            icon: _sincronizando
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2.2),
                  )
                : const Icon(Icons.cloud_sync_rounded),
            label: Text(
              _sincronizando
                  ? 'Sincronizando…'
                  : 'Sincronizar tudo (web, iOS e Android)',
            ),
          ),
        ],
      ),
    );
  }

  Widget _cartaoPlano(PlanoOficial plan, Color cor) {
    final ctrlM = _controllersMonthly[plan.id];
    final ctrlA = _controllersAnnual[plan.id];
    final ctrlN = _controllersName[plan.id];
    final ctrlMem = _controllersMembers[plan.id];
    final ctrlMax = _controllersMaxMembers[plan.id];
    if (ctrlM == null || ctrlA == null || ctrlN == null || ctrlMem == null ||
        ctrlMax == null) {
      return const SizedBox.shrink();
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: ThemeCleanPremium.cardBackground,
        borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusLg),
        border: Border.all(color: cor.withValues(alpha: 0.28)),
        boxShadow: [
          BoxShadow(
            color: cor.withValues(alpha: 0.10),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
                colors: [cor, cor.withValues(alpha: 0.72)],
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.22),
                    borderRadius: BorderRadius.circular(11),
                  ),
                  child: const Icon(
                    Icons.workspace_premium_rounded,
                    color: Colors.white,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 11),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        ctrlN.text.isEmpty ? plan.name : ctrlN.text,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      Text(
                        'ID: ${plan.id}',
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Gravar este plano',
                  onPressed: () => unawaited(_salvar(plan.id)),
                  icon: const Icon(Icons.save_rounded, color: Colors.white),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: ctrlN,
                  onChanged: (_) => setState(() {}),
                  decoration: _campo('Nome exibido', cor),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: ctrlMem,
                  decoration: _campo(
                    'Faixa de membros (texto)',
                    cor,
                    dica: 'Ex.: Até 100 membros',
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: ctrlMax,
                  keyboardType: TextInputType.number,
                  decoration: _campo('Limite máximo de membros', cor),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: ctrlM,
                        keyboardType: TextInputType.number,
                        inputFormatters: [BrCurrencyInputFormatter()],
                        onChanged: (value) {
                          final monthly = parseBrCurrencyInput(value);
                          ctrlA.text = monthly > 0
                              ? formatBrCurrencyInitial(monthly * 10)
                              : '';
                        },
                        decoration: _campo(r'Mensal (R$)', cor),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        controller: ctrlA,
                        readOnly: true,
                        decoration: _campo(
                          'Anual (10 mensalidades)',
                          cor,
                          ajuda: '2 meses de desconto',
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(44),
                    backgroundColor: cor,
                  ),
                  onPressed: () => unawaited(_salvar(plan.id)),
                  icon: const Icon(Icons.save_rounded, size: 18),
                  label: const Text('Gravar plano'),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Deixe nome/faixa/limite iguais ao padrão (ou vazios) para '
                  'remover o override no Firestore.',
                  style: TextStyle(fontSize: 11, color: _cSlate, height: 1.35),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  InputDecoration _campo(
    String label,
    Color cor, {
    String? dica,
    String? ajuda,
  }) {
    return InputDecoration(
      labelText: label,
      hintText: dica,
      helperText: ajuda,
      isDense: true,
      filled: true,
      fillColor: cor.withValues(alpha: 0.05),
      labelStyle: TextStyle(color: cor, fontWeight: FontWeight.w700),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusMd),
        borderSide: BorderSide(color: cor.withValues(alpha: 0.28)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusMd),
        borderSide: BorderSide(color: cor.withValues(alpha: 0.28)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusMd),
        borderSide: BorderSide(color: cor, width: 1.6),
      ),
    );
  }

  Widget _banner(String texto, Color cor, IconData icone) {
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: cor.withValues(alpha: 0.09),
        borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusMd),
        border: Border.all(color: cor.withValues(alpha: 0.32)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icone, color: cor, size: 21),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              texto,
              style: TextStyle(fontSize: 12.5, height: 1.4, color: cor),
            ),
          ),
        ],
      ),
    );
  }
}
