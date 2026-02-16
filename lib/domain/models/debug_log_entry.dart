import "dart:convert";

class DebugLogEntry {
  const DebugLogEntry({
    required this.id,
    required this.timestampIso,
    required this.level,
    required this.category,
    required this.message,
    this.details,
  });

  final String id;
  final String timestampIso;
  final String level;
  final String category;
  final String message;
  final String? details;

  DateTime get timestamp => DateTime.tryParse(timestampIso) ?? DateTime.now();

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      "id": id,
      "timestampIso": timestampIso,
      "level": level,
      "category": category,
      "message": message,
      "details": details,
    };
  }

  String toStorageString() => jsonEncode(toJson());

  factory DebugLogEntry.fromStorageString(String raw) {
    final Object? decoded = jsonDecode(raw);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException("Invalid DebugLogEntry payload");
    }
    return DebugLogEntry.fromJson(decoded);
  }

  factory DebugLogEntry.fromJson(Map<dynamic, dynamic> json) {
    return DebugLogEntry(
      id: (json["id"] as String?) ?? "",
      timestampIso:
          (json["timestampIso"] as String?) ?? DateTime.now().toIso8601String(),
      level: (json["level"] as String?) ?? "info",
      category: (json["category"] as String?) ?? "general",
      message: (json["message"] as String?) ?? "",
      details: json["details"] as String?,
    );
  }
}
