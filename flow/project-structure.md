# Estrutura do Projeto: verify_local_purchase

> **Resumo:** Pacote/plugin Flutter publicável que verifica compras e assinaturas in-app **diretamente no dispositivo**, consultando a App Store Server API (Apple) e a Google Play Developer API (Google) sem necessidade de um backend próprio.

## Stack e Tecnologias

| Elemento | Valor |
|----------|-------|
| Linguagem | Dart (SDK `^3.10.0`) + Swift (iOS/macOS) + Kotlin (Android) |
| Framework | Flutter (`>=3.3.0`) — projeto do tipo **plugin package** |
| Gerenciador de pacotes | pub (`pubspec.yaml`) |
| Principais dependências | `app_store_server_sdk`, `googleapis_auth`, `in_app_purchase`, `plugin_platform_interface` |

## Arquitetura

Este é um **pacote Flutter** (não um app), então não segue a Clean Architecture de Presentation/Domain/Data. A organização é por responsabilidade técnica: uma **fachada pública estática** (`VerifyLocalPurchase`) delega para um **service** (`VerifyPurchaseService`) que contém toda a lógica de verificação. A configuração de credenciais é injetada uma vez via `initialize()` e mantida em estado estático no service. Há ainda funções utilitárias puras para extrair os tokens corretos a partir do `PurchaseDetails` do pacote `in_app_purchase`.

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

purchase_token_utils.dart  ──► extrai o token certo de PurchaseDetails (in_app_purchase)
```

### Regras de dependência

- A verificação roda inteiramente em Dart; o canal de método nativo não é usado no fluxo principal.
- O `VerifyPurchaseService` exige `initialize()` antes de qualquer verificação — caso contrário lança `Exception`.
- A escolha de loja é por plataforma de execução: `Platform.isIOS` → App Store; caso contrário → Google Play.

## Funcionalidades (Flows)

Como pacote, não há "features" de UI; os fluxos relevantes são as operações de verificação expostas pela API pública.

| Flow | Caminho principal | Descrição resumida |
|------|-------------------|--------------------|
| Inicialização / configuração | `lib/verify_local_purchase.dart`, `lib/service/verify_purchase_service.dart`, `lib/models/verify_purchase_config.dart` | Recebe credenciais Apple/Google e guarda em estado estático |
| Verificação de compra única | `lib/service/verify_purchase_service.dart` | Valida compra consumível/não-consumível na loja da plataforma atual |
| Verificação de assinatura | `lib/service/verify_purchase_service.dart` | Verifica se uma assinatura está ativa na loja da plataforma atual |
| Extração de token de compra | `lib/utils/purchase_token_utils.dart` | Converte `PurchaseDetails` no token correto por plataforma/tipo |

## Camadas / Módulos Compartilhados

| Tipo | Caminho | Responsabilidade |
|------|---------|------------------|
| API pública (fachada) | `lib/verify_local_purchase.dart` | Ponto de entrada; exporta o pacote e delega ao service |
| Service | `lib/service/verify_purchase_service.dart` | Lógica de verificação Apple/Google; estado de config |
| Models / Config | `lib/models/verify_purchase_config.dart` | `VerifyPurchaseConfig`, `AppleConfig`, `GooglePlayConfig` |
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
| `app_store_server_sdk` | ^1.2.10 | Cliente da App Store Server API (histórico de transações, status de assinatura) |
| `googleapis_auth` | ^2.0.0 | Autenticação via Service Account para a Google Play Developer API |
| `in_app_purchase` | ^3.2.3 | Tipos de compra (`PurchaseDetails`); reexportado pela API pública |
| `plugin_platform_interface` | ^2.0.2 | Base do scaffold de platform channel |

## Observações

- **Estado estático**: `VerifyPurchaseService._config` é estático e único; o pacote assume uma única configuração global por processo.
- **App Store**: a verificação de assinatura retorna no **primeiro** `lastTransaction` encontrado (`status == 1` = ativo). A verificação de compra única pagina por todo o histórico até achar o `transactionId`/`originalTransactionId` e checa `revocationDate`.
- **Google Play**: usa chamadas HTTP diretas aos endpoints `productsv2`/`subscriptionsv2`; assinatura é considerada válida em `SUBSCRIPTION_STATE_ACTIVE` ou `SUBSCRIPTION_STATE_PENDING`.
- **Logs**: o service usa `debugPrint` com mensagens em português (emoji 🔍/✅/❌). O `CLAUDE.md` do projeto pede `log()` de `dart:developer` — há divergência entre a regra documentada e o código real.
- **Mismatch de documentação**: o `CLAUDE.md` atual descreve um app Flutter Clean Architecture (Presentation/Domain/Data, Cubits, rotas, DI) que **não corresponde** a este repositório, que é um pacote.
- **Sem testes de verificação**: `test/` e `integration_test/` no exemplo são o scaffold padrão (`getPlatformVersion`); não há cobertura da lógica de verificação.
