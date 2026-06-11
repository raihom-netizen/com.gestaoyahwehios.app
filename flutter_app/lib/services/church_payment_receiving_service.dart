import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:gestao_yahweh/services/church_tenant_resilient_reads.dart';
import 'package:gestao_yahweh/services/church_operational_paths.dart';

/// Formas de recebimento — apenas Mercado Pago (`config/payment_receiving`).
class ChurchPaymentReceivingConfig {
  const ChurchPaymentReceivingConfig({
    this.mercadoPagoEnabled = true,
  });

  final bool mercadoPagoEnabled;

  static ChurchPaymentReceivingConfig fromMap(Map<String, dynamic>? raw) {
    if (raw == null || raw.isEmpty) {
      return const ChurchPaymentReceivingConfig();
    }
    return ChurchPaymentReceivingConfig(
      mercadoPagoEnabled: raw['mercadoPagoEnabled'] != false,
    );
  }

  Map<String, dynamic> toMap() => {
        'mercadoPagoEnabled': mercadoPagoEnabled,
        'updatedAt': FieldValue.serverTimestamp(),
      };

  /// Remove campos legados (InitPay / Infinity Pay / outros links).
  static Map<String, dynamic> legacyFieldsToDelete() => {
        'initPayEnabled': FieldValue.delete(),
        'initPayCheckoutUrl': FieldValue.delete(),
        'initPayPixLink': FieldValue.delete(),
        'otherCheckoutUrl': FieldValue.delete(),
        'otherProviderName': FieldValue.delete(),
      };
}

abstract final class ChurchPaymentReceivingService {
  ChurchPaymentReceivingService._();

  static DocumentReference<Map<String, dynamic>> _ref(String tenantId) =>
      ChurchOperationalPaths.churchDoc(tenantId.trim())
          .collection('config')
          .doc('payment_receiving');

  static Future<ChurchPaymentReceivingConfig> read(String tenantId) async {
    try {
      final snap = await ChurchTenantResilientReads.configDoc(
        tenantId,
        'payment_receiving',
      );
      return ChurchPaymentReceivingConfig.fromMap(snap.data());
    } catch (_) {
      return const ChurchPaymentReceivingConfig();
    }
  }

  static Future<void> save(
    String tenantId,
    ChurchPaymentReceivingConfig cfg,
  ) async {
    await _ref(tenantId).set(
      {
        ...cfg.toMap(),
        ...ChurchPaymentReceivingConfig.legacyFieldsToDelete(),
      },
      SetOptions(merge: true),
    );
  }
}
