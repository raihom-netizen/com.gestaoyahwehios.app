import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:gestao_yahweh/services/church_tenant_resilient_reads.dart';

/// Formas de recebimento configuradas pelo gestor/pastor (`config/payment_receiving`).
class ChurchPaymentReceivingConfig {
  const ChurchPaymentReceivingConfig({
    this.mercadoPagoEnabled = true,
    this.initPayEnabled = false,
    this.initPayCheckoutUrl = '',
    this.initPayPixLink = '',
    this.otherCheckoutUrl = '',
    this.otherProviderName = '',
  });

  final bool mercadoPagoEnabled;
  final bool initPayEnabled;
  final String initPayCheckoutUrl;
  final String initPayPixLink;
  final String otherCheckoutUrl;
  final String otherProviderName;

  bool get hasInitPayLink =>
      initPayEnabled &&
      (initPayCheckoutUrl.trim().isNotEmpty ||
          initPayPixLink.trim().isNotEmpty);

  String? get primaryExternalCheckoutUrl {
    if (initPayEnabled && initPayCheckoutUrl.trim().isNotEmpty) {
      return initPayCheckoutUrl.trim();
    }
    final other = otherCheckoutUrl.trim();
    if (other.isNotEmpty) return other;
    return null;
  }

  String get externalCheckoutButtonLabel {
    if (initPayEnabled && hasInitPayLink) return 'Pagar pelo InitPay';
    final name = otherProviderName.trim();
    if (name.isNotEmpty) return 'Pagar por $name';
    return 'Pagar pelo link da igreja';
  }

  static ChurchPaymentReceivingConfig fromMap(Map<String, dynamic>? raw) {
    if (raw == null || raw.isEmpty) {
      return const ChurchPaymentReceivingConfig();
    }
    return ChurchPaymentReceivingConfig(
      mercadoPagoEnabled: raw['mercadoPagoEnabled'] != false,
      initPayEnabled: raw['initPayEnabled'] == true,
      initPayCheckoutUrl: (raw['initPayCheckoutUrl'] ?? '').toString(),
      initPayPixLink: (raw['initPayPixLink'] ?? '').toString(),
      otherCheckoutUrl: (raw['otherCheckoutUrl'] ?? '').toString(),
      otherProviderName: (raw['otherProviderName'] ?? '').toString(),
    );
  }

  Map<String, dynamic> toMap() => {
        'mercadoPagoEnabled': mercadoPagoEnabled,
        'initPayEnabled': initPayEnabled,
        'initPayCheckoutUrl': initPayCheckoutUrl.trim(),
        'initPayPixLink': initPayPixLink.trim(),
        'otherCheckoutUrl': otherCheckoutUrl.trim(),
        'otherProviderName': otherProviderName.trim(),
        'updatedAt': FieldValue.serverTimestamp(),
      };
}

abstract final class ChurchPaymentReceivingService {
  ChurchPaymentReceivingService._();

  static DocumentReference<Map<String, dynamic>> _ref(String tenantId) =>
      FirebaseFirestore.instance
          .collection('igrejas')
          .doc(tenantId.trim())
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
    await _ref(tenantId).set(cfg.toMap(), SetOptions(merge: true));
  }
}
