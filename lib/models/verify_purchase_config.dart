/// Configuration class for Apple App Store and Google Play Store verification
class VerifyPurchaseConfig {
  /// Apple App Store configuration
  final AppleConfig? appleConfig;

  /// Google Play Store configuration
  final GooglePlayConfig? googlePlayConfig;

  /// Prints debug logs (with masked tokens). Off by default.
  final bool enableLogging;

  const VerifyPurchaseConfig({
    this.appleConfig,
    this.googlePlayConfig,
    this.enableLogging = false,
  });
}

/// Which App Store Server API environment to query.
enum AppleEnvironment {
  /// Production only.
  production,

  /// Sandbox only (Xcode / StoreKit sandbox testing).
  sandbox,

  /// Production first; on "transaction not found" retries in sandbox.
  ///
  /// Recommended by Apple: App Review and TestFlight purchases happen in
  /// sandbox even for production builds.
  productionWithSandboxFallback,
}

/// Apple App Store configuration
class AppleConfig {
  /// Your app's bundle identifier (e.g., 'com.example.app')
  final String bundleId;

  /// Your App Store Connect API issuer ID
  final String issuerId;

  /// Your App Store Connect API key ID
  final String keyId;

  /// Your App Store Connect API private key (content of the .p8 file)
  final String privateKey;

  /// Environment to query (default: production with sandbox fallback)
  final AppleEnvironment environment;

  const AppleConfig({
    required this.bundleId,
    required this.issuerId,
    required this.keyId,
    required this.privateKey,
    this.environment = AppleEnvironment.productionWithSandboxFallback,
  });
}

/// Google Play Store configuration
class GooglePlayConfig {
  /// Your app's package name (e.g., 'com.example.app')
  final String packageName;

  /// Your Google Service Account credentials JSON string
  final String serviceAccountJson;

  const GooglePlayConfig({
    required this.packageName,
    required this.serviceAccountJson,
  });
}
