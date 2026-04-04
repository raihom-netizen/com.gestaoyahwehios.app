import 'package:cloud_functions/cloud_functions.dart';

/// Ciclo de cobrança: mensal ou anual.
enum BillingCycle { monthly, annual }

/// Forma de pagamento: PIX ou cartão (parcelado).
enum PaymentMethod { pix, card }

/// Resposta do checkout Mercado Pago (assinatura / preapproval).
class MpCheckoutSession {
  final String initPoint;
  /// URL de retorno configurada no backend (mesma enviada ao MP em `back_url`).
  final String backUrl;

  const MpCheckoutSession({required this.initPoint, this.backUrl = ''});

  bool get isValid => initPoint.isNotEmpty;
}

/// Dados PIX para pagamento instantâneo (copia e cola + QR).
class MpPixSession {
  final String paymentId;
  final String qrCode;
  final String qrCodeBase64;
  final String ticketUrl;

  const MpPixSession({
    this.paymentId = '',
    this.qrCode = '',
    this.qrCodeBase64 = '',
    this.ticketUrl = '',
  });

  bool get isValid => qrCode.isNotEmpty || qrCodeBase64.isNotEmpty;
}

class BillingService {
  final FirebaseFunctions _functions =
      FirebaseFunctions.instanceFor(region: 'us-central1');

  Future<void> activatePlanDemo(String planId) async {
    final callable = _functions.httpsCallable(
      'activatePlanDemo',
      options: HttpsCallableOptions(timeout: const Duration(seconds: 20)),
    );
    await callable.call({'planId': planId});
  }

  /// Cria preferência de pagamento no Mercado Pago.
  /// [billingCycle]: 'monthly' ou 'annual'
  /// [paymentMethod]: 'pix' ou 'card' (cartão parcelado em até 10x)
  /// [installments]: número de parcelas para cartão (ex.: 10). Ignorado se paymentMethod for PIX.
  /// O backend retorna [init_point] e [back_url] (retorno pós-pagamento).
  Future<MpCheckoutSession> createMpCheckout({
    required String planId,
    BillingCycle billingCycle = BillingCycle.monthly,
    PaymentMethod paymentMethod = PaymentMethod.pix,
    int installments = 10,
  }) async {
    final callable = _functions.httpsCallable(
      'createMpPreapproval',
      options: HttpsCallableOptions(timeout: const Duration(seconds: 25)),
    );
    final payload = <String, dynamic>{
      'planId': planId,
      'billingCycle': billingCycle == BillingCycle.annual ? 'annual' : 'monthly',
      'paymentMethod': paymentMethod == PaymentMethod.card ? 'card' : 'pix',
    };
    if (paymentMethod == PaymentMethod.card && installments > 1) {
      payload['installments'] = installments;
    }
    final res = await callable.call(payload);
    final data = res.data as Map? ?? {};
    return MpCheckoutSession(
      initPoint: (data['init_point'] ?? data['initPoint'] ?? '').toString(),
      backUrl: (data['back_url'] ?? data['backUrl'] ?? '').toString(),
    );
  }

  /// Cria cobrança PIX avulsa e retorna QR + código copia-e-cola.
  Future<MpPixSession> createMpPixPayment({
    required String planId,
    BillingCycle billingCycle = BillingCycle.monthly,
  }) async {
    final callable = _functions.httpsCallable(
      'createMpPixPayment',
      options: HttpsCallableOptions(timeout: const Duration(seconds: 25)),
    );
    final res = await callable.call({
      'planId': planId,
      'billingCycle': billingCycle == BillingCycle.annual ? 'annual' : 'monthly',
    });
    final data = res.data as Map? ?? {};
    return MpPixSession(
      paymentId: (data['payment_id'] ?? data['paymentId'] ?? '').toString(),
      qrCode: (data['qr_code'] ?? data['pix_copia_cola'] ?? '').toString(),
      qrCodeBase64: (data['qr_code_base64'] ?? '').toString(),
      ticketUrl: (data['ticket_url'] ?? '').toString(),
    );
  }

  /// Compatibilidade: mantém createMpPreapproval apenas com planId.
  Future<String> createMpPreapproval(String planId) async {
    final s = await createMpCheckout(planId: planId);
    return s.initPoint;
  }
}
