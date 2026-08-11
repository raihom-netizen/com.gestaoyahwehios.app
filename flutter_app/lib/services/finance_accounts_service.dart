import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart' as fa;
import 'package:gestao_yahweh/core/data/church_ui_collections.dart';
import 'package:gestao_yahweh/models/finance_account.dart';
import 'package:gestao_yahweh/utils/finance_transactions_hub.dart';
import 'package:gestao_yahweh/utils/firestore_web_guard.dart';
import 'finance_advanced_settings_service.dart';
import 'goal_deposit_service.dart';

class FinanceAccountsService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  /// [uid] aqui é o `churchId` — contas do Financeiro são por igreja
  /// (`igrejas/{churchId}/contas`, mesma coleção usada por doações/OFX).
  CollectionReference<Map<String, dynamic>> _col(String uid) =>
      ChurchUiCollections.contas(uid.trim());

  /// Mesma ordenação em todo o app: [sortOrder] crescente, empate por data de criação.
  static void sortFinanceAccounts(List<FinanceAccount> list) {
    list.sort((a, b) {
      final c = a.sortOrder.compareTo(b.sortOrder);
      if (c != 0) return c;
      final da = a.createdAt ?? DateTime(2000);
      final db = b.createdAt ?? DateTime(2000);
      return da.compareTo(db);
    });
  }

  /// Contas: mesma regra de sessão — sem [currentUser] não abrir leitura (erro de permissão na web).
  /// Usa o mesmo caminho que [listOnce]/[setAccountOrder] (`_col`) para a ordem gravada coincidir com o stream.
  ///
  /// **Performance**: para evitar tela vazia "Cadastre contas em Financeiro"
  /// enquanto o servidor responde, lemos do **cache local primeiro**
  /// (`Source.cache`) e emitimos imediatamente — depois deixa o snapshot
  /// listener com o servidor entregar a versão fresca. Em iOS/Android/Web
  /// isso deixa a abertura do bottom sheet **instantânea** quando o usuário
  /// já tem contas cadastradas.
  Stream<List<FinanceAccount>> streamAccounts(String uid) async* {
    final user = fa.FirebaseAuth.instance.currentUser;
    if (user != null) {
      // Tentativa de seed instantâneo via cache local (IndexedDB / disk).
      try {
        final cachedSnap =
            await _col(uid).get(const GetOptions(source: Source.cache));
        if (cachedSnap.docs.isNotEmpty) {
          final list =
              cachedSnap.docs.map(FinanceAccount.fromDoc).toList();
          sortFinanceAccounts(list);
          yield list;
        }
      } catch (_) {
        // Cache miss ou indisponível — segue para o snapshot listener.
      }
      // Seed do SERVIDOR (one-shot). No web, sem IndexedDB, o cache acima vem
      // vazio e a lista de "Bancos e cartões" mostrava 0 até o 1º poll (45s) —
      // este `listOnce` garante as contas já no 1º frame. Barato (1 get).
      try {
        final server = await listOnce(uid);
        if (server.isNotEmpty) yield server;
      } catch (_) {
        // Sem rede/erro — o poll/listener abaixo assume.
      }
    }
    yield* fa.FirebaseAuth.instance.authStateChanges().asyncExpand((u) {
      if (u == null) {
        return Stream<List<FinanceAccount>>.value(const <FinanceAccount>[]);
      }
      // Web: listener ao vivo aqui era mais um alvo de watch simultâneo do
      // Financeiro (INTERNAL ASSERTION FAILED / WatchChangeAggregator). Poll
      // leve substitui sem travar o painel — contas mudam pouco por sessão.
      if (FirestoreWebGuard.disableLiveSnapshotsOnWeb) {
        return _pollAccounts(uid);
      }
      return _col(uid).snapshots().map((snap) {
        final list = snap.docs.map(FinanceAccount.fromDoc).toList();
        sortFinanceAccounts(list);
        return list;
      });
    });
  }

  Stream<List<FinanceAccount>> _pollAccounts(String uid) async* {
    while (true) {
      try {
        final snap = await _col(uid).get();
        final list = snap.docs.map(FinanceAccount.fromDoc).toList();
        sortFinanceAccounts(list);
        yield list;
      } catch (_) {}
      await Future<void>.delayed(const Duration(seconds: 180));
    }
  }

  Future<List<FinanceAccount>> listOnce(String uid) async {
    if (uid.trim().isEmpty) return const [];
    try {
      final snap = await _col(uid).get();
      final list = snap.docs.map(FinanceAccount.fromDoc).toList();
      sortFinanceAccounts(list);
      return list;
    } catch (_) {
      return const [];
    }
  }

  static String _normalizeProductType(String productType) {
    if (productType == FinanceAccount.kChecking ||
        productType == FinanceAccount.kSavings ||
        productType == FinanceAccount.kCard ||
        productType == FinanceAccount.kBankAndCard ||
        productType == FinanceAccount.kVault) {
      return productType;
    }
    return FinanceAccount.kChecking;
  }

  /// Localiza a conta Cofre pessoal na lista (productType vault).
  static FinanceAccount? findVaultAccount(Iterable<FinanceAccount> accounts) {
    for (final a in accounts) {
      if (a.isVaultProduct) return a;
    }
    return null;
  }

  /// Garante uma conta «Cofre pessoal» por usuário (reserva / dinheiro físico).
  Future<String> ensureVaultAccount(String uid) async {
    if (uid.trim().isEmpty) return '';
    final prefs = FinanceAdvancedSettingsService();
    final savedId = await prefs.getVaultAccountId(uid);
    if (savedId != null && savedId.isNotEmpty) {
      final doc = await _col(uid).doc(savedId).get();
      if (doc.exists) {
        final acc = FinanceAccount.fromDoc(doc);
        if (acc.isVaultProduct) return savedId;
      }
    }
    final all = await listOnce(uid);
    final existing = findVaultAccount(all);
    if (existing != null) {
      await prefs.setVaultAccountId(uid, existing.id);
      return existing.id;
    }
    final ref = _col(uid).doc();
    await ref.set({
      ...FinanceAccount(
        id: ref.id,
        presetId: FinanceAccount.kVaultPresetId,
        productType: FinanceAccount.kVault,
        nickname: 'Cofre pessoal',
        sortOrder: -1000000,
      ).toMap(),
      'createdAt': FieldValue.serverTimestamp(),
    });
    await prefs.setVaultAccountId(uid, ref.id);
    return ref.id;
  }

  Future<String> addAccount({
    required String uid,
    required String presetId,
    required String productType,
    String? nickname,
    int? statementClosingDay,
    String? cardColorId,
  }) async {
    final pt = _normalizeProductType(productType);
    final ref = _col(uid).doc();
    final sc = _normalizeStatementClosingDay(statementClosingDay, productType: pt);
    final cc = _normalizeCardColorId(cardColorId);
    await ref.set({
      ...FinanceAccount(
        id: ref.id,
        presetId: presetId,
        productType: pt,
        nickname: nickname,
        sortOrder: DateTime.now().millisecondsSinceEpoch % 1000000,
        statementClosingDay: sc,
        cardColorId: cc,
      ).toMap(),
      'createdAt': FieldValue.serverTimestamp(),
    });
    return ref.id;
  }

  static String? _normalizeCardColorId(String? id) {
    final t = id?.trim();
    if (t == null || t.isEmpty) return null;
    return t;
  }

  static int? _normalizeStatementClosingDay(int? day, {required String productType}) {
    if (day == null) return null;
    if (productType != FinanceAccount.kCard && productType != FinanceAccount.kBankAndCard) return null;
    if (day < 1 || day > 31) return null;
    return day;
  }

  Future<void> updateAccount({
    required String uid,
    required String accountId,
    required String presetId,
    required String productType,
    String? nickname,
    int? statementClosingDay,
    String? cardColorId,
  }) async {
    final pt = _normalizeProductType(productType);
    final sc = _normalizeStatementClosingDay(statementClosingDay, productType: pt);
    final cc = _normalizeCardColorId(cardColorId);
    final acc = FinanceAccount(
      id: accountId,
      presetId: presetId,
      productType: pt,
      nickname: nickname?.trim().isEmpty == true ? null : nickname?.trim(),
      statementClosingDay: sc,
      cardColorId: cc,
    );
    final data = <String, dynamic>{
      'nome': acc.displayName,
      'tipoConta': FinanceAccount.tipoContaFor(acc.productType),
      'presetId': acc.presetId,
      'productType': acc.productType,
      'kind': acc.kind,
      'updatedAt': FieldValue.serverTimestamp(),
    };
    if (acc.nickname == null) {
      data['nickname'] = FieldValue.delete();
    } else {
      data['nickname'] = acc.nickname;
    }
    if (sc != null) {
      data['statementClosingDay'] = sc;
    } else {
      data['statementClosingDay'] = FieldValue.delete();
    }
    if (cc != null) {
      data['cardColorId'] = cc;
    } else {
      data['cardColorId'] = FieldValue.delete();
    }
    await _col(uid).doc(accountId).update(data);
  }

  /// Remove a conta e todos os lançamentos vinculados (inclui transferências relacionadas).
  /// O Cofre pessoal não pode ser excluído.
  Future<int> deleteAccount(String uid, String accountId) async {
    final doc = await _col(uid).doc(accountId).get();
    if (doc.exists) {
      final acc = FinanceAccount.fromDoc(doc);
      if (acc.isVaultProduct) {
        throw StateError('O Cofre pessoal não pode ser excluído.');
      }
    }
    final linkedIds = await _collectLinkedTransactionIds(uid, accountId);
    await _deleteTransactionsByIds(uid, linkedIds);
    await _col(uid).doc(accountId).delete();
    await FinanceAdvancedSettingsService().clearDefaultFinanceAccountIfMatches(uid, accountId);
    FinanceTransactionsHub.notifyMutated(uid: uid.trim());
    return linkedIds.length;
  }

  /// Campos que apontam um lançamento para uma conta.
  static const List<String> _accountLinkFields = [
    'financeAccountId',
    'paidFromFinanceAccountId',
    'contaOrigemId',
    'contaDestinoId',
    'contaId',
  ];

  /// Transfere TODOS os lançamentos de [fromId] para [toId] (reatribui os
  /// campos de conta que apontavam para o banco antigo). Retorna quantos moveu.
  /// Depois disso o banco antigo pode ser excluído já sem lançamentos.
  Future<int> transferAccountTransactions(
      String uid, String fromId, String toId) async {
    if (fromId.trim().isEmpty || toId.trim().isEmpty || fromId == toId) return 0;
    final ids = (await _collectLinkedTransactionIds(uid, fromId)).toList();
    if (ids.isEmpty) return 0;
    final col = _txCol(uid);
    var moved = 0;
    for (var i = 0; i < ids.length; i += 300) {
      final chunk =
          ids.sublist(i, i + 300 > ids.length ? ids.length : i + 300);
      final snaps = await Future.wait(chunk.map((id) => col.doc(id).get()));
      final batch = _db.batch();
      var inBatch = 0;
      for (final snap in snaps) {
        final data = snap.data();
        if (data == null) continue;
        final patch = <String, dynamic>{};
        for (final f in _accountLinkFields) {
          if ((data[f] ?? '').toString().trim() == fromId) patch[f] = toId;
        }
        if (patch.isNotEmpty) {
          batch.update(snap.reference, patch);
          inBatch++;
        }
      }
      if (inBatch > 0) {
        await batch.commit();
        moved += inBatch;
      }
    }
    FinanceTransactionsHub.notifyMutated(uid: uid.trim());
    return moved;
  }

  CollectionReference<Map<String, dynamic>> _txCol(String uid) =>
      ChurchUiCollections.financeiro(uid.trim());

  Future<void> _forEachTxByField(
    String uid,
    String field,
    String value,
    void Function(String docId) onId,
  ) async {
    QueryDocumentSnapshot<Map<String, dynamic>>? last;
    while (true) {
      Query<Map<String, dynamic>> q =
          _txCol(uid).where(field, isEqualTo: value).limit(500);
      if (last != null) q = q.startAfterDocument(last);
      final snap = await q.get();
      if (snap.docs.isEmpty) break;
      for (final doc in snap.docs) {
        onId(doc.id);
      }
      last = snap.docs.last;
      if (snap.docs.length < 500) break;
    }
  }

  Future<Set<String>> _collectLinkedTransactionIds(String uid, String accountId) async {
    final ids = <String>{};
    // TODOS os campos que vinculam um lançamento a uma conta. O write service
    // grava contaOrigemId/contaDestinoId; havia lançamentos ficando órfãos
    // porque só se coletava financeAccountId/paidFromFinanceAccountId ("não
    // limpa" ao remover o banco). contaId = legado (doações MP antigas).
    await _forEachTxByField(uid, 'financeAccountId', accountId, ids.add);
    await _forEachTxByField(uid, 'paidFromFinanceAccountId', accountId, ids.add);
    await _forEachTxByField(uid, 'contaOrigemId', accountId, ids.add);
    await _forEachTxByField(uid, 'contaDestinoId', accountId, ids.add);
    await _forEachTxByField(uid, 'contaId', accountId, ids.add);

    final pairIds = <String>{};
    final idList = ids.toList();
    for (var i = 0; i < idList.length; i += 25) {
      final chunk = idList.sublist(i, i + 25 > idList.length ? idList.length : i + 25);
      final snaps = await Future.wait(chunk.map((id) => _txCol(uid).doc(id).get()));
      for (final snap in snaps) {
        final pair = (snap.data()?['transferPairId'] ?? '').toString().trim();
        if (pair.isNotEmpty) pairIds.add(pair);
      }
    }
    for (final pairId in pairIds) {
      final pairSnap =
          await _txCol(uid).where('transferPairId', isEqualTo: pairId).get();
      for (final doc in pairSnap.docs) {
        ids.add(doc.id);
      }
    }
    return ids;
  }

  Future<void> _deleteTransactionsByIds(String uid, Set<String> ids) async {
    if (ids.isEmpty) return;
    final col = _txCol(uid);

    // Desvincula Meta / recalcula semanas antes de apagar cada lançamento.
    for (final id in ids) {
      try {
        final snap = await col.doc(id).get();
        if (!snap.exists) continue;
        await GoalDepositService.unlinkBeforeTransactionDelete(
          uid: uid,
          txId: id,
          txData: snap.data() ?? {},
        );
      } catch (_) {}
    }

    var batch = _db.batch();
    var n = 0;
    for (final id in ids) {
      batch.delete(col.doc(id));
      n++;
      if (n >= 450) {
        await batch.commit();
        batch = _db.batch();
        n = 0;
      }
    }
    if (n > 0) await batch.commit();
  }

  /// Lançamentos com [financeAccountId] ou [paidFromFinanceAccountId] + pares de transferência.
  Future<int> countLinkedTransactions(String uid, String accountId) async {
    final ids = await _collectLinkedTransactionIds(uid, accountId);
    return ids.length;
  }

  /// Persiste a ordem exibida (campo [FinanceAccount.sortOrder]).
  Future<void> setAccountOrder(String uid, List<String> orderedAccountIds) async {
    if (orderedAccountIds.isEmpty || uid.trim().isEmpty) return;
    final batch = _db.batch();
    for (var i = 0; i < orderedAccountIds.length; i++) {
      batch.update(_col(uid).doc(orderedAccountIds[i]), {
        'sortOrder': i,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    }
    await batch.commit();
  }

  Future<void> updateNickname(String uid, String accountId, String? nickname) async {
    final data = <String, dynamic>{
      'updatedAt': FieldValue.serverTimestamp(),
    };
    final trimmed = nickname?.trim();
    if (trimmed == null || trimmed.isEmpty) {
      data['nickname'] = FieldValue.delete();
      // `nome` fica como está — é o campo lido por doações/OFX/saldo, não
      // pode ficar vazio só porque o apelido pessoal foi removido.
    } else {
      data['nickname'] = trimmed;
      data['nome'] = trimmed;
    }
    await _col(uid).doc(accountId).update(data);
  }
}
