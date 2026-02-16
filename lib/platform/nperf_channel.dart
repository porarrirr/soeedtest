import "dart:async";

import "package:flutter/services.dart";

import "speedtest_channel.dart";

class NperfChannel {
  static const MethodChannel _methodChannel = MethodChannel("speedtest");
  static const EventChannel _eventChannel = EventChannel("speedtest_progress");

  Stream<NativeSpeedtestProgress> get progressStream {
    return _eventChannel.receiveBroadcastStream().map((dynamic event) {
      final Map<dynamic, dynamic> map = event as Map<dynamic, dynamic>;
      return NativeSpeedtestProgress(
        phase: (map["phase"] as String?) ?? "download",
        mbps: ((map["mbps"] as num?) ?? 0).toDouble(),
        progress: ((map["progress"] as num?) ?? 0).toDouble(),
      );
    });
  }

  Future<NativeSpeedtestResult> startTest({
    required String config,
    required String downloadUrl,
    required String uploadUrl,
  }) async {
    final Map<dynamic, dynamic>? result = await _methodChannel
        .invokeMapMethod<dynamic, dynamic>("startNperfTest", <String, dynamic>{
          "config": config,
          "downloadUrl": downloadUrl,
          "uploadUrl": uploadUrl,
        });
    if (result == null) {
      throw PlatformException(
        code: "no_result",
        message: "Native nPerf test returned no result",
      );
    }
    return NativeSpeedtestResult(
      downloadMbps: ((result["downloadMbps"] as num?) ?? 0).toDouble(),
      uploadMbps: ((result["uploadMbps"] as num?) ?? 0).toDouble(),
      serverInfo: result["serverInfo"] as String?,
    );
  }

  Future<void> cancelTest() async {
    await _methodChannel.invokeMethod<void>("cancelNperfTest");
  }
}
