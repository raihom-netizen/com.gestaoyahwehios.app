import 'package:shared_preferences/shared_preferences.dart';

/// Fotos de perfil (Storage) em cache no disco do aparelho — listas e módulos abrem mais rápido.
const String kPrefMemberPhotoDiskCacheV1 = 'yahweh_pref_member_photo_disk_cache_v1';

class MediaCachePreferences {
  MediaCachePreferences._();

  static bool? _memberPhotoDiskInMemory;

  /// Padrão: ligado (Android/iOS). Web ignora — não há pasta persistente equivalente.
  static Future<bool> isMemberPhotoDiskCacheEnabled() async {
    if (_memberPhotoDiskInMemory != null) return _memberPhotoDiskInMemory!;
    final p = await SharedPreferences.getInstance();
    _memberPhotoDiskInMemory = p.getBool(kPrefMemberPhotoDiskCacheV1) ?? true;
    return _memberPhotoDiskInMemory!;
  }

  static Future<void> setMemberPhotoDiskCacheEnabled(bool value) async {
    _memberPhotoDiskInMemory = value;
    final p = await SharedPreferences.getInstance();
    await p.setBool(kPrefMemberPhotoDiskCacheV1, value);
  }

  /// Após importar prefs noutro isolate ou teste.
  static void clearMemorySnapshot() {
    _memberPhotoDiskInMemory = null;
  }
}
