import "dart:async";

import "package:flutter/services.dart";

class NativeSpeedtestResult {
  const NativeSpeedtestResult({
    required this.downloadMbps,
    required this.uploadMbps,
    this.serverInfo,
  });

  final double downloadMbps;
  final double uploadMbps;
  final String? serverInfo;
}

class NativeSpeedtestProgress {
  const NativeSpeedtestProgress({
    required this.phase,
    required this.mbps,
    required this.progress,
  });

  final String phase;
  final double mbps;
  final double progress;
}

class SpeedtestChannel {
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
    required String engineName,
    required String downloadUrl,
    required String uploadUrl,
  }) async {
    final Map<dynamic, dynamic>? result = await _methodChannel
        .invokeMapMethod<dynamic, dynamic>("startTest", <String, dynamic>{
          "engine": engineName,
          "downloadUrl": downloadUrl,
          "uploadUrl": uploadUrl,
        });
    if (result == null) {
      throw PlatformException(
        code: "no_result",
        message: "Native test returned no result",
      );
    }
    return NativeSpeedtestResult(
      downloadMbps: ((result["downloadMbps"] as num?) ?? 0).toDouble(),
      uploadMbps: ((result["uploadMbps"] as num?) ?? 0).toDouble(),
      serverInfo: result["serverInfo"] as String?,
    );
  }

  Future<void> cancelTest() async {
    await _methodChannel.invokeMethod<void>("cancelTest");
  }
}
