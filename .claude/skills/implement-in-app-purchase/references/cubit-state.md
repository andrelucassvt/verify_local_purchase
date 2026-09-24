# Cubit e State — PaywallState e PaywallCubit

Índice: 1. PaywallState · 2. PaywallCubit · 3. Por que cada peça existe

O Cubit é idêntico nos modos 🅰 e 🅱: ele só conhece `InAppPurchaseService` e `EntitlementService`. Renomeie
`Paywall` conforme a resposta 4 do Passo 1.

---

## 1. PaywallState

`lib/presentation/paywall/view_model/paywall_state.dart`

```dart
import 'package:flutter/foundation.dart';
import 'package:in_app_purchase/in_app_purchase.dart';

@immutable
sealed class PaywallState {
  const PaywallState();

  @override
  String toString();
}

final class PaywallInitial extends PaywallState {
  const PaywallInitial();

  @override
  String toString() => 'PaywallInitial';
}

/// SOMENTE para o carregamento inicial de produtos. Compra e restauração
/// nunca emitem este estado — usam PaywallLoaded(inProgress: true).
final class PaywallLoading extends PaywallState {
  const PaywallLoading();

  @override
  String toString() => 'PaywallLoading';
}

final class PaywallLoaded extends PaywallState {
  const PaywallLoaded(this.products, {this.inProgress = false, this.notice});

  /// Produtos e assinaturas juntos, na ordem devolvida pela loja.
  final List<ProductDetails> products;

  /// true enquanto uma compra/restauração está em andamento: botões
  /// desabilitados e overlay de progresso, mas o paywall continua visível.
  final bool inProgress;

  /// Aviso one-shot para a View mostrar em SnackBar. Não é um estado de erro:
  /// os produtos continuam na tela e a usuária pode tentar de novo.
  final PaywallNotice? notice;

  @override
  String toString() =>
      'PaywallLoaded(products: ${products.map((p) => p.id).toList()}, '
      'inProgress: $inProgress, notice: $notice)';
}

final class PaywallSuccess extends PaywallState {
  const PaywallSuccess(this.productId);
  final String productId;

  @override
  String toString() => 'PaywallSuccess(productId: $productId)';
}

/// SOMENTE para falha ao carregar produtos. A View mostra a causa e um botão
/// "Tentar novamente" → loadProducts(). Falhas durante compra/restauração
/// voltam para PaywallLoaded com notice.
final class PaywallError extends PaywallState {
  const PaywallError(this.kind, {this.error});
  final PaywallErrorKind kind;
  final Object? error;

  @override
  String toString() => 'PaywallError(kind: $kind, error: $error)';
}

enum PaywallErrorKind { storeUnavailable, productsNotFound, loadFailed }

enum PaywallNotice {
  purchaseFailed,
  verificationFailed,
  verificationUnavailable,
  nothingToRestore,
  restoreFailed,
  storeTimeout,
  pendingApproval,
}
```

---

## 2. PaywallCubit

`lib/presentation/paywall/view_model/paywall_cubit.dart`

```dart
import 'dart:async';

import 'package:base_app/common/services/in_app_purchase/entitlement_service.dart';
import 'package:base_app/common/services/in_app_purchase/in_app_purchase_service.dart';
import 'package:base_app/presentation/paywall/view_model/paywall_state.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:in_app_purchase/in_app_purchase.dart';

class PaywallCubit extends Cubit<PaywallState> {
  PaywallCubit(
    this._iap,
    this._entitlements, {
    Duration buyTimeout = const Duration(minutes: 2),
    Duration restoreTimeout = const Duration(seconds: 45),
    Duration verifyTimeout = const Duration(seconds: 30),
  })  : _buyTimeout = buyTimeout,
        _restoreTimeout = restoreTimeout,
        _verifyTimeout = verifyTimeout,
        super(const PaywallInitial()) {
    _subscription = _iap.purchaseStream.listen(
      _onPurchaseUpdates,
      // Sem onError, um erro do stream encerra a subscription em silêncio e a
      // tela espera um evento que nunca chega.
      onError: _onStreamError,
    );
  }

  final InAppPurchaseService _iap;
  final EntitlementService _entitlements;

  // Nenhuma chamada do plugin tem timeout nativo. A compra é longa porque a
  // folha da loja pode ficar aberta (senha, 2FA); o restore é curto porque
  // "nada a restaurar" já chega como lista vazia — aqui o watchdog é só rede
  // de segurança. Injetáveis para os testes usarem durações curtas.
  final Duration _buyTimeout;
  final Duration _restoreTimeout;
  final Duration _verifyTimeout;

  StreamSubscription<List<PurchaseDetails>>? _subscription;
  Timer? _watchdog;
  List<ProductDetails> _products = const [];
  bool _restoring = false;

  bool get _inProgress => switch (state) {
        PaywallLoaded(:final inProgress) => inProgress,
        _ => false,
      };

  Future<void> loadProducts() async {
    emit(const PaywallLoading());
    try {
      _products = await _iap.loadProducts();
      if (isClosed) return;
      emit(PaywallLoaded(_products));
    } on ProductLoadException catch (e) {
      if (isClosed) return;
      emit(PaywallError(_kindOf(e), error: e));
    } catch (e) {
      if (isClosed) return;
      emit(PaywallError(PaywallErrorKind.loadFailed, error: e));
    }
  }

  Future<void> buy(ProductDetails product) async {
    // Duas compras em paralelo: o StoreKit 2 lança storekit_duplicate_product_object.
    if (_inProgress) return;
    _lock(_buyTimeout);
    try {
      await _iap.buy(product);
      // NÃO emita sucesso aqui — o resultado chega pelo purchaseStream.
    } catch (_) {
      _unlock(notice: PaywallNotice.purchaseFailed);
    }
  }

  Future<void> restore() async {
    if (_inProgress) return;
    _restoring = true;
    _lock(_restoreTimeout);
    try {
      await _iap.restorePurchases();
      // O resultado chega pelo purchaseStream: as compras com status `restored`,
      // ou uma lista VAZIA quando não há nada (Android, StoreKit 1 e 2).
    } catch (_) {
      _restoring = false;
      _unlock(notice: PaywallNotice.restoreFailed);
    }
  }

  Future<void> _onPurchaseUpdates(List<PurchaseDetails> purchases) async {
    if (purchases.isEmpty) {
      if (_restoring) {
        _restoring = false;
        _unlock(notice: PaywallNotice.nothingToRestore);
      }
      return;
    }

    var granted = false;
    // Durante um restore, um item que falhou não deve virar "nada a restaurar":
    // a usuária precisa saber que existia uma compra e por que ela não valeu.
    PaywallNotice? restoreFailure;

    for (final purchase in purchases) {
      switch (purchase.status) {
        case PurchaseStatus.pending:
          // Ask to Buy, aprovação parental ou pagamento pendente: pode levar
          // dias. Libere a tela; quando resolver, `purchased` chega pelo stream
          // (mesmo em outra sessão do app).
          _unlock(notice: PaywallNotice.pendingApproval);

        case PurchaseStatus.canceled:
          await _completeIfPending(purchase);
          _unlock(); // desistir não é erro

        case PurchaseStatus.error:
          await _completeIfPending(purchase); // senão o iOS reentrega a cada abertura
          _unlock(notice: PaywallNotice.purchaseFailed);

        case PurchaseStatus.purchased:
        case PurchaseStatus.restored:
          switch (await _verify(purchase)) {
            case GrantResult.valid:
              await _completeSafely(purchase);
              if (isClosed) return;
              granted = true;
              _watchdog?.cancel();
              if (state is! PaywallSuccess) emit(PaywallSuccess(purchase.productID));

            case GrantResult.invalid:
              await _completeIfPending(purchase); // reembolsada/expirada: pare a reentrega
              if (_restoring) {
                restoreFailure ??= PaywallNotice.verificationFailed;
              } else {
                _unlock(notice: PaywallNotice.verificationFailed);
              }

            case GrantResult.unavailable:
              // NÃO complete: a loja reentrega e a verificação roda de novo.
              if (_restoring) {
                restoreFailure = PaywallNotice.verificationUnavailable;
              } else {
                _unlock(notice: PaywallNotice.verificationUnavailable);
              }
          }
      }
      if (isClosed) return;
    }

    if (_restoring) {
      _restoring = false;
      // `unavailable` tem prioridade sobre `invalid`: vale a pena pedir para
      // tentar de novo com rede antes de dizer que a compra não vale.
      if (!granted) {
        _unlock(notice: restoreFailure ?? PaywallNotice.nothingToRestore);
      }
    }
  }

  void _onStreamError(Object error) {
    _restoring = false;
    _unlock(notice: PaywallNotice.purchaseFailed);
  }

  Future<GrantResult> _verify(PurchaseDetails purchase) async {
    try {
      return await _entitlements.verifyAndGrant(purchase).timeout(_verifyTimeout);
    } catch (_) {
      return GrantResult.unavailable; // inclui TimeoutException
    }
  }

  Future<void> _completeIfPending(PurchaseDetails purchase) async {
    if (purchase.pendingCompletePurchase) await _completeSafely(purchase);
  }

  /// Falha ao completar não pode derrubar o handler do stream: a loja reentrega
  /// a transação e a verificação (idempotente) roda de novo.
  Future<void> _completeSafely(PurchaseDetails purchase) async {
    try {
      await _iap.completePurchase(purchase);
    } catch (_) {
      // Intencional: ver docstring.
    }
  }

  /// Desabilita as ações do paywall SEM esconder os produtos e arma o watchdog:
  /// a garantia de que nenhum caminho deixa a tela travada.
  void _lock(Duration timeout) {
    _watchdog?.cancel();
    _watchdog = Timer(timeout, () {
      final wasRestoring = _restoring;
      _restoring = false;
      _unlock(
        notice: wasRestoring
            ? PaywallNotice.nothingToRestore
            : PaywallNotice.storeTimeout,
      );
    });
    _emitLoaded(inProgress: true);
  }

  void _unlock({PaywallNotice? notice}) {
    _watchdog?.cancel();
    _emitLoaded(notice: notice);
  }

  void _emitLoaded({bool inProgress = false, PaywallNotice? notice}) {
    if (isClosed) return;
    // Evento do stream antes de loadProducts terminar (ex.: transação pendente
    // entregue na abertura do app): não sobrescreva Loading/Error com lista vazia.
    if (_products.isEmpty) return;
    // Depois do sucesso a tela é da View (navegou ou mostra o desbloqueio).
    if (state is PaywallSuccess) return;
    emit(PaywallLoaded(_products, inProgress: inProgress, notice: notice));
  }

  PaywallErrorKind _kindOf(ProductLoadException e) => switch (e) {
        StoreUnavailableException() => PaywallErrorKind.storeUnavailable,
        ProductsNotFoundException() => PaywallErrorKind.productsNotFound,
        ProductQueryException() => PaywallErrorKind.loadFailed,
      };

  @override
  Future<void> close() async {
    _watchdog?.cancel();
    await _subscription?.cancel();
    return super.close();
  }
}
```

---

## 3. Por que cada peça existe

| Peça | Sem ela |
|---|---|
| `inProgress` em vez de `PaywallLoading` | O paywall some atrás de um spinner enquanto a folha da loja está aberta; se a loja não responder, a usuária fica sem tela |
| `notice` dentro de `PaywallLoaded` | Um estado separado (`RestoreNotFound`, `PurchaseError`) substitui o conteúdo e a View não tem produtos para renderizar — tela em branco |
| Lista vazia → `nothingToRestore` | O restore sem compras é o caso mais comum ("usuária que nunca assinou") e ficaria esperando o watchdog |
| Watchdog | `pending` (Ask to Buy) e eventos perdidos não geram estado final; a tela travaria para sempre |
| `onError` no stream | Um erro do plugin mata a subscription em silêncio |
| `isClosed` após cada `await` | `emit` depois de `close()` lança `StateError` quando a View foi descartada com uma verificação em voo |
| `_completeIfPending` em `canceled`/`error`/`invalid` | iOS reentrega a transação a cada abertura; StoreKit 2 recusa nova compra do mesmo produto |
| `state is! PaywallSuccess` antes de emitir | Restore com duas compras válidas emitiria dois `Success` e o `listener` faria `pop` duas vezes |
| `restoreFailure` no restore | Uma compra restaurada que falhou na verificação viraria "nada a restaurar", escondendo a causa real |
| `_products.isEmpty` em `_emitLoaded` | Uma transação pendente entregue na abertura do app sobrescreveria o `Loading` com lista vazia |
| Timeouts injetáveis | Os testes do watchdog levariam minutos |
