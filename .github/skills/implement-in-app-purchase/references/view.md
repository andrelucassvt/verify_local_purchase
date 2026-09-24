# View — PaywallView e l10n

Índice: 1. Requisitos · 2. PaywallView · 3. Chaves de l10n (ARB) · 4. Exigências da Apple no paywall

---

## 1. Requisitos

- `StatefulWidget`; Cubit via `AppInjector.inject.get<PaywallCubit>()`; `loadProducts()` no `initState()`;
  `close()` no `dispose()`.
- `BlocProvider.value` + `BlocConsumer`. Side effects (navegação pós-sucesso, SnackBar de `notice`) SEMPRE no
  `listener`; o `builder` só renderiza.
- `builder` com `switch` exaustivo sobre a `sealed class` — o compilador cobra quando um State novo aparecer.
- `SafeArea` no conteúdo principal.
- Zero strings hardcoded: tudo via `context.l10n`. O Cubit entrega enums; a View traduz.
- Botão "Restaurar compras" sempre presente. Links de Termos e Privacidade quando houver assinatura.
- Compra/restauração em andamento: `AbsorbPointer` + overlay, paywall continua visível.

---

## 2. PaywallView

`lib/presentation/paywall/view/paywall_view.dart`

```dart
import 'package:base_app/common/services/in_app_purchase/purchase_ids.dart';
import 'package:base_app/config/inject/app_injector.dart';
import 'package:base_app/l10n/l10n.dart';
import 'package:base_app/presentation/paywall/view_model/paywall_cubit.dart';
import 'package:base_app/presentation/paywall/view_model/paywall_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

class PaywallView extends StatefulWidget {
  const PaywallView({super.key});

  @override
  State<PaywallView> createState() => _PaywallViewState();
}

class _PaywallViewState extends State<PaywallView> {
  final _cubit = AppInjector.inject.get<PaywallCubit>();

  // Resposta 6 do Passo 1. Obrigatórios quando há assinatura (Apple 3.1.2(c)).
  static final _termsUrl = Uri.parse('https://example.com/terms');
  static final _privacyUrl = Uri.parse('https://example.com/privacy');

  @override
  void initState() {
    super.initState();
    _cubit.loadProducts();
  }

  @override
  void dispose() {
    _cubit.close();
    super.dispose();
  }

  void _showNotice(BuildContext context, PaywallNotice notice) {
    final l10n = context.l10n;
    final text = switch (notice) {
      PaywallNotice.purchaseFailed => l10n.paywallNoticePurchaseFailed,
      PaywallNotice.verificationFailed => l10n.paywallNoticeVerificationFailed,
      PaywallNotice.verificationUnavailable => l10n.paywallNoticeVerificationUnavailable,
      PaywallNotice.nothingToRestore => l10n.paywallNoticeNothingToRestore,
      PaywallNotice.restoreFailed => l10n.paywallNoticeRestoreFailed,
      PaywallNotice.storeTimeout => l10n.paywallNoticeStoreTimeout,
      PaywallNotice.pendingApproval => l10n.paywallNoticePendingApproval,
    };
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final hasSubscriptions = PurchaseIds.subscriptions.isNotEmpty;

    return BlocProvider.value(
      value: _cubit,
      child: Scaffold(
        appBar: AppBar(title: Text(l10n.paywallTitle)),
        body: SafeArea(
          top: false,
          child: BlocConsumer<PaywallCubit, PaywallState>(
            listener: (context, state) {
              if (state is PaywallSuccess) {
                // Resposta 5 do Passo 1. Padrão: fechar devolvendo `true` a quem
                // abriu com `await context.push<bool>(AppRoutes.paywall)`.
                // Alternativas: context.go(AppRoutes.home) ou nenhuma navegação
                // (permanecer — o builder renderiza PaywallSuccess).
                context.pop(true);
                return;
              }
              if (state is PaywallLoaded && state.notice != null) {
                _showNotice(context, state.notice!);
              }
            },
            builder: (context, state) => switch (state) {
              PaywallInitial() || PaywallLoading() =>
                const Center(child: CircularProgressIndicator()),
              PaywallError(:final kind) => Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          switch (kind) {
                            PaywallErrorKind.storeUnavailable =>
                              l10n.paywallErrorStoreUnavailable,
                            PaywallErrorKind.productsNotFound =>
                              l10n.paywallErrorProductsNotFound,
                            PaywallErrorKind.loadFailed => l10n.paywallErrorLoadFailed,
                          },
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 16),
                        FilledButton(
                          onPressed: _cubit.loadProducts,
                          child: Text(l10n.paywallRetryButton),
                        ),
                      ],
                    ),
                  ),
                ),
              // Só aparece se a resposta 5 for "permanecer na tela"; nos outros
              // casos o listener já navegou.
              PaywallSuccess() => Center(child: Text(l10n.paywallSuccessMessage)),
              PaywallLoaded(:final products, :final inProgress) => Stack(
                  children: [
                    AbsorbPointer(
                      absorbing: inProgress,
                      child: ListView(
                        padding: const EdgeInsets.all(16),
                        children: [
                          for (final product in products)
                            Card(
                              child: ListTile(
                                title: Text(product.title),
                                subtitle: Text(product.description),
                                trailing: FilledButton(
                                  onPressed: () => _cubit.buy(product),
                                  child: Text(
                                    PurchaseIds.isSubscription(product.id)
                                        ? l10n.paywallSubscribeButton(product.price)
                                        : l10n.paywallBuyButton(product.price),
                                  ),
                                ),
                              ),
                            ),
                          if (hasSubscriptions)
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              child: Text(
                                l10n.paywallAutoRenewNotice,
                                style: theme.textTheme.bodySmall,
                                textAlign: TextAlign.center,
                              ),
                            ),
                          TextButton(
                            onPressed: _cubit.restore,
                            child: Text(l10n.paywallRestoreButton),
                          ),
                          if (hasSubscriptions)
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                TextButton(
                                  onPressed: () => launchUrl(
                                    _termsUrl,
                                    mode: LaunchMode.externalApplication,
                                  ),
                                  child: Text(l10n.paywallTermsOfUse),
                                ),
                                Text('·', style: theme.textTheme.bodySmall),
                                TextButton(
                                  onPressed: () => launchUrl(
                                    _privacyUrl,
                                    mode: LaunchMode.externalApplication,
                                  ),
                                  child: Text(l10n.paywallPrivacyPolicy),
                                ),
                              ],
                            ),
                        ],
                      ),
                    ),
                    if (inProgress)
                      const Positioned.fill(
                        child: ColoredBox(
                          color: Colors.black38,
                          child: Center(child: CircularProgressIndicator()),
                        ),
                      ),
                  ],
                ),
            },
          ),
        ),
      ),
    );
  }
}
```

Se o bloco do produto crescer além de ~45 linhas ou ganhar estado próprio, extraia para
`presentation/paywall/content/paywall_product_tile.dart` (regra de composição de `flutter-expert`).

---

## 3. Chaves de l10n (ARB)

Adicione em `app_en.arb` e `app_pt.arb` e rode `flutter gen-l10n`. `product.price` já vem formatado pela loja
na moeda da usuária — nunca formate preço na mão.

```json
{
  "paywallTitle": "Premium",
  "paywallBuyButton": "Buy for {price}",
  "@paywallBuyButton": { "placeholders": { "price": { "type": "String" } } },
  "paywallSubscribeButton": "Subscribe for {price}",
  "@paywallSubscribeButton": { "placeholders": { "price": { "type": "String" } } },
  "paywallAutoRenewNotice": "Subscriptions renew automatically until canceled in your store account settings.",
  "paywallRestoreButton": "Restore purchases",
  "paywallTermsOfUse": "Terms of Use",
  "paywallPrivacyPolicy": "Privacy Policy",
  "paywallRetryButton": "Try again",
  "paywallSuccessMessage": "Purchase completed. Enjoy!",
  "paywallErrorStoreUnavailable": "The store is not available on this device.",
  "paywallErrorProductsNotFound": "No products are available right now.",
  "paywallErrorLoadFailed": "We couldn't load the products. Check your connection and try again.",
  "paywallNoticePurchaseFailed": "The purchase could not be completed.",
  "paywallNoticeVerificationFailed": "This purchase could not be verified.",
  "paywallNoticeVerificationUnavailable": "We couldn't verify your purchase right now. It will be unlocked automatically once you're back online.",
  "paywallNoticeNothingToRestore": "No previous purchases were found for this account.",
  "paywallNoticeRestoreFailed": "Purchases could not be restored. Try again.",
  "paywallNoticeStoreTimeout": "The store took too long to respond. If the purchase went through, it will be unlocked automatically.",
  "paywallNoticePendingApproval": "Your purchase is awaiting approval. You'll get access as soon as it's confirmed."
}
```

```json
{
  "paywallTitle": "Premium",
  "paywallBuyButton": "Comprar por {price}",
  "@paywallBuyButton": { "placeholders": { "price": { "type": "String" } } },
  "paywallSubscribeButton": "Assinar por {price}",
  "@paywallSubscribeButton": { "placeholders": { "price": { "type": "String" } } },
  "paywallAutoRenewNotice": "As assinaturas renovam automaticamente até serem canceladas nas configurações da sua conta na loja.",
  "paywallRestoreButton": "Restaurar compras",
  "paywallTermsOfUse": "Termos de Uso",
  "paywallPrivacyPolicy": "Política de Privacidade",
  "paywallRetryButton": "Tentar novamente",
  "paywallSuccessMessage": "Compra concluída. Aproveite!",
  "paywallErrorStoreUnavailable": "A loja não está disponível neste dispositivo.",
  "paywallErrorProductsNotFound": "Nenhum produto disponível no momento.",
  "paywallErrorLoadFailed": "Não foi possível carregar os produtos. Verifique sua conexão e tente novamente.",
  "paywallNoticePurchaseFailed": "Não foi possível concluir a compra.",
  "paywallNoticeVerificationFailed": "Esta compra não pôde ser verificada.",
  "paywallNoticeVerificationUnavailable": "Não conseguimos verificar sua compra agora. Ela será liberada automaticamente quando a conexão voltar.",
  "paywallNoticeNothingToRestore": "Nenhuma compra anterior foi encontrada nesta conta.",
  "paywallNoticeRestoreFailed": "Não foi possível restaurar as compras. Tente novamente.",
  "paywallNoticeStoreTimeout": "A loja demorou para responder. Se a compra foi concluída, ela será liberada automaticamente.",
  "paywallNoticePendingApproval": "Sua compra está aguardando aprovação. O acesso será liberado assim que for confirmada."
}
```

---

## 4. Exigências da Apple no paywall

Para assinaturas (App Store Review Guideline 3.1.2 e Schedule 2 §3.8(b)), o paywall precisa deixar claro:

- **Nome e duração** do plano — no template vêm de `product.title`/`product.description`, então cadastre-os
  na loja com o período explícito ("Premium Mensal"). Para exibir o período programaticamente, leia
  `AppStoreProduct2Details`/`GooglePlayProductDetails`.
- **Preço** formatado pela loja (`product.price`) e o aviso de **renovação automática**
  (`paywallAutoRenewNotice`).
- **Termos de Uso (EULA)** e **Política de Privacidade** como links funcionais.
- **Restaurar compras** acessível sem login.

Compras únicas não exigem os links, mas exigem o botão de restaurar para não-consumíveis.
