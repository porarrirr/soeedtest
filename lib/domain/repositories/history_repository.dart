import "../models/connection_type.dart";
import "../models/speed_test_result.dart";

abstract class HistoryRepository {
  Future<void> save(SpeedTestResult result);

  Future<List<SpeedTestResult>> getAll();

  Future<void> clear();

  Future<List<SpeedTestResult>> filterBy(ConnectionType type);
}
