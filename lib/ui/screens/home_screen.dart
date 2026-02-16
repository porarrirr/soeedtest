import "dart:async";

import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:intl/intl.dart";

import "../../app/providers.dart";
import "../../domain/models/connection_type.dart";
import "../../domain/models/speed_test_engine.dart";
import "../../domain/models/speed_test_result.dart";
import "consent_screen.dart";
import "history_screen.dart";
import "settings_screen.dart";
import "testing_screen.dart";

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<ConsentSnapshot> consent = ref.watch(
      consentControllerProvider,
    );
    final AsyncValue<List<SpeedTestResult>> history = ref.watch(
      historyControllerProvider,
    );
    final AsyncValue<ConnectionType> connection = ref.watch(
      currentConnectionTypeProvider,
    );
    final AsyncValue<SpeedTestEngine> selectedEngineAsync = ref.watch(
      speedTestEngineControllerProvider,
    );
    final SpeedTestState testState = ref.watch(speedTestControllerProvider);

    final bool granted = consent.valueOrNull?.granted ?? false;
    final SpeedTestEngine selectedEngine =
        selectedEngineAsync.valueOrNull ?? SpeedTestEngine.ndt7;
    final SpeedTestResult? latest = history.valueOrNull?.isNotEmpty == true
        ? history.valueOrNull!.first
        : null;

    return Scaffold(
      appBar: AppBar(
        title: const Text("Speed Test"),
        actions: <Widget>[
          IconButton(
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => const HistoryScreen()),
              );
            },
            icon: const Icon(Icons.history),
          ),
          IconButton(
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => const SettingsScreen()),
              );
            },
            icon: const Icon(Icons.settings),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    const Text(
                      "接続種別",
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    Text(connection.valueOrNull?.label ?? "Unknown"),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Card(
              child: ListTile(
                title: const Text("測定エンジン"),
                subtitle: Text(
                  "${selectedEngine.label} (${selectedEngine.statusLabel})",
                ),
              ),
            ),
            const SizedBox(height: 12),
            if (latest != null)
              Card(
                child: ListTile(
                  title: Text(
                    "直近: DL ${latest.downloadMbps.toStringAsFixed(1)} / UL ${latest.uploadMbps.toStringAsFixed(1)} Mbps",
                  ),
                  subtitle: Text(
                    "${DateFormat("yyyy-MM-dd HH:mm").format(latest.timestamp.toLocal())}  •  ${latest.engine.label}",
                  ),
                ),
              )
            else
              const Card(
                child: ListTile(
                  title: Text("履歴なし"),
                  subtitle: Text("測定を開始すると結果が保存されます"),
                ),
              ),
            const Spacer(),
            if (!granted)
              const Text(
                "同意未取得のため測定できません。",
                style: TextStyle(color: Colors.red),
              ),
            if (granted && !selectedEngine.isImplemented)
              Text(
                "${selectedEngine.label} は未対応です。設定から実装済みエンジンを選んでください。",
                style: const TextStyle(color: Colors.red),
              ),
            const SizedBox(height: 8),
            SizedBox(
              height: 52,
              child: FilledButton(
                onPressed: testState.running || !selectedEngine.isImplemented
                    ? null
                    : () async {
                        if (!granted) {
                          Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => const ConsentScreen(),
                            ),
                          );
                          return;
                        }
                        unawaited(
                          ref
                              .read(speedTestControllerProvider.notifier)
                              .start(),
                        );
                        Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => const TestingScreen(),
                          ),
                        );
                      },
                child: const Text("開始"),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
