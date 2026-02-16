import "package:flutter/foundation.dart";

import "../domain/models/speed_test_engine.dart";
import "runtime_config.dart";

class EngineAvailability {
  const EngineAvailability.available() : available = true, reason = null;

  const EngineAvailability.unavailable(this.reason) : available = false;

  final bool available;
  final String? reason;
}

class EngineAvailabilityService {
  const EngineAvailabilityService({
    required this.isWeb,
    required this.platform,
  });

  final bool isWeb;
  final TargetPlatform platform;

  EngineAvailability availabilityFor(
    SpeedTestEngine engine,
    AppRuntimeConfig config,
  ) {
    switch (engine) {
      case SpeedTestEngine.ndt7:
        return const EngineAvailability.available();
      case SpeedTestEngine.nperf:
        if (isWeb) {
          return const EngineAvailability.unavailable("Web版では利用できません。");
        }
        if (config.nperfWebUrl != null) {
          return const EngineAvailability.available();
        }
        return const EngineAvailability.unavailable(
          "nPerf URLが未設定です（SPEEDTEST_NPERF_WEB_URL）。",
        );
      case SpeedTestEngine.openSpeedTest:
        if (config.openSpeedTestUrl == null) {
          return const EngineAvailability.unavailable(
            "OpenSpeedTest URLが未設定です（SPEEDTEST_OPEN_SPEED_TEST_URL）。",
          );
        }
        return const EngineAvailability.available();
      case SpeedTestEngine.cloudflareWeb:
        return const EngineAvailability.available();
      case SpeedTestEngine.speedtestCli:
        if (isWeb) {
          return const EngineAvailability.unavailable("Web版では利用できません。");
        }
        if (platform != TargetPlatform.android) {
          return const EngineAvailability.unavailable(
            "Speedtest CLIはAndroidのみ対応です。",
          );
        }
        return const EngineAvailability.available();
    }
  }
}
