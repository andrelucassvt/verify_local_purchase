import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'verify_local_purchase_platform_interface.dart';

/// An implementation of [VerifyLocalPurchasePlatform] that uses method channels.
class MethodChannelVerifyLocalPurchase extends VerifyLocalPurchasePlatform {
  /// The method channel used to interact with the native platform.
  @visibleForTesting
  final methodChannel = const MethodChannel('verify_local_purchase');

  @override
  Future<String?> getPlatformVersion() async {
    final version = await methodChannel.invokeMethod<String>(
      'getPlatformVersion',
    );
    return version;
  }
}
