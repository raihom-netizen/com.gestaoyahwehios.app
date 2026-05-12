/// Limites de leitura Firestore no **painel da igreja** (1.ª pintura, streams, BI).
///
/// Valores altos demais atrasam mobile/web (deserialização + UI). Valores baixos
/// demais podem omitir lançamentos antigos quando o filtro de **data efetiva**
/// ([financeLancamentoDate]) cai fora dos N documentos mais recentes por `createdAt`.
///
/// Manter o número alinhado a `FINANCE_LEDGER_CAP` em `functions/src/panelFinanceSummary.ts`.
abstract final class ChurchDashboardQueryLimits {
  ChurchDashboardQueryLimits._();

  /// Máximo de docs em `igrejas/{id}/finance` carregados no stream do dashboard
  /// e no fallback `_load` do cartão «Saúde ministerial» (ordenado por `createdAt` desc).
  ///
  /// Reduzido para **2500** (painel + cartão BI + Cloud Function de resumo alinhados).
  static const int financeLedgerSnapshotMax = 2500;
}
