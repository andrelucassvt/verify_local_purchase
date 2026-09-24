# verify_local_purchase

Pacote Flutter publicável (pub.dev) que verifica compras e assinaturas in-app **no dispositivo**, consultando a App Store Server API (Apple) e a Google Play Developer API (Google) — sem backend próprio.

## Stack

- Dart `^3.10.0` / Flutter `>=3.38.0` — **package Dart puro** (sem código nativo), plataformas Android/iOS/macOS
- `app_store_server_sdk` — cliente da App Store Server API
- `googleapis_auth` — autenticação Service Account para a Google Play Developer API
- `http` — client HTTP (injetável nos testes via `package:http/testing.dart`)
- `in_app_purchase` — reexportado pela API pública; origem dos `PurchaseDetails`

## Arquitetura

Fachada 100% estática `VerifyLocalPurchase` → guarda uma instância de `VerifyPurchaseService` (criada no `initialize`) que faz as chamadas HTTP → `StoreResponseParser` (funções puras) converte as respostas em `VerificationResult`. **Não** é Clean Architecture com Presentation/Domain/Data — é um pacote. Não há código nativo nem platform channel (removidos na 2.0.0).

## Estrutura

- `lib/verify_local_purchase.dart` — API pública (fachada estática) + exports do pacote
- `lib/service/verify_purchase_service.dart` — chamadas Apple/Google, fallback de sandbox, cache de clients, mapeamento de erros; não exportado
- `lib/service/store_response_parser.dart` — regras puras de status → `VerificationResult` (onde mora "o que é válido")
- `lib/models/verification_result.dart` — `VerificationResult`, `VerificationState`
- `lib/models/verify_purchase_exception.dart` — `VerifyPurchaseException`, `VerifyPurchaseErrorCode`
- `lib/models/verify_purchase_config.dart` — `VerifyPurchaseConfig`, `AppleConfig`, `AppleEnvironment`, `GooglePlayConfig`
- `lib/models/refund_entry.dart` — `RefundEntry`; normaliza reembolsos Apple/Google
- `lib/models/store_platform.dart` — `StorePlatform` (apple/google)
- `lib/utils/purchase_token_utils.dart` — extrai o token certo de `PurchaseDetails`
- `test/helpers/apple_fixtures.dart` — monta JWS/StatusResponse falsos para testes
- `example/` — app de exemplo
- `.github/workflows/ci.yml` — format, analyze, test, publish dry-run
- `docs/flow/` — documentação dos fluxos do pacote

## Comandos

- `flutter analyze` — análise estática
- `flutter test` — testes unitários
- `dart format .` — formatação
- `cd example && flutter run` — roda o app de exemplo

## Convenções

- Verificação é por plataforma de execução: `Platform.isIOS || Platform.isMacOS` → App Store; caso contrário → Google Play.
- A fachada exige `initialize()` antes de qualquer verificação — senão lança `VerifyPurchaseException(notInitialized)`.
- Métodos de verificação retornam `Future<VerificationResult>`; token/transação desconhecido **não** é erro (`state: notFound`). Falhas de API/config/rede lançam `VerifyPurchaseException` com `code`.
- Regras de validade ficam em `StoreResponseParser`; o service não decide status. Toda regra nova ganha teste em `test/store_response_parser_test.dart`.
- Testes injetam dependências pelo construtor de `VerifyPurchaseService` (`googleClient`, `appStoreApiFactory`, `now`, `isApplePlatform`).
- Antes de mexer no comportamento de verificação, leia o flow relevante em `docs/flow/`.

## Gotchas

- A fachada guarda **um** service estático: uma `initialize()` descarta o anterior (e fecha seus clients); não há múltiplas configs por processo.
- Assinatura Apple: válida em status 1 (active) e 4 (grace period). Considera todos os grupos, priorizando o `lastTransaction` com o mesmo `originalTransactionId`; sem match, usa o melhor status entre todos.
- Assinatura Google: válida em `ACTIVE`/`CANCELED`/`IN_GRACE_PERIOD` **e** `expiryTime` futuro. `PENDING` **não** é válido (mudou na 2.0.0).
- Apple com `AppleEnvironment.productionWithSandboxFallback` (default): erros `4040001/4040005/4040010` em produção disparam nova tentativa no sandbox.
- `app_store_server_sdk` 1.2.10 não tem `getTransactionInfo` — compra única pagina `getTransactionHistory`. O SDK também não valida a assinatura JWS (`unverifiedPayload`).
- Reembolsos têm escopos diferentes: `getRefundsWithAppStore` é por cliente (`originalTransactionId`); `getRefundsWithGooglePlay` é do app inteiro (paginado, últimos 30 dias por padrão). `RefundEntry.productId` é sempre `null` no Google; `RefundEntry.reasonCode` é sempre `null` na Apple (SDK 1.2.10).

## Não fazer

- Não introduzir camadas de app (Cubit/Presentation/Domain/Data) — este é um pacote, não um app.
- Não criar arquivos barrel/export adicionais; os exports vivem em `lib/verify_local_purchase.dart`.
- Não fazer `flutter pub upgrade` sem perguntar — versões são pinadas.
- Logs de debug usam `_log()` (→ `debugPrint`, com emoji/PT-BR, só com `enableLogging`) no service; tokens sempre via `mask()`. Não chame `debugPrint` direto.

## 📖 Documentação de Flows

Para qualquer feature ou fluxo, verifique a pasta `./docs/flow/`: leia os títulos dos arquivos `.md` disponíveis e, se algum for relevante para a tarefa atual, leia-o antes de implementar ou debugar. Invoque a skill `flow` para criar ou atualizar flows individuais.

## 🧪 Teste funcional

Após implementar, não execute o projeto para validar o resultado (rodar o app, emulador/simulador, dispositivo físico, servidor local, screenshots ou interação simulada). Teste funcional/visual é responsabilidade do usuário.

- Limite a verificação a análise estática, build/compile e testes automatizados
- Ao concluir, liste objetivamente o que o usuário deve testar manualmente
- Não pergunte se deve executar o projeto — só faça isso se o usuário pedir explicitamente
