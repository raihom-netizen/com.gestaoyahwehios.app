import 'package:flutter/material.dart';
import 'dart:typed_data';

/// Stub mobile/desktop — viewer nativo em FinanceComprovanteViewerSheet.
Future<void> showFinanceComprovanteWebEmbed({
  required BuildContext context,
  required String url,
  required String fileName,
  required String mimeType,
}) async {}

Future<void> showFinanceComprovanteWebBytes({
  required BuildContext context,
  required Uint8List bytes,
  required String fileName,
  required String mimeType,
}) async {}
