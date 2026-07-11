import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:gestao_yahweh/core/repositories/church_repository.dart';
import 'package:gestao_yahweh/services/finance_despesas_categorias_tenant.dart';
import 'package:gestao_yahweh/utils/firestore_web_guard.dart';

/// Categorias de receita padrão para igrejas (seed único na primeira abertura).
const kCategoriasReceitaPadraoIgreja = <String>[
  'Aluguéis Recebidos',
  'Dízimos',
  'Doações',
  'Inscrições em Eventos',
  'Ofertas Missionárias',
  'Ofertas Voluntárias',
  'Vendas de Produtos',
  'Campanhas',
  'Outros',
];

/// Contas básicas da tesouraria (Caixa + corrente) — Mercado Pago via Cloud Function.
const _kContasPadraoIgreja = <({
  String docId,
  String nome,
  String tipoConta,
  String seedPreset,
})>[
  (
    docId: 'caixa_tesouraria',
    nome: 'Caixa da Tesouraria',
    tipoConta: 'caixa',
    seedPreset: 'tesouraria_caixa',
  ),
  (
    docId: 'conta_corrente_principal',
    nome: 'Conta Corrente Principal',
    tipoConta: 'corrente',
    seedPreset: 'tesouraria_corrente',
  ),
];

/// Garante categorias, contas e integração MP ao abrir o módulo Financeiro.
abstract final class FinanceChurchBootstrapService {
  FinanceChurchBootstrapService._();

  static final Set<String> _ensuredChurchIds = <String>{};

  static Future<void> ensureForChurch(String tenantHint) async {
    final churchId = ChurchRepository.churchId(tenantHint.trim());
    if (churchId.isEmpty) return;
    if (_ensuredChurchIds.contains(churchId)) return;
    _ensuredChurchIds.add(churchId);

    await Future.wait<void>([
      _ensureCategoriasReceita(churchId),
      getCategoriasDespesaForTenant(churchId),
      _ensureContasBasicas(churchId),
      _ensureMercadoPagoConta(churchId),
    ], eagerError: false);
  }

  static Future<void> _ensureCategoriasReceita(String churchId) async {
    try {
      final col = ChurchUiCollections.churchDoc(churchId)
          .collection('categorias_receitas');
      var snap = await col.orderBy('nome').limit(1).get();
      if (snap.docs.isNotEmpty) return;
      for (var i = 0; i < kCategoriasReceitaPadraoIgreja.length; i++) {
        final nome = kCategoriasReceitaPadraoIgreja[i];
        await FirestoreWebGuard.runWithWebRecovery(
          () => col.add({'nome': nome, 'ordem': i}),
          maxAttempts: 4,
        );
      }
    } catch (_) {}
  }

  static Future<void> _ensureContasBasicas(String churchId) async {
    try {
      final col = ChurchUiCollections.churchDoc(churchId).collection('contas');
      final any = await col.limit(1).get();
      if (any.docs.isNotEmpty) return;

      for (final preset in _kContasPadraoIgreja) {
        await FirestoreWebGuard.runWithWebRecovery(
          () => col.doc(preset.docId).set({
            'nome': preset.nome,
            'bancoCodigo': '',
            'bancoNome': '',
            'agencia': '',
            'numeroConta': '',
            'tipoConta': preset.tipoConta,
            'observacao': 'Conta padrão da tesouraria.',
            'ativo': true,
            'seedPreset': preset.seedPreset,
            'createdAt': FieldValue.serverTimestamp(),
            'updatedAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true)),
          maxAttempts: 4,
        );
      }
    } catch (_) {}
  }

  static Future<void> _ensureMercadoPagoConta(String churchId) async {
    try {
      final callable = FirebaseFunctions.instanceFor(region: 'us-central1')
          .httpsCallable('ensureChurchTreasuryAccountPresets');
      await callable.call(<String, dynamic>{'tenantId': churchId});
    } catch (_) {}
  }
}
