import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import 'package:gestao_yahweh/models/user_profile.dart';

class Goal52WeeksSummaryPanel extends StatelessWidget {
  const Goal52WeeksSummaryPanel({
    super.key,
    required this.target,
    required this.deposited,
    required this.paidWeeks,
    required this.currentWeek,
    required this.gradient,
    this.compact = false,
  });

  final double target;
  final double deposited;
  final int paidWeeks;
  final int currentWeek;
  final List<Color> gradient;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(compact ? 10 : 14),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: gradient),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            'Sem. $currentWeek',
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800),
          ),
          Text(
            '$paidWeeks sem. ok',
            style: const TextStyle(color: Colors.white70, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

class Goal52WeeksPdfButton extends StatelessWidget {
  const Goal52WeeksPdfButton({
    super.key,
    required this.onPressed,
    required this.label,
  });

  final VoidCallback onPressed;
  final String label;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: onPressed,
      icon: const Icon(Icons.picture_as_pdf_rounded, size: 18),
      label: Text(label),
    );
  }
}

Future<void> exportFiftyTwoWeeksGoalPdf({
  required BuildContext context,
  required QueryDocumentSnapshot<Map<String, dynamic>> goalDoc,
}) async {}

Future<void> showFiftyTwoWeeksScheduleSheet({
  required BuildContext context,
  required QueryDocumentSnapshot<Map<String, dynamic>> goalDoc,
  required UserProfile profile,
  required String uid,
  bool depositMode = false,
}) async {}

Future<void> showRegistrarDepositoDialog({
  required BuildContext context,
  required DocumentReference<Map<String, dynamic>> goalRef,
  required String goalId,
  required String goalTitle,
  required String uid,
  required UserProfile profile,
}) async {}

Future<void> showGoalContributionsSheet({
  required BuildContext context,
  required QueryDocumentSnapshot<Map<String, dynamic>> goalDoc,
  required String goalTitle,
  required String uid,
  required UserProfile profile,
}) async {}
