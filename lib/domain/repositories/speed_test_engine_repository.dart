import "../models/speed_test_engine.dart";

abstract class SpeedTestEngineRepository {
  Future<SpeedTestEngine> getSelectedEngine();

  Future<void> setSelectedEngine(SpeedTestEngine engine);
}
