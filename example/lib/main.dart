import 'package:flutter/material.dart';
import 'package:verify_local_purchase/verify_local_purchase.dart';

void main() {
  // Initialize the verification service with your credentials
  VerifyLocalPurchase.initialize(
    VerifyPurchaseConfig(
      appleConfig: AppleConfig(
        bundleId: 'com.example.app',
        issuerId: 'your-issuer-id-here',
        keyId: 'your-key-id-here',
        privateKey: '''-----BEGIN PRIVATE KEY-----
YOUR_PRIVATE_KEY_CONTENT_HERE
-----END PRIVATE KEY-----''',
        useSandbox: true, // Use sandbox for testing
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
    ),
  );

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Verify Local Purchase Example',
      theme: ThemeData(primarySwatch: Colors.blue, useMaterial3: true),
      home: const PurchaseVerificationPage(),
    );
  }
}

class PurchaseVerificationPage extends StatefulWidget {
  const PurchaseVerificationPage({super.key});

  @override
  State<PurchaseVerificationPage> createState() =>
      _PurchaseVerificationPageState();
}

class _PurchaseVerificationPageState extends State<PurchaseVerificationPage> {
  final _verifyPurchase = VerifyLocalPurchase();
  final _purchaseTokenController = TextEditingController();
  final _subscriptionTokenController = TextEditingController();

  String _purchaseResult = '';
  String _subscriptionResult = '';
  bool _isVerifyingPurchase = false;
  bool _isVerifyingSubscription = false;

  @override
  void dispose() {
    _purchaseTokenController.dispose();
    _subscriptionTokenController.dispose();
    super.dispose();
  }

  Future<void> _verifyPurchaseAction() async {
    if (_purchaseTokenController.text.isEmpty) {
      setState(() {
        _purchaseResult = '⚠️ Please enter a purchase token';
      });
      return;
    }

    setState(() {
      _isVerifyingPurchase = true;
      _purchaseResult = 'Verifying...';
    });

    try {
      final isValid = await _verifyPurchase.verifyPurchase(
        _purchaseTokenController.text,
      );

      setState(() {
        _purchaseResult = isValid
            ? '✅ Purchase is valid!'
            : '❌ Purchase is invalid or refunded';
      });
    } catch (e) {
      setState(() {
        _purchaseResult = '❌ Error: $e';
      });
    } finally {
      setState(() {
        _isVerifyingPurchase = false;
      });
    }
  }

  Future<void> _verifySubscriptionAction() async {
    if (_subscriptionTokenController.text.isEmpty) {
      setState(() {
        _subscriptionResult = '⚠️ Please enter a subscription token';
      });
      return;
    }

    setState(() {
      _isVerifyingSubscription = true;
      _subscriptionResult = 'Verifying...';
    });

    try {
      final isActive = await _verifyPurchase.verifySubscription(
        _subscriptionTokenController.text,
      );

      setState(() {
        _subscriptionResult = isActive
            ? '✅ Subscription is active!'
            : '❌ Subscription is expired or canceled';
      });
    } catch (e) {
      setState(() {
        _subscriptionResult = '❌ Error: $e';
      });
    } finally {
      setState(() {
        _isVerifyingSubscription = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Verify Local Purchase'), elevation: 2),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Info Card
            Card(
              color: Colors.blue.shade50,
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.info_outline, color: Colors.blue.shade700),
                        const SizedBox(width: 8),
                        Text(
                          'How to use',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Colors.blue.shade700,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'For iOS: Enter the transactionId or originalTransactionId\n'
                      'For Android: Enter the purchaseToken or subscriptionToken',
                      style: TextStyle(fontSize: 14),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),

            // Purchase Verification Section
            Text(
              'Verify One-Time Purchase',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _purchaseTokenController,
              decoration: const InputDecoration(
                labelText: 'Purchase Token / Transaction ID',
                hintText: 'Enter purchase token here',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.shopping_cart),
              ),
              maxLines: 2,
            ),
            const SizedBox(height: 12),
            ElevatedButton.icon(
              onPressed: _isVerifyingPurchase ? null : _verifyPurchaseAction,
              icon: _isVerifyingPurchase
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.verified),
              label: Text(
                _isVerifyingPurchase ? 'Verifying...' : 'Verify Purchase',
              ),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.all(16),
              ),
            ),
            if (_purchaseResult.isNotEmpty) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: _purchaseResult.startsWith('✅')
                      ? Colors.green.shade50
                      : _purchaseResult.startsWith('❌')
                      ? Colors.red.shade50
                      : Colors.orange.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: _purchaseResult.startsWith('✅')
                        ? Colors.green
                        : _purchaseResult.startsWith('❌')
                        ? Colors.red
                        : Colors.orange,
                  ),
                ),
                child: Text(
                  _purchaseResult,
                  style: const TextStyle(fontSize: 16),
                ),
              ),
            ],
            const SizedBox(height: 32),

            // Subscription Verification Section
            Text(
              'Verify Subscription',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _subscriptionTokenController,
              decoration: const InputDecoration(
                labelText: 'Subscription Token / Original Transaction ID',
                hintText: 'Enter subscription token here',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.card_membership),
              ),
              maxLines: 2,
            ),
            const SizedBox(height: 12),
            ElevatedButton.icon(
              onPressed: _isVerifyingSubscription
                  ? null
                  : _verifySubscriptionAction,
              icon: _isVerifyingSubscription
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.subscriptions),
              label: Text(
                _isVerifyingSubscription
                    ? 'Verifying...'
                    : 'Verify Subscription',
              ),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.all(16),
              ),
            ),
            if (_subscriptionResult.isNotEmpty) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: _subscriptionResult.startsWith('✅')
                      ? Colors.green.shade50
                      : _subscriptionResult.startsWith('❌')
                      ? Colors.red.shade50
                      : Colors.orange.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: _subscriptionResult.startsWith('✅')
                        ? Colors.green
                        : _subscriptionResult.startsWith('❌')
                        ? Colors.red
                        : Colors.orange,
                  ),
                ),
                child: Text(
                  _subscriptionResult,
                  style: const TextStyle(fontSize: 16),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
