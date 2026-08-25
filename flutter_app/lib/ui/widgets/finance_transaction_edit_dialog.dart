import 'package:gestao_yahweh/core/data/yahweh_write_batch.dart';
import 'package:gestao_yahweh/ui/widgets/finance_vinculo_picker.dart';
import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart' hide showDatePicker;
import 'package:gestao_yahweh/core/finance_theme_context.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import 'package:gestao_yahweh/constants/currency_formats.dart';
import 'package:gestao_yahweh/constants/finance_category_visuals.dart';
import 'package:gestao_yahweh/models/finance_account.dart';
import 'package:gestao_yahweh/models/user_profile.dart';
import 'package:gestao_yahweh/services/finance_comprovante_attach_service.dart';
import 'package:gestao_yahweh/services/finance_accounts_service.dart';
import 'package:gestao_yahweh/services/goal_deposit_service.dart';
import 'package:gestao_yahweh/services/finance_receipt_upload_service.dart';
import 'package:gestao_yahweh/services/logs_service.dart';
import 'package:gestao_yahweh/services/transaction_save_service.dart';
import 'package:gestao_yahweh/services/user_categories_service.dart';
import 'package:gestao_yahweh/core/finance_app_colors.dart';
import 'package:gestao_yahweh/ui/widgets/modern_module_ui.dart';
import 'package:gestao_yahweh/utils/finance_line_opening.dart';
import 'package:gestao_yahweh/utils/finance_goal_tx_delete.dart';
import 'package:gestao_yahweh/utils/finance_transaction_datetime.dart';
import 'package:gestao_yahweh/utils/date_picker_a11y.dart';
import 'package:gestao_yahweh/utils/fifty_two_weeks_plan.dart';
import 'package:gestao_yahweh/utils/premium_upgrade.dart';
import 'brl_amount_text_field.dart';
import 'fast_text_field.dart';
import 'finance_calendar_color_picker.dart';
import 'finance_category_picker.dart';
import 'finance_pending_receipt_preview.dart';
import 'finance_premium_ui.dart';
import 'finance_transfer_bottom_sheet.dart';
import 'goal_deposit_ui.dart';
import 'package:gestao_yahweh/core/data/yahweh_doc_write.dart';

typedef FinanceTxEditOnSaved = void Function(
  String docId,
  Map<String, dynamic> patch,
  DateTime effectiveDate,
);

typedef FinanceTxEditOnDeleted = void Function(
  String docId,
  DateTime? effectiveDate,
);

/// Modal premium de edição — verde (receita) / vermelho (despesa), igual ao Financeiro.
Future<bool> showFinanceTransactionEditDialog({
  required BuildContext context,
  required String uid,
  required UserProfile profile,
  required String docId,
  required Map<String, dynamic> current,
  required String type,
  List<FinanceAccount>? financeAccountsPreloaded,
  String logModulo = 'Financeiro',
  FinanceTxEditOnSaved? onSaved,
  FinanceTxEditOnDeleted? onDeleted,
}) async {
  if (!profile.hasActiveLicense) {
    mostrarAvisoSeLicencaInativa(context, profile);
    return false;
  }
  final fsUid = uid.trim();
  final pairId = (current['transferPairId'] ?? '').toString().trim();
  if (pairId.isNotEmpty) {
    final accounts = financeAccountsPreloaded ??
        await FinanceAccountsService().listOnce(fsUid);
    if (!context.mounted) return false;
    return FinanceTransferBottomSheet.showEdit(
      context,
      uid: uid,
      profile: profile,
      pairId: pairId,
      accounts: accounts,
      logModulo: logModulo,
    );
  }

  final loaded = await UserCategoriesService().load(fsUid);
  var categoryList = UserCategoriesService.sortedWithoutIncluirNova(
    type == 'income' ? loaded.income : loaded.expense,
  );
  final incluirNovaCat = UserCategoriesService.kIncluirNova;
  if (!context.mounted) return false;

  final amountCtrl = TextEditingController(
    text: CurrencyFormats.formatBRLInput((current['amount'] ?? 0).toDouble()),
  );
  final descCtrl =
      TextEditingController(text: (current['description'] ?? '').toString());
  final currentCat = (current['category'] ?? '').toString().trim();

  String pickFirstSelectable() {
    final real = categoryList.where((c) => c != incluirNovaCat).toList();
    return real.isNotEmpty ? real.first : '__outra__';
  }

  late String selectedCategory;
  if (currentCat.isNotEmpty) {
    final match = categoryList
        .where((c) => c.toLowerCase() == currentCat.toLowerCase())
        .toList();
    selectedCategory = match.isNotEmpty ? match.first : '__outra__';
  } else {
    selectedCategory = pickFirstSelectable();
  }

  final catCtrl = TextEditingController(
    text: currentCat.isNotEmpty
        ? currentCat
        : (selectedCategory == '__outra__' ? '' : selectedCategory),
  );
  String status = (current['status'] ?? 'paid').toString();
  // Desligado por defeito. So fica ligado se foi gravado explicitamente
  // `true` — com `!= false`, o campo ausente (todo lançamento antigo) ligava.
  var addToCalendar = status == 'pending' &&
      current['hideFromCalendar'] != true &&
      current['addToCalendar'] == true;
  String? calendarColorHex = current['calendarColorHex']?.toString();
  // Vinculo (membro ou fornecedor). Estava gravado no lancamento mas nao
  // aparecia ao editar: quem abria «Editar despesa» nao tinha como saber de
  // quem era aquele gasto, nem como corrigir se estivesse errado.
  var vinculo = FinanceVinculoSelecao.deFirestore(current);
  DateTime date = (current['date'] is Timestamp)
      ? (current['date'] as Timestamp).toDate()
      : DateTime.now();
  final fromOpenFinance =
      FinanceTransactionDatetime.isOpenFinanceBacked(current);

  final receipt = Map<String, dynamic>.from(current['receipt'] ?? {});
  // Legado (`receipt.*`) OU canônico (`comprovanteUrl`/`comprovanteLink`)
  // — o diálogo de edição não pode depender só do formato legado.
  final receiptLink = (receipt['webViewLink'] ??
          receipt['webContentLink'] ??
          receipt['downloadUrl'] ??
          current['comprovanteUrl'] ??
          current['comprovanteLink'] ??
          '')
      .toString();
  var removeReceipt = false;
  Uint8List? newReceiptBytes;
  var newReceiptName = '';
  String? newReceiptMime;

  final financeAccounts = financeAccountsPreloaded ??
      await FinanceAccountsService().listOnce(fsUid);
  final rawAid = (current['financeAccountId'] ?? '').toString().trim();
  var selectedFinanceAccountId = rawAid.isEmpty ? null : rawAid;
  if (type == 'expense' &&
      financeAccounts.isNotEmpty &&
      (selectedFinanceAccountId == null ||
          selectedFinanceAccountId.trim().isEmpty)) {
    selectedFinanceAccountId = financeAccounts.first.id;
  }
  if (!context.mounted) return false;

  final goalIdFromTx = (current['goalId'] ?? '').toString().trim();
  final metaEdit = type == 'income' && goalIdFromTx.isNotEmpty
      ? await _loadGoalFinanceEditContext(
          fsUid: fsUid,
          goalId: goalIdFromTx,
          txId: docId,
        )
      : null;
  if (!context.mounted) return false;

  var metaPreviewWeeks = metaEdit?.initialWeeks ?? const <int>[];
  if (metaEdit != null && metaEdit.is52) {
    final initialAmount = CurrencyFormats.parseBRLInput(amountCtrl.text) ?? 0;
    metaPreviewWeeks = computeGoalDepositPreviewWeeks(
      goalData: metaEdit.goalData,
      schedule: metaEdit.schedule,
      oldWeeks: metaEdit.initialWeeks,
      amount: initialAmount,
    );
  }

  void recalcMetaWeeks(void Function(void Function()) setState) {
    if (metaEdit == null || !metaEdit.is52) return;
    final amount = CurrencyFormats.parseBRLInput(amountCtrl.text) ?? 0;
    metaPreviewWeeks = computeGoalDepositPreviewWeeks(
      goalData: metaEdit.goalData,
      schedule: metaEdit.schedule,
      oldWeeks: metaEdit.initialWeeks,
      amount: amount,
    );
    setState(() {});
  }

  final ok = await showDialog<bool>(
    context: context,
    barrierColor: AppColors.deepBlueDark.withValues(alpha: 0.55),
    builder: (ctx) => StatefulBuilder(
      builder: (context, setState) {
        final hasExistingReceipt =
            receiptLink.isNotEmpty && !removeReceipt && newReceiptBytes == null;
        final hasNewReceipt = newReceiptBytes != null;
        final showComprovante = true; // comprovante não é premium
        final orphan = selectedFinanceAccountId != null &&
            selectedFinanceAccountId!.isNotEmpty &&
            !financeAccounts.any((a) => a.id == selectedFinanceAccountId);
        final editAccent = type == 'income'
            ? AppColors.financeReceita
            : AppColors.financeDespesa;

        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 20),
          child: ConstrainedBox(
            constraints:
                BoxConstraints(maxHeight: MediaQuery.sizeOf(ctx).height * 0.9),
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(24),
                gradient: LinearGradient(colors: [
                  ctx.appChipIdleBg,
                  ModernModuleUI.cardBg(ctx),
                ]),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.deepBlueDark.withValues(alpha: 0.22),
                    blurRadius: 28,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.fromLTRB(18, 16, 12, 14),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          editAccent,
                          Color.lerp(editAccent, AppColors.accent, 0.4)!
                        ],
                      ),
                      borderRadius:
                          const BorderRadius.vertical(top: Radius.circular(24)),
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.22),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Icon(
                            type == 'income'
                                ? Icons.arrow_downward_rounded
                                : Icons.arrow_upward_rounded,
                            color: Colors.white,
                            size: 22,
                          ),
                        ),
                        SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            type == 'income'
                                ? 'Editar Receita'
                                : 'Editar Despesa',
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 18,
                                fontWeight: FontWeight.w900),
                          ),
                        ),
                        IconButton(
                          onPressed: () => Navigator.pop(ctx, false),
                          icon: Icon(Icons.close_rounded, color: Colors.white),
                        ),
                      ],
                    ),
                  ),
                  Flexible(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 10),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(18),
                              gradient: LinearGradient(
                                colors: [
                                  editAccent.withValues(alpha: 0.12),
                                  Colors.white
                                ],
                              ),
                              border: Border.all(
                                  color: editAccent.withValues(alpha: 0.28)),
                            ),
                            child: BrlAmountTextField(
                              controller: amountCtrl,
                              onChanged: metaEdit?.is52 == true
                                  ? (_) => recalcMetaWeeks(setState)
                                  : null,
                              decoration: InputDecoration(
                                labelText: 'Valor',
                                isDense: true,
                                border: InputBorder.none,
                                labelStyle: TextStyle(
                                    fontWeight: FontWeight.w800,
                                    color: editAccent),
                              ),
                            ),
                          ),
                          SizedBox(height: 12),
                          Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                              'Categoria',
                              style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 13,
                                  color: context.appTextPrimary),
                            ),
                          ),
                          SizedBox(height: 6),
                          Material(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(14),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(14),
                              onTap: () async {
                                final picked = await showFinanceCategoryPicker(
                                  context: context,
                                  uid: fsUid,
                                  isIncome: type == 'income',
                                  initialQuery: selectedCategory == '__outra__'
                                      ? catCtrl.text.trim()
                                      : selectedCategory,
                                );
                                if (picked == null || !ctx.mounted) return;
                                if (picked == '__outra__') {
                                  setState(
                                      () => selectedCategory = '__outra__');
                                  return;
                                }
                                final reloaded =
                                    await UserCategoriesService().load(fsUid);
                                if (!ctx.mounted) return;
                                setState(() {
                                  categoryList = UserCategoriesService
                                      .sortedWithoutIncluirNova(
                                    type == 'income'
                                        ? reloaded.income
                                        : reloaded.expense,
                                  );
                                  selectedCategory = picked;
                                  catCtrl.text = picked;
                                });
                              },
                              child: Ink(
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(
                                      color: AppColors.primary
                                          .withValues(alpha: 0.22)),
                                  color: ctx.appChipIdleBg,
                                ),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 12, vertical: 12),
                                  child: Row(
                                    children: [
                                      Builder(
                                        builder: (_) {
                                          final vis = selectedCategory !=
                                                  '__outra__'
                                              ? financeCategoryVisualFor(
                                                  selectedCategory,
                                                  isIncome: type == 'income')
                                              : financeCategoryVisualFor(
                                                  catCtrl.text.trim().isEmpty
                                                      ? 'Outros'
                                                      : catCtrl.text.trim(),
                                                  isIncome: type == 'income',
                                                );
                                          return Container(
                                            width: 38,
                                            height: 38,
                                            decoration: BoxDecoration(
                                              color: vis.color
                                                  .withValues(alpha: 0.14),
                                              borderRadius:
                                                  BorderRadius.circular(10),
                                            ),
                                            child: Icon(vis.icon,
                                                color: vis.color, size: 22),
                                          );
                                        },
                                      ),
                                      SizedBox(width: 10),
                                      Expanded(
                                        child: Text(
                                          selectedCategory == '__outra__'
                                              ? (catCtrl.text.trim().isEmpty
                                                  ? 'Outra — toque para lista ou digite abaixo'
                                                  : catCtrl.text.trim())
                                              : selectedCategory,
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            fontWeight: FontWeight.w800,
                                            fontSize: 14,
                                            color: context.appTextPrimary,
                                          ),
                                        ),
                                      ),
                                      Icon(Icons.unfold_more_rounded,
                                          color: context.appTextSecondary,
                                          size: 22),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                          if (selectedCategory == '__outra__') ...[
                            SizedBox(height: 8),
                            FastTextField(
                              controller: catCtrl,
                              decoration: const InputDecoration(
                                labelText: 'Nome da categoria',
                                border: OutlineInputBorder(),
                                isDense: true,
                              ),
                              textCapitalization: TextCapitalization.words,
                            ),
                          ],
                          SizedBox(height: 12),
                          FastTextField(
                              controller: descCtrl,
                              decoration: const InputDecoration(
                                  labelText: 'Descrição')),
                          SizedBox(height: 10),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      fromOpenFinance
                                          ? 'Data e horário (Open Finance)'
                                          : 'Data e horário do lançamento',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w700,
                                        fontSize: 13,
                                        color: context.appTextPrimary,
                                      ),
                                    ),
                                    SizedBox(height: 4),
                                    Text(
                                      '${DateFormat('dd/MM/yyyy', 'pt_BR').format(date)} · ${DateFormat('HH:mm', 'pt_BR').format(date)}',
                                      style: const TextStyle(fontSize: 14),
                                    ),
                                  ],
                                ),
                              ),
                              if (!fromOpenFinance)
                                Wrap(
                                  spacing: 6,
                                  runSpacing: 4,
                                  alignment: WrapAlignment.end,
                                  children: [
                                    TextButton(
                                      onPressed: () async {
                                        final picked = await showDatePicker(
                                          context: context,
                                          initialDate: date,
                                          firstDate: DateTime(2020),
                                          lastDate: DateTime(2100),
                                        );
                                        if (picked != null) {
                                          setState(() => date =
                                              FinanceTransactionDatetime
                                                  .mergeCalendarDayWithExistingTime(
                                                      picked, date));
                                        }
                                      },
                                      child: Text('Alterar dia'),
                                    ),
                                    TextButton(
                                      onPressed: () async {
                                        final picked = await showTimePicker(
                                          context: context,
                                          initialTime: TimeOfDay(
                                              hour: date.hour,
                                              minute: date.minute),
                                          helpText: 'Horário do lançamento',
                                          hourLabelText: 'Hora',
                                          minuteLabelText: 'Minuto',
                                          builder: (context, child) {
                                            return MediaQuery(
                                              data: MediaQuery.of(context)
                                                  .copyWith(
                                                      alwaysUse24HourFormat:
                                                          true),
                                              child: child ??
                                                  const SizedBox.shrink(),
                                            );
                                          },
                                        );
                                        if (picked != null) {
                                          setState(() =>
                                              date = FinanceTransactionDatetime
                                                  .mergeCalendarDayWithTimeOfDay(
                                                date,
                                                picked.hour,
                                                picked.minute,
                                              ));
                                        }
                                      },
                                      child: Text('Alterar hora'),
                                    ),
                                  ],
                                ),
                            ],
                          ),
                          SizedBox(height: 10),
                          DropdownButtonFormField<String>(
                            key: ValueKey<String>(status),
                            initialValue: status,
                            decoration: financePremiumDropdownDecoration(
                              context,
                              label: 'Status',
                              prefixIcon: Icons.flag_rounded,
                              accent: editAccent,
                            ),
                            items: const [
                              DropdownMenuItem(
                                  value: 'paid', child: Text('Pago')),
                              DropdownMenuItem(
                                  value: 'pending', child: Text('Pendente')),
                            ],
                            onChanged: (v) => setState(() {
                              status = v ?? 'paid';
                              // Sem religar o calendário: «Pendente» não é
                              // consentimento para pôr o lançamento na agenda.
                            }),
                          ),
                          if (status == 'pending') ...[
                            SizedBox(height: 12),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 8),
                              decoration: BoxDecoration(
                                color: editAccent.withValues(alpha: 0.08),
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(
                                  color: editAccent.withValues(alpha: 0.28),
                                ),
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    addToCalendar
                                        ? Icons.event_available_rounded
                                        : Icons.event_busy_rounded,
                                    size: 20,
                                    color: editAccent,
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'Mostrar no calendário',
                                          style: TextStyle(
                                            fontSize: 13,
                                            fontWeight: FontWeight.w800,
                                            color: context.appTextPrimary,
                                          ),
                                        ),
                                        Text(
                                          'Agenda/Escala',
                                          style: TextStyle(
                                            fontSize: 11.5,
                                            color: context.appTextSecondary,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Switch.adaptive(
                                    value: addToCalendar,
                                    activeThumbColor: editAccent,
                                    activeTrackColor:
                                        editAccent.withValues(alpha: 0.5),
                                    onChanged: (v) =>
                                        setState(() => addToCalendar = v),
                                  ),
                                ],
                              ),
                            ),
                            if (addToCalendar) ...[
                              SizedBox(height: 10),
                              Builder(builder: (ctx) {
                                final hex = (calendarColorHex ??
                                        FinanceCalendarColorPicker
                                            .defaultHexFor(type == 'income'))
                                    .replaceFirst('#', '')
                                    .replaceFirst(
                                        RegExp(r'^0x', caseSensitive: false),
                                        '');
                                final six = hex.length > 6
                                    ? hex.substring(hex.length - 6)
                                    : hex.padLeft(6, '0');
                                final bg =
                                    Color(int.parse('FF$six', radix: 16));
                                return Material(
                                  color: bg,
                                  borderRadius: BorderRadius.circular(14),
                                  child: InkWell(
                                    borderRadius: BorderRadius.circular(14),
                                    onTap: () async {
                                      final picked =
                                          await FinanceCalendarColorPicker.show(
                                        context,
                                        isIncome: type == 'income',
                                        currentHex: calendarColorHex,
                                      );
                                      if (picked != null) {
                                        setState(
                                            () => calendarColorHex = picked);
                                      }
                                    },
                                    child: const SizedBox(
                                      height: 44,
                                      width: double.infinity,
                                      child: Center(
                                        child: Text(
                                          'Cor no calendário',
                                          style: TextStyle(
                                            color: Colors.white,
                                            fontWeight: FontWeight.w900,
                                            fontSize: 13.5,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                );
                              }),
                            ],
                          ],
                          SizedBox(height: 12),
                          Text('Vínculo (membro ou fornecedor)',
                              style: TextStyle(
                                  fontWeight: FontWeight.w700, fontSize: 13)),
                          SizedBox(height: 6),
                          Material(
                            color: Colors.transparent,
                            child: InkWell(
                              borderRadius: BorderRadius.circular(12),
                              onTap: () async {
                                final escolha =
                                    await escolherVinculoFinanceiro(
                                  context,
                                  tenantId: uid,
                                  atual: vinculo,
                                );
                                if (escolha != null) {
                                  setState(() => vinculo = escolha);
                                }
                              },
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 14, vertical: 13),
                                decoration: BoxDecoration(
                                  color: context.appInputFill,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: editAccent.withValues(alpha: 0.35),
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    Icon(
                                      vinculo.vazio
                                          ? Icons.link_off_rounded
                                          : (vinculo.individual &&
                                                  vinculo.itens.first.ehMembro
                                              ? Icons.person_rounded
                                              : Icons.local_shipping_rounded),
                                      size: 18,
                                      color: editAccent,
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Text(
                                        vinculo.resumo,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w700,
                                          color: vinculo.vazio
                                              ? context.appTextSecondary
                                              : context.appTextPrimary,
                                        ),
                                      ),
                                    ),
                                    Icon(Icons.unfold_more_rounded,
                                        color: editAccent, size: 22),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          if (vinculo.somenteHistorico)
                            Padding(
                              padding: const EdgeInsets.only(top: 6),
                              child: Text(
                                'Com mais de uma pessoa, o lançamento fica só no '
                                'histórico geral — não entra no total individual '
                                'de nenhuma delas.',
                                style: TextStyle(
                                  fontSize: 11.5,
                                  height: 1.35,
                                  fontWeight: FontWeight.w600,
                                  color: const Color(0xFFB45309),
                                ),
                              ),
                            ),
                          SizedBox(height: 12),
                          Text('Conta',
                              style: TextStyle(
                                  fontWeight: FontWeight.w700, fontSize: 13)),
                          SizedBox(height: 6),
                          if (financeAccounts.isEmpty)
                            Text(
                              'Cadastre ao menos uma conta em Financeiro → Bancos e cartões.',
                              style: TextStyle(
                                  fontSize: 12,
                                  color: context.appTextSecondary,
                                  height: 1.35),
                            )
                          else
                            DropdownButtonFormField<String?>(
                              key: ValueKey<String?>(selectedFinanceAccountId),
                              initialValue: selectedFinanceAccountId,
                              decoration: financePremiumDropdownDecoration(
                                context,
                                label: 'Conta do lançamento',
                                prefixIcon: Icons.account_balance_rounded,
                                accent: editAccent,
                              ),
                              items: [
                                if (type == 'income')
                                  const DropdownMenuItem<String?>(
                                    value: null,
                                    child:
                                        Text('Sem conta vinculada (opcional)'),
                                  ),
                                ...financeAccounts.map(
                                  (a) => DropdownMenuItem<String?>(
                                    value: a.id,
                                    child: Text(a.displayName,
                                        overflow: TextOverflow.ellipsis),
                                  ),
                                ),
                                if (orphan)
                                  DropdownMenuItem<String?>(
                                      value: rawAid,
                                      child: Text('Manter vínculo antigo')),
                              ],
                              onChanged: (v) => setState(() {
                                selectedFinanceAccountId = v;
                                if (type == 'expense' && v != null) {
                                  FinanceAccount? acc;
                                  for (final a in financeAccounts) {
                                    if (a.id == v) {
                                      acc = a;
                                      break;
                                    }
                                  }
                                  if (acc?.expenseDefaultsToPending == true) {
                                    status = 'pending';
                                  } else if (acc?.isDebitBankProduct == true) {
                                    status = 'paid';
                                  }
                                }
                              }),
                            ),
                          if (metaEdit != null) ...[
                            SizedBox(height: 12),
                            if (metaEdit.is52)
                              GoalDepositWeeksPreviewBanner(
                                oldWeeks: metaEdit.initialWeeks,
                                previewWeeks: metaPreviewWeeks,
                              )
                            else
                              Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: GoalDepositUi.green
                                      .withValues(alpha: 0.08),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: GoalDepositUi.green
                                        .withValues(alpha: 0.22),
                                  ),
                                ),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Icon(Icons.savings_rounded,
                                        size: 18,
                                        color: GoalDepositUi.greenDark),
                                    SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        'Lançamento vinculado à meta «${metaEdit.goalTitle}». '
                                        'Ao salvar, o depósito na meta será atualizado.',
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w700,
                                          color: GoalDepositUi.greenDark,
                                          height: 1.35,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                          ],
                          if (showComprovante) ...[
                            SizedBox(height: 16),
                            const Divider(),
                            Text('Comprovante',
                                style: TextStyle(
                                    fontWeight: FontWeight.w700, fontSize: 14)),
                            SizedBox(height: 8),
                            if (hasExistingReceipt)
                              Row(
                                children: [
                                  Expanded(
                                    child: OutlinedButton.icon(
                                      icon: Icon(Icons.visibility_rounded,
                                          size: 18),
                                      label: Text('Ver anexo'),
                                      onPressed: () async {
                                        await FinanceComprovanteAttachService
                                            .viewFromDoc(context, current);
                                      },
                                    ),
                                  ),
                                  SizedBox(width: 8),
                                  OutlinedButton.icon(
                                    icon: Icon(Icons.delete_outline_rounded,
                                        size: 18),
                                    label: Text('Remover'),
                                    style: OutlinedButton.styleFrom(
                                        foregroundColor: Colors.red),
                                    onPressed: () => setState(() {
                                      removeReceipt = true;
                                      newReceiptBytes = null;
                                    }),
                                  ),
                                ],
                              ),
                            // Anexo recém-escolhido: miniatura + «olho» para
                            // conferir antes de salvar (padrão Controle Total).
                            if (hasNewReceipt) ...[
                              FinancePendingReceiptCard(
                                bytes: newReceiptBytes!,
                                fileName: newReceiptName.isEmpty
                                    ? 'Comprovante'
                                    : newReceiptName,
                                isPdf:
                                    (newReceiptMime ?? '').contains('pdf') ||
                                    newReceiptName
                                        .toLowerCase()
                                        .endsWith('.pdf'),
                                onRemove: () => setState(() {
                                  newReceiptBytes = null;
                                  newReceiptName = '';
                                  newReceiptMime = null;
                                }),
                              ),
                              SizedBox(height: 8),
                            ],
                            OutlinedButton.icon(
                              icon: Icon(
                                hasExistingReceipt || hasNewReceipt
                                    ? Icons.swap_horiz_rounded
                                    : Icons.attach_file_rounded,
                                size: 18,
                              ),
                              label: Text(
                                hasExistingReceipt || hasNewReceipt
                                    ? 'Trocar comprovante'
                                    : 'Anexar comprovante',
                              ),
                              onPressed: () async {
                                final picked =
                                    await FinanceComprovanteAttachService
                                        .showPickSheet(
                                  context,
                                  title: hasExistingReceipt || hasNewReceipt
                                      ? 'Trocar comprovante'
                                      : 'Anexar comprovante',
                                );
                                if (picked == null) return;
                                setState(() {
                                  removeReceipt = false;
                                  newReceiptBytes = picked.bytes;
                                  newReceiptName = picked.fileName;
                                  newReceiptMime = picked.mimeType;
                                });
                              },
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
                    child: Align(
                      alignment: Alignment.center,
                      child: TextButton.icon(
                        icon: Icon(Icons.delete_outline_rounded, size: 20),
                        label: Text('Excluir lançamento'),
                        style: TextButton.styleFrom(
                          foregroundColor: const Color(0xFFEF4444),
                        ),
                        onPressed: () async {
                          final metaInfo =
                              await GoalDepositService.linkedInfoForTransaction(
                            uid: uid,
                            txId: docId,
                            txData: current,
                          );
                          if (!ctx.mounted) return;
                          final ok = await confirmFinanceTransactionDelete(
                            context: ctx,
                            metaInfo: metaInfo,
                          );
                          if (ok != true || !ctx.mounted) return;
                          // Coleção real do lançamento — era `users/{uid}/transactions`
                          // (caminho legado inexistente), então excluir não apagava nada.
                          final txCol = TransactionSaveService.txRef(fsUid);
                          await deleteFinanceTransactionRecord(
                            uid: uid,
                            docId: docId,
                            txData: current,
                            txCol: txCol,
                          );
                          final effectiveDate =
                              FinanceLineOpening.effectiveDateTimeFromMap(
                                      current) ??
                                  (current['date'] as Timestamp?)?.toDate();
                          final typeLog =
                              (current['type'] ?? 'expense').toString();
                          final amountLog = (current['amount'] ?? 0).toDouble();
                          final categoryLog =
                              (current['category'] ?? '').toString();
                          await LogsService().saveLog(
                            modulo: logModulo,
                            acao: typeLog == 'income'
                                ? 'Excluiu receita'
                                : 'Excluiu despesa',
                            detalhes:
                                '${categoryLog.isEmpty ? 'Categoria' : categoryLog} • ${CurrencyFormats.formatBRL(amountLog)}',
                          );
                          onDeleted?.call(docId, effectiveDate);
                          if (ctx.mounted) {
                            Navigator.pop(ctx, false);
                            final extra = metaInfo?.hasWeeksImpact == true
                                ? ' Semanas da meta atualizadas.'
                                : '';
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                  content: Text('Lançamento excluído.$extra')),
                            );
                          }
                        },
                      ),
                    ),
                  ),
                  Padding(
                    padding: EdgeInsets.fromLTRB(
                        16, 8, 16, 12 + MediaQuery.paddingOf(ctx).bottom),
                    child: Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => Navigator.pop(ctx, false),
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              side: BorderSide(
                                  color: editAccent.withValues(alpha: 0.4)),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14)),
                            ),
                            child: Text('Cancelar',
                                style: TextStyle(
                                    fontWeight: FontWeight.w800,
                                    color: editAccent)),
                          ),
                        ),
                        SizedBox(width: 10),
                        Expanded(
                          flex: 2,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(14),
                              gradient: LinearGradient(
                                colors: [
                                  editAccent,
                                  Color.lerp(
                                      editAccent, AppColors.secondary, 0.35)!
                                ],
                              ),
                            ),
                            child: FilledButton(
                              onPressed: () {
                                if (type == 'expense' &&
                                    financeAccounts.isNotEmpty &&
                                    (selectedFinanceAccountId == null ||
                                        selectedFinanceAccountId!
                                            .trim()
                                            .isEmpty)) {
                                  ScaffoldMessenger.of(ctx).showSnackBar(
                                    const SnackBar(
                                        content: Text(
                                            'Selecione a conta da despesa.')),
                                  );
                                  return;
                                }
                                Navigator.pop(ctx, true);
                              },
                              style: FilledButton.styleFrom(
                                backgroundColor: Colors.transparent,
                                shadowColor: Colors.transparent,
                                foregroundColor: Colors.white,
                                padding:
                                    const EdgeInsets.symmetric(vertical: 14),
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(14)),
                              ),
                              child: Text('Salvar',
                                  style:
                                      TextStyle(fontWeight: FontWeight.w900)),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    ),
  );

  if (ok != true || !context.mounted) {
    amountCtrl.dispose();
    descCtrl.dispose();
    catCtrl.dispose();
    return false;
  }

  final amount = CurrencyFormats.parseBRLInput(amountCtrl.text) ?? 0;
  var categoryFinal =
      selectedCategory == '__outra__' ? catCtrl.text.trim() : selectedCategory;
  if (categoryFinal.isEmpty || categoryFinal == incluirNovaCat) {
    categoryFinal = type == 'income' ? 'Receita' : 'Despesa';
  }
  if (amount.isNaN || amount.isInfinite || amount <= 0) {
    amountCtrl.dispose();
    descCtrl.dispose();
    catCtrl.dispose();
    return false;
  }

  final updateData = <String, dynamic>{
    'amount': amount,
    'category': categoryFinal,
    'description': descCtrl.text.trim(),
    'status': status,
    'date': Timestamp.fromDate(FinanceTransactionDatetime.withoutSeconds(date)),
    'updatedAt': YahwehFv.serverTimestamp,
  };
  final paidForEffective = status == 'paid'
      ? (current['paidAt'] is Timestamp
          ? current['paidAt'] as Timestamp
          : Timestamp.fromDate(date))
      : null;
  updateData['effectiveDate'] = FinanceLineOpening.effectiveTimestampForWrite(
    date: FinanceTransactionDatetime.withoutSeconds(date),
    paidAt: paidForEffective,
  );

  updateData.addAll(vinculo.paraFirestore());

  // A conta tem de ser escrita nos TRES campos.
  //
  // O saldo por banco (`financeSaldoPorContaAteInclusive`) nao olha para
  // `financeAccountId`: le `contaDestinoId` na receita e `contaOrigemId` na
  // despesa. Como o editor so gravava `financeAccountId`, trocar a conta de um
  // lancamento nao mexia em saldo nenhum — e pior, o `contaOrigemId` antigo
  // ficava la e o dinheiro continuava a ser descontado do banco errado.
  // (Na criacao isto ja era feito pelo `TransactionSaveService`.)
  final aid = selectedFinanceAccountId?.trim() ?? '';
  final ehReceita = type == 'income';
  if (aid.isEmpty) {
    updateData['financeAccountId'] = YahwehFv.deleteField;
    updateData['contaOrigemId'] = YahwehFv.deleteField;
    updateData['contaDestinoId'] = YahwehFv.deleteField;
    updateData['contaId'] = YahwehFv.deleteField;
  } else {
    updateData['financeAccountId'] = aid;
    updateData['contaId'] = aid;
    if (ehReceita) {
      updateData['contaDestinoId'] = aid;
      updateData['contaOrigemId'] = YahwehFv.deleteField;
    } else {
      updateData['contaOrigemId'] = aid;
      updateData['contaDestinoId'] = YahwehFv.deleteField;
    }
  }

  if (status == 'pending') {
    updateData['addToCalendar'] = addToCalendar;
    updateData['hideFromCalendar'] = !addToCalendar;
    if (addToCalendar &&
        calendarColorHex != null &&
        calendarColorHex!.trim().isNotEmpty) {
      updateData['calendarColorHex'] = calendarColorHex!.trim();
    } else {
      updateData['calendarColorHex'] = YahwehFv.deleteField;
    }
  } else {
    updateData['addToCalendar'] = false;
    updateData['hideFromCalendar'] = YahwehFv.deleteField;
    updateData['calendarColorHex'] = YahwehFv.deleteField;
  }

  /// Motivo da falha do comprovante, quando houver — o lancamento grava na
  /// mesma e o utilizador e avisado no fim.
  String? comprovanteFalhou;

  // Comprovante NÃO é recurso premium: a igreja em plano FREE anexava, via a
  // miniatura e o olho, salvava — e o ficheiro era descartado em silêncio
  // porque este bloco estava dentro de `if (profile.temAcessoPremium)`.
  if (removeReceipt) {
    updateData['receipt'] = YahwehFv.deleteField;
    updateData['hasReceipt'] = false;
  } else if (newReceiptBytes != null &&
      newReceiptBytes!.isNotEmpty &&
      newReceiptName.isNotEmpty &&
      newReceiptMime != null) {
    // O comprovante e anexo: nao pode vetar o lancamento. Este `await` estava
    // FORA do try da gravacao — uma falha de upload (rede, Storage, cliente
    // web envenenado) derrubava o save inteiro e o utilizador perdia valor,
    // data e categoria que tinha acabado de editar, nao so o ficheiro.
    try {
      await FinanceReceiptUploadService.attachToTransaction(
        uid: uid,
        txDocId: docId,
        bytes: newReceiptBytes!,
        filename: newReceiptName,
        mimeType: newReceiptMime!,
        context: context,
      );
      updateData['hasReceipt'] = true;
    } catch (receiptErr) {
      comprovanteFalhou = receiptErr is StateError
          ? receiptErr.message
          : 'Nao foi possivel anexar o comprovante. '
                'O lancamento foi gravado sem ele.';
    }
  }

  try {
    // Coleção real do lançamento (`igrejas/{churchId}/finance`) — era
    // `users/{uid}/transactions` (caminho legado inexistente), então a
    // edição (incluindo anexar comprovante) sempre lançava "not-found" aqui,
    // mesmo já tendo subido o arquivo para o Storage/doc real antes.
    await YahwehDocWrite.update(TransactionSaveService.txRef(fsUid).doc(docId), updateData);
    final goalId = (current['goalId'] ?? '').toString().trim();
    if (goalId.isNotEmpty && type == 'income') {
      unawaited(
        GoalDepositService.syncFromTransaction(
          uid: uid,
          goalId: goalId,
          txId: docId,
          amount: amount,
          date: date,
          financeAccountId: aid.isEmpty ? null : aid,
        ).catchError((_) {}),
      );
    }
    final effectiveDate = FinanceTransactionDatetime.withoutSeconds(date);
    onSaved?.call(
        docId,
        {
          'type': type,
          'amount': amount,
          'category': categoryFinal,
          'description': descCtrl.text.trim(),
          'status': status,
          'date': Timestamp.fromDate(effectiveDate),
          'financeAccountId': aid,
          'addToCalendar': status == 'pending' && addToCalendar,
          'hideFromCalendar': status == 'pending' && !addToCalendar,
          if (status == 'pending' &&
              addToCalendar &&
              calendarColorHex != null &&
              calendarColorHex!.trim().isNotEmpty)
            'calendarColorHex': calendarColorHex!.trim(),
        },
        effectiveDate);
    if (context.mounted) {
      HapticFeedback.lightImpact();
      // Lancamento gravado; se so o comprovante falhou, avisa sem o perder.
      final falha = comprovanteFalhou;
      ScaffoldMessenger.of(context).showSnackBar(
        falha == null
            ? const SnackBar(content: Text('Lançamento atualizado.'))
            : SnackBar(
                content: Text(falha),
                backgroundColor: Colors.orange.shade800,
                duration: const Duration(seconds: 6),
              ),
      );
    }
    unawaited(
      LogsService()
          .saveLog(
            modulo: logModulo,
            acao: type == 'income' ? 'Editou receita' : 'Editou despesa',
            detalhes: '$categoryFinal • ${CurrencyFormats.formatBRL(amount)}',
          )
          .catchError((_) {}),
    );
    amountCtrl.dispose();
    descCtrl.dispose();
    catCtrl.dispose();
    return true;
  } catch (err) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Erro ao atualizar: ${err.toString().split('\n').first}'),
        backgroundColor: AppColors.error,
      ));
    }
    amountCtrl.dispose();
    descCtrl.dispose();
    catCtrl.dispose();
    return false;
  }
}

class _GoalFinanceEditContext {
  const _GoalFinanceEditContext({
    required this.is52,
    required this.goalData,
    required this.schedule,
    required this.initialWeeks,
    required this.goalTitle,
  });

  final bool is52;
  final Map<String, dynamic> goalData;
  final List<FiftyTwoWeeksWeekEntry> schedule;
  final List<int> initialWeeks;
  final String goalTitle;
}

Future<_GoalFinanceEditContext?> _loadGoalFinanceEditContext({
  required String fsUid,
  required String goalId,
  required String txId,
}) async {
  try {
    final goalRef = FirebaseFirestore.instance
        .collection('users')
        .doc(fsUid)
        .collection('goals')
        .doc(goalId);
    final goalSnap = await goalRef.get();
    if (!goalSnap.exists) return null;
    final goalData = goalSnap.data() ?? {};
    final is52 = FiftyTwoWeeksPlan.is52WeeksGoal(goalData);
    final target = (goalData['targetAmount'] as num?)?.toDouble() ?? 0;
    final planStart =
        FiftyTwoWeeksPlan.planStartFromData(goalData) ?? DateTime.now();
    final schedule = is52
        ? FiftyTwoWeeksPlan.buildSchedule(target: target, planStart: planStart)
        : const <FiftyTwoWeeksWeekEntry>[];
    var initialWeeks = <int>[];
    final contribQ = await goalRef
        .collection('contributions')
        .where('transactionId', isEqualTo: txId)
        .limit(1)
        .get();
    if (contribQ.docs.isNotEmpty) {
      initialWeeks =
          GoalDepositService.weeksFromContribData(contribQ.docs.first.data());
    }
    return _GoalFinanceEditContext(
      is52: is52,
      goalData: goalData,
      schedule: schedule,
      initialWeeks: initialWeeks,
      goalTitle: (goalData['title'] ?? 'Meta').toString(),
    );
  } catch (_) {
    return null;
  }
}
