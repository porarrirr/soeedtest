import "dart:convert";

class WebSpeedtestBridgeMessage {
  const WebSpeedtestBridgeMessage({
    required this.type,
    this.phase,
    this.progress,
    this.downloadMbps,
    this.uploadMbps,
    this.mbps,
    this.error,
    this.serverInfo,
  });

  factory WebSpeedtestBridgeMessage.tryParse(String raw) {
    final Object? decoded = jsonDecode(raw);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException("Invalid bridge payload");
    }
    return WebSpeedtestBridgeMessage(
      type: (decoded["type"] as String?) ?? "",
      phase: decoded["phase"] as String?,
      progress: (decoded["progress"] as num?)?.toDouble(),
      downloadMbps: (decoded["downloadMbps"] as num?)?.toDouble(),
      uploadMbps: (decoded["uploadMbps"] as num?)?.toDouble(),
      mbps: (decoded["mbps"] as num?)?.toDouble(),
      error: decoded["error"] as String?,
      serverInfo: decoded["serverInfo"] as String?,
    );
  }

  final String type;
  final String? phase;
  final double? progress;
  final double? downloadMbps;
  final double? uploadMbps;
  final double? mbps;
  final String? error;
  final String? serverInfo;
}
