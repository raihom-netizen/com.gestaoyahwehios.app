import 'package:flutter/foundation.dart';

/// Notifica telas de taxas de escala quando cache em memória muda.
class ScaleRatesCacheNotifier {
  ScaleRatesCacheNotifier._();

  static final ScaleRatesCacheNotifier instance = ScaleRatesCacheNotifier._();

  final ValueNotifier<int> revision = ValueNotifier<int>(0);

  void notifyRatesChanged([String? uid]) {
    revision.value++;
  }
}
