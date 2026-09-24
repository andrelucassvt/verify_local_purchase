import 'package:app_store_server_sdk/app_store_server_sdk.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:verify_local_purchase/models/store_platform.dart';
import 'package:verify_local_purchase/models/verification_result.dart';
import 'package:verify_local_purchase/service/store_response_parser.dart';

import 'helpers/apple_fixtures.dart';

void main() {
  final now = DateTime.utc(2026, 1, 1);
  final future = DateTime.utc(2026, 2, 1);
  final past = DateTime.utc(2025, 12, 1);

  group('StoreResponseParser.googleSubscription', () {
    Map<String, dynamic> sub(
      String state, {
      DateTime? expiry,
      bool? autoRenew = true,
    }) {
      return {
        'subscriptionState': 'SUBSCRIPTION_STATE_$state',
        'lineItems': [
          {
            'productId': 'premium_monthly',
            if (expiry != null) 'expiryTime': expiry.toIso8601String(),
            if (autoRenew != null)
              'autoRenewingPlan': {'autoRenewEnabled': autoRenew},
          },
        ],
      };
    }

    final cases = <(String, DateTime?, bool, VerificationState)>[
      ('ACTIVE', future, true, VerificationState.active),
      ('CANCELED', future, true, VerificationState.canceled),
      ('CANCELED', past, false, VerificationState.canceled),
      ('CANCELED', null, false, VerificationState.canceled),
      ('IN_GRACE_PERIOD', future, true, VerificationState.gracePeriod),
      ('PENDING', future, false, VerificationState.pending),
      ('ON_HOLD', past, false, VerificationState.onHold),
      ('PAUSED', past, false, VerificationState.paused),
      ('EXPIRED', past, false, VerificationState.expired),
      ('ACTIVE', past, false, VerificationState.active),
      ('SOMETHING_NEW', future, false, VerificationState.unknown),
    ];

    for (final (state, expiry, isValid, expected) in cases) {
      test('$state expiring $expiry → isValid: $isValid', () {
        final result = StoreResponseParser.googleSubscription(
          sub(state, expiry: expiry),
          now: now,
        );
        expect(result.isValid, isValid);
        expect(result.state, expected);
        expect(result.platform, StorePlatform.google);
      });
    }

    test(
      'maps product, expiration and auto-renew from the latest line item',
      () {
        final result = StoreResponseParser.googleSubscription({
          'subscriptionState': 'SUBSCRIPTION_STATE_ACTIVE',
          'lineItems': [
            {
              'productId': 'old',
              'expiryTime': past.toIso8601String(),
              'autoRenewingPlan': {'autoRenewEnabled': false},
            },
            {
              'productId': 'premium_yearly',
              'expiryTime': future.toIso8601String(),
              'autoRenewingPlan': {'autoRenewEnabled': true},
            },
          ],
          'testPurchase': <String, dynamic>{},
        }, now: now);

        expect(result.productId, 'premium_yearly');
        expect(result.expiresAt, future);
        expect(result.willAutoRenew, isTrue);
        expect(result.isSandbox, isTrue);
      },
    );

    test('prepaid plan never auto-renews', () {
      final result = StoreResponseParser.googleSubscription({
        'subscriptionState': 'SUBSCRIPTION_STATE_ACTIVE',
        'lineItems': [
          {
            'productId': 'prepaid',
            'expiryTime': future.toIso8601String(),
            'prepaidPlan': <String, dynamic>{},
          },
        ],
      }, now: now);

      expect(result.willAutoRenew, isFalse);
      expect(result.isSandbox, isFalse);
    });
  });

  group('StoreResponseParser.googleProduct', () {
    Map<String, dynamic> product(String state) => {
      'purchaseStateContext': {'purchaseState': state},
      'productLineItem': [
        {'productId': 'coins_100'},
      ],
    };

    test('PURCHASED is valid', () {
      final result = StoreResponseParser.googleProduct(product('PURCHASED'));
      expect(result.isValid, isTrue);
      expect(result.state, VerificationState.purchased);
      expect(result.productId, 'coins_100');
    });

    test('PENDING is not valid', () {
      final result = StoreResponseParser.googleProduct(product('PENDING'));
      expect(result.isValid, isFalse);
      expect(result.state, VerificationState.pending);
    });

    test('CANCELLED is revoked', () {
      final result = StoreResponseParser.googleProduct(product('CANCELLED'));
      expect(result.isValid, isFalse);
      expect(result.state, VerificationState.revoked);
    });

    test('test purchases are flagged as sandbox', () {
      final result = StoreResponseParser.googleProduct({
        ...product('PURCHASED'),
        'testPurchaseContext': {'fopType': 'TEST'},
      });
      expect(result.isSandbox, isTrue);
    });
  });

  group('StoreResponseParser.appleSubscription', () {
    final expires = future.millisecondsSinceEpoch;

    final cases = <(int, int, bool, VerificationState)>[
      (1, 1, true, VerificationState.active),
      (1, 0, true, VerificationState.canceled),
      (4, 1, true, VerificationState.gracePeriod),
      (3, 1, false, VerificationState.billingRetry),
      (2, 0, false, VerificationState.expired),
      (5, 0, false, VerificationState.revoked),
    ];

    for (final (status, autoRenew, isValid, expected) in cases) {
      test('status $status / autoRenew $autoRenew → isValid: $isValid', () {
        final result = StoreResponseParser.appleSubscription(
          appleStatusResponse([
            [
              appleLastTransaction(
                status: status,
                autoRenewStatus: autoRenew,
                expiresDate: expires,
              ),
            ],
          ]),
          'orig_1',
        );
        expect(result.isValid, isValid);
        expect(result.state, expected);
        expect(result.platform, StorePlatform.apple);
        expect(result.expiresAt, DateTime.fromMillisecondsSinceEpoch(expires));
        expect(result.willAutoRenew, autoRenew == 1);
      });
    }

    test('prefers the entry matching the originalTransactionId', () {
      final result = StoreResponseParser.appleSubscription(
        appleStatusResponse([
          [appleLastTransaction(status: 1, originalTransactionId: 'other')],
          [
            appleLastTransaction(
              status: 2,
              originalTransactionId: 'orig_1',
              productId: 'mine',
            ),
          ],
        ]),
        'orig_1',
      );
      expect(result.isValid, isFalse);
      expect(result.productId, 'mine');
    });

    test('without a match, the best status across all groups wins', () {
      final result = StoreResponseParser.appleSubscription(
        appleStatusResponse([
          [appleLastTransaction(status: 2, originalTransactionId: 'a')],
          [
            appleLastTransaction(
              status: 1,
              originalTransactionId: 'b',
              productId: 'active_one',
            ),
          ],
        ]),
        'some_other_transaction',
      );
      expect(result.isValid, isTrue);
      expect(result.productId, 'active_one');
    });

    test('no subscriptions → notFound', () {
      final result = StoreResponseParser.appleSubscription(
        appleStatusResponse([], environment: 'Sandbox'),
        'orig_1',
      );
      expect(result.isValid, isFalse);
      expect(result.state, VerificationState.notFound);
      expect(result.isSandbox, isTrue);
    });
  });

  group('StoreResponseParser.appleTransaction', () {
    test('not revoked → purchased', () {
      final tx = JWSTransactionDecodedPayload.fromJson(appleTransactionJson());
      final result = StoreResponseParser.appleTransaction(
        tx,
        environment: 'Production',
      );
      expect(result.isValid, isTrue);
      expect(result.state, VerificationState.purchased);
      expect(result.productId, 'premium_monthly');
      expect(result.isSandbox, isFalse);
    });

    test('revoked → revoked', () {
      final tx = JWSTransactionDecodedPayload.fromJson(
        appleTransactionJson(revocationDate: 1700000000000),
      );
      final result = StoreResponseParser.appleTransaction(
        tx,
        environment: 'Sandbox',
      );
      expect(result.isValid, isFalse);
      expect(result.state, VerificationState.revoked);
      expect(result.isSandbox, isTrue);
    });
  });
}
