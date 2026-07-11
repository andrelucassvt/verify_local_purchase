---
generated_at: 2026-07-10
source_commit: d18a88b
source_state: dirty
verified_at: 2026-07-10
status: current
related_plans: []
---

# Flow: Extração de Token de Compra

> **Resumo:** Funções utilitárias puras que extraem o token correto a partir do `PurchaseDetails` do pacote `in_app_purchase`, para alimentar as verificações de compra única e de assinatura.

## Visão Geral

O pacote `in_app_purchase` entrega um `PurchaseDetails` com formatos diferentes por plataforma. Estes helpers normalizam esse dado para o token que cada loja espera, evitando que o app consumidor precise conhecer as diferenças de iOS/macOS vs Android.

```
PurchaseDetails (in_app_purchase)
   │
   ├── getOneTimePurchaseToken(purchase) ─► token p/ verifyPurchase
   └── getSubscriptionToken(purchase)    ─► token p/ verifySubscription
```

## Passo a Passo

### `getOneTimePurchaseToken(purchase)`

1. Se `Platform.isIOS || Platform.isMacOS` → retorna `purchase.purchaseID ?? ''` (o transaction ID).
2. Caso contrário (Android) → retorna `purchase.verificationData.serverVerificationData` (o purchase token).

### `getSubscriptionToken(purchase)`

1. Se `Platform.isIOS || Platform.isMacOS`:
   - `jsonDecode(purchase.verificationData.localVerificationData)`.
   - retorna `data['originalTransactionId']` (estável entre renovações e restaurações).
2. Caso contrário (Android) → retorna `purchase.verificationData.serverVerificationData` (o subscription token).

## Arquivos Envolvidos

| Arquivo | Papel |
|---------|-------|
| `lib/utils/purchase_token_utils.dart` | `getOneTimePurchaseToken`, `getSubscriptionToken` |
| `lib/verify_local_purchase.dart` | Reexporta `in_app_purchase` e os utils |

## Regras de Negócio

- **iOS/macOS, compra única**: usa `purchaseID` (transaction ID).
- **iOS/macOS, assinatura**: usa `originalTransactionId` extraído do `localVerificationData` (JSON), pois é estável.
- **Android (ambos)**: usa `serverVerificationData`.

## Dependências Externas

- `in_app_purchase` — fornece o tipo `PurchaseDetails` e os dados de verificação.

## Observações

- `getSubscriptionToken` no iOS faz `data['originalTransactionId'] as String` **sem** null-check; se o JSON não tiver a chave, lança erro em runtime.
- `getOneTimePurchaseToken` no iOS usa `?? ''`, então pode retornar string vazia se `purchaseID` for `null` — a verificação subsequente provavelmente retornará `false`.
- Os tokens produzidos aqui são exatamente o input esperado por [verificacao-compra-unica.md](verificacao-compra-unica.md) e [verificacao-assinatura.md](verificacao-assinatura.md).
