import "package:flutter_test/flutter_test.dart";
import "package:hive/hive.dart";
import "package:hive_test/hive_test.dart";
import "package:iosandrodispeedtesy/data/repositories/history_repository_impl.dart";
import "package:iosandrodispeedtesy/domain/models/connection_type.dart";
import "package:iosandrodispeedtesy/domain/models/speed_test_result.dart";

void main() {
  group("HistoryRepositoryImpl", () {
    late Box<dynamic> historyBox;
    late HistoryRepositoryImpl repository;

    setUp(() async {
      await setUpTestHive();
      historyBox = await Hive.openBox<dynamic>("history_test_box");
      repository = HistoryRepositoryImpl(historyBox);
    });

    tearDown(() async {
      await historyBox.deleteFromDisk();
      await tearDownTestHive();
    });

    test("saves and returns newest first", () async {
      final older = SpeedTestResult(
        id: "1",
        timestampIso: DateTime(2025, 1, 1, 12).toIso8601String(),
        downloadMbps: 10,
        uploadMbps: 5,
        connectionType: ConnectionType.mobile,
      );
      final newer = SpeedTestResult(
        id: "2",
        timestampIso: DateTime(2025, 1, 1, 13).toIso8601String(),
        downloadMbps: 20,
        uploadMbps: 8,
        connectionType: ConnectionType.wifi,
      );

      await repository.save(older);
      await repository.save(newer);
      final all = await repository.getAll();

      expect(all.length, 2);
      expect(all.first.id, "2");
      expect(all.last.id, "1");
    });

    test("filters by connection type", () async {
      await repository.save(
        SpeedTestResult(
          id: "wifi",
          timestampIso: DateTime.now().toIso8601String(),
          downloadMbps: 30,
          uploadMbps: 15,
          connectionType: ConnectionType.wifi,
        ),
      );
      await repository.save(
        SpeedTestResult(
          id: "mobile",
          timestampIso: DateTime.now().toIso8601String(),
          downloadMbps: 12,
          uploadMbps: 3,
          connectionType: ConnectionType.mobile,
        ),
      );

      final wifiOnly = await repository.filterBy(ConnectionType.wifi);
      expect(wifiOnly.length, 1);
      expect(wifiOnly.first.id, "wifi");
    });
  });
}
