# verify_local_purchase

Pacote/plugin Flutter publicável (pub.dev) que verifica compras e assinaturas in-app **no dispositivo**, consultando a App Store Server API (Apple) e a Google Play Developer API (Google) — sem backend próprio.

## Stack

- Dart `^3.10.0` / Flutter `>=3.3.0` — projeto do tipo **plugin package** (Android/iOS/macOS)
- `app_store_server_sdk` — cliente da App Store Server API
- `googleapis_auth` — autenticação Service Account para a Google Play Developer API
- `in_app_purchase` — reexportado pela API pública; origem dos `PurchaseDetails`

## Arquitetura

Fachada estática pública `VerifyLocalPurchase` → delega para `VerifyPurchaseService` (toda a lógica de verificação e estado da config). **Não** é Clean Architecture com Presentation/Domain/Data — é um pacote. O scaffold de platform channel (`*_platform_interface.dart`, `*_method_channel.dart`, código nativo Swift/Kotlin) existe por ser plugin, mas só expõe `getPlatformVersion()` e **não participa da verificação** — a verificação é 100% Dart via HTTP.

## Estrutura

- `lib/verify_local_purchase.dart` — API pública (fachada) + exports do pacote
- `lib/service/verify_purchase_service.dart` — lógica de verificação Apple/Google; `_config` estático
- `lib/models/verify_purchase_config.dart` — `VerifyPurchaseConfig`, `AppleConfig`, `GooglePlayConfig`
- `lib/utils/purchase_token_utils.dart` — extrai o token certo de `PurchaseDetails`
- `lib/verify_local_purchase_{platform_interface,method_channel}.dart` — boilerplate de plugin (não usado na verificação)
- `example/` — app de exemplo do plugin
- `flow/` — documentação dos fluxos do pacote

## Comandos

- `flutter analyze` — análise estática
- `flutter test` — testes unitários
- `dart format .` — formatação
- `cd example && flutter run` — roda o app de exemplo

## Convenções

- Verificação é por plataforma de execução: `Platform.isIOS` → App Store; caso contrário → Google Play.
- `VerifyPurchaseService` exige `initialize()` antes de qualquer verificação — senão lança `Exception`.
- Métodos de verificação retornam `Future<bool>`; falhas de API/config são lançadas como `Exception`.
- Antes de mexer no comportamento de verificação, leia o flow relevante em `flow/`.

## Gotchas

- A config (`_config`) é **estática e global**: uma `initialize()` sobrescreve a anterior; não há suporte a múltiplas configs por processo.
- Assinatura iOS (`verifySubscriptionWithAppStore`) retorna no **primeiro** `lastTransaction` do **primeiro** `status` — não agrega múltiplos grupos de assinatura. Revisar antes de assumir suporte multi-grupo.
- Android trata `SUBSCRIPTION_STATE_PENDING` como assinatura ativa.
- `getSubscriptionToken` (iOS) faz `data['originalTransactionId'] as String` sem null-check — lança se a chave faltar.

## Não fazer

- Não introduzir camadas de app (Cubit/Presentation/Domain/Data) — este é um pacote, não um app.
- Não criar arquivos barrel/export adicionais; os exports vivem em `lib/verify_local_purchase.dart`.
- Não fazer `flutter pub upgrade` sem perguntar — versões são pinadas.
- Logs de debug usam `debugPrint` (com emoji/PT-BR) no service; mantenha o padrão existente do arquivo ao editá-lo.

## 📖 Documentação de Flows

Para qualquer feature ou fluxo, verifique a pasta `./flow/`: leia os títulos dos arquivos `.md` disponíveis e, se algum for relevante para a tarefa atual, leia-o antes de implementar ou debugar. Use `/flow <nome>` para criar ou atualizar flows individuais.
