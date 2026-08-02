import 'package:flutter/foundation.dart';
import 'package:local_auth/local_auth.dart';

import 'biometric_auth_stub.dart';

final LocalAuthentication _localAuth = LocalAuthentication();

Future<BiometricCapabilities> probeBiometricCapabilities() async {
  if (kIsWeb) return const BiometricCapabilities();
  try {
    final hardware = await _localAuth.isDeviceSupported();
    final available = hardware && await _localAuth.canCheckBiometrics;
    return BiometricCapabilities(available: available, hardware: hardware);
  } catch (_) {
    return const BiometricCapabilities();
  }
}

Future<bool> authenticateWithBiometric() async {
  if (kIsWeb) return true;
  try {
    return await _localAuth.authenticate(
      localizedReason: 'Confirme sua identidade para ver dados bancários',
      biometricOnly: true,
      persistAcrossBackgrounding: true,
    );
  } catch (_) {
    return false;
  }
}
