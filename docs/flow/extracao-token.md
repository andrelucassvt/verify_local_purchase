---
generated_at: 2026-07-10
source_commit: 894d27a
source_state: dirty
verified_at: 2026-09-24
status: current
related_plans: []
---

# Flow: Extração de Token de Compra

> **Resumo:** Funções puras que convertem o `PurchaseDetails` do `in_app_purchase` no token que cada loja espera (transactionId / originalTransactionId na Apple, purchase/subscription token no Google), lançando `invalidToken` quando o dado falta; usadas pelos atalhos `verifyPurchaseDetails` e `verifySubscriptionDetails`.

## Visão Geral

O `in_app_purchase` entrega `PurchaseDetails` com formatos diferentes por plataforma. Estes helpers escondem essa diferença. O app pode chamá-los e passar a string para `verifyPurchase`/`verifySubscription`, ou usar os atalhos da fachada que fazem isso internamente.

```
PurchaseDetails
   ├── getOneTimePurchaseToken ─► verifyPurchase        (atalho: verifyPurchaseDetails)
   └── getSubscriptionToken    ─► verifySubscription    (atalho: verifySubscriptionDetails)
```

## Passo a Passo

### `getOneTimePurchaseToken(purchase)` — `lib/utils/purchase_token_utils.dart`

1. iOS/macOS → `purchase.purchaseID`; Android → `verificationData.serverVerificationData`.
2. `_requireToken`: `null` ou vazio → `VerifyPurchaseException(invalidToken)`.

### `getSubscriptionToken(purchase)` — `lib/utils/purchase_token_utils.dart`

1. iOS/macOS → `jsonDecode(verificationData.localVerificationData)`; se for `Map`, lê `originalTransactionId` (convertido com `toString()`). `FormatException` ou chave ausente → `null`.
2. Android → `verificationData.serverVerificationData`.
3. `_requireToken`: `null`/vazio → `invalidToken`.

### Atalhos — `lib/verify_local_purchase.dart`

- `verifyPurchaseDetails(purchase)` = `verifyPurchase(getOneTimePurchaseToken(purchase))`.
- `verifySubscriptionDetails(purchase)` = `verifySubscription(getSubscriptionToken(purchase))`.

## Arquivos Envolvidos

| Camada | Arquivo | Responsabilidade |
|--------|---------|------------------|
| Utils | `lib/utils/purchase_token_utils.dart` | `getOneTimePurchaseToken`, `getSubscriptionToken` |
| API pública | `lib/verify_local_purchase.dart` | Atalhos `*Details`; reexporta `in_app_purchase` e os utils |

## Regras de Negócio Relevantes

- **iOS/macOS, compra única**: `purchaseID` (transaction ID).
- **iOS/macOS, assinatura**: `originalTransactionId` do `localVerificationData`, estável entre renovações e restaurações.
- **Android (ambos)**: `serverVerificationData`.

## Dependências Externas

- `in_app_purchase` — tipo `PurchaseDetails`.

## Observações

- Os helpers usam `Platform` diretamente (sem injeção), por isso não têm teste unitário; a lógica de token vazio no service é coberta em `test/verify_purchase_service_test.dart`.
- Até a 1.x, `getOneTimePurchaseToken` devolvia `''` e `getSubscriptionToken` quebrava com cast; na 2.0.0 ambos lançam `invalidToken`.
- Tokens seguem para [verificacao-compra-unica.md](verificacao-compra-unica.md) e [verificacao-assinatura.md](verificacao-assinatura.md).
