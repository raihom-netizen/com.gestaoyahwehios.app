import 'dart:io';

import 'package:flutter/foundation.dart';

/// Trabalho pesado fora da thread principal — compressão, PDF, bytes grandes.
abstract final class YahwehHeavyWork {
  YahwehHeavyWork._();

  /// Executa [callback] em isolate (mobile/desktop) ou inline na web.
  static Future<R> run<Q, R>(
    ComputeCallback<Q, R> callback,
    Q message,
  ) {
    if (kIsWeb) {
      final result = callback(message);
      if (result is Future<R>) return result;
      return Future.value(result);
    }
    return compute(callback, message);
  }

  /// Leitura de ficheiro grande — preferir isolate.
  static Future<List<int>> readFileBytes(String path) async {
    return run<String, List<int>>(_readFileBytesIsolate, path);
  }
}

List<int> _readFileBytesIsolate(String path) {
  return File(path).readAsBytesSync();
}
