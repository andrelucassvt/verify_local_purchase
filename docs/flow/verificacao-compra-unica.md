---
generated_at: 2026-07-10
source_commit: d18a88b
source_state: dirty
verified_at: 2026-07-10
status: current
related_plans: []
---

# Flow: Verificação de Compra Única

> **Resumo:** Valida uma compra consumível ou não-consumível consultando a loja da plataforma atual. Retorna `true` se a transação existe e **não** foi reembolsada/revogada.

## Visão Geral

`verifyPurchase(token)` escolhe a loja pela plataforma de execução (`Platform.isIOS` → App Store; caso contrário → Google Play) e delega para o método específico. Os métodos `*WithAppStore` e `*WithGooglePlay` também podem ser chamados diretamente quando o app já sabe a loja.

```
verifyPurchase(token)
   │  Platform.isIOS ?
   ├── true  ─► verifyPurchaseWithAppStore(transactionId)   ─► App Store Server API (histórico)
   └── false ─► verifyPurchaseWithGooglePlay(purchaseToken) ─► Google Play Developer API (productsv2)
```

## Passo a Passo

### Caminho App Store (`verifyPurchaseWithAppStore`)

1. Obtém a config via `_getConfig`; se `appleConfig` for `null`, lança `Exception('Apple configuration not provided')`.
2. Monta `AppStoreEnvironment.sandbox(...)` ou `.live(...)` conforme `useSandbox`.
3. Cria `AppStoreServerHttpClient` + `AppStoreServerAPI`.
4. Pagina o histórico com `api.getTransactionHistory(transactionId, revision:)` em loop enquanto `hasMore`.
5. Para cada `signedTransaction`, decodifica via `JWSTransactionDecodedPayload.fromEncodedPayload`.
6. Se `transactionId` ou `originalTransactionId` baterem:
   - `revocationDate == null` → retorna `true` (compra válida).
   - caso contrário → retorna `false` (reembolsada/revogada).
7. Se nada bater em todo o histórico → retorna `false`.

### Caminho Google Play (`verifyPurchaseWithGooglePlay`)

1. Obtém a config; se `googlePlayConfig` for `null`, lança `Exception('Google Play configuration not provided')`.
2. `jsonDecode` do `serviceAccountJson` → `ServiceAccountCredentials.fromJson`.
3. Autentica via `clientViaServiceAccount` com o escopo `androidpublisher`.
4. `GET .../applications/{packageName}/purchases/productsv2/tokens/{purchaseToken}`.
5. Se HTTP 200 → lê `purchaseStateContext.purchaseState`; retorna `true` somente se `== 'PURCHASED'`.
6. Se status ≠ 200 → lança `Exception` com status e corpo.
7. `finally` sempre fecha o `authClient`.

## Arquivos Envolvidos

| Arquivo | Papel |
|---------|-------|
| `lib/verify_local_purchase.dart` | `verifyPurchase`, `verifyPurchaseWithAppStore`, `verifyPurchaseWithGooglePlay` (fachada) |
| `lib/service/verify_purchase_service.dart` | Implementação dos três métodos |
| `lib/models/verify_purchase_config.dart` | Credenciais usadas em cada loja |
| `lib/utils/purchase_token_utils.dart` | `getOneTimePurchaseToken` produz o token de entrada |

## Regras de Negócio

- **iOS**: o token é o `transactionId`. Uma compra é válida se encontrada no histórico **e** sem `revocationDate`.
- **Android**: o token é o `purchaseToken`. Considerada válida apenas em `purchaseState == 'PURCHASED'`.
- Erros de API Apple viram `Exception` com `errorCode`/`errorMessage` (`ApiException`).

## Dependências Externas

- `app_store_server_sdk` — cliente e decodificação JWS da App Store.
- `googleapis_auth` — autenticação Service Account para a Google Play Developer API.
- Endpoint Google: `https://androidpublisher.googleapis.com/.../purchases/productsv2/tokens/{token}`.

## Observações

- A verificação Apple percorre **todo** o histórico paginado até encontrar o ID, o que pode gerar múltiplas chamadas de rede.
- Logs em português via `debugPrint` (🔍/✅/❌).
