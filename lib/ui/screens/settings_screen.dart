import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";

import "../../app/providers.dart";
import "../../domain/models/speed_test_engine.dart";
import "consent_screen.dart";

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<ConsentSnapshot> consent = ref.watch(
      consentControllerProvider,
    );
    final AsyncValue<SpeedTestEngine> selectedEngineAsync = ref.watch(
      speedTestEngineControllerProvider,
    );
    final SpeedTestEngine selectedEngine =
        selectedEngineAsync.valueOrNull ?? SpeedTestEngine.ndt7;
    final bool granted = consent.valueOrNull?.granted ?? false;

    return Scaffold(
      appBar: AppBar(title: const Text("設定")),
      body: ListView(
        children: <Widget>[
          ListTile(
            title: const Text("同意状態"),
            subtitle: Text(granted ? "同意済み" : "未同意"),
          ),
          ListTile(
            title: const Text("同意画面を開く"),
            trailing: const Icon(Icons.arrow_forward_ios, size: 14),
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => const ConsentScreen()),
              );
            },
          ),
          ListTile(
            title: const Text("同意を撤回する"),
            subtitle: const Text("撤回後は測定を開始できません。"),
            enabled: granted,
            onTap: granted
                ? () async {
                    await ref.read(consentControllerProvider.notifier).revoke();
                    if (!context.mounted) {
                      return;
                    }
                    ScaffoldMessenger.of(
                      context,
                    ).showSnackBar(const SnackBar(content: Text("同意を撤回しました。")));
                  }
                : null,
          ),
          const Divider(),
          const ListTile(
            title: Text("測定エンジン"),
            subtitle: Text("速度測定で使用する基盤を選択します。"),
          ),
          for (final SpeedTestEngine engine in SpeedTestEngine.values)
            ListTile(
              title: Text(engine.label),
              subtitle: Text(
                engine.isImplemented
                    ? engine.statusLabel
                    : "${engine.statusLabel} (選択のみ)",
              ),
              trailing: Icon(
                selectedEngine == engine
                    ? Icons.radio_button_checked
                    : Icons.radio_button_off,
              ),
              onTap: () async {
                await ref
                    .read(speedTestEngineControllerProvider.notifier)
                    .setSelectedEngine(engine);
                if (!context.mounted) {
                  return;
                }
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text("測定エンジンを ${engine.label} に変更しました。")),
                );
              },
            ),
          if (selectedEngineAsync.hasError)
            const ListTile(
              title: Text("測定エンジン設定の読み込みに失敗しました"),
              subtitle: Text("デフォルト値で継続します。"),
            ),
          const Divider(),
          const ListTile(
            title: Text("注意文・ポリシー"),
            subtitle: Text(
              "https://example.com/policy\nhttps://example.com/notice",
            ),
          ),
        ],
      ),
    );
  }
}
