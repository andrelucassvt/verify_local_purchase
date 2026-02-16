import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:verify_local_purchase/verify_local_purchase.dart';

void main() {
  // Initialize the verification service with your credentials
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

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'In-App Purchase Example',
      theme: ThemeData(primarySwatch: Colors.blue, useMaterial3: true),
      home: const PurchaseExamplePage(),
    );
  }
}

class PurchaseExamplePage extends StatefulWidget {
  const PurchaseExamplePage({super.key});

  @override
  State<PurchaseExamplePage> createState() => _PurchaseExamplePageState();
}

class _PurchaseExamplePageState extends State<PurchaseExamplePage> {
  final InAppPurchase _inAppPurchase = InAppPurchase.instance;
  final VerifyLocalPurchase _verifyPurchase = VerifyLocalPurchase();

  StreamSubscription<List<PurchaseDetails>>? _purchaseSubscription;
  List<ProductDetails> _products = [];
  String _statusMessage = 'Loading...';
  bool _isLoading = true;
  int _userTokens = 0;

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  @override
  void dispose() {
    _purchaseSubscription?.cancel();
    super.dispose();
  }

  Future<void> _initialize() async {
    // Listen to purchase updates
    _purchaseSubscription = _inAppPurchase.purchaseStream.listen(
      _handlePurchaseUpdate,
      onError: (error) {
        debugPrint('❌ Purchase stream error: $error');
        _showMessage('Error: $error');
      },
    );

    await _loadProducts();
  }

  Future<void> _loadProducts() async {
    setState(() {
      _isLoading = true;
      _statusMessage = 'Loading products...';
    });

    try {
      // Check if in-app purchase is available
      final available = await _inAppPurchase.isAvailable();
      if (!available) {
        setState(() {
          _statusMessage = 'In-app purchases not available';
          _isLoading = false;
        });
        return;
      }

      // Load products (replace with your product IDs)
      const productIds = {'tokens_100', 'tokens_500', 'tokens_1000'};
      final response = await _inAppPurchase.queryProductDetails(productIds);

      if (response.error != null) {
        setState(() {
          _statusMessage = 'Error loading products: ${response.error}';
          _isLoading = false;
        });
        return;
      }

      setState(() {
        _products = response.productDetails;
        _statusMessage = _products.isEmpty
            ? 'No products found'
            : 'Tap a product to purchase';
        _isLoading = false;
      });

      debugPrint('📦 Loaded ${_products.length} products');
    } catch (e) {
      debugPrint('❌ Error loading products: $e');
      setState(() {
        _statusMessage = 'Error: $e';
        _isLoading = false;
      });
    }
  }

  Future<void> _buyProduct(ProductDetails product) async {
    debugPrint('🛒 Starting purchase: ${product.id}');

    setState(() {
      _statusMessage = 'Processing purchase...';
    });

    final purchaseParam = PurchaseParam(productDetails: product);
    await _inAppPurchase.buyConsumable(purchaseParam: purchaseParam);
  }

  Future<void> _handlePurchaseUpdate(
    List<PurchaseDetails> purchaseDetailsList,
  ) async {
    debugPrint('🔔 Received ${purchaseDetailsList.length} purchase updates');

    for (final purchaseDetails in purchaseDetailsList) {
      debugPrint(
        '  📦 ${purchaseDetails.productID}: ${purchaseDetails.status}',
      );

      switch (purchaseDetails.status) {
        case PurchaseStatus.pending:
          _showMessage('⏳ Purchase pending...');

        case PurchaseStatus.purchased:
        case PurchaseStatus.restored:
          await _verifyAndCompletePurchase(purchaseDetails);

        case PurchaseStatus.error:
          final errorMsg = purchaseDetails.error?.message ?? 'Unknown error';
          debugPrint('❌ Purchase error: $errorMsg');
          _showMessage('❌ Purchase failed: $errorMsg');
          if (purchaseDetails.pendingCompletePurchase) {
            await _inAppPurchase.completePurchase(purchaseDetails);
          }

        case PurchaseStatus.canceled:
          debugPrint('🚫 Purchase canceled');
          _showMessage('❌ Purchase canceled');
          if (purchaseDetails.pendingCompletePurchase) {
            await _inAppPurchase.completePurchase(purchaseDetails);
          }
      }
    }
  }

  Future<void> _verifyAndCompletePurchase(
    PurchaseDetails purchaseDetails,
  ) async {
    try {
      // Get token for verification (iOS uses transactionId, Android uses purchaseToken)
      String verificationToken;
      if (Platform.isIOS) {
        verificationToken = purchaseDetails.purchaseID ?? '';
      } else {
        verificationToken =
            purchaseDetails.verificationData.serverVerificationData;
      }

      if (verificationToken.isEmpty) {
        debugPrint('⚠️ Empty verification token');
        _showMessage('❌ Invalid purchase data');
        if (purchaseDetails.pendingCompletePurchase) {
          await _inAppPurchase.completePurchase(purchaseDetails);
        }
        return;
      }

      debugPrint('🔐 Verifying purchase...');
      _showMessage('🔐 Verifying purchase...');

      // Verify the purchase locally
      final isValid = await _verifyPurchase.verifyPurchase(verificationToken);

      if (!isValid) {
        debugPrint('❌ Purchase verification failed');
        _showMessage('❌ Purchase verification failed');
        if (purchaseDetails.pendingCompletePurchase) {
          await _inAppPurchase.completePurchase(purchaseDetails);
        }
        return;
      }

      debugPrint('✅ Purchase verified successfully');

      // Extract tokens from product description
      // In a real app, you'd get this from your backend
      final tokens = _extractTokensFromDescription(
        _products
            .firstWhere((p) => p.id == purchaseDetails.productID)
            .description,
      );

      // Add tokens to user (in a real app, this would be done on your backend)
      setState(() {
        _userTokens += tokens;
      });

      // Complete the purchase
      if (purchaseDetails.pendingCompletePurchase) {
        await _inAppPurchase.completePurchase(purchaseDetails);
      }

      _showMessage('✅ Purchase successful! Added $tokens tokens');
      debugPrint('✅ Purchase completed. Total tokens: $_userTokens');
    } catch (e) {
      debugPrint('❌ Error processing purchase: $e');
      _showMessage('❌ Error: $e');
    }
  }

  int _extractTokensFromDescription(String description) {
    // Simple extraction - in production, use proper product metadata
    final match = RegExp(
      r'(\d+)\s*tokens?',
      caseSensitive: false,
    ).firstMatch(description);
    return match != null ? int.parse(match.group(1)!) : 100;
  }

  void _showMessage(String message) {
    setState(() {
      _statusMessage = message;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('In-App Purchase Example'),
        elevation: 2,
      ),
      body: Column(
        children: [
          // User Balance
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            color: Colors.blue.shade50,
            child: Column(
              children: [
                const Icon(
                  Icons.account_balance_wallet,
                  size: 48,
                  color: Colors.blue,
                ),
                const SizedBox(height: 8),
                Text(
                  '$_userTokens Tokens',
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),

          // Status Message
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            color: _statusMessage.contains('✅')
                ? Colors.green.shade50
                : _statusMessage.contains('❌')
                ? Colors.red.shade50
                : Colors.grey.shade100,
            child: Text(
              _statusMessage,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 16),
            ),
          ),

          // Products List
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _products.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(
                          Icons.shopping_cart_outlined,
                          size: 64,
                          color: Colors.grey,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          _statusMessage,
                          style: const TextStyle(
                            fontSize: 18,
                            color: Colors.grey,
                          ),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: _products.length,
                    itemBuilder: (context, index) {
                      final product = _products[index];
                      return Card(
                        margin: const EdgeInsets.only(bottom: 12),
                        child: ListTile(
                          contentPadding: const EdgeInsets.all(16),
                          leading: CircleAvatar(
                            backgroundColor: Colors.blue,
                            child: Text(
                              '${index + 1}',
                              style: const TextStyle(color: Colors.white),
                            ),
                          ),
                          title: Text(
                            product.title,
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 18,
                            ),
                          ),
                          subtitle: Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Text(product.description),
                          ),
                          trailing: ElevatedButton(
                            onPressed: () => _buyProduct(product),
                            child: Text(
                              product.price,
                              style: const TextStyle(fontSize: 16),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
