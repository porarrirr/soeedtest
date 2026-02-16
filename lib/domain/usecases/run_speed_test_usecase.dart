import "dart:async";

import "package:uuid/uuid.dart";

import "../../app/runtime_config.dart";
import "../../data/network/locate_api_client.dart";
import "../../platform/cli_speedtest_channel.dart";
import "../../platform/speedtest_channel.dart";
import "../models/connection_type.dart";
import "../models/speed_test_engine.dart";
import "../models/speed_test_result.dart";

typedef ProgressCallback = void Function(NativeSpeedtestProgress progress);

class UnsupportedSpeedTestEngineException implements Exception {
  const UnsupportedSpeedTestEngineException(this.engine, [this.reason]);

  final SpeedTestEngine engine;
  final String? reason;

  @override
  String toString() {
    if (reason == null) {
      return "UnsupportedSpeedTestEngineException: ${engine.name}";
    }
    return "UnsupportedSpeedTestEngineException: ${engine.name}, reason: $reason";
  }
}

class RunSpeedTestUseCase {
  RunSpeedTestUseCase({
    required LocateApiClient locateApiClient,
    required SpeedtestChannel speedtestChannel,
    required CliSpeedtestChannel cliSpeedtestChannel,
    required Uuid uuid,
  }) : _locateApiClient = locateApiClient,
       _speedtestChannel = speedtestChannel,
       _cliSpeedtestChannel = cliSpeedtestChannel,
       _uuid = uuid;

  final LocateApiClient _locateApiClient;
  final SpeedtestChannel _speedtestChannel;
  final CliSpeedtestChannel _cliSpeedtestChannel;
  final Uuid _uuid;

  StreamSubscription<NativeSpeedtestProgress>? _progressSubscription;
  Future<void> Function()? _cancelCallback;

  Future<SpeedTestResult> execute({
    required ConnectionType connectionType,
    required SpeedTestEngine engine,
    required AppRuntimeConfig config,
    required ProgressCallback onProgress,
  }) async {
    _progressSubscription?.cancel();

    try {
      NativeSpeedtestResult native;
      String? serverInfo;
      switch (engine) {
        case SpeedTestEngine.ndt7:
          {
            final LocateApiResult locate = await _locateApiClient.nearest();
            _progressSubscription = _speedtestChannel.progressStream.listen(
              onProgress,
            );
            _cancelCallback = _speedtestChannel.cancelTest;
            native = await _speedtestChannel.startTest(
              engineName: engine.storageValue,
              downloadUrl: locate.downloadUrl,
              uploadUrl: locate.uploadUrl,
            );
            serverInfo = native.serverInfo ?? locate.serverInfo;
            break;
          }
        case SpeedTestEngine.nperf:
        case SpeedTestEngine.openSpeedTest:
        case SpeedTestEngine.cloudflareWeb:
          throw UnsupportedSpeedTestEngineException(
            engine,
            "Web engines must run in webview flow",
          );
        case SpeedTestEngine.speedtestCli:
          {
            final List<String> order = config.cliProviderOrder
                .where((String item) => item == "ookla")
                .toList();
            _progressSubscription = _cliSpeedtestChannel.progressStream.listen(
              onProgress,
            );
            _cancelCallback = _cliSpeedtestChannel.cancelTest;
            native = await _cliSpeedtestChannel.startTest(
              providerOrder: order.isEmpty ? const <String>["ookla"] : order,
            );
            serverInfo = native.serverInfo;
            break;
          }
      }
      return SpeedTestResult(
        id: _uuid.v4(),
        timestampIso: DateTime.now().toIso8601String(),
        downloadMbps: native.downloadMbps,
        uploadMbps: native.uploadMbps,
        connectionType: connectionType,
        engine: engine,
        serverInfo: serverInfo,
      );
    } finally {
      await _progressSubscription?.cancel();
      _progressSubscription = null;
      _cancelCallback = null;
    }
  }

  Future<void> cancel() async {
    final Future<void> Function()? cancelCallback = _cancelCallback;
    if (cancelCallback != null) {
      await cancelCallback();
    }
    await _progressSubscription?.cancel();
    _progressSubscription = null;
    _cancelCallback = null;
  }
}
