import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_quill/quill_delta.dart';

/// Campo Firestore com o Delta Quill (lista JSON). Mantém [text] em paralelo para busca e legados.
const String kChurchPostTextDeltaKey = 'textDelta';

/// Documento a partir de um mapa de post (evento/aviso): usa [kChurchPostTextDeltaKey] ou texto simples em `text`.
Document churchPostDocumentFromData(Map<String, dynamic> data) {
  final raw = data[kChurchPostTextDeltaKey];
  if (raw is List && raw.isNotEmpty) {
    try {
      return Document.fromJson(List<dynamic>.from(raw));
    } catch (_) {}
  }
  final t = (data['text'] ?? '').toString();
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

/// Texto plano para pesquisa, partilha e compatível com posts só com `text`.
String churchPostPlainText(Map<String, dynamic> data) {
  final raw = data[kChurchPostTextDeltaKey];
  if (raw is List && raw.isNotEmpty) {
    try {
      return Document.fromJson(List<dynamic>.from(raw)).toPlainText().trim();
    } catch (_) {}
  }
  return (data['text'] ?? '').toString().trim();
}

/// Assinatura para [Key] quando o conteúdo rico ou o texto mudam.
int churchPostRichContentSig(Map<String, dynamic> data) {
  final plain = churchPostPlainText(data);
  final raw = data[kChurchPostTextDeltaKey];
  return Object.hash(plain, raw is List ? raw.toString().hashCode : 0);
}
