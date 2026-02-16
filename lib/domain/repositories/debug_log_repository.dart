import "../models/debug_log_entry.dart";

abstract class DebugLogRepository {
  Future<void> append(DebugLogEntry entry);

  Future<List<DebugLogEntry>> getAll();

  Future<void> clear();
}
