import 'dart:convert';
import 'dart:io';

import 'package:app_store_server_sdk/app_store_server_sdk.dart';
import 'package:flutter/foundation.dart';
import 'package:googleapis_auth/auth_io.dart';

import '../models/verify_purchase_config.dart';

class VerifyPurchaseService {
  static VerifyPurchaseConfig? _config;

  /// Initialize the service with your App Store and Google Play credentials
  ///
  /// This should be called once in your app's main() function before using
  /// any verification methods.
  ///
  /// Example:
  /// ```dart
  /// void main() {
  ///   VerifyPurchaseService.initialize(
  ///     VerifyPurchaseConfig(
  ///       appleConfig: AppleConfig(
  ///         bundleId: 'com.example.app',
  ///         issuerId: 'your-issuer-id',
  ///         keyId: 'your-key-id',
  ///         privateKey: 'your-private-key',
  ///       ),
  ///       googlePlayConfig: GooglePlayConfig(
  ///         packageName: 'com.example.app',
  ///         serviceAccountJson: 'your-service-account-json',
  ///       ),
  ///     ),
  ///   );
  ///   runApp(MyApp());
  /// }
  /// ```
  static void initialize(VerifyPurchaseConfig config) {
    _config = config;
  }

  static VerifyPurchaseConfig get _getConfig {
    if (_config == null) {
      throw Exception(
        'VerifyPurchaseService not initialized. '
        'Call VerifyPurchaseService.initialize() in your main() function.',
      );
    }
    return _config!;
  }

  /// Verify a one-time purchase (consumable or non-consumable)
  ///
  /// [purchaseToken] is the transaction ID from App Store or purchase token from Google Play
  Future<bool> verifyPurchase(String purchaseToken) async {
    return Platform.isIOS
        ? await verifyPurchaseWithAppStore(purchaseToken)
        : await verifyPurchaseWithGooglePlay(purchaseToken);
  }

  /// Verify a subscription
  ///
  /// [subscriptionToken] is the original transaction ID from App Store or subscription token from Google Play
  Future<bool> verifySubscription(String subscriptionToken) async {
    return Platform.isIOS
        ? await verifySubscriptionWithAppStore(subscriptionToken)
        : await verifySubscriptionWithGooglePlay(subscriptionToken);
  }

  Future<bool> verifySubscriptionWithAppStore(String subscriptionToken) async {
    final config = _getConfig;
    if (config.appleConfig == null) {
      throw Exception('Apple configuration not provided');
    }

    try {
      debugPrint(
        '🔍 Verificando assinatura na App Store com transactionId: '
        '$subscriptionToken',
      );

      final appStoreEnvironment = config.appleConfig!.useSandbox
          ? AppStoreEnvironment.sandbox(
              bundleId: config.appleConfig!.bundleId,
              issuerId: config.appleConfig!.issuerId,
              keyId: config.appleConfig!.keyId,
              privateKey: config.appleConfig!.privateKey,
            )
          : AppStoreEnvironment.live(
              bundleId: config.appleConfig!.bundleId,
              issuerId: config.appleConfig!.issuerId,
              keyId: config.appleConfig!.keyId,
              privateKey: config.appleConfig!.privateKey,
            );

      final appStoreHttpClient = AppStoreServerHttpClient(appStoreEnvironment);
      final api = AppStoreServerAPI(appStoreHttpClient);

      final statusResponse = await api.getAllSubscriptionStatuses(
        subscriptionToken,
      );

      for (final status in statusResponse.data) {
        for (final subs in status.lastTransactions) {
          return subs.status == 1; // 1 = active, 2 = canceled, 3 = expired
        }
      }

      return false;
    } on ApiException catch (e) {
      throw Exception(
        'App Store API error (code: ${e.error?.errorCode}): '
        '${e.error?.errorMessage}',
      );
    } catch (e) {
      throw Exception('Error verifying purchase with App Store: $e');
    }
  }

  Future<bool> verifySubscriptionWithGooglePlay(
    String subscriptionToken,
  ) async {
    final config = _getConfig;
    if (config.googlePlayConfig == null) {
      throw Exception('Google Play configuration not provided');
    }

    try {
      debugPrint(
        '🔍 Verificando assinatura no Google Play com token: $subscriptionToken',
      );

      // 1. Carrega as credenciais do Service Account
      final jsonMap =
          jsonDecode(config.googlePlayConfig!.serviceAccountJson)
              as Map<String, dynamic>;
      final credentials = ServiceAccountCredentials.fromJson(jsonMap);

      // 2. Define os escopos necessários
      final scopes = ['https://www.googleapis.com/auth/androidpublisher'];

      // 3. Autentica e obtém o client HTTP autenticado
      final authClient = await clientViaServiceAccount(credentials, scopes);

      // 4. Faz a requisição usando o client autenticado
      try {
        final response = await authClient.get(
          Uri.parse(
            'https://androidpublisher.googleapis.com/androidpublisher/v3/applications/${config.googlePlayConfig!.packageName}/purchases/subscriptionsv2/tokens/$subscriptionToken',
          ),
        );

        if (response.statusCode == 200) {
          final data = jsonDecode(response.body) as Map<String, dynamic>;
          final subscriptionState = data['subscriptionState'] as String?;
          // ACTIVE = active, CANCELED = canceled, PENDING = pending
          return subscriptionState == 'SUBSCRIPTION_STATE_ACTIVE';
        } else {
          throw Exception(
            'Failed to verify subscription with Google Play: ${response.statusCode} - ${response.body}',
          );
        }
      } finally {
        // Sempre feche o client autenticado
        authClient.close();
      }
    } catch (e) {
      throw Exception('Error verifying subscription: $e');
    }
  }

  Future<bool> verifyPurchaseWithAppStore(String transactionId) async {
    final config = _getConfig;
    if (config.appleConfig == null) {
      throw Exception('Apple configuration not provided');
    }

    try {
      debugPrint(
        '🔍 Verificando compra na App Store com transactionId: '
        '$transactionId',
      );

      final appStoreEnvironment = config.appleConfig!.useSandbox
          ? AppStoreEnvironment.sandbox(
              bundleId: config.appleConfig!.bundleId,
              issuerId: config.appleConfig!.issuerId,
              keyId: config.appleConfig!.keyId,
              privateKey: config.appleConfig!.privateKey,
            )
          : AppStoreEnvironment.live(
              bundleId: config.appleConfig!.bundleId,
              issuerId: config.appleConfig!.issuerId,
              keyId: config.appleConfig!.keyId,
              privateKey: config.appleConfig!.privateKey,
            );

      final appStoreHttpClient = AppStoreServerHttpClient(appStoreEnvironment);
      final api = AppStoreServerAPI(appStoreHttpClient);

      String? revision;
      var hasMore = true;

      while (hasMore) {
        final HistoryResponse historyResponse = await api.getTransactionHistory(
          transactionId,
          revision: revision,
        );

        for (final signedTransaction in historyResponse.signedTransactions) {
          final decodedTransaction =
              JWSTransactionDecodedPayload.fromEncodedPayload(
                signedTransaction,
              );

          if (decodedTransaction.transactionId == transactionId ||
              decodedTransaction.originalTransactionId == transactionId) {
            // Verifica se a transação não foi reembolsada/revogada
            if (decodedTransaction.revocationDate == null) {
              debugPrint(
                '✅ Compra verificada com sucesso - '
                'productId: ${decodedTransaction.productId}',
              );
              return true;
            } else {
              debugPrint(
                '❌ Compra foi reembolsada/revogada - '
                'productId: ${decodedTransaction.productId}',
              );
              return false;
            }
          }
        }

        hasMore = historyResponse.hasMore;
        revision = historyResponse.revision;
      }

      debugPrint('❌ Transação não encontrada no histórico');
      return false;
    } on ApiException catch (e) {
      throw Exception(
        'App Store API error (code: ${e.error?.errorCode}): '
        '${e.error?.errorMessage}',
      );
    } catch (e) {
      throw Exception('Error verifying purchase with App Store: $e');
    }
  }

  Future<bool> verifyPurchaseWithGooglePlay(String purchaseToken) async {
    final config = _getConfig;
    if (config.googlePlayConfig == null) {
      throw Exception('Google Play configuration not provided');
    }

    try {
      debugPrint(
        '🔍 Verificando compra no Google Play com token: $purchaseToken',
      );

      // 1. Carrega as credenciais do Service Account
      final jsonMap =
          jsonDecode(config.googlePlayConfig!.serviceAccountJson)
              as Map<String, dynamic>;
      final credentials = ServiceAccountCredentials.fromJson(jsonMap);

      // 2. Define os escopos necessários
      final scopes = ['https://www.googleapis.com/auth/androidpublisher'];

      // 3. Autentica e obtém o client HTTP autenticado
      final authClient = await clientViaServiceAccount(credentials, scopes);

      // 4. Faz a requisição usando o client autenticado
      try {
        final response = await authClient.get(
          Uri.parse(
            'https://androidpublisher.googleapis.com/androidpublisher/v3/applications/${config.googlePlayConfig!.packageName}/purchases/productsv2/tokens/$purchaseToken',
          ),
        );

        if (response.statusCode == 200) {
          final data = jsonDecode(response.body) as Map<String, dynamic>;
          final purchaseState =
              data['purchaseStateContext']?['purchaseState'] as String?;
          // PURCHASED = purchased, CANCELED = canceled, PENDING = pending
          return purchaseState == 'PURCHASED';
        } else {
          throw Exception(
            'Failed to verify purchase with Google Play: ${response.statusCode} - ${response.body}',
          );
        }
      } finally {
        // Sempre feche o client autenticado
        authClient.close();
      }
    } catch (e) {
      throw Exception('Error verifying purchase with Google Play: $e');
    }
  }
}
