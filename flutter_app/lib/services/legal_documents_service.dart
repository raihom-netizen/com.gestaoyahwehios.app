import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:gestao_yahweh/core/firebase_bootstrap.dart';
import 'package:gestao_yahweh/services/firestore_stream_utils.dart';
import 'package:gestao_yahweh/services/legal_document_models.dart';
import 'package:gestao_yahweh/services/legal_documents_defaults.dart';
import 'package:gestao_yahweh/services/master_admin_firestore.dart';
import 'package:gestao_yahweh/utils/firestore_web_guard.dart';

/// Termos e Política — fonte única `config/legal_documents` (Web = Android = iOS).
abstract final class LegalDocumentsService {
  LegalDocumentsService._();

  static const docPath = 'config/legal_documents';
  static const cacheKey = 'config_legal_documents';

  static LegalDocumentsBundle? _memory;
  static int _memoryRevision = -1;

  static DocumentReference<Map<String, dynamic>> get _ref =>
      firebaseDefaultFirestore.doc(docPath);

  static LegalDocumentsBundle peekCached() =>
      _memory ?? LegalDocumentsDefaults.bundle;

  static void _applyMemory(LegalDocumentsBundle bundle) {
    _memory = bundle;
    _memoryRevision = bundle.revision;
  }

  static LegalDocumentsBundle _parseOrDefault(Map<String, dynamic>? data) {
    if (data == null || data.isEmpty) {
      return LegalDocumentsDefaults.bundle;
    }
    try {
      final parsed = LegalDocumentsBundle.fromFirestore(data);
      if (parsed.terms.intro.trim().isEmpty ||
          parsed.privacy.intro.trim().isEmpty) {
        return LegalDocumentsDefaults.bundle;
      }
      return parsed;
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('LegalDocumentsService parse: $e\n$st');
      }
      return LegalDocumentsDefaults.bundle;
    }
  }

  /// Pré-aquece cache em background (login / arranque).
  static Future<void> warmCache() async {
    try {
      await loadOnce();
    } catch (_) {}
  }

  static Future<LegalDocumentsBundle> loadOnce({
    Source source = Source.serverAndCache,
  }) async {
    if (kIsWeb) {
      await FirestoreWebGuard.ensurePanelReadReady().catchError((_) {});
    }
    try {
      final snap = await FirestoreWebGuard.runWithWebRecovery(
        () => MasterAdminFirestore.document(
          _ref,
          cacheKey: cacheKey,
          source: source,
        ),
        maxAttempts: 3,
      );
      final bundle = snap.exists
          ? _parseOrDefault(snap.data())
          : LegalDocumentsDefaults.bundle;
      _applyMemory(bundle);
      return bundle;
    } catch (_) {
      return peekCached();
    }
  }

  /// Stream em tempo real — alterações do painel master refletem nas telas abertas.
  static Stream<LegalDocumentsBundle> watch() async* {
    if (kIsWeb) {
      await FirestoreWebGuard.ensurePanelReadReady().catchError((_) {});
    }
    yield peekCached();
    yield* _ref.watchSafe().map((snap) {
      final bundle = snap.exists
          ? _parseOrDefault(snap.data())
          : LegalDocumentsDefaults.bundle;
      _applyMemory(bundle);
      return bundle;
    });
  }

  static Future<bool> existsOnServer() async {
    try {
      final snap = await MasterAdminFirestore.document(
        _ref,
        cacheKey: '${cacheKey}_exists',
        source: Source.server,
      );
      return snap.exists;
    } catch (_) {
      return false;
    }
  }

  /// Gravação exclusiva do painel master.
  static Future<int> saveMaster({
    required LegalDocumentsBundle bundle,
    required String uid,
  }) async {
    final nextRev = (_memoryRevision >= 0 ? _memoryRevision : 0) + 1;
    final payload = {
      ...bundle.toFirestore(),
      'revision': nextRev,
      'updatedAt': FieldValue.serverTimestamp(),
      'updatedBy': uid,
    };
    await MasterAdminFirestore.write(
      () => _ref.set(payload, SetOptions(merge: false)),
    );
    final saved = bundle.copyWith(revision: nextRev);
    _applyMemory(saved);
    return nextRev;
  }
}
