import 'package:gestao_yahweh/core/data/yahweh_write_batch.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:gestao_yahweh/core/firebase_bootstrap.dart';
import 'package:gestao_yahweh/utils/admin_user_search.dart';
import 'package:gestao_yahweh/core/data/yahweh_doc_write.dart';

class UserService {
  final FirebaseFirestore _db = firebaseDefaultFirestore;

  Future<Map<String, dynamic>> ensureUserDoc({
    required String uid,
    String? email,
  }) async {
    final ref = _db.collection('users').doc(uid);
    final snap = await ref.get();

    if (!snap.exists) {
      final emailTrim = (email ?? '').trim().toLowerCase();
      if (!adminUserHasCompleteEmail({'email': emailTrim})) {
        throw StateError(
          'E-mail é obrigatório para criar o perfil do utilizador.',
        );
      }
      final now = DateTime.now();
      final trialEnd = now.add(const Duration(days: 30));

      final data = <String, dynamic>{
        'createdAt': YahwehFv.serverTimestamp,
        'email': emailTrim,
        'onboardingCompleted': false,
        'trialStart': Timestamp.fromDate(now),
        'trialEnd': Timestamp.fromDate(trialEnd),
        'plan': 'trial',
        'status': 'active',
      };

      await YahwehDocWrite.set(ref, data, merge: false);
      return data;
    }

    final data = snap.data() ?? {};

    if (data['trialStart'] == null || data['trialEnd'] == null) {
      final now = DateTime.now();
      final trialEnd = now.add(const Duration(days: 30));
      await YahwehDocWrite.set(ref, {
        'trialStart': Timestamp.fromDate(now),
        'trialEnd': Timestamp.fromDate(trialEnd),
        'plan': data['plan'] ?? 'trial',
        'status': data['status'] ?? 'active',
      });

      final refreshed = await ref.get();
      return refreshed.data() ?? {};
    }

    return data;
  }

  Future<void> markOnboardingDone(String uid) async {
    await YahwehDocWrite.set(_db.collection('users').doc(uid), {
      'onboardingCompleted': true,
      'onboardingAt': YahwehFv.serverTimestamp,
    });
  }
}
