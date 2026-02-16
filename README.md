# verify_local_purchase

A Flutter package for verifying in-app purchases and subscriptions **locally on device** with Apple App Store and Google Play Store. This package allows you to validate purchases without the need for a backend server.

[![pub package](https://img.shields.io/pub/v/verify_local_purchase.svg)](https://pub.dev/packages/verify_local_purchase)

## 📚 Documentation

- 🚀 [Quick Start Guide](QUICKSTART.md) - Get started in 5 minutes
- 🔑 [Credentials Guide](CREDENTIALS_GUIDE.md) - How to get API credentials
- 🔒 [Security Best Practices](example/SECURITY.md) - Secure credential storage
- 🔗 [Integration Examples](example/INTEGRATION_EXAMPLES.md) - Usage with popular packages
- 📦 [Publishing Guide](PUBLISHING.md) - How to publish to pub.dev

## Features

✅ **Local verification** - Verify purchases directly from your Flutter app  
🍎 **Apple App Store** - Support for iOS and macOS in-app purchases and subscriptions  
🤖 **Google Play Store** - Support for Android in-app purchases and subscriptions  
🔒 **Secure** - Uses official Apple and Google APIs for verification  
⚡ **Easy to use** - Simple initialization and verification methods  

## Installation

Add this to your package's `pubspec.yaml` file:

```yaml
dependencies:
  verify_local_purchase: ^0.0.1
```

Then run:

```bash
flutter pub get
```

## Setup

### Apple App Store (iOS/macOS)

1. **Create an App Store Connect API Key**:
   - Go to [App Store Connect](https://appstoreconnect.apple.com/)
   - Navigate to Users and Access > Keys
   - Create a new API key with "App Manager" role
   - Download the `.p8` private key file
   - Note your **Issuer ID** and **Key ID**

2. **Read your private key**:
   ```dart
   final privateKey = await File('path/to/AuthKey_XXXXXX.p8').readAsString();
   ```

### Google Play Store (Android)

1. **Create a Service Account**:
   - Go to [Google Cloud Console](https://console.cloud.google.com/)
   - Create a new service account or use an existing one
   - Grant it the "Androidpublisher" role
   - Create a JSON key and download it

2. **Link Service Account to Google Play Console**:
   - Go to [Google Play Console](https://play.google.com/console/)
   - Navigate to Setup > API access
   - Link the service account you created
   - Grant "View financial data" and "Manage orders" permissions

3. **Read your service account JSON**:
   ```dart
   final serviceAccountJson = await File('path/to/service-account.json').readAsString();
   ```

## Usage

### 1. Initialize the package

Initialize the package in your app's `main()` function **before** calling `runApp()`:

```dart
import 'package:flutter/material.dart';
import 'package:verify_local_purchase/verify_local_purchase.dart';

void main() {
  // Initialize the verification service
  VerifyLocalPurchase.initialize(
    VerifyPurchaseConfig(
      appleConfig: AppleConfig(
        bundleId: 'com.example.app',
        issuerId: 'xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx',
        keyId: 'XXXXXXXXXX',
        privateKey: '''-----BEGIN PRIVATE KEY-----
YOUR_PRIVATE_KEY_CONTENT_HERE
-----END PRIVATE KEY-----''',
        useSandbox: false, // Set to true for testing
      ),
      googlePlayConfig: GooglePlayConfig(
        packageName: 'com.example.app',
        serviceAccountJson: '''
{
  "type": "service_account",
  "project_id": "your-project",
  "private_key_id": "xxxxx",
  "private_key": "-----BEGIN PRIVATE KEY-----\\nYOUR_KEY\\n-----END PRIVATE KEY-----\\n",
  "client_email": "your-service-account@your-project.iam.gserviceaccount.com",
  "client_id": "xxxxx",
  ...
}''',
      ),
    ),
  );

  runApp(MyApp());
}
```

### 2. Verify a one-time purchase

```dart
final verifyPurchase = VerifyLocalPurchase();

try {
  // For iOS: transactionId from StoreKit
  // For Android: purchaseToken from Google Play Billing
  final isValid = await verifyPurchase.verifyPurchase(purchaseToken);
  
  if (isValid) {
    print('✅ Purchase is valid!');
    // Grant access to the purchased content
  } else {
    print('❌ Purchase is invalid or refunded');
  }
} catch (e) {
  print('Error verifying purchase: $e');
}
```

### 3. Verify a subscription

```dart
final verifyPurchase = VerifyLocalPurchase();

try {
  // For iOS: originalTransactionId from StoreKit
  // For Android: subscriptionToken from Google Play Billing
  final isActive = await verifyPurchase.verifySubscription(subscriptionToken);
  
  if (isActive) {
    print('✅ Subscription is active!');
    // Grant access to premium features
  } else {
    print('❌ Subscription is expired or canceled');
  }
} catch (e) {
  print('Error verifying subscription: $e');
}
```

## Configuration Options

### AppleConfig

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `bundleId` | String | ✅ | Your app's bundle identifier (e.g., 'com.example.app') |
| `issuerId` | String | ✅ | App Store Connect API Issuer ID |
| `keyId` | String | ✅ | App Store Connect API Key ID |
| `privateKey` | String | ✅ | App Store Connect API Private Key (.p8 file content) |
| `useSandbox` | bool | ❌ | Use sandbox environment for testing (default: false) |

### GooglePlayConfig

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `packageName` | String | ✅ | Your app's package name (e.g., 'com.example.app') |
| `serviceAccountJson` | String | ✅ | Google Service Account JSON credentials |

## Platform-specific notes

### iOS/macOS
- Uses the [App Store Server API](https://developer.apple.com/documentation/appstoreserverapi)
- Requires an App Store Connect API Key
- Supports both production and sandbox environments
- Returns `false` if the purchase was refunded

### Android
- Uses the [Google Play Developer API](https://developers.google.com/android-publisher)
- Requires a Google Service Account with proper permissions
- Automatically handles OAuth2 authentication
- Returns `false` if the purchase is canceled or pending

## Security Considerations

⚠️ **Important**: While this package allows local verification, it's recommended to also implement server-side verification for production apps to prevent tampering.

**Best practices**:
1. Store your credentials securely (never commit them to version control)
2. Use environment variables or secure storage for credentials
3. Consider encrypting credentials if storing them in your app
4. Implement additional server-side verification for critical purchases
5. Use ProGuard/R8 on Android to obfuscate your code

## Example

See the [example](example/) directory for a complete working example.

## Troubleshooting

### Apple App Store

**Error: "App Store API error (code: 4040010)"**
- The transaction ID doesn't exist or is invalid
- Make sure you're using the correct environment (sandbox vs production)

**Error: "Invalid JWT"**
- Check that your API credentials are correct
- Ensure the private key includes the header and footer lines

### Google Play Store

**Error: "Failed to verify purchase: 401"**
- Service account doesn't have proper permissions
- Make sure the service account is linked in Google Play Console

**Error: "Failed to verify purchase: 404"**
- The purchase token doesn't exist
- Check that the package name is correct

## License

MIT License - see [LICENSE](LICENSE) file for details.

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## Support

For issues and feature requests, please use the [issue tracker](https://github.com/yourusername/verify_local_purchase/issues).