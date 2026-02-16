enum SpeedTestEngine { ndt7, nperf, openSpeedTest, cloudflareWeb }

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
    }
  }

  String get statusLabel {
    if (isImplemented) {
      return "実装済み";
    }
    return "未対応";
  }

  bool get isImplemented => this == SpeedTestEngine.ndt7;

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
