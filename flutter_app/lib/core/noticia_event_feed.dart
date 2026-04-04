import 'package:cloud_firestore/cloud_firestore.dart';

/// Eventos em [noticias] com `type == evento`: o **Feed** e o mural público devem mostrar só
/// **eventos especiais** (cultos de campanha, datas comemorativas, etc.).
///
/// **Fora do Feed** (não misturar):
/// - Gerados pela Cloud Function antiga (`createdByUid: system`, id `evt_...`)
/// - Gerados pelo botão "Gerar eventos futuros" nos Eventos Fixos (`generated: true` / `templateId`)
bool noticiaEventoEhRotinaOuGeradoAutomatico(Map<String, dynamic> data, String docId) {
  final g = data['generated'];
  if (g == true) return true;
  if (g != null && g.toString().trim().toLowerCase() == 'true') return true;

  final tid = (data['templateId'] ?? '').toString().trim();
  if (tid.isNotEmpty) return true;

  final uid = (data['createdByUid'] ?? '').toString().trim();
  if (uid == 'system') return true;

  if (docId.startsWith('evt_')) return true;

  return false;
}

/// `true` se o documento [noticias] deve aparecer na aba **Feed** (evento especial).
bool noticiaDocEhEventoSpecialFeed(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
  if ((doc.data()['type'] ?? '').toString() != 'evento') return false;
  return !noticiaEventoEhRotinaOuGeradoAutomatico(doc.data(), doc.id);
}

/// Para o mural (aba Eventos): mesma regra — só eventos especiais.
bool noticiaDocIncluirNoMuralEventos(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
  return noticiaDocEhEventoSpecialFeed(doc);
}
