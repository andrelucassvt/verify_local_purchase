## 2.0.3

* fix: App Store subscriptions and purchases with an introductory offer or free trial failed with `VerifyPurchaseException(invalidResponse)` (`type 'int' is not a subtype of type 'String?'`). Transaction and renewal payloads are now decoded leniently instead of through the `app_store_server_sdk` models, whose `offerType` / `gracePeriodExpiresDate` types don't match Apple's responses. `willAutoRenew` is also filled in during billing grace period.

## 2.0.1

* chore: bumps `in_app_purchase` to `^3.3.1` (pulls `in_app_purchase_android` `^0.5.0` / Google Play Billing Library 8.0.0). Apps calling `queryPurchaseHistory` on Android must migrate to `queryPurchases`.

## 2.0.0

**Breaking changes** — see "Migrating from 1.x" in the README.

* feat!: verification methods return `VerificationResult` (`isValid`, `state`, `productId`, `expiresAt`, `willAutoRenew`, `isSandbox`, `raw`) instead of `bool`
* feat!: `VerifyLocalPurchase` methods are now static (`VerifyLocalPurchase.verifyPurchase(...)`)
* feat!: errors are thrown as `VerifyPurchaseException` with a `VerifyPurchaseErrorCode`
* feat!: `AppleConfig.useSandbox` replaced by `AppleConfig.environment`; default `productionWithSandboxFallback` retries in sandbox when production returns "transaction not found" (App Review / TestFlight)
* feat!: `RefundPlatform` renamed to `StorePlatform`; `VerifyPurchaseService` is no longer exported
* feat!: removed the unused native platform channel — now a pure Dart package (Android, iOS, macOS)
* feat: `verifyPurchaseDetails` / `verifySubscriptionDetails` take a `PurchaseDetails` directly
* feat: `initialize(enableLogging:)` — logs are off by default and tokens are masked
* feat: `VerifyLocalPurchase.dispose()`
* fix: Apple subscriptions in billing grace period (status 4) are valid; all subscription groups are checked, preferring the entry matching the `originalTransactionId`
* fix: Google `SUBSCRIPTION_STATE_PENDING` is no longer valid (reverts 1.0.6); `IN_GRACE_PERIOD` is valid; `CANCELED` stays valid until `expiryTime`
* fix: macOS was verified against Google Play
* fix: `getSubscriptionToken` / `getOneTimePurchaseToken` throw `invalidToken` instead of crashing or returning `''`
* fix: unknown Google tokens (HTTP 404/410) return `state: notFound` instead of throwing
* perf: Google OAuth client and App Store clients are reused between calls
* chore: `flutter >=3.38.0`, CI workflow, unit tests for all store states

## 1.1.0

* feat: add `getRefundsWithAppStore()` — lists refunds for a single customer via App Store Server API (`getRefundHistory`)
* feat: add `getRefundsWithGooglePlay()` — lists all voided purchases for the app via Google Play Developer API (`voidedpurchases`) with automatic pagination
* feat: add `RefundEntry` model (+ `RefundPlatform` enum) exported in public API

## 1.0.8

* feat: export `in_app_purchase` package for convenience

## 1.0.7

* docs: remove dotenv example from README

## 1.0.6

* fix: consider `SUBSCRIPTION_STATE_PENDING` as valid active state when verifying Google Play subscriptions

## 1.0.5

* docs: add Google Play Android Developer API enablement step in Google Cloud Console setup

## 1.0.4
  * purchase_token_utils.dart

## 1.0.3
  * new doc
## 1.0.2

* Added individual platform-specific methods to `VerifyLocalPurchase`:
  * `verifyPurchaseWithAppStore()`
  * `verifyPurchaseWithGooglePlay()`
  * `verifySubscriptionWithAppStore()`
  * `verifySubscriptionWithGooglePlay()`

## 1.0.0

* Initial release
* Support for verifying in-app purchases on iOS and Android
* Support for verifying subscriptions on iOS and Android
* Easy initialization with `VerifyLocalPurchase.initialize()`
* Apple App Store integration using App Store Server API
* Google Play Store integration using Google Play Developer API
* Local verification without backend server
* Support for both sandbox and production environments
