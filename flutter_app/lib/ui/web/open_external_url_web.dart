// ignore_for_file: avoid_web_libraries_in_flutter

import 'dart:html' as html;

import 'package:url_launcher/url_launcher.dart';

Future<bool> openExternalApplicationUrl(Uri uri) async {
  try {
    final ok = await launchUrl(
      uri,
      mode: LaunchMode.externalApplication,
      webOnlyWindowName: '_blank',
    );
    if (ok) return true;
  } catch (_) {
    // fallback abaixo
  }
  html.window.open(uri.toString(), '_blank');
  return true;
}
