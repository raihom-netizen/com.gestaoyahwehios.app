import 'dart:async';
import 'dart:io' show Platform;

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:gestao_yahweh/core/firebase_bootstrap.dart';
import 'package:gestao_yahweh/services/billing_service.dart';
import 'package:in_app_purchase/in_app_purchase.dart';

/// Pagamento nativo Android via Google Play Billing.
///
/// O utilizador escolhe o plano e confirma diretamente no diálogo do Google
/// Play (insere os dados do cartão/Google Pay lá, nunca dentro do app). Após a
/// compra, o token é validado no backend ([verifyPlayPurchase]) que ativa a
/// licença da igreja. Pagamento único (one-time), sem cobrança recorrente.
///
/// Requisitos no Google Play Console:
///  - Produtos únicos (IDs abaixo) com o mesmo preço dos planos web.
///  - API Google Play Developer ativada + conta de serviço com acesso.
class GooglePlayPaymentsGate {
  GooglePlayPaymentsGate._();

  static final InAppPurchase _iap = InAppPurchase.instance;

  /// `true` apenas em Android nativo (Play Billing indisponível em iOS/Web).
  static bool get isPlayAvailable {
    if (kIsWeb) return false;
    try {
      return Platform.isAndroid;
    } catch (_) {
      return false;
    }
  }

  /// SKUs do Google Play (um por ciclo de cobrança). Devem coincidir com o
  /// Play Console. O preço do produto é definido lá; o plano da igreja (planId)
  /// é ativado no backend a partir do [planId] escolhido no app.
  static const String skuMensal = 'gy_plan_mensal';
  static const String skuAnual = 'gy_plan_anual';

  /// SKU conforme o ciclo selecionado (mensal/anual), independente do plano.
  static String skuForCycle(BillingCycle cycle) =>
      cycle == BillingCycle.annual ? skuAnual : skuMensal;

  /// Verifica se o Play Billing está disponível e configurado neste dispositivo.
  static Future<bool> isAvailable() async {
    if (!isPlayAvailable) return false;
    try {
      return await _iap.isAvailable();
    } catch (_) {
      return false;
    }
  }

  /// Carrega os detalhes de produto (preço) para os SKUs indicados.
  static Future<Map<String, ProductDetails>> loadProducts(
    List<String> skus,
  ) async {
    final ids = skus.where((s) => s.trim().isNotEmpty).toSet();
    if (ids.isEmpty) return {};
    try {
      final resp = await _iap.queryProductDetails(ids);
      final map = <String, ProductDetails>{};
      for (final p in resp.productDetails) {
        map[p.id] = p;
      }
      return map;
    } catch (_) {
      return {};
    }
  }

  /// Inicia a compra do [sku] e aguarda o resultado no stream do Play Billing.
  /// Em caso de sucesso valida no backend e ativa a licença da igreja.
  static Future<GooglePlayPurchaseResult> buy({
    required String sku,
    required String planId,
    required BillingCycle cycle,
    String? tenantId,
  }) async {
    if (!await isAvailable()) {
      return const GooglePlayPurchaseResult.failed(
        'Google Play Billing indisponível neste dispositivo.',
      );
    }
    final products = await loadProducts([sku]);
    final product = products[sku];
    if (product == null) {
      return GooglePlayPurchaseResult.failed(
        'Produto $sku não encontrado no Google Play.',
      );
    }

    final completer = Completer<PurchaseDetails>();
    final sub = _iap.purchaseStream.listen((purchases) {
      for (final p in purchases) {
        if (p.productID == sku && !completer.isCompleted) {
          completer.complete(p);
        }
      }
    });

    try {
      final started = await _iap.buyNonConsumable(
        purchaseParam: PurchaseParam(productDetails: product),
      );
      if (!started) {
        return const GooglePlayPurchaseResult.failed(
          'Não foi possível iniciar a compra no Google Play.',
        );
      }
      final purchase = await completer.future.timeout(const Duration(minutes: 5));
      return await _verifyAndActivate(
        purchase,
        planId: planId,
        cycle: cycle,
        tenantId: tenantId,
      );
    } catch (e) {
      return GooglePlayPurchaseResult.failed('Erro na compra: $e');
    } finally {
      await sub.cancel();
    }
  }

  static Future<GooglePlayPurchaseResult> _verifyAndActivate(
    PurchaseDetails purchase, {
    required String planId,
    required BillingCycle cycle,
    String? tenantId,
  }) async {
    if (purchase.status != PurchaseStatus.purchased &&
        purchase.status != PurchaseStatus.restored) {
      return GooglePlayPurchaseResult.failed(
        'Pagamento não concluído (${purchase.status}).',
      );
    }
    try {
      final functions =
          FirebaseFunctions.instanceFor(app: firebaseDefaultApp, region: 'us-central1');
      final callable = functions.httpsCallable(
        'verifyPlayPurchase',
        options: HttpsCallableOptions(timeout: const Duration(seconds: 30)),
      );
      final payload = <String, dynamic>{
        'planId': planId,
        'billingCycle': cycle == BillingCycle.annual ? 'annual' : 'monthly',
        'productId': purchase.productID,
        'purchaseToken': purchase.verificationData.serverVerificationData,
      };
      final tid = tenantId?.trim() ?? '';
      if (tid.isNotEmpty) {
        payload['tenantId'] = tid;
        payload['igrejaId'] = tid;
      }
      final res = await callable.call(payload);
      final data = res.data as Map? ?? {};
      if (data['ok'] == true) {
        if (purchase.pendingCompletePurchase) {
          await _iap.completePurchase(purchase);
        }
        return const GooglePlayPurchaseResult.success();
      }
      return GooglePlayPurchaseResult.failed(
        data['error']?.toString() ?? 'Falha na ativação da licença.',
      );
    } catch (e) {
      return GooglePlayPurchaseResult.failed('Erro ao ativar licença: $e');
    }
  }
}

class GooglePlayPurchaseResult {
  final bool ok;
  final String? error;
  const GooglePlayPurchaseResult.success()
      : ok = true,
        error = null;
  const GooglePlayPurchaseResult.failed(this.error)
      : ok = false;
}
