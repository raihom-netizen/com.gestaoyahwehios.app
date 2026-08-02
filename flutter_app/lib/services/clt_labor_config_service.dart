import 'package:gestao_yahweh/models/scale_rates.dart';

/// Configuração CLT simplificada — converte para [ScaleRates] padrão.
class CltLaborConfig {
  const CltLaborConfig();

  ScaleRates toScaleRates() => ScaleRates.defaultRates;
}

class CltLaborConfigService {
  CltLaborConfigService();

  final Map<String, CltLaborConfig> _memory = {};

  void invalidate([String? uid]) {
    if (uid == null || uid.isEmpty) {
      _memory.clear();
    } else {
      _memory.remove(uid.trim());
    }
  }

  Future<CltLaborConfig> getConfig(String uid) async {
    final key = uid.trim();
    return _memory.putIfAbsent(key, () => const CltLaborConfig());
  }
}
