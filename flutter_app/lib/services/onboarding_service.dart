import 'package:cloud_functions/cloud_functions.dart';

import 'package:gestao_yahweh/core/firebase_bootstrap.dart';
class OnboardingService {
  final FirebaseFunctions _functions =
      FirebaseFunctions.instanceFor(app: firebaseDefaultApp, region: '');

  Future<void> createGestorWithTrial({
    required String nome,
    required String cpf,
    required String email,
    required String senha,
    required String igrejaNome,
    required String igrejaDoc,
    required String planId,
  }) async {
    final callable = _functions.httpsCallable(
      'createFirstGestorWithPlan',
      options: HttpsCallableOptions(timeout: const Duration(seconds: 30)),
    );

    await callable.call({
      'nome': nome,
      'cpf': cpf,
      'email': email,
      'senha': senha,
      'igrejaNome': igrejaNome,
      'igrejaDoc': igrejaDoc,
      'planId': planId,
    });
  }
}

