import 'dart:convert';

import 'package:app_store_server_sdk/app_store_server_sdk.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:verify_local_purchase/service/verify_purchase_service.dart';
import 'package:verify_local_purchase/verify_local_purchase.dart';

import 'helpers/apple_fixtures.dart';

const _apple = AppleConfig(
  bundleId: 'com.example.app',
  issuerId: 'issuer',
  keyId: 'keyId',
  privateKey: 'privateKey',
);

const _google = GooglePlayConfig(
  packageName: 'com.example.app',
  serviceAccountJson: '{}',
);

Matcher _throwsCode(VerifyPurchaseErrorCode code) =>
    throwsA(isA<VerifyPurchaseException>().having((e) => e.code, 'code', code));

/// App Store API that answers per environment host.
class _FakeAppStoreApi implements AppStoreServerAPI {
  _FakeAppStoreApi(this.isSandbox, this.statuses);

  final bool isSandbox;
  final Future<StatusResponse> Function(bool isSandbox) statuses;

  @override
  Future<StatusResponse> getAllSubscriptionStatuses(
    String originalTransactionId,
  ) => statuses(isSandbox);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

ApiException _appleError(int statusCode, int errorCode) =>
    ApiException(statusCode, error: ApiError(errorCode, 'error $errorCode'));

VerifyPurchaseService _appleService(
  Future<StatusResponse> Function(bool isSandbox) statuses, {
  AppleEnvironment environment = AppleEnvironment.productionWithSandboxFallback,
}) {
  return VerifyPurchaseService(
    VerifyPurchaseConfig(
      appleConfig: AppleConfig(
        bundleId: _apple.bundleId,
        issuerId: _apple.issuerId,
        keyId: _apple.keyId,
        privateKey: _apple.privateKey,
        environment: environment,
      ),
    ),
    appStoreApiFactory: (env) =>
        _FakeAppStoreApi(env.host.contains('sandbox'), statuses),
    isApplePlatform: true,
  );
}

VerifyPurchaseService _googleService(MockClientHandler handler) {
  return VerifyPurchaseService(
    const VerifyPurchaseConfig(googlePlayConfig: _google),
    googleClient: MockClient(handler),
    now: () => DateTime.utc(2026, 1, 1),
    isApplePlatform: false,
  );
}

void main() {
  group('missing config', () {
    test('Apple methods throw missingConfig without appleConfig', () {
      final service = VerifyPurchaseService(
        const VerifyPurchaseConfig(googlePlayConfig: _google),
      );
      expect(
        () => service.getRefundsWithAppStore('orig_tx_001'),
        throwsA(
          isA<VerifyPurchaseException>()
              .having(
                (e) => e.code,
                'code',
                VerifyPurchaseErrorCode.missingConfig,
              )
              .having(
                (e) => e.message,
                'message',
                'Apple configuration not provided',
              ),
        ),
      );
    });

    test('Google methods throw missingConfig without googlePlayConfig', () {
      final service = VerifyPurchaseService(
        const VerifyPurchaseConfig(appleConfig: _apple),
      );
      expect(
        () => service.getRefundsWithGooglePlay(),
        throwsA(
          isA<VerifyPurchaseException>()
              .having(
                (e) => e.code,
                'code',
                VerifyPurchaseErrorCode.missingConfig,
              )
              .having(
                (e) => e.message,
                'message',
                'Google Play configuration not provided',
              ),
        ),
      );
    });

    test('facade throws notInitialized before initialize()', () {
      VerifyLocalPurchase.dispose();
      expect(
        () => VerifyLocalPurchase.verifyPurchase('token'),
        _throwsCode(VerifyPurchaseErrorCode.notInitialized),
      );
    });
  });

  group('Google Play', () {
    test('calls subscriptionsv2 and parses the response', () async {
      late Uri calledUri;
      final service = _googleService((request) async {
        calledUri = request.url;
        return http.Response(
          jsonEncode({
            'subscriptionState': 'SUBSCRIPTION_STATE_ACTIVE',
            'lineItems': [
              {'productId': 'premium', 'expiryTime': '2026-02-01T00:00:00Z'},
            ],
          }),
          200,
        );
      });

      final result = await service.verifySubscription('sub_token');

      expect(
        calledUri.path,
        '/androidpublisher/v3/applications/com.example.app'
        '/purchases/subscriptionsv2/tokens/sub_token',
      );
      expect(result.isValid, isTrue);
      expect(result.productId, 'premium');
    });

    for (final status in [404, 410]) {
      test('HTTP $status → notFound result', () async {
        final service = _googleService(
          (_) async => http.Response('{}', status),
        );
        final result = await service.verifyPurchase('token');
        expect(result.isValid, isFalse);
        expect(result.state, VerificationState.notFound);
      });
    }

    test('HTTP 401 → unauthorized', () {
      final service = _googleService((_) async => http.Response('denied', 401));
      expect(
        () => service.verifyPurchase('token'),
        _throwsCode(VerifyPurchaseErrorCode.unauthorized),
      );
    });

    test('HTTP 500 → apiError with statusCode', () {
      final service = _googleService((_) async => http.Response('boom', 500));
      expect(
        () => service.verifySubscription('token'),
        throwsA(
          isA<VerifyPurchaseException>()
              .having((e) => e.code, 'code', VerifyPurchaseErrorCode.apiError)
              .having((e) => e.statusCode, 'statusCode', 500),
        ),
      );
    });

    test('connection failure → networkError', () {
      final service = _googleService(
        (_) async => throw http.ClientException('offline'),
      );
      expect(
        () => service.verifyPurchase('token'),
        _throwsCode(VerifyPurchaseErrorCode.networkError),
      );
    });

    test('non-JSON body → invalidResponse', () {
      final service = _googleService((_) async => http.Response('<html>', 200));
      expect(
        () => service.verifyPurchase('token'),
        _throwsCode(VerifyPurchaseErrorCode.invalidResponse),
      );
    });

    test('empty token → invalidToken without calling the API', () {
      var called = false;
      final service = _googleService((_) async {
        called = true;
        return http.Response('{}', 200);
      });
      expect(
        () => service.verifyPurchase('  '),
        _throwsCode(VerifyPurchaseErrorCode.invalidToken),
      );
      expect(called, isFalse);
    });

    test('malformed service account JSON → invalidCredentials', () {
      final service = VerifyPurchaseService(
        const VerifyPurchaseConfig(
          googlePlayConfig: GooglePlayConfig(
            packageName: 'com.example.app',
            serviceAccountJson: 'not json',
          ),
        ),
        isApplePlatform: false,
      );
      expect(
        () => service.verifyPurchase('token'),
        _throwsCode(VerifyPurchaseErrorCode.invalidCredentials),
      );
    });

    test('voidedpurchases follows pagination', () async {
      final tokens = <String?>[];
      final service = _googleService((request) async {
        final token = request.url.queryParameters['token'];
        tokens.add(token);
        return http.Response(
          jsonEncode({
            'voidedPurchases': [
              {
                'orderId': 'GPA.$token',
                'purchaseToken': 'tok',
                'voidedTimeMillis': '1700000000000',
              },
            ],
            if (token == null) 'tokenPagination': {'nextPageToken': 'page2'},
          }),
          200,
        );
      });

      final refunds = await service.getRefundsWithGooglePlay();

      expect(tokens, [null, 'page2']);
      expect(refunds, hasLength(2));
    });
  });

  group('App Store', () {
    final active = appleStatusResponse([
      [appleLastTransaction(status: 1)],
    ], environment: 'Sandbox');

    test(
      'falls back to sandbox when production does not know the id',
      () async {
        final calls = <bool>[];
        final service = _appleService((isSandbox) async {
          calls.add(isSandbox);
          if (!isSandbox) throw _appleError(404, 4040010);
          return active;
        });

        final result = await service.verifySubscription('orig_1');

        expect(calls, [false, true]);
        expect(result.isValid, isTrue);
        expect(result.isSandbox, isTrue);
      },
    );

    test('production only → notFound without trying sandbox', () async {
      final calls = <bool>[];
      final service = _appleService((isSandbox) async {
        calls.add(isSandbox);
        throw _appleError(404, 4040010);
      }, environment: AppleEnvironment.production);

      final result = await service.verifySubscription('orig_1');

      expect(calls, [false]);
      expect(result.state, VerificationState.notFound);
    });

    test('not found in both environments → notFound', () async {
      final service = _appleService(
        (_) async => throw _appleError(404, 4040005),
      );
      final result = await service.verifySubscription('orig_1');
      expect(result.state, VerificationState.notFound);
      expect(result.isSandbox, isTrue);
    });

    test('HTTP 401 → unauthorized, no fallback', () {
      final calls = <bool>[];
      final service = _appleService((isSandbox) async {
        calls.add(isSandbox);
        throw _appleError(401, 4010001);
      });
      expect(
        () => service.verifySubscription('orig_1'),
        throwsA(
          isA<VerifyPurchaseException>()
              .having(
                (e) => e.code,
                'code',
                VerifyPurchaseErrorCode.unauthorized,
              )
              .having((e) => e.storeErrorCode, 'storeErrorCode', 4010001),
        ),
      );
    });
  });

  group('mask', () {
    test('hides the middle of long tokens', () {
      expect(VerifyPurchaseService.mask('abcdef1234567890wxyz'), 'abcdef…wxyz');
    });

    test('hides short tokens entirely', () {
      expect(VerifyPurchaseService.mask('short'), '***');
    });
  });
}
