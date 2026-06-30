import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:gestao_yahweh/core/firebase_bootstrap.dart';
class BiometricService {
  static const _prefEnabled = 'biometric_enabled';
  static const _prefAsked = 'biometric_asked';
  /// Utilizador desactivou explicitamente em Configurações — nunca reactivar sozinho.
  static const _prefDisabledByUser = 'biometric_disabled_by_user';

  /// Após login na tela de login com biometria do aparelho, evita pedir digital de novo ao abrir o painel.
  static bool _skipNextDashboardBiometricLock = false;

  /// Desbloqueio válido até logout ou fecho do app — evita pedir digital ao voltar do picker/câmera.
  static bool _sessionBiometricUnlocked = false;

  static void markBiometricVerifiedForNextPainelEntry() {
    _skipNextDashboardBiometricLock = true;
    _sessionBiometricUnlocked = true;
  }

  static void markSessionBiometricUnlocked() {
    _sessionBiometricUnlocked = true;
  }

  static bool get isSessionBiometricUnlocked => _sessionBiometricUnlocked;

  static void clearSessionBiometricUnlock() {
    _sessionBiometricUnlocked = false;
    _skipNextDashboardBiometricLock = false;
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
    if (prefs.getBool(_prefDisabledByUser) == true) return false;
    return prefs.getBool(_prefEnabled) == true;
  }

  Future<bool> isDisabledByUser() async {
    if (kIsWeb) return false;
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_prefDisabledByUser) == true;
  }

  Future<void> maybeEnableBiometrics(BuildContext context) async {
    if (kIsWeb) return;
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_prefAsked) == true) return;
    if (prefs.getBool(_prefDisabledByUser) == true) return;

    final supported = await _auth.isDeviceSupported();
    final canCheck = await _auth.canCheckBiometrics;
    if (!supported || !canCheck) {
      await prefs.setBool(_prefAsked, true);
      return;
    }

    if (!context.mounted) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Acesso rapido'),
        content: const Text(
          'Deseja ativar entrada com Face ID ou impressao digital nas proximas vezes '
          '(o aparelho mostra o que estiver disponivel)? '
          'Depois ativado, o login pode abrir o pedido biometrico sozinho; se falhar, '
          'use e-mail e senha ate entrar de novo. Voce tambem pode mudar isto em Configuracoes.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Nao'),
          ),
          FilledButton(
            onPressed: () async {
              final confirmed = await authenticate();
              if (!ctx.mounted) return;
              if (confirmed) Navigator.pop(ctx, true);
            },
            child: const Text('Ativar'),
          ),
        ],
      ),
    );

    await prefs.setBool(_prefAsked, true);
    if (ok == true) {
      await prefs.setBool(_prefEnabled, true);
      await prefs.setBool(_prefDisabledByUser, false);
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
        biometricOnly: true,
        persistAcrossBackgrounding: true,
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
  Future<bool> canUseQuickBiometricLogin() async => isEnabled();

  /// Desativa biometria para este dispositivo.
  Future<void> disableForThisDevice() async {
    if (kIsWeb) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefEnabled, false);
    await prefs.setBool(_prefDisabledByUser, true);
    await prefs.setBool(_prefAsked, true);
    clearSessionBiometricUnlock();
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

  /// Dispositivo com digital/Face ID — só se o utilizador activou em Configurações.
  Future<bool> shouldRequireBiometricUnlock() async {
    if (kIsWeb) return false;
    final user = firebaseDefaultAuth.currentUser;
    if (user == null || user.isAnonymous) return false;
    return isEnabled();
  }

  /// Primeiro login nativo — sugere biometria só se o utilizador nunca recusou/desactivou.
  Future<void> enableForReturningUserAfterLogin() async {
    if (kIsWeb) return;
    if (await isDisabledByUser()) return;
    try {
      if (!await isDeviceBiometricCapable()) return;
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getBool(_prefAsked) == true) return;
      await prefs.setBool(_prefEnabled, true);
      await prefs.setBool(_prefAsked, true);
      await prefs.setBool(_prefDisabledByUser, false);
    } catch (_) {}
  }

  /// Liga o desbloqueio após o usuário confirmar na prompt nativa (mesma regra da tela de login).
  Future<bool> enableUnlockWithBiometrics() async {
    if (kIsWeb) return false;
    final ok = await authenticate();
    if (!ok) return false;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefEnabled, true);
    await prefs.setBool(_prefAsked, true);
    await prefs.setBool(_prefDisabledByUser, false);
    return true;
  }
}

