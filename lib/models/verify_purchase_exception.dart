/// Category of a [VerifyPurchaseException].
enum VerifyPurchaseErrorCode {
  /// `VerifyLocalPurchase.initialize()` was not called.
  notInitialized,

  /// The config for the store being called was not provided.
  missingConfig,

  /// The credentials could not be parsed (malformed JSON / key).
  invalidCredentials,

  /// The store rejected the credentials (HTTP 401/403).
  unauthorized,

  /// The token passed in is empty or could not be extracted.
  invalidToken,

  /// The store returned an error response.
  apiError,

  /// The request did not reach the store (no connection, DNS, timeout).
  networkError,

  /// The store answered with a payload this package could not read.
  invalidResponse,

  /// Any other failure.
  unknown,
}

/// Error thrown by every verification and refund method of this package.
class VerifyPurchaseException implements Exception {
  final VerifyPurchaseErrorCode code;
  final String message;

  /// HTTP status code, when the error came from a store response.
  final int? statusCode;

  /// Store-specific error code (e.g. Apple `4040010`), when available.
  final int? storeErrorCode;

  /// Underlying error, if any.
  final Object? cause;

  const VerifyPurchaseException(
    this.code,
    this.message, {
    this.statusCode,
    this.storeErrorCode,
    this.cause,
  });

  @override
  String toString() {
    final details = [
      if (statusCode != null) 'status: $statusCode',
      if (storeErrorCode != null) 'storeErrorCode: $storeErrorCode',
    ].join(', ');
    return 'VerifyPurchaseException(${code.name}): $message'
        '${details.isEmpty ? '' : ' ($details)'}';
  }
}
