---
generated_at: 2026-07-10
source_commit: 894d27a
source_state: dirty
verified_at: 2026-09-24
status: current
related_plans: []
---

# Estrutura do Projeto: verify_local_purchase

> **Resumo:** Pacote Flutter em Dart puro (pub.dev, v2.0.0) que verifica compras e assinaturas in-app **no dispositivo** e lista reembolsos, consultando a App Store Server API e a Google Play Developer API sem backend, devolvendo `VerificationResult` e erros tipados.

## Stack e Tecnologias

| Elemento | Valor |
|----------|-------|
| Linguagem | Dart (SDK `^3.10.0`) — sem código nativo |
| Framework | Flutter (`>=3.38.0`); plataformas declaradas: Android, iOS, macOS |
| Gerenciador de pacotes | pub (`pubspec.yaml`) |
| Principais dependências | `app_store_server_sdk`, `googleapis_auth`, `http`, `in_app_purchase` |
| Versão do pacote | 2.0.0 |
| CI | `.github/workflows/ci.yml` (format, analyze, test, publish dry-run) |

## Arquitetura

Pacote, não app: organização por responsabilidade técnica, sem Presentation/Domain/Data.

- **Fachada** `VerifyLocalPurchase` (`abstract final`, só estática) guarda uma instância de `VerifyPurchaseService` criada no `initialize`.
- **Service** faz o I/O: App Store via `app_store_server_sdk`, Google via `googleapis_auth` + `http`; trata fallback de sandbox, cache de clients e converte falhas em `VerifyPurchaseException`.
- **`StoreResponseParser`** contém as regras puras que transformam respostas das lojas em `VerificationResult`.
- **Utils** extraem o token certo de `PurchaseDetails`.

O scaffold de platform channel e as pastas `android/`, `ios/`, `macos/` foram removidos na 2.0.0.

```
App ─► VerifyLocalPurchase (estática) ─► VerifyPurchaseService ─► App Store Server API
                                              │                 └► Google Play Developer API
                                              └► StoreResponseParser ─► VerificationResult
purchase_token_utils ─► token a partir de PurchaseDetails
```

### Regras de dependência

- Service não decide validade; parser não faz I/O.
- Loja escolhida por `Platform.isIOS || Platform.isMacOS` (Apple) nas operações genéricas; reembolsos são sempre por loja explícita.
- Toda falha pública é `VerifyPurchaseException`; token desconhecido é `state: notFound`, não erro.

## Funcionalidades (Flows)

| Flow | Caminho principal | Descrição resumida | Documentado |
|------|-------------------|--------------------|-------------|
| Inicialização | `lib/verify_local_purchase.dart` | Cria o service com credenciais, ambiente Apple e flag de log | [inicializacao.md](inicializacao.md) |
| Compra única | `lib/service/verify_purchase_service.dart` | Histórico Apple / `productsv2` Google | [verificacao-compra-unica.md](verificacao-compra-unica.md) |
| Assinatura | `lib/service/verify_purchase_service.dart`, `lib/service/store_response_parser.dart` | Status Apple / `subscriptionsv2` Google com expiração | [verificacao-assinatura.md](verificacao-assinatura.md) |
| Extração de token | `lib/utils/purchase_token_utils.dart` | `PurchaseDetails` → token por plataforma | [extracao-token.md](extracao-token.md) |
| Reembolsos | `lib/service/verify_purchase_service.dart`, `lib/models/refund_entry.dart` | Apple (por cliente) e Google (app inteiro, paginado) | _sugerido_ ([flow-suggestions.md](flow-suggestions.md)) |

## Camadas / Módulos Compartilhados

| Tipo | Caminho | Responsabilidade |
|------|---------|------------------|
| API pública | `lib/verify_local_purchase.dart` | Fachada estática e exports |
| Service | `lib/service/verify_purchase_service.dart` | I/O, fallback, cache, erros, log mascarado |
| Regras | `lib/service/store_response_parser.dart` | Status das lojas → `VerificationResult` |
| Models | `lib/models/verification_result.dart` | `VerificationResult`, `VerificationState` |
| Models | `lib/models/verify_purchase_exception.dart` | `VerifyPurchaseException`, `VerifyPurchaseErrorCode` |
| Models | `lib/models/verify_purchase_config.dart` | Configs e `AppleEnvironment` |
| Models | `lib/models/refund_entry.dart`, `lib/models/store_platform.dart` | Reembolsos normalizados, `StorePlatform` |
| Utils | `lib/utils/purchase_token_utils.dart` | Extração de token |
| Testes | `test/` | Parser, service (HTTP mockado, API Apple fake), `RefundEntry` |

## Configuração

| Componente | Arquivo | Responsabilidade |
|-----------|---------|------------------|
| Credenciais | `lib/models/verify_purchase_config.dart` | Apple/Google, ambiente Apple, logging |
| Manifest | `pubspec.yaml` | Versão, deps, `platforms:` |
| Lint | `analysis_options.yaml` | `flutter_lints` |
| CI | `.github/workflows/ci.yml` | Gate de format/analyze/test/publish |

## Dependências Externas Principais

| Pacote | Versão | Uso |
|--------|--------|-----|
| `app_store_server_sdk` | ^1.2.10 | Histórico, status de assinatura, reembolsos Apple |
| `googleapis_auth` | ^2.0.0 | OAuth Service Account (client reusado) |
| `http` | ^1.6.0 | Chamadas Google; `MockClient` nos testes |
| `in_app_purchase` | ^3.2.3 | `PurchaseDetails`; reexportado |

## Observações

- Credenciais (.p8 e Service Account) vão dentro do binário do app consumidor — o README documenta o trade-off de segurança.
- O SDK Apple não valida a assinatura JWS localmente (`unverifiedPayload`); verificação JWS offline não existe no pacote.
- `.github/copilot-instructions.md` descreve outro repositório (hub de instruções) e não este pacote.
