/// Formatação de pré-visualização na lista do hub (estilo WhatsApp).
String churchChatHubRowSubtitle({
  required String rawPreview,
  required bool isTyping,
  String? typingPreview,
}) {
  if (isTyping) {
    final t = (typingPreview ?? '').trim();
    return t.isNotEmpty ? t : 'A digitar…';
  }
  final p = rawPreview.trim();
  if (p.isEmpty) return 'Toque para conversar';
  return p;
}

/// Em grupos, prefixo «Nome: mensagem» quando a última mensagem não é sua.
String churchChatHubGroupPreviewLine({
  required String preview,
  required String myUid,
  required String? lastSenderUid,
  required String senderFirstName,
}) {
  final p = preview.trim();
  if (p.isEmpty) return 'Toque para conversar';
  final sender = (lastSenderUid ?? '').trim();
  if (sender.isEmpty || sender == myUid) return p;
  final name = senderFirstName.trim();
  if (name.isEmpty) return p;
  if (p.startsWith('$name:')) return p;
  return '$name: $p';
}
