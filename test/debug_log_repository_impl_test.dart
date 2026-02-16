import "package:flutter_test/flutter_test.dart";
import "package:hive/hive.dart";
import "package:hive_test/hive_test.dart";
import "package:iosandrodispeedtesy/data/repositories/debug_log_repository_impl.dart";
import "package:iosandrodispeedtesy/domain/models/debug_log_entry.dart";

void main() {
  group("DebugLogRepositoryImpl", () {
    late Box<dynamic> debugLogBox;
    late DebugLogRepositoryImpl repository;

    setUp(() async {
      await setUpTestHive();
      debugLogBox = await Hive.openBox<dynamic>("debug_log_test_box");
      repository = DebugLogRepositoryImpl(debugLogBox);
    });

    tearDown(() async {
      await debugLogBox.deleteFromDisk();
      await tearDownTestHive();
    });

    test("appends and returns newest first", () async {
      final DebugLogEntry older = DebugLogEntry(
        id: "1",
        timestampIso: DateTime(2025, 1, 1, 12).toIso8601String(),
        level: "info",
        category: "speedtest",
        message: "older",
      );
      final DebugLogEntry newer = DebugLogEntry(
        id: "2",
        timestampIso: DateTime(2025, 1, 1, 13).toIso8601String(),
        level: "error",
        category: "speedtest",
        message: "newer",
      );

      await repository.append(older);
      await repository.append(newer);
      final List<DebugLogEntry> logs = await repository.getAll();

      expect(logs.length, 2);
      expect(logs.first.id, "2");
      expect(logs.last.id, "1");
    });

    test("keeps only latest 500 entries", () async {
      final DateTime base = DateTime(2025, 1, 1);
      for (int i = 0; i < 510; i++) {
        await repository.append(
          DebugLogEntry(
            id: "$i",
            timestampIso: base.add(Duration(seconds: i)).toIso8601String(),
            level: "info",
            category: "speedtest",
            message: "log-$i",
          ),
        );
      }

      final List<DebugLogEntry> logs = await repository.getAll();
      expect(logs.length, 500);
      expect(logs.first.id, "509");
      expect(logs.any((DebugLogEntry entry) => entry.id == "0"), isFalse);
      expect(logs.any((DebugLogEntry entry) => entry.id == "9"), isFalse);
      expect(logs.any((DebugLogEntry entry) => entry.id == "10"), isTrue);
    });
  });
}
