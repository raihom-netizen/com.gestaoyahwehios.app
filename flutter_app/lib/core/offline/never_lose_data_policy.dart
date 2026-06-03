import 'package:gestao_yahweh/core/offline/offline_modules.dart';

/// Modo «Nunca Perder Dados» — write-ahead obrigatório antes do Firebase.
abstract final class NeverLoseDataPolicy {
  NeverLoseDataPolicy._();

  static const protectedModules = <String>{
    OfflineModules.membros,
    OfflineModules.eventos,
    OfflineModules.avisos,
    OfflineModules.patrimonio,
    OfflineModules.financeiro,
    OfflineModules.chat,
    OfflineModules.mural,
  };

  static bool appliesTo(String module) => protectedModules.contains(module);
}
