import 'dart:convert';

import 'package:crypto/crypto.dart';

/// Versionamento de artefatos gerados (carteirinha, certificado PDF).
abstract final class ChurchDocumentVersionService {
  ChurchDocumentVersionService._();

  static const String cardVersionField = 'cardVersion';
  static const String cardPathField = 'cardPdfPath';
  static const String pdfVersionField = 'pdfVersion';
  static const String pdfPathField = 'pdfPath';
  static const String fingerprintField = 'contentFingerprint';

  static String fingerprintFromMap(Map<String, dynamic> fields) {
    final keys = fields.keys.toList()..sort();
    final buf = StringBuffer();
    for (final k in keys) {
      buf.write('$k=${fields[k]};');
    }
    return sha256.convert(utf8.encode(buf.toString())).toString();
  }

  static bool shouldRegenerate({
    required Map<String, dynamic> doc,
    required String versionField,
    required String pathField,
    required String expectedFingerprint,
  }) {
    final path = (doc[pathField] ?? '').toString().trim();
    if (path.isEmpty) return true;
    final stored = (doc[fingerprintField] ?? '').toString().trim();
    if (stored.isEmpty || stored != expectedFingerprint) return true;
    final v = doc[versionField];
    if (v == null) return true;
    return false;
  }

  static Map<String, dynamic> afterGenerate({
    required int version,
    required String storagePath,
    required String fingerprint,
    required String versionField,
    required String pathField,
  }) =>
      {
        versionField: version,
        pathField: storagePath,
        fingerprintField: fingerprint,
        '${versionField}At': DateTime.now().toUtc().toIso8601String(),
      };

  static int nextVersion(Map<String, dynamic> doc, String versionField) {
    final cur = doc[versionField];
    if (cur is num) return cur.toInt() + 1;
    return (int.tryParse('$cur') ?? 0) + 1;
  }
}
