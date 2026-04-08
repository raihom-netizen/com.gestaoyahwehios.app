import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_linkify/flutter_linkify.dart';
import 'package:gestao_yahweh/ui/theme_clean_premium.dart';
import 'package:gestao_yahweh/ui/widgets/church_panel_ui_helpers.dart';

/// Aviso global (`config/global_announcement`) no painel da igreja e master.
///
/// - [revision] (incrementado ao salvar) + [dismissedGlobalAnnouncementRev] no `users/{uid}`.
/// - Legado: sem [revision], usa [updatedAt] como antes.
/// - [validUntil]: o dia escolhido conta como **válido até o fim desse dia** (corrigido).
/// - Campos opcionais: [title], [kind], botões [primaryButtonUrl] / [secondaryButtonUrl].
/// - Links `https://` no texto ficam clicáveis ([Linkify] + [openHttpsUrlInBrowser]).
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

  static String _normalizeKind(dynamic v) {
    final s = (v ?? 'info').toString().trim().toLowerCase();
    if (s == 'maintenance' || s == 'manutencao' || s == 'manutenção') {
      return 'maintenance';
    }
    if (s == 'promotion' || s == 'promocao' || s == 'promoção') {
      return 'promotion';
    }
    return 'info';
  }

  static ({Color c1, Color c2, IconData icon, String defaultTitle}) _styleForKind(
      String kind) {
    switch (kind) {
      case 'maintenance':
        return (
          c1: const Color(0xFFE65100),
          c2: const Color(0xFFFF9800),
          icon: Icons.build_circle_rounded,
          defaultTitle: 'Manutenção',
        );
      case 'promotion':
        return (
          c1: const Color(0xFF6A1B9A),
          c2: const Color(0xFFAB47BC),
          icon: Icons.local_offer_rounded,
          defaultTitle: 'Promoção',
        );
      default:
        return (
          c1: ThemeCleanPremium.primary,
          c2: const Color(0xFF42A5F5),
          icon: Icons.notifications_active_rounded,
          defaultTitle: 'Aviso do sistema',
        );
    }
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

    final kind = _normalizeKind(ann['kind']);
    final title = (ann['title'] ?? '').toString().trim();
    final primaryUrl = (ann['primaryButtonUrl'] ?? '').toString().trim();
    final primaryLabel = (ann['primaryButtonLabel'] ?? '').toString().trim();
    final secondaryUrl = (ann['secondaryButtonUrl'] ?? '').toString().trim();
    final secondaryLabel = (ann['secondaryButtonLabel'] ?? '').toString().trim();

    await _showAnnouncementDialog(
      context,
      message: message,
      revision: revision,
      updatedAt: updatedAt,
      uid: user.uid,
      kind: kind,
      title: title,
      primaryUrl: primaryUrl,
      primaryLabel: primaryLabel,
      secondaryUrl: secondaryUrl,
      secondaryLabel: secondaryLabel,
    );
  }

  Future<void> _showAnnouncementDialog(
    BuildContext context, {
    required String message,
    required int revision,
    required Timestamp? updatedAt,
    required String uid,
    required String kind,
    required String title,
    required String primaryUrl,
    required String primaryLabel,
    required String secondaryUrl,
    required String secondaryLabel,
  }) async {
    final style = _styleForKind(kind);
    final displayTitle =
        title.isEmpty ? style.defaultTitle : title;

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        final maxH = MediaQuery.sizeOf(ctx).height * 0.5;
        return Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(22),
          ),
          insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
          clipBehavior: Clip.antiAlias,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.fromLTRB(20, 22, 20, 18),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [style.c1, style.c2],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(style.icon, color: Colors.white, size: 34),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Text(
                          displayTitle,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                            height: 1.2,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                ConstrainedBox(
                  constraints: BoxConstraints(maxHeight: maxH),
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
                    child: SelectableLinkify(
                      text: message,
                      onOpen: (link) =>
                          openHttpsUrlInBrowser(ctx, link.url),
                      style: TextStyle(
                        fontSize: 15,
                        height: 1.55,
                        color: ThemeCleanPremium.onSurface,
                      ),
                      linkStyle: TextStyle(
                        color: ThemeCleanPremium.primary,
                        fontWeight: FontWeight.w700,
                        decoration: TextDecoration.underline,
                        decorationColor: ThemeCleanPremium.primary,
                      ),
                      options: const LinkifyOptions(humanize: false),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (primaryUrl.isNotEmpty) ...[
                        FilledButton.icon(
                          onPressed: () =>
                              openHttpsUrlInBrowser(ctx, primaryUrl),
                          icon: const Icon(Icons.open_in_new_rounded, size: 20),
                          label: Text(
                            primaryLabel.isEmpty
                                ? 'Abrir link'
                                : primaryLabel,
                          ),
                          style: FilledButton.styleFrom(
                            backgroundColor: ThemeCleanPremium.primary,
                            padding: const EdgeInsets.symmetric(
                                vertical: 14, horizontal: 16),
                          ),
                        ),
                        const SizedBox(height: 8),
                      ],
                      if (secondaryUrl.isNotEmpty) ...[
                        OutlinedButton.icon(
                          onPressed: () =>
                              openHttpsUrlInBrowser(ctx, secondaryUrl),
                          icon: const Icon(Icons.link_rounded, size: 20),
                          label: Text(
                            secondaryLabel.isEmpty
                                ? 'Segundo link'
                                : secondaryLabel,
                          ),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: ThemeCleanPremium.primary,
                            side: BorderSide(
                              color: ThemeCleanPremium.primary.withOpacity(0.6),
                            ),
                            padding: const EdgeInsets.symmetric(
                                vertical: 12, horizontal: 16),
                          ),
                        ),
                        const SizedBox(height: 8),
                      ],
                    ],
                  ),
                ),
                Padding(
                  padding:
                      const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  child: FilledButton(
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
                      backgroundColor: ThemeCleanPremium.onSurface
                          .withOpacity(0.88),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    child: const Text('Entendi'),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}
