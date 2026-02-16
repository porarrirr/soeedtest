import "package:flutter/material.dart";
import "package:intl/intl.dart";
import "package:share_plus/share_plus.dart";

import "../../domain/models/connection_type.dart";
import "../../domain/models/speed_test_result.dart";
import "history_screen.dart";

class ResultScreen extends StatelessWidget {
  const ResultScreen({super.key, required this.result});

  final SpeedTestResult result;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("結果")),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: <Widget>[
                    Text(
                      "DL ${result.downloadMbps.toStringAsFixed(1)} Mbps",
                      style: const TextStyle(
                        fontSize: 32,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      "UL ${result.uploadMbps.toStringAsFixed(1)} Mbps",
                      style: const TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            ListTile(
              title: const Text("日時"),
              subtitle: Text(
                DateFormat(
                  "yyyy-MM-dd HH:mm:ss",
                ).format(result.timestamp.toLocal()),
              ),
            ),
            ListTile(
              title: const Text("接続種別"),
              subtitle: Text(result.connectionType.label),
            ),
            ListTile(
              title: const Text("測定先"),
              subtitle: Text(result.serverInfo ?? "N/A"),
            ),
            const Spacer(),
            FilledButton.icon(
              onPressed: () async {
                final String message =
                    "Speed Test Result\n"
                    "DL: ${result.downloadMbps.toStringAsFixed(1)} Mbps\n"
                    "UL: ${result.uploadMbps.toStringAsFixed(1)} Mbps\n"
                    "At: ${DateFormat("yyyy-MM-dd HH:mm:ss").format(result.timestamp.toLocal())}\n"
                    "Connection: ${result.connectionType.label}";
                await SharePlus.instance.share(ShareParams(text: message));
              },
              icon: const Icon(Icons.share),
              label: const Text("共有"),
            ),
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const HistoryScreen(),
                  ),
                );
              },
              child: const Text("履歴を見る"),
            ),
          ],
        ),
      ),
    );
  }
}
