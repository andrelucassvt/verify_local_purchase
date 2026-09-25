import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:app_store_server_sdk/app_store_server_sdk.dart';
import 'package:flutter/foundation.dart';
import 'package:googleapis_auth/auth_io.dart';
import 'package:http/http.dart' as http;

import '../models/refund_entry.dart';
import '../models/store_platform.dart';
import '../models/verification_result.dart';
import '../models/verify_purchase_config.dart';
import '../models/verify_purchase_exception.dart';
import 'apple_jws_payload.dart';
import 'store_response_parser.dart';

/// Builds the App Store API client for an environment. Overridable in tests.
typedef AppStoreApiFactory =
    AppStoreServerAPI Function(AppStoreEnvironment environment);

/// Verification logic for both stores.
///
/// Holds its own config and caches the authenticated clients between calls
/// (Google OAuth token, App Store JWT). Call [dispose] to release them.
class VerifyPurchaseService {
  final VerifyPurchaseConfig config;

  final AppStoreApiFactory? _appStoreApiFactory;
  final DateTime Function() _now;
  final bool _isApplePlatform;

  /// Authenticated Google client injected by the caller (not owned).
  final http.Client? _injectedGoogleClient;

  /// Lazily created Google client (owned — closed on [dispose]).
  Future<AutoRefreshingAuthClient>? _googleClientFuture;

  final Map<bool, AppStoreServerAPI> _appStoreApis = {};

  /// App Store HTTP clients created here (owned — closed on [dispose]).
  final List<AppStoreServerHttpClient> _appStoreHttpClients = [];

  /// Apple error codes meaning "this transaction is not in this environment".
  static const _appleNotFoundCodes = {4040001, 4040005, 4040010};

  static const _googleScopes = [
    'https://www.googleapis.com/auth/androidpublisher',
  ];

  VerifyPurchaseService(
    this.config, {
    @visibleForTesting http.Client? googleClient,
    @visibleForTesting AppStoreApiFactory? appStoreApiFactory,
    @visibleForTesting DateTime Function()? now,
    @visibleForTesting bool? isApplePlatform,
  }) : _injectedGoogleClient = googleClient,
       _appStoreApiFactory = appStoreApiFactory,
       _now = now ?? DateTime.now,
       _isApplePlatform =
           isApplePlatform ?? (Platform.isIOS || Platform.isMacOS);

  /// Releases the cached HTTP clients.
  void dispose() {
    final future = _googleClientFuture;
    _googleClientFuture = null;
    future?.then((client) => client.close(), onError: (_) {});
    for (final client in _appStoreHttpClients) {
      client.close();
    }
    _appStoreHttpClients.clear();
    _appStoreApis.clear();
  }

  /// Verify a one-time purchase on the current platform's store.
  Future<VerificationResult> verifyPurchase(String purchaseToken) {
    return _isApplePlatform
        ? verifyPurchaseWithAppStore(purchaseToken)
        : verifyPurchaseWithGooglePlay(purchaseToken);
  }

  /// Verify a subscription on the current platform's store.
  Future<VerificationResult> verifySubscription(String subscriptionToken) {
    return _isApplePlatform
        ? verifySubscriptionWithAppStore(subscriptionToken)
        : verifySubscriptionWithGooglePlay(subscriptionToken);
  }

  // ───────────────────────────── App Store ─────────────────────────────

  Future<VerificationResult> verifySubscriptionWithAppStore(
    String originalTransactionId,
  ) async {
    _requireToken(originalTransactionId);
    _log(
      '🔍 Verificando assinatura na App Store com transactionId: '
      '${mask(originalTransactionId)}',
    );

    final result = await _callAppStore(
      (api) async => StoreResponseParser.appleSubscription(
        await api.getAllSubscriptionStatuses(originalTransactionId),
        originalTransactionId,
      ),
      onNotFound: (isSandbox) => VerificationResult.notFound(
        StorePlatform.apple,
        isSandbox: isSandbox,
      ),
    );
    _log('📋 Resultado da assinatura na App Store: $result');
    return result;
  }

  Future<VerificationResult> verifyPurchaseWithAppStore(
    String transactionId,
  ) async {
    _requireToken(transactionId);
    _log(
      '🔍 Verificando compra na App Store com transactionId: '
      '${mask(transactionId)}',
    );

    final result = await _callAppStore(
      (api) async {
        String? revision;
        var hasMore = true;

        while (hasMore) {
          final historyResponse = await api.getTransactionHistory(
            transactionId,
            revision: revision,
          );

          for (final signedTransaction in historyResponse.signedTransactions) {
            final tx = AppleJwsPayload.decode(signedTransaction);
            if (tx.transactionId == transactionId ||
                tx.originalTransactionId == transactionId) {
              return StoreResponseParser.appleTransaction(
                tx,
                environment: historyResponse.environment,
              );
            }
          }

          hasMore = historyResponse.hasMore;
          revision = historyResponse.revision;
        }

        _log('❌ Transação não encontrada no histórico');
        return const VerificationResult.notFound(StorePlatform.apple);
      },
      onNotFound: (isSandbox) => VerificationResult.notFound(
        StorePlatform.apple,
        isSandbox: isSandbox,
      ),
    );
    _log('📋 Resultado da compra na App Store: $result');
    return result;
  }

  /// Lista os reembolsos de UM cliente na App Store.
  ///
  /// Escopo: reembolsos associados ao [originalTransactionId] informado.
  /// Requer que [AppleConfig] esteja configurado no initialize.
  Future<List<RefundEntry>> getRefundsWithAppStore(
    String originalTransactionId,
  ) async {
    _requireToken(originalTransactionId);
    _log(
      '🔍 Buscando reembolsos na App Store para originalTransactionId: '
      '${mask(originalTransactionId)}',
    );

    return _callAppStore((api) async {
      final refundResponse = await api.getRefundHistory(originalTransactionId);
      return refundResponse.signedTransactions
          .map(
            (signed) =>
                StoreResponseParser.appleRefund(AppleJwsPayload.decode(signed)),
          )
          .toList();
    }, onNotFound: (_) => <RefundEntry>[]);
  }

  /// Runs [call] against the configured App Store environment(s).
  ///
  /// With [AppleEnvironment.productionWithSandboxFallback], a "not found"
  /// answer from production is retried in sandbox.
  Future<T> _callAppStore<T>(
    Future<T> Function(AppStoreServerAPI api) call, {
    required T Function(bool isSandbox) onNotFound,
  }) async {
    final apple = config.appleConfig;
    if (apple == null) {
      throw const VerifyPurchaseException(
        VerifyPurchaseErrorCode.missingConfig,
        'Apple configuration not provided',
      );
    }

    final environments = switch (apple.environment) {
      AppleEnvironment.production => [false],
      AppleEnvironment.sandbox => [true],
      AppleEnvironment.productionWithSandboxFallback => [false, true],
    };

    for (final isSandbox in environments) {
      try {
        return await call(_appStoreApi(apple, isSandbox: isSandbox));
      } on ApiException catch (e) {
        final errorCode = e.error?.errorCode;
        if (_appleNotFoundCodes.contains(errorCode)) {
          if (isSandbox != environments.last) {
            _log('↪️ Não encontrado em produção, tentando sandbox...');
            continue;
          }
          return onNotFound(isSandbox);
        }
        throw VerifyPurchaseException(
          e.statusCode == 401 || e.statusCode == 403
              ? VerifyPurchaseErrorCode.unauthorized
              : VerifyPurchaseErrorCode.apiError,
          'App Store API error: ${e.error?.errorMessage ?? e.response ?? ''}',
          statusCode: e.statusCode,
          storeErrorCode: errorCode,
          cause: e,
        );
      } catch (e) {
        throw _wrapError(e, 'App Store');
      }
    }
    // Unreachable: `environments` is never empty.
    throw StateError('No App Store environment configured');
  }

  AppStoreServerAPI _appStoreApi(AppleConfig apple, {required bool isSandbox}) {
    return _appStoreApis.putIfAbsent(isSandbox, () {
      final environment = isSandbox
          ? AppStoreEnvironment.sandbox(
              bundleId: apple.bundleId,
              issuerId: apple.issuerId,
              keyId: apple.keyId,
              privateKey: apple.privateKey,
            )
          : AppStoreEnvironment.live(
              bundleId: apple.bundleId,
              issuerId: apple.issuerId,
              keyId: apple.keyId,
              privateKey: apple.privateKey,
            );
      final factory = _appStoreApiFactory;
      if (factory != null) return factory(environment);

      final httpClient = AppStoreServerHttpClient(environment);
      _appStoreHttpClients.add(httpClient);
      return AppStoreServerAPI(httpClient);
    });
  }

  // ──────────────────────────── Google Play ────────────────────────────

  Future<VerificationResult> verifySubscriptionWithGooglePlay(
    String subscriptionToken,
  ) async {
    _requireToken(subscriptionToken);
    final packageName = _googleConfig.packageName;
    _log(
      '🔍 Verificando assinatura no Google Play com token: '
      '${mask(subscriptionToken)}',
    );

    final data = await _googleGet(
      Uri.https(
        'androidpublisher.googleapis.com',
        '/androidpublisher/v3/applications/$packageName'
            '/purchases/subscriptionsv2/tokens/$subscriptionToken',
      ),
    );
    final result = data == null
        ? const VerificationResult.notFound(StorePlatform.google)
        : StoreResponseParser.googleSubscription(data, now: _now());
    _log('📋 Resultado da assinatura no Google Play: $result');
    return result;
  }

  Future<VerificationResult> verifyPurchaseWithGooglePlay(
    String purchaseToken,
  ) async {
    _requireToken(purchaseToken);
    final packageName = _googleConfig.packageName;
    _log(
      '🔍 Verificando compra no Google Play com token: '
      '${mask(purchaseToken)}',
    );

    final data = await _googleGet(
      Uri.https(
        'androidpublisher.googleapis.com',
        '/androidpublisher/v3/applications/$packageName'
            '/purchases/productsv2/tokens/$purchaseToken',
      ),
    );
    final result = data == null
        ? const VerificationResult.notFound(StorePlatform.google)
        : StoreResponseParser.googleProduct(data);
    _log('📋 Resultado da compra no Google Play: $result');
    return result;
  }

  /// Lista os reembolsos do APP INTEIRO no Google Play, com paginação automática.
  ///
  /// Escopo: todos os reembolsos do app num período (não filtra por usuário).
  /// [startTime] e [endTime] são opcionais; se omitidos, a API retorna os
  /// últimos 30 dias por padrão.
  ///
  /// **Nota:** O endpoint `voidedpurchases` não retorna `productId` — o campo
  /// ficará nulo em cada [RefundEntry]. Para obter o produto, cruze o
  /// `originalId` (purchaseToken) com outro endpoint.
  ///
  /// Requer permissão de Financeiro no Service Account do Play Console.
  Future<List<RefundEntry>> getRefundsWithGooglePlay({
    DateTime? startTime,
    DateTime? endTime,
  }) async {
    final packageName = _googleConfig.packageName;
    _log('🔍 Buscando reembolsos no Google Play...');

    final results = <RefundEntry>[];
    String? pageToken;

    do {
      final queryParams = <String, String>{
        if (startTime != null)
          'startTime': startTime.millisecondsSinceEpoch.toString(),
        if (endTime != null)
          'endTime': endTime.millisecondsSinceEpoch.toString(),
        'token': ?pageToken,
      };

      final body = await _googleGet(
        Uri.https(
          'androidpublisher.googleapis.com',
          '/androidpublisher/v3/applications/$packageName'
              '/purchases/voidedpurchases',
          queryParams,
        ),
      );
      if (body == null) break;

      final purchases = (body['voidedPurchases'] as List<dynamic>?) ?? [];
      for (final item in purchases) {
        results.add(
          RefundEntry.fromGoogleVoidedPurchase(item as Map<String, dynamic>),
        );
      }

      final nextToken =
          (body['tokenPagination'] as Map<String, dynamic>?)?['nextPageToken']
              as String?;
      pageToken = (nextToken != null && nextToken != pageToken)
          ? nextToken
          : null;
    } while (pageToken != null);

    _log('✅ ${results.length} reembolso(s) encontrado(s) no Google Play');
    return results;
  }

  GooglePlayConfig get _googleConfig {
    final google = config.googlePlayConfig;
    if (google == null) {
      throw const VerifyPurchaseException(
        VerifyPurchaseErrorCode.missingConfig,
        'Google Play configuration not provided',
      );
    }
    return google;
  }

  /// GET on the Google Play Developer API.
  ///
  /// Returns `null` when the token is unknown or gone (404/410).
  Future<Map<String, dynamic>?> _googleGet(Uri uri) async {
    final client = await _googleClient();
    try {
      final response = await client.get(uri);

      if (response.statusCode == 404 || response.statusCode == 410) {
        return null;
      }
      if (response.statusCode != 200) {
        throw VerifyPurchaseException(
          response.statusCode == 401 || response.statusCode == 403
              ? VerifyPurchaseErrorCode.unauthorized
              : VerifyPurchaseErrorCode.apiError,
          'Google Play API error: ${response.body}',
          statusCode: response.statusCode,
        );
      }

      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) {
        throw const VerifyPurchaseException(
          VerifyPurchaseErrorCode.invalidResponse,
          'Google Play returned an unexpected payload',
        );
      }
      return decoded;
    } catch (e) {
      throw _wrapError(e, 'Google Play');
    }
  }

  Future<http.Client> _googleClient() async {
    final injected = _injectedGoogleClient;
    if (injected != null) return injected;

    final google = _googleConfig;
    final future = _googleClientFuture ??= () async {
      final ServiceAccountCredentials credentials;
      try {
        credentials = ServiceAccountCredentials.fromJson(
          jsonDecode(google.serviceAccountJson),
        );
      } catch (e) {
        throw VerifyPurchaseException(
          VerifyPurchaseErrorCode.invalidCredentials,
          'Invalid Google Play service account JSON',
          cause: e,
        );
      }
      try {
        return await clientViaServiceAccount(credentials, _googleScopes);
      } catch (e) {
        throw _wrapError(e, 'Google Play');
      }
    }();

    try {
      return await future;
    } catch (_) {
      // Do not cache a failed authentication — the next call retries.
      if (identical(_googleClientFuture, future)) _googleClientFuture = null;
      rethrow;
    }
  }

  // ────────────────────────────── helpers ──────────────────────────────

  VerifyPurchaseException _wrapError(Object e, String store) {
    if (e is VerifyPurchaseException) return e;
    if (e is SocketException || e is http.ClientException) {
      return VerifyPurchaseException(
        VerifyPurchaseErrorCode.networkError,
        'Could not reach $store: $e',
        cause: e,
      );
    }
    if (e is AccessDeniedException) {
      return VerifyPurchaseException(
        VerifyPurchaseErrorCode.unauthorized,
        '$store rejected the credentials: ${e.message}',
        cause: e,
      );
    }
    if (e is FormatException || e is TypeError) {
      return VerifyPurchaseException(
        VerifyPurchaseErrorCode.invalidResponse,
        'Unexpected response from $store: $e',
        cause: e,
      );
    }
    return VerifyPurchaseException(
      VerifyPurchaseErrorCode.unknown,
      'Error calling $store: $e',
      cause: e,
    );
  }

  void _requireToken(String token) {
    if (token.trim().isEmpty) {
      throw const VerifyPurchaseException(
        VerifyPurchaseErrorCode.invalidToken,
        'Purchase token/transaction ID is empty',
      );
    }
  }

  void _log(String message) {
    if (config.enableLogging) debugPrint(message);
  }

  /// Keeps only the edges of a token so logs do not leak it.
  @visibleForTesting
  static String mask(String token) {
    if (token.length <= 12) return '***';
    return '${token.substring(0, 6)}…${token.substring(token.length - 4)}';
  }
}
