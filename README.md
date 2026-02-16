# verify_local_purchase

A Flutter package for verifying in-app purchases and subscriptions **locally on device** with Apple App Store and Google Play Store. This package allows you to validate purchases without the need for a backend server.

[![pub package](https://img.shields.io/pub/v/verify_local_purchase.svg)](https://pub.dev/packages/verify_local_purchase)

## Features

✅ **Local verification** - Verify purchases directly from your Flutter app  
🍎 **Apple App Store** - Support for iOS and macOS in-app purchases and subscriptions  
🤖 **Google Play Store** - Support for Android in-app purchases and subscriptions  
🔒 **Secure** - Uses official Apple and Google APIs for verification  
⚡ **Easy to use** - Simple initialization and verification methods  

## 🔑 Getting Credentials

Before using this package, you need to get API credentials from each platform:

### 🍎 Apple App Store (iOS/macOS)

1. Go to [App Store Connect](https://appstoreconnect.apple.com/)
2. Navigate to **Users and Access** > **Keys**
3. Click the **+** button to create a new key
4. Name it (e.g., "In-App Purchase Verification")
5. Select **App Manager** role
6. Click **Generate**
7. **Download** the `.p8` file (you can only do this once!)
8. Note down your **Issuer ID** (at the top) and **Key ID**

**You'll need:**
- ✅ Issuer ID (UUID format)
- ✅ Key ID (10 characters)
- ✅ Private Key (content of the .p8 file)
- ✅ Bundle ID (from your Xcode project)

### 🤖 Google Play Store (Android)

1. Go to [Google Cloud Console](https://console.cloud.google.com/)
2. Select your project (or create one)
3. Navigate to **IAM & Admin** > **Service Accounts**
4. Click **Create Service Account**
5. Name it (e.g., "In-App Purchase Verifier")
6. Grant role: **Pub/Sub** > **Pub/Sub Editor** (or create custom role)
7. Click **Done**
8. Click on the created service account
9. Go to **Keys** tab > **Add Key** > **Create new key**
10. Choose **JSON** format and click **Create**
11. The JSON file will be downloaded automatically

**Now link it to Google Play:**

12. Go to [Google Play Console](https://play.google.com/console/)
13. Navigate to **Setup** > **API access**
14. Click **Link** next to your service account
15. Grant permissions: **View financial data** and **Manage orders**
16. Click **Invite user** and then **Invite user** again

**You'll need:**
- ✅ Service Account JSON file (entire content)
- ✅ Package Name (from your build.gradle)

## Installation

Add this to your `pubspec.yaml`:

```yaml
dependencies:
  verify_local_purchase: ^0.0.1
  in_app_purchase: ^3.2.0  # For handling purchases
```

Run:

```bash
flutter pub get
```

## Complete Example

Here's a complete working example of how to use this package with the `in_app_purchase` plugin:

```dart
import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:verify_local_purchase/verify_local_purchase.dart';

void main() {
  // 🔑 Initialize with your credentials
  VerifyLocalPurchase.initialize(
    appleConfig: AppleConfig(
      bundleId: 'com.example.app',
      issuerId: 'your-issuer-id-here',
      keyId: 'your-key-id-here',
      privateKey: '''-----BEGIN PRIVATE KEY-----
YOUR_PRIVATE_KEY_CONTENT_HERE
-----END PRIVATE KEY-----''',
      useSandbox: true,
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
  "client_id": "xxxxx"
}''',
    ),
  );

  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  final InAppPurchase _inAppPurchase = InAppPurchase.instance;
  final VerifyLocalPurchase _verifyPurchase = VerifyLocalPurchase();
  
  StreamSubscription<List<PurchaseDetails>>? _subscription;
  List<ProductDetails> _products = [];

  @override
  void initState() {
    super.initState();
    // Listen to purchase updates
    _subscription = _inAppPurchase.purchaseStream.listen(_onPurchaseUpdate);
    _loadProducts();
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  Future<void> _loadProducts() async {
    // Check if purchases are available
    final available = await _inAppPurchase.isAvailable();
    if (!available) return;

    // Load your product IDs
    const productIds = {'tokens_100', 'premium_monthly'};
    final response = await _inAppPurchase.queryProductDetails(productIds);
    
    setState(() {
      _products = response.productDetails;
    });
  }

  Future<void> _buyProduct(ProductDetails product) async {
    final purchaseParam = PurchaseParam(productDetails: product);
    await _inAppPurchase.buyConsumable(purchaseParam: purchaseParam);
  }

  Future<void> _onPurchaseUpdate(List<PurchaseDetails> purchases) async {
    for (final purchase in purchases) {
      if (purchase.status == PurchaseStatus.purchased ||
          purchase.status == PurchaseStatus.restored) {
        // ✅ Verify the purchase
        await _verifyAndComplete(purchase);
      } else if (purchase.status == PurchaseStatus.error) {
        // ❌ Handle error
        print('Error: ${purchase.error?.message}');
        if (purchase.pendingCompletePurchase) {
          await _inAppPurchase.completePurchase(purchase);
        }
      }
    }
  }

  Future<void> _verifyAndComplete(PurchaseDetails purchase) async {
    try {
      // Get the verification token
      String token;
      if (Platform.isIOS) {
        // ⚠️ For subscriptions, use localVerificationData to get originalTransactionId
        // For one-time purchases, use purchaseID
        token = purchase.purchaseID ?? '';
      } else {
        // Android: Always use serverVerificationData
        token = purchase.verificationData.serverVerificationData;
      }

      // 🔐 Verify the purchase locally
      final isValid = await _verifyPurchase.verifyPurchase(token);

      if (isValid) {
        // ✅ Purchase is valid - grant access
        print('✅ Purchase verified successfully!');
        // TODO: Grant access to purchased content
        
        // Complete the purchase
        if (purchase.pendingCompletePurchase) {
          await _inAppPurchase.completePurchase(purchase);
        }
      } else {
        // ❌ Purchase is invalid or refunded
        print('❌ Purchase verification failed');
      }
    } catch (e) {
      print('❌ Error verifying purchase: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(title: const Text('In-App Purchase Example')),
        body: ListView.builder(
          itemCount: _products.length,
          itemBuilder: (context, index) {
            final product = _products[index];
            return ListTile(
              title: Text(product.title),
              subtitle: Text(product.description),
              trailing: ElevatedButton(
                onPressed: () => _buyProduct(product),
                child: Text(product.price),
              ),
            );
          },
        ),
      ),
    );
  }
}
```

## Quick Reference

### Verify a One-Time Purchase

```dart
final verifyPurchase = VerifyLocalPurchase();

// iOS: use transactionId
// Android: use purchaseToken
final isValid = await verifyPurchase.verifyPurchase(token);

if (isValid) {
  // ✅ Grant access to purchased content
} else {
  // ❌ Purchase is invalid or refunded
}
```

### Verify a Subscription

```dart
final verifyPurchase = VerifyLocalPurchase();

// iOS: use originalTransactionId from localVerificationData
// Android: use serverVerificationData
final isActive = await verifyPurchase.verifySubscription(token);

if (isActive) {
  // ✅ Grant access to premium features
} else {
  // ❌ Subscription is expired or canceled
}
```

**📱 Getting the correct token for subscriptions:**

```dart
import 'dart:convert';

String getSubscriptionToken(PurchaseDetails purchase) {
  if (Platform.isIOS || Platform.isMacOS) {
    // For Apple subscriptions, parse localVerificationData to get originalTransactionId
    final data = jsonDecode(purchase.verificationData.localVerificationData);
    return data['originalTransactionId'] as String;
  } else {
    // For Google Play, use serverVerificationData
    return purchase.verificationData.serverVerificationData;
  }
}
```

## Configuration Reference

### AppleConfig

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `bundleId` | String | ✅ | Your app's bundle ID (e.g., 'com.example.app') |
| `issuerId` | String | ✅ | Issuer ID from App Store Connect |
| `keyId` | String | ✅ | Key ID from App Store Connect |
| `privateKey` | String | ✅ | Content of your .p8 file |
| `useSandbox` | bool | ❌ | Use sandbox for testing (default: false) |

### GooglePlayConfig

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `packageName` | String | ✅ | Your app's package name (e.g., 'com.example.app') |
| `serviceAccountJson` | String | ✅ | Complete JSON from service account file |

## 🔒 Security Best Practices

⚠️ **Important**: While this package verifies purchases locally, for production apps you should:

1. **Never commit credentials** to version control
2. **Use environment variables** or secure storage for credentials
3. **Consider server-side verification** for critical purchases
4. **Use ProGuard/R8** on Android to obfuscate your code
5. **Monitor for unusual patterns** in purchase behavior

**Example secure initialization:**

```dart
import 'package:flutter_dotenv/flutter_dotenv.dart';

void main() async {
  await dotenv.load();
  
  VerifyLocalPurchase.initialize(
    VerifyPurchaseConfig(
      appleConfig: AppleConfig(
        bundleId: dotenv.env['APPLE_BUNDLE_ID']!,
        issuerId: dotenv.env['APPLE_ISSUER_ID']!,
        keyId: dotenv.env['APPLE_KEY_ID']!,
        privateKey: dotenv.env['APPLE_PRIVATE_KEY']!,
        useSandbox: true,
      ),
      googlePlayConfig: GooglePlayConfig(
        packageName: dotenv.env['ANDROID_PACKAGE_NAME']!,
        serviceAccountJson: dotenv.env['GOOGLE_SERVICE_ACCOUNT']!,
      ),
    ),
  );
  
  runApp(const MyApp());
}
```

## Platform-Specific Notes

### 🍎 iOS/macOS
- Uses [App Store Server API](https://developer.apple.com/documentation/appstoreserverapi)
- Returns `false` if purchase was refunded
- Supports both sandbox and production environments
- **One-time purchases**: Use `transactionId` from `purchase.purchaseID`
- **Subscriptions**: Use `originalTransactionId` from `purchase.verificationData.localVerificationData` (JSON)
  - Parse the `localVerificationData` JSON to extract the `originalTransactionId` field

### 🤖 Android
- Uses [Google Play Developer API](https://developers.google.com/android-publisher)
- Handles OAuth2 authentication automatically
- Returns `false` if purchase is canceled or pending
- **Both purchases and subscriptions**: Always use `purchase.verificationData.serverVerificationData`
  - This contains the `purchaseToken` for one-time purchases
  - This contains the `subscriptionToken` for subscriptions

## Troubleshooting

### ❌ Common Errors

#### Apple: "App Store API error (code: 4040010)"
- The transaction ID doesn't exist
- Wrong environment (check `useSandbox` setting)
- Transaction might be from a different app

#### Apple: "Invalid JWT"
- Check API credentials are correct
- Ensure private key includes header/footer lines
- Verify Issuer ID and Key ID match

#### Google: "401 Unauthorized"
- Service account lacks permissions
- Not linked in Google Play Console
- Check "View financial data" permission is granted

#### Google: "404 Not Found"
- Purchase token doesn't exist
- Wrong package name
- Purchase might be from a different app

## Example App

Check out the [example](example/) directory for a complete working app that demonstrates:

- ✅ Loading products from App Store/Play Store
- ✅ Handling purchase flow
- ✅ Verifying purchases locally
- ✅ Completing transactions properly
- ✅ Error handling

## Contributing

Contributions are welcome! Please:

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Submit a pull request

## License

MIT License - see [LICENSE](LICENSE) file for details.

## Support

- 📖 [Documentation](https://pub.dev/packages/verify_local_purchase)
- 🐛 [Issue Tracker](https://github.com/yourusername/verify_local_purchase/issues)
- 💬 [Discussions](https://github.com/yourusername/verify_local_purchase/discussions)

---

Made with ❤️ for the Flutter community