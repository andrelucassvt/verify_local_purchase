# Setup — dependências, lojas, DI, credenciais, rota e inicialização

Índice: 1. pubspec · 2. Configuração das lojas · 3. DI · 4. Credenciais e `initialize()` do modo 🅰 · 5. Rota
e abertura do paywall · 6. `refresh()` na inicialização · 7. Migrando um app que usava `verify_local_purchase`
1.x

---

## 1. pubspec.yaml

```yaml
dependencies:
  in_app_purchase: ^3.3.0
  url_launcher: ^6.3.2            # links de Termos/Privacidade
  verify_local_purchase: ^2.0.0   # SOMENTE modo 🅰

dev_dependencies:
  bloc_test: ^10.0.0
```

Versões vigentes em setembro de 2026 — confira no pub.dev antes de fixar. `in_app_purchase` 3.3.x e
`verify_local_purchase` 2.x exigem Flutter 3.38+/Dart 3.10+; o plugin pede iOS 15+ e Android minSdk 21+. No iOS
o plugin usa StoreKit 2 por padrão.

`verify_local_purchase` 2.x é Dart puro (sem código nativo), suporta Android, iOS e macOS, e reexporta
`in_app_purchase` — mesmo assim mantenha `in_app_purchase` como dependência direta, porque o app o importa
(`depend_on_referenced_packages`). As duas precisam ser compatíveis (`verify_local_purchase` 2.0.0 pede
`in_app_purchase: ^3.2.3`).

---

## 2. Configuração das lojas

Sem isso `queryProductDetails` devolve tudo em `notFoundIDs` e o paywall cai em `productsNotFound`.

**App Store Connect**

- Contrato de apps pagos (Paid Apps Agreement) assinado em Agreements, Tax, and Banking.
- Produtos criados em In-App Purchases / Subscriptions com os IDs exatos da resposta 3, metadados
  preenchidos e status "Ready to Submit" ou aprovados.
- Capability **In-App Purchase** ativa no target Runner (Xcode → Signing & Capabilities).
- Conta **Sandbox Tester** em Users and Access → Sandbox, logada em Settings → App Store → Sandbox Account no
  aparelho de teste.
- TestFlight e App Review usam sandbox mesmo em build de produção. No modo 🅰 isso já está resolvido pelo
  default `AppleEnvironment.productionWithSandboxFallback` (ver §4) — não crie lógica por flavor.

**Google Play Console**

- Produtos criados em Monetize → Products (In-app products / Subscriptions), ativos, com os IDs exatos.
- Um build assinado com a mesma chave e `applicationId` enviado a uma faixa (interno/fechado) — a Billing
  Library só reconhece produtos de apps que a Play já viu.
- Testadores de licença em Setup → License testing, logados com essa conta no aparelho.
- O plugin adiciona a permissão `com.android.vending.BILLING` sozinho.

---

## 3. DI

`app_injector.dart`, seção de Services (o Cubit vai na seção de Cubits, sempre `registerFactory`):

```dart
// 2. Services
inject.registerLazySingleton<InAppPurchaseService>(InAppPurchaseServiceImpl.new);

// 🅰 — sem back-end (initLocalPurchaseVerification() já rodou no main, §4)
inject.registerLazySingleton<EntitlementService>(
  () => LocalEntitlementService(inject()), // PurchaseVerifierImpl é o default
);

// 🅱 — com back-end: ver backend.md (ServerEntitlementService após o Repository)

// 6. Cubits
inject.registerFactory<PaywallCubit>(() => PaywallCubit(inject(), inject()));
```

Registre UMA implementação de `EntitlementService`. Registrar as duas é o erro mais fácil de cometer ao copiar
os dois blocos.

`PurchaseVerifier` não precisa ir para o GetIt: ele só existe para o teste injetar um fake pelo construtor do
`LocalEntitlementService`. Se o projeto preferir tudo no DI, registre
`registerLazySingleton<PurchaseVerifier>(PurchaseVerifierImpl.new)` e passe `verifier: inject()`.

---

## 4. Credenciais e `initialize()` do modo 🅰

A fachada `VerifyLocalPurchase` é estática e guarda **uma** config por processo: inicialize uma única vez, no
`main()`, antes de qualquer verificação. Chamar `initialize()` de novo descarta a config anterior (e fecha os
clients HTTP) — não re-inicialize por transação, como os templates da 1.x faziam para trocar `useSandbox`.

`lib/common/services/in_app_purchase/local_purchase_verification.dart`

```dart
import 'package:flutter/foundation.dart';
import 'package:verify_local_purchase/verify_local_purchase.dart';

/// Credenciais via `--dart-define`, nunca literais no código. Loja sem
/// credencial fica `null`: a verificação dela lança `missingConfig`, que o
/// LocalEntitlementService trata como `unavailable` e reporta.
void initLocalPurchaseVerification() {
  const appleIssuerId = String.fromEnvironment('IAP_APPLE_ISSUER_ID');
  const appleKeyId = String.fromEnvironment('IAP_APPLE_KEY_ID');
  const applePrivateKey = String.fromEnvironment('IAP_APPLE_PRIVATE_KEY');
  const googleServiceAccount = String.fromEnvironment('IAP_GOOGLE_SERVICE_ACCOUNT_JSON');

  VerifyLocalPurchase.initialize(
    appleConfig: appleIssuerId.isEmpty || appleKeyId.isEmpty || applePrivateKey.isEmpty
        ? null
        : const AppleConfig(
            bundleId: String.fromEnvironment('IAP_APPLE_BUNDLE_ID'),
            issuerId: appleIssuerId,
            keyId: appleKeyId,
            privateKey: applePrivateKey,
            // environment: default productionWithSandboxFallback — NÃO mude por flavor.
          ),
    googlePlayConfig: googleServiceAccount.isEmpty
        ? null
        : const GooglePlayConfig(
            packageName: String.fromEnvironment('IAP_ANDROID_PACKAGE_NAME'),
            serviceAccountJson: googleServiceAccount,
          ),
    enableLogging: kDebugMode, // logs com token mascarado; desligado em release
  );
}
```

`main.dart`:

```dart
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  initLocalPurchaseVerification(); // 🅰 — antes do DI e do runApp
  await setupInjector();
  runApp(const App());
}
```

Sobre `AppleEnvironment`:

| Valor | Quando usar |
|---|---|
| `productionWithSandboxFallback` (default) | Sempre em app publicado. Produção primeiro; "transação não encontrada" (`4040001/4040005/4040010`) repete no sandbox — cobre TestFlight e App Review |
| `sandbox` | Só em build de desenvolvimento que nunca vai para a loja, se quiser pular a ida à produção |
| `production` | Evite: TestFlight e App Review passam a falhar como `notFound` → `invalid` |

`VerificationResult.isSandbox` diz de qual ambiente veio a resposta — útil para log ou para esconder
diagnóstico de sandbox em produção, nunca para negar acesso (App Review é sandbox).

Arquivo de secrets fora do controle de versão — `iap_secrets.json` (adicione ao `.gitignore`):

```json
{
  "IAP_APPLE_BUNDLE_ID": "com.example.app",
  "IAP_APPLE_ISSUER_ID": "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx",
  "IAP_APPLE_KEY_ID": "XXXXXXXXXX",
  "IAP_APPLE_PRIVATE_KEY": "-----BEGIN PRIVATE KEY-----\nMIGT...\n-----END PRIVATE KEY-----",
  "IAP_ANDROID_PACKAGE_NAME": "com.example.app",
  "IAP_GOOGLE_SERVICE_ACCOUNT_JSON": "{\"type\":\"service_account\",\"project_id\":\"...\"}"
}
```

```bash
flutter run --dart-define-from-file=iap_secrets.json
flutter build ipa --dart-define-from-file=iap_secrets.json
```

Como obter (mesmo passo a passo do README do pacote): Apple → App Store Connect → Users and Access → Keys →
chave com papel App Manager (baixe o `.p8` uma única vez; anote Issuer ID e Key ID). Google → Cloud Console →
Service Account com a Google Play Android Developer API habilitada → chave JSON → vincule em Play Console →
Setup → API access com permissão Manage orders (acrescente View financial data só se o app usar
`getRefundsWithGooglePlay`).

Use credenciais **dedicadas** a este fim (revogáveis sem afetar mais nada), rotacione-as e ofusque o release
(`flutter build ... --obfuscate --split-debug-info=build/symbols`).

Quebras de linha da chave `.p8` vão como `\n` dentro da string JSON. O JSON da service account vai inteiro,
escapado, em uma única string.

Credencial errada aparece como `VerifyPurchaseException` com `code` `invalidCredentials` (não deu para ler a
chave/JSON) ou `unauthorized` (a loja recusou, HTTP 401/403 — no Google, costuma ser a service account sem
permissão no Play Console ou o vínculo recém-feito, que pode levar horas para propagar).

Mesmo assim as credenciais ficam no binário. É o custo do modo 🅰 — está registrado na seção Segurança do
`SKILL.md`.

---

## 5. Rota e abertura do paywall

`app_routes.dart` / `app_router.dart`:

```dart
static const String paywall = '/paywall';

GoRoute(
  path: AppRoutes.paywall,
  builder: (context, state) => const PaywallView(),
),
```

Quem abre o paywall recebe o resultado do `pop(true)` da resposta 5 (padrão):

```dart
final purchased = await context.push<bool>(AppRoutes.paywall);
if (purchased == true && context.mounted) {
  // recarregue o estado premium da tela atual
}
```

---

## 6. `refresh()` na inicialização

No `SplashCubit` (ou equivalente), antes de decidir a rota inicial:

```dart
Future<void> start() async {
  // Não bloqueie a abertura por causa da rede: 5s é teto, não meta.
  await _entitlements
      .refresh()
      .timeout(const Duration(seconds: 5), onTimeout: () {});
  // ... decide a rota inicial
}
```

Sem isso uma assinatura cancelada continua "ativa" no dispositivo até a usuária abrir o paywall de novo.
Injete `EntitlementService` no `SplashCubit` via construtor, como qualquer Service.

---

## 7. Migrando um app que usava `verify_local_purchase` 1.x

Se o projeto já tem a integração gerada pela versão anterior desta skill:

| 1.x | 2.x |
|---|---|
| `enum VerificationResult { valid, invalid, unavailable }` no app | Renomeie para `GrantResult` — o pacote agora exporta `VerificationResult` |
| `VerifyLocalPurchase()` instanciado / injetado | Métodos estáticos; injete `PurchaseVerifier` (service.md §5.1) |
| `initialize` por transação com `useSandbox` | `initialize` uma vez no `main()`; `AppleConfig.environment` default resolve o sandbox. Apague `_isSandboxTransaction`/`_configureVerifier` e `LocalVerificationCredentials` |
| `Future<bool>` + `catch` → `unavailable` | `VerificationResult`; mapeie com `grantResultOf` (service.md §5.3) |
| `getSubscriptionToken` devolvia `''` / lançava erro genérico | Lança `VerifyPurchaseException(invalidToken)` |
| Google `PENDING` contava como assinatura válida | Não conta mais (`state: pending`, `isValid: false`) |
| Apple em grace period (status 4) negava acesso | Concede (`state: gracePeriod`, `isValid: true`) |
| `RefundPlatform` | `StorePlatform` |

Registros antigos em `entitlement_<productId>` (`{"token","source","sandbox"}`) continuam legíveis: sem
`isValid`, `hasAccess` devolve `false` até o primeiro `refresh()` bem-sucedido regravar o status. Se isso
bloquear assinantes offline no primeiro boot após o update, trate a ausência de `isValid` como `true` só nessa
primeira leitura.
