---
name: implement-in-app-purchase
description: "Implements In-App Purchase (consumable, non-consumable, or subscription) with a complete paywall following the project architecture. Asks whether there is a backend server, then generates the full implementation: PurchaseIds, InAppPurchaseService, EntitlementService (on-device verification via verify_local_purchase 2.x + StorageService OR backend endpoint), Cubit, State, View, DI registration, l10n keys and tests. Also migrates apps from verify_local_purchase 1.x. Use whenever adding purchases, subscriptions, paywall, or premium features to the app, integrating App Store or Google Play billing, verifying receipts, restoring purchases, or deciding whether the user is premium. Activate even when the user says 'make the app paid', 'add a paywall', 'implement premium', 'add a subscription plan', 'unlock premium features', 'add a pro version', 'restore purchases is stuck', or 'monetize the app' without explicitly mentioning InAppPurchase, StoreKit, or Google Play Billing."
metadata:
  version: "2.0.0"
  last_modified: 2026-09-24
  min_flutter: "3.38"
  verify_local_purchase: "^2.0.0"
  example_prompt: "Implemente uma paywall de assinatura com restauração, l10n e testes do Cubit"
---

# Implement In-App Purchase — Flutter

Implementa compras únicas (consumível e não-consumível) e assinaturas com um paywall completo, seguindo a
arquitetura de referência da skill `flutter-expert` (Cubit + GetIt + GoRouter, `Result<T>`, `StorageService`,
`context.l10n`). Em projeto com convenções próprias, siga as do projeto — os caminhos abaixo são a proposta,
não uma regra.

## Leitura Rápida

- **Passo 1 obrigatório**: faça todas as perguntas em uma única mensagem e aguarde antes de gerar código.
- **Comprar é assíncrono**: `buy()` só abre a loja. Todo resultado (compra, restauração, cancelamento, erro,
  pendência) chega pelo `purchaseStream` e é tratado em um único lugar: `_onPurchaseUpdates` no Cubit.
- **Um Cubit para os dois modos**: a diferença entre "sem back-end" (🅰) e "com back-end" (🅱) é qual
  implementação de `EntitlementService` entra no DI. Service, Cubit, State e View não mudam.
- **Verificação tem três respostas**, não duas: `GrantResult.valid` (concede e completa), `invalid` (não
  concede, mas completa para a loja parar de reentregar) e `unavailable` (sem rede/servidor — NÃO completa; a
  loja reentrega e a verificação roda de novo). Confundir `unavailable` com `invalid` faz a usuária perder uma
  compra paga.
- **`GrantResult` ≠ `VerificationResult`**: o `verify_local_purchase` 2.x devolve `VerificationResult`
  (`isValid`, `state`, `productId`, `expiresAt`, `isSandbox`) e lança `VerifyPurchaseException` com `code`. O
  `LocalEntitlementService` traduz um no outro pela tabela de `service.md` §5.3: `isValid` → `valid`;
  `pending`/`unknown` → `unavailable`; demais estados → `invalid`; qualquer exceção → `unavailable`. Nunca
  nomeie o enum do app de `VerificationResult` — colide com o do pacote.
- **Loading nunca é infinito**: `PaywallLoading` existe só para carregar produtos. Compra e restauração mantêm
  o paywall visível com `PaywallLoaded(inProgress: true)`, e um watchdog libera a tela se a loja não responder.
- **"Nada para restaurar" chega como lista vazia** no `purchaseStream` — no Android, no StoreKit 1 e no
  StoreKit 2 (verificado no código de `in_app_purchase_android` 0.5.3 e `in_app_purchase_storekit` 0.4.12).
  Trate a lista vazia como o sinal, e o watchdog como rede de segurança.
- **Sandbox não é flavor**: TestFlight e a revisão da App Store geram transações de sandbox em builds de
  produção. No modo 🅰 o default `AppleEnvironment.productionWithSandboxFallback` já resolve (produção e, se a
  Apple disser "não encontrada", sandbox). `VerifyLocalPurchase.initialize()` roda **uma vez** no `main()`.
- **Método por tipo**: consumível → `buyConsumable` + verificação de compra única; não-consumível →
  `buyNonConsumable` + compra única; assinatura → `buyNonConsumable` + verificação de assinatura (sim, assinatura
  também compra com `buyNonConsumable` — é assim que o plugin funciona). No modo 🅰 a verificação passa pelo
  `PurchaseVerifier` (porta testável sobre a fachada estática `VerifyLocalPurchase`).
- **`refresh()` reverifica tudo que dá acesso**: assinaturas (expiração, grace period) e não-consumíveis
  (reembolso vira `state: revoked`). Assinatura expirada ou em billing retry perde o acesso mas **mantém o
  token** — se o pagamento voltar, o próximo `refresh()` devolve o acesso sem "Restaurar".
- **Cubit emite causas, não textos**: `PaywallErrorKind` e `PaywallNotice` são enums; a View traduz com
  `context.l10n`.
- **Apple 3.1.2**: paywall com assinatura exibe preço, período e renovação automática, links de Termos de Uso
  e Política de Privacidade, e botão "Restaurar compras". Sem isso a revisão rejeita.
- **Segurança**: nunca desbloqueie conteúdo confiando só no que está no dispositivo; veja a seção Segurança.
- **Compra de loja é do aparelho, não da conta do app**: em app com login, o token que `refresh()` re-verifica
  é o registro gravado neste aparelho por `verifyAndGrant`, que sobrevive ao logout. Um espelho remoto
  (`users/{uid}`) serve para visibilidade e grant manual — nunca como fonte da re-verificação, senão "Restaurar"
  em outra conta propaga o Plus para todos os aparelhos dela. Veja "Apps com login".

## Referências

| Arquivo | Quando ler |
|---|---|
| `references/service.md` | Sempre — `PurchaseIds`, `InAppPurchaseService`, contrato `EntitlementService`/`GrantResult`, `PurchaseVerifier` + `LocalEntitlementService` (🅰) com a tabela `VerificationResult` → `GrantResult`, e a seção 7 para apps com login (registro do aparelho, espelho remoto, grant manual) |
| `references/cubit-state.md` | Sempre — `PaywallState`, enums e `PaywallCubit` completo |
| `references/view.md` | Sempre — `PaywallView`, chaves de l10n e ARB |
| `references/setup.md` | Sempre — pubspec, configuração das lojas, DI, credenciais por `--dart-define` + `initialize()` no `main()`, rota, Splash e migração de apps na 1.x do pacote |
| `references/backend.md` | Só no modo 🅱 — `PurchaseRepository`, DataSource, RepositoryImpl, `ServerEntitlementService`, contrato dos endpoints |
| `references/testing.md` | Ao fechar — testes do Cubit com fakes (máquina de estados sem loja) e, no 🅰, do `LocalEntitlementService` com `PurchaseVerifier` fake |

---

## Passo 1 — Perguntas obrigatórias (uma única mensagem)

Use a ferramenta de perguntas da plataforma se existir (ex.: `AskUserQuestion`); senão liste e aguarde.

```
1. O app tem back-end próprio?
   - SIM → o servidor valida e registra as compras (modo 🅱)
   - NÃO → verificação no dispositivo com verify_local_purchase (modo 🅰)

   Se já existe integração com verify_local_purchase 1.x → migre (setup.md §7)

2. Quais tipos de produto? (pode marcar mais de um)
   - [ ] Consumível (ex.: pacote de créditos)
   - [ ] Não-consumível permanente (ex.: remover anúncios)
   - [ ] Assinatura (ex.: plano mensal/anual)

3. Quais são os IDs dos produtos, por tipo, exatamente como cadastrados
   no App Store Connect e no Google Play Console?
   Ex.: "coins_100", "remove_ads", "premium_monthly"

4. Qual é o nome da feature/tela? Ex.: "paywall", "premium", "store"

5. O que acontece logo após uma compra concluída?
   - Fechar o paywall e voltar (pop) — padrão
   - Navegar para uma rota específica → qual?
   - Permanecer no paywall mostrando o estado desbloqueado

6. Se houver assinatura: URLs de Termos de Uso e Política de Privacidade?
   (obrigatórias — Apple 3.1.2(c); use placeholder se ainda não existirem)
```

As respostas definem `PurchaseIds`, qual `EntitlementService` vai no DI, o nome dos arquivos, o `listener` de
`PaywallSuccess` e os links do paywall. Os templates usam `paywall` como nome — renomeie conforme a resposta 4.

---

## Passo 2 — Arquitetura da feature

```
View ──buy()/restore()──▶ PaywallCubit ──▶ InAppPurchaseService ──▶ App Store / Google Play
                              ▲                                          │
                              └────────────── purchaseStream ◀───────────┘
                              │
                     _onPurchaseUpdates
                              │
                     EntitlementService.verifyAndGrant(purchase)   ◀── ÚNICO ponto que muda
                        ├─ 🅰 LocalEntitlementService  → PurchaseVerifier (verify_local_purchase) + StorageService
                        └─ 🅱 ServerEntitlementService → PurchaseRepository → POST /purchases/verify
```

Arquivos comuns aos dois modos:

```
lib/common/services/in_app_purchase/
├── purchase_ids.dart                  # IDs por tipo — única fonte
├── in_app_purchase_service.dart       # interface + exceções tipadas de carregamento
├── in_app_purchase_service_impl.dart  # wrapper do plugin (nenhuma verificação aqui)
├── entitlement_service.dart           # contrato: GrantResult + verifyAndGrant / hasAccess / refresh
├── local_purchase_verification.dart   # 🅰 initLocalPurchaseVerification() — chamado no main()
├── purchase_verifier.dart             # 🅰 porta para verify_local_purchase (interface)
├── purchase_verifier_impl.dart        # 🅰 delega para VerifyLocalPurchase.*WithAppStore/*WithGooglePlay
└── local_entitlement_service.dart     # 🅰
lib/presentation/paywall/
├── view_model/paywall_state.dart
├── view_model/paywall_cubit.dart
└── view/paywall_view.dart
test/presentation/paywall/paywall_cubit_test.dart
test/common/services/in_app_purchase/local_entitlement_service_test.dart   # 🅰
```

Só no modo 🅱, no lugar dos arquivos 🅰:

```
lib/common/services/in_app_purchase/server_entitlement_service.dart
lib/domain/interfaces/purchase_repository.dart
lib/data/datasources/purchase_remote_datasource.dart
lib/data/repositories/purchase_repository_impl.dart
```

`ServerEntitlementService` é um adaptador fino sobre o `PurchaseRepository`: existe para o Cubit não mudar
entre os modos.

---

## Passo 3 — Workflow: ordem de implementação

- [ ] 1. `pubspec.yaml` e configuração das lojas → `references/setup.md`
- [ ] 2. `PurchaseIds` + `InAppPurchaseService` (interface e impl) → `references/service.md`
- [ ] 3. `EntitlementService` + a implementação do modo escolhido → `references/service.md` (🅰) ou
   `references/backend.md` (🅱)
- [ ] 4. `PaywallState` + `PaywallCubit` → `references/cubit-state.md`
- [ ] 5. `PaywallView` + chaves nos ARB + `flutter gen-l10n` → `references/view.md` e `flutter-setup-localization`
- [ ] 6. Rota, registro no DI, `initLocalPurchaseVerification()` no `main()` (🅰) e `refresh()` na inicialização
   → `references/setup.md`
- [ ] 7. Testes do Cubit e, no 🅰, do `LocalEntitlementService` → `references/testing.md`
- [ ] 8. **Feedback loop:** `dart format --set-exit-if-changed lib test && flutter analyze --fatal-infos --fatal-warnings && flutter test` → revisar → corrigir → repetir

---

## Passo 4 — O que chega pelo stream e o que fazer

| Evento | Tratamento no Cubit | Por quê |
|---|---|---|
| Lista vazia | Se estava restaurando → `nothingToRestore`; senão ignore | É como as três plataformas dizem "restore terminou sem compras" |
| `pending` | Libera a tela com `pendingApproval` | Ask to Buy / aprovação parental / pagamento pendente podem levar dias; quando resolver, `purchased` chega pelo stream, mesmo em outra sessão |
| `canceled` | Completa se `pendingCompletePurchase`; libera sem aviso | Desistir não é erro. Sem completar, o StoreKit 2 bloqueia nova compra do mesmo produto (`storekit_duplicate_product_object`) |
| `error` | Completa se `pendingCompletePurchase`; libera com `purchaseFailed` | Sem completar, o iOS reentrega a transação com erro a cada abertura |
| `purchased`/`restored` + `valid` | `completePurchase` + `PaywallSuccess` (uma vez por lote) | Concede só depois da fonte de verdade confirmar |
| `purchased`/`restored` + `invalid` | Completa; aviso `verificationFailed` | Reembolsada/expirada/inexistente: não concede e para a reentrega |
| `purchased`/`restored` + `unavailable` | NÃO completa; aviso `verificationUnavailable` | Sem rede ou servidor fora: a loja reentrega e a verificação roda de novo |
| Erro no próprio stream (`onError`) | Libera com `purchaseFailed` | Sem `onError` a subscription morre em silêncio e a tela espera para sempre |
| Nada chega (watchdog) | Libera com `storeTimeout` ou `nothingToRestore` | Nenhuma chamada do plugin tem timeout nativo |

---

## Passo 5 — Como o app sabe que a usuária tem acesso

O paywall concede; o resto do app pergunta ao `EntitlementService`, nunca ao `StorageService` nem ao plugin:

- `hasAccess(productId)` — resposta rápida e offline-friendly, baseada no último estado conhecido. No 🅰 usa o
  `expiresAt` que a loja devolveu: offline, a assinatura vale até `expiresAt` + `offlineTolerance` (3 dias).
  Para "é premium?" pergunte por qualquer ID de `PurchaseIds.subscriptions` — após upgrade o registro fica sob o
  plano novo.
- `refresh()` — reconsulta a fonte de verdade. Chame uma vez na inicialização (Splash), porque cancelamento,
  expiração e reembolso de assinatura não chegam ao dispositivo sozinhos.
- Reinstalação ou troca de aparelho: no modo 🅰 o dispositivo está vazio e o botão "Restaurar compras" reaciona
  o fluxo com `PurchaseStatus.restored`. No modo 🅱 o servidor já sabe — `refresh()` resolve.
- Consumível (créditos): o efeito é do domínio do app e é aplicado dentro de `verifyAndGrant`, com
  idempotência por `purchaseID` — se a loja reentregar a transação, não credita duas vezes.

Se o projeto já tem um `PremiumService`/`FeatureGateService` (padrão de `flutter-expert/references/service.md`),
faça-o delegar para `EntitlementService.hasAccess` em vez de duplicar a regra.

---

## Apps com login — conta do app ≠ conta da loja

Uma assinatura pertence ao Apple ID / conta Google do aparelho, não ao usuário autenticado no app. Quando o
app tem login (Firebase Auth, back-end próprio) e espelha o status em um documento remoto por usuário, surge
uma brecha no modo 🅰:

```
Conta A assina → users/A recebe {isPlus, token}
Logout → login com a conta B no MESMO aparelho → "Restaurar" → users/B recebe o mesmo token
Conta B entra em QUALQUER outro aparelho → refresh() lê o token de users/B → Plus sem pagar
```

O ponto que vaza não é a restauração (a conta de loja pagante está presente no aparelho — isso é legítimo
e inevitável sem servidor); é o `refresh()` confiar no token que está no documento remoto. Regras:

- **Registro do aparelho é a única fonte da re-verificação.** `verifyAndGrant` grava o token localmente
  (`entitlement_<productId>`) e `refresh()` re-verifica só esse registro, com a plataforma (`source`) dele.
  Sem registro local, o status é "sem acesso" mesmo que o documento remoto tenha token — e o remoto **não**
  é escrito nesse caso (não há evidência).
- **O registro sobrevive ao logout e à exclusão de conta.** Se o app tem um "limpar sessão" que remove chaves
  do `StorageService`, as chaves de entitlement ficam de fora: são do aparelho, não da conta. Quem entrar em
  seguida no mesmo aparelho re-verifica pelo mesmo token — mesma conta de loja pagante.
- **Espelho remoto é saída, não entrada.** Escreva `users/{uid}` (merge) em `verifyAndGrant` e no resultado de
  `refresh()` para o admin enxergar o status; nunca copie `purchaseDetails` do remoto para o cache local.
- **Grant manual é uma plataforma própria.** `plataforma: 'manual'` (com ou sem expiração) no documento remoto
  concede acesso em qualquer aparelho pela regra local de validade, e o app **nunca** escreve sobre esse
  documento — é o mecanismo para tornar alguém premium sem compra.
- **Migração.** Se uma versão anterior espelhava o remoto no cache local, promova o token desse cache a
  registro do aparelho uma única vez na primeira `refresh()` sem registro — assinantes atuais não devem
  precisar tocar em "Restaurar". Instalações que já haviam herdado um token continuam com acesso **só naquele
  aparelho**; nada novo se propaga.
- **Consequências a declarar para o time**: duas contas no mesmo aparelho ficam premium (mesma conta de loja);
  a mesma conta em um aparelho novo precisa de "Restaurar" — a propagação automática entre aparelhos via
  documento remoto deixa de existir. Isso é o comportamento padrão das lojas; o modo 🅱 é o caminho para
  vincular compra ↔ usuária no servidor.

Implementação de referência: `references/service.md`, seção 7.

---

## Passo 6 — Checklist final

- [ ] `PurchaseIds` com os IDs REAIS da resposta 3, cada um no Set do tipo certo
- [ ] Apenas UMA implementação de `EntitlementService` registrada no DI (🅰 ou 🅱)
- [ ] `listener` de `PaywallSuccess` implementando a resposta 5 — não invente comportamento
- [ ] Todos os `PaywallErrorKind` e `PaywallNotice` traduzidos na View, com chaves nos ARB (en e pt)
- [ ] Rota adicionada em `app_routes.dart` e `app_router.dart`
- [ ] 🅰: `verify_local_purchase: ^2.0.0`; `initialize()` uma vez no `main()` com `enableLogging: kDebugMode`;
      `AppleConfig.environment` no default; credenciais via `--dart-define`, secrets no `.gitignore`
- [ ] 🅰: enum do app se chama `GrantResult`; `VerifyPurchaseException` de config (`missingConfig`,
      `invalidCredentials`, `unauthorized`, `notInitialized`) vira `unavailable` **e** é reportada
- [ ] 🅱: contrato dos endpoints alinhado com o time de back-end (`references/backend.md`)
- [ ] `refresh()` chamado na inicialização
- [ ] App com login: `refresh()` re-verifica só o registro do aparelho; chaves de entitlement fora da limpeza de
      sessão; documento remoto escrito apenas como espelho; grant `manual` nunca sobrescrito
- [ ] Capability In-App Purchase no Xcode; produtos ativos nas duas lojas
- [ ] Testes cobrindo cada linha da tabela `VerificationResult` → `GrantResult` (🅰)
- [ ] `flutter analyze` e `flutter test` limpos

Ao concluir, informe o que a usuária deve testar manualmente (a skill não roda o app):

- Compra de cada tipo com conta de teste (Sandbox Tester na App Store; testador de licença no Google Play)
- Após a compra, o comportamento da resposta 5 acontece
- Cancelar no diálogo da loja → paywall volta ao normal, sem aviso de erro
- "Restaurar compras" sem nenhuma compra na conta → aviso "nada a restaurar" em poucos segundos, nas duas
  plataformas
- "Restaurar compras" após reinstalar, com compra real → acesso volta
- Modo avião durante a verificação → aviso de verificação indisponível; ao voltar a rede e reabrir o app, a
  compra é liberada sem cobrar de novo
- Links de Termos e Privacidade abrem no navegador externo
- 🅰 em TestFlight: a verificação funciona (transação de sandbox em build de produção, via fallback)
- 🅰 sem credencial de uma loja (ou chave errada): a compra fica pendente com aviso de verificação indisponível
  e o log de debug mostra `VerifyPurchaseException(missingConfig|unauthorized)` — nunca "compra inválida"
- 🅰 reembolso (Google: reembolsar pelo Play Console; Apple: sandbox não gera reembolso real) → após reabrir o
  app, `refresh()` remove o acesso
- App com login: conta A assina → logout → conta B no mesmo aparelho abre o app **sem** acesso; B em outro
  aparelho (sem a conta de loja) continua sem acesso e o documento remoto de B não é reescrito; grant
  `manual` no console concede em qualquer aparelho e nunca é sobrescrito

---

## Segurança

- **🅰**: `verify_local_purchase` consulta as APIs oficiais da Apple e do Google, o que barra recibos forjados e
  detecta reembolso/expiração. Mas as credenciais (chave `.p8`, service account) viajam dentro do binário e
  podem ser extraídas, e um app modificado pode pular a verificação. É proteção razoável para apps pequenos,
  não garantia — use credenciais dedicadas e com permissão mínima, passe-as por `--dart-define` (nunca
  commitadas), ofusque o release, mantenha `enableLogging` desligado em release e considere migrar para 🅱
  quando houver servidor.
- **🅰**: o pacote (SDK `app_store_server_sdk` 1.2.10) **não valida a assinatura JWS** da resposta da Apple —
  confia no TLS da chamada. Não trate `result.raw` como prova assinada.
- **🅰**: compare `result.productId` com o produto comprado (`grantResultOf` faz isso) — senão um token de
  consumível barato destrava o premium.
- **🅱**: conceda acesso SOMENTE após o servidor confirmar. O servidor valida o `serverVerificationData` (JWS no
  StoreKit 2, purchase token no Android) com a App Store Server API / Google Play Developer API e guarda o
  vínculo compra ↔ usuária.
- Em ambos: quem decide "premium" é o `EntitlementService`, não um `bool` solto em `SharedPreferences`.

---

## Anti-patterns

- ❌ Emitir `PaywallSuccess` dentro de `buy()` — o resultado vem pelo stream
- ❌ Emitir `PaywallLoading` em `buy()`/`restore()` — esconde o paywall; use `PaywallLoaded(inProgress: true)`
- ❌ Tratar verificação como `bool` — sem `unavailable`, falha de rede vira "compra inválida" e a usuária perde o
  que pagou
- ❌ `completePurchase()` antes de verificar, ou deixar de completar `canceled`/`error`/`invalid` pendentes
- ❌ Esperar o resultado com `Future.delayed` fixo ou confiar só em `.timeout()` na chamada do plugin —
  `restorePurchases()` resolve antes do resultado chegar; o que demora é o stream
- ❌ Decidir `AppleEnvironment` por flavor ou chamar `initialize()` por transação — o default
  `productionWithSandboxFallback` cobre TestFlight e App Review, e cada `initialize()` descarta os clients
- ❌ Nomear o enum do app `VerificationResult` — colide com o do `verify_local_purchase` 2.x
- ❌ Instanciar `VerifyLocalPurchase()` ou injetá-lo — a fachada é estática; injete `PurchaseVerifier`
- ❌ Tratar `VerificationResult.state == notFound` como erro de rede (é `invalid`) ou uma
  `VerifyPurchaseException` como compra inválida (é `unavailable`)
- ❌ Reimplementar a regra de validade lendo `state`/`raw` — use `isValid`; `state` só decide o que fazer quando
  ele é `false`
- ❌ Apagar o registro de assinatura `expired`/`billingRetry` no `refresh()` — só `revoked`/`notFound` apagam
- ❌ Ouvir o `purchaseStream` sem `onError`, ou emitir depois de `close()` sem checar `isClosed`
- ❌ Textos no Cubit (`PaywallError('Erro ao...')`) — emita `PaywallErrorKind`/`PaywallNotice` e traduza na View
- ❌ Acessar `InAppPurchaseService`/`EntitlementService` da View — sempre via Cubit
- ❌ Ler `SharedPreferences` para saber se é premium — pergunte ao `EntitlementService`
- ❌ Verificar assinatura com `verifyPurchase` ou compra única com `verifySubscription` — ou usar os genéricos
  (que escolhem a loja por `Platform.isIOS`) no `refresh()` em vez de `...WithAppStore`/`...WithGooglePlay` pela
  plataforma do registro
- ❌ Ignorar que no Android uma assinatura com várias ofertas chega como vários `ProductDetails` com o mesmo `id`
- ❌ Em app com login, re-verificar o token lido do documento remoto (`users/{uid}`) ou copiá-lo para o cache
  local — o registro do aparelho é a única entrada de `refresh()`; o remoto é só espelho e grant manual
- ❌ Apagar as chaves de entitlement no logout — a compra é do aparelho, não da conta

---
