---
generated_at: 2026-07-10
source_commit: 894d27a
source_state: dirty
verified_at: 2026-09-24
status: current
related_plans: []
---

# Flow: Verificação de Compra Única

> **Resumo:** Valida uma compra consumível/não-consumível procurando o `transactionId` no histórico paginado da App Store (com fallback de sandbox) ou lendo `purchaseState` no `productsv2` do Google; devolve `VerificationResult` com `purchased`, `revoked`, `pending` ou `notFound`.

## Visão Geral

O app chama `VerifyLocalPurchase.verifyPurchase(token)` ou `verifyPurchaseDetails(purchase)` (extrai o token com `getOneTimePurchaseToken`). A fachada estática delega ao `VerifyPurchaseService`, que escolhe a loja por `Platform.isIOS || Platform.isMacOS`. Os métodos `verifyPurchaseWithAppStore` / `verifyPurchaseWithGooglePlay` podem ser chamados diretamente.

Na Apple não há endpoint de transação única no SDK 1.2.10, então o service pagina `getTransactionHistory` até encontrar o ID. No Google, uma chamada ao `productsv2` basta. Em ambos, a decisão fica em `StoreResponseParser`.

```
verifyPurchase(token)
   ├── Apple ─► verifyPurchaseWithAppStore ─► _callAppStore ─► getTransactionHistory (loop)
   │                                              └─► StoreResponseParser.appleTransaction
   └── Google ─► verifyPurchaseWithGooglePlay ─► _googleGet(productsv2)
                                                  └─► StoreResponseParser.googleProduct
```

## Passo a Passo

1. **Fachada** — `lib/verify_local_purchase.dart` → `VerifyLocalPurchase.verifyPurchase` / `verifyPurchaseDetails`
   Sem `initialize` → `VerifyPurchaseException(notInitialized)`.
2. **Roteamento** — `lib/service/verify_purchase_service.dart` → `verifyPurchase`.

### Caminho App Store

3. `verifyPurchaseWithAppStore` → `_requireToken` (vazio → `invalidToken`).
4. `_callAppStore` percorre os ambientes de `AppleConfig.environment` (default: produção e depois sandbox); códigos `4040001/4040005/4040010` passam ao próximo ambiente ou viram `notFound` no último.
5. Dentro do ambiente, loop `getTransactionHistory(transactionId, revision:)` enquanto `hasMore`; cada `signedTransaction` é decodificado com `JWSTransactionDecodedPayload.fromEncodedPayload`.
6. Ao achar `transactionId` **ou** `originalTransactionId` igual ao token → `StoreResponseParser.appleTransaction(tx, environment: historyResponse.environment)`.
7. Histórico esgotado sem match → `VerificationResult.notFound(StorePlatform.apple)` (não dispara fallback: a Apple respondeu com sucesso).

### Caminho Google Play

3. `verifyPurchaseWithGooglePlay` → `_requireToken`, `_googleConfig` (`missingConfig`).
4. `_googleGet` com o client cacheado → `GET /androidpublisher/v3/applications/{packageName}/purchases/productsv2/tokens/{token}`.
   - 404/410 → `notFound`; 401/403 → `unauthorized`; outro ≠ 200 → `apiError`; rede → `networkError`.
5. `StoreResponseParser.googleProduct(json)` lê `purchaseStateContext.purchaseState` e o `productId` do primeiro `productLineItem`.

## Arquivos Envolvidos

| Camada | Arquivo | Responsabilidade |
|--------|---------|------------------|
| API pública | `lib/verify_local_purchase.dart` | `verifyPurchase`, `verifyPurchaseDetails`, `verifyPurchaseWithAppStore`, `verifyPurchaseWithGooglePlay` |
| Service | `lib/service/verify_purchase_service.dart` | Paginação do histórico, fallback, chamada HTTP Google, erros |
| Regras | `lib/service/store_response_parser.dart` | `appleTransaction`, `googleProduct` |
| Models | `lib/models/verification_result.dart` | Resultado e estados |
| Testes | `test/store_response_parser_test.dart` | `PURCHASED`/`PENDING`/`CANCELLED`, revogação Apple |
| Testes | `test/verify_purchase_service_test.dart` | 404/410, 401, 500, rede, JSON inválido, token vazio |

## Regras de Negócio Relevantes

- **Apple**: válida se encontrada no histórico **e** sem `revocationDate`; revogada → `state: revoked`.
- **Google**: válida só em `PURCHASED`; `PENDING` → `pending` (inválida); `CANCELLED`/`CANCELED` → `revoked`.
- **`isSandbox`**: Apple pelo `environment` do histórico; Google pela presença de `testPurchaseContext`.
- **Token desconhecido não é erro** — retorna `notFound` nas duas lojas.

## Dependências Externas

- `app_store_server_sdk` 1.2.10 — `getTransactionHistory`, decodificação JWS.
- `googleapis_auth` + `http` — endpoint `productsv2`.

## Observações

- A busca Apple pode fazer várias chamadas (20 transações por página). O SDK 1.2.10 não tem `getTransactionInfo`.
- Consumíveis já finalizados podem não aparecer no histórico da Apple, dependendo da configuração do app — nesse caso o resultado é `notFound`.
