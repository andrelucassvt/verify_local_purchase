# Integration Examples

Examples of how to integrate `verify_local_purchase` with popular Flutter in-app purchase packages.

## With in_app_purchase (Official Flutter Package)

```dart
import 'package:flutter/material.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:verify_local_purchase/verify_local_purchase.dart';

class PurchaseManager {
  final InAppPurchase _iap = InAppPurchase.instance;
  final VerifyLocalPurchase _verifyPurchase = VerifyLocalPurchase();

  Future<void> handlePurchase(PurchaseDetails purchase) async {
    if (purchase.status == PurchaseStatus.purchased ||
        purchase.status == PurchaseStatus.restored) {
      
      // Verify the purchase locally
      final isValid = await _verifyPurchase.verifyPurchase(
        // For iOS: purchase.verificationData.serverVerificationData
        // For Android: purchase.verificationData.serverVerificationData
        purchase.verificationData.serverVerificationData,
      );

      if (isValid) {
        // Grant access to the purchased content
        await _deliverProduct(purchase);
        
        // Complete the purchase
        await _iap.completePurchase(purchase);
      } else {
        // Purchase is invalid
        debugPrint('Invalid purchase: ${purchase.productID}');
      }
    }
  }

  Future<void> _deliverProduct(PurchaseDetails purchase) async {
    // Your logic to grant access to the purchased content
    debugPrint('Delivering product: ${purchase.productID}');
  }
}
```

## With purchases_flutter (RevenueCat)

```dart
import 'package:flutter/material.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:verify_local_purchase/verify_local_purchase.dart';

class RevenueCatManager {
  final VerifyLocalPurchase _verifyPurchase = VerifyLocalPurchase();

  Future<void> initRevenueCat() async {
    await Purchases.configure(
      PurchasesConfiguration('your_revenuecat_api_key'),
    );
  }

  Future<void> purchaseProduct(Package package) async {
    try {
      final purchaseResult = await Purchases.purchasePackage(package);
      
      // Get the transaction ID
      final transaction = purchaseResult.customerInfo.nonSubscriptionTransactions.last;
      final transactionId = transaction.transactionIdentifier;

      // Verify locally
      final isValid = await _verifyPurchase.verifyPurchase(transactionId);

      if (isValid) {
        debugPrint('Purchase verified successfully');
        // Grant access to content
      } else {
        debugPrint('Purchase verification failed');
      }
    } catch (e) {
      debugPrint('Purchase error: $e');
    }
  }

  Future<void> verifySubscription() async {
    try {
      final customerInfo = await Purchases.getCustomerInfo();
      
      if (customerInfo.activeSubscriptions.isNotEmpty) {
        // Get the latest subscription transaction
        final subscriptionId = customerInfo.activeSubscriptions.first;
        
        // Verify locally
        final isActive = await _verifyPurchase.verifySubscription(subscriptionId);

        if (isActive) {
          debugPrint('Subscription is active');
          // Grant premium access
        } else {
          debugPrint('Subscription verification failed');
        }
      }
    } catch (e) {
      debugPrint('Subscription check error: $e');
    }
  }
}
```

## With purchases_ui_flutter (Custom Implementation)

```dart
import 'package:flutter/material.dart';
import 'package:verify_local_purchase/verify_local_purchase.dart';
import 'dart:io';

class CustomPurchaseScreen extends StatefulWidget {
  const CustomPurchaseScreen({super.key});

  @override
  State<CustomPurchaseScreen> createState() => _CustomPurchaseScreenState();
}

class _CustomPurchaseScreenState extends State<CustomPurchaseScreen> {
  final VerifyLocalPurchase _verifyPurchase = VerifyLocalPurchase();
  bool _isPremium = false;

  @override
  void initState() {
    super.initState();
    _checkPremiumStatus();
  }

  Future<void> _checkPremiumStatus() async {
    // Load stored transaction ID from local storage
    final storedTransactionId = await _loadStoredTransactionId();
    
    if (storedTransactionId != null) {
      try {
        final isValid = await _verifyPurchase.verifyPurchase(storedTransactionId);
        setState(() {
          _isPremium = isValid;
        });
      } catch (e) {
        debugPrint('Error verifying stored purchase: $e');
      }
    }
  }

  Future<void> _purchasePremium() async {
    // Implement your purchase logic with platform channels
    // This is a simplified example
    
    try {
      // For iOS: Use StoreKit
      // For Android: Use Google Play Billing
      final transactionId = await _makePurchase();
      
      if (transactionId != null) {
        // Verify the purchase
        final isValid = await _verifyPurchase.verifyPurchase(transactionId);
        
        if (isValid) {
          // Store the transaction ID for future verification
          await _saveTransactionId(transactionId);
          
          setState(() {
            _isPremium = true;
          });
          
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Purchase successful!')),
            );
          }
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Purchase failed: $e')),
        );
      }
    }
  }

  Future<String?> _makePurchase() async {
    // Implement your platform-specific purchase logic here
    // Return the transaction ID
    return null;
  }

  Future<String?> _loadStoredTransactionId() async {
    // Implement loading from SharedPreferences or secure storage
    return null;
  }

  Future<void> _saveTransactionId(String transactionId) async {
    // Implement saving to SharedPreferences or secure storage
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Premium'),
      ),
      body: Center(
        child: _isPremium
            ? const Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.verified, size: 64, color: Colors.green),
                  SizedBox(height: 16),
                  Text(
                    'You have Premium!',
                    style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                  ),
                ],
              )
            : Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.star, size: 64, color: Colors.amber),
                  const SizedBox(height: 16),
                  const Text(
                    'Upgrade to Premium',
                    style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 32),
                  ElevatedButton(
                    onPressed: _purchasePremium,
                    child: const Text('Purchase Premium'),
                  ),
                ],
              ),
      ),
    );
  }
}
```

## Periodic Subscription Verification

For subscriptions, it's recommended to verify periodically:

```dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:verify_local_purchase/verify_local_purchase.dart';

class SubscriptionManager {
  final VerifyLocalPurchase _verifyPurchase = VerifyLocalPurchase();
  Timer? _verificationTimer;
  bool _isSubscribed = false;

  /// Start periodic verification (every 24 hours)
  void startPeriodicVerification(String subscriptionToken) {
    _verificationTimer?.cancel();
    
    // Verify immediately
    _verifySubscriptionStatus(subscriptionToken);
    
    // Then verify every 24 hours
    _verificationTimer = Timer.periodic(
      const Duration(hours: 24),
      (_) => _verifySubscriptionStatus(subscriptionToken),
    );
  }

  Future<void> _verifySubscriptionStatus(String subscriptionToken) async {
    try {
      final isActive = await _verifyPurchase.verifySubscription(subscriptionToken);
      
      if (_isSubscribed != isActive) {
        _isSubscribed = isActive;
        
        if (!isActive) {
          // Subscription expired or canceled
          _handleSubscriptionExpired();
        } else {
          // Subscription renewed
          _handleSubscriptionRenewed();
        }
      }
    } catch (e) {
      debugPrint('Error verifying subscription: $e');
    }
  }

  void _handleSubscriptionExpired() {
    debugPrint('Subscription expired - revoking premium access');
    // Revoke premium features
  }

  void _handleSubscriptionRenewed() {
    debugPrint('Subscription renewed - granting premium access');
    // Grant premium features
  }

  void dispose() {
    _verificationTimer?.cancel();
  }

  bool get isSubscribed => _isSubscribed;
}
```

## Error Handling Best Practices

```dart
import 'package:verify_local_purchase/verify_local_purchase.dart';

class PurchaseVerifier {
  final VerifyLocalPurchase _verifyPurchase = VerifyLocalPurchase();

  Future<bool> safeVerifyPurchase(String token) async {
    try {
      return await _verifyPurchase.verifyPurchase(token);
    } on Exception catch (e) {
      if (e.toString().contains('not initialized')) {
        debugPrint('VerifyLocalPurchase not initialized');
        // Handle initialization error
      } else if (e.toString().contains('API error')) {
        debugPrint('API error: $e');
        // Handle API errors (might be temporary)
        // Consider retrying
      } else if (e.toString().contains('configuration not provided')) {
        debugPrint('Platform configuration missing: $e');
        // Handle missing configuration
      } else {
        debugPrint('Unknown error: $e');
      }
      return false;
    }
  }

  Future<bool> verifyWithRetry(
    String token, {
    int maxRetries = 3,
    Duration delay = const Duration(seconds: 2),
  }) async {
    for (var i = 0; i < maxRetries; i++) {
      try {
        return await _verifyPurchase.verifyPurchase(token);
      } catch (e) {
        if (i == maxRetries - 1) {
          rethrow;
        }
        debugPrint('Verification attempt ${i + 1} failed, retrying...');
        await Future.delayed(delay);
      }
    }
    return false;
  }
}
```
