import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:gestao_yahweh/core/app_constants.dart';
import 'package:gestao_yahweh/core/church_tenant_posts_collections.dart';
import 'package:gestao_yahweh/core/evento_calendar_integration.dart';
import 'package:gestao_yahweh/ui/theme_clean_premium.dart';
import 'package:gestao_yahweh/ui/web/open_external_url.dart';

bool _churchPublicEventoStillActive(Map<String, dynamic> m, DateTime now) {
  final v = m['validUntil'];
  if (v is Timestamp && !v.toDate().isAfter(now)) return false;
  return true;
}

/// Próximo evento público em [noticias] com data/hora — base do bloco «Próximo culto».
class ChurchProximoCultoSnapshot {
  final String title;
  final DateTime start;
  final DateTime end;
  final String locationLine;
  final String description;
  final String noticiaId;

  const ChurchProximoCultoSnapshot({
    required this.title,
    required this.start,
    required this.end,
    required this.locationLine,
    required this.description,
    required this.noticiaId,
  });
}

Future<ChurchProximoCultoSnapshot?> fetchChurchProximoCultoSnapshot(
  String igrejaId,
) async {
  final tid = igrejaId.trim();
  if (tid.isEmpty) return null;
  final now = DateTime.now();
  try {
    final snap = await FirebaseFirestore.instance
        .collection('igrejas')
        .doc(tid)
        .collection(ChurchTenantPostsCollections.noticias)
        .where('type', isEqualTo: 'evento')
        .where('startAt', isGreaterThanOrEqualTo: Timestamp.fromDate(now))
        .orderBy('startAt')
        .limit(24)
        .get();

    for (final d in snap.docs) {
      final m = d.data();
      if (m['publicSite'] == false) continue;
      if (!_churchPublicEventoStillActive(m, now)) continue;
      final st = m['startAt'];
      if (st is! Timestamp) continue;
      final start = st.toDate();
      DateTime end = start.add(const Duration(hours: 2));
      final en = m['endAt'];
      if (en is Timestamp) {
        final e = en.toDate();
        if (e.isAfter(start)) end = e;
      }
      final title = (m['title'] ?? m['titulo'] ?? 'Culto').toString().trim();
      if (title.isEmpty) continue;
      final loc = (m['location'] ?? m['local'] ?? '').toString().trim();
      final body = (m['text'] ?? m['body'] ?? m['descricao'] ?? '')
          .toString()
          .trim();
      return ChurchProximoCultoSnapshot(
        title: title,
        start: start,
        end: end,
        locationLine: loc,
        description: body,
        noticiaId: d.id,
      );
    }
  } catch (_) {}
  return null;
}

String _formatPortugueseDateTime(DateTime dt) {
  const wd = [
    'Segunda-feira',
    'Terça-feira',
    'Quarta-feira',
    'Quinta-feira',
    'Sexta-feira',
    'Sábado',
    'Domingo',
  ];
  final w = dt.weekday >= 1 && dt.weekday <= 7 ? wd[dt.weekday - 1] : '';
  String two(int n) => n.toString().padLeft(2, '0');
  return '$w, ${two(dt.day)}/${two(dt.month)}/${dt.year} às ${two(dt.hour)}:${two(dt.minute)}';
}

/// Destaque explícito: data/hora, local, Maps e agenda (ecossistema [noticias] + cadastro da igreja).
class ChurchPublicProximoCultoCard extends StatelessWidget {
  final String igrejaId;
  final String churchName;
  final String churchSlug;
  final Color accentColor;
  final String enderecoIgreja;
  final double? latitude;
  final double? longitude;
  final String linkGoogleMaps;
  final String horariosText;

  const ChurchPublicProximoCultoCard({
    super.key,
    required this.igrejaId,
    required this.churchName,
    required this.churchSlug,
    required this.accentColor,
    required this.enderecoIgreja,
    required this.latitude,
    required this.longitude,
    required this.linkGoogleMaps,
    required this.horariosText,
  });

  Uri _mapsUri() {
    final g = linkGoogleMaps.trim();
    if (g.isNotEmpty) {
      final u = Uri.tryParse(g);
      if (u != null) return u;
    }
    if (latitude != null && longitude != null) {
      return Uri.parse('https://www.google.com/maps?q=$latitude,$longitude');
    }
    final q = Uri.encodeComponent(enderecoIgreja.trim());
    return Uri.parse('https://www.google.com/maps/search/?api=1&query=$q');
  }

  bool get _canOpenMaps =>
      linkGoogleMaps.trim().isNotEmpty ||
      (latitude != null && longitude != null) ||
      enderecoIgreja.trim().isNotEmpty;

  String _displayAddress(ChurchProximoCultoSnapshot? ev) {
    if (ev != null && ev.locationLine.isNotEmpty) return ev.locationLine;
    return enderecoIgreja.trim();
  }

  @override
  Widget build(BuildContext context) {
    final slug = churchSlug.trim();

    return FutureBuilder<ChurchProximoCultoSnapshot?>(
      future: fetchChurchProximoCultoSnapshot(igrejaId),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: LinearProgressIndicator(
                minHeight: 3,
                color: accentColor,
                backgroundColor: accentColor.withValues(alpha: 0.12),
              ),
            ),
          );
        }

        final evento = snap.data;
        final addressLine = _displayAddress(evento);
        final minTouch = Size(
          ThemeCleanPremium.minTouchTarget,
          ThemeCleanPremium.minTouchTarget,
        );

        final descForCal =
            EventoCalendarIntegration.buildDescriptionWithPublicLink(
          body: evento != null ? evento.description : horariosText,
          churchSlug: slug,
        );

        return Semantics(
          container: true,
          label: evento != null
              ? 'Próximo culto ou evento: ${evento.title}, ${_formatPortugueseDateTime(evento.start)}'
              : 'Informações de culto e local da igreja',
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  accentColor.withValues(alpha: 0.14),
                  Colors.white,
                ],
              ),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: accentColor.withValues(alpha: 0.28)),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x0C000000),
                  blurRadius: 18,
                  offset: Offset(0, 8),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: accentColor,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Text(
                        'PRÓXIMO CULTO / EVENTO',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.4,
                        ),
                      ),
                    ),
                    const Spacer(),
                    Icon(Icons.event_available_rounded,
                        color: accentColor, size: 26),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  evento != null
                      ? evento.title
                      : (churchName.trim().isEmpty ? 'Culto' : churchName.trim()),
                  style: TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.w900,
                    color: Colors.blueGrey.shade900,
                    height: 1.2,
                  ),
                ),
                if (evento != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    _formatPortugueseDateTime(evento.start),
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: Colors.blueGrey.shade800,
                    ),
                  ),
                ] else if (horariosText.trim().isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    horariosText.trim(),
                    style: TextStyle(
                      fontSize: 14,
                      height: 1.45,
                      color: Colors.grey.shade800,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
                if (addressLine.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.place_rounded,
                          size: 20, color: accentColor),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          addressLine,
                          style: TextStyle(
                            fontSize: 14,
                            height: 1.4,
                            color: Colors.grey.shade800,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 14),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    if (_canOpenMaps)
                      Semantics(
                        button: true,
                        label: 'Como chegar: abrir local no mapa',
                        child: OutlinedButton.icon(
                          onPressed: () async {
                            await openExternalApplicationUrl(_mapsUri());
                          },
                          icon: const Icon(Icons.directions_rounded, size: 20),
                          label: const Text('Como chegar'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: accentColor,
                            minimumSize: minTouch,
                            side: BorderSide(
                                color: accentColor.withValues(alpha: 0.5)),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                        ),
                      ),
                    if (evento != null)
                      Semantics(
                        button: true,
                        label: 'Adicionar este culto ou evento ao calendário',
                        child: FilledButton.icon(
                          onPressed: () async {
                            final ev = snap.data;
                            if (ev == null) return;
                            final calLoc = addressLine.isNotEmpty
                                ? addressLine
                                : enderecoIgreja.trim();
                            var desc = descForCal;
                            if (slug.isNotEmpty &&
                                ev.noticiaId.trim().isNotEmpty) {
                              final link = AppConstants.shareNoticiaSocialPreviewUrl(
                                slug,
                                ev.noticiaId,
                                igrejaId,
                              );
                              desc = '$desc\n\nPublicação: $link';
                            }
                            final ok = await EventoCalendarIntegration
                                .addToCalendarAdaptive(
                              title: ev.title,
                              start: ev.start,
                              end: ev.end,
                              location: calLoc,
                              description: desc,
                              locationLat: latitude,
                              locationLng: longitude,
                            );
                            if (!context.mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  ok
                                      ? 'Abra o calendário (ou a nova aba) para concluir.'
                                      : 'Não foi possível abrir o calendário neste dispositivo.',
                                ),
                              ),
                            );
                          },
                          icon:
                              const Icon(Icons.calendar_month_rounded, size: 20),
                          label: const Text('Adicionar ao calendário'),
                          style: FilledButton.styleFrom(
                            backgroundColor: accentColor,
                            foregroundColor: Colors.white,
                            minimumSize: minTouch,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
                if (evento == null && horariosText.trim().isEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      'Quando a igreja publicar um evento com data no mural (visível no site), '
                      'a data e o botão de calendário aparecem aqui automaticamente.',
                      style: TextStyle(
                        fontSize: 12,
                        height: 1.35,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}
