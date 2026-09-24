export 'models/refund_entry.dart';
export 'models/store_platform.dart';
export 'models/verification_result.dart';
export 'models/verify_purchase_config.dart';
export 'models/verify_purchase_exception.dart';
export 'utils/purchase_token_utils.dart';
export 'package:in_app_purchase/in_app_purchase.dart';

import 'package:in_app_purchase/in_app_purchase.dart';

import 'models/refund_entry.dart';
import 'models/verification_result.dart';
import 'models/verify_purchase_config.dart';
import 'models/verify_purchase_exception.dart';
import 'service/verify_purchase_service.dart';
import 'utils/purchase_token_utils.dart';

/// Verifies in-app purchases and subscriptions directly with the
/// App Store Server API and the Google Play Developer API.
///
/// Every method throws [VerifyPurchaseException] on failure.
abstract final class VerifyLocalPurchase {
  static VerifyPurchaseService? _service;

  /// Initialize the verification service with your credentials
  ///
  /// Call this once in your app's main() function before using verification
  /// methods. Calling it again replaces the previous config.
  ///
  /// Example:
  /// ```dart
  /// void main() {
  ///   VerifyLocalPurchase.initialize(
  ///     appleConfig: AppleConfig(
  ///       bundleId: 'com.example.app',
  ///       issuerId: 'your-issuer-id',
  ///       keyId: 'your-key-id',
  ///       privateKey: 'your-private-key',
  ///     ),
  ///     googlePlayConfig: GooglePlayConfig(
  ///       packageName: 'com.example.app',
  ///       serviceAccountJson: 'your-service-account-json',
  ///     ),
  ///   );
  ///   runApp(MyApp());
  /// }
  /// ```
  static void initialize({
    AppleConfig? appleConfig,
    GooglePlayConfig? googlePlayConfig,
    bool enableLogging = false,
  }) {
    _service?.dispose();
    _service = VerifyPurchaseService(
      VerifyPurchaseConfig(
        appleConfig: appleConfig,
        googlePlayConfig: googlePlayConfig,
        enableLogging: enableLogging,
      ),
    );
  }

  /// Releases the cached HTTP clients. [initialize] must be called again
  /// before the next verification.
  static void dispose() {
    _service?.dispose();
    _service = null;
  }

  static VerifyPurchaseService get _requireService {
    final service = _service;
    if (service == null) {
      throw const VerifyPurchaseException(
        VerifyPurchaseErrorCode.notInitialized,
        'VerifyLocalPurchase not initialized. '
        'Call VerifyLocalPurchase.initialize() in your main() function.',
      );
    }
    return service;
  }

  /// Verify a one-time purchase (consumable or non-consumable) on the current
  /// platform's store.
  ///
  /// [VerificationResult.isValid] is `true` if the purchase exists and was not
  /// refunded/revoked.
  ///
  /// For iOS/macOS: [purchaseToken] is the transaction ID.
  /// For Android: [purchaseToken] is the purchase token from Google Play.
  static Future<VerificationResult> verifyPurchase(String purchaseToken) {
    return _requireService.verifyPurchase(purchaseToken);
  }

  /// Verify a subscription on the current platform's store.
  ///
  /// [VerificationResult.isValid] is `true` while the user is entitled:
  /// active, canceled-but-not-expired or in billing grace period.
  ///
  /// For iOS/macOS: [subscriptionToken] is the original transaction ID.
  /// For Android: [subscriptionToken] is the subscription token.
  static Future<VerificationResult> verifySubscription(
    String subscriptionToken,
  ) {
    return _requireService.verifySubscription(subscriptionToken);
  }

  /// Shortcut for [verifyPurchase] that extracts the token with
  /// [getOneTimePurchaseToken].
  static Future<VerificationResult> verifyPurchaseDetails(
    PurchaseDetails purchase,
  ) {
    return verifyPurchase(getOneTimePurchaseToken(purchase));
  }

  /// Shortcut for [verifySubscription] that extracts the token with
  /// [getSubscriptionToken].
  static Future<VerificationResult> verifySubscriptionDetails(
    PurchaseDetails purchase,
  ) {
    return verifySubscription(getSubscriptionToken(purchase));
  }

  /// Verify a one-time purchase directly with the App Store Server API
  ///
  /// [transactionId] is the transaction ID from the App Store
  static Future<VerificationResult> verifyPurchaseWithAppStore(
    String transactionId,
  ) {
    return _requireService.verifyPurchaseWithAppStore(transactionId);
  }

  /// Verify a one-time purchase directly with the Google Play Developer API
  ///
  /// [purchaseToken] is the purchase token from Google Play
  static Future<VerificationResult> verifyPurchaseWithGooglePlay(
    String purchaseToken,
  ) {
    return _requireService.verifyPurchaseWithGooglePlay(purchaseToken);
  }

  /// Verify a subscription directly with the App Store Server API
  ///
  /// [originalTransactionId] is the original transaction ID from the App Store
  static Future<VerificationResult> verifySubscriptionWithAppStore(
    String originalTransactionId,
  ) {
    return _requireService.verifySubscriptionWithAppStore(
      originalTransactionId,
    );
  }

  /// Verify a subscription directly with the Google Play Developer API
  ///
  /// [subscriptionToken] is the subscription token from Google Play
  static Future<VerificationResult> verifySubscriptionWithGooglePlay(
    String subscriptionToken,
  ) {
    return _requireService.verifySubscriptionWithGooglePlay(subscriptionToken);
  }

  /// List refunds for a single customer using the App Store Server API.
  ///
  /// Scope: refunds tied to [originalTransactionId] — one customer at a time.
  /// Requires [AppleConfig] to be set in [initialize].
  static Future<List<RefundEntry>> getRefundsWithAppStore(
    String originalTransactionId,
  ) {
    return _requireService.getRefundsWithAppStore(originalTransactionId);
  }

  /// List refunds for the entire app using the Google Play Developer API.
  ///
  /// Scope: all voided purchases in the app, paginated — not per-customer.
  /// [startTime] and [endTime] are optional; the API defaults to the last 30 days.
  ///
  /// **Note:** [RefundEntry.productId] is always `null` for Google results — the
  /// `voidedpurchases` endpoint does not return the product ID. Cross-reference
  /// [RefundEntry.originalId] (purchaseToken) with another API call if needed.
  ///
  /// Requires the Service Account to have Financial permissions in Play Console.
  static Future<List<RefundEntry>> getRefundsWithGooglePlay({
    DateTime? startTime,
    DateTime? endTime,
  }) {
    return _requireService.getRefundsWithGooglePlay(
      startTime: startTime,
      endTime: endTime,
    );
  }
}
