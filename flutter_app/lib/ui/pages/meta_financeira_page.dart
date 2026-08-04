import 'dart:async';
import 'package:flutter/material.dart' hide showDatePicker;
import 'package:gestao_yahweh/core/finance_theme_context.dart';
import 'package:gestao_yahweh/ui/widgets/fast_text_field.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart' as fa;
import 'package:intl/intl.dart';
import 'package:gestao_yahweh/models/user_profile.dart';
import 'package:gestao_yahweh/models/financial_goal.dart';
import 'package:gestao_yahweh/core/finance_app_colors.dart';
import 'package:gestao_yahweh/constants/finance_tips.dart';
import 'package:gestao_yahweh/constants/currency_formats.dart';
import 'package:gestao_yahweh/services/firestore_stream_utils.dart';
import 'package:gestao_yahweh/utils/premium_upgrade.dart';
import 'package:gestao_yahweh/ui/widgets/create_financial_goal_dialog.dart';
import 'package:gestao_yahweh/ui/widgets/goal_52_weeks_objective_card.dart';
import 'package:gestao_yahweh/utils/date_picker_a11y.dart';
import 'package:gestao_yahweh/core/data/church_ui_collections.dart';
import 'package:gestao_yahweh/ui/widgets/brl_amount_text_field.dart';
import 'package:gestao_yahweh/utils/keyboard_form_scaffold.dart';
import 'package:gestao_yahweh/utils/home_shell_layout.dart';
import 'package:gestao_yahweh/ui/widgets/goal_finance_account_field.dart';

/// Categorias de metas (estrutura base Premium).
final List<GoalCategory> kGoalCategories = GoalCategory.values.toList();

/// Sugestões rápidas de metas para o usuário escolher ou inspirar.
const List<Map<String, String>> kMetaSugestoes = [
  {'title': 'Comprar um carro', 'emoji': '🚗', 'cat': 'veiculo'},
  {
    'title': 'Pagar contas / quitar dívidas',
    'emoji': '📋',
    'cat': 'personalizada'
  },
  {
    'title': 'Reserva de emergência',
    'emoji': '🛡️',
    'cat': 'reserva_emergencia'
  },
  {'title': 'Viagem', 'emoji': '✈️', 'cat': 'viagem'},
  {'title': 'Reforma da casa', 'emoji': '🏠', 'cat': 'casa'},
  {'title': 'Curso ou especialização', 'emoji': '📚', 'cat': 'estudo'},
  {'title': 'Investimento', 'emoji': '📈', 'cat': 'investimento'},
  {'title': 'Outro', 'emoji': '🎯', 'cat': 'personalizada'},
];

class MetaFinanceiraScreen extends StatefulWidget {
  final String uid;
  final UserProfile profile;
  final void Function(int index)? onNavigateTo;

  /// Quando dentro do [HomeShell]: scroll volta ao topo ao mudar de módulo.
  final ScrollController? shellScrollController;

  const MetaFinanceiraScreen({
    super.key,
    required this.uid,
    required this.profile,
    this.onNavigateTo,
    this.shellScrollController,
  });

  @override
  State<MetaFinanceiraScreen> createState() => _MetaFinanceiraScreenState();
}

enum _GoalListSort { prazo, titulo, valorAlvoDesc }

class _MetaFinanceiraScreenState extends State<MetaFinanceiraScreen> {
  StreamSubscription<fa.User?>? _authStateSub;

  _GoalListSort _goalListSort = _GoalListSort.prazo;

  /// Metas do Financeiro são por igreja — nunca pela sessão pessoal.
  String get _userDocId => widget.uid.trim();

  CollectionReference<Map<String, dynamic>> get _goals =>
      ChurchUiCollections.churchDoc(_userDocId).collection('goals');
  CollectionReference<Map<String, dynamic>> get _tx =>
      ChurchUiCollections.financeiro(_userDocId);
  DocumentReference<Map<String, dynamic>> get _planningRef =>
      ChurchUiCollections.config(_userDocId).doc('finance_planning');

  @override
  void initState() {
    super.initState();
    _authStateSub = fa.FirebaseAuth.instance.authStateChanges().listen((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _authStateSub?.cancel();
    _authStateSub = null;
    super.dispose();
  }

  /// Dica do dia (rotacionada pelo dia do ano).
  String get _dicaDoDia {
    final dayOfYear =
        DateTime.now().difference(DateTime(DateTime.now().year, 1, 1)).inDays;
    return kFinanceTips[dayOfYear % kFinanceTips.length];
  }

  Future<void> _criarMeta(BuildContext context) async {
    await showCreateFinancialGoalDialog(
      context,
      profile: widget.profile,
      uid: widget.uid,
    );
  }

  /// Barra superior padrão dos previews/sheets do módulo Meta — pedido do
  /// usuário: cada preview tem **«Voltar»** à esquerda (paridade total
  /// iPhone / iOS / Android / Web) + atalho **«X»** à direita. Mesmo
  /// visual dos previews do Painel Inicial e dos demais módulos.
  Widget _metaPreviewTopBar(BuildContext ctx) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 12, 8, 4),
      child: Row(
        children: [
          Material(
            color: AppColors.primary.withValues(alpha: 0.08),
            shape: const CircleBorder(),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: () => Navigator.of(ctx).pop(),
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Icon(
                  Icons.arrow_back_rounded,
                  color: AppColors.primary,
                  size: 22,
                  semanticLabel: 'Voltar',
                ),
              ),
            ),
          ),
          SizedBox(width: 6),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            style: TextButton.styleFrom(
              minimumSize: const Size(44, 44),
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
              foregroundColor: AppColors.primary,
            ),
            child: Text(
              'Voltar',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.2,
              ),
            ),
          ),
          const Spacer(),
          Material(
            color: Colors.grey.shade100,
            shape: const CircleBorder(),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: () => Navigator.of(ctx).pop(),
              child: Padding(
                padding: EdgeInsets.all(8),
                child: Icon(
                  Icons.close_rounded,
                  size: 22,
                  color: context.appDeepTitle,
                  semanticLabel: 'Fechar',
                ),
              ),
            ),
          ),
          SizedBox(width: 4),
        ],
      ),
    );
  }

  Future<void> _editarMeta(BuildContext context,
      QueryDocumentSnapshot<Map<String, dynamic>> goalDoc) async {
    if (!widget.profile.hasActiveLicense) {
      mostrarAvisoSeLicencaInativa(context, widget.profile);
      return;
    }
    final data = goalDoc.data();
    final titleCtrl =
        TextEditingController(text: (data['title'] ?? '').toString());
    final targetCtrl = TextEditingController(
        text:
            CurrencyFormats.formatBRLInput((data['targetAmount'] ?? 0) as num));
    DateTime? dueDate = (data['dueDate'] as Timestamp?)?.toDate();
    GoalPriority priority = GoalPriority.media;
    try {
      priority = GoalPriority.values
          .firstWhere((e) => e.name == (data['priority'] ?? ''));
    } catch (_) {}
    final storedAccount = (data['financeAccountId'] ?? '').toString().trim();
    String? financeAccountId = storedAccount.isEmpty ? null : storedAccount;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          insetPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
          titlePadding: const EdgeInsets.fromLTRB(22, 20, 22, 4),
          contentPadding: const EdgeInsets.fromLTRB(22, 8, 22, 8),
          actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          title: goalFormDialogHeader(
            context,
            title: 'Editar meta',
            icon: Icons.savings_rounded,
            subtitle: 'Atualize dados e a conta vinculada aos depósitos.',
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                FastTextField(
                  controller: titleCtrl,
                  decoration: _metaInputDecoration(labelText: 'Nome da meta'),
                ),
                SizedBox(height: 12),
                BrlAmountTextField(
                  controller: targetCtrl,
                  decoration: _metaInputDecoration(
                    labelText: 'Valor alvo (R\$)',
                    prefixText: 'R\$ ',
                  ),
                ),
                SizedBox(height: 14),
                GoalFinanceAccountField(
                  uid: widget.uid,
                  selectedAccountId: financeAccountId,
                  onChanged: (v) => setState(() => financeAccountId = v),
                ),
                SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        dueDate == null
                            ? 'Sem prazo'
                            : 'Prazo: ${DateFormat('dd/MM/yyyy').format(dueDate!)}',
                        style: TextStyle(
                            fontSize: 13, color: context.appTextSecondary),
                      ),
                    ),
                    FilledButton.icon(
                      onPressed: () async {
                        final picked = await showDatePicker(
                          context: ctx,
                          initialDate: dueDate ??
                              DateTime.now().add(const Duration(days: 365)),
                          firstDate: DateTime.now(),
                          lastDate: DateTime(2030, 12, 31),
                        );
                        if (picked != null) setState(() => dueDate = picked);
                      },
                      icon: Icon(Icons.calendar_today_rounded, size: 18),
                      label: Text('Alterar'),
                      style: FilledButton.styleFrom(
                        backgroundColor:
                            AppColors.accent.withValues(alpha: 0.16),
                        foregroundColor: AppColors.accent,
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 10),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14)),
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 12),
                Text('Prioridade',
                    style:
                        TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: GoalPriority.values.map((p) {
                    final sel = priority == p;
                    return _buildSortChip(
                      label: p.label,
                      selected: sel,
                      onTap: () => setState(() => priority = p),
                      active: _priorityActiveColor(p),
                    );
                  }).toList(),
                ),
              ],
            ),
          ),
          actions: [
            Wrap(
              alignment: WrapAlignment.end,
              spacing: 10,
              runSpacing: 10,
              children: [
                _metaDialogCancel(onPressed: () => Navigator.pop(ctx, false)),
                _metaDialogGradientButton(
                  label: 'Salvar alterações',
                  onPressed: () => Navigator.pop(ctx, true),
                ),
              ],
            ),
          ],
        ),
      ),
    );

    try {
      if (ok != true) return;
      final title = titleCtrl.text.trim();
      final target = CurrencyFormats.parseBRLInput(targetCtrl.text) ?? 0;
      if (title.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Informe o nome da meta.')));
        }
        return;
      }
      if (target <= 0) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Informe o valor alvo.')));
        }
        return;
      }
      if (financeAccountId == null || financeAccountId!.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text(
                    'Selecione ou cadastre a conta onde o dinheiro será guardado.')),
          );
        }
        return;
      }
      try {
        await goalDoc.reference.update({
          'title': title,
          'targetAmount': target,
          'dueDate': dueDate != null ? Timestamp.fromDate(dueDate!) : null,
          'priority': priority.name,
          'financeAccountId': financeAccountId,
        });
        if (mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(const SnackBar(content: Text('Meta atualizada.')));
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text(
                  'Erro ao atualizar: ${e.toString().split('\n').first}')));
        }
      }
    } finally {
      titleCtrl.dispose();
      targetCtrl.dispose();
    }
  }

  Future<void> _excluirMeta(BuildContext context,
      QueryDocumentSnapshot<Map<String, dynamic>> goalDoc) async {
    if (!widget.profile.hasActiveLicense) {
      mostrarAvisoSeLicencaInativa(context, widget.profile);
      return;
    }
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: _metaDialogTitleRow(
            icon: Icons.flag_outlined, title: 'Excluir meta'),
        content: Text(
          'Excluir "${(goalDoc.data()['title'] ?? 'Meta').toString()}"? Os aportes já registrados não serão removidos.',
        ),
        actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        actions: [
          Wrap(
            alignment: WrapAlignment.end,
            spacing: 10,
            children: [
              _metaDialogCancel(onPressed: () => Navigator.pop(ctx, false)),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.error,
                  foregroundColor: Colors.white,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                ),
                child: Text('Excluir',
                    style: TextStyle(fontWeight: FontWeight.w800)),
              ),
            ],
          ),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      await goalDoc.reference.delete();
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Meta excluída.')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content:
                Text('Erro ao excluir: ${e.toString().split('\n').first}')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final padding = MediaQuery.paddingOf(context);
    final isNarrow = width < 720;
    final isCompact = width < 400;
    final embeddedInShell = widget.shellScrollController != null;

    return Scaffold(
      resizeToAvoidBottomInset: scaffoldKeyboardResizeToAvoidBottomInset(
        embeddedInHomeShell: embeddedInShell,
      ),
      backgroundColor: Colors.transparent,
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: context.appBodyGradient,
            stops: context.isDarkMode
                ? const [0.0, 0.5, 1.0]
                : const [0.0, 0.55, 1.0],
          ),
        ),
        child: SafeArea(
          top: false,
          bottom: homeShellSafeAreaBottom(embeddedInHomeShell: embeddedInShell),
          left: true,
          right: true,
          child: RepaintBoundary(
            child: CustomScrollView(
              controller: widget.shellScrollController,
              physics: const BouncingScrollPhysics(
                parent: AlwaysScrollableScrollPhysics(),
              ),
              slivers: [
                SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(
                      (isNarrow ? 16 : 24) + padding.left,
                      isNarrow ? 6 : 4,
                      (isNarrow ? 16 : 24) + padding.right,
                      homeShellScrollBottomPadding(
                        context,
                        embeddedInHomeShell: embeddedInShell,
                        tail: 20,
                      ),
                    ),
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 900),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (_userDocId.isNotEmpty)
                              StreamBuilder<
                                  DocumentSnapshot<Map<String, dynamic>>>(
                                key: ValueKey<String>(
                                    'meta-planning-$_userDocId'),
                                stream: _planningRef.watchSafe(),
                                builder: (context, snap) {
                                  final enabled =
                                      (snap.data?.data()?['dailyTipsEnabled'] ??
                                          false) as bool;
                                  if (!enabled) return const SizedBox.shrink();
                                  return Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      _buildDicaCard(context),
                                      SizedBox(height: 24),
                                    ],
                                  );
                                },
                              ),
                            if (isCompact)
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  _buildModuleHeroHeader(isCompact: true),
                                  SizedBox(height: 16),
                                  Text('Minhas metas',
                                      style: TextStyle(
                                          fontSize: 20,
                                          fontWeight: FontWeight.w900,
                                          color: context.appDeepTitle)),
                                  SizedBox(height: 12),
                                  _buildNovaMetaButton(
                                      expand: true, label: 'Nova meta'),
                                ],
                              )
                            else
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  _buildModuleHeroHeader(isCompact: false),
                                  SizedBox(height: 16),
                                  Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    crossAxisAlignment:
                                        CrossAxisAlignment.center,
                                    children: [
                                      Text('Minhas metas',
                                          style: TextStyle(
                                              fontSize: 20,
                                              fontWeight: FontWeight.w900,
                                              color: context.appDeepTitle)),
                                      _buildNovaMetaButton(
                                          expand: false, label: 'Nova meta'),
                                    ],
                                  ),
                                ],
                              ),
                            SizedBox(height: 12),
                            Wrap(
                              spacing: 10,
                              runSpacing: 10,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                Text(
                                  'Ordenar metas:',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                    color: context.appTextSecondary,
                                  ),
                                ),
                                _buildSortChip(
                                  label: 'Prazo',
                                  selected:
                                      _goalListSort == _GoalListSort.prazo,
                                  onTap: () => setState(() =>
                                      _goalListSort = _GoalListSort.prazo),
                                  active: _sortPrazo,
                                ),
                                _buildSortChip(
                                  label: 'Título A-Z',
                                  selected:
                                      _goalListSort == _GoalListSort.titulo,
                                  onTap: () => setState(() =>
                                      _goalListSort = _GoalListSort.titulo),
                                  active: _sortTitulo,
                                ),
                                _buildSortChip(
                                  label: 'Valor alvo',
                                  selected: _goalListSort ==
                                      _GoalListSort.valorAlvoDesc,
                                  onTap: () => setState(() => _goalListSort =
                                      _GoalListSort.valorAlvoDesc),
                                  active: _sortValor,
                                  onActive: const Color(0xFF78350F),
                                  onActiveMuted: const Color(0xFF78350F),
                                ),
                              ],
                            ),
                            SizedBox(height: 12),
                            _buildGoalsList(context),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Cabeçalho colorido do módulo Meta Financeira.
  Widget _buildModuleHeroHeader({required bool isCompact}) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(isCompact ? 16 : 20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        gradient: const LinearGradient(
          colors: [Color(0xFF4F46E5), Color(0xFF7C3AED), Color(0xFFEC4899)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF7C3AED).withValues(alpha: 0.32),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(14),
                ),
                child:
                    Icon(Icons.savings_rounded, color: Colors.white, size: 26),
              ),
              SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Meta Financeira',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    fontSize: 22,
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: 8),
          Text(
            'Projeto 52 semanas - viagem, carro, casa, reforma, quitar dívidas',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.92),
              fontWeight: FontWeight.w600,
              fontSize: isCompact ? 12 : 13,
              height: 1.35,
            ),
          ),
        ],
      ),
    );
  }

  /// CTA principal — gradiente + sombra (visual premium).
  Widget _buildNovaMetaButton(
      {required bool expand, String label = 'Nova meta'}) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _criarMeta(context),
        borderRadius: BorderRadius.circular(18),
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Color(0xFF2563EB),
                Color(0xFF1D4ED8),
                Color(0xFF0D9488),
              ],
            ),
            boxShadow: [
              BoxShadow(
                color: Color(0xFF0D9488).withValues(alpha: 0.38),
                blurRadius: 14,
                offset: const Offset(0, 5),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.22),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(Icons.add_rounded, color: Colors.white, size: 22),
                ),
                SizedBox(width: 10),
                Text(
                  label,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                    letterSpacing: 0.2,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static const Color _sortPrazo = Color(0xFF0D9488);
  static const Color _sortTitulo = Color(0xFF4F46E5);
  static const Color _sortValor = Color(0xFFF59E0B);

  Widget _buildSortChip({
    required String label,
    required bool selected,
    required VoidCallback onTap,
    required Color active,
    Color onActive = Colors.white,
    Color? onActiveMuted,
  }) {
    final muted = onActiveMuted ?? onActive;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(22),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: selected ? active : context.appChipIdleBg,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(
              color: selected
                  ? active.withValues(alpha: 0.95)
                  : context.appChipIdleBorder,
              width: selected ? 0 : 1.2,
            ),
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: active.withValues(alpha: 0.35),
                      blurRadius: 10,
                      offset: const Offset(0, 3),
                    ),
                  ]
                : [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.04),
                      blurRadius: 4,
                      offset: const Offset(0, 1),
                    ),
                  ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (selected) ...[
                Icon(Icons.check_rounded, size: 18, color: onActive),
                SizedBox(width: 5),
              ],
              Text(
                label,
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 13,
                  color: selected ? muted : Colors.grey.shade700,
                  letterSpacing: 0.1,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Barra de progresso com gradiente e altura confortável para leitura.

  static const LinearGradient _metaCtaGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      Color(0xFF2563EB),
      Color(0xFF1D4ED8),
      Color(0xFF0D9488),
    ],
  );

  Widget _metaDialogTitleRow({required IconData icon, required String title}) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            gradient: _metaCtaGradient,
            borderRadius: BorderRadius.circular(14),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF0D9488).withValues(alpha: 0.28),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Icon(icon, color: Colors.white, size: 22),
        ),
        SizedBox(width: 12),
        Expanded(
          child: Text(
            title,
            style: TextStyle(
              fontSize: 19,
              fontWeight: FontWeight.w800,
              color: context.appDeepTitle,
              height: 1.2,
            ),
          ),
        ),
      ],
    );
  }

  InputDecoration _metaInputDecoration({
    required String labelText,
    String? hintText,
    Widget? prefixIcon,
    String? prefixText,
    String? suffixText,
  }) {
    final r = BorderRadius.circular(14);
    return InputDecoration(
      labelText: labelText,
      hintText: hintText,
      prefixIcon: prefixIcon,
      prefixText: prefixText,
      suffixText: suffixText,
      filled: true,
      fillColor: context.appInputFill,
      border: OutlineInputBorder(borderRadius: r),
      enabledBorder: OutlineInputBorder(
        borderRadius: r,
        borderSide: BorderSide(color: Colors.grey.shade300),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: r,
        borderSide: const BorderSide(color: AppColors.accent, width: 2),
      ),
    );
  }

  Widget _metaDialogCancel({required VoidCallback onPressed}) {
    return OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        foregroundColor: const Color(0xFF334155),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        side: BorderSide(color: Colors.grey.shade300, width: 1.2),
      ),
      child: Text('Cancelar', style: TextStyle(fontWeight: FontWeight.w700)),
    );
  }

  Widget _metaDialogGradientButton(
      {required String label, required VoidCallback onPressed}) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(14),
        child: Ink(
          decoration: BoxDecoration(
            gradient: _metaCtaGradient,
            borderRadius: BorderRadius.circular(14),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF0D9488).withValues(alpha: 0.32),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            child: Text(
              label,
              style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  fontSize: 15),
            ),
          ),
        ),
      ),
    );
  }

  Color _priorityActiveColor(GoalPriority p) {
    return switch (p) {
      GoalPriority.alta => AppColors.error,
      GoalPriority.media => AppColors.primary,
      GoalPriority.baixa => const Color(0xFF64748B),
    };
  }

  Widget _buildDicaCard(BuildContext context) {
    final isCompact = MediaQuery.sizeOf(context).width < 400;
    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(isCompact ? 14 : 18, isCompact ? 14 : 16,
          isCompact ? 14 : 18, isCompact ? 14 : 16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppColors.deepBlueDark.withValues(alpha: 0.92),
            const Color(0xFF134E6F),
            AppColors.accent.withValues(alpha: 0.88),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
        boxShadow: [
          BoxShadow(
              color: AppColors.accent.withValues(alpha: 0.22),
              blurRadius: 18,
              offset: const Offset(0, 8)),
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 12,
              offset: const Offset(0, 4)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(Icons.lightbulb_rounded,
                    color: Colors.amber.shade200, size: isCompact ? 22 : 24),
              ),
              SizedBox(width: isCompact ? 10 : 12),
              Expanded(
                child: Text(
                  'Dica do dia',
                  style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      fontSize: 15,
                      letterSpacing: 0.2),
                ),
              ),
            ],
          ),
          SizedBox(height: 10),
          Text(
            _dicaDoDia,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.95),
              fontSize: isCompact ? 13 : 14,
              height: 1.45,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGoalsList(BuildContext context) {
    final id = _userDocId;
    if (id.isEmpty) {
      return Padding(
        padding: EdgeInsets.all(40),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(strokeWidth: 2),
              SizedBox(height: 16),
              Text('A sincronizar sessão…', textAlign: TextAlign.center),
            ],
          ),
        ),
      );
    }
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      key: ValueKey<String>('meta-goals-$id'),
      stream: FirebaseFirestore.instance
          .collection('users')
          .doc(id)
          .collection('goals')
          .where('status', isEqualTo: 'active')
          .watchSafe(),
      builder: (context, snap) {
        if (snap.hasError) {
          return Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.error_outline_rounded,
                    size: 48, color: Colors.orange.shade700),
                SizedBox(height: 16),
                Text('Erro ao carregar metas. Tente novamente.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: context.appTextSecondary)),
                SizedBox(height: 16),
                FilledButton.icon(
                    onPressed: () => setState(() {}),
                    icon: Icon(Icons.refresh_rounded),
                    label: Text('Atualizar')),
              ],
            ),
          );
        }
        if (snap.connectionState == ConnectionState.waiting && !snap.hasData) {
          return Padding(
              padding: EdgeInsets.all(40),
              child: Center(child: CircularProgressIndicator()));
        }
        var docs = snap.data?.docs ?? [];
        if (docs.isEmpty) {
          return _buildEmptyGoals();
        }
        docs = docs.toList()
          ..sort((a, b) {
            final da = a.data();
            final db = b.data();
            switch (_goalListSort) {
              case _GoalListSort.prazo:
                final ta = da['dueDate'] as Timestamp?;
                final tb = db['dueDate'] as Timestamp?;
                if (ta == null && tb == null) return 0;
                if (ta == null) return 1;
                if (tb == null) return -1;
                return ta.compareTo(tb);
              case _GoalListSort.titulo:
                return (da['title'] ?? '')
                    .toString()
                    .toLowerCase()
                    .compareTo((db['title'] ?? '').toString().toLowerCase());
              case _GoalListSort.valorAlvoDesc:
                return ((db['targetAmount'] ?? 0) as num)
                    .compareTo((da['targetAmount'] ?? 0) as num);
            }
          });
        return Column(
          children: docs.map((doc) => _buildGoalCard(context, doc)).toList(),
        );
      },
    );
  }

  Widget _buildEmptyGoals() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 24),
      decoration: context.appPanelDecoration(radius: 24),
      child: Column(
        children: [
          Icon(Icons.flag_rounded, size: 64, color: Colors.grey.shade300),
          SizedBox(height: 16),
          Text(
            'Nenhuma meta ainda',
            style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: context.appDeepTitle),
          ),
          SizedBox(height: 8),
          Text(
            'Crie uma meta com Projeto 52 semanas - o app monta a programação semanal automaticamente.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 14, color: context.appTextSecondary),
          ),
          SizedBox(height: 24),
          _buildNovaMetaButton(
              expand: true, label: 'Criar minha primeira meta'),
        ],
      ),
    );
  }

  /// Cor do indicador de progresso: verde = no prazo, amarelo = risco, vermelho = atrasado.

  Widget _buildGoalCard(BuildContext context,
      QueryDocumentSnapshot<Map<String, dynamic>> goalDoc) {
    return Goal52WeeksObjectiveCard(
      goalDoc: goalDoc,
      uid: widget.uid,
      profile: widget.profile,
      margin: const EdgeInsets.only(bottom: 20),
      onEditGoal: () => _editarMeta(context, goalDoc),
      onDeleteGoal: () => _excluirMeta(context, goalDoc),
    );
  }
}
