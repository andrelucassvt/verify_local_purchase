---
generated_at: 2026-07-10
source_commit: d18a88b
source_state: dirty
verified_at: 2026-07-10
status: current
related_plans: []
---

# Estrutura do Projeto: verify_local_purchase

> **Resumo:** Pacote/plugin Flutter publicável (pub.dev) que verifica compras e assinaturas in-app **diretamente no dispositivo** e lista reembolsos, consultando a App Store Server API (Apple) e a Google Play Developer API (Google) — sem backend próprio.

## Stack e Tecnologias

| Elemento | Valor |
|----------|-------|
| Linguagem | Dart (SDK `^3.10.0`) + Swift (iOS/macOS) + Kotlin (Android) |
| Framework | Flutter (`>=3.3.0`) — projeto do tipo **plugin package** |
| Gerenciador de pacotes | pub (`pubspec.yaml`) |
| Principais dependências | `app_store_server_sdk`, `googleapis_auth`, `in_app_purchase`, `plugin_platform_interface` |
| Versão do pacote | 1.1.0 |

## Arquitetura

Este é um **pacote Flutter** (não um app), então não segue a Clean Architecture de Presentation/Domain/Data. A organização é por responsabilidade técnica: uma **fachada pública estática** (`VerifyLocalPurchase`) delega para um **service** (`VerifyPurchaseService`) que contém toda a lógica de verificação e listagem de reembolsos. A configuração de credenciais é injetada uma vez via `initialize()` e mantida em estado estático no service. Há ainda funções utilitárias puras para extrair os tokens corretos a partir do `PurchaseDetails` do pacote `in_app_purchase`.

O scaffold de **plugin platform-channel** (`platform_interface` + `method_channel` + código nativo Swift/Kotlin) existe por ser um plugin package, mas atualmente expõe apenas `getPlatformVersion()` e **não participa do fluxo de verificação** — a verificação é 100% Dart, via chamadas HTTP às APIs das lojas.

```
App consumidor
      │  VerifyLocalPurchase.initialize(appleConfig, googlePlayConfig)
      ▼
VerifyLocalPurchase (fachada estática pública)
      │  delega
      ▼
VerifyPurchaseService  ──► App Store Server API   (app_store_server_sdk)
                       └─► Google Play Developer API (googleapis_auth + HTTP)
        │
        ├─ verifyPurchase / verifySubscription        ──► Future<bool>
        └─ getRefundsWithAppStore / ...GooglePlay      ──► Future<List<RefundEntry>>

purchase_token_utils.dart  ──► extrai o token certo de PurchaseDetails (in_app_purchase)
```

### Regras de dependência

- A verificação roda inteiramente em Dart; o canal de método nativo não é usado no fluxo principal.
- O `VerifyPurchaseService` exige `initialize()` antes de qualquer verificação ou listagem — caso contrário lança `Exception`.
- A escolha de loja nas operações genéricas é por plataforma de execução: `Platform.isIOS` → App Store; caso contrário → Google Play. As operações de reembolso são chamadas por loja explicitamente.

## Funcionalidades (Flows)

Como pacote, não há "features" de UI; os fluxos relevantes são as operações expostas pela API pública.

| Flow | Caminho principal | Descrição resumida | Documentado |
|------|-------------------|--------------------|-------------|
| Inicialização / configuração | `lib/verify_local_purchase.dart`, `lib/service/verify_purchase_service.dart`, `lib/models/verify_purchase_config.dart` | Recebe credenciais Apple/Google e guarda em estado estático | [inicializacao.md](inicializacao.md) |
| Verificação de compra única | `lib/service/verify_purchase_service.dart` | Valida compra consumível/não-consumível na loja da plataforma atual | [verificacao-compra-unica.md](verificacao-compra-unica.md) |
| Verificação de assinatura | `lib/service/verify_purchase_service.dart` | Verifica se uma assinatura está ativa na loja da plataforma atual | [verificacao-assinatura.md](verificacao-assinatura.md) |
| Extração de token de compra | `lib/utils/purchase_token_utils.dart` | Converte `PurchaseDetails` no token correto por plataforma/tipo | [extracao-token.md](extracao-token.md) |
| Listagem de reembolsos | `lib/service/verify_purchase_service.dart`, `lib/models/refund_entry.dart` | Lista reembolsos: Apple (por cliente) e Google (app inteiro, paginado) | _sugerido_ ([flow-suggestions.md](flow-suggestions.md)) |

## Camadas / Módulos Compartilhados

| Tipo | Caminho | Responsabilidade |
|------|---------|------------------|
| API pública (fachada) | `lib/verify_local_purchase.dart` | Ponto de entrada; exporta o pacote e delega ao service |
| Service | `lib/service/verify_purchase_service.dart` | Lógica de verificação e reembolsos Apple/Google; estado de config |
| Models / Config | `lib/models/verify_purchase_config.dart` | `VerifyPurchaseConfig`, `AppleConfig`, `GooglePlayConfig` |
| Models / Reembolso | `lib/models/refund_entry.dart` | `RefundEntry`, `RefundPlatform`; normaliza reembolsos Apple/Google |
| Utils | `lib/utils/purchase_token_utils.dart` | `getOneTimePurchaseToken`, `getSubscriptionToken` |
| Plugin scaffold | `lib/verify_local_purchase_platform_interface.dart`, `lib/verify_local_purchase_method_channel.dart` | Boilerplate de platform channel (`getPlatformVersion`) |
| Código nativo | `ios/Classes/`, `macos/Classes/`, `android/src/main/kotlin/` | Implementações nativas do plugin (Swift/Kotlin) |

## Configuração

| Componente | Arquivo | Responsabilidade |
|-----------|---------|------------------|
| Configuração de credenciais | `lib/models/verify_purchase_config.dart` | Define os dados de Apple/Google necessários |
| Inicialização | `lib/verify_local_purchase.dart` → `VerifyPurchaseService.initialize` | Registra a config em estado estático |
| Manifest do pacote | `pubspec.yaml` | Nome, versão, dependências, declaração de plugin |
| Lint | `analysis_options.yaml` | Regras de análise estática (`flutter_lints`) |

## Dependências Externas Principais

| Pacote | Versão | Uso no projeto |
|--------|--------|----------------|
| `app_store_server_sdk` | ^1.2.10 | Cliente da App Store Server API (histórico, status de assinatura, histórico de reembolsos) |
| `googleapis_auth` | ^2.0.0 | Autenticação via Service Account para a Google Play Developer API |
| `in_app_purchase` | ^3.2.3 | Tipos de compra (`PurchaseDetails`); reexportado pela API pública |
| `plugin_platform_interface` | ^2.0.2 | Base do scaffold de platform channel |

## Observações

- **Estado estático**: `VerifyPurchaseService._config` é estático e único; o pacote assume uma única configuração global por processo. Uma nova `initialize()` sobrescreve a anterior.
- **App Store**: a verificação de assinatura retorna no **primeiro** `lastTransaction` do **primeiro** `status` (`status == 1` = ativo) — não agrega múltiplos grupos. A verificação de compra única pagina por todo o histórico (`getTransactionHistory`) até achar o `transactionId`/`originalTransactionId` e checa `revocationDate`.
- **Google Play**: usa chamadas HTTP diretas aos endpoints `productsv2` (`purchaseState == 'PURCHASED'`) / `subscriptionsv2` (assinatura válida em `SUBSCRIPTION_STATE_ACTIVE` **ou** `SUBSCRIPTION_STATE_PENDING`).
- **Reembolsos**: `getRefundsWithAppStore` é por cliente (`originalTransactionId`, via `getRefundHistory`); `getRefundsWithGooglePlay` é do app inteiro (`voidedpurchases`, paginado, últimos 30 dias por padrão). O `voidedpurchases` **não** retorna `productId`, então `RefundEntry.productId` é sempre `null` no Google; no Apple, `RefundEntry.reasonCode` é sempre `null` (SDK 1.2.10 não expõe `revocationReason`).
- **Logs**: o service usa `debugPrint` com mensagens em português (emojis 🔍/✅/❌) — padrão consistente entre `CLAUDE.md` e o código.
- **Estado de análise**: o working tree estava `dirty` no momento desta geração, mas o código-fonte em `lib/` corresponde ao commit `d18a88b` (sem modificações locais em `lib/`).
- **Sem testes de verificação**: os testes em `test/` e `integration_test/` do exemplo são o scaffold padrão (`getPlatformVersion`); não há cobertura da lógica de verificação/reembolso.
