# verify_local_purchase

A Flutter package for verifying in-app purchases and subscriptions **locally on device** with Apple App Store and Google Play Store. This package allows you to validate purchases without the need for a backend server.

[![pub package](https://img.shields.io/pub/v/verify_local_purchase.svg)](https://pub.dev/packages/verify_local_purchase)

## Features

✅ **Local verification** - Verify purchases directly from your Flutter app  
🍎 **Apple App Store** - Support for iOS and macOS in-app purchases and subscriptions  
🤖 **Google Play Store** - Support for Android in-app purchases and subscriptions  
🔒 **Official APIs** - App Store Server API and Google Play Developer API  
📋 **Rich results** - State, expiration, auto-renew and sandbox flag, not just a boolean  
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
3. Navigate to **APIs & Services** > **Library**, search for **Google Play Android Developer API** and click **Enable**
4. Navigate to **IAM & Admin** > **Service Accounts**
4. Click **Create Service Account**
6. Name it (e.g., "In-App Purchase Verifier")
7. Grant role: **Pub/Sub** > **Pub/Sub Editor** (or create custom role)
8. Click **Done**
9. Click on the created service account
10. Go to **Keys** tab > **Add Key** > **Create new key**
11. Choose **JSON** format and click **Create**
12. The JSON file will be downloaded automatically

**Now link it to Google Play:**

13. Go to [Google Play Console](https://play.google.com/console/)
14. Navigate to **Setup** > **API access**
15. Click **Link** next to your service account
16. Grant permissions: **View financial data** and **Manage orders**
17. Click **Invite user** and then **Invite user** again

**You'll need:**
- ✅ Service Account JSON file (entire content)
- ✅ Package Name (from your build.gradle)

## Installation

Add this to your `pubspec.yaml`:

```yaml
dependencies:
  verify_local_purchase: ^2.0.0
```

`in_app_purchase` is re-exported by this package — you don't need to add it separately.

Run:

```bash
flutter pub get
```

> Upgrading from 1.x? See [Migrating from 1.x](#migrating-from-1x).

## Quick Reference

**Initialization:**

```dart
void main() {
  VerifyLocalPurchase.initialize(
    appleConfig: AppleConfig(
      bundleId: 'com.example.app',
      issuerId: 'your-issuer-id',
      keyId: 'your-key-id',
      privateKey: '-----BEGIN PRIVATE KEY-----\n...\n-----END PRIVATE KEY-----',
      // Default: production, retrying in sandbox when the transaction is not
      // found there (App Review and TestFlight use sandbox).
      environment: AppleEnvironment.productionWithSandboxFallback,
    ),
    googlePlayConfig: GooglePlayConfig(
      packageName: 'com.example.app',
      serviceAccountJson: '{ ... }',
    ),
    enableLogging: kDebugMode, // masked tokens; off by default
  );

  runApp(const MyApp());
}
```

### Verify straight from `PurchaseDetails`

The easiest path — the package extracts the right token for each platform:

```dart
// One-time purchase (consumable or non-consumable)
final result = await VerifyLocalPurchase.verifyPurchaseDetails(purchase);

// Subscription
final result = await VerifyLocalPurchase.verifySubscriptionDetails(purchase);

if (result.isValid) {
  // ✅ Grant access
} else {
  // ❌ result.state tells why: expired, revoked, pending, notFound...
}
```

### Verify with a token

If you store tokens yourself, use `getOneTimePurchaseToken` / `getSubscriptionToken` and pass the string:

```dart
final token = getSubscriptionToken(purchase);
final result = await VerifyLocalPurchase.verifySubscription(token);
```

| Platform | One-time purchase | Subscription |
|----------|-------------------|--------------|
| iOS/macOS | `purchase.purchaseID` (transaction ID) | `originalTransactionId` from `localVerificationData` |
| Android | `serverVerificationData` (purchase token) | `serverVerificationData` (subscription token) |

Both helpers throw `VerifyPurchaseException` (`invalidToken`) if the token is missing.

### `VerificationResult`

| Field | Description |
|-------|-------------|
| `isValid` | Whether to grant access **now** |
| `state` | `purchased`, `active`, `canceled`, `gracePeriod`, `billingRetry`, `onHold`, `paused`, `pending`, `expired`, `revoked`, `notFound`, `unknown` |
| `platform` | `StorePlatform.apple` / `StorePlatform.google` |
| `productId` | Product returned by the store |
| `expiresAt` | End of the current subscription period (use it to cache the result) |
| `willAutoRenew` | Whether the subscription renews automatically |
| `isSandbox` | Answer came from sandbox / a test purchase |
| `raw` | Decoded store payload |

**When is a subscription valid?**

| Store | Valid (`isValid: true`) | Not valid |
|-------|------------------------|-----------|
| Apple | Active (1), Billing Grace Period (4) — canceled auto-renew still counts until expiration | Expired (2), Billing Retry (3), Revoked (5) |
| Google | `ACTIVE`, `CANCELED`, `IN_GRACE_PERIOD` **and** `expiryTime` in the future | `PENDING`, `ON_HOLD`, `PAUSED`, `EXPIRED` |

### Errors

Every method throws `VerifyPurchaseException` with a `code`:

```dart
try {
  final result = await VerifyLocalPurchase.verifyPurchaseDetails(purchase);
} on VerifyPurchaseException catch (e) {
  switch (e.code) {
    case VerifyPurchaseErrorCode.networkError:
      // offline — retry later, don't revoke access
    case VerifyPurchaseErrorCode.unauthorized:
    case VerifyPurchaseErrorCode.invalidCredentials:
      // configuration problem
    default:
      // e.statusCode / e.storeErrorCode have details
  }
}
```

An unknown token/transaction is **not** an error: it returns `VerificationResult` with `state: notFound`.

### Refunds

```dart
// Apple: refunds for one customer
final appleRefunds = await VerifyLocalPurchase.getRefundsWithAppStore(originalTransactionId);

// Google: all voided purchases of the app (last 30 days by default, paginated)
final googleRefunds = await VerifyLocalPurchase.getRefundsWithGooglePlay(
  startTime: DateTime.now().subtract(const Duration(days: 7)),
);
```

## Complete Example

```dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:verify_local_purchase/verify_local_purchase.dart';

void main() {
  VerifyLocalPurchase.initialize(
    appleConfig: AppleConfig(
      bundleId: 'com.example.app',
      issuerId: 'your-issuer-id-here',
      keyId: 'your-key-id-here',
      privateKey: '''-----BEGIN PRIVATE KEY-----
YOUR_PRIVATE_KEY_CONTENT_HERE
-----END PRIVATE KEY-----''',
    ),
    googlePlayConfig: GooglePlayConfig(
      packageName: 'com.example.app',
      serviceAccountJson: '''{ "type": "service_account", ... }''',
    ),
  );

  runApp(const MaterialApp(home: StorePage()));
}

class StorePage extends StatefulWidget {
  const StorePage({super.key});

  @override
  State<StorePage> createState() => _StorePageState();
}

class _StorePageState extends State<StorePage> {
  final _inAppPurchase = InAppPurchase.instance;
  StreamSubscription<List<PurchaseDetails>>? _subscription;

  @override
  void initState() {
    super.initState();
    _subscription = _inAppPurchase.purchaseStream.listen(_onPurchaseUpdate);
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  Future<void> _onPurchaseUpdate(List<PurchaseDetails> purchases) async {
    for (final purchase in purchases) {
      if (purchase.status == PurchaseStatus.purchased ||
          purchase.status == PurchaseStatus.restored) {
        await _verifyAndComplete(purchase);
      } else if (purchase.pendingCompletePurchase) {
        await _inAppPurchase.completePurchase(purchase);
      }
    }
  }

  Future<void> _verifyAndComplete(PurchaseDetails purchase) async {
    try {
      final result = await VerifyLocalPurchase.verifyPurchaseDetails(purchase);

      if (result.isValid) {
        // ✅ TODO: grant access to result.productId
      } else {
        debugPrint('❌ Purchase not valid: ${result.state}');
      }

      if (purchase.pendingCompletePurchase) {
        await _inAppPurchase.completePurchase(purchase);
      }
    } on VerifyPurchaseException catch (e) {
      // Network/config errors: keep the purchase pending to retry later
      debugPrint('⚠️ Could not verify: $e');
    }
  }

  @override
  Widget build(BuildContext context) => const Scaffold();
}
```

## Configuration Reference

### `VerifyLocalPurchase.initialize`

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `appleConfig` | AppleConfig | ❌ | Required to verify on iOS/macOS |
| `googlePlayConfig` | GooglePlayConfig | ❌ | Required to verify on Android |
| `enableLogging` | bool | ❌ | Print debug logs with masked tokens (default: false) |

Calling `initialize` again replaces the previous config. `VerifyLocalPurchase.dispose()` releases the cached HTTP clients.

### AppleConfig

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `bundleId` | String | ✅ | Your app's bundle ID (e.g., 'com.example.app') |
| `issuerId` | String | ✅ | Issuer ID from App Store Connect |
| `keyId` | String | ✅ | Key ID from App Store Connect |
| `privateKey` | String | ✅ | Content of your .p8 file |
| `environment` | AppleEnvironment | ❌ | `production`, `sandbox` or `productionWithSandboxFallback` (default) |

### GooglePlayConfig

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `packageName` | String | ✅ | Your app's package name (e.g., 'com.example.app') |
| `serviceAccountJson` | String | ✅ | Complete JSON from service account file |

## 🔒 Security — read before shipping

Verifying on device means **your store credentials ship inside the app binary**. Anyone who decompiles the app can extract them, and a modified app can skip the verification call entirely. Understand the trade-off:

1. **Use dedicated credentials** for this package — a separate App Store Connect API key and a separate Google service account — so you can revoke them without affecting anything else.
2. **Grant the minimum permissions** in Play Console. Only grant *View financial data* if you use `getRefundsWithGooglePlay`.
3. **Rotate keys** periodically and whenever you suspect a leak.
4. **Obfuscate** release builds (`flutter build --obfuscate --split-debug-info=...`) and never commit credentials to version control.
5. **Keep logging off in release** — `enableLogging` defaults to `false`.
6. For high-value content, **prefer server-side verification**; this package fits apps where a backend isn't worth it.

## Platform-Specific Notes

### 🍎 iOS/macOS
- Uses the [App Store Server API](https://developer.apple.com/documentation/appstoreserverapi)
- **One-time purchases**: searches the customer's transaction history; refunded/revoked transactions return `state: revoked`
- **Subscriptions**: checks all subscription groups, preferring the entry that matches the `originalTransactionId`
- With the default environment, transactions not found in production are looked up in sandbox (App Review, TestFlight)

### 🤖 Android
- Uses the [Google Play Developer API](https://developers.google.com/android-publisher) (`productsv2` and `subscriptionsv2`)
- OAuth2 is handled automatically and the access token is reused between calls
- A canceled subscription stays valid until `expiryTime`; a pending one is not valid until payment completes

## Troubleshooting

### ❌ Common Errors

#### Apple: `state: notFound`
- The transaction ID doesn't exist in the environment(s) queried
- If you set `environment: AppleEnvironment.production`, sandbox purchases won't be found
- Transaction might be from a different app

#### Apple: `unauthorized` / "Invalid JWT"
- Check API credentials are correct
- Ensure private key includes header/footer lines
- Verify Issuer ID and Key ID match

#### Google: `unauthorized` with status 403 or "API not enabled"
- The **Google Play Android Developer API** is not enabled in Google Cloud Console
- Go to **APIs & Services** > **Library**, search for **Google Play Android Developer API** and click **Enable**

#### Google: `unauthorized` with status 401
- Service account lacks permissions
- Not linked in Google Play Console

#### Google: `state: notFound`
- Purchase token doesn't exist or is too old (HTTP 404/410)
- Wrong package name

## Migrating from 1.x

| 1.x | 2.0 |
|-----|-----|
| `VerifyLocalPurchase().verifyPurchase(token)` → `bool` | `VerifyLocalPurchase.verifyPurchase(token)` → `VerificationResult` (use `.isValid`) |
| Instance methods | Static methods on `VerifyLocalPurchase` |
| `AppleConfig(useSandbox: true)` | `AppleConfig(environment: AppleEnvironment.sandbox)` — default is now production with sandbox fallback |
| `throw Exception(...)` | `throw VerifyPurchaseException(code, ...)` |
| `RefundPlatform` | `StorePlatform` |
| `getOneTimePurchaseToken` returned `''` when missing | Throws `VerifyPurchaseException(invalidToken)` |
| Google `SUBSCRIPTION_STATE_PENDING` was valid | Not valid; `IN_GRACE_PERIOD` and `CANCELED` (until expiry) are valid |
| Apple status 4 (grace period) was invalid | Valid |
| Unknown Google token threw an exception | Returns `state: notFound` |
| `VerifyPurchaseService` exported | Internal |
| Native plugin (`getPlatformVersion`) | Removed — pure Dart package |

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
- 🐛 [Issue Tracker](https://github.com/andrelucassvt/verify_local_purchase/issues)
- 💬 [Discussions](https://github.com/andrelucassvt/verify_local_purchase/discussions)

---

Made with ❤️ for the Flutter community