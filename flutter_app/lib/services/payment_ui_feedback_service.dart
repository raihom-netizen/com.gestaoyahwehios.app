import 'package:flutter/foundation.dart';

/// Sinaliza eventos visuais globais após confirmação de pagamento.
class PaymentUiFeedbackService {
  PaymentUiFeedbackService._();

  static final ValueNotifier<int> paymentConfirmedTick = ValueNotifier<int>(0);

  static void notifyPaymentConfirmed() {
    paymentConfirmedTick.value = paymentConfirmedTick.value + 1;
  }
}
