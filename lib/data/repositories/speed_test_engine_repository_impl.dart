import "package:hive/hive.dart";

import "../../domain/models/speed_test_engine.dart";
import "../../domain/repositories/speed_test_engine_repository.dart";

class SpeedTestEngineRepositoryImpl implements SpeedTestEngineRepository {
  SpeedTestEngineRepositoryImpl(this._settingsBox);

  static const String engineKey = "speed_test_engine";

  final Box<dynamic> _settingsBox;

  @override
  Future<SpeedTestEngine> getSelectedEngine() async {
    final String? stored = _settingsBox.get(engineKey) as String?;
    return SpeedTestEngineX.fromStorageValue(stored);
  }

  @override
  Future<void> setSelectedEngine(SpeedTestEngine engine) async {
    await _settingsBox.put(engineKey, engine.storageValue);
  }
}
