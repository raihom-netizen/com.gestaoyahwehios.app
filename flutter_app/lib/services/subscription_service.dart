import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:gestao_yahweh/core/app_constants.dart';

class SubscriptionStatus {
  final String status; // TRIAL / ACTIVE / BLOCKED
  final DateTime? trialEndsAt;
  final DateTime? nextChargeAt; // próxima cobrança (plano pago); usado para carência
  final String planId;

  SubscriptionStatus({
    required this.status,
    required this.planId,
    this.trialEndsAt,
    this.nextChargeAt,
  });
}

class SubscriptionService {
  final _db = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;

  Future<String?> _igrejaIdFromClaims() async {
    final user = _auth.currentUser;
    if (user == null) return null;
    final token = await user.getIdTokenResult(true);
    final igrejaId = token.claims?['igrejaId'];
    return igrejaId?.toString();
  }

  Future<SubscriptionStatus?> getCurrentForMyChurch() async {
    final igrejaId = await _igrejaIdFromClaims();
    if (igrejaId == null || igrejaId.isEmpty) return null;

    final qs = await _db
        .collection('subscriptions')
        .where('igrejaId', isEqualTo: igrejaId)
        .orderBy('createdAt', descending: true)
        .limit(1)
        .get();

    if (qs.docs.isEmpty) return null;

    final d = qs.docs.first.data();
    final status = (d['status'] ?? 'TRIAL').toString();
    final planId = (d['planId'] ?? '').toString();

    DateTime? trialEndsAt;
    final rawTrial = d['trialEndsAt'];
    if (rawTrial is Timestamp) trialEndsAt = rawTrial.toDate();

    DateTime? nextChargeAt;
    final rawNext = d['nextChargeAt'];
    if (rawNext is Timestamp) nextChargeAt = rawNext.toDate();

    return SubscriptionStatus(
      status: status,
      planId: planId,
      trialEndsAt: trialEndsAt,
      nextChargeAt: nextChargeAt,
    );
  }

  bool isTrialExpired(SubscriptionStatus? s) {
    if (s == null) return false;
    if (s.status == 'ACTIVE') return false;
    final end = s.trialEndsAt ?? s.nextChargeAt;
    if (end == null) return false;
    final graceEnd = end.add(const Duration(days: AppConstants.subscriptionGraceDays));
    return DateTime.now().isAfter(graceEnd);
  }
}
