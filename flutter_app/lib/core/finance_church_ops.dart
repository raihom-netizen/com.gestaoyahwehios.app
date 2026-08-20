/// Operações financeiras da igreja (compatibilidade).
///
/// Funções church-specific que eram parte do antigo `finance_page.dart`
/// do YAHWEH e agora são fornecidas como módulo separado, já que o
/// novo módulo financeiro veio do Controle Total App.
library;

import 'package:gestao_yahweh/ui/widgets/finance_vinculo_picker.dart';
import 'package:gestao_yahweh/ui/pages/novo_lancamento_page.dart';
import 'package:gestao_yahweh/core/data/yahweh_write_batch.dart';
import 'package:gestao_yahweh/utils/firestore_rest_read.dart';
import 'package:gestao_yahweh/core/data/yahweh_rest_first.dart';
import 'package:gestao_yahweh/utils/finance_line_opening.dart';
import 'package:gestao_yahweh/utils/finance_transactions_hub.dart';
import 'package:gestao_yahweh/core/firebase_bootstrap.dart';
import 'package:gestao_yahweh/ui/widgets/finance_transaction_edit_dialog.dart';
import 'package:gestao_yahweh/services/user_profile_startup_cache.dart';
import 'package:gestao_yahweh/models/user_profile.dart';
import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:gestao_yahweh/core/cache/tenant_deleted_doc_tombstones.dart';
import 'package:gestao_yahweh/core/finance_infer_tipo.dart';
import 'package:gestao_yahweh/core/cache/tenant_module_keys.dart';
import 'package:gestao_yahweh/core/repositories/church_repository.dart';
import 'package:gestao_yahweh/services/church_finance_realtime_service.dart';
import 'package:gestao_yahweh/services/finance_audit_log_service.dart';
import 'package:gestao_yahweh/services/finance_comprovante_attach_flow.dart';
import 'package:gestao_yahweh/services/finance_comprovante_attach_service.dart';
import 'package:gestao_yahweh/services/finance_comprovante_update_service.dart';
import 'package:gestao_yahweh/services/church_context_service.dart';
import 'package:gestao_yahweh/ui/theme_clean_premium.dart';
import 'package:gestao_yahweh/utils/firestore_web_guard.dart';
import 'package:gestao_yahweh/core/data/yahweh_doc_write.dart';

// ────────────────────────────────────────────────────────────────────────────
// Exclusão com auditoria
// ────────────────────────────────────────────────────────────────────────────

/// Exclui um lançamento financeiro do Firestore com auditoria e invalidação de cache.
Future<void> excluirLancamentoFinanceiroComAuditoria(
  DocumentSnapshot<Map<String, dynamic>> doc,
  String tenantId,
) async {
  final data = Map<String, dynamic>.from(doc.data() ?? {});
  TenantDeletedDocTombstones.mark(
    tenantId,
    TenantModuleKeys.financeiro,
    [doc.id],
  );
  try {
    await logFinanceiroAuditoria(
      tenantId: tenantId,
      acao: 'exclusao',
      lancamentoId: doc.id,
      dadosAntes: data,
    );
  } catch (_) {}
  if (kIsWeb) {
    await FirestoreWebGuard.prepareForPublishWrite().catchError((_) {});
  }
  await FirestoreWebGuard.runWithWebRecovery(
    () => YahwehDocWrite.delete(doc.reference),
    maxAttempts: 2,
  );
  unawaited(ChurchFinanceRealtimeService.onFinanceMutation(tenantId));
  // Saldos recalculam sozinhos a partir daqui.
  //
  // Antes so o `finance_page` invalidava, e so quando era ele o chamador:
  // excluir a partir de Fornecedores (ou de qualquer outro modulo) deixava o
  // saldo de abertura e os totais com o valor antigo ate a proxima leitura
  // fria. Pondo a notificacao na primitiva, todos os caminhos ficam cobertos.
  FinanceTransactionsHub.marcarApagado(doc.id);
  FinanceTransactionsHub.notifyMutated(
    uid: tenantId,
    effectiveDate: FinanceLineOpening.effectiveDateTimeFromMap(data),
  );
}

// ────────────────────────────────────────────────────────────────────────────
// Upload de comprovante
// ────────────────────────────────────────────────────────────────────────────

/// Faz upload de comprovante para um lançamento financeiro.
Future<void> uploadFinanceComprovanteForLancamento(
  BuildContext context, {
  required String tenantId,
  required DocumentSnapshot<Map<String, dynamic>> doc,
}) async {
  await FinanceComprovanteAttachFlow.attachToLancamento(
    context: context,
    tenantId: tenantId,
    docRef: doc.reference,
    docData: doc.data(),
  );
}

// ────────────────────────────────────────────────────────────────────────────
// Remover comprovante
// ────────────────────────────────────────────────────────────────────────────

/// Remove o comprovante anexado a um lançamento financeiro.
Future<void> removeFinanceComprovanteForLancamento(
  BuildContext context, {
  required String tenantId,
  required DocumentSnapshot<Map<String, dynamic>> doc,
  VoidCallback? onChanged,
}) async {
  final data = doc.data() ?? {};
  if (!FinanceComprovanteAttachService.hasComprovanteInDoc(data)) return;
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusLg),
      ),
      title: const Text('Remover comprovante'),
      content: const Text(
        'O comprovante será removido deste lançamento e apagado do armazenamento.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: ThemeCleanPremium.error,
          ),
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('Remover'),
        ),
      ],
    ),
  );
  if (ok != true || !context.mounted) return;
  try {
    await FinanceComprovanteUpdateService.removeFinanceLancamentoStrict(
      churchIdHint: tenantId,
      docRef: doc.reference,
      data: data,
    );
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      ThemeCleanPremium.successSnackBar('Comprovante removido.'),
    );
    onChanged?.call();
    unawaited(ChurchFinanceRealtimeService.onFinanceMutation(tenantId));
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString())),
      );
    }
  }
}

// ────────────────────────────────────────────────────────────────────────────
// Detalhes do lançamento (bottom sheet)
// ────────────────────────────────────────────────────────────────────────────

/// Mostra um bottom sheet com os detalhes de um lançamento financeiro.
void showFinanceLancamentoDetailsBottomSheet(
  BuildContext context, {
  required Map<String, dynamic> data,
  required String comprovanteUrl,
  required String dataStr,
  required bool isEntrada,
  required bool isTransfer,
  required Color color,
  required double valor,
  required String titulo,
  required String subtitulo,
}) {
  final tipoLabel =
      isTransfer ? 'Transferência' : (isEntrada ? 'Receita' : 'Despesa');
  final origemNome = (data['contaOrigemNome'] ?? '').toString();
  final destinoNome = (data['contaDestinoNome'] ?? '').toString();
  showModalBottomSheet(
    context: context,
    shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (ctx) => Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
              child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(2)))),
          const SizedBox(height: 20),
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12)),
                child: Icon(
                    isTransfer
                        ? Icons.swap_horiz_rounded
                        : (isEntrada
                            ? Icons.trending_up_rounded
                            : Icons.trending_down_rounded),
                    color: color,
                    size: 28),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(titulo,
                        style: const TextStyle(
                            fontSize: 18, fontWeight: FontWeight.w800)),
                    Text(tipoLabel,
                        style: TextStyle(
                            fontSize: 13,
                            color: color,
                            fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
              Text('R\$ ${valor.toStringAsFixed(2)}',
                  style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                      color: color)),
            ],
          ),
          const SizedBox(height: 16),
          if (isTransfer &&
              origemNome.isNotEmpty &&
              destinoNome.isNotEmpty) ...[
            Text('Conta de origem',
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey.shade600)),
            Text(origemNome, style: const TextStyle(fontSize: 15)),
            const SizedBox(height: 8),
            Text('Conta de destino',
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey.shade600)),
            Text(destinoNome, style: const TextStyle(fontSize: 15)),
            const SizedBox(height: 12),
          ],
          if (subtitulo.isNotEmpty && !isTransfer) ...[
            Text('Descrição',
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey.shade600)),
            Text(subtitulo, style: const TextStyle(fontSize: 15)),
            const SizedBox(height: 12),
          ],
          Text('Data',
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey.shade600)),
          Text(dataStr, style: const TextStyle(fontSize: 15)),
          const SizedBox(height: 16),
          if (comprovanteUrl.isNotEmpty ||
              FinanceComprovanteAttachService.hasComprovanteInDoc(data)) ...[
            Text('Comprovante',
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey.shade600)),
            const SizedBox(height: 4),
            Text(comprovanteUrl.isNotEmpty ? 'Disponível' : 'Interno',
                style: const TextStyle(fontSize: 14)),
          ],
        ],
      ),
    ),
  );
}

// ────────────────────────────────────────────────────────────────────────────
// Editor de lançamento (compatibilidade church)
// ────────────────────────────────────────────────────────────────────────────

/// Abre o editor de lançamento financeiro para a igreja.
///
/// Esta é uma versão simplificada que cria/edita lançamentos diretamente
/// no Firestore da igreja. O módulo financeiro principal (FinanceScreen)
/// tem o seu próprio editor inline.
/// Perfil para abrir o editor completo do Financeiro a partir de outro modulo.
///
/// Mesmo caminho do [CompromissoExpressFullForm]: cache de arranque primeiro,
/// leitura do `users/{uid}` depois. Devolve `null` quando nao da — o chamador
/// cai no editor curto.
/// Perfil usado pelo editor de lançamentos do Financeiro.
///
/// Público porque o extrato por membro/fornecedor abre o **mesmo** editor: sem
/// perfil o diálogo não abre, e duplicar esta resolução dava duas noções
/// diferentes de quem está a editar.
Future<UserProfile?> perfilParaEditorFinanceiro(String uid, {String? panelRole}) =>
    _perfilParaEditorCompleto(uid, panelRole: panelRole);

Future<UserProfile?> _perfilParaEditorCompleto(String uid, {String? panelRole}) async {
  final id = uid.trim();
  if (id.isEmpty) return null;
  final cached = UserProfileStartupCache.resolveForShell(shellUid: id);
  if (cached != null) return cached;
  final authUid = firebaseDefaultAuth.currentUser?.uid.trim() ?? '';
  if (authUid.isEmpty) return null;

  // Leitura pelo gateway REST. Com `.get()` cru do SDK esta leitura falhava na
  // web (INTERNAL ASSERTION do Firestore JS) e devolvia null — e um null aqui
  // nao dava erro nenhum: mandava o utilizador para o editor CURTO, sem
  // status, conta, vinculo nem comprovante. Era esse o «Fornecedores nao esta
  // igual ao Financeiro».
  Map<String, dynamic>? dados;
  try {
    if (YahwehRestFirst.prefer) {
      final snap = await firestoreRestGetDocSnap('users/$authUid')
          .timeout(const Duration(seconds: 8));
      dados = snap.data();
    } else {
      final snap = await firebaseDefaultFirestore
          .collection('users')
          .doc(authUid)
          .get()
          .timeout(const Duration(seconds: 8));
      dados = snap.data();
    }
  } catch (_) {
    dados = null;
  }
  if (dados != null && dados.isNotEmpty) {
    return UserProfile.fromFirestoreMap(authUid, dados);
  }

  // Sem o documento (rede, permissoes, cache fria) ainda assim se abre o
  // editor completo: quem esta no painel ja passou pelo guarda de licenca do
  // shell, e cair na folha curta perde funcionalidade que o utilizador espera.
  final user = firebaseDefaultAuth.currentUser;
  return UserProfile(
    uid: authUid,
    cpf: '',
    cpfMasked: '',
    email: user?.email ?? '',
    name: user?.displayName ?? 'Utilizador',
    role: (panelRole ?? '').trim().isEmpty ? 'admin' : panelRole!.trim(),
    plan: 'premium',
    planStatus: 'active',
  );
}

Future<bool> showFinanceLancamentoEditorForTenant(
  BuildContext context, {
  required String tenantId,
  DocumentSnapshot<Map<String, dynamic>>? existingDoc,
  String? presetFornecedorId,
  String? presetFornecedorNome,
  bool lockFornecedor = false,
  String? panelRole,
  String? presetNovoTipo,
  String? presetContaOrigemId,
}) async {
  final effectiveTenantId =
      ChurchContextService.panelChurchId(ChurchRepository.churchId(tenantId));
  if (effectiveTenantId.isEmpty) return false;

  final isEdit = existingDoc != null;
  final data = existingDoc?.data();

  // ── Editar: a MESMA tela do Financeiro ────────────────────────────────────
  //
  // Esta folha aqui embaixo e o editor curto (tipo, valor, descricao,
  // categoria). Serve para criar depressa, mas ao EDITAR faltava tudo o que o
  // utilizador precisa: status pago/pendente, conta do lancamento, mostrar no
  // calendario, cor, e sobretudo **anexar comprovante**. Quem edita um
  // lancamento de fornecedor tem de ver o mesmo que ve no modulo Financeiro.
  //
  // O dialogo completo exige um [UserProfile]; se nao houver forma de o obter
  // (sessao a arrancar, cache fria e leitura falhada), continua-se na folha
  // curta em vez de deixar o utilizador sem editor nenhum.
  if (isEdit && data != null) {
    final tipoAtual = financeInferTipo(data);
    if (tipoAtual == 'entrada' || tipoAtual == 'saida') {
      final profile = await _perfilParaEditorCompleto(
        effectiveTenantId,
        panelRole: panelRole,
      );
      if (profile != null && context.mounted) {
        final salvo = await showFinanceTransactionEditDialog(
          context: context,
          uid: effectiveTenantId,
          profile: profile,
          docId: existingDoc.id,
          current: data,
          type: tipoAtual == 'entrada' ? 'income' : 'expense',
          logModulo: 'Fornecedores',
          // Sem isto, editar o valor a partir de Fornecedores nao mexia no
          // saldo de abertura — quem invalidava era so o `finance_page`.
          onSaved: (id, patch, effectiveDate) {
            FinanceTransactionsHub.notifyMutated(
              uid: effectiveTenantId,
              effectiveDate: effectiveDate,
            );
          },
          onDeleted: (id, effectiveDate) {
            FinanceTransactionsHub.marcarApagado(id);
            FinanceTransactionsHub.notifyMutated(
              uid: effectiveTenantId,
              effectiveDate: effectiveDate,
            );
          },
        );
        return salvo;
      }
    }
  }
  // ── Criar: a MESMA tela do Financeiro ──────────────────────────
  //
  // A folha curta lá em baixo pede tipo, valor, descrição e categoria. Falta
  // tudo o resto: conta, pago/pendente, vencimento, comprovante. Lançar a
  // partir de Fornecedores ou da ficha de um membro tem de dar exatamente o
  // mesmo que lançar pelo Financeiro — só muda o vínculo, que já vem
  // preenchido porque a pessoa foi escolhida ao abrir o ecrã.
  //
  // Transferência continua na folha curta: não é receita nem despesa e a
  // [NovoLancamentoPage] não a trata.
  if (!isEdit && presetNovoTipo != 'transferencia') {
    final perfil = await _perfilParaEditorCompleto(
      effectiveTenantId,
      panelRole: panelRole,
    );
    if (context.mounted) {
      final fid = (presetFornecedorId ?? '').trim();
      final salvo = await Navigator.of(context).push<bool>(
        MaterialPageRoute<bool>(
          fullscreenDialog: true,
          builder: (_) => NovoLancamentoPage(
            uid: effectiveTenantId,
            initialType:
                presetNovoTipo == 'saida' ? 'expense' : 'income',
            hasActiveLicense: perfil?.hasActiveLicense ?? true,
            vinculoFixo: fid.isEmpty
                ? null
                : FinanceVinculo(
                    tipo: 'fornecedor',
                    id: fid,
                    nome: (presetFornecedorNome ?? '').trim().isEmpty
                        ? fid
                        : presetFornecedorNome!.trim(),
                  ),
            travarVinculo: fid.isNotEmpty && lockFornecedor,
          ),
        ),
      );
      if (salvo == true) {
        FinanceTransactionsHub.notifyMutated(uid: effectiveTenantId);
      }
      return salvo == true;
    }
  }

  final financeCol = ChurchUiCollections.financeiro(effectiveTenantId);

  String tipo = isEdit ? financeInferTipo(data ?? const {}) : 'entrada';
  if (tipo != 'entrada' && tipo != 'saida' && tipo != 'transferencia') {
    tipo = 'entrada';
  }
  if (!isEdit && presetNovoTipo != null) {
    final p = presetNovoTipo.trim().toLowerCase();
    if (p == 'entrada' || p == 'saida' || p == 'transferencia') {
      tipo = p;
    }
  }

  final amtInicial = isEdit
      ? ((data?['amount'] ?? data?['valor']) ?? 0).toDouble()
      : 0.0;
  final valorCtrl = TextEditingController(
      text: isEdit && amtInicial > 0 ? amtInicial.toStringAsFixed(2) : '');
  final descCtrl = TextEditingController(
      text: isEdit
          ? (data?['descricao'] ?? data?['anotacoes'] ?? '').toString()
          : '');
  String categoria = isEdit ? (data?['categoria'] ?? '').toString() : '';
  DateTime dataSel = DateTime.now();
  if (isEdit) {
    final ts = data?['createdAt'] ?? data?['date'];
    if (ts is Timestamp) dataSel = ts.toDate();
  }

  // A resolucao do perfil acima e assincrona: confirmar que a tela ainda esta
  // montada antes de abrir a folha curta.
  if (!context.mounted) return false;
  final result = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (ctx) {
      return Padding(
        padding: EdgeInsets.fromLTRB(
          24, 24, 24, MediaQuery.of(ctx).viewInsets.bottom + 24,
        ),
        child: StatefulBuilder(
          builder: (ctx, setModalState) {
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40, height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(isEdit ? 'Editar lançamento' : 'Novo lançamento',
                    style: const TextStyle(
                        fontSize: 20, fontWeight: FontWeight.w800)),
                const SizedBox(height: 20),
                // Tipo
                Row(children: [
                  _tipoChip('Entrada', 'entrada', tipo,
                      Colors.blue, (v) => setModalState(() => tipo = v)),
                  const SizedBox(width: 8),
                  _tipoChip('Saída', 'saida', tipo,
                      Colors.red, (v) => setModalState(() => tipo = v)),
                  const SizedBox(width: 8),
                  _tipoChip('Transf.', 'transferencia', tipo,
                      Colors.indigo, (v) => setModalState(() => tipo = v)),
                ]),
                const SizedBox(height: 16),
                // Valor
                TextField(
                  controller: valorCtrl,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(
                    labelText: 'Valor (R\$)',
                    prefixText: 'R\$ ',
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                ),
                const SizedBox(height: 12),
                // Descrição
                TextField(
                  controller: descCtrl,
                  maxLines: 2,
                  decoration: InputDecoration(
                    labelText: 'Descrição',
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                ),
                const SizedBox(height: 12),
                // Categoria
                TextField(
                  controller: TextEditingController(text: categoria),
                  decoration: InputDecoration(
                    labelText: 'Categoria',
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  onChanged: (v) => categoria = v,
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: ThemeCleanPremium.success,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    onPressed: () async {
                      final valor = double.tryParse(
                          valorCtrl.text.replaceAll(',', '.'));
                      if (valor == null || valor <= 0) {
                        ScaffoldMessenger.of(ctx).showSnackBar(
                          const SnackBar(content: Text('Informe um valor válido.')),
                        );
                        return;
                      }
                      final desc = descCtrl.text.trim();
                      if (desc.isEmpty) {
                        ScaffoldMessenger.of(ctx).showSnackBar(
                          const SnackBar(content: Text('Informe uma descrição.')),
                        );
                        return;
                      }
                      try {
                        final payload = <String, dynamic>{
                          'amount': valor,
                          'valor': valor,
                          'descricao': desc,
                          'categoria': categoria,
                          'tipo': tipo,
                          'date': Timestamp.fromDate(dataSel),
                          'updatedAt': YahwehFv.serverTimestamp,
                        };
                        if (presetFornecedorId != null) {
                          payload['fornecedorId'] = presetFornecedorId;
                          payload['fornecedorNome'] =
                              presetFornecedorNome ?? '';
                        }
                        if (isEdit) {
                          await YahwehDocWrite.update(existingDoc.reference, payload);
                        } else {
                          payload['createdAt'] = YahwehFv.serverTimestamp;
                          payload['churchId'] = effectiveTenantId;
                          await financeCol.add(payload);
                        }
                        unawaited(ChurchFinanceRealtimeService
                            .onFinanceMutation(effectiveTenantId));
                        Navigator.pop(ctx, true);
                      } catch (e) {
                        ScaffoldMessenger.of(ctx).showSnackBar(
                          SnackBar(content: Text(e.toString())),
                        );
                      }
                    },
                    child: Text(isEdit ? 'Salvar' : 'Criar',
                        style: const TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w700)),
                  ),
                ),
              ],
            );
          },
        ),
      );
    },
  );
  return result == true;
}

Widget _tipoChip(
  String label,
  String value,
  String selected,
  Color color,
  ValueChanged<String> onTap,
) {
  final isSelected = selected == value;
  return InkWell(
    onTap: () => onTap(value),
    borderRadius: BorderRadius.circular(20),
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: isSelected ? color.withValues(alpha: 0.15) : Colors.grey.shade100,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isSelected ? color : Colors.transparent,
          width: 1.5,
        ),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: isSelected ? color : Colors.grey.shade700,
        ),
      ),
    ),
  );
}
