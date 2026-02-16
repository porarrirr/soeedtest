import "dart:convert";

import "connection_type.dart";
import "speed_test_engine.dart";

class SpeedTestResult {
  const SpeedTestResult({
    required this.id,
    required this.timestampIso,
    required this.downloadMbps,
    required this.uploadMbps,
    required this.connectionType,
    this.engine = SpeedTestEngine.ndt7,
    this.serverInfo,
    this.error,
  });

  final String id;
  final String timestampIso;
  final double downloadMbps;
  final double uploadMbps;
  final ConnectionType connectionType;
  final SpeedTestEngine engine;
  final String? serverInfo;
  final String? error;

  DateTime get timestamp => DateTime.tryParse(timestampIso) ?? DateTime.now();

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      "id": id,
      "timestampIso": timestampIso,
      "downloadMbps": downloadMbps,
      "uploadMbps": uploadMbps,
      "connectionType": connectionType.name,
      "engine": engine.storageValue,
      "serverInfo": serverInfo,
      "error": error,
    };
  }

  String toStorageString() => jsonEncode(toJson());

  factory SpeedTestResult.fromStorageString(String raw) {
    final Object? decoded = jsonDecode(raw);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException("Invalid SpeedTestResult payload");
    }
    return SpeedTestResult.fromJson(decoded);
  }

  factory SpeedTestResult.fromJson(Map<dynamic, dynamic> json) {
    final String typeRaw = (json["connectionType"] as String?) ?? "unknown";
    return SpeedTestResult(
      id: (json["id"] as String?) ?? "",
      timestampIso:
          (json["timestampIso"] as String?) ?? DateTime.now().toIso8601String(),
      downloadMbps: ((json["downloadMbps"] as num?) ?? 0).toDouble(),
      uploadMbps: ((json["uploadMbps"] as num?) ?? 0).toDouble(),
      connectionType: ConnectionType.values.firstWhere(
        (ConnectionType value) => value.name == typeRaw,
        orElse: () => ConnectionType.unknown,
      ),
      engine: SpeedTestEngineX.fromStorageValue(json["engine"] as String?),
      serverInfo: json["serverInfo"] as String?,
      error: json["error"] as String?,
    );
  }
}
