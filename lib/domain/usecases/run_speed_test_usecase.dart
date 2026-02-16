import "dart:async";

import "package:uuid/uuid.dart";

import "../../data/network/locate_api_client.dart";
import "../../platform/speedtest_channel.dart";
import "../models/connection_type.dart";
import "../models/speed_test_engine.dart";
import "../models/speed_test_result.dart";

typedef ProgressCallback = void Function(NativeSpeedtestProgress progress);

class UnsupportedSpeedTestEngineException implements Exception {
  const UnsupportedSpeedTestEngineException(this.engine);

  final SpeedTestEngine engine;

  @override
  String toString() => "UnsupportedSpeedTestEngineException: ${engine.name}";
}

class RunSpeedTestUseCase {
  RunSpeedTestUseCase({
    required LocateApiClient locateApiClient,
    required SpeedtestChannel speedtestChannel,
    required Uuid uuid,
  }) : _locateApiClient = locateApiClient,
       _speedtestChannel = speedtestChannel,
       _uuid = uuid;

  final LocateApiClient _locateApiClient;
  final SpeedtestChannel _speedtestChannel;
  final Uuid _uuid;

  StreamSubscription<NativeSpeedtestProgress>? _progressSubscription;

  Future<SpeedTestResult> execute({
    required ConnectionType connectionType,
    required SpeedTestEngine engine,
    required ProgressCallback onProgress,
  }) async {
    if (!engine.isImplemented) {
      throw UnsupportedSpeedTestEngineException(engine);
    }
    _progressSubscription?.cancel();
    _progressSubscription = _speedtestChannel.progressStream.listen(onProgress);
    try {
      final LocateApiResult locate = await _locateApiClient.nearest();
      final NativeSpeedtestResult native = await _speedtestChannel.startTest(
        engineName: engine.storageValue,
        downloadUrl: locate.downloadUrl,
        uploadUrl: locate.uploadUrl,
      );
      return SpeedTestResult(
        id: _uuid.v4(),
        timestampIso: DateTime.now().toIso8601String(),
        downloadMbps: native.downloadMbps,
        uploadMbps: native.uploadMbps,
        connectionType: connectionType,
        engine: engine,
        serverInfo: native.serverInfo ?? locate.serverInfo,
      );
    } finally {
      await _progressSubscription?.cancel();
      _progressSubscription = null;
    }
  }

  Future<void> cancel() async {
    await _speedtestChannel.cancelTest();
    await _progressSubscription?.cancel();
    _progressSubscription = null;
  }
}
