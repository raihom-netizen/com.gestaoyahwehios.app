import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'credential_store.dart';

class _InMemoryCredentialStore implements CredentialStore {
  final Map<String, Object?> _data = <String, Object?>{};

  @override
  Future<bool?> getBool(String key) async => _data[key] as bool?;

  @override
  Future<String?> getString(String key) async => _data[key] as String?;

  @override
  Future<void> remove(String key) async {
    _data.remove(key);
  }

  @override
  Future<void> setBool(String key, bool value) async {
    _data[key] = value;
  }

  @override
  Future<void> setString(String key, String value) async {
    _data[key] = value;
  }
}

class _SharedPrefsCredentialStore implements CredentialStore {
  _SharedPrefsCredentialStore(this._prefs);

  final SharedPreferences _prefs;

  @override
  Future<bool?> getBool(String key) async => _prefs.getBool(key);

  @override
  Future<String?> getString(String key) async => _prefs.getString(key);

  @override
  Future<void> remove(String key) async {
    await _prefs.remove(key);
  }

  @override
  Future<void> setBool(String key, bool value) async {
    await _prefs.setBool(key, value);
  }

  @override
  Future<void> setString(String key, String value) async {
    await _prefs.setString(key, value);
  }
}

CredentialStore createCredentialStoreImpl() {
  try {
    final asyncPrefs = SharedPreferencesAsync();
    return _SharedPrefsAsyncCredentialStore(asyncPrefs);
  } on MissingPluginException catch (e) {
    debugPrint('Aviso: SharedPreferences indisponível, usando memória: $e');
    return _InMemoryCredentialStore();
  } catch (e) {
    debugPrint('Aviso ao inicializar armazenamento local, usando memória: $e');
    return _InMemoryCredentialStore();
  }
}

class _SharedPrefsAsyncCredentialStore implements CredentialStore {
  _SharedPrefsAsyncCredentialStore(this._prefs);

  final SharedPreferencesAsync _prefs;

  @override
  Future<bool?> getBool(String key) => _prefs.getBool(key);

  @override
  Future<String?> getString(String key) => _prefs.getString(key);

  @override
  Future<void> remove(String key) => _prefs.remove(key);

  @override
  Future<void> setBool(String key, bool value) => _prefs.setBool(key, value);

  @override
  Future<void> setString(String key, String value) => _prefs.setString(key, value);
}
