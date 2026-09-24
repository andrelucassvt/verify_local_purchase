# Modo 🅱 — Verificação no back-end

Índice: 1. Contrato dos endpoints · 2. PurchaseRepository · 3. PurchaseRemoteDataSource · 4. PurchaseRepositoryImpl ·
5. ServerEntitlementService · 6. DI · 7. O que o servidor precisa fazer

Neste modo o app NÃO usa `verify_local_purchase` nem salva recibo no `StorageService`. A verificação e o
registro compra ↔ usuária são do servidor; o app só transporta os dados e pergunta o status.

---

## 1. Contrato dos endpoints

Alinhe com o time de back-end antes de codar. O template assume:

`POST /purchases/verify`

```json
{
  "product_id": "premium_monthly",
  "verification_data": "<purchase.verificationData.serverVerificationData>",
  "local_verification_data": "<purchase.verificationData.localVerificationData>",
  "source": "app_store | google_play"
}
```

Resposta `200`:

```json
{ "valid": true }
```

`valid: false` significa "a loja disse que não vale" (reembolsada, expirada, token inexistente) → o app
completa a transação e não concede. Qualquer status fora de 2xx significa "não deu para verificar" → o app
NÃO completa e a loja reentrega depois.

`GET /purchases/status` → `200`:

```json
{ "active_product_ids": ["premium_monthly"] }
```

O que `verification_data` contém: no iOS com StoreKit 2 é o JWS assinado pela Apple (`jwsRepresentation`); no
Android é o `purchaseToken`. `local_verification_data` é o JSON da transação (StoreKit 2) ou o JSON da compra
(Android) — útil para o servidor logar sem chamar a loja.

---

## 2. PurchaseRepository

`lib/domain/interfaces/purchase_repository.dart`

```dart
import 'package:base_app/config/error/result_pattern.dart';

abstract class PurchaseRepository {
  /// POST /purchases/verify — o servidor valida com a loja e registra o vínculo
  /// compra ↔ usuária. `true` = válida e ativa; `false` = inválida/reembolsada.
  Future<Result<bool>> verifyPurchase({
    required String productId,
    required String serverVerificationData,
    required String localVerificationData,
    required String source,
  });

  /// GET /purchases/status — IDs dos produtos a que a usuária tem acesso agora.
  Future<Result<List<String>>> getActiveProductIds();
}
```

---

## 3. PurchaseRemoteDataSource

`lib/data/datasources/purchase_remote_datasource.dart`

```dart
import 'package:base_app/config/network/http_service.dart';

class PurchaseRemoteDataSource {
  const PurchaseRemoteDataSource(this._httpService);

  final HttpService _httpService;

  Future<HttpResponse> verify(Map<String, dynamic> body) =>
      _httpService.post('/purchases/verify', data: body);

  Future<HttpResponse> status() => _httpService.get('/purchases/status');
}
```

---

## 4. PurchaseRepositoryImpl

`lib/data/repositories/purchase_repository_impl.dart`

```dart
import 'package:base_app/config/error/app_exception.dart';
import 'package:base_app/config/error/repository_error_mapper.dart'; // ajuste ao caminho do projeto
import 'package:base_app/config/error/result_pattern.dart';
import 'package:base_app/data/datasources/purchase_remote_datasource.dart';
import 'package:base_app/domain/interfaces/purchase_repository.dart';

class PurchaseRepositoryImpl with RepositoryErrorMapper implements PurchaseRepository {
  const PurchaseRepositoryImpl(this._remoteDataSource);

  final PurchaseRemoteDataSource _remoteDataSource;

  @override
  Future<Result<bool>> verifyPurchase({
    required String productId,
    required String serverVerificationData,
    required String localVerificationData,
    required String source,
  }) async {
    try {
      final response = await _remoteDataSource.verify({
        'product_id': productId,
        'verification_data': serverVerificationData,
        'local_verification_data': localVerificationData,
        'source': source,
      });
      ensureSuccess(response); // fora de 2xx vira AppException antes do parsing
      final data = response.data as Map<String, dynamic>;
      final valid = data['valid'];
      if (valid is! bool) {
        throw const ResponseParsingException('Campo "valid" ausente em /purchases/verify');
      }
      return Result.ok(valid);
    } catch (error, stackTrace) {
      return Result.error(toAppException(error, stackTrace));
    }
  }

  @override
  Future<Result<List<String>>> getActiveProductIds() async {
    try {
      final response = await _remoteDataSource.status();
      ensureSuccess(response);
      final data = response.data as Map<String, dynamic>;
      final ids = data['active_product_ids'];
      if (ids is! List) {
        throw const ResponseParsingException(
          'Campo "active_product_ids" ausente em /purchases/status',
        );
      }
      return Result.ok(ids.cast<String>());
    } catch (error, stackTrace) {
      return Result.error(toAppException(error, stackTrace));
    }
  }
}
```

---

## 5. ServerEntitlementService

`lib/common/services/in_app_purchase/server_entitlement_service.dart`

```dart
import 'package:base_app/common/services/in_app_purchase/entitlement_service.dart';
import 'package:base_app/domain/interfaces/purchase_repository.dart';
import 'package:in_app_purchase/in_app_purchase.dart';

/// Adaptador fino sobre o PurchaseRepository — existe para o PaywallCubit não
/// mudar entre os modos. Não usa StorageService nem verify_local_purchase: a
/// verificação inteira é do servidor.
class ServerEntitlementService implements EntitlementService {
  ServerEntitlementService(this._repository);

  final PurchaseRepository _repository;

  /// Cache em memória da última resposta do servidor.
  Set<String> _activeProductIds = const {};

  @override
  Future<GrantResult> verifyAndGrant(PurchaseDetails purchase) async {
    final result = await _repository.verifyPurchase(
      productId: purchase.productID,
      serverVerificationData: purchase.verificationData.serverVerificationData,
      localVerificationData: purchase.verificationData.localVerificationData,
      source: purchase.verificationData.source, // "app_store" | "google_play"
    );
    return result.when(
      ok: (isValid) {
        if (!isValid) return GrantResult.invalid;
        _activeProductIds = {..._activeProductIds, purchase.productID};
        return GrantResult.valid;
      },
      // Qualquer falha de rede/servidor é `unavailable`: nunca complete uma
      // transação que o servidor não confirmou nem negou.
      error: (_) => GrantResult.unavailable,
    );
  }

  @override
  Future<bool> hasAccess(String productId) async {
    if (_activeProductIds.isEmpty) await refresh();
    return _activeProductIds.contains(productId);
  }

  @override
  Future<void> refresh() async {
    final result = await _repository.getActiveProductIds();
    result.when(
      ok: (ids) {
        _activeProductIds = ids.toSet();
      },
      error: (_) {
        // Sem rede: mantenha o último estado conhecido.
      },
    );
  }
}
```

Se o app tiver login, o back-end identifica a usuária pelo Bearer token que o `AuthInterceptor` já injeta
(skill `implement-auth-token-flow`). Sem login, envie `applicationUserName`/`appAccountToken` no
`PurchaseParam` e no payload para o servidor conseguir vincular a compra a um identificador estável.

---

## 6. DI

Em `app_injector.dart`, respeitando a ordem services → network → datasources → repositories → cubits:

```dart
// 2. Services
inject.registerLazySingleton<InAppPurchaseService>(InAppPurchaseServiceImpl.new);

// 4. DataSources
inject.registerLazySingleton<PurchaseRemoteDataSource>(
  () => PurchaseRemoteDataSource(inject()),
);

// 5. Repositories
inject.registerLazySingleton<PurchaseRepository>(
  () => PurchaseRepositoryImpl(inject()),
);

// 5b. EntitlementService depende do Repository, então vem depois dele
inject.registerLazySingleton<EntitlementService>(
  () => ServerEntitlementService(inject()),
);

// 6. Cubits
inject.registerFactory<PaywallCubit>(() => PaywallCubit(inject(), inject()));
```

---

## 7. O que o servidor precisa fazer

Não é escopo desta skill implementar o back-end, mas o contrato só funciona se ele:

- **iOS**: validar a assinatura do JWS (`verification_data`) com os certificados da Apple e consultar a
  App Store Server API (`Get Transaction Info` / `Get All Subscription Statuses`) para status atual.
- **Android**: chamar a Google Play Developer API (`purchases.products.get` ou
  `purchases.subscriptionsv2.get`) com o `purchaseToken` e, para compras únicas, fazer o
  `acknowledge` se o app não fizer.
- **Persistir** compra ↔ usuária e recusar o mesmo token para duas contas.
- **Receber notificações** de cancelamento/reembolso (App Store Server Notifications V2 e Play Real-time
  Developer Notifications) para que `GET /purchases/status` reflita a realidade sem o app precisar perguntar à
  loja.
