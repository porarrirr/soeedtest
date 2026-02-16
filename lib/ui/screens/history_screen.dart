import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:intl/intl.dart";

import "../../app/providers.dart";
import "../../domain/models/connection_type.dart";
import "../../domain/models/speed_test_engine.dart";
import "../../domain/models/speed_test_result.dart";
import "result_screen.dart";

class HistoryScreen extends ConsumerWidget {
  const HistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<List<SpeedTestResult>> history = ref.watch(
      filteredHistoryProvider,
    );
    final ConnectionType? currentFilter = ref.watch(historyFilterProvider);

    return Scaffold(
      appBar: AppBar(title: const Text("履歴")),
      body: Column(
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Wrap(
              spacing: 8,
              children: <Widget>[
                ChoiceChip(
                  label: const Text("All"),
                  selected: currentFilter == null,
                  onSelected: (_) =>
                      ref.read(historyFilterProvider.notifier).state = null,
                ),
                ChoiceChip(
                  label: const Text("Wi-Fi"),
                  selected: currentFilter == ConnectionType.wifi,
                  onSelected: (_) =>
                      ref.read(historyFilterProvider.notifier).state =
                          ConnectionType.wifi,
                ),
                ChoiceChip(
                  label: const Text("Mobile"),
                  selected: currentFilter == ConnectionType.mobile,
                  onSelected: (_) =>
                      ref.read(historyFilterProvider.notifier).state =
                          ConnectionType.mobile,
                ),
              ],
            ),
          ),
          Expanded(
            child: history.when(
              data: (List<SpeedTestResult> items) {
                if (items.isEmpty) {
                  return const Center(child: Text("履歴はありません"));
                }
                return ListView.separated(
                  itemCount: items.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (BuildContext context, int index) {
                    final SpeedTestResult item = items[index];
                    return ListTile(
                      title: Text(
                        "DL ${item.downloadMbps.toStringAsFixed(1)} / UL ${item.uploadMbps.toStringAsFixed(1)} Mbps",
                      ),
                      subtitle: Text(
                        "${DateFormat("yyyy-MM-dd HH:mm").format(item.timestamp.toLocal())}  •  ${item.connectionType.label}  •  ${item.engine.label}",
                      ),
                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => ResultScreen(result: item),
                          ),
                        );
                      },
                    );
                  },
                );
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (Object error, StackTrace stackTrace) =>
                  Center(child: Text("読み込み失敗: $error")),
            ),
          ),
        ],
      ),
    );
  }
}
