import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scho_navi/core/platform/system_share_platform.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('test.schonavi.app/share');

  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
  });

  tearDown(() async {
    debugDefaultTargetPlatformOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('shareText sends the expected method and text payload', () async {
    MethodCall? received;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          received = call;
          return 'launched';
        });
    final platform = MethodChannelSystemSharePlatform(channel: channel);

    final result = await platform.shareText('推荐内容');

    expect(result, SystemShareResult.launched);
    expect(received?.method, 'shareText');
    expect(received?.arguments, {'text': '推荐内容'});
  });

  test('shareText maps unavailable and failed native outcomes', () async {
    final platform = MethodChannelSystemSharePlatform(channel: channel);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async => 'unavailable');
    expect(await platform.shareText('内容'), SystemShareResult.unavailable);

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async => 'failed');
    expect(await platform.shareText('内容'), SystemShareResult.failed);
  });

  test('unsupported platforms do not invoke the MethodChannel', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    var invoked = false;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async {
          invoked = true;
          return 'launched';
        });
    final platform = MethodChannelSystemSharePlatform(channel: channel);

    expect(await platform.shareText('内容'), SystemShareResult.unavailable);
    expect(invoked, isFalse);
  });
}
