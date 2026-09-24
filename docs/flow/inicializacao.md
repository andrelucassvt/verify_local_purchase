---
generated_at: 2026-07-10
source_commit: 894d27a
source_state: dirty
verified_at: 2026-09-24
status: current
related_plans: []
---

# Flow: Inicialização e Configuração

> **Resumo:** `VerifyLocalPurchase.initialize()` recebe as credenciais Apple/Google, a escolha de ambiente Apple e a flag de log, descarta o service anterior (fechando os clients HTTP em cache) e cria uma nova instância de `VerifyPurchaseService` guardada na fachada estática.

## Visão Geral

A inicialização é o ponto de entrada obrigatório. A fachada `VerifyLocalPurchase` (classe `abstract final`, só estática) monta um `VerifyPurchaseConfig` e cria o `VerifyPurchaseService` que guarda essa config como campo de instância. Nenhuma chamada de rede acontece aqui: os clients são criados na primeira verificação e reusados depois.

```
main() do app
   │  VerifyLocalPurchase.initialize(appleConfig:, googlePlayConfig:, enableLogging:)
   ▼
VerifyLocalPurchase._service?.dispose()   (fecha clients da config anterior)
   ▼
VerifyLocalPurchase._service = VerifyPurchaseService(VerifyPurchaseConfig(...))
```

## Passo a Passo

1. **Fachada** — `lib/verify_local_purchase.dart` → `VerifyLocalPurchase.initialize`
   Chama `dispose()` do service anterior, se houver, e cria um novo com `VerifyPurchaseConfig(appleConfig, googlePlayConfig, enableLogging)`.
2. **Service** — `lib/service/verify_purchase_service.dart` → construtor `VerifyPurchaseService`
   Guarda a config e resolve os defaults: `AppStoreServerAPI` real, `DateTime.now`, `Platform.isIOS || Platform.isMacOS`. Em testes esses pontos são injetados (`googleClient`, `appStoreApiFactory`, `now`, `isApplePlatform`).
3. **Uso posterior** — cada método da fachada passa por `_requireService`, que lança `VerifyPurchaseException(notInitialized)` se não houver service.
4. **Encerramento** — `VerifyLocalPurchase.dispose()` fecha o `AutoRefreshingAuthClient` do Google e os `AppStoreServerHttpClient` criados, e zera o service.

## Arquivos Envolvidos

| Camada | Arquivo | Responsabilidade |
|--------|---------|------------------|
| API pública | `lib/verify_local_purchase.dart` | `initialize`, `dispose`, `_requireService` |
| Service | `lib/service/verify_purchase_service.dart` | Construtor, `dispose`, caches `_googleClientFuture` / `_appStoreApis` |
| Config | `lib/models/verify_purchase_config.dart` | `VerifyPurchaseConfig`, `AppleConfig`, `AppleEnvironment`, `GooglePlayConfig` |
| Testes | `test/verify_purchase_service_test.dart` | `notInitialized`, `missingConfig`, credenciais inválidas |

## Regras de Negócio Relevantes

- **Config por loja é opcional** — mas chamar a loja sem config lança `missingConfig` (`Apple configuration not provided` / `Google Play configuration not provided`).
- **`AppleConfig.environment` default = `productionWithSandboxFallback`** — `verify_purchase_config.dart`.
- **Logs desligados por padrão** (`enableLogging: false`); quando ligados, tokens passam por `VerifyPurchaseService.mask`.
- **Uma config por processo** — nova `initialize()` substitui (e fecha) a anterior.

## Observações

- `serviceAccountJson` só é decodificado na primeira chamada ao Google; JSON inválido aparece como `invalidCredentials` nesse momento, não no `initialize`.
- Uma falha ao autenticar no Google não fica em cache: a próxima chamada tenta de novo.
