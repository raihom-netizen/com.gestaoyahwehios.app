import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:gestao_yahweh/ui/theme_clean_premium.dart';

/// Aviso global (`config/global_announcement`) no painel da igreja e master.
///
/// - [revision] (incrementado ao salvar) + [dismissedGlobalAnnouncementRev] no `users/{uid}`.
/// - Legado: sem [revision], usa [updatedAt] como antes.
/// - [validUntil]: o dia escolhido conta como **válido até o fim desse dia** (corrigido).
/// - Ouve o documento em tempo real para novos avisos na sessão.
class GlobalAnnouncementOverlay extends StatefulWidget {
  final Widget child;

  const GlobalAnnouncementOverlay({super.key, required this.child});

  @override
  State<GlobalAnnouncementOverlay> createState() =>
      _GlobalAnnouncementOverlayState();
}

class _GlobalAnnouncementOverlayState extends State<GlobalAnnouncementOverlay> {
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _annSub;
  int? _lastShownRevision;

  @override
  void initState() {
    super.initState();
    _annSub = FirebaseFirestore.instance
        .doc('config/global_announcement')
        .snapshots()
        .listen(_onAnnouncementSnap, onError: (_) {});
  }

  @override
  void dispose() {
    _annSub?.cancel();
    super.dispose();
  }

  /// Dia inclusivo: válido até 23:59:59 do calendário escolhido.
  static bool _validUntilExpired(Timestamp? validUntil) {
    if (validUntil == null) return false;
    final d = validUntil.toDate();
    final lastDay = DateTime(d.year, d.month, d.day);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    return today.isAfter(lastDay);
  }

  static int _revisionOf(Map<String, dynamic> ann) {
    final r = ann['revision'];
    if (r is num) return r.toInt();
    return 0;
  }

  Future<void> _onAnnouncementSnap(
      DocumentSnapshot<Map<String, dynamic>> snap) async {
    if (!mounted) return;
    if (!snap.exists || snap.data() == null) return;
    final ann = snap.data()!;
    if (ann['active'] != true) return;
    if (_validUntilExpired(ann['validUntil'] as Timestamp?)) return;

    final message = (ann['message'] ?? '').toString().trim();
    if (message.isEmpty) return;

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final revision = _revisionOf(ann);
    final updatedAt = ann['updatedAt'] as Timestamp?;

    DocumentSnapshot<Map<String, dynamic>>? userSnap;
    try {
      userSnap =
          await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
    } catch (_) {
      return;
    }

    final uData = userSnap.data();
    final dismissedRev = uData?['dismissedGlobalAnnouncementRev'];
    if (revision > 0 &&
        dismissedRev is num &&
        dismissedRev.toInt() >= revision) {
      return;
    }

    if (revision == 0) {
      final dh = uData?['dismissedGlobalAnnouncementMsgHash'];
      if (dh is num && dh.toInt() == message.hashCode) return;
      if (updatedAt != null) {
        final dismissedAt = uData?['dismissedGlobalAnnouncementAt'];
        if (dismissedAt is Timestamp &&
            dismissedAt.compareTo(updatedAt) >= 0) {
          return;
        }
      }
    }

    if (revision > 0 && _lastShownRevision == revision) return;
    if (revision == 0 && _lastShownRevision == message.hashCode) return;

    if (!mounted) return;
    if (revision > 0) {
      _lastShownRevision = revision;
    } else {
      _lastShownRevision = message.hashCode;
    }

    await _showDialog(
      context,
      message: message,
      revision: revision,
      updatedAt: updatedAt,
      uid: user.uid,
    );
  }

  Future<void> _showDialog(
    BuildContext context, {
    required String message,
    required int revision,
    required Timestamp? updatedAt,
    required String uid,
  }) async {
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusLg)),
        title: Row(
          children: [
            Icon(Icons.info_outline_rounded,
                color: ThemeCleanPremium.primary, size: 28),
            const SizedBox(width: 12),
            const Expanded(child: Text('Aviso do sistema')),
          ],
        ),
        content: SingleChildScrollView(
          child: Text(message,
              style: const TextStyle(fontSize: 15, height: 1.5)),
        ),
        actions: [
          FilledButton(
            onPressed: () async {
              Navigator.of(ctx).pop();
              final payload = <String, dynamic>{};
              if (revision > 0) {
                payload['dismissedGlobalAnnouncementRev'] = revision;
                if (updatedAt != null) {
                  payload['dismissedGlobalAnnouncementAt'] = updatedAt;
                }
              } else if (updatedAt != null) {
                payload['dismissedGlobalAnnouncementAt'] = updatedAt;
              } else {
                payload['dismissedGlobalAnnouncementMsgHash'] =
                    message.hashCode;
              }
              try {
                await FirebaseFirestore.instance
                    .collection('users')
                    .doc(uid)
                    .set(payload, SetOptions(merge: true));
              } catch (_) {}
            },
            style: FilledButton.styleFrom(
                backgroundColor: ThemeCleanPremium.primary),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}
