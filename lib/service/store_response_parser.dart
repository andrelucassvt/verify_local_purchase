import 'package:app_store_server_sdk/app_store_server_sdk.dart';

import '../models/refund_entry.dart';
import '../models/store_platform.dart';
import '../models/verification_result.dart';
import 'apple_jws_payload.dart';

/// Pure functions that turn store responses into [VerificationResult].
///
/// No network or global state here — everything the decision depends on is
/// passed in, so each rule can be unit tested.
class StoreResponseParser {
  const StoreResponseParser._();

  // App Store subscription status values.
  // https://developer.apple.com/documentation/appstoreserverapi/status
  static const _appleActive = 1;
  static const _appleExpired = 2;
  static const _appleBillingRetry = 3;
  static const _appleGracePeriod = 4;
  static const _appleRevoked = 5;

  /// Order used to pick the most relevant subscription when there are several.
  static const _appleStatusRank = {
    _appleActive: 5,
    _appleGracePeriod: 4,
    _appleBillingRetry: 3,
    _appleExpired: 2,
    _appleRevoked: 1,
  };

  /// Parses `getAllSubscriptionStatuses`.
  ///
  /// Looks at every subscription group, preferring the entries whose
  /// `originalTransactionId` matches [originalTransactionId]; if none match,
  /// considers all of the customer's subscriptions. Among the candidates, the
  /// best status wins (active > grace period > billing retry > expired >
  /// revoked), then the latest expiration.
  static VerificationResult appleSubscription(
    StatusResponse response,
    String originalTransactionId,
  ) {
    final isSandbox = _isAppleSandbox(response.environment);
    final all = [for (final group in response.data) ...group.lastTransactions];
    if (all.isEmpty) {
      return VerificationResult.notFound(
        StorePlatform.apple,
        isSandbox: isSandbox,
      );
    }

    final matching = all
        .where((item) => item.originalTransactionId == originalTransactionId)
        .toList();
    final candidates = matching.isNotEmpty ? matching : all;

    final decoded = [
      for (final item in candidates)
        (
          item: item,
          tx: AppleJwsPayload.decode(item.signedTransactionInfo),
          renewal: _renewalOf(item),
        ),
    ];
    decoded.sort((a, b) {
      final byRank = (_appleStatusRank[b.item.status] ?? 0).compareTo(
        _appleStatusRank[a.item.status] ?? 0,
      );
      if (byRank != 0) return byRank;
      return (b.tx.expiresDate ?? 0).compareTo(a.tx.expiresDate ?? 0);
    });

    final best = decoded.first;
    final autoRenewStatus = best.renewal?.autoRenewStatus;
    final willAutoRenew = autoRenewStatus == null ? null : autoRenewStatus == 1;

    final VerificationState state;
    switch (best.item.status) {
      case _appleActive:
        state = willAutoRenew == false
            ? VerificationState.canceled
            : VerificationState.active;
      case _appleGracePeriod:
        state = VerificationState.gracePeriod;
      case _appleBillingRetry:
        state = VerificationState.billingRetry;
      case _appleExpired:
        state = VerificationState.expired;
      case _appleRevoked:
        state = VerificationState.revoked;
      default:
        state = VerificationState.unknown;
    }

    return VerificationResult(
      isValid:
          best.item.status == _appleActive ||
          best.item.status == _appleGracePeriod,
      state: state,
      platform: StorePlatform.apple,
      productId: best.tx.productId,
      expiresAt: _fromMillis(best.tx.expiresDate),
      willAutoRenew: willAutoRenew,
      isSandbox: isSandbox,
      raw: {
        'status': best.item.status,
        'transaction': best.tx.json,
        if (best.renewal != null) 'renewalInfo': best.renewal!.json,
      },
    );
  }

  /// Parses a single decoded transaction from `getTransactionHistory`.
  static VerificationResult appleTransaction(
    AppleJwsPayload tx, {
    required String environment,
  }) {
    final revoked = tx.revocationDate != null;
    return VerificationResult(
      isValid: !revoked,
      state: revoked ? VerificationState.revoked : VerificationState.purchased,
      platform: StorePlatform.apple,
      productId: tx.productId,
      expiresAt: _fromMillis(tx.expiresDate),
      isSandbox: _isAppleSandbox(environment),
      raw: tx.json,
    );
  }

  /// Maps a transaction from `getRefundHistory` to a [RefundEntry].
  static RefundEntry appleRefund(AppleJwsPayload tx) {
    return RefundEntry(
      platform: StorePlatform.apple,
      transactionId: tx.transactionId ?? '',
      originalId: tx.originalTransactionId ?? '',
      productId: tx.productId,
      refundDate: DateTime.fromMillisecondsSinceEpoch(tx.revocationDate ?? 0),
      raw: tx.json,
    );
  }

  static const _googleSubscriptionStates = {
    'SUBSCRIPTION_STATE_ACTIVE': VerificationState.active,
    'SUBSCRIPTION_STATE_CANCELED': VerificationState.canceled,
    'SUBSCRIPTION_STATE_IN_GRACE_PERIOD': VerificationState.gracePeriod,
    'SUBSCRIPTION_STATE_ON_HOLD': VerificationState.onHold,
    'SUBSCRIPTION_STATE_PAUSED': VerificationState.paused,
    'SUBSCRIPTION_STATE_EXPIRED': VerificationState.expired,
    'SUBSCRIPTION_STATE_PENDING': VerificationState.pending,
    'SUBSCRIPTION_STATE_PENDING_PURCHASE_CANCELED': VerificationState.canceled,
  };

  /// Parses `purchases.subscriptionsv2.get`.
  ///
  /// Valid when the state grants access (active, canceled or grace period)
  /// **and** the latest line item has not expired yet. A canceled
  /// subscription keeps access until `expiryTime`; a pending one does not.
  static VerificationResult googleSubscription(
    Map<String, dynamic> json, {
    required DateTime now,
  }) {
    final state =
        _googleSubscriptionStates[json['subscriptionState']] ??
        VerificationState.unknown;

    final lineItems = (json['lineItems'] as List<dynamic>? ?? [])
        .cast<Map<String, dynamic>>();
    Map<String, dynamic>? latest;
    DateTime? expiresAt;
    for (final item in lineItems) {
      final expiry = DateTime.tryParse(item['expiryTime'] as String? ?? '');
      if (latest == null ||
          (expiry != null &&
              (expiresAt == null || expiry.isAfter(expiresAt)))) {
        latest = item;
        expiresAt = expiry;
      }
    }

    final grantsAccess =
        state == VerificationState.active ||
        state == VerificationState.canceled ||
        state == VerificationState.gracePeriod;
    final notExpired = expiresAt == null
        ? state != VerificationState.canceled
        : expiresAt.isAfter(now);

    final autoRenewingPlan = latest?['autoRenewingPlan'] as Map?;
    final bool? willAutoRenew = autoRenewingPlan != null
        ? autoRenewingPlan['autoRenewEnabled'] as bool? ?? false
        : (latest?['prepaidPlan'] != null ? false : null);

    return VerificationResult(
      isValid: grantsAccess && notExpired,
      state: state,
      platform: StorePlatform.google,
      productId: latest?['productId'] as String?,
      expiresAt: expiresAt,
      willAutoRenew: willAutoRenew,
      isSandbox: json.containsKey('testPurchase'),
      raw: json,
    );
  }

  /// Parses `purchases.productsv2.getproductpurchasev2`.
  static VerificationResult googleProduct(Map<String, dynamic> json) {
    final purchaseState =
        (json['purchaseStateContext'] as Map?)?['purchaseState'] as String?;

    final VerificationState state;
    switch (purchaseState) {
      case 'PURCHASED':
        state = VerificationState.purchased;
      case 'PENDING':
        state = VerificationState.pending;
      case 'CANCELLED' || 'CANCELED':
        state = VerificationState.revoked;
      default:
        state = VerificationState.unknown;
    }

    final lineItems = json['productLineItem'] as List<dynamic>? ?? [];
    final productId = lineItems.isEmpty
        ? null
        : (lineItems.first as Map)['productId'] as String?;

    return VerificationResult(
      isValid: state == VerificationState.purchased,
      state: state,
      platform: StorePlatform.google,
      productId: productId,
      isSandbox: json.containsKey('testPurchaseContext'),
      raw: json,
    );
  }

  static AppleJwsPayload? _renewalOf(LastTransactionsItem item) {
    if (item.signedRenewalInfo.isEmpty) return null;
    try {
      return AppleJwsPayload.decode(item.signedRenewalInfo);
    } catch (_) {
      return null;
    }
  }

  static bool _isAppleSandbox(String environment) =>
      environment.toLowerCase() == 'sandbox';

  static DateTime? _fromMillis(int? millis) =>
      millis == null ? null : DateTime.fromMillisecondsSinceEpoch(millis);
}
