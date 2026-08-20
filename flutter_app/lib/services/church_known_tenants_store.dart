import 'dart:async';

import 'package:shared_preferences/shared_preferences.dart';

import 'package:gestao_yahweh/core/tenant/church_tenant_override.dart';

/// Guarda no aparelho os ids que já se provou serem documentos reais de igreja.
///
/// Nem todo tenant respeita `igreja_*` (`assembleia_de_deus_palavra_que_da_vida`,
/// `igreta_batista_nacional_alianca`). [ChurchTenantOverride] aceita esses ids
/// depois de alguém os registar — mas o registo vivia **só em RAM**: bastava
/// fechar a app para todos os módulos voltarem a rejeitá-los e lerem a igreja
/// de origem, até o operador abrir o seletor de igrejas outra vez.
///
/// Aqui o registo sobrevive ao arranque a frio: [restore] repõe a lista antes
/// do primeiro módulo ler o que quer que seja.
abstract final class ChurchKnownTenantsStore {
  ChurchKnownTenantsStore._();

  static const String _prefsKey = 'church_known_tenant_ids_v1';
  static const int _maxIds = 200;

  static bool _wired = false;
  static bool _saveScheduled = false;

  /// Repõe os ids guardados e passa a persistir os novos.
  static Future<void> restore() async {
    if (!_wired) {
      _wired = true;
      ChurchTenantOverride.onKnownRegistered = (_) => _scheduleSave();
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      for (final id in prefs.getStringList(_prefsKey) ?? const <String>[]) {
        ChurchTenantOverride.registerKnownSilently(id);
      }
    } catch (_) {}
  }

  /// Grava em lote: o registo acontece em rajada (lista de igrejas, índice de
  /// slugs), e uma escrita por id seria desperdício.
  static void _scheduleSave() {
    if (_saveScheduled) return;
    _saveScheduled = true;
    Timer(const Duration(milliseconds: 400), () {
      _saveScheduled = false;
      unawaited(_save());
    });
  }

  static Future<void> _save() async {
    try {
      final ids = ChurchTenantOverride.known.toList();
      if (ids.isEmpty) return;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(
        _prefsKey,
        ids.length > _maxIds ? ids.sublist(ids.length - _maxIds) : ids,
      );
    } catch (_) {}
  }
}
