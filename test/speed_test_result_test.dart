import "package:flutter_test/flutter_test.dart";
import "package:iosandrodispeedtesy/domain/models/connection_type.dart";
import "package:iosandrodispeedtesy/domain/models/speed_test_engine.dart";
import "package:iosandrodispeedtesy/domain/models/speed_test_result.dart";

void main() {
  group("SpeedTestResult", () {
    test("defaults engine to ndt7 for backward compatibility", () {
      final SpeedTestResult result = SpeedTestResult(
        id: "id-1",
        timestampIso: "2025-01-01T00:00:00.000Z",
        downloadMbps: 10,
        uploadMbps: 5,
        connectionType: ConnectionType.wifi,
      );

      expect(result.engine, SpeedTestEngine.ndt7);
    });

    test("reads ndt7 from old storage payload without engine field", () {
      final SpeedTestResult result = SpeedTestResult.fromJson(<String, dynamic>{
        "id": "id-2",
        "timestampIso": "2025-01-01T00:00:00.000Z",
        "downloadMbps": 20,
        "uploadMbps": 8,
        "connectionType": "mobile",
      });

      expect(result.engine, SpeedTestEngine.ndt7);
      expect(result.connectionType, ConnectionType.mobile);
    });
  });
}
