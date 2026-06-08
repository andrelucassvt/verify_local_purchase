# Flow: Verificação de Assinatura

> **Resumo:** Verifica se uma assinatura está **ativa** consultando a loja da plataforma atual. Retorna `true` quando o status indica assinatura vigente.

## Visão Geral

`verifySubscription(token)` escolhe a loja por `Platform.isIOS` e delega para o método específico. Diferente da compra única, o critério é o **estado atual** da assinatura, não a ausência de reembolso.

```
verifySubscription(token)
   │  Platform.isIOS ?
   ├── true  ─► verifySubscriptionWithAppStore(originalTransactionId) ─► App Store: getAllSubscriptionStatuses
   └── false ─► verifySubscriptionWithGooglePlay(subscriptionToken)   ─► Google Play: subscriptionsv2
```

## Passo a Passo

### Caminho App Store (`verifySubscriptionWithAppStore`)

1. `_getConfig`; se `appleConfig` for `null`, lança `Exception('Apple configuration not provided')`.
2. Monta `AppStoreEnvironment.sandbox/live` conforme `useSandbox`.
3. Cria `AppStoreServerHttpClient` + `AppStoreServerAPI`.
4. `api.getAllSubscriptionStatuses(subscriptionToken)`.
5. Itera `statusResponse.data` → `status.lastTransactions`; no **primeiro** `lastTransaction`, retorna `subs.status == 1` (1 = ativo; 2 = cancelado; 3 = expirado).
6. Se não houver transações → retorna `false`.

### Caminho Google Play (`verifySubscriptionWithGooglePlay`)

1. `_getConfig`; se `googlePlayConfig` for `null`, lança `Exception('Google Play configuration not provided')`.
2. `jsonDecode` do `serviceAccountJson` → `ServiceAccountCredentials.fromJson`.
3. `clientViaServiceAccount` com escopo `androidpublisher`.
4. `GET .../applications/{packageName}/purchases/subscriptionsv2/tokens/{subscriptionToken}`.
5. Se HTTP 200 → lê `subscriptionState`; retorna `true` se `SUBSCRIPTION_STATE_ACTIVE` **ou** `SUBSCRIPTION_STATE_PENDING`.
6. Status ≠ 200 → lança `Exception`.
7. `finally` fecha o `authClient`.

## Arquivos Envolvidos

| Arquivo | Papel |
|---------|-------|
| `lib/verify_local_purchase.dart` | `verifySubscription`, `verifySubscriptionWithAppStore`, `verifySubscriptionWithGooglePlay` |
| `lib/service/verify_purchase_service.dart` | Implementação dos três métodos |
| `lib/models/verify_purchase_config.dart` | Credenciais por loja |
| `lib/utils/purchase_token_utils.dart` | `getSubscriptionToken` produz o token de entrada |

## Regras de Negócio

- **iOS**: token é o `originalTransactionId` (estável entre renovações/restaurações). Ativo quando `status == 1`.
- **Android**: token é o `subscriptionToken`. Ativo em `SUBSCRIPTION_STATE_ACTIVE` ou `SUBSCRIPTION_STATE_PENDING`.
- Erros de API Apple viram `Exception` (`ApiException` com `errorCode`/`errorMessage`).

## Dependências Externas

- `app_store_server_sdk` — `getAllSubscriptionStatuses`.
- `googleapis_auth` — autenticação Service Account.
- Endpoint Google: `https://androidpublisher.googleapis.com/.../purchases/subscriptionsv2/tokens/{token}`.

## Observações

- **Atenção (iOS)**: o código retorna no **primeiro** `lastTransaction` do **primeiro** `status` — não agrega múltiplos produtos/grupos de assinatura. Para apps com vários grupos, esse comportamento pode precisar de revisão.
- No Android, `SUBSCRIPTION_STATE_PENDING` é tratado como válido (assinatura em período de graça/pagamento pendente é considerada ativa).
