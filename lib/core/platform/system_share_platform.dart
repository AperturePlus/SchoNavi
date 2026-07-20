import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

enum SystemShareResult { launched, unavailable, failed }

abstract interface class SystemSharePlatform {
  bool get isSupported;

  Future<SystemShareResult> shareText(String text);
}

class MethodChannelSystemSharePlatform implements SystemSharePlatform {
  MethodChannelSystemSharePlatform({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel(_channelName);

  static const _channelName = 'top.schonavi.app/share';

  final MethodChannel _channel;

  @override
  bool get isSupported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  @override
  Future<SystemShareResult> shareText(String text) async {
    if (!isSupported) return SystemShareResult.unavailable;
    if (text.trim().isEmpty) return SystemShareResult.failed;
    try {
      final value = await _channel.invokeMethod<String>('shareText', {
        'text': text,
      });
      return switch (value) {
        'launched' => SystemShareResult.launched,
        'unavailable' => SystemShareResult.unavailable,
        _ => SystemShareResult.failed,
      };
    } catch (_) {
      return SystemShareResult.failed;
    }
  }
}
