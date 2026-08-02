import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart' hide showDatePicker;
import 'package:gestao_yahweh/core/finance_theme_context.dart';
import 'package:intl/intl.dart';

import 'package:gestao_yahweh/core/finance_app_colors.dart';
import 'package:gestao_yahweh/utils/date_picker_a11y.dart';
import 'package:gestao_yahweh/constants/finance_account_visuals.dart';
import 'package:gestao_yahweh/models/finance_account.dart';
import 'package:gestao_yahweh/models/user_profile.dart';
import 'package:gestao_yahweh/services/finance_accounts_service.dart';
import 'package:gestao_yahweh/services/finance_opening_balance_service.dart';
import 'package:gestao_yahweh/services/sensitive_balance_preferences.dart';
import 'package:gestao_yahweh/ui/pages/finance_page.dart' show FinanceInsightScope;
import 'package:gestao_yahweh/utils/finance_account_category_sheet_launcher.dart';
import 'package:gestao_yahweh/utils/finance_account_balance_utils.dart';
import 'package:gestao_yahweh/utils/finance_line_opening.dart';
import 'package:gestao_yahweh/utils/finance_transactions_realtime.dart';
import 'package:gestao_yahweh/utils/firestore_user_doc_id.dart';
import 'package:gestao_yahweh/utils/premium_upgrade.dart';
import 'package:gestao_yahweh/ui/widgets/finance_sparkline.dart';
import 'package:gestao_yahweh/ui/widgets/modern_module_ui.dart';

/// Resumo financeiro no Início — filtros de período, saldo de abertura e contas clicáveis.
class HomeFinanceOverviewPanel extends StatefulWidget {
  const HomeFinanceOverviewPanel({
    super.key,
    required this.uid,
    required this.profile,
    required this.onOpenFinanceiro,
  });

  final String uid;
  final UserProfile profile;
  final VoidCallback onOpenFinanceiro;

  @override
  State<HomeFinanceOverviewPanel> createState() => _HomeFinanceOverviewPanelState();
}

class _HomeFinanceOverviewPanelState extends State<HomeFinanceOverviewPanel> {
  static const _periods = ['Mês anterior', 'Mensal', 'Anual', 'Por período'];

  bool _hideBalances = false;
  String _selectedPeriod = 'Mensal';
  DateTime? _customRangeStart;
  DateTime? _customRangeEnd;

  String _saldoAberturaKey = '';
  ({double total, Map<String, double> byAccount})? _saldoAberturaCached;

  String get _userFsId => firestoreUserDocIdForAppShell(widget.uid);

  (DateTime, DateTime) _rangeForPeriod() {
    final now = DateTime.now();
    switch (_selectedPeriod) {
      case 'Mês anterior':
        final lastMonth = DateTime(now.year, now.month - 1);
        return (
          DateTime(lastMonth.year, lastMonth.month, 1),
          DateTime(lastMonth.year, lastMonth.month + 1, 0, 23, 59, 59),
        );
      case 'Mensal':
        return (
          DateTime(now.year, now.month, 1),
          DateTime(now.year, now.month + 1, 0, 23, 59, 59),
        );
      case 'Anual':
        return (
          DateTime(now.year, 1, 1),
          DateTime(now.year, 12, 31, 23, 59, 59),
        );
      case 'Por período':
        final start = _customRangeStart ?? DateTime(now.year, now.month, 1);
        final end = _customRangeEnd ?? now;
        final endNorm = end.isBefore(start) ? start : end;
        return (
          DateTime(start.year, start.month, start.day),
          DateTime(endNorm.year, endNorm.month, endNorm.day, 23, 59, 59),
        );
      default:
        return (
          DateTime(now.year, now.month, 1),
          DateTime(now.year, now.month + 1, 0, 23, 59, 59),
        );
    }
  }

  String _periodLabel(DateTime start, DateTime end) {
    switch (_selectedPeriod) {
      case 'Mês anterior':
      case 'Mensal':
        return '${_monthName(start.month)} ${start.year}';
      case 'Anual':
        return 'Ano ${start.year}';
      case 'Por período':
        final df = DateFormat('dd/MM/yy', 'pt_BR');
        return '${df.format(start)} — ${df.format(end)}';
      default:
        return '${_monthName(start.month)} ${start.year}';
    }
  }

  @override
  void initState() {
    super.initState();
    _loadPrefs();
    final (start, _) = _rangeForPeriod();
    _ensureSaldoAberturaForPeriod(start);
  }

  Future<void> _loadPrefs() async {
    final h = await SensitiveBalancePreferences.load();
    if (mounted) setState(() => _hideBalances = h);
  }

  void _ensureSaldoAberturaForPeriod(DateTime periodStart) {
    final key = '${periodStart.year}-${periodStart.month}-${periodStart.day}';
    if (_saldoAberturaKey == key && _saldoAberturaCached != null) return;
    _saldoAberturaKey = key;
    final peek = FinanceOpeningBalanceService.peekCached(
      uid: widget.uid,
      periodStart: periodStart,
      loadAccounts: false,
    );
    if (peek != null) {
      _saldoAberturaCached = peek;
    }
    unawaited(_loadSaldoAberturaIntoState(periodStart));
  }

  Future<void> _loadSaldoAberturaIntoState(DateTime periodStart) async {
    final fast = await FinanceOpeningBalanceService.load(
      uid: widget.uid,
      periodStart: periodStart,
      loadAccounts: false,
    );
    if (!mounted || _saldoAberturaKey != '${periodStart.year}-${periodStart.month}-${periodStart.day}') {
      return;
    }
    setState(() => _saldoAberturaCached = fast);
    final full = await FinanceOpeningBalanceService.load(
      uid: widget.uid,
      periodStart: periodStart,
      loadAccounts: true,
    );
    if (!mounted || _saldoAberturaKey != '${periodStart.year}-${periodStart.month}-${periodStart.day}') {
      return;
    }
    setState(() => _saldoAberturaCached = full);
  }

  void _applyPeriod(String period) {
    setState(() {
      _selectedPeriod = period;
      if (period == 'Por período' && _customRangeStart == null) {
        final now = DateTime.now();
        _customRangeStart = DateTime(now.year, now.month, 1);
        _customRangeEnd = now;
      }
    });
    final (start, _) = _rangeForPeriod();
    _ensureSaldoAberturaForPeriod(start);
  }

  static Map<String, double> _mergeAccountBalances(
    Map<String, double> openingByAccount,
    Map<String, double> periodByAccount,
  ) {
    final out = <String, double>{...openingByAccount};
    periodByAccount.forEach((id, val) {
      out[id] = (out[id] ?? 0) + val;
    });
    return out;
  }

  void _openAccountSheet({
    required BuildContext context,
    required DateTime start,
    required DateTime end,
    required List<FinanceAccount> accounts,
    FinanceAccount? account,
    required double? openingBalanceHint,
  }) {
    if (!widget.profile.hasActiveLicense) {
      mostrarAvisoSeLicencaInativa(context, widget.profile);
      return;
    }
    FinanceAccountCategorySheetLauncher.show(
      context: context,
      uid: widget.uid,
      profile: widget.profile,
      from: start,
      to: end,
      account: account,
      openingBalanceHint: openingBalanceHint,
      financeAccounts: accounts,
      onOpenFinanceModule: widget.onOpenFinanceiro,
      nearlyFullScreen: true,
    );
  }

  void _openFinanceInsight({
    required BuildContext context,
    required FinanceInsightScope scope,
    required DateTime start,
    required DateTime end,
    String? financeAccountFilterId,
    String? financeAccountFilterLabel,
    double? openingBalanceHint,
    Map<String, double>? openingByAccountHint,
  }) {
    FinanceAccountCategorySheetLauncher.showInsight(
      context: context,
      uid: widget.uid,
      profile: widget.profile,
      scope: scope,
      from: start,
      to: end,
      financeAccountFilterId: financeAccountFilterId,
      financeAccountFilterLabel: financeAccountFilterLabel,
      openingBalanceHint: openingBalanceHint,
      openingByAccountHint: openingByAccountHint,
    );
  }

  @override
  Widget build(BuildContext context) {
    final (start, end) = _rangeForPeriod();
    final periodLabel = _periodLabel(start, end);
    final saldoAbertura = _saldoAberturaCached?.total ?? 0.0;
    final openingByAccount = _saldoAberturaCached?.byAccount ?? const <String, double>{};

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF14532D), Color(0xFF15803D)],
                ),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(Icons.account_balance_wallet_rounded, color: Colors.white, size: 22),
            ),
            SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Seu Financeiro',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                      color: Color(0xFF0B1B4B),
                    ),
                  ),
                  Text(
                    'Resumo de $periodLabel · toque em receitas, despesas ou contas',
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: context.appTextSecondary,
                    ),
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: _hideBalances ? 'Mostrar valores' : 'Ocultar valores',
              onPressed: () async {
                final v = !_hideBalances;
                await SensitiveBalancePreferences.set(v);
                if (mounted) setState(() => _hideBalances = v);
              },
              icon: Icon(
                _hideBalances ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                color: AppColors.primary,
              ),
            ),
          ],
        ),
        SizedBox(height: 10),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          physics: const BouncingScrollPhysics(),
          child: Row(
            children: _periods.map((p) {
              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: _periodChip(
                  context: context,
                  period: p,
                  selected: _selectedPeriod == p,
                  onSelect: () => _applyPeriod(p),
                ),
              );
            }).toList(),
          ),
        ),
        if (_selectedPeriod == 'Por período') ...[
          SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: FilledButton.tonalIcon(
                  onPressed: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: _customRangeStart ?? start,
                      firstDate: DateTime(2000),
                      lastDate: DateTime(2030),
                    );
                    if (picked != null && mounted) {
                      setState(() => _customRangeStart = picked);
                      _ensureSaldoAberturaForPeriod(_rangeForPeriod().$1);
                    }
                  },
                  icon: Icon(Icons.calendar_today_rounded, size: 16),
                  label: Text(
                    'De ${DateFormat('dd/MM/yy', 'pt_BR').format(_customRangeStart ?? start)}',
                    style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700),
                  ),
                  style: FilledButton.styleFrom(
                    foregroundColor: AppColors.primary,
                    backgroundColor: AppColors.primary.withValues(alpha: 0.1),
                    padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
              SizedBox(width: 8),
              Expanded(
                child: FilledButton.tonalIcon(
                  onPressed: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: _customRangeEnd ?? end,
                      firstDate: _customRangeStart ?? DateTime(2000),
                      lastDate: DateTime(2030),
                    );
                    if (picked != null && mounted) {
                      setState(() => _customRangeEnd = picked);
                      _ensureSaldoAberturaForPeriod(_rangeForPeriod().$1);
                    }
                  },
                  icon: Icon(Icons.event_rounded, size: 16),
                  label: Text(
                    'Até ${DateFormat('dd/MM/yy', 'pt_BR').format(_customRangeEnd ?? end)}',
                    style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700),
                  ),
                  style: FilledButton.styleFrom(
                    foregroundColor: AppColors.primary,
                    backgroundColor: AppColors.primary.withValues(alpha: 0.1),
                    padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
            ],
          ),
        ],
        SizedBox(height: 12),
        StreamBuilder<List<QueryDocumentSnapshot<Map<String, dynamic>>>>(
          key: ValueKey('home_fin_${start.millisecondsSinceEpoch}_${end.millisecondsSinceEpoch}'),
          stream: financeTransactionsPeriodDocs(
            uid: _userFsId,
            rangeStart: start,
            rangeEnd: end,
          ),
          builder: (context, txSnap) {
            return StreamBuilder<List<FinanceAccount>>(
              stream: FinanceAccountsService().streamAccounts(_userFsId),
              builder: (context, accSnap) {
                final accounts = accSnap.data ?? const <FinanceAccount>[];
                final docs = txSnap.data ?? const [];
                double receitas = 0, despesas = 0;
                final byDay = <DateTime, double>{};

                for (final doc in docs) {
                  final d = doc.data();
                  final type = (d['type'] ?? 'expense').toString();
                  if ((d['status'] ?? 'paid').toString() != 'paid') continue;
                  final amt = ((d['amount'] ?? 0) as num).toDouble().abs();
                  final effective = FinanceLineOpening.effectiveDateTimeFromMap(d) ??
                      (d['date'] as Timestamp?)?.toDate();
                  if (effective == null) continue;
                  if (effective.isBefore(start) || effective.isAfter(end)) continue;

                  final day = DateTime(effective.year, effective.month, effective.day);
                  if (type == 'income') {
                    receitas += amt;
                    byDay[day] = (byDay[day] ?? 0) + amt;
                  } else {
                    despesas += amt;
                    byDay[day] = (byDay[day] ?? 0) - amt;
                  }
                }

                final creditCardIds = FinanceAccountBalanceUtils.creditCardAccountIds(accounts);
                final byAccPeriod = FinanceAccountBalanceUtils.netPaidByAccountEffective(
                  docs: docs,
                  from: start,
                  to: end,
                  creditCardIds: creditCardIds,
                );
                final byAcc = _mergeAccountBalances(openingByAccount, byAccPeriod);

                final saldoPeriodo = receitas - despesas;
                final saldoAcum = saldoAbertura + saldoPeriodo;
                final spark = _sparklineFrom(byDay);

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(20),
                        gradient: const LinearGradient(
                          colors: [Color(0xFF14532D), Color(0xFF166534), Color(0xFF15803D)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.saldoPositive.withValues(alpha: 0.28),
                            blurRadius: 16,
                            offset: const Offset(0, 6),
                          ),
                        ],
                      ),
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            periodLabel,
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.92),
                              fontWeight: FontWeight.w700,
                              fontSize: 12,
                            ),
                          ),
                          SizedBox(height: 10),
                          _metricTile(
                            context,
                            'Saldo acumulado',
                            saldoAcum,
                            saldoAcum >= 0 ? AppColors.saldoPositive : AppColors.saldoNegative,
                            hint: 'Gráficos e lançamentos',
                            onTap: () => _openFinanceInsight(
                              context: context,
                              scope: FinanceInsightScope.balance,
                              start: start,
                              end: end,
                              openingBalanceHint: saldoAbertura,
                              openingByAccountHint: openingByAccount,
                            ),
                          ),
                          SizedBox(height: 8),
                          Row(
                            children: [
                              Expanded(
                                child: _metricTile(
                                  context,
                                  'Receitas',
                                  receitas,
                                  AppColors.saldoPositive,
                                  hint: 'Ver e editar',
                                  onTap: () => _openFinanceInsight(
                                    context: context,
                                    scope: FinanceInsightScope.income,
                                    start: start,
                                    end: end,
                                    openingBalanceHint: saldoAbertura,
                                    openingByAccountHint: openingByAccount,
                                  ),
                                ),
                              ),
                              SizedBox(width: 8),
                              Expanded(
                                child: _metricTile(
                                  context,
                                  'Despesas',
                                  despesas,
                                  AppColors.saldoNegative,
                                  hint: 'Ver e editar',
                                  onTap: () => _openFinanceInsight(
                                    context: context,
                                    scope: FinanceInsightScope.expense,
                                    start: start,
                                    end: end,
                                    openingBalanceHint: saldoAbertura,
                                    openingByAccountHint: openingByAccount,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          if (spark.length >= 2) ...[
                            SizedBox(height: 12),
                            SizedBox(
                              width: double.infinity,
                              height: 36,
                              child: FinanceSparkline(
                                values: spark,
                                color: Colors.white.withValues(alpha: 0.9),
                              ),
                            ),
                          ],
                          SizedBox(height: 10),
                          Align(
                            alignment: Alignment.centerRight,
                            child: TextButton.icon(
                              onPressed: widget.onOpenFinanceiro,
                              icon: Icon(
                                Icons.open_in_new_rounded,
                                size: 16,
                                color: Colors.white.withValues(alpha: 0.92),
                              ),
                              label: Text(
                                'Abrir Financeiro',
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.92),
                                  fontWeight: FontWeight.w800,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    SizedBox(height: 12),
                    if (accounts.isEmpty)
                      _emptyAccountsCard()
                    else
                      SizedBox(
                        height: 118,
                        child: ListView(
                          scrollDirection: Axis.horizontal,
                          physics: const BouncingScrollPhysics(),
                          children: [
                            _accountCard(
                              title: 'Todas',
                              subtitle: SensitiveBalancePreferences.formatBrl(
                                saldoAcum,
                                hidden: _hideBalances,
                              ),
                              gradient: const [AppColors.primary, AppColors.deepBlue],
                              icon: Icons.dashboard_rounded,
                              onTap: () => _openAccountSheet(
                                context: context,
                                start: start,
                                end: end,
                                accounts: accounts,
                                openingBalanceHint: saldoAbertura,
                              ),
                            ),
                            ...accounts.map((a) {
                              final vis = financeAccountVisualFor(a);
                              final accSaldo = byAcc[a.id] ?? (openingByAccount[a.id] ?? 0);
                              return _accountCard(
                                title: a.displayName,
                                subtitle: SensitiveBalancePreferences.formatBrl(
                                  accSaldo,
                                  hidden: _hideBalances,
                                ),
                                gradient: vis.gradient,
                                icon: vis.icon,
                                onTap: () => _openAccountSheet(
                                  context: context,
                                  start: start,
                                  end: end,
                                  accounts: accounts,
                                  account: a,
                                  openingBalanceHint: openingByAccount[a.id],
                                ),
                              );
                            }),
                          ],
                        ),
                      ),
                  ],
                );
              },
            );
          },
        ),
      ],
    );
  }

  Widget _periodChip({
    required BuildContext context,
    required String period,
    required bool selected,
    required VoidCallback onSelect,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onSelect,
        borderRadius: BorderRadius.circular(14),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            gradient: selected
                ? const LinearGradient(
                    colors: [Color(0xFF14532D), Color(0xFF15803D)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  )
                : null,
            color: selected ? null : context.appChipIdleBg,
            border: Border.all(
              color: selected ? Colors.transparent : context.appChipIdleBorder,
            ),
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: const Color(0xFF14532D).withValues(alpha: 0.22),
                      blurRadius: 10,
                      offset: const Offset(0, 3),
                    ),
                  ]
                : null,
          ),
          child: Text(
            period,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w800,
              color: selected ? Colors.white : const Color(0xFF14532D),
            ),
          ),
        ),
      ),
    );
  }

  Widget _metricTile(
    BuildContext context,
    String label,
    double value,
    Color color, {
    String? hint,
    VoidCallback? onTap,
  }) {
    final tile = Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: ModernModuleUI.cardBg(context),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
          if (hint != null && onTap != null) ...[
            SizedBox(height: 2),
            Text(
              hint,
              style: TextStyle(
                fontSize: 9.5,
                fontWeight: FontWeight.w700,
                color: color.withValues(alpha: 0.72),
              ),
            ),
          ],
          SizedBox(height: 4),
          Text(
            SensitiveBalancePreferences.formatBrl(value, hidden: _hideBalances),
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w900,
              color: color,
            ),
          ),
        ],
      ),
    );
    if (onTap == null) return tile;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: tile,
      ),
    );
  }

  Widget _accountCard({
    required String title,
    required String subtitle,
    required List<Color> gradient,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.only(right: 10),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Ink(
            width: 148,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              gradient: LinearGradient(
                colors: gradient,
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              boxShadow: [
                BoxShadow(
                  color: gradient.first.withValues(alpha: 0.25),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon, color: Colors.white, size: 22),
                const Spacer(),
                Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    fontSize: 12.5,
                    height: 1.15,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  subtitle,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.92),
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _emptyAccountsCard() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: ModernModuleUI.cardBg(context),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Cadastre bancos e cartões para ver saldos e gráficos aqui.',
            style: TextStyle(fontSize: 13, height: 1.35),
          ),
          SizedBox(height: 10),
          FilledButton.icon(
            onPressed: widget.onOpenFinanceiro,
            icon: Icon(Icons.add_card_rounded),
            label: Text('Abrir Financeiro'),
          ),
        ],
      ),
    );
  }

  List<double> _sparklineFrom(Map<DateTime, double> byDay) {
    if (byDay.isEmpty) return const [];
    final keys = byDay.keys.toList()..sort();
    var run = 0.0;
    final out = <double>[];
    for (final k in keys) {
      run += byDay[k] ?? 0;
      out.add(run);
    }
    return out.length >= 2 ? out : const [];
  }

  String _monthName(int m) {
    const names = [
      'Janeiro', 'Fevereiro', 'Março', 'Abril', 'Maio', 'Junho',
      'Julho', 'Agosto', 'Setembro', 'Outubro', 'Novembro', 'Dezembro',
    ];
    return names[m - 1];
  }
}
