class AppRuntimeConfig {
  const AppRuntimeConfig({
    required this.nperfWebUrl,
    required this.nperfAndroidConfig,
    required this.nperfIosConfig,
    required this.openSpeedTestUrl,
    required this.cloudflareUrl,
    required this.cliProviderOrder,
  });

  factory AppRuntimeConfig.fromEnvironment() {
    return AppRuntimeConfig.fromRaw(
      nperfWebUrl: const String.fromEnvironment("SPEEDTEST_NPERF_WEB_URL"),
      nperfAndroidConfig: const String.fromEnvironment(
        "SPEEDTEST_NPERF_ANDROID_CONFIG",
      ),
      nperfIosConfig: const String.fromEnvironment(
        "SPEEDTEST_NPERF_IOS_CONFIG",
      ),
      openSpeedTestUrl: const String.fromEnvironment(
        "SPEEDTEST_OPEN_SPEED_TEST_URL",
      ),
      cloudflareUrl: const String.fromEnvironment("SPEEDTEST_CLOUDFLARE_URL"),
      cliProviderOrder: const String.fromEnvironment(
        "SPEEDTEST_CLI_PROVIDER_ORDER",
      ),
    );
  }

  factory AppRuntimeConfig.fromRaw({
    required String nperfWebUrl,
    required String nperfAndroidConfig,
    required String nperfIosConfig,
    required String openSpeedTestUrl,
    required String cloudflareUrl,
    required String cliProviderOrder,
  }) {
    final List<String> providerOrder = cliProviderOrder
        .split(",")
        .map((String item) => item.trim().toLowerCase())
        .where((String item) => item.isNotEmpty)
        .toList();
    return AppRuntimeConfig(
      nperfWebUrl: _normalize(nperfWebUrl),
      nperfAndroidConfig: _normalize(nperfAndroidConfig),
      nperfIosConfig: _normalize(nperfIosConfig),
      openSpeedTestUrl: _normalize(openSpeedTestUrl),
      cloudflareUrl:
          _normalize(cloudflareUrl) ?? "https://speed.cloudflare.com",
      cliProviderOrder: providerOrder.isEmpty
          ? const <String>["ookla", "python"]
          : providerOrder,
    );
  }

  final String? nperfWebUrl;
  final String? nperfAndroidConfig;
  final String? nperfIosConfig;
  final String? openSpeedTestUrl;
  final String cloudflareUrl;
  final List<String> cliProviderOrder;

  static String? _normalize(String value) {
    final String trimmed = value.trim();
    if (trimmed.isEmpty) {
      return null;
    }
    return trimmed;
  }
}
