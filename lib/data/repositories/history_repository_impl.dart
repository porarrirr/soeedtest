import "package:hive/hive.dart";

import "../../domain/models/connection_type.dart";
import "../../domain/models/speed_test_result.dart";
import "../../domain/repositories/history_repository.dart";

class HistoryRepositoryImpl implements HistoryRepository {
  HistoryRepositoryImpl(this._historyBox);

  final Box<dynamic> _historyBox;

  @override
  Future<void> save(SpeedTestResult result) async {
    await _historyBox.put(result.id, result.toStorageString());
  }

  @override
  Future<List<SpeedTestResult>> getAll() async {
    final List<SpeedTestResult> items = _historyBox.values
        .whereType<String>()
        .map(SpeedTestResult.fromStorageString)
        .toList();
    items.sort(
      (SpeedTestResult a, SpeedTestResult b) =>
          b.timestamp.compareTo(a.timestamp),
    );
    return items;
  }

  @override
  Future<void> clear() async {
    await _historyBox.clear();
  }

  @override
  Future<List<SpeedTestResult>> filterBy(ConnectionType type) async {
    final List<SpeedTestResult> all = await getAll();
    return all
        .where((SpeedTestResult result) => result.connectionType == type)
        .toList();
  }
}
