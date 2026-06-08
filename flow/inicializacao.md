# Flow: Inicialização e Configuração

> **Resumo:** Antes de qualquer verificação, o app consumidor chama `VerifyLocalPurchase.initialize()` passando as credenciais de Apple e/ou Google. Essa config é guardada em estado estático e reutilizada por todas as chamadas de verificação subsequentes.

## Visão Geral

A inicialização é o ponto de entrada obrigatório do pacote. Ela monta um `VerifyPurchaseConfig` (contendo `AppleConfig` e/ou `GooglePlayConfig`) e o armazena em um campo estático do `VerifyPurchaseService`. Qualquer verificação chamada sem inicialização prévia lança uma `Exception`.

```
main() do app
   │  VerifyLocalPurchase.initialize(appleConfig:, googlePlayConfig:)
   ▼
VerifyLocalPurchase.initialize  (fachada)
   │  delega
   ▼
VerifyPurchaseService.initialize
   │  cria
   ▼
VerifyPurchaseConfig { appleConfig?, googlePlayConfig? }  ──► VerifyPurchaseService._config (estático)
```

## Passo a Passo

1. O app consumidor chama `VerifyLocalPurchase.initialize(appleConfig: ..., googlePlayConfig: ...)`, idealmente no `main()` antes do `runApp()`.
2. A fachada delega para `VerifyPurchaseService.initialize(appleConfig:, googlePlayConfig:)`.
3. O service instancia `VerifyPurchaseConfig(appleConfig: ..., googlePlayConfig: ...)` e atribui ao campo estático `_config`.
4. A partir daí, o getter privado `_getConfig` retorna essa config; se `_config` for `null`, lança `Exception('VerifyPurchaseService not initialized...')`.

## Arquivos Envolvidos

| Arquivo | Papel |
|---------|-------|
| `lib/verify_local_purchase.dart` | Fachada pública `VerifyLocalPurchase.initialize` |
| `lib/service/verify_purchase_service.dart` | `VerifyPurchaseService.initialize`, `_config`, `_getConfig` |
| `lib/models/verify_purchase_config.dart` | `VerifyPurchaseConfig`, `AppleConfig`, `GooglePlayConfig` |

## Regras de Negócio

- `appleConfig` e `googlePlayConfig` são ambos opcionais, mas a verificação na loja correspondente falha (lança `Exception`) se a config daquela loja não tiver sido fornecida.
- `AppleConfig.useSandbox` controla se a App Store usa ambiente sandbox (`false` por padrão = produção).
- A config é **global e estática**: uma nova chamada a `initialize()` sobrescreve a anterior.

## Dependências Externas

- Nenhuma chamada de rede nesta etapa; apenas armazenamento de credenciais em memória.

## Observações

- `GooglePlayConfig.serviceAccountJson` é a string JSON completa das credenciais do Service Account; só é decodificada (`jsonDecode`) no momento da verificação.
- Por ser estado estático, não há suporte a múltiplas configurações simultâneas no mesmo processo.
