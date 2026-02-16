import "package:flutter/foundation.dart";
import "package:flutter_test/flutter_test.dart";
import "package:iosandrodispeedtesy/app/engine_availability.dart";
import "package:iosandrodispeedtesy/app/runtime_config.dart";
import "package:iosandrodispeedtesy/domain/models/speed_test_engine.dart";

void main() {
  group("EngineAvailabilityService", () {
    final AppRuntimeConfig configured = AppRuntimeConfig.fromRaw(
      nperfWebUrl: "https://example.com/nperf",
      nperfAndroidConfig: "android-config",
      nperfIosConfig: "ios-config",
      openSpeedTestUrl: "https://example.com/open",
      cloudflareUrl: "https://speed.cloudflare.com",
      cliProviderOrder: "ookla,python",
    );

    test("marks nPerf unavailable when config is missing", () {
      const EngineAvailabilityService service = EngineAvailabilityService(
        isWeb: false,
        platform: TargetPlatform.android,
      );
      final AppRuntimeConfig config = AppRuntimeConfig.fromRaw(
        nperfWebUrl: "",
        nperfAndroidConfig: "",
        nperfIosConfig: "",
        openSpeedTestUrl: "https://example.com/open",
        cloudflareUrl: "https://speed.cloudflare.com",
        cliProviderOrder: "ookla,python",
      );

      final EngineAvailability availability = service.availabilityFor(
        SpeedTestEngine.nperf,
        config,
      );

      expect(availability.available, isFalse);
      expect(availability.reason, isNotNull);
    });

    test("marks Speedtest CLI available only on Android", () {
      const EngineAvailabilityService androidService =
          EngineAvailabilityService(
            isWeb: false,
            platform: TargetPlatform.android,
          );
      const EngineAvailabilityService iosService = EngineAvailabilityService(
        isWeb: false,
        platform: TargetPlatform.iOS,
      );

      expect(
        androidService
            .availabilityFor(SpeedTestEngine.speedtestCli, configured)
            .available,
        isTrue,
      );
      expect(
        iosService
            .availabilityFor(SpeedTestEngine.speedtestCli, configured)
            .available,
        isFalse,
      );
    });

    test("marks OpenSpeedTest unavailable when URL is missing", () {
      const EngineAvailabilityService service = EngineAvailabilityService(
        isWeb: false,
        platform: TargetPlatform.android,
      );
      final AppRuntimeConfig config = AppRuntimeConfig.fromRaw(
        nperfWebUrl: "https://example.com/nperf",
        nperfAndroidConfig: "android-config",
        nperfIosConfig: "ios-config",
        openSpeedTestUrl: "",
        cloudflareUrl: "https://speed.cloudflare.com",
        cliProviderOrder: "ookla,python",
      );

      final EngineAvailability availability = service.availabilityFor(
        SpeedTestEngine.openSpeedTest,
        config,
      );

      expect(availability.available, isFalse);
      expect(availability.reason, contains("OPEN_SPEED_TEST"));
    });
  });
}
