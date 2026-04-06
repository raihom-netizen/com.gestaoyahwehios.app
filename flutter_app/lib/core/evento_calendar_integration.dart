import 'package:add_2_calendar/add_2_calendar.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import 'package:gestao_yahweh/core/app_constants.dart';
import 'package:gestao_yahweh/ui/web/open_external_url.dart';

String _mapsLineForLocation(String location, {double? lat, double? lng}) {
  final loc = location.trim();
  final maps = AppConstants.mapsShortUrl(
    lat: lat,
    lng: lng,
    address: loc.isNotEmpty ? loc : null,
  );
  if (maps.isEmpty) return '';
  return '\nMapa: $maps';
}

/// Integração com a agenda do telemóvel após confirmar presença num evento.
class EventoCalendarIntegration {
  EventoCalendarIntegration._();

  static DateTime _defaultEnd(DateTime start) =>
      start.add(const Duration(hours: 2));

  static String _googleCalendarUtcCompact(DateTime d) {
    final u = d.toUtc();
    String two(int n) => n.toString().padLeft(2, '0');
    final y = u.year.toString().padLeft(4, '0');
    return '$y${two(u.month)}${two(u.day)}T${two(u.hour)}${two(u.minute)}${two(u.second)}Z';
  }

  /// Web: abre o Google Calendar numa nova aba. Mobile: mesma lógica que [addEventToDeviceCalendar].
  static Uri googleCalendarTemplateUri({
    required String title,
    required DateTime start,
    required DateTime end,
    String details = '',
    String location = '',
  }) {
    final dates =
        '${_googleCalendarUtcCompact(start)}/${_googleCalendarUtcCompact(end)}';
    return Uri(
      scheme: 'https',
      host: 'www.google.com',
      path: '/calendar/render',
      queryParameters: {
        'action': 'TEMPLATE',
        'text': title,
        'dates': dates,
        'details': details,
        'location': location,
      },
    );
  }

  /// Inclui web (template Google Calendar) e nativo ([addEventToDeviceCalendar]).
  static Future<bool> addToCalendarAdaptive({
    required String title,
    required DateTime start,
    DateTime? end,
    String location = '',
    String description = '',
    double? locationLat,
    double? locationLng,
  }) async {
    final t = title.trim();
    if (t.isEmpty) return false;
    var fin = end ?? _defaultEnd(start);
    if (!fin.isAfter(start)) {
      fin = start.add(const Duration(hours: 2));
    }
    final locText = location.trim();
    final desc = [
      description.trim(),
      _mapsLineForLocation(locText, lat: locationLat, lng: locationLng),
    ].where((s) => s.isNotEmpty).join('\n');

    if (kIsWeb) {
      final uri = googleCalendarTemplateUri(
        title: t,
        start: start,
        end: fin,
        details: desc,
        location: locText,
      );
      return openExternalApplicationUrl(uri);
    }

    return addEventToDeviceCalendar(
      title: t,
      start: start,
      end: fin,
      location: locText,
      description: description.trim(),
      locationLat: locationLat,
      locationLng: locationLng,
    );
  }

  /// Abre o fluxo nativo (Google Calendar / Apple Calendar) com lembrete ~1h antes.
  static Future<bool> addEventToDeviceCalendar({
    required String title,
    required DateTime start,
    DateTime? end,
    String location = '',
    String description = '',
    double? locationLat,
    double? locationLng,
  }) async {
    if (kIsWeb) return false;
    final t = title.trim();
    if (t.isEmpty) return false;
    var fin = end ?? _defaultEnd(start);
    if (!fin.isAfter(start)) {
      fin = start.add(const Duration(hours: 2));
    }
    final locText = location.trim();
    final desc = [
      description.trim(),
      _mapsLineForLocation(locText, lat: locationLat, lng: locationLng),
    ].where((s) => s.isNotEmpty).join('\n');

    final event = Event(
      title: t,
      description: desc,
      location: locText,
      startDate: start,
      endDate: fin,
      iosParams: const IOSParams(
        reminder: Duration(hours: 1),
      ),
      androidParams: const AndroidParams(
        emailInvites: [],
      ),
    );
    return Add2Calendar.addEvent2Cal(event);
  }

  static String buildDescriptionWithPublicLink({
    required String body,
    required String churchSlug,
  }) {
    final link = churchSlug.trim().isEmpty
        ? AppConstants.publicWebBaseUrl
        : AppConstants.publicChurchHomeUrl(churchSlug.trim());
    final b = body.replaceAll(RegExp(r'\s+'), ' ').trim();
    final buf = StringBuffer();
    if (b.isNotEmpty) {
      buf.writeln(b);
      buf.writeln();
    }
    buf.writeln('Site da igreja: $link');
    return buf.toString().trim();
  }

  /// Após confirmar presença, pergunta se deseja gravar na agenda.
  static Future<void> offerAddToCalendarDialog(
    BuildContext context, {
    required String eventTitle,
    required DateTime start,
    DateTime? end,
    required String location,
    required String description,
    double? locationLat,
    double? locationLng,
  }) async {
    if (kIsWeb || !context.mounted) return;
    final add = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Adicionar à agenda?'),
        content: Text(
          'Quer guardar "${eventTitle.trim().isEmpty ? 'Evento' : eventTitle.trim()}" no calendário do telemóvel? '
          'Pode receber um lembrete cerca de 1 hora antes.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Agora não'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Adicionar'),
          ),
        ],
      ),
    );
    if (add != true || !context.mounted) return;
    final ok = await addEventToDeviceCalendar(
      title: eventTitle,
      start: start,
      end: end,
      location: location,
      description: description,
      locationLat: locationLat,
      locationLng: locationLng,
    );
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          ok
              ? 'Abra o calendário para concluir, se o sistema pedir.'
              : 'Não foi possível abrir o calendário neste dispositivo.',
        ),
      ),
    );
  }
}
