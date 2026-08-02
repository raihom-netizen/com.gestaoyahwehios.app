import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

/// Como o usuário quer receber lembretes de agenda por tipo.
enum AgendaTypeDeliveryMode {
  /// Push (celular/app) + e-mail quando o e-mail global estiver ligado.
  both,

  /// Apenas notificação no aparelho / push FCM.
  pushOnly,

  /// Apenas e-mail (servidor); sem agendar push local.
  emailOnly,
}

const String kDeliveryFirestoreBoth = 'both';
const String kDeliveryFirestorePushOnly = 'push_only';
const String kDeliveryFirestoreEmailOnly = 'email_only';

AgendaTypeDeliveryMode agendaTypeDeliveryModeFromFirestore(dynamic raw) {
  final s = (raw ?? '').toString().trim().toLowerCase();
  if (s.isEmpty) return AgendaTypeDeliveryMode.both;
  if (s == kDeliveryFirestorePushOnly || s == 'push') {
    return AgendaTypeDeliveryMode.pushOnly;
  }
  if (s == kDeliveryFirestoreEmailOnly || s == 'email') {
    return AgendaTypeDeliveryMode.emailOnly;
  }
  return AgendaTypeDeliveryMode.both;
}

/// Audiências: padrão celular + e-mail (evento sério).
AgendaTypeDeliveryMode defaultAudienciaDeliveryFromFirestore(dynamic raw) {
  if (raw == null) return AgendaTypeDeliveryMode.both;
  return agendaTypeDeliveryModeFromFirestore(raw);
}

String agendaTypeDeliveryModeToFirestore(AgendaTypeDeliveryMode mode) {
  switch (mode) {
    case AgendaTypeDeliveryMode.pushOnly:
      return kDeliveryFirestorePushOnly;
    case AgendaTypeDeliveryMode.emailOnly:
      return kDeliveryFirestoreEmailOnly;
    case AgendaTypeDeliveryMode.both:
      return kDeliveryFirestoreBoth;
  }
}

/// Lembretes de agenda no aparelho (flutter_local_notifications).
/// Com `true`, o envio principal passa a ser servidor (FCM/e-mail),
/// garantindo popup também com app fechado.
const bool kAgendaNotificationsServerPushOnly = true;

/// iOS: servidor (FCM/APNs) + backup local — evita zero notificação se token/fila falhar.
bool get agendaHybridIosLocalBackupEnabled {
  if (kIsWeb) return false;
  return defaultTargetPlatform == TargetPlatform.iOS;
}

/// Android/iOS/Web com server-push-only não agenda local — fila `agendaAlerts` + FCM.
bool agendaSkipsLocalSchedulingBecauseServerPushOnly() {
  if (!kAgendaNotificationsServerPushOnly) return false;
  return !agendaHybridIosLocalBackupEnabled;
}

/// Push local / FCM permitido para este tipo.
bool agendaAllowsLocalOrPushDelivery(AgendaTypeDeliveryMode mode) {
  return mode != AgendaTypeDeliveryMode.emailOnly;
}

/// Agendamento local no SO (flutter_local_notifications / timer Web).
bool agendaAllowsLocalScheduling(AgendaTypeDeliveryMode mode) {
  if (agendaSkipsLocalSchedulingBecauseServerPushOnly()) return false;
  return agendaAllowsLocalOrPushDelivery(mode);
}

/// E-mail permitido para este tipo (ainda exige e-mail global ligado).
bool agendaAllowsEmailDelivery(AgendaTypeDeliveryMode mode) {
  return mode != AgendaTypeDeliveryMode.pushOnly;
}

Map<String, dynamic> agendaDeliveryModesToFirestore({
  required AgendaTypeDeliveryMode escala,
  required AgendaTypeDeliveryMode compromisso,
  required AgendaTypeDeliveryMode audiencia,
  AgendaTypeDeliveryMode? financeiro,
}) {
  return {
    'deliveryEscala': agendaTypeDeliveryModeToFirestore(escala),
    'deliveryCompromisso': agendaTypeDeliveryModeToFirestore(compromisso),
    'deliveryAudiencia': agendaTypeDeliveryModeToFirestore(audiencia),
    if (financeiro != null)
      'deliveryFinanceiro': agendaTypeDeliveryModeToFirestore(financeiro),
  };
}
