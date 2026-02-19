import 'dart:convert';
import 'dart:io';

import 'package:in_app_purchase/in_app_purchase.dart';

/// Returns the token for a ONE-TIME purchase (consumable or non-consumable)
/// to be used with [VerifyLocalPurchase.verifyPurchase].
///
/// - **iOS/macOS**: returns `purchase.purchaseID` (the transaction ID).
/// - **Android**: returns `purchase.verificationData.serverVerificationData`
///   (the purchase token).
///
/// Example:
/// ```dart
/// final token = getOneTimePurchaseToken(purchase);
/// final isValid = await VerifyLocalPurchase().verifyPurchase(token);
/// ```
String getOneTimePurchaseToken(PurchaseDetails purchase) {
  if (Platform.isIOS || Platform.isMacOS) {
    // iOS/macOS: use the transactionId (purchaseID)
    return purchase.purchaseID ?? '';
  } else {
    // Android: use serverVerificationData (contains the purchaseToken)
    return purchase.verificationData.serverVerificationData;
  }
}

/// Returns the token for a SUBSCRIPTION to be used with
/// [VerifyLocalPurchase.verifySubscription].
///
/// - **iOS/macOS**: parses `localVerificationData` JSON to extract
///   `originalTransactionId`, which is stable across renewals and restores.
/// - **Android**: returns `purchase.verificationData.serverVerificationData`
///   (the subscription token).
///
/// Example:
/// ```dart
/// final token = getSubscriptionToken(purchase);
/// final isActive = await VerifyLocalPurchase().verifySubscription(token);
/// ```
String getSubscriptionToken(PurchaseDetails purchase) {
  if (Platform.isIOS || Platform.isMacOS) {
    // iOS/macOS: parse localVerificationData JSON to get originalTransactionId
    // The originalTransactionId is stable across renewals and restores
    final data = jsonDecode(purchase.verificationData.localVerificationData);
    return data['originalTransactionId'] as String;
  } else {
    // Android: use serverVerificationData (contains the subscriptionToken)
    return purchase.verificationData.serverVerificationData;
  }
}
