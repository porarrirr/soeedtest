enum ConnectionType { wifi, mobile, unknown }

extension ConnectionTypeX on ConnectionType {
  String get label {
    switch (this) {
      case ConnectionType.wifi:
        return "Wi-Fi";
      case ConnectionType.mobile:
        return "Mobile";
      case ConnectionType.unknown:
        return "Unknown";
    }
  }
}
