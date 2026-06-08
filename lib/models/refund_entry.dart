import 'package:app_store_server_sdk/app_store_server_sdk.dart';

enum RefundPlatform { apple, google }

class RefundEntry {
  final RefundPlatform platform;

  /// For Apple: transactionId. For Google: orderId.
  final String transactionId;

  /// For Apple: originalTransactionId. For Google: purchaseToken.
  final String originalId;

  /// For Apple: productId from the transaction payload.
  /// For Google: always null — voidedpurchases endpoint does not return productId.
  final String? productId;

  final DateTime refundDate;

  /// For Apple: always null — SDK 1.2.10 does not expose revocationReason.
  /// For Google: voidedReason (0–7).
  final int? reasonCode;

  final Map<String, dynamic> raw;

  const RefundEntry({
    required this.platform,
    required this.transactionId,
    required this.originalId,
    this.productId,
    required this.refundDate,
    this.reasonCode,
    required this.raw,
  });

  factory RefundEntry.fromGoogleVoidedPurchase(Map<String, dynamic> json) {
    final rawMillis = json['voidedTimeMillis'];
    final millis = rawMillis is int
        ? rawMillis
        : int.tryParse(rawMillis?.toString() ?? '') ?? 0;

    return RefundEntry(
      platform: RefundPlatform.google,
      transactionId: json['orderId'] as String,
      originalId: json['purchaseToken'] as String,
      productId: null,
      refundDate: DateTime.fromMillisecondsSinceEpoch(millis),
      reasonCode: json['voidedReason'] as int?,
      raw: json,
    );
  }

  factory RefundEntry.fromAppleTransaction(JWSTransactionDecodedPayload tx) {
    return RefundEntry(
      platform: RefundPlatform.apple,
      transactionId: tx.transactionId,
      originalId: tx.originalTransactionId,
      productId: tx.productId,
      refundDate: DateTime.fromMillisecondsSinceEpoch(tx.revocationDate ?? 0),
      reasonCode: null,
      raw: tx.toJson(),
    );
  }

  @override
  String toString() {
    return 'RefundEntry{platform: $platform, transactionId: $transactionId, '
        'originalId: $originalId, productId: $productId, '
        'refundDate: $refundDate, reasonCode: $reasonCode}';
  }
}
