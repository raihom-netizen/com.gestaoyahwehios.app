import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:gestao_yahweh/core/app_constants.dart';

class AuthCpfService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  /// Mesma região das functions (resolveCpfToEmail, etc.)
  FirebaseFunctions get _functions => FirebaseFunctions.instanceFor(region: 'us-central1');

  /// E-mail sintético quando o membro só tem CPF (igual ao backend).
  static String syntheticEmailForCpf(String cpfDigits11) =>
      '${cpfDigits11.replaceAll(RegExp(r'[^0-9]'), '')}@membro.gestaoyahweh.com.br';

  String _cpfDigits(String cpf) => cpf.replaceAll(RegExp(r'[^0-9]'), '');

  Future<String?> resolveEmailByCpf(String cpf) async {
    final cpfLimpo = _cpfDigits(cpf);
    if (cpfLimpo.length != 11) return null;

    try {
      final callable = _functions.httpsCallable('resolveCpfToEmail');
      final res = await callable.call({'cpf': cpfLimpo});
      final data = Map<String, dynamic>.from(res.data as Map);
      final email = (data['email'] ?? '').toString().trim().toLowerCase();
      return email.isEmpty ? null : email;
    } on FirebaseFunctionsException {
      return null;
    } catch (_) {
      return null;
    }
  }

  /// Entrar com **e-mail** ou **CPF** (11 dígitos). Senha igual em ambos os casos.
  Future<void> signInByCpf({required String cpf, required String senha}) async {
    final raw = cpf.trim();
    if (raw.contains('@')) {
      await _auth.signInWithEmailAndPassword(
        email: raw.toLowerCase().trim(),
        password: senha,
      );
      return;
    }
    final cpfLimpo = _cpfDigits(cpf);
    if (cpfLimpo.length != 11) {
      throw FirebaseAuthException(
        code: 'invalid-credential',
        message: 'Use seu e-mail ou um CPF com 11 dígitos.',
      );
    }
    final synthetic = syntheticEmailForCpf(cpfLimpo);
    final resolved = await resolveEmailByCpf(cpfLimpo);
    final emailsToTry = <String>{};
    if (resolved != null && resolved.isNotEmpty) emailsToTry.add(resolved);
    emailsToTry.add(synthetic);

    Object? lastError;
    for (final email in emailsToTry) {
      try {
        await _auth.signInWithEmailAndPassword(email: email, password: senha);
        return;
      } on FirebaseAuthException catch (e) {
        lastError = e;
        final code = e.code.toLowerCase();
        if (code.contains('wrong-password') ||
            code.contains('invalid-credential') ||
            code.contains('invalid-login')) {
          rethrow;
        }
        if (!code.contains('user-not-found')) rethrow;
      }
    }
    if (lastError is FirebaseAuthException) throw lastError;
    throw FirebaseAuthException(
      code: 'user-not-found',
      message: 'CPF não encontrado ou sem cadastro.',
    );
  }

  /// Envia link de redefinição de senha. Aceita CPF ou e-mail.
  Future<void> sendPasswordResetByCpf(String cpfOrEmail) async {
    final raw = cpfOrEmail.trim();
    String? email;
    if (raw.contains('@')) {
      email = raw.toLowerCase();
    } else {
      final d = _cpfDigits(raw);
      email = await resolveEmailByCpf(raw);
      email ??= (d.length == 11) ? syntheticEmailForCpf(d) : null;
    }
    if (email == null || email.isEmpty) {
      throw FirebaseAuthException(
        code: 'user-not-found',
        message: 'CPF ou e-mail não encontrado. Verifique e tente novamente.',
      );
    }

    await _auth.sendPasswordResetEmail(
      email: email,
      actionCodeSettings: ActionCodeSettings(
        url: '${AppConstants.publicWebBaseUrl}/reset',
        handleCodeInApp: true,
      ),
    );
  }
}
