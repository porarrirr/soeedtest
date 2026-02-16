import "package:flutter/material.dart";
import "package:flutter/services.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:intl/intl.dart";

import "../../app/providers.dart";
import "../../domain/models/debug_log_entry.dart";

class DebugLogScreen extends ConsumerWidget {
  const DebugLogScreen({super.key});

  Color _levelColor(BuildContext context, String level) {
    switch (level) {
      case "error":
        return Colors.red.shade700;
      case "warning":
        return Colors.orange.shade700;
      default:
        return Theme.of(context).colorScheme.primary;
    }
  }

  Future<void> _copyAll(BuildContext context, List<DebugLogEntry> logs) async {
    if (logs.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("コピーするログがありません。")));
      return;
    }
    final String content = logs
        .map((DebugLogEntry log) {
          final String detail = log.details == null ? "" : "\n${log.details}";
          return "[${log.timestampIso}] [${log.level}] [${log.category}] ${log.message}$detail";
        })
        .join("\n\n");
    await Clipboard.setData(ClipboardData(text: content));
    if (!context.mounted) {
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text("ログをコピーしました。")));
  }

  Future<void> _clearAll(BuildContext context, WidgetRef ref) async {
    await ref.read(debugLogControllerProvider.notifier).clear();
    if (!context.mounted) {
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text("ログを削除しました。")));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<List<DebugLogEntry>> logsAsync = ref.watch(
      debugLogControllerProvider,
    );
    final List<DebugLogEntry> logs = logsAsync.valueOrNull ?? <DebugLogEntry>[];
    return Scaffold(
      appBar: AppBar(
        title: const Text("デバッグログ"),
        actions: <Widget>[
          IconButton(
            tooltip: "更新",
            onPressed: () async {
              await ref.read(debugLogControllerProvider.notifier).reload();
            },
            icon: const Icon(Icons.refresh),
          ),
          IconButton(
            tooltip: "コピー",
            onPressed: () => _copyAll(context, logs),
            icon: const Icon(Icons.copy),
          ),
          IconButton(
            tooltip: "全削除",
            onPressed: logs.isEmpty ? null : () => _clearAll(context, ref),
            icon: const Icon(Icons.delete_outline),
          ),
        ],
      ),
      body: logsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (Object error, StackTrace stackTrace) {
          return Center(child: Text("ログ読み込みに失敗しました: $error"));
        },
        data: (List<DebugLogEntry> logs) {
          if (logs.isEmpty) {
            return const Center(child: Text("ログはまだありません。"));
          }
          return ListView.separated(
            padding: const EdgeInsets.all(12),
            itemCount: logs.length,
            separatorBuilder: (_, _) => const SizedBox(height: 8),
            itemBuilder: (BuildContext context, int index) {
              final DebugLogEntry item = logs[index];
              return Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Row(
                        children: <Widget>[
                          Container(
                            width: 10,
                            height: 10,
                            margin: const EdgeInsets.only(right: 8),
                            decoration: BoxDecoration(
                              color: _levelColor(context, item.level),
                              shape: BoxShape.circle,
                            ),
                          ),
                          Expanded(
                            child: Text(
                              "[${item.level}] ${item.category}",
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          Text(
                            DateFormat(
                              "yyyy-MM-dd HH:mm:ss",
                            ).format(item.timestamp.toLocal()),
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(item.message),
                      if (item.details != null &&
                          item.details!.isNotEmpty) ...<Widget>[
                        const SizedBox(height: 8),
                        SelectableText(
                          item.details!,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
