import 'store_platform.dart';

/// Normalized state of a purchase or subscription, across both stores.
enum VerificationState {
  /// One-time purchase completed and not refunded/revoked.
  purchased,

  /// Subscription active and renewing (or set to renew).
  active,

  /// Subscription canceled by the user (auto-renew off) — may still be
  /// entitled until [VerificationResult.expiresAt].
  canceled,

  /// Payment failed but the store still grants access (billing grace period).
  gracePeriod,

  /// Payment failed and the store is retrying — no access.
  billingRetry,

  /// Subscription on hold after a failed payment (Google) — no access.
  onHold,

  /// Subscription paused by the user (Google) — no access.
  paused,

  /// Payment not completed yet — no access until it is.
  pending,

  /// Subscription expired.
  expired,

  /// Refunded or revoked by the store.
  revoked,

  /// The store has no record of this token/transaction.
  notFound,

  /// The store returned a state this package does not recognize.
  unknown,
}

/// Result of verifying a purchase or subscription with the store.
class VerificationResult {
  /// Whether the user should be granted access right now.
  final bool isValid;

  /// Normalized state reported by the store.
  final VerificationState state;

  /// Store that answered the verification.
  final StorePlatform platform;

  /// Product identifier, when the store returns it.
  final String? productId;

  /// Subscription expiration (or end of the current period). `null` for
  /// one-time purchases.
  final DateTime? expiresAt;

  /// Whether the subscription will renew automatically. `null` when unknown
  /// or not applicable.
  final bool? willAutoRenew;

  /// Whether the store answered from its sandbox/test environment.
  final bool isSandbox;

  /// Raw decoded store payload, for fields not mapped here.
  final Map<String, dynamic> raw;

  const VerificationResult({
    required this.isValid,
    required this.state,
    required this.platform,
    this.productId,
    this.expiresAt,
    this.willAutoRenew,
    this.isSandbox = false,
    this.raw = const {},
  });

  /// Result for a token/transaction the store does not know.
  const VerificationResult.notFound(this.platform, {this.isSandbox = false})
    : isValid = false,
      state = VerificationState.notFound,
      productId = null,
      expiresAt = null,
      willAutoRenew = null,
      raw = const {};

  @override
  String toString() {
    return 'VerificationResult{isValid: $isValid, state: $state, '
        'platform: $platform, productId: $productId, expiresAt: $expiresAt, '
        'willAutoRenew: $willAutoRenew, isSandbox: $isSandbox}';
  }
}
