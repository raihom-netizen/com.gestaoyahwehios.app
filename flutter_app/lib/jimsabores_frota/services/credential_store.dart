import 'credential_store_io.dart'
    if (dart.library.html) 'credential_store_web.dart';

abstract class CredentialStore {
  Future<bool?> getBool(String key);
  Future<String?> getString(String key);
  Future<void> setBool(String key, bool value);
  Future<void> setString(String key, String value);
  Future<void> remove(String key);
}

CredentialStore createCredentialStore() => createCredentialStoreImpl();
