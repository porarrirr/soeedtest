import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";

import "../../app/providers.dart";
import "consent_screen.dart";
import "home_screen.dart";

class AppGateScreen extends ConsumerWidget {
  const AppGateScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<ConsentSnapshot> consent = ref.watch(
      consentControllerProvider,
    );
    return consent.when(
      data: (ConsentSnapshot state) {
        if (!state.prompted) {
          return const ConsentScreen(initialFlow: true);
        }
        return const HomeScreen();
      },
      loading: () =>
          const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (Object error, StackTrace stackTrace) =>
          Scaffold(body: Center(child: Text("初期化に失敗しました: $error"))),
    );
  }
}
