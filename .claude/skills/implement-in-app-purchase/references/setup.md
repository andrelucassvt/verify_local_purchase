# Setup — dependências, lojas, DI, credenciais, rota e inicialização

Índice: 1. pubspec · 2. Configuração das lojas · 3. DI · 4. Credenciais do modo 🅰 · 5. Rota e abertura do
paywall · 6. `refresh()` na inicialização

---

## 1. pubspec.yaml

```yaml
dependencies:
  in_app_purchase: ^3.3.0
  url_launcher: ^6.3.2            # links de Termos/Privacidade
  verify_local_purchase: ^1.1.0   # SOMENTE modo 🅰

dev_dependencies:
  bloc_test: ^10.0.0
```

Versões vigentes em setembro de 2026 — confira no pub.dev antes de fixar. `in_app_purchase` 3.3.x exige
Flutter 3.38+/Dart 3.10+, iOS 15+ e Android minSdk 21+. No iOS o plugin usa StoreKit 2 por padrão.
`verify_local_purchase` já depende de `in_app_purchase`, então as versões precisam ser compatíveis.

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
- TestFlight e App Review usam sandbox mesmo em build de produção — por isso o modo 🅰 decide `useSandbox` por
  transação (ver `service.md`).

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

// 🅰 — sem back-end
inject.registerLazySingleton<LocalVerificationCredentials>(
  () => const LocalVerificationCredentials(
    appleBundleId: String.fromEnvironment('IAP_APPLE_BUNDLE_ID'),
    appleIssuerId: String.fromEnvironment('IAP_APPLE_ISSUER_ID'),
    appleKeyId: String.fromEnvironment('IAP_APPLE_KEY_ID'),
    applePrivateKey: String.fromEnvironment('IAP_APPLE_PRIVATE_KEY'),
    androidPackageName: String.fromEnvironment('IAP_ANDROID_PACKAGE_NAME'),
    googleServiceAccountJson: String.fromEnvironment('IAP_GOOGLE_SERVICE_ACCOUNT_JSON'),
  ),
);
inject.registerLazySingleton<EntitlementService>(
  () => LocalEntitlementService(inject(), inject()),
);

// 🅱 — com back-end: ver backend.md (ServerEntitlementService após o Repository)

// 6. Cubits
inject.registerFactory<PaywallCubit>(() => PaywallCubit(inject(), inject()));
```

Registre UMA implementação de `EntitlementService`. Registrar as duas é o erro mais fácil de cometer ao copiar
os dois blocos.

---

## 4. Credenciais do modo 🅰

As credenciais entram por `--dart-define`, lidas com `String.fromEnvironment` em contexto `const`. Crie um
arquivo fora do controle de versão:

`iap_secrets.json` (adicione ao `.gitignore`):

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

Como obter: Apple → App Store Connect → Users and Access → Keys → chave com papel App Manager (baixe o `.p8`
uma única vez; anote Issuer ID e Key ID). Google → Cloud Console → Service Account com a Google Play Android
Developer API habilitada → chave JSON → vincule em Play Console → Setup → API access com permissões View
financial data e Manage orders.

Quebras de linha da chave `.p8` vão como `\n` dentro da string JSON. O JSON da service account vai inteiro,
escapado, em uma única string.

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
