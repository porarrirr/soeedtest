enum SpeedTestEngine { ndt7, nperf, openSpeedTest, cloudflareWeb, speedtestCli }

extension SpeedTestEngineX on SpeedTestEngine {
  String get storageValue => name;

  String get label {
    switch (this) {
      case SpeedTestEngine.ndt7:
        return "M-Lab NDT7";
      case SpeedTestEngine.nperf:
        return "nPerf";
      case SpeedTestEngine.openSpeedTest:
        return "OpenSpeedTest";
      case SpeedTestEngine.cloudflareWeb:
        return "Cloudflare Speed Test";
      case SpeedTestEngine.speedtestCli:
        return "Speedtest CLI";
    }
  }

  bool get isWebFlow {
    return this == SpeedTestEngine.nperf ||
        this == SpeedTestEngine.openSpeedTest ||
        this == SpeedTestEngine.cloudflareWeb;
  }

  bool get isNativeFlow => !isWebFlow;

  static SpeedTestEngine fromStorageValue(String? value) {
    if (value == null) {
      return SpeedTestEngine.ndt7;
    }
    return SpeedTestEngine.values.firstWhere(
      (SpeedTestEngine item) => item.storageValue == value,
      orElse: () => SpeedTestEngine.ndt7,
    );
  }
}
