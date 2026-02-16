export 'models/verify_purchase_config.dart';
export 'service/verify_purchase_service.dart';

import 'models/verify_purchase_config.dart';
import 'service/verify_purchase_service.dart';

class VerifyLocalPurchase {
  static final _service = VerifyPurchaseService();

  /// Initialize the verification service with your credentials
  ///
  /// Call this once in your app's main() function before using verification methods.
  ///
  /// Example:
  /// ```dart
  /// void main() {
  ///   VerifyLocalPurchase.initialize(
  ///     VerifyPurchaseConfig(
  ///       appleConfig: AppleConfig(
  ///         bundleId: 'com.example.app',
  ///         issuerId: 'your-issuer-id',
  ///         keyId: 'your-key-id',
  ///         privateKey: 'your-private-key',
  ///       ),
  ///       googlePlayConfig: GooglePlayConfig(
  ///         packageName: 'com.example.app',
  ///         serviceAccountJson: 'your-service-account-json',
  ///       ),
  ///     ),
  ///   );
  ///   runApp(MyApp());
  /// }
  /// ```
  static void initialize({
    AppleConfig? appleConfig,
    GooglePlayConfig? googlePlayConfig,
  }) {
    VerifyPurchaseService.initialize(
      appleConfig: appleConfig,
      googlePlayConfig: googlePlayConfig,
    );
  }

  /// Verify a one-time purchase (consumable or non-consumable)
  ///
  /// Returns `true` if the purchase is valid and not refunded.
  ///
  /// For iOS: [purchaseToken] should be the transaction ID
  /// For Android: [purchaseToken] should be the purchase token from Google Play
  Future<bool> verifyPurchase(String purchaseToken) async {
    return _service.verifyPurchase(purchaseToken);
  }

  /// Verify a subscription
  ///
  /// Returns `true` if the subscription is currently active.
  ///
  /// For iOS: [subscriptionToken] should be the original transaction ID
  /// For Android: [subscriptionToken] should be the subscription token from Google Play
  Future<bool> verifySubscription(String subscriptionToken) async {
    return _service.verifySubscription(subscriptionToken);
  }
}
