import 'package:flutter/material.dart';

import 'package:gestao_yahweh/core/finance_app_colors.dart';

/// Card de resumo do período no topo do Financeiro — visual inspirado no
/// dashboard "Controle Total" (cartão cheio, KPIs em destaque, "Saldo por
/// contas" e exportação em PDF), mas as cores vêm sempre de [AppColors]
/// (mesma paleta de marca usada em todo o `finance_page.dart`) em vez de
/// tons soltos, e saldo/abertura mudam de verde para vermelho conforme o
/// sinal — igual ao resto do painel (KPIs, listas, relatórios).
class ControleTotalFinanceDashboardCard extends StatelessWidget {
  const ControleTotalFinanceDashboardCard({
    super.key,
    required this.monthLabel,
    required this.saldoAbertura,
    required this.receitas,
    required this.despesas,
    required this.saldo,
    required this.onTapSaldoAbertura,
    required this.onTapReceitas,
    required this.onTapDespesas,
    required this.onTapSaldo,
    required this.onTapSaldoContas,
    required this.onExportPdf,
  });

  final String monthLabel;
  final String saldoAbertura;
  final String receitas;
  final String despesas;
  final String saldo;
  final VoidCallback onTapSaldoAbertura;
  final VoidCallback onTapReceitas;
  final VoidCallback onTapDespesas;
  final VoidCallback onTapSaldo;
  final VoidCallback onTapSaldoContas;
  final VoidCallback onExportPdf;

  /// [CurrencyFormats.formatBRL] prefixa negativos com "R$ -" — evita
  /// depender do valor numérico bruto (o card só recebe texto já formatado).
  static bool _isNegative(String formatted) => formatted.contains('-');

  @override
  Widget build(BuildContext context) {
    final saldoAberturaColor =
        _isNegative(saldoAbertura) ? AppColors.saldoNegative : AppColors.saldoPositive;
    final saldoColor =
        _isNegative(saldo) ? AppColors.saldoNegative : AppColors.saldoPositive;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: AppColors.logoGradient,
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.deepBlueDark.withValues(alpha: 0.28),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(99),
                ),
                child: Text(
                  monthLabel,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                    letterSpacing: 0.2,
                  ),
                ),
              ),
              const Spacer(),
              Icon(
                Icons.account_balance_wallet_rounded,
                color: Colors.white.withValues(alpha: 0.55),
                size: 22,
              ),
            ],
          ),
          const SizedBox(height: 14),
          InkWell(
            onTap: onTapSaldoAbertura,
            borderRadius: BorderRadius.circular(20),
            child: _kpiBox(
              title: 'Saldo de abertura',
              value: saldoAbertura,
              titleColor: saldoAberturaColor,
              valueColor: saldoAberturaColor,
              subtitle: 'Toque para ver lançamentos',
            ),
          ),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: InkWell(
                  onTap: onTapReceitas,
                  borderRadius: BorderRadius.circular(18),
                  child: _kpiBox(
                    title: 'Receitas',
                    value: receitas,
                    titleColor: AppColors.financeReceita,
                    valueColor: AppColors.financeReceita,
                    subtitle: 'Toque para ver lançamentos',
                    compact: true,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: InkWell(
                  onTap: onTapDespesas,
                  borderRadius: BorderRadius.circular(18),
                  child: _kpiBox(
                    title: 'Despesas',
                    value: despesas,
                    titleColor: AppColors.financeDespesa,
                    valueColor: AppColors.financeDespesa,
                    subtitle: 'Toque para ver lançamentos',
                    compact: true,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: InkWell(
                  onTap: onTapSaldo,
                  borderRadius: BorderRadius.circular(18),
                  child: _kpiBox(
                    title: 'Saldo',
                    value: saldo,
                    titleColor: saldoColor,
                    valueColor: saldoColor,
                    subtitle: 'Toque para ver lançamentos',
                    compact: true,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          InkWell(
            onTap: onTapSaldoContas,
            borderRadius: BorderRadius.circular(18),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(18),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.deepBlueDark.withValues(alpha: 0.10),
                    blurRadius: 10,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Container(
                    width: 50,
                    height: 50,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(14),
                      gradient: const LinearGradient(
                        colors: [AppColors.primary, AppColors.accent],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                    ),
                    child: const Icon(
                      Icons.account_balance_wallet_rounded,
                      color: Colors.white,
                      size: 27,
                    ),
                  ),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Saldo por contas',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        SizedBox(height: 2),
                        Text(
                          'Corrente, poupança e cartões — toque para ver',
                          style: TextStyle(
                            fontSize: 12.5,
                            color: AppColors.textSecondary,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    Icons.chevron_right_rounded,
                    size: 28,
                    color: AppColors.textMuted,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
          FilledButton.icon(
            onPressed: onExportPdf,
            icon: const Icon(Icons.picture_as_pdf_rounded, size: 22),
            label: const Text(
              'Exportar PDF',
              style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
            ),
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(56),
              backgroundColor: AppColors.logoOrange,
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _kpiBox({
    required String title,
    required String value,
    required Color titleColor,
    required Color valueColor,
    required String subtitle,
    bool compact = false,
  }) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 10 : 14,
        vertical: compact ? 10 : 12,
      ),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(compact ? 18 : 20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: compact ? 13 : 14.5,
              fontWeight: FontWeight.w800,
              color: titleColor,
            ),
          ),
          const SizedBox(height: 4),
          // FittedBox em vez de ellipsis: valores negativos ("R$ - 12.345,67")
          // encolhem para caber em vez de cortar o número.
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              maxLines: 1,
              style: TextStyle(
                fontSize: compact ? 18 : 32,
                fontWeight: FontWeight.w900,
                color: valueColor,
                height: 1,
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: AppColors.textMuted,
            ),
          ),
        ],
      ),
    );
  }
}

class ControleTotalSupplierFinanceCard extends StatelessWidget {
  const ControleTotalSupplierFinanceCard({
    super.key,
    required this.title,
    required this.subtitle,
    this.saldoBancos,
    required this.despesas,
    required this.receitas,
    required this.saldo,
    required this.saldoNegativo,
    required this.onOpenLancamentos,
    required this.onOpenPendentes,
    required this.onOpenComprovantes,
  });

  final String title;
  final String subtitle;
  /// Saldo global dos bancos da igreja.
  ///
  /// `null` no cartão de um fornecedor: o saldo da igreja não diz nada sobre
  /// aquele fornecedor, e o utilizador estava a lê-lo como se fosse dívida
  /// àquele fornecedor. Aqui a conta é só dele.
  final String? saldoBancos;
  final String despesas;
  final String receitas;
  final String saldo;
  final bool saldoNegativo;
  final VoidCallback onOpenLancamentos;
  final VoidCallback onOpenPendentes;
  final VoidCallback onOpenComprovantes;

  @override
  Widget build(BuildContext context) {
    final saldoColor = saldoNegativo ? const Color(0xFF991B1B) : const Color(0xFF166534);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF14532D), Color(0xFF166534)],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w900,
              fontSize: 18,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            subtitle,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.86),
              fontSize: 12.5,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 12),
          if (saldoBancos != null) ...[
            _lineCard('Saldo bancos', saldoBancos!, const Color(0xFF1D4ED8)),
            const SizedBox(height: 8),
          ],
          Row(
            children: [
              Expanded(child: _miniCard('Despesas', despesas, const Color(0xFF991B1B))),
              const SizedBox(width: 8),
              Expanded(child: _miniCard('Receitas', receitas, const Color(0xFF166534))),
              const SizedBox(width: 8),
              Expanded(child: _miniCard('Saldo', saldo, saldoColor)),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: onOpenLancamentos,
                icon: const Icon(Icons.grid_view_rounded, size: 18),
                label: const Text('Lançamentos'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white,
                  side: BorderSide(color: Colors.white.withValues(alpha: 0.6)),
                ),
              ),
              OutlinedButton.icon(
                onPressed: onOpenPendentes,
                icon: const Icon(Icons.schedule_rounded, size: 18),
                label: const Text('Pendentes'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white,
                  side: BorderSide(color: Colors.white.withValues(alpha: 0.6)),
                ),
              ),
              OutlinedButton.icon(
                onPressed: onOpenComprovantes,
                icon: const Icon(Icons.receipt_long_rounded, size: 18),
                label: const Text('Comprovantes'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white,
                  side: BorderSide(color: Colors.white.withValues(alpha: 0.6)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _lineCard(String label, String value, Color valueColor) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 13,
                color: Color(0xFF334155),
              ),
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontWeight: FontWeight.w900,
              fontSize: 16,
              color: valueColor,
            ),
          ),
        ],
      ),
    );
  }

  Widget _miniCard(String label, String value, Color valueColor) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 12.5,
              color: Color(0xFF334155),
            ),
          ),
          const SizedBox(height: 5),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontWeight: FontWeight.w900,
              fontSize: 15,
              color: valueColor,
            ),
          ),
        ],
      ),
    );
  }
}
