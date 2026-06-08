import 'package:flutter_test/flutter_test.dart';
import 'package:verify_local_purchase/models/verify_purchase_config.dart';
import 'package:verify_local_purchase/service/verify_purchase_service.dart';

void main() {
  group('getRefundsWithAppStore', () {
    test('throws Exception when appleConfig is null', () async {
      VerifyPurchaseService.initialize(
        googlePlayConfig: GooglePlayConfig(
          packageName: 'com.example.app',
          serviceAccountJson: '{}',
        ),
      );

      final service = VerifyPurchaseService();

      expect(
        () => service.getRefundsWithAppStore('orig_tx_001'),
        throwsA(
          isA<Exception>().having(
            (e) => e.toString(),
            'message',
            contains('Apple configuration not provided'),
          ),
        ),
      );
    });
  });

  group('getRefundsWithGooglePlay', () {
    test('throws Exception when googlePlayConfig is null', () async {
      VerifyPurchaseService.initialize(
        appleConfig: AppleConfig(
          bundleId: 'com.example.app',
          issuerId: 'issuer',
          keyId: 'keyId',
          privateKey: 'privateKey',
        ),
      );

      final service = VerifyPurchaseService();

      expect(
        () => service.getRefundsWithGooglePlay(),
        throwsA(
          isA<Exception>().having(
            (e) => e.toString(),
            'message',
            contains('Google Play configuration not provided'),
          ),
        ),
      );
    });
  });
}
