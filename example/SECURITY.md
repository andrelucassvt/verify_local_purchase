# Security Best Practices

## Storing Credentials Securely

While this package allows local verification, you should **never hardcode your credentials** directly in your source code. Here are some recommended approaches:

### 1. Environment Variables (Recommended for Development)

Use environment variables and load them at build time:

```dart
// In your main.dart
void main() {
  VerifyLocalPurchase.initialize(
    VerifyPurchaseConfig(
      appleConfig: AppleConfig(
        bundleId: const String.fromEnvironment('APPLE_BUNDLE_ID'),
        issuerId: const String.fromEnvironment('APPLE_ISSUER_ID'),
        keyId: const String.fromEnvironment('APPLE_KEY_ID'),
        privateKey: const String.fromEnvironment('APPLE_PRIVATE_KEY'),
      ),
      googlePlayConfig: GooglePlayConfig(
        packageName: const String.fromEnvironment('GOOGLE_PACKAGE_NAME'),
        serviceAccountJson: const String.fromEnvironment('GOOGLE_SERVICE_ACCOUNT'),
      ),
    ),
  );
  runApp(MyApp());
}
```

Then run your app with:
```bash
flutter run --dart-define=APPLE_BUNDLE_ID=com.example.app \
            --dart-define=APPLE_ISSUER_ID=your-issuer-id \
            --dart-define=APPLE_KEY_ID=your-key-id \
            --dart-define=APPLE_PRIVATE_KEY="$(cat AuthKey.p8)" \
            --dart-define=GOOGLE_PACKAGE_NAME=com.example.app \
            --dart-define=GOOGLE_SERVICE_ACCOUNT="$(cat service-account.json)"
```

### 2. Encrypted Credentials in Assets

Store encrypted credentials in your app's assets and decrypt them at runtime:

```dart
import 'package:encrypt/encrypt.dart';
import 'package:flutter/services.dart';

class CredentialsManager {
  static Future<String> decryptCredential(String assetPath, String key) async {
    final encryptedData = await rootBundle.loadString(assetPath);
    final keyBytes = Key.fromUtf8(key.padRight(32, '0').substring(0, 32));
    final iv = IV.fromLength(16);
    final encrypter = Encrypter(AES(keyBytes));
    
    return encrypter.decrypt64(encryptedData, iv: iv);
  }
}

// In your main.dart
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Decrypt credentials (encryption key should come from native code or secure storage)
  final applePrivateKey = await CredentialsManager.decryptCredential(
    'assets/apple_key.enc',
    'your-encryption-key',
  );
  
  final googleServiceAccount = await CredentialsManager.decryptCredential(
    'assets/google_service.enc',
    'your-encryption-key',
  );
  
  VerifyLocalPurchase.initialize(
    VerifyPurchaseConfig(
      appleConfig: AppleConfig(
        bundleId: 'com.example.app',
        issuerId: 'your-issuer-id',
        keyId: 'your-key-id',
        privateKey: applePrivateKey,
      ),
      googlePlayConfig: GooglePlayConfig(
        packageName: 'com.example.app',
        serviceAccountJson: googleServiceAccount,
      ),
    ),
  );
  
  runApp(MyApp());
}
```

### 3. Remote Configuration (Most Secure)

Fetch credentials from your secure backend server:

```dart
import 'package:http/http.dart' as http;
import 'dart:convert';

class CredentialsService {
  static Future<Map<String, dynamic>> fetchCredentials() async {
    final response = await http.get(
      Uri.parse('https://your-backend.com/api/credentials'),
      headers: {'Authorization': 'Bearer YOUR_API_TOKEN'},
    );
    
    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    }
    throw Exception('Failed to load credentials');
  }
}

// In your main.dart
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  final credentials = await CredentialsService.fetchCredentials();
  
  VerifyLocalPurchase.initialize(
    VerifyPurchaseConfig(
      appleConfig: AppleConfig(
        bundleId: credentials['apple']['bundleId'],
        issuerId: credentials['apple']['issuerId'],
        keyId: credentials['apple']['keyId'],
        privateKey: credentials['apple']['privateKey'],
      ),
      googlePlayConfig: GooglePlayConfig(
        packageName: credentials['google']['packageName'],
        serviceAccountJson: credentials['google']['serviceAccount'],
      ),
    ),
  );
  
  runApp(MyApp());
}
```

### 4. Using flutter_secure_storage

Store credentials in the device's secure storage:

```yaml
dependencies:
  flutter_secure_storage: ^9.0.0
```

```dart
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class SecureCredentials {
  static const _storage = FlutterSecureStorage();
  
  static Future<void> saveCredentials({
    required String applePrivateKey,
    required String googleServiceAccount,
  }) async {
    await _storage.write(key: 'apple_private_key', value: applePrivateKey);
    await _storage.write(key: 'google_service_account', value: googleServiceAccount);
  }
  
  static Future<Map<String, String?>> loadCredentials() async {
    return {
      'applePrivateKey': await _storage.read(key: 'apple_private_key'),
      'googleServiceAccount': await _storage.read(key: 'google_service_account'),
    };
  }
}

// First time setup (call this once to store credentials)
await SecureCredentials.saveCredentials(
  applePrivateKey: 'YOUR_APPLE_PRIVATE_KEY',
  googleServiceAccount: 'YOUR_GOOGLE_SERVICE_ACCOUNT',
);

// In your main.dart
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  final credentials = await SecureCredentials.loadCredentials();
  
  VerifyLocalPurchase.initialize(
    VerifyPurchaseConfig(
      appleConfig: AppleConfig(
        bundleId: 'com.example.app',
        issuerId: 'your-issuer-id',
        keyId: 'your-key-id',
        privateKey: credentials['applePrivateKey']!,
      ),
      googlePlayConfig: GooglePlayConfig(
        packageName: 'com.example.app',
        serviceAccountJson: credentials['googleServiceAccount']!,
      ),
    ),
  );
  
  runApp(MyApp());
}
```

## Additional Security Recommendations

1. **Use ProGuard/R8** on Android to obfuscate your code
2. **Enable code shrinking** in your release builds
3. **Implement certificate pinning** when fetching credentials from a server
4. **Use jailbreak/root detection** to prevent tampering
5. **Add server-side verification** as an additional layer of security
6. **Never commit credentials** to version control (use `.gitignore`)
7. **Rotate credentials regularly**
8. **Monitor for unusual verification patterns** in your analytics

## .gitignore Example

Add these to your `.gitignore`:

```
# Credentials
*.p8
*service-account*.json
.env
credentials.json
secrets.dart

# Environment files
.env.local
.env.production

# Encrypted credentials (if you choose to commit encrypted versions)
# Remove the # if you don't want to commit encrypted files
# *.enc
```

## Remember

⚠️ **Local verification is convenient but not foolproof**. For high-value purchases or subscriptions, always implement server-side verification as well.
