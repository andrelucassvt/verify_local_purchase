---
generated_at: 2026-07-10
source_commit: d18a88b
source_state: dirty
verified_at: 2026-07-10
status: current
related_plans: []
---

# Sugestões de Flows a Documentar

> Gerado em 2026-07-10. Invoque a skill `flow` para criar qualquer um destes flows.

## Flows Sugeridos

### Listagem de Reembolsos
**Arquivo a criar:** `docs/flow/listagem-reembolsos.md`
**Resumo:** Documentaria as operações `getRefundsWithAppStore(originalTransactionId)` e `getRefundsWithGooglePlay({startTime, endTime})` em `lib/service/verify_purchase_service.dart`, retornando `List<RefundEntry>` (`lib/models/refund_entry.dart`). Cobriria: escopo por-cliente na Apple (`getRefundHistory`) vs. app-inteiro/paginado no Google (`voidedpurchases`, últimos 30 dias por padrão), a normalização via `RefundEntry.fromAppleTransaction` / `RefundEntry.fromGoogleVoidedPurchase`, e as limitações de campo (`productId` sempre `null` no Google; `reasonCode` sempre `null` na Apple no SDK 1.2.10).

---

## Já documentados

- `docs/flow/project-structure.md` — Estrutura geral do projeto
- `docs/flow/inicializacao.md` — Inicialização e configuração
- `docs/flow/verificacao-compra-unica.md` — Verificação de compra única (consumível/não-consumível)
- `docs/flow/verificacao-assinatura.md` — Verificação de assinatura
- `docs/flow/extracao-token.md` — Extração de token a partir de `PurchaseDetails`
