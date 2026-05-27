import 'package:shared_preferences/shared_preferences.dart';

/// Secções colapsáveis do painel (persistem entre sessões).
abstract final class PanelSectionPrefs {
  PanelSectionPrefs._();

  static const _prefix = 'panel_section_collapsed_v2_';

  static Future<bool> isCollapsed(String sectionKey) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('$_prefix$sectionKey') ?? false;
  }

  static Future<void> setCollapsed(String sectionKey, bool collapsed) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('$_prefix$sectionKey', collapsed);
  }
}
