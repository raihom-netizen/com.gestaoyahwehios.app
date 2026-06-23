import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:gestao_yahweh/core/firebase_bootstrap.dart';
class BiometricService {
  static const _prefEnabled = 'biometric_enabled';
  static const _prefAsked = 'biometric_asked';

  /// ApÃ³s login na tela de login com biometria do aparelho, evita pedir digital de novo ao abrir o painel.
  static bool _skipNextDashboardBiometricLock = false;

  /// Desbloqueio vÃ¡lido atÃ© logout ou fecho do app â€” evita pedir digital ao voltar do picker/cÃ¢mera.
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

  /// Indica se o login rÃ¡pido por biometria pode ser usado (credenciais salvas + biometria disponÃ­vel).
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

  /// Sensor digital / Face ID utilizÃ¡vel (Android e iOS).
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

  /// Dispositivo com digital/Face ID â€” desbloqueio ao abrir o painel (sessÃ£o activa).
  Future<bool> shouldRequireBiometricUnlock() async {
    if (kIsWeb) return false;
    final user = firebaseDefaultAuth.currentUser;
    if (user == null || user.isAnonymous) return false;
    if (await isEnabled()) return true;
    if (await isDeviceBiometricCapable()) {
      await enableForReturningUserAfterLogin();
      return await isEnabled();
    }
    return false;
  }

  /// ApÃ³s login bem-sucedido no app nativo â€” activa digital/Face ID sem segundo diÃ¡logo
  /// (o utilizador pode desactivar em ConfiguraÃ§Ãµes).
  Future<void> enableForReturningUserAfterLogin() async {
    if (kIsWeb) return;
    try {
      if (!await isDeviceBiometricCapable()) return;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_prefEnabled, true);
      await prefs.setBool(_prefAsked, true);
    } catch (_) {}
  }

  /// Liga o desbloqueio apÃ³s o usuÃ¡rio confirmar na prompt nativa (mesma regra da tela de login).
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

