import 'package:flutter/material.dart';

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

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF166534), Color(0xFF15803D), Color(0xFF0F766E)],
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF14532D).withValues(alpha: 0.26),
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
              Text(
                monthLabel,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 16,
                ),
              ),
              const Spacer(),
              Icon(
                Icons.visibility_off_rounded,
                color: Colors.white.withValues(alpha: 0.9),
                size: 24,
              ),
            ],
          ),
          const SizedBox(height: 12),
          InkWell(
            onTap: onTapSaldoAbertura,
            borderRadius: BorderRadius.circular(20),
            child: _kpiBox(
              title: 'Saldo de abertura',
              value: saldoAbertura,
              titleColor: const Color(0xFF991B1B),
              valueColor: const Color(0xFF991B1B),
              subtitle: 'Toque para gráficos',
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: InkWell(
                  onTap: onTapReceitas,
                  borderRadius: BorderRadius.circular(18),
                  child: _kpiBox(
                    title: 'Receitas',
                    value: receitas,
                    titleColor: const Color(0xFF166534),
                    valueColor: const Color(0xFF166534),
                    subtitle: 'Toque para gráficos',
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
                    titleColor: const Color(0xFF991B1B),
                    valueColor: const Color(0xFF991B1B),
                    subtitle: 'Toque para gráficos',
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
                    titleColor: const Color(0xFF166534),
                    valueColor: const Color(0xFF166534),
                    subtitle: 'Toque para gráficos',
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
              ),
              child: Row(
                children: [
                  Container(
                    width: 50,
                    height: 50,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(14),
                      gradient: const LinearGradient(
                        colors: [Color(0xFF3B82F6), Color(0xFF14B8A6)],
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
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF14532D),
                          ),
                        ),
                        SizedBox(height: 2),
                        Text(
                          'Corrente, poupança e cartões — toque para ver',
                          style: TextStyle(
                            fontSize: 13,
                            color: Color(0xFF374151),
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Icon(
                    Icons.chevron_right_rounded,
                    size: 30,
                    color: Color(0xFF334155),
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
              style: TextStyle(fontWeight: FontWeight.w900, fontSize: 17),
            ),
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(58),
              backgroundColor: const Color(0xFFF97316),
              foregroundColor: Colors.white,
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
              fontSize: compact ? 14 : 15,
              fontWeight: FontWeight.w800,
              color: titleColor,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: compact ? 17 : 38,
              fontWeight: FontWeight.w900,
              color: valueColor,
              height: 1,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: Color(0xFF6B7280),
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
    required this.saldoBancos,
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
  final String saldoBancos;
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
          _lineCard('Saldo bancos', saldoBancos, const Color(0xFF1D4ED8)),
          const SizedBox(height: 8),
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
