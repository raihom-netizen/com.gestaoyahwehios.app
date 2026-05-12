import 'package:flutter/foundation.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_quill/quill_delta.dart';

/// Campo Firestore com o Delta Quill (lista JSON). Mantém [text] em paralelo para busca e legados.
const String kChurchPostTextDeltaKey = 'textDelta';

Document _documentFromPlainText(String text) {
  final t = text.trim();
  if (t.isEmpty) {
    return Document();
  }
  final delta = Delta();
  if (t.endsWith('\n')) {
    delta.insert(t);
  } else {
    delta.insert('$t\n');
  }
  return Document.fromDelta(delta);
}

/// Documento a partir de um mapa de post (evento/aviso): usa [kChurchPostTextDeltaKey] ou texto simples em `text`.
///
/// Blindado: qualquer Delta inválido/corrupto cai para texto plano — evita tela cinza no Quill.
Document churchPostDocumentFromData(Map<String, dynamic> data) {
  try {
    final raw = data[kChurchPostTextDeltaKey];
    if (raw is List && raw.isNotEmpty) {
      try {
        return Document.fromJson(List<dynamic>.from(raw));
      } catch (e1, st1) {
        assert(() {
          debugPrint('churchPostDocumentFromData: Delta inválido, a usar text. $e1\n$st1');
          return true;
        }());
      }
    }
    return _documentFromPlainText((data['text'] ?? '').toString());
  } catch (e, st) {
    assert(() {
      debugPrint('churchPostDocumentFromData: fallback total. $e\n$st');
      return true;
    }());
    try {
      return _documentFromPlainText((data['text'] ?? '').toString());
    } catch (_) {
      return Document();
    }
  }
}

/// Texto plano para pesquisa, partilha e compatível com posts só com `text`.
String churchPostPlainText(Map<String, dynamic> data) {
  try {
    final raw = data[kChurchPostTextDeltaKey];
    if (raw is List && raw.isNotEmpty) {
      try {
        return Document.fromJson(List<dynamic>.from(raw)).toPlainText().trim();
      } catch (_) {}
    }
    return (data['text'] ?? '').toString().trim();
  } catch (_) {
    return (data['text'] ?? '').toString().trim();
  }
}

/// Assinatura para [Key] quando o conteúdo rico ou o texto mudam.
int churchPostRichContentSig(Map<String, dynamic> data) {
  final plain = churchPostPlainText(data);
  final raw = data[kChurchPostTextDeltaKey];
  return Object.hash(plain, raw is List ? raw.toString().hashCode : 0);
}
