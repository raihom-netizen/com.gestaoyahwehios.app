import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:gestao_yahweh/ui/theme_clean_premium.dart';
import 'package:gestao_yahweh/ui/widgets/finance_premium_widgets.dart';

/// Paleta canónica — receitas (azul/verde) vs despesas (vermelho).
abstract final class FinanceReportColors {
  FinanceReportColors._();

  static const receitas = Color(0xFF2563EB);
  static const receitasLight = Color(0xFF10B981);
  static const despesas = Color(0xFFDC2626);
  static const saldoPos = Color(0xFF059669);
  static const saldoNeg = Color(0xFFB91C1C);
  static const heroStart = Color(0xFF0F766E);
  static const heroEnd = Color(0xFF134E4A);
  static const accent = Color(0xFF059669);
}

/// Hero principal — balanço receitas × despesas (estilo resumo financeiro).
class FinanceReportBalanceHero extends StatelessWidget {
  const FinanceReportBalanceHero({
    super.key,
    required this.receitas,
    required this.despesas,
    required this.saldo,
    this.periodLabel,
  });

  final double receitas;
  final double despesas;
  final double saldo;
  final String? periodLabel;

  static final _nf = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');

  @override
  Widget build(BuildContext context) {
    final saldoPos = saldo >= 0;
    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            FinanceReportColors.heroStart,
            FinanceReportColors.heroEnd,
            Color(0xFF0F172A),
          ],
        ),
        borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusLg),
        boxShadow: [
          BoxShadow(
            color: FinanceReportColors.heroStart.withValues(alpha: 0.38),
            blurRadius: 28,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(
                    Icons.account_balance_wallet_rounded,
                    color: Colors.white,
                    size: 26,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Balanço do período',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.92),
                          fontWeight: FontWeight.w900,
                          fontSize: 16,
                          letterSpacing: -0.3,
                        ),
                      ),
                      if (periodLabel != null && periodLabel!.isNotEmpty) ...[
                        const SizedBox(height: 3),
                        Text(
                          periodLabel!,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.72),
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      'Saldo líquido',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.75),
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      _nf.format(saldo),
                      style: TextStyle(
                        color: saldoPos
                            ? const Color(0xFF86EFAC)
                            : const Color(0xFFFCA5A5),
                        fontWeight: FontWeight.w900,
                        fontSize: 20,
                        letterSpacing: -0.5,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 16),
            FinancePremiumFluxoMiniBar(
              receitas: receitas,
              despesas: despesas,
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: _BalancePill(
                    label: 'Receitas',
                    value: _nf.format(receitas),
                    icon: Icons.trending_up_rounded,
                    color: const Color(0xFFBBF7D0),
                    iconColor: FinanceReportColors.receitasLight,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _BalancePill(
                    label: 'Despesas',
                    value: _nf.format(despesas),
                    icon: Icons.trending_down_rounded,
                    color: const Color(0xFFFECDD3),
                    iconColor: FinanceReportColors.despesas,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _BalancePill extends StatelessWidget {
  const _BalancePill({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
    required this.iconColor,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color color;
  final Color iconColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
      ),
      child: Row(
        children: [
          Icon(icon, color: iconColor, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    color: color.withValues(alpha: 0.95),
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.3,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// KPI secundário — gradiente colorido (previsão, pendências).
class FinanceReportKpiTile extends StatelessWidget {
  const FinanceReportKpiTile({
    super.key,
    required this.title,
    required this.value,
    required this.accent,
    required this.icon,
  });

  final String title;
  final double value;
  final Color accent;
  final IconData icon;

  static final _nf = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');

  @override
  Widget build(BuildContext context) {
    return FinancePremiumKpiHero(
      label: title,
      value: _nf.format(value),
      icon: icon,
      accent: accent,
    );
  }
}

/// Cabeçalho de secção com ícone gradiente.
class FinanceReportSectionHeader extends StatelessWidget {
  const FinanceReportSectionHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.icon = Icons.insights_rounded,
    this.accent,
  });

  final String title;
  final String? subtitle;
  final IconData icon;
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    final ac = accent ?? FinanceReportColors.accent;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(9),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [ac, Color.lerp(ac, const Color(0xFF0F172A), 0.35)!],
            ),
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: ac.withValues(alpha: 0.35),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Icon(icon, color: Colors.white, size: 20),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.25,
                  color: ThemeCleanPremium.onSurface,
                ),
              ),
              if (subtitle != null && subtitle!.isNotEmpty) ...[
                const SizedBox(height: 3),
                Text(
                  subtitle!,
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.3,
                    color: Colors.grey.shade600,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// Card de lançamento — substitui linhas cruas da tabela.
class FinanceReportLancamentoCard extends StatelessWidget {
  const FinanceReportLancamentoCard({
    super.key,
    required this.data,
    this.onComprovante,
  });

  final Map<String, dynamic> data;
  final VoidCallback? onComprovante;

  static final _df = DateFormat('dd/MM/yyyy');

  @override
  Widget build(BuildContext context) {
    final tipo = (data['tipo'] ?? '').toString();
    final tl = tipo.toLowerCase();
    final isEntrada =
        tl.contains('entrada') || tl.contains('receita');
    final isSaida = tl.contains('saida') || tl.contains('despesa');
    final valor = ((data['valor'] ?? 0) as num).toDouble();
    final accent = isEntrada
        ? FinanceReportColors.receitasLight
        : isSaida
            ? FinanceReportColors.despesas
            : ThemeCleanPremium.primary;
    final ms = (data['createdAtMs'] ?? 0) as int;
    final dt = DateTime.fromMillisecondsSinceEpoch(ms);
    final comp = (data['comprovanteUrl'] ?? '').toString().trim();

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: accent.withValues(alpha: 0.14)),
        boxShadow: ThemeCleanPremium.softUiCardShadow,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                width: 5,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      accent,
                      Color.lerp(accent, const Color(0xFF0F172A), 0.4)!,
                    ],
                  ),
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 3,
                                  ),
                                  decoration: BoxDecoration(
                                    color: accent.withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    tipo.isEmpty ? '—' : tipo,
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w800,
                                      color: accent,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  _df.format(dt),
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.grey.shade600,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Text(
                              (data['descricao'] ?? '—').toString(),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 14,
                                letterSpacing: -0.2,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              (data['categoria'] ?? '—').toString(),
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey.shade600,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 10),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            NumberFormat.currency(
                              locale: 'pt_BR',
                              symbol: 'R\$',
                            ).format(valor),
                            style: TextStyle(
                              fontWeight: FontWeight.w900,
                              fontSize: 15,
                              color: accent,
                              letterSpacing: -0.35,
                            ),
                          ),
                          if (comp.isNotEmpty && onComprovante != null) ...[
                            const SizedBox(height: 6),
                            Material(
                              color: Colors.transparent,
                              child: InkWell(
                                onTap: onComprovante,
                                borderRadius: BorderRadius.circular(10),
                                child: Ink(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: FinanceReportColors.accent
                                        .withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        Icons.receipt_long_rounded,
                                        size: 16,
                                        color: FinanceReportColors.accent,
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        'Comp.',
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w800,
                                          color: FinanceReportColors.accent,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
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
}

/// Barra de exportação PDF / CSV premium.
class FinanceReportExportBar extends StatelessWidget {
  const FinanceReportExportBar({
    super.key,
    required this.loading,
    required this.onPdf,
    required this.onFechamento,
    required this.onCsv,
  });

  final bool loading;
  final VoidCallback onPdf;
  final VoidCallback onFechamento;
  final VoidCallback onCsv;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Colors.white,
            FinanceReportColors.accent.withValues(alpha: 0.06),
          ],
        ),
        borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusLg),
        border: Border.all(color: const Color(0xFFE2E8F4)),
        boxShadow: ThemeCleanPremium.softUiCardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const FinanceReportSectionHeader(
            title: 'Exportar relatório',
            subtitle: 'PDF completo, fechamento oficial ou planilha CSV.',
            icon: Icons.file_download_rounded,
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _ExportBtn(
                label: loading ? 'Gerando…' : 'PDF completo',
                icon: Icons.picture_as_pdf_rounded,
                filled: true,
                onTap: loading ? null : onPdf,
                loading: loading,
              ),
              _ExportBtn(
                label: 'Fechamento oficial',
                icon: Icons.lock_outline_rounded,
                onTap: loading ? null : onFechamento,
              ),
              _ExportBtn(
                label: 'Excel (CSV)',
                icon: Icons.table_chart_rounded,
                onTap: loading ? null : onCsv,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ExportBtn extends StatelessWidget {
  const _ExportBtn({
    required this.label,
    required this.icon,
    required this.onTap,
    this.filled = false,
    this.loading = false,
  });

  final String label;
  final IconData icon;
  final VoidCallback? onTap;
  final bool filled;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    if (filled) {
      return FilledButton.icon(
        onPressed: onTap,
        icon: loading
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            : Icon(icon),
        label: Text(label),
        style: FilledButton.styleFrom(
          backgroundColor: FinanceReportColors.accent,
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 18),
        ),
      );
    }
    return OutlinedButton.icon(
      onPressed: onTap,
      icon: Icon(icon),
      label: Text(label),
      style: OutlinedButton.styleFrom(
        foregroundColor: FinanceReportColors.accent,
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 18),
        side: BorderSide(
          color: FinanceReportColors.accent.withValues(alpha: 0.45),
        ),
      ),
    );
  }
}

/// Card resumo por conta no relatório.
class FinanceReportContaResumoCard extends StatelessWidget {
  const FinanceReportContaResumoCard({
    super.key,
    required this.nome,
    required this.entradas,
    required this.saidas,
    required this.liquido,
  });

  final String nome;
  final double entradas;
  final double saidas;
  final double liquido;

  static final _nf = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');

  @override
  Widget build(BuildContext context) {
    return FinancePremiumAccountCard(
      nome: nome,
      saldoAtual: liquido,
      receitasMes: entradas,
      despesasMes: saidas,
      bancoSubtitle: 'Movimentação no período',
      accent: FinanceReportColors.accent,
    );
  }
}
