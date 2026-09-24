---
generated_at: 2026-07-10
source_commit: 894d27a
source_state: dirty
verified_at: 2026-09-24
status: current
related_plans: []
---

# Flow: Verificação de Assinatura

> **Resumo:** Decide se o usuário tem direito a uma assinatura **agora** (ativa, cancelada mas não expirada, ou em grace period) consultando `getAllSubscriptionStatuses` (Apple, com fallback de sandbox) ou `subscriptionsv2` (Google), e devolve um `VerificationResult` com estado, expiração e auto-renovação.

## Visão Geral

O app chama `VerifyLocalPurchase.verifySubscription(token)` (ou `verifySubscriptionDetails(purchase)`, que extrai o token antes). A fachada estática delega à instância de `VerifyPurchaseService` criada no `initialize`, que escolhe a loja por `Platform.isIOS || Platform.isMacOS`.

O service só faz I/O: monta a chamada, trata fallback de ambiente e converte erros em `VerifyPurchaseException`. A decisão de validade mora em `StoreResponseParser` (funções puras), que transforma a resposta da loja em `VerificationResult`.

Diferente da compra única, o critério é o **estado atual + data de expiração**, não a ausência de reembolso. Token desconhecido não é erro: volta `state: notFound`.

```
verifySubscription(token)
   │  Apple (iOS/macOS)?
   ├── sim ─► verifySubscriptionWithAppStore ─► _callAppStore ─► getAllSubscriptionStatuses
   │                                                     └─► StoreResponseParser.appleSubscription
   └── não ─► verifySubscriptionWithGooglePlay ─► _googleGet(subscriptionsv2)
                                                     └─► StoreResponseParser.googleSubscription
```

## Passo a Passo

1. **Fachada** — `lib/verify_local_purchase.dart` → `VerifyLocalPurchase.verifySubscription` / `verifySubscriptionDetails`
   `_requireService` lança `VerifyPurchaseException(notInitialized)` se `initialize` não rodou. `verifySubscriptionDetails` usa `getSubscriptionToken` (ver [extracao-token.md](extracao-token.md)).
2. **Roteamento** — `lib/service/verify_purchase_service.dart` → `verifySubscription`
   `_isApplePlatform` (injetável via construtor) decide a loja.

### Caminho App Store

3. `verifySubscriptionWithAppStore` → `_requireToken` rejeita token vazio (`invalidToken`); loga com `mask()` se `enableLogging`.
4. `_callAppStore` → sem `appleConfig` lança `missingConfig`. Monta a lista de ambientes por `AppleConfig.environment`: `production` → [live], `sandbox` → [sandbox], `productionWithSandboxFallback` (default) → [live, sandbox].
5. Para cada ambiente, `_appStoreApi` reusa/cria o `AppStoreServerAPI` em cache (`_appStoreApis`) e chama `getAllSubscriptionStatuses(originalTransactionId)`.
   - `ApiException` com código `4040001/4040005/4040010` → tenta o próximo ambiente; se era o último, devolve `VerificationResult.notFound`.
   - Outro `ApiException` → `unauthorized` (401/403) ou `apiError`, com `storeErrorCode`.
6. `StoreResponseParser.appleSubscription` junta os `lastTransactions` de **todos** os grupos, filtra os de mesmo `originalTransactionId` (se nenhum bater, usa todos), ordena por status (1 > 4 > 3 > 2 > 5) e depois pela maior `expiresDate`, e mapeia o melhor.

### Caminho Google Play

3. `verifySubscriptionWithGooglePlay` → `_requireToken`; `_googleConfig` lança `missingConfig` sem config.
4. `_googleGet` → `_googleClient` devolve o client injetado ou cria (uma vez) um `AutoRefreshingAuthClient` via `clientViaServiceAccount`; JSON inválido vira `invalidCredentials`, falha de auth não fica em cache.
5. `GET /androidpublisher/v3/applications/{packageName}/purchases/subscriptionsv2/tokens/{token}`.
   - 404/410 → `null` → `VerificationResult.notFound`.
   - 401/403 → `unauthorized`; outro ≠ 200 → `apiError`; corpo não-JSON → `invalidResponse`; `ClientException`/`SocketException` → `networkError`.
6. `StoreResponseParser.googleSubscription(json, now: _now())` escolhe o `lineItem` com maior `expiryTime` e calcula `isValid`.

## Arquivos Envolvidos

| Camada | Arquivo | Responsabilidade |
|--------|---------|------------------|
| API pública | `lib/verify_local_purchase.dart` | `verifySubscription`, `verifySubscriptionDetails`, `*WithAppStore`, `*WithGooglePlay` |
| Service | `lib/service/verify_purchase_service.dart` | I/O, fallback de ambiente, cache de clients, mapeamento de erros |
| Regras | `lib/service/store_response_parser.dart` | `appleSubscription`, `googleSubscription` — decidem `isValid`/`state` |
| Models | `lib/models/verification_result.dart` | `VerificationResult`, `VerificationState` |
| Models | `lib/models/verify_purchase_exception.dart` | `VerifyPurchaseException`, `VerifyPurchaseErrorCode` |
| Config | `lib/models/verify_purchase_config.dart` | `AppleConfig.environment`, `GooglePlayConfig` |
| Testes | `test/store_response_parser_test.dart` | Tabela de status Apple/Google, match por grupo, expiração |
| Testes | `test/verify_purchase_service_test.dart` | Fallback de sandbox, 404/410, erros HTTP/rede |

## Regras de Negócio Relevantes

- **Apple válido = status 1 (Active) ou 4 (Billing Grace Period)** — `store_response_parser.dart`. Status 1 com `autoRenewStatus == 0` vira `state: canceled` mas continua válido.
- **Apple não válido**: 2 Expired, 3 Billing Retry, 5 Revoked.
- **Apple multi-grupo**: prioriza o `lastTransaction` com o mesmo `originalTransactionId`; sem match, o melhor status entre todas as assinaturas do cliente.
- **Google válido = `ACTIVE`, `CANCELED` ou `IN_GRACE_PERIOD` e `expiryTime` futuro** — `CANCELED` sem `expiryTime` é inválido; `ACTIVE` sem `expiryTime` confia no estado.
- **Google `PENDING` não é válido** (até a 1.x era).
- **Fallback de sandbox** (Apple, default) — `verify_purchase_service.dart`: compras do App Review/TestFlight vivem no sandbox.
- **`willAutoRenew`**: Apple via `renewalInfo.autoRenewStatus`; Google via `autoRenewingPlan.autoRenewEnabled` (`prepaidPlan` → `false`).
- **`isSandbox`**: Apple via `environment` da resposta; Google via presença de `testPurchase`.

## Dependências Externas

- `app_store_server_sdk` 1.2.10 — `getAllSubscriptionStatuses`, decodificação JWS.
- `googleapis_auth` — `clientViaServiceAccount` (escopo `androidpublisher`).
- `http` — client usado no Google (injetável em testes via `MockClient`).

## Observações

- O SDK Apple decodifica o JWS com `unverifiedPayload` — a assinatura de Apple não é validada localmente (a resposta vem por HTTPS da própria Apple).
- `now` e `isApplePlatform` são injetáveis no construtor do service; a fachada sempre usa `DateTime.now` e `Platform`.
- O cliente Google é reusado entre chamadas; `VerifyLocalPurchase.initialize`/`dispose` o fecham.
