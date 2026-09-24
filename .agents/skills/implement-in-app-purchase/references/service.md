# Service — PurchaseIds, InAppPurchaseService e EntitlementService

Índice: 1. PurchaseIds · 2. InAppPurchaseService (interface) · 3. InAppPurchaseServiceImpl ·
4. EntitlementService (contrato) · 5. LocalEntitlementService (modo 🅰) · 6. Ofertas de assinatura no Android ·
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

enum VerificationResult {
  /// Compra legítima e ativa: conceda o acesso e complete a transação.
  valid,

  /// A fonte de verdade disse que a compra não vale (reembolsada, expirada,
  /// inexistente). Não conceda; complete a transação para a loja parar de
  /// reentregá-la.
  invalid,

  /// Não deu para consultar a fonte de verdade (sem rede, timeout, 5xx).
  /// NÃO complete: a loja reentrega a transação e a verificação roda de novo.
  unavailable,
}

/// Fonte de verdade sobre o que a usuária tem direito a acessar.
/// 🅰 LocalEntitlementService  (verify_local_purchase + StorageService)
/// 🅱 ServerEntitlementService (PurchaseRepository)
abstract class EntitlementService {
  /// Verifica a compra e, se válida, registra o direito de acesso.
  Future<VerificationResult> verifyAndGrant(PurchaseDetails purchase);

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

---

## 5. LocalEntitlementService (modo 🅰)

`lib/common/services/in_app_purchase/local_entitlement_service.dart`

```dart
import 'dart:convert';

import 'package:base_app/common/services/in_app_purchase/entitlement_service.dart';
import 'package:base_app/common/services/in_app_purchase/purchase_ids.dart';
import 'package:base_app/common/services/storage_service.dart';
import 'package:verify_local_purchase/verify_local_purchase.dart';

/// Credenciais das APIs de verificação. Vêm de `--dart-define` (ver setup.md),
/// nunca de literais no código.
class LocalVerificationCredentials {
  const LocalVerificationCredentials({
    required this.appleBundleId,
    required this.appleIssuerId,
    required this.appleKeyId,
    required this.applePrivateKey,
    required this.androidPackageName,
    required this.googleServiceAccountJson,
  });

  final String appleBundleId;
  final String appleIssuerId;
  final String appleKeyId;
  final String applePrivateKey;
  final String androidPackageName;
  final String googleServiceAccountJson;

  bool get hasApple =>
      appleIssuerId.isNotEmpty && appleKeyId.isNotEmpty && applePrivateKey.isNotEmpty;
  bool get hasGoogle => googleServiceAccountJson.isNotEmpty;
}

class LocalEntitlementService implements EntitlementService {
  LocalEntitlementService(
    this._storage,
    this._credentials, {
    VerifyLocalPurchase? verifier,
  }) : _verifier = verifier ?? VerifyLocalPurchase();

  final StorageService _storage;
  final LocalVerificationCredentials _credentials;
  final VerifyLocalPurchase _verifier;

  /// `entitlement_<productId>` → JSON {"token", "source", "sandbox"}.
  static String entitlementKey(String productId) => 'entitlement_$productId';

  /// IDs de transação de consumíveis já creditados (idempotência).
  static const consumedKey = 'purchase_consumed_ids';

  @override
  Future<VerificationResult> verifyAndGrant(PurchaseDetails purchase) async {
    final productId = purchase.productID;
    final isSubscription = PurchaseIds.isSubscription(productId);

    final String token;
    try {
      token = isSubscription
          ? getSubscriptionToken(purchase)
          : getOneTimePurchaseToken(purchase);
    } catch (_) {
      return VerificationResult.unavailable; // formato inesperado: não descarte a compra
    }
    if (token.isEmpty) return VerificationResult.unavailable;

    final sandbox = _isSandboxTransaction(purchase);
    _configureVerifier(useSandbox: sandbox);

    final bool isValid;
    try {
      isValid = isSubscription
          ? await _verifier.verifySubscription(token)
          : await _verifier.verifyPurchase(token);
    } catch (_) {
      return VerificationResult.unavailable; // rede/API: a loja reentrega, tentamos de novo
    }
    if (!isValid) return VerificationResult.invalid;

    if (PurchaseIds.isConsumable(productId)) {
      final firstTime = await _markConsumed(purchase.purchaseID ?? token);
      if (firstTime) {
        // TODO(app): aplique aqui o efeito do consumível (ex.: CreditsService.add(100)).
      }
      return VerificationResult.valid;
    }

    await _storage.setString(
      entitlementKey(productId),
      jsonEncode({
        'token': token,
        'source': purchase.verificationData.source, // "app_store" | "google_play"
        'sandbox': sandbox,
      }),
    );
    return VerificationResult.valid;
  }

  @override
  Future<bool> hasAccess(String productId) async =>
      await _storage.getString(entitlementKey(productId)) != null;

  @override
  Future<void> refresh() async {
    for (final productId in PurchaseIds.subscriptions) {
      final raw = await _storage.getString(entitlementKey(productId));
      if (raw == null) continue;
      final data = jsonDecode(raw) as Map<String, dynamic>;
      _configureVerifier(useSandbox: data['sandbox'] == true);
      try {
        final active = await _verifier.verifySubscription(data['token'] as String);
        if (!active) await _storage.remove(entitlementKey(productId));
      } catch (_) {
        // Sem rede: mantenha o último estado conhecido em vez de bloquear a usuária.
      }
    }
  }

  /// TestFlight e a revisão da App Store geram transações de SANDBOX mesmo em
  /// build de produção. O verificador tem um único flag global, então ele é
  /// ajustado por transação lendo o `environment` que o StoreKit 2 entrega
  /// ("Production", "Sandbox" ou "Xcode"). No Android não há distinção.
  bool _isSandboxTransaction(PurchaseDetails purchase) {
    if (purchase.verificationData.source != 'app_store') return false;
    try {
      final json = jsonDecode(purchase.verificationData.localVerificationData)
          as Map<String, dynamic>;
      return json['environment'] != 'Production';
    } catch (_) {
      return false; // StoreKit 1 entrega recibo base64, não JSON: assuma produção
    }
  }

  /// `initialize` só guarda a config em memória — é barato chamar por transação.
  void _configureVerifier({required bool useSandbox}) {
    VerifyLocalPurchase.initialize(
      appleConfig: _credentials.hasApple
          ? AppleConfig(
              bundleId: _credentials.appleBundleId,
              issuerId: _credentials.appleIssuerId,
              keyId: _credentials.appleKeyId,
              privateKey: _credentials.applePrivateKey,
              useSandbox: useSandbox,
            )
          : null,
      googlePlayConfig: _credentials.hasGoogle
          ? GooglePlayConfig(
              packageName: _credentials.androidPackageName,
              serviceAccountJson: _credentials.googleServiceAccountJson,
            )
          : null,
    );
  }

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

Pontos que importam neste arquivo:

- **`VerifyLocalPurchase.initialize` recebe parâmetros nomeados** (`appleConfig:`, `googlePlayConfig:`), não um
  `VerifyPurchaseConfig` posicional — o docstring do pacote está desatualizado; o código acima segue a
  assinatura real da versão 1.1.0.
- **`getOneTimePurchaseToken` / `getSubscriptionToken`** vêm do próprio pacote e já escolhem o token certo
  por plataforma (iOS: `purchaseID` ou `originalTransactionId`; Android: `serverVerificationData`).
- **O verificador lança exceção em erro de rede/API e devolve `false` só quando a compra é realmente inválida**
  — é isso que permite separar `unavailable` de `invalid`.
- **Ambiente Xcode** (arquivo `.storekit` de teste local) não é verificável pela App Store Server API: para
  testar o modo 🅰 use uma conta Sandbox Tester, não o StoreKit Configuration File.

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
fica o esqueleto de como o `LocalEntitlementService` da seção 5 muda — o resto (Cubit, View, verificação na
compra) não muda.

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

  /// Registro do aparelho: escrito SOMENTE aqui. Nunca por um espelho do remoto.
  static String entitlementKey(String productId) => 'entitlement_$productId';

  /// Último status resolvido (cache de sessão) — é o que `hasAccess` lê.
  static const statusKey = 'entitlement_status';

  @override
  Future<VerificationResult> verifyAndGrant(PurchaseDetails purchase) async {
    // ...verificação idêntica à seção 5; se `valid`:
    await _storage.setString(entitlementKey(productId), jsonEncode({...}));
    await _mirrorRemote(isPlus: true, platform: purchase.verificationData.source);
    return VerificationResult.valid;
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
      final raw = await _storage.getString(entitlementKey(productId))
          ?? await _migrateLegacyCache(productId); // ver nota abaixo
      if (raw == null) {
        await _storage.setString(statusKey, jsonEncode({'isPlus': false}));
        continue; // remoto intocado: não há evidência para escrever
      }
      final data = jsonDecode(raw) as Map<String, dynamic>;
      final bool active;
      try {
        active = data['source'] == EntitlementPlatform.appStore
            ? await _verifier.verifySubscriptionWithAppStore(data['token'] as String)
            : await _verifier.verifySubscriptionWithGooglePlay(data['token'] as String);
      } catch (_) {
        return; // sem rede: mantém o último status conhecido
      }
      if (!active) await _storage.remove(entitlementKey(productId));
      await _storage.setString(statusKey, jsonEncode({'isPlus': active, ...data}));
      await _mirrorRemote(isPlus: active, platform: data['source'] as String);
    }
  }

  /// Espelho para o admin enxergar o status. Saída, nunca entrada.
  Future<void> _mirrorRemote({required bool isPlus, required String platform}) async {
    final uid = _currentUid();
    if (uid == null) return;
    await _remote.merge(uid, {'isPlus': isPlus, 'plataforma': platform});
  }
}
```

Pontos que importam:

- **Use `verifySubscriptionWithAppStore`/`WithGooglePlay` pela plataforma do registro**, não o
  `verifySubscription()` genérico do pacote, que decide por `Platform.isIOS` — o registro pode ter sido
  migrado de um cache gravado em outra plataforma.
- **Limpeza de sessão**: o helper de logout/exclusão de conta remove `statusKey` (é da sessão) e **não** remove
  `entitlement_<productId>` (é do aparelho). Confira que nada chama `StorageService.clear()`.
- **`_migrateLegacyCache`**: só existe se uma versão anterior espelhava o remoto no cache local. Lê o cache
  antigo, promove o token a `entitlement_<productId>` uma única vez e devolve o registro; sem token, `null`.
  Remova o helper quando a base instalada tiver migrado.
- **Testes do `refresh()`** que provam a regra (fakes de storage e remoto): grant manual → sem escrita remota;
  remoto com token mas aparelho sem registro → sem acesso, remoto intocado, `verify*` nunca chamado; registro
  ativo → acesso + espelho; registro inativo → chave removida + espelho `isPlus: false`; verificador lança →
  último status mantido; cache antigo com token → migração única.
