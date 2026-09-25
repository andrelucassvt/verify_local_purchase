import 'dart:convert';

/// Payload of a signed App Store JWS (transaction or renewal info).
///
/// Decoded here instead of with the SDK's `JWSTransactionDecodedPayload` /
/// `JWSRenewalInfoDecodedPayload`: their generated casts don't match what
/// Apple sends (e.g. `offerType` and `gracePeriodExpiresDate` are numbers),
/// so any purchase with an introductory offer or free trial threw a
/// `TypeError`. Fields are read leniently and only the ones we need.
///
/// Like the SDK, the signature is not verified — the payload comes straight
/// from the App Store Server API over an authenticated connection.
class AppleJwsPayload {
  final Map<String, dynamic> json;

  const AppleJwsPayload(this.json);

  /// Decodes the payload segment of a compact JWS.
  ///
  /// Throws [FormatException] when [jws] is not a valid compact JWS.
  factory AppleJwsPayload.decode(String jws) {
    final parts = jws.split('.');
    if (parts.length != 3) {
      throw const FormatException('Invalid JWS: expected 3 segments');
    }
    final payload = jsonDecode(
      utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))),
    );
    if (payload is! Map<String, dynamic>) {
      throw const FormatException('Invalid JWS: payload is not an object');
    }
    return AppleJwsPayload(payload);
  }

  String? get transactionId => _string('transactionId');
  String? get originalTransactionId => _string('originalTransactionId');
  String? get productId => _string('productId');

  /// Milliseconds since epoch.
  int? get expiresDate => _int('expiresDate');

  /// Milliseconds since epoch.
  int? get revocationDate => _int('revocationDate');

  /// Renewal info only: 1 = will renew, 0 = turned off.
  int? get autoRenewStatus => _int('autoRenewStatus');

  String? _string(String key) => json[key]?.toString();

  int? _int(String key) {
    final value = json[key];
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value);
    return null;
  }
}
