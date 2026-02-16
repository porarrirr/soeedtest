import "package:flutter_test/flutter_test.dart";
import "package:iosandrodispeedtesy/app/runtime_config.dart";

void main() {
  group("AppRuntimeConfig", () {
    test("uses defaults for cloudflare URL and CLI provider order", () {
      final AppRuntimeConfig config = AppRuntimeConfig.fromRaw(
        nperfWebUrl: "",
        nperfAndroidConfig: "",
        nperfIosConfig: "",
        openSpeedTestUrl: "https://example.com/open",
        cloudflareUrl: "",
        cliProviderOrder: "",
      );

      expect(config.cloudflareUrl, "https://speed.cloudflare.com");
      expect(config.cliProviderOrder, <String>["ookla", "python"]);
    });

    test("normalizes empty values to null", () {
      final AppRuntimeConfig config = AppRuntimeConfig.fromRaw(
        nperfWebUrl: " ",
        nperfAndroidConfig: "   ",
        nperfIosConfig: "",
        openSpeedTestUrl: " ",
        cloudflareUrl: "https://speed.cloudflare.com",
        cliProviderOrder: "ookla, python",
      );

      expect(config.nperfAndroidConfig, isNull);
      expect(config.nperfIosConfig, isNull);
      expect(config.openSpeedTestUrl, isNull);
      expect(config.cliProviderOrder, <String>["ookla", "python"]);
    });
  });
}
