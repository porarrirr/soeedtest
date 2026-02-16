import "package:hive/hive.dart";

import "../../domain/models/debug_log_entry.dart";
import "../../domain/repositories/debug_log_repository.dart";

class DebugLogRepositoryImpl implements DebugLogRepository {
  DebugLogRepositoryImpl(this._debugLogBox);

  static const int maxEntries = 500;

  final Box<dynamic> _debugLogBox;

  @override
  Future<void> append(DebugLogEntry entry) async {
    await _debugLogBox.put(entry.id, entry.toStorageString());
    if (_debugLogBox.length <= maxEntries) {
      return;
    }
    final List<DebugLogEntry> sorted =
        _debugLogBox.values
            .whereType<String>()
            .map(DebugLogEntry.fromStorageString)
            .toList()
          ..sort(
            (DebugLogEntry a, DebugLogEntry b) =>
                b.timestamp.compareTo(a.timestamp),
          );
    final Iterable<String> removeIds = sorted
        .skip(maxEntries)
        .map((DebugLogEntry entry) => entry.id)
        .where((String id) => id.isNotEmpty);
    await _debugLogBox.deleteAll(removeIds);
  }

  @override
  Future<List<DebugLogEntry>> getAll() async {
    final List<DebugLogEntry> items = _debugLogBox.values
        .whereType<String>()
        .map(DebugLogEntry.fromStorageString)
        .toList();
    items.sort(
      (DebugLogEntry a, DebugLogEntry b) => b.timestamp.compareTo(a.timestamp),
    );
    return items;
  }

  @override
  Future<void> clear() async {
    await _debugLogBox.clear();
  }
}
