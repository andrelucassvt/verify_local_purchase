# Service — PurchaseIds, InAppPurchaseService e EntitlementService

Índice: 1. PurchaseIds · 2. InAppPurchaseService (interface) · 3. InAppPurchaseServiceImpl ·
4. EntitlementService (contrato) · 5. PurchaseVerifier + LocalEntitlementService (modo 🅰) · 6. Ofertas de assinatura no Android ·
7. Apps com login: registro do aparelho, espelho remoto e grant manual

Imports usam `package:base_app/...` — troque pelo nome do pacote do projeto. Interface e implementação ficam em
arquivos separados, como manda `flutter-expert/references/service.md`; é o que permite os fakes de
`references/testing.md`.

---

## 1. PurchaseIds

`lib/common/services/in_app_purchase/purchase_ids.dart`

```dart
/// IDs dos produtos exatamente como cadastrados no App Store Connect e no
/// Google Play Console (resposta 3 do Passo 1). Sets vazios são permitidos.
class PurchaseIds {
  PurchaseIds._();

  static const Set<String> consumables = {'coins_100'};
  static const Set<String> nonConsumables = {'remove_ads'};
  static const Set<String> subscriptions = {'premium_monthly', 'premium_yearly'};

  static Set<String> get all => {...consumables, ...nonConsumables, ...subscriptions};

  static bool isConsumable(String productId) => consumables.contains(productId);
  static bool isSubscription(String productId) => subscriptions.contains(productId);
}
```

Um ID no Set errado troca o método de compra e o de verificação de uma vez só — confira contra o console.

---

## 2. InAppPurchaseService — interface e exceções

`lib/common/services/in_app_purchase/in_app_purchase_service.dart`

```dart
import 'package:in_app_purchase/in_app_purchase.dart';

/// Falhas ao carregar produtos. O Cubit escolhe o `PaywallErrorKind` pelo tipo.
sealed class ProductLoadException implements Exception {
  const ProductLoadException();
}

/// `isAvailable()` devolveu false: sem Google Play/App Store, conta restrita,
/// emulador sem Play Services.
final class StoreUnavailableException extends ProductLoadException {
  const StoreUnavailableException();
}

/// A loja respondeu com erro (rede, Billing Client, StoreKit).
final class ProductQueryException extends ProductLoadException {
  const ProductQueryException(this.error);
  final IAPError error;
}

/// A loja não conhece nenhum dos IDs. Causas comuns: produto não criado ou não
/// aprovado, contrato de apps pagos não assinado, build ainda não enviada para
/// uma faixa de teste, ID digitado diferente do console.
final class ProductsNotFoundException extends ProductLoadException {
  const ProductsNotFoundException(this.notFoundIds);
  final List<String> notFoundIds;
}

/// A loja recusou abrir o fluxo de compra (`buy*` devolveu false).
final class PurchaseNotStartedException implements Exception {
  const PurchaseNotStartedException();
}

abstract class InAppPurchaseService {
  /// Único canal de resultados: compra, restauração, cancelamento, erro e pendência.
  Stream<List<PurchaseDetails>> get purchaseStream;

  Future<List<ProductDetails>> loadProducts();

  /// Só abre a loja. O resultado chega pelo [purchaseStream].
  Future<void> buy(ProductDetails product);

  /// Só pede a restauração. As compras (ou uma lista vazia) chegam pelo [purchaseStream].
  Future<void> restorePurchases();

  Future<void> completePurchase(PurchaseDetails purchase);
}
```

---

## 3. InAppPurchaseServiceImpl

`lib/common/services/in_app_purchase/in_app_purchase_service_impl.dart`

```dart
import 'package:base_app/common/services/in_app_purchase/in_app_purchase_service.dart';
import 'package:base_app/common/services/in_app_purchase/purchase_ids.dart';
import 'package:in_app_purchase/in_app_purchase.dart';

class InAppPurchaseServiceImpl implements InAppPurchaseService {
  InAppPurchaseServiceImpl({InAppPurchase? iap})
      : _iap = iap ?? InAppPurchase.instance;

  final InAppPurchase _iap;

  @override
  Stream<List<PurchaseDetails>> get purchaseStream => _iap.purchaseStream;

  @override
  Future<List<ProductDetails>> loadProducts() async {
    if (!await _iap.isAvailable()) throw const StoreUnavailableException();

    final response = await _iap.queryProductDetails(PurchaseIds.all);
    final error = response.error;
    if (error != null) throw ProductQueryException(error);
    if (response.productDetails.isEmpty) {
      throw ProductsNotFoundException(response.notFoundIDs);
    }
    return _onePerProductId(response.productDetails);
  }

  /// No Android, uma assinatura com várias ofertas (planos base, trial, promo)
  /// chega como N `ProductDetails` com o mesmo `id`, cada um com seu `offerToken`.
  /// A Play já devolve só as ofertas para as quais a usuária é elegível, então a
  /// primeira costuma ser a melhor. Remova este filtro se o paywall exibir cada
  /// oferta separadamente (ver seção 6).
  List<ProductDetails> _onePerProductId(List<ProductDetails> products) {
    final seen = <String>{};
    return [
      for (final product in products)
        if (seen.add(product.id)) product,
    ];
  }

  @override
  Future<void> buy(ProductDetails product) async {
    final param = PurchaseParam(productDetails: product);
    // Assinatura também usa buyNonConsumable — é assim que o plugin funciona.
    // No Android o offerToken é lido do próprio GooglePlayProductDetails.
    final started = PurchaseIds.isConsumable(product.id)
        ? await _iap.buyConsumable(purchaseParam: param)
        : await _iap.buyNonConsumable(purchaseParam: param);
    if (!started) throw const PurchaseNotStartedException();
  }

  @override
  Future<void> restorePurchases() => _iap.restorePurchases();

  @override
  Future<void> completePurchase(PurchaseDetails purchase) =>
      _iap.completePurchase(purchase);
}
```

Notas:

- `buyConsumable` tem `autoConsume: true` por padrão: no Android o plugin consome a compra sozinho depois de
  entregá-la pelo stream. O que a usuária ganhou (créditos) é responsabilidade do `EntitlementService`.
- O Service não verifica nada nem toca em `StorageService`. Verificação e concessão são do `EntitlementService`.

---

## 4. EntitlementService — contrato

`lib/common/services/in_app_purchase/entitlement_service.dart`

```dart
import 'package:in_app_purchase/in_app_purchase.dart';

/// Resposta do app para uma compra entregue pela loja. NÃO confunda com o
/// `VerificationResult` do verify_local_purchase — aquele é o que a loja disse;
/// este é o que o Cubit deve fazer com a transação.
enum GrantResult {
  /// Compra legítima e ativa: conceda o acesso e complete a transação.
  valid,

  /// A fonte de verdade disse que a compra não vale (reembolsada, expirada,
  /// inexistente, de outro produto). Não conceda; complete a transação para a
  /// loja parar de reentregá-la.
  invalid,

  /// Não deu para consultar a fonte de verdade (sem rede, timeout, 5xx,
  /// credencial errada) ou o pagamento ainda não liquidou. NÃO complete: a loja
  /// reentrega a transação e a verificação roda de novo.
  unavailable,
}

/// Fonte de verdade sobre o que a usuária tem direito a acessar.
/// 🅰 LocalEntitlementService  (verify_local_purchase + StorageService)
/// 🅱 ServerEntitlementService (PurchaseRepository)
abstract class EntitlementService {
  /// Verifica a compra e, se válida, registra o direito de acesso.
  Future<GrantResult> verifyAndGrant(PurchaseDetails purchase);

  /// Último estado conhecido — rápido e funciona offline.
  Future<bool> hasAccess(String productId);

  /// Reconsulta a fonte de verdade. Chame na inicialização do app: cancelamento,
  /// expiração e reembolso não chegam ao dispositivo sozinhos.
  Future<void> refresh();
}
```

Por que três resultados e não `bool`: com `bool`, uma queda de rede durante a verificação vira "compra
inválida", a transação é completada e a usuária paga sem receber. Com `unavailable` a transação fica aberta,
a loja a reentrega na próxima abertura e a verificação roda de novo — sem cobrar duas vezes.

O nome é `GrantResult` de propósito: desde a 2.0.0 o `verify_local_purchase` exporta a classe
`VerificationResult`, e um enum com esse nome no app colide no import.

---

## 5. LocalEntitlementService (modo 🅰)

Três arquivos: a porta `PurchaseVerifier` (interface + impl sobre o pacote) e o service. A porta existe porque a
fachada `VerifyLocalPurchase` é 100% estática — sem ela o service não tem como receber um fake no teste.

### 5.1 PurchaseVerifier

`lib/common/services/in_app_purchase/purchase_verifier.dart`

```dart
import 'package:verify_local_purchase/verify_local_purchase.dart';

/// Porta para o verify_local_purchase. Todo método lança
/// `VerifyPurchaseException` em falha de rede/API/config.
abstract class PurchaseVerifier {
  /// Token que identifica a compra na loja — é o que `refresh()` re-verifica.
  /// Assinatura no iOS: `originalTransactionId` (estável entre renovações).
  String tokenOf(PurchaseDetails purchase, {required bool subscription});

  /// Consulta a loja da [platform] informada — não a do aparelho atual.
  Future<VerificationResult> verify(
    String token,
    StorePlatform platform, {
    required bool subscription,
  });
}
```

`lib/common/services/in_app_purchase/purchase_verifier_impl.dart`

```dart
import 'package:base_app/common/services/in_app_purchase/purchase_verifier.dart';
import 'package:verify_local_purchase/verify_local_purchase.dart';

class PurchaseVerifierImpl implements PurchaseVerifier {
  const PurchaseVerifierImpl();

  @override
  String tokenOf(PurchaseDetails purchase, {required bool subscription}) =>
      subscription
          ? getSubscriptionToken(purchase)
          : getOneTimePurchaseToken(purchase);

  @override
  Future<VerificationResult> verify(
    String token,
    StorePlatform platform, {
    required bool subscription,
  }) =>
      switch ((platform, subscription)) {
        (StorePlatform.apple, true) =>
          VerifyLocalPurchase.verifySubscriptionWithAppStore(token),
        (StorePlatform.apple, false) =>
          VerifyLocalPurchase.verifyPurchaseWithAppStore(token),
        (StorePlatform.google, true) =>
          VerifyLocalPurchase.verifySubscriptionWithGooglePlay(token),
        (StorePlatform.google, false) =>
          VerifyLocalPurchase.verifyPurchaseWithGooglePlay(token),
      };
}
```

Os métodos `...WithAppStore`/`...WithGooglePlay` são usados em vez de `verifySubscription()`/`verifyPurchase()`
porque os genéricos escolhem a loja por `Platform.isIOS` — o `refresh()` precisa verificar pela plataforma
gravada no registro, não pela do aparelho.

### 5.2 LocalEntitlementService

`lib/common/services/in_app_purchase/local_entitlement_service.dart`

```dart
import 'dart:convert';

import 'package:base_app/common/services/in_app_purchase/entitlement_service.dart';
import 'package:base_app/common/services/in_app_purchase/purchase_ids.dart';
import 'package:base_app/common/services/in_app_purchase/purchase_verifier.dart';
import 'package:base_app/common/services/in_app_purchase/purchase_verifier_impl.dart';
import 'package:base_app/common/services/storage_service.dart';
import 'package:flutter/foundation.dart';
import 'package:verify_local_purchase/verify_local_purchase.dart';

class LocalEntitlementService implements EntitlementService {
  LocalEntitlementService(
    this._storage, {
    PurchaseVerifier verifier = const PurchaseVerifierImpl(),
    DateTime Function()? now,
  })  : _verifier = verifier,
        _now = now ?? DateTime.now;

  final StorageService _storage;
  final PurchaseVerifier _verifier;
  final DateTime Function() _now;

  /// Registro do aparelho: `entitlement_<productId>` → JSON
  /// {"token", "source", "isValid", "expiresAt", "checkedAt", "sandbox"}.
  static String entitlementKey(String productId) => 'entitlement_$productId';

  /// IDs de transação de consumíveis já creditados (idempotência).
  static const consumedKey = 'purchase_consumed_ids';

  /// Quanto o acesso sobrevive offline além do último ponto confirmado
  /// (o maior entre `expiresAt` e `checkedAt`) enquanto `refresh()` não
  /// consegue falar com a loja.
  static const offlineTolerance = Duration(days: 3);

  @override
  Future<GrantResult> verifyAndGrant(PurchaseDetails purchase) async {
    final productId = purchase.productID;
    final subscription = PurchaseIds.isSubscription(productId);
    final source = purchase.verificationData.source; // "app_store" | "google_play"

    final String token;
    final VerificationResult result;
    try {
      token = _verifier.tokenOf(purchase, subscription: subscription);
      result = await _verifier.verify(
        token,
        _platformOf(source),
        subscription: subscription,
      );
    } on VerifyPurchaseException catch (e) {
      _reportIfMisconfigured(e);
      return GrantResult.unavailable; // a loja reentrega e tentamos de novo
    }

    final grant = grantResultOf(result, productId);
    if (grant != GrantResult.valid) return grant;

    if (PurchaseIds.isConsumable(productId)) {
      final firstTime = await _markConsumed(purchase.purchaseID ?? token);
      if (firstTime) {
        // TODO(app): aplique aqui o efeito do consumível (ex.: CreditsService.add(100)).
      }
      return GrantResult.valid;
    }

    // Upgrade/downgrade de assinatura: a loja responde com o plano vigente.
    await _saveRecord(result.productId ?? productId, {
      'token': token,
      'source': source,
      ..._statusOf(result),
    });
    return GrantResult.valid;
  }

  /// Traduz o que a loja disse no que o Cubit deve fazer com a transação.
  /// Público e estático para ser testado isoladamente.
  static GrantResult grantResultOf(VerificationResult result, String productId) {
    // Token de outro produto (ex.: consumível barato apresentado como premium).
    // Assinatura aceita qualquer plano do app — após upgrade a loja devolve o
    // plano novo para a transação antiga.
    final storeProduct = result.productId;
    if (storeProduct != null) {
      final matches = PurchaseIds.isSubscription(productId)
          ? PurchaseIds.isSubscription(storeProduct)
          : storeProduct == productId;
      if (!matches) return GrantResult.invalid;
    }
    if (result.isValid) return GrantResult.valid;
    return switch (result.state) {
      // Pagamento não liquidado / estado novo da loja: não descarte a compra.
      VerificationState.pending || VerificationState.unknown => GrantResult.unavailable,
      // notFound, revoked, expired, billingRetry, onHold, paused, canceled vencido.
      _ => GrantResult.invalid,
    };
  }

  @override
  Future<bool> hasAccess(String productId) async {
    final record = await _readRecord(productId);
    if (record == null || record['isValid'] != true) return false;
    final expiresAt = DateTime.tryParse(record['expiresAt'] as String? ?? '');
    if (expiresAt == null) return true; // não-consumível: vale até reembolso
    final checkedAt =
        DateTime.tryParse(record['checkedAt'] as String? ?? '') ?? expiresAt;
    // Grace period: `expiresAt` já passou, mas a loja confirmou há pouco.
    final confirmedUntil = expiresAt.isAfter(checkedAt) ? expiresAt : checkedAt;
    return _now().isBefore(confirmedUntil.add(offlineTolerance));
  }

  @override
  Future<void> refresh() async {
    // Não-consumíveis também: é assim que um reembolso chega ao app.
    for (final productId in {...PurchaseIds.nonConsumables, ...PurchaseIds.subscriptions}) {
      final record = await _readRecord(productId);
      if (record == null) continue;

      final VerificationResult result;
      try {
        result = await _verifier.verify(
          record['token'] as String,
          _platformOf(record['source'] as String),
          subscription: PurchaseIds.isSubscription(productId),
        );
      } on VerifyPurchaseException catch (e) {
        _reportIfMisconfigured(e);
        continue; // sem rede: vale o último estado conhecido + tolerância
      }

      switch (result.state) {
        // Token morto: não há o que re-verificar depois.
        case VerificationState.revoked || VerificationState.notFound:
          await _storage.remove(entitlementKey(productId));
        // Estado novo da loja: não mexa no que já se sabe.
        case VerificationState.unknown:
          break;
        // Expirada, em billing retry, pausada... MANTENHA o token: se o
        // pagamento se recuperar ou a usuária reassinar (Apple mantém o
        // originalTransactionId), o próximo refresh() devolve o acesso.
        default:
          await _saveRecord(productId, {...record, ..._statusOf(result)});
      }
    }
  }

  Map<String, dynamic> _statusOf(VerificationResult result) => {
        'isValid': result.isValid,
        'expiresAt': result.expiresAt?.toIso8601String(),
        'checkedAt': _now().toIso8601String(),
        'sandbox': result.isSandbox,
      };

  static StorePlatform _platformOf(String source) =>
      source == 'app_store' ? StorePlatform.apple : StorePlatform.google;

  /// Configuração errada não se resolve sozinha. Nunca vira `invalid` (a
  /// usuária pagou), mas precisa aparecer — senão todo o faturamento some
  /// em silêncio como "verificação indisponível".
  void _reportIfMisconfigured(VerifyPurchaseException e) {
    const configErrors = {
      VerifyPurchaseErrorCode.notInitialized,
      VerifyPurchaseErrorCode.missingConfig,
      VerifyPurchaseErrorCode.invalidCredentials,
      VerifyPurchaseErrorCode.unauthorized,
    };
    if (configErrors.contains(e.code)) {
      // TODO(app): envie também ao crash reporter (Crashlytics/Sentry).
      debugPrint('IAP: verificação mal configurada — $e');
    }
  }

  Future<Map<String, dynamic>?> _readRecord(String productId) async {
    final raw = await _storage.getString(entitlementKey(productId));
    return raw == null ? null : jsonDecode(raw) as Map<String, dynamic>;
  }

  Future<void> _saveRecord(String productId, Map<String, dynamic> record) =>
      _storage.setString(entitlementKey(productId), jsonEncode(record));

  Future<bool> _markConsumed(String transactionId) async {
    final raw = await _storage.getString(consumedKey);
    final ids = raw == null
        ? <String>{}
        : (jsonDecode(raw) as List<dynamic>).cast<String>().toSet();
    if (!ids.add(transactionId)) return false;
    await _storage.setString(consumedKey, jsonEncode(ids.toList()));
    return true;
  }
}
```

### 5.3 Como o `VerificationResult` do pacote vira `GrantResult`

| `VerificationResult` (v2) | Na compra (`verifyAndGrant`) | No `refresh()` |
|---|---|---|
| `isValid: true` (`purchased`, `active`, `canceled` não vencido, `gracePeriod`) | `valid` | atualiza status e `expiresAt` |
| `pending` | `unavailable` — a loja reentrega quando liquidar | atualiza status (sem acesso) |
| `unknown` | `unavailable` — estado novo da loja; não descarte | não mexe |
| `notFound`, `revoked` | `invalid` | remove o registro |
| `expired`, `billingRetry`, `onHold`, `paused` | `invalid` | atualiza status (sem acesso), **mantém o token** |
| `productId` de outro produto | `invalid` | — |
| `VerifyPurchaseException` (qualquer `code`) | `unavailable`; códigos de config são reportados | mantém o último estado |

Pontos que importam neste arquivo:

- **`initialize` roda uma vez, no `main()`** (ver `setup.md` §4) — não por transação. Na 1.x o service
  re-inicializava o pacote a cada compra para trocar `useSandbox`; na 2.0.0 o default
  `AppleEnvironment.productionWithSandboxFallback` tenta produção e, se a Apple responder "transação não
  encontrada", repete no sandbox. TestFlight e App Review funcionam sem nenhuma lógica no app.
- **`VerificationResult.isValid` já é a regra de acesso** do pacote: assinatura Apple em status 1/4, Google em
  `ACTIVE`/`CANCELED`/`IN_GRACE_PERIOD` com `expiryTime` futuro; compra única não reembolsada. Não reimplemente
  a regra olhando `state` — use `state` só para decidir *o que fazer* quando `isValid` é `false`.
- **Token desconhecido não é exceção**: vem como `state: notFound`. Exceção é só rede/API/config — é isso que
  separa `invalid` de `unavailable` sem heurística.
- **`getOneTimePurchaseToken` / `getSubscriptionToken`** lançam `VerifyPurchaseException(invalidToken)` quando
  não conseguem extrair o token (ex.: StoreKit 1 sem JSON). O `try` acima trata como `unavailable`.
- **Não confie em `result.raw`** para decidir acesso: é o payload cru da loja, útil só para log/depuração.
- **Ambiente Xcode** (arquivo `.storekit` de teste local) não é verificável pela App Store Server API — a Apple
  responde "não encontrado" e a compra vira `invalid`. Para testar o modo 🅰 use uma conta Sandbox Tester.
- **Assinatura com upgrade/downgrade**: o registro é gravado sob o `productId` que a loja devolveu. Para "é
  premium?", pergunte por qualquer ID de `PurchaseIds.subscriptions`
  (`Future.wait(PurchaseIds.subscriptions.map(hasAccess))`), não por um plano específico.

---

## 6. Ofertas de assinatura no Android

Desde a Billing Library 5, uma assinatura tem planos base e ofertas. O plugin expande cada oferta em um
`GooglePlayProductDetails` separado (mesmo `id`, `offerToken` diferente), e `buyNonConsumable` usa o
`offerToken` do `ProductDetails` que você passar. Duas escolhas possíveis:

- **Um botão por produto** (padrão do template): mantenha `_onePerProductId`. A Play só devolve ofertas para
  as quais a usuária é elegível, então a primeira já é a melhor (trial ou promo, quando houver).
- **Um botão por oferta**: remova o filtro e, no paywall, leia `(product as GooglePlayProductDetails)
  .productDetails.subscriptionOfferDetails` para exibir período e preço de cada oferta. No iOS cada produto
  chega uma vez só, então trate os dois casos.

Sem decidir isso, o paywall Android mostra o mesmo plano repetido — o sintoma mais comum de quem ignora o
detalhe.

---

## 7. Apps com login: registro do aparelho, espelho remoto e grant manual

Vale quando o app tem usuário autenticado e quer (a) enxergar o status premium por usuário em um documento
remoto e/ou (b) conceder premium manualmente sem compra. A regra está em `SKILL.md` ("Apps com login"); aqui
fica o esqueleto de como o `LocalEntitlementService` da seção 5 muda — o resto (`PurchaseVerifier`, Cubit,
View, verificação na compra) não muda.

```dart
/// Plataformas do campo `plataforma` no documento remoto.
class EntitlementPlatform {
  static const appStore = 'app_store';   // valor cru de verificationData.source
  static const googlePlay = 'google_play';
  static const manual = 'manual';        // grant do admin, direto no console
}

class LocalEntitlementService implements EntitlementService {
  // ...campos da seção 5, mais:
  final RemoteEntitlementDataSource _remote; // lê/grava users/{uid} com merge
  final String? Function() _currentUid;

  /// Último status resolvido (cache de sessão) — é o que `hasAccess` lê
  /// quando há grant manual.
  static const statusKey = 'entitlement_status';

  @override
  Future<GrantResult> verifyAndGrant(PurchaseDetails purchase) async {
    // ...verificação idêntica à seção 5; se `valid`, depois do _saveRecord:
    await _mirrorRemote(
      isPlus: true,
      platform: purchase.verificationData.source,
      expiresAt: result.expiresAt,
    );
    return GrantResult.valid;
  }

  @override
  Future<void> refresh() async {
    final uid = _currentUid();
    if (uid == null) return;

    // 1. Grant manual: decidido pela regra local de validade (isPlus && !expirado)
    //    e NUNCA sobrescrito pelo app.
    final remote = await _readRemoteOrNull(uid);
    if (remote?['plataforma'] == EntitlementPlatform.manual) {
      await _storage.setString(statusKey, jsonEncode(remote));
      return;
    }

    // 2. Só o registro DESTE aparelho entra na re-verificação. O token que
    //    estiver em users/{uid} não concede acesso aqui.
    for (final productId in PurchaseIds.subscriptions) {
      final record = await _readRecord(productId)
          ?? await _migrateLegacyCache(productId); // ver nota abaixo
      if (record == null) {
        await _storage.setString(statusKey, jsonEncode({'isPlus': false}));
        continue; // remoto intocado: não há evidência para escrever
      }
      final VerificationResult result;
      try {
        result = await _verifier.verify(
          record['token'] as String,
          _platformOf(record['source'] as String), // plataforma do REGISTRO
          subscription: true,
        );
      } on VerifyPurchaseException {
        return; // sem rede: mantém o último status conhecido
      }
      // Mesma tabela da seção 5.3 para remover/atualizar o registro, e então:
      await _storage.setString(statusKey, jsonEncode({'isPlus': result.isValid}));
      await _mirrorRemote(
        isPlus: result.isValid,
        platform: record['source'] as String,
        expiresAt: result.expiresAt,
      );
    }
  }

  /// Espelho para o admin enxergar o status. Saída, nunca entrada.
  Future<void> _mirrorRemote({
    required bool isPlus,
    required String platform,
    DateTime? expiresAt,
  }) async {
    final uid = _currentUid();
    if (uid == null) return;
    await _remote.merge(uid, {
      'isPlus': isPlus,
      'plataforma': platform,
      'expiresAt': expiresAt?.toIso8601String(),
    });
  }
}
```

Pontos que importam:

- **A plataforma vem do registro, não do aparelho**: por isso `PurchaseVerifier.verify` recebe `StorePlatform`
  e usa `...WithAppStore`/`...WithGooglePlay` — o registro pode ter sido migrado de um cache gravado em outra
  plataforma.
- **O espelho nunca leva o token**: `users/{uid}` recebe `isPlus`, `plataforma` e `expiresAt` (vindo do
  `VerificationResult`, útil para o admin). Sem token no remoto, não há o que copiar por engano.
- **Limpeza de sessão**: o helper de logout/exclusão de conta remove `statusKey` (é da sessão) e **não** remove
  `entitlement_<productId>` (é do aparelho). Confira que nada chama `StorageService.clear()`.
- **`_migrateLegacyCache`**: só existe se uma versão anterior espelhava o remoto no cache local. Lê o cache
  antigo, promove o token a `entitlement_<productId>` uma única vez (com `source`, `isValid: false` e sem
  `checkedAt` — o `refresh()` corrente preenche) e devolve o registro; sem token, `null`. Remova o helper
  quando a base instalada tiver migrado.
- **Testes do `refresh()`** que provam a regra (fakes de storage, remoto e `PurchaseVerifier`): grant manual →
  sem escrita remota; remoto com token mas aparelho sem registro → sem acesso, remoto intocado, `verify` nunca
  chamado; registro ativo → acesso + espelho; registro `expired` → sem acesso, token mantido, espelho
  `isPlus: false`; registro `revoked` → chave removida; verificador lança → último status mantido; cache antigo
  com token → migração única.
