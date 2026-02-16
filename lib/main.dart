import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:hive_flutter/hive_flutter.dart";

import "app/providers.dart";
import "data/storage/hive_boxes.dart";
import "ui/screens/app_gate_screen.dart";

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Hive.initFlutter();
  await initStorage();
  final historyBox = Hive.box<dynamic>(historyBoxName);
  final settingsBox = Hive.box<dynamic>(settingsBoxName);

  runApp(
    ProviderScope(
      overrides: <Override>[
        historyBoxProvider.overrideWithValue(historyBox),
        settingsBoxProvider.overrideWithValue(settingsBox),
      ],
      child: const SpeedTestApp(),
    ),
  );
}

class SpeedTestApp extends StatelessWidget {
  const SpeedTestApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: "Speed Test",
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF006D77)),
      ),
      home: const AppGateScreen(),
    );
  }
}
