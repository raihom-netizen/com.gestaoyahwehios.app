import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:gestao_yahweh/core/event_gallery_archive.dart';

/// `true` quando a **data/hora** do evento (início, fim do dia ou [endAt]) já passou,
/// independentemente do modo permanente / 1 dia de graça.
/// Nome do identificador em ASCII (dart2js exige: sem acentos em identificadores).
bool noticiaEventoEspecialNaoMaisNoDestaquePorDataHora(
  Map<String, dynamic> data,
  DateTime now,
) {
  if ((data['type'] ?? '').toString() != 'evento') return false;
  final st = (data['startAt'] is Timestamp)
      ? (data['startAt'] as Timestamp).toDate()
      : null;
  if (st == null) {
    // Sem [startAt]: só "permanentes" permanecem em destaque (Mural + painel).
    return data['galleryPermanent'] != true;
  }
  if (data['endAt'] is Timestamp) {
    final en = (data['endAt'] as Timestamp).toDate();
    return now.isAfter(en);
  }
  final fimDia = DateTime(st.year, st.month, st.day, 23, 59, 59, 999);
  return now.isAfter(fimDia);
}

/// Deixa de constar no **Feed** e deve ir para a **Galeria** (Mural) — combina
/// o arquivo de permanente ([eventShouldMoveToGalleryArchive]) com data passada.
bool noticiaEventoEspecialCaiuDoFeedParaGaleria(
  Map<String, dynamic> data,
  DateTime now,
) {
  if (eventShouldMoveToGalleryArchive(data, now)) return true;
  return noticiaEventoEspecialNaoMaisNoDestaquePorDataHora(data, now);
}
