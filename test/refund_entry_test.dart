import 'package:app_store_server_sdk/app_store_server_sdk.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:verify_local_purchase/models/refund_entry.dart';

void main() {
  group('RefundEntry.fromGoogleVoidedPurchase', () {
    test('maps all fields correctly', () {
      final json = <String, dynamic>{
        'orderId': 'GPA.1234',
        'purchaseToken': 'tok_abc',
        'voidedTimeMillis': 1700000000000,
        'voidedReason': 3,
      };

      final entry = RefundEntry.fromGoogleVoidedPurchase(json);

      expect(entry.platform, RefundPlatform.google);
      expect(entry.transactionId, 'GPA.1234');
      expect(entry.originalId, 'tok_abc');
      expect(entry.productId, isNull);
      expect(
        entry.refundDate,
        DateTime.fromMillisecondsSinceEpoch(1700000000000),
      );
      expect(entry.reasonCode, 3);
      expect(entry.raw, json);
    });

    test('handles voidedTimeMillis as String defensively', () {
      final json = <String, dynamic>{
        'orderId': 'GPA.5678',
        'purchaseToken': 'tok_def',
        'voidedTimeMillis': '1700000000000',
        'voidedReason': 0,
      };

      final entry = RefundEntry.fromGoogleVoidedPurchase(json);

      expect(
        entry.refundDate,
        DateTime.fromMillisecondsSinceEpoch(1700000000000),
      );
    });

    test('reasonCode is null when voidedReason is absent', () {
      final json = <String, dynamic>{
        'orderId': 'GPA.9999',
        'purchaseToken': 'tok_xyz',
        'voidedTimeMillis': 1700000000000,
      };

      final entry = RefundEntry.fromGoogleVoidedPurchase(json);

      expect(entry.reasonCode, isNull);
    });
  });

  group('RefundEntry.fromAppleTransaction', () {
    JWSTransactionDecodedPayload makePayload({
      String transactionId = 'tx_apple_001',
      String originalTransactionId = 'orig_tx_001',
      String productId = 'com.example.premium',
      int? revocationDate = 1700000000000,
    }) {
      return JWSTransactionDecodedPayload(
        null, // appAccountToken
        'com.example.app', // bundleId
        null, // expiresDate
        null, // inAppOwnershipType
        null, // isUpgraded
        null, // offerIdentifier
        null, // offerType
        1699000000000, // originalPurchaseDate
        originalTransactionId,
        productId,
        1699000000000, // purchaseDate
        null, // quantity
        revocationDate,
        1700000001000, // signedDate
        null, // subscriptionGroupIdentifier
        transactionId,
        'Non-Consumable', // type
        null, // webOrderLineItemId
      );
    }

    test('maps all fields correctly', () {
      final tx = makePayload();

      final entry = RefundEntry.fromAppleTransaction(tx);

      expect(entry.platform, RefundPlatform.apple);
      expect(entry.transactionId, 'tx_apple_001');
      expect(entry.originalId, 'orig_tx_001');
      expect(entry.productId, 'com.example.premium');
      expect(
        entry.refundDate,
        DateTime.fromMillisecondsSinceEpoch(1700000000000),
      );
      // SDK 1.2.10 does not expose revocationReason
      expect(entry.reasonCode, isNull);
    });

    test('raw map contains transactionId', () {
      final tx = makePayload();

      final entry = RefundEntry.fromAppleTransaction(tx);

      expect(entry.raw['transactionId'], 'tx_apple_001');
    });
  });
}
