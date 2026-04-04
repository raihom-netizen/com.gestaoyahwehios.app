import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

class BiometricService {
  static const _prefEnabled = 'biometric_enabled';
  static const _prefAsked = 'biometric_asked';

  final LocalAuthentication _auth = LocalAuthentication();

  Future<bool> isEnabled() async {
    if (kIsWeb) return false;
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_prefEnabled) == true;
  }

  Future<void> maybeEnableBiometrics(BuildContext context) async {
    if (kIsWeb) return;
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_prefAsked) == true) return;

    final supported = await _auth.isDeviceSupported();
    final canCheck = await _auth.canCheckBiometrics;
    if (!supported || !canCheck) {
      await prefs.setBool(_prefAsked, true);
      return;
    }

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Acesso rapido'),
        content: const Text(
          'Deseja ativar acesso por digital/face para as proximas entradas?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Nao'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Ativar'),
          ),
        ],
      ),
    );

    await prefs.setBool(_prefAsked, true);
    if (ok == true) {
      await prefs.setBool(_prefEnabled, true);
    }
  }

  Future<bool> authenticate() async {
    if (kIsWeb) return true;
    try {
      return await _auth.authenticate(
        localizedReason: 'Confirme sua identidade para acessar o app',
        options: const AuthenticationOptions(
          biometricOnly: true,
          stickyAuth: true,
        ),
      );
    } catch (_) {
      return false;
    }
  }

  /// Indica se o login rápido por biometria pode ser usado (credenciais salvas + biometria disponível).
  Future<bool> canUseQuickBiometricLogin() async {
    if (kIsWeb) return false;
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_prefEnabled) == true;
  }

  /// Desativa biometria para este dispositivo.
  Future<void> disableForThisDevice() async {
    if (kIsWeb) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefEnabled, false);
  }
}
