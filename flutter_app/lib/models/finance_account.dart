import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:gestao_yahweh/constants/finance_bank_presets.dart';

/// Conta bancária ou cartão cadastrado pelo usuário.
class FinanceAccount {
  static const String kChecking = 'checking';
  static const String kSavings = 'savings';
  static const String kCard = 'card';
  /// Mesma instituição com conta bancária e cartão (um cadastro; útil p.ex. Nubank corrente + crédito).
  static const String kBankAndCard = 'bank_and_card';
  /// Reserva separada (dinheiro físico / emergência) — Cofre pessoal.
  static const String kVault = 'vault';
  static const String kVaultPresetId = 'cofre_pessoal';

  final String id;
  final String presetId;
  /// Conta corrente, poupança ou cartão (`kChecking` / `kSavings` / `kCard`).
  final String productType;
  final String? nickname;
  final int sortOrder;
  final DateTime? createdAt;
  /// Dia do mês em que a fatura do cartão fecha (1–31), para conferir com o app do banco.
  final int? statementClosingDay;
  /// Tema de cor do card no Financeiro (`ocean`, `violet`, …). Null = automática (banco + tipo).
  final String? cardColorId;

  const FinanceAccount({
    required this.id,
    required this.presetId,
    required this.productType,
    this.nickname,
    this.sortOrder = 0,
    this.createdAt,
    this.statementClosingDay,
    this.cardColorId,
  });

  /// Próxima data de fechimento (só calendário), útil para exibir ao usuário.
  static DateTime? computeNextStatementClosing(int closingDay, [DateTime? from]) {
    if (closingDay < 1 || closingDay > 31) return null;
    final now = from ?? DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final lastThis = DateTime(now.year, now.month + 1, 0).day;
    final dThis = closingDay > lastThis ? lastThis : closingDay;
    final thisMonthClose = DateTime(now.year, now.month, dThis);
    if (today.isBefore(thisMonthClose)) return thisMonthClose;
    final ny = now.month == 12 ? now.year + 1 : now.year;
    final nm = now.month == 12 ? 1 : now.month + 1;
    final lastNext = DateTime(ny, nm + 1, 0).day;
    final dNext = closingDay > lastNext ? lastNext : closingDay;
    return DateTime(ny, nm, dNext);
  }

  /// Compatível com dados antigos (`kind` no Firestore).
  String get kind {
    if (productType == kVault) return 'vault';
    if (productType == kCard) return 'card';
    if (productType == kBankAndCard) return 'bank_and_card';
    return 'bank';
  }

  bool get isVaultProduct => productType == kVault;

  /// Usado em filtros: esta conta representa movimentação de cartão.
  bool get isCardProduct => productType == kCard || productType == kBankAndCard;

  /// Cartão de crédito (fatura futura — status pendente por padrão em despesas).
  bool get isCreditCardProduct => productType == kCard;

  /// Conta bancária / débito (saída imediata do saldo).
  bool get isDebitBankProduct => productType == kChecking || productType == kSavings;

  /// Despesa em cartão de crédito ou conta+cartão → pagamento futuro (pendente).
  bool get expenseDefaultsToPending =>
      productType == kCard || productType == kBankAndCard;

  /// Inclui corrente, poupança e o modo «conta + cartão» (saldo bancário).
  bool get isBankProduct =>
      productType == kChecking || productType == kSavings || productType == kBankAndCard;

  FinanceBankPreset? get preset => financeBankPresetById(presetId);

  String get displayName {
    final n = nickname?.trim();
    if (n != null && n.isNotEmpty) return n;
    if (isVaultProduct) return 'Cofre pessoal';
    return preset?.name ?? presetId;
  }

  /// Rótulo curto do tipo de produto (lista / edição).
  String get productTypeLabel {
    switch (productType) {
      case kSavings:
        return 'Poupança';
      case kCard:
        return 'Cartão';
      case kBankAndCard:
        return 'Conta + cartão';
      case kVault:
        return 'Cofre pessoal';
      case kChecking:
      default:
        return 'Conta corrente';
    }
  }

  /// productType (pessoal) <-> tipoConta (`igrejas/{churchId}/contas`, PT-BR).
  static const Map<String, String> _productTypeToTipoConta = {
    kChecking: 'corrente',
    kSavings: 'poupanca',
    kCard: 'cartao',
    kBankAndCard: 'corrente',
    kVault: 'caixa',
  };
  static String tipoContaFor(String productType) =>
      _productTypeToTipoConta[productType] ?? 'corrente';

  static const Map<String, String> _tipoContaToProductType = {
    'corrente': kChecking,
    'poupanca': kSavings,
    'poupança': kSavings,
    'cartao': kCard,
    'cartão': kCard,
    'caixa': kVault,
  };

  factory FinanceAccount.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? {};
    final created = d['createdAt'];
    final rawSc = d['statementClosingDay'];
    int? statementClosingDay;
    if (rawSc is num) {
      final v = rawSc.toInt();
      if (v >= 1 && v <= 31) statementClosingDay = v;
    }
    final rawCc = (d['cardColorId'] ?? '').toString().trim();
    final cardColorId = rawCc.isEmpty ? null : rawCc;
    final rawPt = (d['productType'] ?? '').toString().trim();
    String pt;
    if (rawPt == kChecking ||
        rawPt == kSavings ||
        rawPt == kCard ||
        rawPt == kBankAndCard ||
        rawPt == kVault) {
      pt = rawPt;
    } else {
      // `igrejas/{churchId}/contas` (padrão Controle Total por igreja) usa
      // `tipoConta` em vez de `productType` — mesma conta, nome PT-BR.
      final tipoConta = (d['tipoConta'] ?? '').toString().trim().toLowerCase();
      final mapped = _tipoContaToProductType[tipoConta];
      if (mapped != null) {
        pt = mapped;
      } else {
        final legacyKind = (d['kind'] ?? 'bank').toString();
        pt = legacyKind == 'card' ? kCard : kChecking;
      }
    }
    final nickname = (d['nickname'] as String?)?.trim().isNotEmpty == true
        ? (d['nickname'] as String).trim()
        : (d['nome'] as String?)?.trim();
    return FinanceAccount(
      id: doc.id,
      presetId: (d['presetId'] ?? 'outro_banco').toString(),
      productType: pt,
      nickname: nickname,
      sortOrder: (d['sortOrder'] is num) ? (d['sortOrder'] as num).toInt() : 0,
      createdAt: created is Timestamp ? created.toDate() : null,
      statementClosingDay: statementClosingDay,
      cardColorId: cardColorId,
    );
  }

  /// Grava no formato de `igrejas/{churchId}/contas` (nome/tipoConta/ativo) —
  /// mesma coleção lida por doações, OFX e o motor de saldo do Financeiro.
  Map<String, dynamic> toMap() {
    return {
      'nome': displayName,
      'tipoConta': _productTypeToTipoConta[productType] ?? 'corrente',
      'ativo': true,
      // Compat: mantém os campos "pessoais" também, para telas ainda não
      // migradas que leem `productType`/`nickname` diretamente do doc.
      'presetId': presetId,
      'productType': productType,
      'kind': kind,
      if (nickname != null && nickname!.trim().isNotEmpty) 'nickname': nickname!.trim(),
      'sortOrder': sortOrder,
      'updatedAt': FieldValue.serverTimestamp(),
      if (statementClosingDay != null) 'statementClosingDay': statementClosingDay,
      if (cardColorId != null && cardColorId!.isNotEmpty) 'cardColorId': cardColorId,
    };
  }
}
