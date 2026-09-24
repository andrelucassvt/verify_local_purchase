import 'dart:convert';
import 'dart:io';

import 'package:in_app_purchase/in_app_purchase.dart';

import '../models/verify_purchase_exception.dart';

/// Returns the token for a ONE-TIME purchase (consumable or non-consumable)
/// to be used with [VerifyLocalPurchase.verifyPurchase].
///
/// - **iOS/macOS**: returns `purchase.purchaseID` (the transaction ID).
/// - **Android**: returns `purchase.verificationData.serverVerificationData`
///   (the purchase token).
///
/// Throws [VerifyPurchaseException] with
/// [VerifyPurchaseErrorCode.invalidToken] if the token is missing.
///
/// Example:
/// ```dart
/// final token = getOneTimePurchaseToken(purchase);
/// final result = await VerifyLocalPurchase.verifyPurchase(token);
/// ```
String getOneTimePurchaseToken(PurchaseDetails purchase) {
  final token = (Platform.isIOS || Platform.isMacOS)
      // iOS/macOS: use the transactionId (purchaseID)
      ? purchase.purchaseID
      // Android: use serverVerificationData (contains the purchaseToken)
      : purchase.verificationData.serverVerificationData;
  return _requireToken(token, 'purchase token');
}

/// Returns the token for a SUBSCRIPTION to be used with
/// [VerifyLocalPurchase.verifySubscription].
///
/// - **iOS/macOS**: parses `localVerificationData` JSON to extract
///   `originalTransactionId`, which is stable across renewals and restores.
/// - **Android**: returns `purchase.verificationData.serverVerificationData`
///   (the subscription token).
///
/// Throws [VerifyPurchaseException] with
/// [VerifyPurchaseErrorCode.invalidToken] if the token is missing.
///
/// Example:
/// ```dart
/// final token = getSubscriptionToken(purchase);
/// final result = await VerifyLocalPurchase.verifySubscription(token);
/// ```
String getSubscriptionToken(PurchaseDetails purchase) {
  if (Platform.isIOS || Platform.isMacOS) {
    // iOS/macOS: parse localVerificationData JSON to get originalTransactionId
    // The originalTransactionId is stable across renewals and restores
    String? originalTransactionId;
    try {
      final data = jsonDecode(purchase.verificationData.localVerificationData);
      if (data is Map) {
        originalTransactionId = data['originalTransactionId']?.toString();
      }
    } on FormatException {
      originalTransactionId = null;
    }
    return _requireToken(originalTransactionId, 'originalTransactionId');
  }
  // Android: use serverVerificationData (contains the subscriptionToken)
  return _requireToken(
    purchase.verificationData.serverVerificationData,
    'subscription token',
  );
}

String _requireToken(String? token, String name) {
  if (token == null || token.isEmpty) {
    throw VerifyPurchaseException(
      VerifyPurchaseErrorCode.invalidToken,
      'Could not extract the $name from PurchaseDetails',
    );
  }
  return token;
}
