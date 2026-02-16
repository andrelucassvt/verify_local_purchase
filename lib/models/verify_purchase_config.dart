/// Configuration class for Apple App Store and Google Play Store verification
class VerifyPurchaseConfig {
  /// Apple App Store configuration
  final AppleConfig? appleConfig;

  /// Google Play Store configuration
  final GooglePlayConfig? googlePlayConfig;

  VerifyPurchaseConfig({this.appleConfig, this.googlePlayConfig});
}

/// Apple App Store configuration
class AppleConfig {
  /// Your app's bundle identifier (e.g., 'com.example.app')
  final String bundleId;

  /// Your App Store Connect API issuer ID
  final String issuerId;

  /// Your App Store Connect API key ID
  final String keyId;

  /// Your App Store Connect API private key (encrypted or plain)
  final String privateKey;

  /// Whether to use sandbox environment (default: false for production)
  final bool useSandbox;

  AppleConfig({
    required this.bundleId,
    required this.issuerId,
    required this.keyId,
    required this.privateKey,
    this.useSandbox = false,
  });
}

/// Google Play Store configuration
class GooglePlayConfig {
  /// Your app's package name (e.g., 'com.example.app')
  final String packageName;

  /// Your Google Service Account credentials JSON string
  final String serviceAccountJson;

  GooglePlayConfig({
    required this.packageName,
    required this.serviceAccountJson,
  });
}
