import 'dart:typed_data';

/// Fallback para plataformas IO sem extensoes nativas de clipboard de imagem.
/// Mantemos retorno nulo para nao acoplar build Android a bibliotecas nativas
/// que podem quebrar requisitos de pagina 16KB na Play.
Future<Uint8List?> smartInputReadClipboardImageBytesForPaste() async {
  return null;
}

/// Colagem por teclado / atalhos é tratada na web; em mobile use [ContentInsertionConfiguration] + botão Colar.
Object? smartInputRegisterWebPasteImageListener(void Function(Uint8List bytes) onImage) => null;

void smartInputUnregisterWebPasteImageListener(Object? handle) {}
