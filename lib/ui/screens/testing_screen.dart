import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";

import "../../app/providers.dart";
import "result_screen.dart";

class TestingScreen extends ConsumerStatefulWidget {
  const TestingScreen({super.key});

  @override
  ConsumerState<TestingScreen> createState() => _TestingScreenState();
}

class _TestingScreenState extends ConsumerState<TestingScreen> {
  bool _handled = false;

  @override
  Widget build(BuildContext context) {
    ref.listen<SpeedTestState>(speedTestControllerProvider, (
      SpeedTestState? previous,
      SpeedTestState next,
    ) {
      if (_handled) {
        return;
      }
      if (next.phase == TestPhase.done && next.result != null) {
        _handled = true;
        Navigator.of(context).pushReplacement(
          MaterialPageRoute<void>(
            builder: (_) => ResultScreen(result: next.result!),
          ),
        );
        return;
      }
      if (next.phase == TestPhase.error || next.phase == TestPhase.cancelled) {
        _handled = true;
        final String message = next.errorMessage ?? "測定が中断されました。";
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(message)));
        Navigator.of(context).pop();
      }
    });

    final SpeedTestState state = ref.watch(speedTestControllerProvider);
    final String phaseLabel = switch (state.phase) {
      TestPhase.download => "DL測定中",
      TestPhase.upload => "UL測定中",
      _ => "測定準備中",
    };

    return Scaffold(
      appBar: AppBar(title: const Text("測定中")),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text(
              phaseLabel,
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            LinearProgressIndicator(
              value: state.progress > 0 ? state.progress : null,
            ),
            const SizedBox(height: 20),
            Text(
              "${(state.currentMbps ?? 0).toStringAsFixed(1)} Mbps",
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 38, fontWeight: FontWeight.w700),
            ),
            const Spacer(),
            OutlinedButton(
              onPressed: () async {
                await ref.read(speedTestControllerProvider.notifier).cancel();
              },
              child: const Text("キャンセル"),
            ),
          ],
        ),
      ),
    );
  }
}
