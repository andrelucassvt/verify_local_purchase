# Testes — PaywallCubit e LocalEntitlementService com fakes

Índice: 1. Por que testar o Cubit · 2. Fakes · 3. Testes do Cubit · 4. Testes do `LocalEntitlementService` (🅰)

A loja não roda em teste, e é exatamente por isso que a máquina de estados do Cubit precisa de prova
automatizada: cada linha da tabela do Passo 4 vira um `blocTest`. Segue `flutter-expert/references/testing.md`
(fakes concretos, `blocTest`, Arrange → Act → Assert).

---

## 1. Por que testar o Cubit

Os bugs clássicos de IAP (loading infinito, compra completada sem verificar, `pop` duplicado, "nada a
restaurar" nunca aparecendo) são todos bugs de sequência de estados — e sequência de estados é o que
`blocTest` verifica. Os timeouts injetáveis existem para o teste do watchdog levar milissegundos.

---

## 2. Fakes

`test/presentation/paywall/fakes/fake_in_app_purchase_service.dart`

```dart
import 'dart:async';

import 'package:base_app/common/services/in_app_purchase/entitlement_service.dart';
import 'package:base_app/common/services/in_app_purchase/in_app_purchase_service.dart';
import 'package:in_app_purchase/in_app_purchase.dart';

class FakeInAppPurchaseService implements InAppPurchaseService {
  final controller = StreamController<List<PurchaseDetails>>.broadcast();
  List<ProductDetails> products = [];
  ProductLoadException? loadFailure;
  Object? buyFailure;
  final completed = <PurchaseDetails>[];
  int restoreCalls = 0;

  @override
  Stream<List<PurchaseDetails>> get purchaseStream => controller.stream;

  @override
  Future<List<ProductDetails>> loadProducts() async {
    final failure = loadFailure;
    if (failure != null) throw failure;
    return products;
  }

  @override
  Future<void> buy(ProductDetails product) async {
    final failure = buyFailure;
    if (failure != null) throw failure;
  }

  @override
  Future<void> restorePurchases() async {
    restoreCalls++;
  }

  @override
  Future<void> completePurchase(PurchaseDetails purchase) async {
    completed.add(purchase);
  }

  /// Simula o que a loja entrega pelo purchaseStream.
  void deliver(List<PurchaseDetails> purchases) => controller.add(purchases);
}

class FakeEntitlementService implements EntitlementService {
  GrantResult result = GrantResult.valid;
  final verified = <PurchaseDetails>[];

  @override
  Future<GrantResult> verifyAndGrant(PurchaseDetails purchase) async {
    verified.add(purchase);
    return result;
  }

  @override
  Future<bool> hasAccess(String productId) async => false;

  @override
  Future<void> refresh() async {}
}
```

---

## 3. Testes do Cubit

`test/presentation/paywall/paywall_cubit_test.dart`

```dart
import 'package:base_app/common/services/in_app_purchase/entitlement_service.dart';
import 'package:base_app/common/services/in_app_purchase/in_app_purchase_service.dart';
import 'package:base_app/presentation/paywall/view_model/paywall_cubit.dart';
import 'package:base_app/presentation/paywall/view_model/paywall_state.dart';
import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:in_app_purchase/in_app_purchase.dart';

import 'fakes/fake_in_app_purchase_service.dart';

ProductDetails _product(String id) => ProductDetails(
      id: id,
      title: 'Premium',
      description: 'Acesso total',
      price: r'R$ 9,90',
      rawPrice: 9.9,
      currencyCode: 'BRL',
    );

PurchaseDetails _purchase(String id, PurchaseStatus status) => PurchaseDetails(
      purchaseID: 'tx_$id',
      productID: id,
      verificationData: PurchaseVerificationData(
        localVerificationData: '{}',
        serverVerificationData: 'jws',
        source: 'app_store',
      ),
      transactionDate: null,
      status: status,
    )..pendingCompletePurchase = true;

void main() {
  late FakeInAppPurchaseService iap;
  late FakeEntitlementService entitlements;
  final premium = _product('premium_monthly');

  setUp(() {
    iap = FakeInAppPurchaseService()..products = [premium];
    entitlements = FakeEntitlementService();
  });

  tearDown(() => iap.controller.close());

  PaywallCubit buildCubit({Duration buyTimeout = const Duration(minutes: 2)}) =>
      PaywallCubit(iap, entitlements, buyTimeout: buyTimeout);

  final loaded = isA<PaywallLoaded>()
      .having((s) => s.inProgress, 'inProgress', false)
      .having((s) => s.notice, 'notice', isNull);
  final locked = isA<PaywallLoaded>().having((s) => s.inProgress, 'inProgress', true);
  Matcher unlockedWith(PaywallNotice notice) => isA<PaywallLoaded>()
      .having((s) => s.inProgress, 'inProgress', false)
      .having((s) => s.notice, 'notice', notice);

  group('loadProducts', () {
    blocTest<PaywallCubit, PaywallState>(
      'whenStoreReturnsProducts_emitsLoadingThenLoaded',
      build: buildCubit,
      act: (cubit) => cubit.loadProducts(),
      expect: () => [isA<PaywallLoading>(), loaded],
    );

    blocTest<PaywallCubit, PaywallState>(
      'whenStoreUnavailable_emitsErrorWithKind',
      build: () {
        iap.loadFailure = const StoreUnavailableException();
        return buildCubit();
      },
      act: (cubit) => cubit.loadProducts(),
      expect: () => [
        isA<PaywallLoading>(),
        isA<PaywallError>()
            .having((s) => s.kind, 'kind', PaywallErrorKind.storeUnavailable),
      ],
    );
  });

  group('buy', () {
    blocTest<PaywallCubit, PaywallState>(
      'whenPurchasedAndValid_completesAndEmitsSuccess',
      build: buildCubit,
      act: (cubit) async {
        await cubit.loadProducts();
        await cubit.buy(premium);
        iap.deliver([_purchase(premium.id, PurchaseStatus.purchased)]);
      },
      wait: const Duration(milliseconds: 20),
      expect: () => [
        isA<PaywallLoading>(),
        loaded,
        locked,
        isA<PaywallSuccess>().having((s) => s.productId, 'productId', premium.id),
      ],
      verify: (_) => expect(iap.completed, hasLength(1)),
    );

    blocTest<PaywallCubit, PaywallState>(
      'whenCanceled_completesPendingAndUnlocksWithoutNotice',
      build: buildCubit,
      act: (cubit) async {
        await cubit.loadProducts();
        await cubit.buy(premium);
        iap.deliver([_purchase(premium.id, PurchaseStatus.canceled)]);
      },
      wait: const Duration(milliseconds: 20),
      expect: () => [isA<PaywallLoading>(), loaded, locked, loaded],
      verify: (_) => expect(iap.completed, hasLength(1)),
    );

    blocTest<PaywallCubit, PaywallState>(
      'whenVerificationUnavailable_doesNotCompleteAndNotifies',
      build: () {
        entitlements.result = GrantResult.unavailable;
        return buildCubit();
      },
      act: (cubit) async {
        await cubit.loadProducts();
        await cubit.buy(premium);
        iap.deliver([_purchase(premium.id, PurchaseStatus.purchased)]);
      },
      wait: const Duration(milliseconds: 20),
      expect: () => [
        isA<PaywallLoading>(),
        loaded,
        locked,
        unlockedWith(PaywallNotice.verificationUnavailable),
      ],
      verify: (_) => expect(iap.completed, isEmpty),
    );

    blocTest<PaywallCubit, PaywallState>(
      'whenVerificationInvalid_completesAndNotifies',
      build: () {
        entitlements.result = GrantResult.invalid;
        return buildCubit();
      },
      act: (cubit) async {
        await cubit.loadProducts();
        await cubit.buy(premium);
        iap.deliver([_purchase(premium.id, PurchaseStatus.purchased)]);
      },
      wait: const Duration(milliseconds: 20),
      expect: () => [
        isA<PaywallLoading>(),
        loaded,
        locked,
        unlockedWith(PaywallNotice.verificationFailed),
      ],
      verify: (_) => expect(iap.completed, hasLength(1)),
    );

    blocTest<PaywallCubit, PaywallState>(
      'whenStoreNeverAnswers_watchdogUnlocks',
      build: () => buildCubit(buyTimeout: const Duration(milliseconds: 50)),
      act: (cubit) async {
        await cubit.loadProducts();
        await cubit.buy(premium);
      },
      wait: const Duration(milliseconds: 120),
      expect: () => [
        isA<PaywallLoading>(),
        loaded,
        locked,
        unlockedWith(PaywallNotice.storeTimeout),
      ],
    );
  });

  group('restore', () {
    blocTest<PaywallCubit, PaywallState>(
      'whenStoreDeliversEmptyList_notifiesNothingToRestore',
      build: buildCubit,
      act: (cubit) async {
        await cubit.loadProducts();
        await cubit.restore();
        iap.deliver([]);
      },
      wait: const Duration(milliseconds: 20),
      expect: () => [
        isA<PaywallLoading>(),
        loaded,
        locked,
        unlockedWith(PaywallNotice.nothingToRestore),
      ],
      verify: (_) => expect(iap.restoreCalls, 1),
    );

    blocTest<PaywallCubit, PaywallState>(
      'whenRestoredPurchaseCannotBeVerified_notifiesCauseNotNothingToRestore',
      build: () {
        entitlements.result = GrantResult.unavailable;
        return buildCubit();
      },
      act: (cubit) async {
        await cubit.loadProducts();
        await cubit.restore();
        iap.deliver([_purchase(premium.id, PurchaseStatus.restored)]);
      },
      wait: const Duration(milliseconds: 20),
      expect: () => [
        isA<PaywallLoading>(),
        loaded,
        locked,
        unlockedWith(PaywallNotice.verificationUnavailable),
      ],
      verify: (_) => expect(iap.completed, isEmpty),
    );

    blocTest<PaywallCubit, PaywallState>(
      'whenTwoValidPurchasesRestored_emitsSuccessOnce',
      build: buildCubit,
      act: (cubit) async {
        await cubit.loadProducts();
        await cubit.restore();
        iap.deliver([
          _purchase(premium.id, PurchaseStatus.restored),
          _purchase('premium_yearly', PurchaseStatus.restored),
        ]);
      },
      wait: const Duration(milliseconds: 20),
      expect: () => [isA<PaywallLoading>(), loaded, locked, isA<PaywallSuccess>()],
      verify: (_) => expect(iap.completed, hasLength(2)),
    );
  });
}
```

Adicione um teste para cada comportamento que a resposta do Passo 1 introduzir (ex.: consumível creditando
uma única vez).

---

## 4. Testes do `LocalEntitlementService` (🅰)

É aqui que mora a tradução `VerificationResult` → `GrantResult` (service.md §5.3) — errar uma linha dessa
tabela é perder compra paga ou dar premium de graça. O `PurchaseVerifier` fake devolve `VerificationResult`
montados à mão (o construtor do pacote é público e `const`); a rede da Apple/Google nunca entra em teste
unitário, e `tokenOf` fake evita depender de `Platform.isIOS` do host que roda o teste.

`test/common/services/in_app_purchase/local_entitlement_service_test.dart`

```dart
import 'package:base_app/common/services/in_app_purchase/entitlement_service.dart';
import 'package:base_app/common/services/in_app_purchase/local_entitlement_service.dart';
import 'package:base_app/common/services/in_app_purchase/purchase_verifier.dart';
import 'package:base_app/common/services/storage_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:verify_local_purchase/verify_local_purchase.dart';

/// Ajuste as assinaturas às do `StorageService` do projeto.
class FakeStorageService extends Fake implements StorageService {
  final values = <String, String>{};

  @override
  Future<String?> getString(String key) async => values[key];

  @override
  Future<void> setString(String key, String value) async => values[key] = value;

  @override
  Future<void> remove(String key) async => values.remove(key);
}

class FakePurchaseVerifier implements PurchaseVerifier {
  VerificationResult? result;
  Object? error;
  final verifiedTokens = <String>[];

  @override
  String tokenOf(PurchaseDetails purchase, {required bool subscription}) =>
      purchase.purchaseID!;

  @override
  Future<VerificationResult> verify(
    String token,
    StorePlatform platform, {
    required bool subscription,
  }) async {
    verifiedTokens.add(token);
    final failure = error;
    if (failure != null) throw failure;
    return result!;
  }
}

VerificationResult _result(
  VerificationState state, {
  bool isValid = false,
  String? productId = 'premium_monthly',
  DateTime? expiresAt,
}) =>
    VerificationResult(
      isValid: isValid,
      state: state,
      platform: StorePlatform.apple,
      productId: productId,
      expiresAt: expiresAt,
    );

PurchaseDetails _purchase(String id) => PurchaseDetails(
      purchaseID: 'tx_$id',
      productID: id,
      verificationData: PurchaseVerificationData(
        localVerificationData: '{}',
        serverVerificationData: 'jws',
        source: 'app_store',
      ),
      transactionDate: null,
      status: PurchaseStatus.purchased,
    );

void main() {
  late FakeStorageService storage;
  late FakePurchaseVerifier verifier;
  var now = DateTime(2026, 9, 24);
  final inAMonth = DateTime(2026, 10, 24);

  setUp(() {
    storage = FakeStorageService();
    verifier = FakePurchaseVerifier();
    now = DateTime(2026, 9, 24);
  });

  LocalEntitlementService build() =>
      LocalEntitlementService(storage, verifier: verifier, now: () => now);

  group('verifyAndGrant', () {
    test('whenSubscriptionActive_returnsValidAndGrantsAccess', () async {
      verifier.result = _result(VerificationState.active, isValid: true, expiresAt: inAMonth);
      final service = build();

      expect(await service.verifyAndGrant(_purchase('premium_monthly')), GrantResult.valid);
      expect(await service.hasAccess('premium_monthly'), isTrue);
    });

    test('whenNetworkError_returnsUnavailableAndGrantsNothing', () async {
      verifier.error = const VerifyPurchaseException(VerifyPurchaseErrorCode.networkError, 'offline');
      final service = build();

      expect(await service.verifyAndGrant(_purchase('premium_monthly')), GrantResult.unavailable);
      expect(await service.hasAccess('premium_monthly'), isFalse);
    });

    test('whenMisconfigured_returnsUnavailableNotInvalid', () async {
      verifier.error = const VerifyPurchaseException(VerifyPurchaseErrorCode.unauthorized, '401');

      expect(await build().verifyAndGrant(_purchase('premium_monthly')), GrantResult.unavailable);
    });

    test('whenNotFound_returnsInvalid', () async {
      verifier.result = _result(VerificationState.notFound, productId: null);

      expect(await build().verifyAndGrant(_purchase('premium_monthly')), GrantResult.invalid);
    });

    test('whenPending_returnsUnavailable', () async {
      verifier.result = _result(VerificationState.pending);

      expect(await build().verifyAndGrant(_purchase('premium_monthly')), GrantResult.unavailable);
    });

    test('whenStoreReportsAnotherProduct_returnsInvalid', () async {
      verifier.result = _result(VerificationState.purchased, isValid: true, productId: 'coins_100');

      expect(await build().verifyAndGrant(_purchase('remove_ads')), GrantResult.invalid);
    });

    test('whenSubscriptionUpgraded_grantsTheCurrentPlan', () async {
      verifier.result = _result(
        VerificationState.active,
        isValid: true,
        productId: 'premium_yearly',
        expiresAt: inAMonth,
      );
      final service = build();

      expect(await service.verifyAndGrant(_purchase('premium_monthly')), GrantResult.valid);
      expect(await service.hasAccess('premium_yearly'), isTrue);
    });
  });

  group('refresh', () {
    Future<LocalEntitlementService> subscribed() async {
      verifier.result = _result(VerificationState.active, isValid: true, expiresAt: inAMonth);
      final service = build();
      await service.verifyAndGrant(_purchase('premium_monthly'));
      return service;
    }

    test('whenRevoked_removesTheRecord', () async {
      final service = await subscribed();
      verifier.result = _result(VerificationState.revoked);

      await service.refresh();

      expect(storage.values[LocalEntitlementService.entitlementKey('premium_monthly')], isNull);
    });

    test('whenExpired_deniesAccessButKeepsTheToken', () async {
      final service = await subscribed();
      verifier.result = _result(VerificationState.expired, expiresAt: now);

      await service.refresh();

      expect(await service.hasAccess('premium_monthly'), isFalse);
      verifier.result = _result(VerificationState.active, isValid: true, expiresAt: inAMonth);
      await service.refresh(); // reassinou: o mesmo token volta a valer
      expect(await service.hasAccess('premium_monthly'), isTrue);
    });

    test('whenOffline_keepsAccessUntilExpiryPlusTolerance', () async {
      final service = await subscribed();
      verifier.error = const VerifyPurchaseException(VerifyPurchaseErrorCode.networkError, 'offline');

      now = inAMonth.add(const Duration(days: 1));
      await service.refresh();
      expect(await service.hasAccess('premium_monthly'), isTrue);

      now = inAMonth.add(LocalEntitlementService.offlineTolerance);
      expect(await service.hasAccess('premium_monthly'), isFalse);
    });
  });
}
```

Para `grantResultOf`, um teste por linha da tabela da seção 5.3 do `service.md` (é função estática pura —
chame direto, sem service).
