import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

/// O Firebase Storage **não implementa listagem** (`listAll`/`list`) no SDK
/// **C++**, que é o usado no desktop Windows/Linux.
///
/// ⚠️ Não basta apanhar a excepção: chamar `listAll()` no Windows devolve
/// `[firebase_storage/unimplemented] Listing files is not supported by the
/// Firebase C++ SDK on Windows` e a seguir **mata o processo com
/// Segmentation fault** — é o que fazia o app instalado ficar «Não está
/// respondendo». O `try/catch` do lado Dart não salva, porque o crash acontece
/// dentro do plugin nativo.
///
/// Por isso a regra é: **nem sequer chamar** a listagem onde não é suportada.
bool get firebaseStorageListingSupported {
  if (kIsWeb) return true;
  switch (defaultTargetPlatform) {
    case TargetPlatform.android:
    case TargetPlatform.iOS:
    case TargetPlatform.macOS:
      return true;
    case TargetPlatform.windows:
    case TargetPlatform.linux:
    case TargetPlatform.fuchsia:
      return false;
  }
}
