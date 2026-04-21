import 'package:cloud_firestore/cloud_firestore.dart';

DateTime? eventArchiveBaseDate(Map<String, dynamic> data) {
  final endRaw = data['endAt'];
  if (endRaw is Timestamp) return endRaw.toDate();
  final startRaw = data['startAt'];
  if (startRaw is Timestamp) return startRaw.toDate();
  return null;
}

bool eventShouldMoveToGalleryArchive(
  Map<String, dynamic> data,
  DateTime now,
) {
  if ((data['type'] ?? '').toString() != 'evento') return false;
  if (data['galleryPermanent'] != true) return false;
  final base = eventArchiveBaseDate(data);
  if (base == null) return false;
  return now.isAfter(base.add(const Duration(days: 1)));
}

