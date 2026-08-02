class BiometricCapabilities {
  const BiometricCapabilities({this.available = false, this.hardware = false});

  final bool available;
  final bool hardware;
}

Future<BiometricCapabilities> probeBiometricCapabilities() async =>
    const BiometricCapabilities();

Future<bool> authenticateWithBiometric() async => true;
