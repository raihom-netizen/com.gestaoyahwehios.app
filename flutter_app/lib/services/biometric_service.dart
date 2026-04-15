import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

class BiometricService {
  static const _prefEnabled = 'biometric_enabled';
  static const _prefAsked = 'biometric_asked';

  /// Após login na tela de login com biometria do aparelho, evita pedir digital de novo ao abrir o painel.
  static bool _skipNextDashboardBiometricLock = false;

  static void markBiometricVerifiedForNextPainelEntry() {
    _skipNextDashboardBiometricLock = true;
  }

  static bool consumeSkipNextDashboardBiometricLock() {
    if (!_skipNextDashboardBiometricLock) return false;
    _skipNextDashboardBiometricLock = false;
    return true;
  }

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
      final supported = await _auth.isDeviceSupported();
      final canCheck = await _auth.canCheckBiometrics;
      if (!supported || !canCheck) {
        if (kDebugMode) {
          debugPrint(
            'BiometricService: dispositivo sem biometria utilizavel (supported=$supported canCheck=$canCheck)',
          );
        }
        return false;
      }
      return await _auth.authenticate(
        localizedReason: 'Confirme sua identidade para acessar o app',
        options: const AuthenticationOptions(
          biometricOnly: true,
          stickyAuth: true,
          useErrorDialogs: true,
        ),
      );
    } on PlatformException catch (e, st) {
      if (kDebugMode) {
        debugPrint('BiometricService.authenticate: ${e.code} ${e.message}\n$st');
      }
      return false;
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('BiometricService.authenticate: $e\n$st');
      }
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

  /// Sensor digital / Face ID utilizável (Android e iOS).
  Future<bool> isDeviceBiometricCapable() async {
    if (kIsWeb) return false;
    try {
      final supported = await _auth.isDeviceSupported();
      final canCheck = await _auth.canCheckBiometrics;
      return supported && canCheck;
    } catch (_) {
      return false;
    }
  }

  /// Liga o desbloqueio após o usuário confirmar na prompt nativa (mesma regra da tela de login).
  Future<bool> enableUnlockWithBiometrics() async {
    if (kIsWeb) return false;
    final ok = await authenticate();
    if (!ok) return false;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefEnabled, true);
    await prefs.setBool(_prefAsked, true);
    return true;
  }
}
