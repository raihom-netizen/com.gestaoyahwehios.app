# Alinhamento Gestão Yahweh ↔ Controle Total (referência)

Este ficheiro é o **plano único** para portar melhorias do projeto de referência  
`C:\Controletotalapp_Independente\flutter_app` para  
`C:\gestao_yahweh_premium_final\flutter_app`.

Abra este repositório no Cursor e peça: *“seguir IMPLEMENTACAO_ALINHAMENTO_CONTROLE_TOTAL.md fase X”*.

---

## Diferença de modelo de dados (importante)

| Controle Total | Gestão Yahweh Premium |
|----------------|------------------------|
| `users/{uid}/transactions` | `igrejas/{tenantId}/finance` |
| `users/{uid}/finance_accounts` | `igrejas/{tenantId}/contas` |
| `users/{uid}/locations`, `scales` | Não existe igual — **lançamentos automáticos de escalas** são opcionais ou adaptar a “dízimos/recorrentes” já existentes |

Toda a lógica nova deve usar **`tenantId`** e as coleções acima, **não** copiar paths `users/…` sem adaptar.

---

## Já implementado neste repositório (baseline)

| Item | Onde |
|------|------|
| Agrupamento de categorias (totais / gráficos ignoram só diferença de maiúsculas) | `flutter_app/lib/utils/finance_category_grouping.dart` |
| Campo **`contaPrincipal`** na conta + exclusividade (só uma conta principal por igreja) + UI no editor | `flutter_app/lib/ui/pages/finance_page.dart` (editor de contas) |
| Chip “Principal” na lista de contas | `finance_page.dart` (`_FinanceContasTab`) |

---

## Fase 1 — Lançamento inteligente (texto + PDF + pré-visualização)

**Referência Controle Total**

- `lib/screens/smart_input_screen.dart`
- `lib/screens/smart_input_batch_preview_screen.dart`
- `lib/services/smart_input_pdf_text_service.dart` (extração PDF / texto)
- `lib/models/smart_input_pop_result.dart`
- `lib/services/finance_service.dart` → `saveSmartPasteTransaction` (campo opcional `smartPasteBatchId`)

**Destino sugerido Gestão Yahweh**

- `lib/ui/pages/finance_smart_input_page.dart` (novo)
- `lib/services/finance_smart_import_service.dart` (novo; PDF via `file_picker` / `pdf` / texto nativo conforme já usam em relatórios)
- Entrada na UI: botão na aba **Lançamentos** ou FAB “Importar / colar extrato” em `finance_page.dart`

**Firestore**

- Garantir que `igrejas/{tenant}/finance` aceita os mesmos campos extra opcionais (`source`, `parsedSnippet`, `smartPasteBatchId`, etc.) nas **regras** — espelhar a nota em `finance_service` do Controle Total sobre whitelist.

**Telemetria**

- Controle Total evita telemetria opcional por defeito; manter igual (sem analytics obrigatório).

---

## Fase 2 — Lançamentos em massa (por data, categoria, “sem conta”)

**Referência**

- `lib/screens/finance_bulk_assign_screen.dart`
- Padrão de intervalo + lista com checkboxes + conta destino + `batch`/`update` em documentos

**Destino**

- `lib/ui/pages/finance_bulk_assign_page.dart` (novo)
- Mapear `financeContaDestinoReceitaId` / campos equivalentes já usados em `finance_page.dart` (`_totaisReceitaDespesaPorContaNoMes`, `financeContaDestino…`)

**Regras**

- Respeitar `AppPermissions` / papel (`role`) como no resto do painel financeiro.

---

## Fase 3 — SnackBar e persistência alinhados ao Controle Total

**Referência**

- `lib/services/transaction_save_service.dart` → parâmetro `showSuccessSnack`, mensagens por tipo (receita/despesa/parcelas)
- `lib/utils/finance_transaction_datetime.dart` (dia calendário + relógio “agora”)

**Destino**

- Extrair um `FinanceTransactionSaveService` (ou estender o fluxo atual de gravação em `finance_page.dart`) com a mesma API mental: **um SnackBar** após gravações em lote.

---

## Fase 4 — Cartão por conta (visual Controle Total no extrato)

**Referência**

- `lib/widgets/finance_account_category_sheet.dart`
- `lib/widgets/finance_bank_brand_thumb.dart`
- `lib/constants/finance_bank_presets.dart`
- Resumo período: `lib/utils/finance_period_summary.dart` (se aplicável)

**Destino atual**

- `_FinanceContasResumoStrip` e `_MovimentacoesContaPage` em `finance_page.dart` já têm resumo e extrato.

**Melhorias pedidas (checklist)**

- [ ] Cabeçalho tipo **cartão** com cor/gradiente por `bancoBrandSlug` ou `bancoCodigo` (reutilizar `brasilBancoBrandingFor` / `_financeContaBancoColor`)
- [ ] Bloco fixo: **saldo inicial do mês** → **receitas** → **despesas** → **saldo final** (filtro de mês já existe em `extratoMes`; estender para seletor de mês no topo da página)
- [ ] Filtros: todas / só despesas / só receitas / transferências; **todas as contas** vs conta atual; tipo (caixa, cartão, corrente)
- [ ] Lista filtrada coerente com os chips (mesmo padrão de `FinanceInsightSheet` no Controle Total, simplificado)

---

## Fase 5 — Lançamentos automáticos (fora de escalas)

No Controle Total: fecho de mês + receitas a partir de plantões (`scale_month_closure_sheet`, `scale_closure_summary.dart`).

**Opções na igreja**

- A) Automatizar só **receitas recorrentes** / dízimos (já há `finance_receitas_recorrentes_tabs.dart`) — reforçar UX “gerar mês”
- B) Importar módulo escalas (provável **fora de escopo**); preferir documentar integração futura

---

## Fase 6 — Categorias (totais e donuts)

**Referência**

- `lib/utils/finance_category_grouping.dart` + uso em `finance_screen.dart` e `dashboard_screen.dart`

**Destino**

- Importar `FinanceCategoryMerger` nos sítios que agregam `categoria` / `categoriaDespesa` / campos equivalentes nos relatórios e donuts de `finance_page.dart` (grep `categoria` nos totais).

---

## Ordem recomendada de trabalho

1. Fase 6 (agrupamentos) — baixo risco, melhora relatórios imediatamente  
2. Fase 3 (SnackBar / lote) — melhora UX em importações  
3. Fase 2 (massa) — alto valor operacional  
4. Fase 1 (PDF/texto) — maior esforço; dependências e permissões  
5. Fase 4 (UI extrato) — polish premium  
6. Fase 5 — decisão de produto  

---

## Comando útil (grep no projeto de referência)

```text
Controle Total (origem):
C:\Controletotalapp_Independente\flutter_app\lib
```

Palavras-chave: `smart_input`, `FinanceBulkAssign`, `saveSmartPasteTransaction`, `FinanceCategoryMerger`, `scale_month_closure`.

---

*Última atualização: documento gerado para acompanhamento no Cursor; atualize as checklists à medida que cada fase for concluída.*
