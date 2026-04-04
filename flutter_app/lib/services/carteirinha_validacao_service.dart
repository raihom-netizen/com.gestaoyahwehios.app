import 'package:cloud_functions/cloud_functions.dart';

/// Resultado da validação pública da credencial (via Cloud Function com Admin SDK).
class CarteirinhaValidacaoResultado {
  final bool ok;
  final bool found;
  final bool active;
  final String churchName;
  final String titularMascarado;
  final String validityHint;
  final String message;

  const CarteirinhaValidacaoResultado({
    required this.ok,
    required this.found,
    required this.active,
    required this.churchName,
    required this.titularMascarado,
    required this.validityHint,
    required this.message,
  });

  factory CarteirinhaValidacaoResultado.fromMap(Map<String, dynamic> raw) {
    bool b(dynamic v) {
      if (v is bool) return v;
      if (v is String) return v.toLowerCase() == 'true';
      return false;
    }

    String s(dynamic v) => (v ?? '').toString().trim();

    return CarteirinhaValidacaoResultado(
      ok: b(raw['ok']),
      found: b(raw['found']),
      active: b(raw['active']),
      churchName: s(raw['churchName']),
      titularMascarado: s(raw['titularMascarado']),
      validityHint: s(raw['validityHint']),
      message: s(raw['message']),
    );
  }
}

/// Chama a função [validateCarteirinhaPublic] (sem login).
class CarteirinhaValidacaoService {
  CarteirinhaValidacaoService._();

  static final FirebaseFunctions _fn = FirebaseFunctions.instanceFor(region: 'us-central1');

  static Future<CarteirinhaValidacaoResultado> consultar({
    required String tenantId,
    required String memberId,
  }) async {
    final tid = tenantId.trim();
    final mid = memberId.trim();
    if (tid.isEmpty || mid.isEmpty) {
      return const CarteirinhaValidacaoResultado(
        ok: false,
        found: false,
        active: false,
        churchName: '',
        titularMascarado: '',
        validityHint: '',
        message: 'Parâmetros inválidos.',
      );
    }

    try {
      final callable = _fn.httpsCallable('validateCarteirinhaPublic');
      final res = await callable.call({
        'tenantId': tid,
        'memberId': mid,
      });
      final data = res.data;
      if (data is! Map) {
        return const CarteirinhaValidacaoResultado(
          ok: false,
          found: false,
          active: false,
          churchName: '',
          titularMascarado: '',
          validityHint: '',
          message: 'Resposta vazia do servidor.',
        );
      }
      return CarteirinhaValidacaoResultado.fromMap(Map<String, dynamic>.from(data));
    } on FirebaseFunctionsException catch (e) {
      return CarteirinhaValidacaoResultado(
        ok: false,
        found: false,
        active: false,
        churchName: '',
        titularMascarado: '',
        validityHint: '',
        message: e.message ?? e.code,
      );
    } catch (e) {
      return CarteirinhaValidacaoResultado(
        ok: false,
        found: false,
        active: false,
        churchName: '',
        titularMascarado: '',
        validityHint: '',
        message: e.toString(),
      );
    }
  }
}
