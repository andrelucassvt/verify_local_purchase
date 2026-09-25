import 'dart:convert';

import 'package:app_store_server_sdk/app_store_server_sdk.dart';

/// Unsigned compact JWS — the SDK only reads the payload (`unverifiedPayload`).
String fakeJws(Map<String, dynamic> payload) {
  String encode(Object value) =>
      base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=', '');
  return '${encode({'alg': 'ES256'})}.${encode(payload)}.c2ln';
}

Map<String, dynamic> appleTransactionJson({
  String transactionId = 'tx_1',
  String originalTransactionId = 'orig_1',
  String productId = 'premium_monthly',
  int? expiresDate,
  int? revocationDate,
  int? offerType,
}) {
  return {
    'bundleId': 'com.example.app',
    'originalPurchaseDate': 1700000000000,
    'originalTransactionId': originalTransactionId,
    'productId': productId,
    'purchaseDate': 1700000000000,
    'signedDate': 1700000000000,
    'transactionId': transactionId,
    'type': 'Auto-Renewable Subscription',
    'expiresDate': ?expiresDate,
    'revocationDate': ?revocationDate,
    'offerType': ?offerType,
  };
}

LastTransactionsItem appleLastTransaction({
  required int status,
  String originalTransactionId = 'orig_1',
  String productId = 'premium_monthly',
  int? expiresDate,
  int autoRenewStatus = 1,
  int? offerType,
  int? gracePeriodExpiresDate,
}) {
  return LastTransactionsItem(
    originalTransactionId,
    status,
    fakeJws({
      'autoRenewProductId': productId,
      'autoRenewStatus': autoRenewStatus,
      'originalTransactionId': originalTransactionId,
      'productId': productId,
      'signedDate': 1700000000000,
      'offerType': ?offerType,
      'gracePeriodExpiresDate': ?gracePeriodExpiresDate,
    }),
    fakeJws(
      appleTransactionJson(
        originalTransactionId: originalTransactionId,
        productId: productId,
        expiresDate: expiresDate,
        offerType: offerType,
      ),
    ),
  );
}

StatusResponse appleStatusResponse(
  List<List<LastTransactionsItem>> groups, {
  String environment = 'Production',
}) {
  return StatusResponse(environment, null, 'com.example.app', [
    for (var i = 0; i < groups.length; i++)
      SubscriptionGroupIdentifierItem('group_$i', groups[i]),
  ]);
}
