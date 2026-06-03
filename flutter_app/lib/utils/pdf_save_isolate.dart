import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:pdf/widgets.dart' as pw;

Uint8List _wrapPdfBytes(List<int> raw) => Uint8List.fromList(raw);

/// [pw.Document.save] fora da UI thread (mobile/desktop). Web mantém na main.
Future<Uint8List> savePdfDocumentOffUiThread(pw.Document doc) async {
  final raw = await doc.save();
  if (kIsWeb) return Uint8List.fromList(raw);
  return compute(_wrapPdfBytes, raw);
}
