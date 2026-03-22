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
