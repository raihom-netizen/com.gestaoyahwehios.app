import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:gestao_yahweh/core/data/church_ui_collections.dart';

/// Preferências opcionais do painel Financeiro (ex.: faixa de contas).

/// Não há mais opção em Configurações para “financeiro avançado”: contas por

/// banco/cartão são sempre ativas; esta classe só guarda prefs complementares.

class FinanceAdvancedSettingsService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  /// [uid] aqui é o `churchId` — prefs do Financeiro são por igreja
  /// (`igrejas/{churchId}/config/finance_prefs`), compartilhadas pela equipe.
  DocumentReference<Map<String, dynamic>> _doc(String uid) =>
      ChurchUiCollections.config(uid.trim()).doc('finance_prefs');

  static const String _keyStripHideZero = 'financeStripHideZeroBalances';

  /// ID do documento em `finance_accounts` usado como padrão em novos lançamentos.
  static const String keyDefaultFinanceAccountId = 'defaultFinanceAccountId';
  static const String keyVaultAccountId = 'vaultAccountId';

  Stream<bool> watchStripHideZeroBalances(String uid) {
    if (uid.isEmpty) return Stream.value(false);
    return _doc(uid).snapshots().map((s) => s.data()?[_keyStripHideZero] == true);
  }

  /// Leitura única (entrada rápida no Financeiro; o stream continua a atualizar).
  Future<bool> getStripHideZeroBalancesOnce(String uid) async {
    if (uid.trim().isEmpty) return false;
    try {
      final snap = await _doc(uid).get();
      return snap.data()?[_keyStripHideZero] == true;
    } catch (_) {
      return false;
    }
  }

  Future<void> setStripHideZeroBalances(String uid, bool value) async {
    if (uid.isEmpty) return;
    await _doc(uid).set({
      _keyStripHideZero: value,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<String?> getDefaultFinanceAccountId(String uid) async {
    if (uid.isEmpty) return null;
    try {
      final snap = await _doc(uid).get();
      final v = snap.data()?[keyDefaultFinanceAccountId];
      if (v is String && v.trim().isNotEmpty) return v.trim();
    } catch (_) {}
    return null;
  }

  Stream<String?> watchDefaultFinanceAccountId(String uid) {
    if (uid.isEmpty) return Stream.value(null);
    return _doc(uid).snapshots().map((s) {
      final v = s.data()?[keyDefaultFinanceAccountId];
      if (v is String && v.trim().isNotEmpty) return v.trim();
      return null;
    });
  }

  Future<void> setDefaultFinanceAccountId(String uid, String? accountId) async {
    if (uid.isEmpty) return;
    if (accountId == null || accountId.trim().isEmpty) {
      await _doc(uid).set({
        keyDefaultFinanceAccountId: FieldValue.delete(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } else {
      await _doc(uid).set({
        keyDefaultFinanceAccountId: accountId.trim(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    }
  }

  Future<void> clearDefaultFinanceAccountIfMatches(String uid, String accountId) async {
    final cur = await getDefaultFinanceAccountId(uid);
    if (cur != null && cur == accountId) {
      await setDefaultFinanceAccountId(uid, null);
    }
  }

  Future<String?> getVaultAccountId(String uid) async {
    if (uid.isEmpty) return null;
    final snap = await _doc(uid).get();
    final v = snap.data()?[keyVaultAccountId];
    if (v is String && v.trim().isNotEmpty) return v.trim();
    return null;
  }

  Future<void> setVaultAccountId(String uid, String accountId) async {
    if (uid.isEmpty || accountId.trim().isEmpty) return;
    await _doc(uid).set({
      keyVaultAccountId: accountId.trim(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }
}

