import 'dart:html' as html;

import 'credential_store.dart';

class _WebCredentialStore implements CredentialStore {
  html.Storage get _storage => html.window.localStorage;

  @override
  Future<bool?> getBool(String key) async {
    final value = _storage[key];
    if (value == null) return null;
    if (value == 'true') return true;
    if (value == 'false') return false;
    return null;
  }

  @override
  Future<String?> getString(String key) async => _storage[key];

  @override
  Future<void> remove(String key) async {
    _storage.remove(key);
  }

  @override
  Future<void> setBool(String key, bool value) async {
    _storage[key] = value.toString();
  }

  @override
  Future<void> setString(String key, String value) async {
    _storage[key] = value;
  }
}

CredentialStore createCredentialStoreImpl() => _WebCredentialStore();
