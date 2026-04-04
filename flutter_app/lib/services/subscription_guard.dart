import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:gestao_yahweh/core/app_constants.dart';

class SubscriptionGuardState {
  final String statusAssinatura;
  final DateTime? dataVencimento;
  final DateTime? dataBloqueio;
  final bool isFree;
  final bool adminBlocked;
  final bool blocked;
  final bool inGrace;
  final int graceDaysLeft;

  const SubscriptionGuardState({
    required this.statusAssinatura,
    required this.dataVencimento,
    required this.dataBloqueio,
    required this.isFree,
    required this.adminBlocked,
    required this.blocked,
    required this.inGrace,
    required this.graceDaysLeft,
  });

  String get masterBadgeLabel {
    if (isFree) return 'FREE';
    if (adminBlocked || blocked) return 'Bloqueada';
    if (inGrace) return 'Em carência';
    if (statusAssinatura == 'trialing') return 'Trial';
    if (statusAssinatura == 'overdue') return 'Vencida';
    return 'Ativa';
  }
}

class SubscriptionGuard {
  SubscriptionGuard._();

  static SubscriptionGuardState evaluate({
    required Map<String, dynamic>? church,
    Map<String, dynamic>? subscription,
    DateTime? now,
  }) {
    final current = now ?? DateTime.now();
    final c = church ?? const <String, dynamic>{};
    final lic = c['license'] is Map ? Map<String, dynamic>.from(c['license'] as Map) : const <String, dynamic>{};

    final isFree = c['plano']?.toString().toLowerCase() == 'free' || lic['isFree'] == true;
    final adminBlocked = c['adminBlocked'] == true || lic['adminBlocked'] == true;
    /// Master / documento: igreja desligada no ecossistema (site público + bloqueio alinhado ao painel).
    final ecosystemOff = adminBlocked ||
        lic['active'] == false ||
        c['ativa'] == false ||
        c['masterInactive'] == true ||
        c['siteDisabled'] == true ||
        (c['status'] ?? '').toString().toLowerCase() == 'inativa';

    final rawStatus = (c['status_assinatura'] ?? subscription?['status_assinatura'] ?? subscription?['status'] ?? 'active')
        .toString()
        .toLowerCase()
        .trim();
    final normalizedStatus = _normalizeStatus(rawStatus);

    final dataVencimento = _pickDate(
      c['data_vencimento'],
      c['licenseExpiresAt'],
      c['trialEndsAt'],
      c['billing'] is Map ? (c['billing'] as Map)['nextChargeAt'] : null,
      subscription?['data_vencimento'],
      subscription?['nextChargeAt'],
      subscription?['trialEndsAt'],
      subscription?['currentPeriodEnd'],
    );

    final dataBloqueio = _pickDate(
      c['data_bloqueio'],
      subscription?['data_bloqueio'],
    ) ??
        (dataVencimento != null ? dataVencimento.add(const Duration(days: AppConstants.subscriptionGraceDays)) : null);

    if (isFree) {
      return SubscriptionGuardState(
        statusAssinatura: 'active',
        dataVencimento: dataVencimento,
        dataBloqueio: dataBloqueio,
        isFree: true,
        adminBlocked: adminBlocked,
        blocked: ecosystemOff,
        inGrace: false,
        graceDaysLeft: 0,
      );
    }

    final suspendedByStatus = normalizedStatus == 'suspended';
    final blockedByDate = dataBloqueio != null && current.isAfter(dataBloqueio);
    final blocked = ecosystemOff || suspendedByStatus || blockedByDate;

    final inGrace = !blocked &&
        dataVencimento != null &&
        current.isAfter(dataVencimento) &&
        (dataBloqueio == null || current.isBefore(dataBloqueio) || current.isAtSameMomentAs(dataBloqueio));

    final graceDaysLeft = inGrace && dataBloqueio != null
        ? dataBloqueio.difference(current).inDays.clamp(0, AppConstants.subscriptionGraceDays)
        : 0;

    return SubscriptionGuardState(
      statusAssinatura: normalizedStatus,
      dataVencimento: dataVencimento,
      dataBloqueio: dataBloqueio,
      isFree: false,
      adminBlocked: adminBlocked,
      blocked: blocked,
      inGrace: inGrace,
      graceDaysLeft: graceDaysLeft,
    );
  }

  static Map<String, dynamic> normalizedChurchFields(SubscriptionGuardState s) {
    return {
      'status_assinatura': s.blocked ? 'suspended' : (s.inGrace ? 'overdue' : s.statusAssinatura),
      if (s.dataVencimento != null) 'data_vencimento': Timestamp.fromDate(s.dataVencimento!),
      if (s.dataBloqueio != null) 'data_bloqueio': Timestamp.fromDate(s.dataBloqueio!),
    };
  }

  static String _normalizeStatus(String v) {
    if (v == 'trial') return 'trialing';
    if (v == 'past_due' || v == 'vencida') return 'overdue';
    if (v == 'blocked' || v == 'bloqueada') return 'suspended';
    if (v == 'paid' || v == 'pago' || v == 'approved' || v == 'accredited') return 'active';
    if (v != 'active' && v != 'trialing' && v != 'overdue' && v != 'suspended') return 'active';
    return v;
  }

  static DateTime? _pickDate([Object? a, Object? b, Object? c, Object? d, Object? e, Object? f, Object? g, Object? h]) {
    for (final raw in [a, b, c, d, e, f, g, h]) {
      final dt = _toDate(raw);
      if (dt != null) return dt;
    }
    return null;
  }

  static DateTime? _toDate(Object? raw) {
    if (raw == null) return null;
    if (raw is Timestamp) return raw.toDate();
    if (raw is DateTime) return raw;
    if (raw is Map) {
      final sec = raw['seconds'] ?? raw['_seconds'];
      if (sec is num) return DateTime.fromMillisecondsSinceEpoch(sec.toInt() * 1000);
    }
    return DateTime.tryParse(raw.toString());
  }
}
