import 'package:cloud_firestore/cloud_firestore.dart';

class UserService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  Future<Map<String, dynamic>> ensureUserDoc({
    required String uid,
    String? email,
  }) async {
    final ref = _db.collection('users').doc(uid);
    final snap = await ref.get();

    if (!snap.exists) {
      final now = DateTime.now();
      final trialEnd = now.add(const Duration(days: 30));

      final data = <String, dynamic>{
        'createdAt': FieldValue.serverTimestamp(),
        'email': email,
        'onboardingCompleted': false,
        'trialStart': Timestamp.fromDate(now),
        'trialEnd': Timestamp.fromDate(trialEnd),
        'plan': 'trial',
        'status': 'active',
      };

      await ref.set(data);
      return data;
    }

    final data = snap.data() ?? {};

    if (data['trialStart'] == null || data['trialEnd'] == null) {
      final now = DateTime.now();
      final trialEnd = now.add(const Duration(days: 30));
      await ref.set({
        'trialStart': Timestamp.fromDate(now),
        'trialEnd': Timestamp.fromDate(trialEnd),
        'plan': data['plan'] ?? 'trial',
        'status': data['status'] ?? 'active',
      }, SetOptions(merge: true));

      final refreshed = await ref.get();
      return refreshed.data() ?? {};
    }

    return data;
  }

  Future<void> markOnboardingDone(String uid) async {
    await _db.collection('users').doc(uid).set({
      'onboardingCompleted': true,
      'onboardingAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }
}
