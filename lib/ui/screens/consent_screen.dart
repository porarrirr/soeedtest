import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";

import "../../app/providers.dart";
import "home_screen.dart";

class ConsentScreen extends ConsumerWidget {
  const ConsentScreen({super.key, this.initialFlow = false});

  final bool initialFlow;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("同意"),
        automaticallyImplyLeading: !initialFlow,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const Text(
              "このアプリは外部公開測定基盤（M-Lab）を利用して通信速度を測定します。",
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            const Text(
              "測定データはM-Labの公開データとして共有される可能性があります。"
              "内容をご理解の上、同意してください。"
              "\n\n同意しない場合は測定を開始できません。",
            ),
            const Spacer(),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () async {
                  await ref.read(consentControllerProvider.notifier).accept();
                  if (initialFlow) {
                    if (!context.mounted) {
                      return;
                    }
                    Navigator.of(context).pushReplacement(
                      MaterialPageRoute<void>(
                        builder: (_) => const HomeScreen(),
                      ),
                    );
                  } else {
                    if (!context.mounted) {
                      return;
                    }
                    Navigator.of(context).pop();
                  }
                },
                child: const Text("同意する"),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: () async {
                  await ref.read(consentControllerProvider.notifier).decline();
                  if (initialFlow) {
                    if (!context.mounted) {
                      return;
                    }
                    Navigator.of(context).pushReplacement(
                      MaterialPageRoute<void>(
                        builder: (_) => const HomeScreen(),
                      ),
                    );
                  } else {
                    if (!context.mounted) {
                      return;
                    }
                    Navigator.of(context).pop();
                  }
                },
                child: const Text("同意しない"),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
