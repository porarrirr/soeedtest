import "package:flutter_test/flutter_test.dart";
import "package:hive/hive.dart";
import "package:hive_test/hive_test.dart";
import "package:iosandrodispeedtesy/data/repositories/speed_test_engine_repository_impl.dart";
import "package:iosandrodispeedtesy/domain/models/speed_test_engine.dart";

void main() {
  group("SpeedTestEngineRepositoryImpl", () {
    late Box<dynamic> settingsBox;
    late SpeedTestEngineRepositoryImpl repository;

    setUp(() async {
      await setUpTestHive();
      settingsBox = await Hive.openBox<dynamic>("engine_settings_test_box");
      repository = SpeedTestEngineRepositoryImpl(settingsBox);
    });

    tearDown(() async {
      await settingsBox.deleteFromDisk();
      await tearDownTestHive();
    });

    test("defaults to ndt7 when no value exists", () async {
      final SpeedTestEngine selected = await repository.getSelectedEngine();
      expect(selected, SpeedTestEngine.ndt7);
    });

    test("stores and returns selected engine", () async {
      await repository.setSelectedEngine(SpeedTestEngine.cloudflareWeb);
      final SpeedTestEngine selected = await repository.getSelectedEngine();
      expect(selected, SpeedTestEngine.cloudflareWeb);
    });
  });
}
