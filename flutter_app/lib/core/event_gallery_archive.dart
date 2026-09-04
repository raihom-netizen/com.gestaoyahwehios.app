import 'package:cloud_firestore/cloud_firestore.dart';

DateTime? eventArchiveBaseDate(Map<String, dynamic> data) {
  final endRaw = data['endAt'];
  if (endRaw is Timestamp) return endRaw.toDate();
  final startRaw = data['startAt'];
  if (startRaw is Timestamp) return startRaw.toDate();
  return null;
}

/// Evento sem validade e evento explicitamente marcado para arquivo sao
/// permanentes. O fallback sem [validUntil] mantem compatibilidade com os
/// documentos antigos, que exibiam 'Permanente' no formulario mas gravavam
/// galleryPermanent como false.
bool eventIsGalleryPermanent(Map<String, dynamic> data) {
  if ((data['type'] ?? '').toString() != 'evento') return false;
  if (data['galleryPermanent'] == true) return true;
  return data['validUntil'] is! Timestamp;
}

/// Temporarios sao eliminados somente 24 horas depois da validade.
bool eventTemporaryRetentionExpired(Map<String, dynamic> data, DateTime now) {
  if ((data['type'] ?? '').toString() != 'evento') return false;
  if (eventIsGalleryPermanent(data)) return false;
  final validUntil = data['validUntil'];
  if (validUntil is! Timestamp) return false;
  return !now.isBefore(validUntil.toDate().add(const Duration(days: 1)));
}

bool eventShouldMoveToGalleryArchive(Map<String, dynamic> data, DateTime now) {
  if ((data['type'] ?? '').toString() != 'evento') return false;
  if (!eventIsGalleryPermanent(data)) return false;
  final base = eventArchiveBaseDate(data);
  if (base == null) return false;
  return now.isAfter(base.add(const Duration(days: 1)));
}
