import "dart:async";
import "dart:convert";

import "package:connectivity_plus/connectivity_plus.dart";
import "package:dio/dio.dart";
import "package:flutter/foundation.dart";
import "package:flutter/services.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:hive/hive.dart";
import "package:uuid/uuid.dart";

import "engine_availability.dart";
import "runtime_config.dart";
import "../data/network/locate_api_client.dart";
import "../data/repositories/consent_repository_impl.dart";
import "../data/repositories/debug_log_repository_impl.dart";
import "../data/repositories/history_repository_impl.dart";
import "../data/repositories/speed_test_engine_repository_impl.dart";
import "../data/storage/hive_boxes.dart";
import "../domain/models/connection_type.dart";
import "../domain/models/debug_log_entry.dart";
import "../domain/models/speed_test_engine.dart";
import "../domain/models/speed_test_result.dart";
import "../domain/repositories/consent_repository.dart";
import "../domain/repositories/debug_log_repository.dart";
import "../domain/repositories/history_repository.dart";
import "../domain/repositories/speed_test_engine_repository.dart";
import "../domain/usecases/run_speed_test_usecase.dart";
import "../platform/cli_speedtest_channel.dart";
import "../platform/nperf_channel.dart";
import "../platform/speedtest_channel.dart";

final Provider<Box<dynamic>> settingsBoxProvider = Provider<Box<dynamic>>((
  Ref ref,
) {
  throw UnimplementedError("settingsBoxProvider must be overridden in main()");
});

final Provider<Box<dynamic>> historyBoxProvider = Provider<Box<dynamic>>((
  Ref ref,
) {
  throw UnimplementedError("historyBoxProvider must be overridden in main()");
});

final Provider<Box<dynamic>> debugLogBoxProvider = Provider<Box<dynamic>>((
  Ref ref,
) {
  throw UnimplementedError("debugLogBoxProvider must be overridden in main()");
});

final Provider<Dio> dioProvider = Provider<Dio>((Ref ref) {
  return Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 20),
    ),
  );
});

final Provider<LocateApiClient> locateApiClientProvider =
    Provider<LocateApiClient>((Ref ref) {
      return LocateApiClient(ref.watch(dioProvider));
    });

final Provider<SpeedtestChannel> speedtestChannelProvider =
    Provider<SpeedtestChannel>((Ref ref) {
      return SpeedtestChannel();
    });

final Provider<NperfChannel> nperfChannelProvider = Provider<NperfChannel>((
  Ref ref,
) {
  return NperfChannel();
});

final Provider<CliSpeedtestChannel> cliSpeedtestChannelProvider =
    Provider<CliSpeedtestChannel>((Ref ref) {
      return CliSpeedtestChannel();
    });

final Provider<AppRuntimeConfig> runtimeConfigProvider =
    Provider<AppRuntimeConfig>((Ref ref) {
      return AppRuntimeConfig.fromEnvironment();
    });

final Provider<EngineAvailabilityService> engineAvailabilityServiceProvider =
    Provider<EngineAvailabilityService>((Ref ref) {
      return EngineAvailabilityService(
        isWeb: kIsWeb,
        platform: defaultTargetPlatform,
      );
    });

final Provider<Map<SpeedTestEngine, EngineAvailability>>
engineAvailabilityProvider = Provider<Map<SpeedTestEngine, EngineAvailability>>(
  (Ref ref) {
    final AppRuntimeConfig config = ref.watch(runtimeConfigProvider);
    final EngineAvailabilityService service = ref.watch(
      engineAvailabilityServiceProvider,
    );
    return <SpeedTestEngine, EngineAvailability>{
      for (final SpeedTestEngine engine in SpeedTestEngine.values)
        engine: service.availabilityFor(engine, config),
    };
  },
);

final Provider<List<String>> startupConfigIssuesProvider =
    Provider<List<String>>((Ref ref) {
      final Map<SpeedTestEngine, EngineAvailability> availability = ref.watch(
        engineAvailabilityProvider,
      );
      return availability.entries
          .where(
            (MapEntry<SpeedTestEngine, EngineAvailability> item) =>
                !item.value.available &&
                item.value.reason != null &&
                (item.value.reason!.contains("dart-define") ||
                    item.value.reason!.contains("URL")),
          )
          .map(
            (MapEntry<SpeedTestEngine, EngineAvailability> item) =>
                "${item.key.label}: ${item.value.reason}",
          )
          .toList();
    });

final Provider<Connectivity> connectivityProvider = Provider<Connectivity>((
  Ref ref,
) {
  return Connectivity();
});

final Provider<Uuid> uuidProvider = Provider<Uuid>((Ref ref) {
  return const Uuid();
});

final Provider<ConsentRepository> consentRepositoryProvider =
    Provider<ConsentRepository>((Ref ref) {
      return ConsentRepositoryImpl(ref.watch(settingsBoxProvider));
    });

final Provider<HistoryRepository> historyRepositoryProvider =
    Provider<HistoryRepository>((Ref ref) {
      return HistoryRepositoryImpl(ref.watch(historyBoxProvider));
    });

final Provider<SpeedTestEngineRepository> speedTestEngineRepositoryProvider =
    Provider<SpeedTestEngineRepository>((Ref ref) {
      return SpeedTestEngineRepositoryImpl(ref.watch(settingsBoxProvider));
    });

final Provider<DebugLogRepository> debugLogRepositoryProvider =
    Provider<DebugLogRepository>((Ref ref) {
      return DebugLogRepositoryImpl(ref.watch(debugLogBoxProvider));
    });

class ConsentSnapshot {
  const ConsentSnapshot({required this.granted, required this.prompted});

  final bool granted;
  final bool prompted;
}

class ConsentController extends StateNotifier<AsyncValue<ConsentSnapshot>> {
  ConsentController(this._repository) : super(const AsyncValue.loading()) {
    unawaited(load());
  }

  final ConsentRepository _repository;

  Future<void> load() async {
    state = const AsyncValue.loading();
    try {
      final bool granted = await _repository.isConsentGranted();
      final bool prompted = await _repository.hasSeenConsentPrompt();
      state = AsyncValue.data(
        ConsentSnapshot(granted: granted, prompted: prompted),
      );
    } catch (error, stackTrace) {
      state = AsyncValue.error(error, stackTrace);
    }
  }

  Future<void> accept() async {
    await _repository.setConsentGranted(true);
    await _repository.setHasSeenConsentPrompt(true);
    await load();
  }

  Future<void> decline() async {
    await _repository.setConsentGranted(false);
    await _repository.setHasSeenConsentPrompt(true);
    await load();
  }

  Future<void> revoke() async {
    await _repository.setConsentGranted(false);
    await _repository.setHasSeenConsentPrompt(true);
    await load();
  }
}

final StateNotifierProvider<ConsentController, AsyncValue<ConsentSnapshot>>
consentControllerProvider =
    StateNotifierProvider<ConsentController, AsyncValue<ConsentSnapshot>>((
      Ref ref,
    ) {
      return ConsentController(ref.watch(consentRepositoryProvider));
    });

class HistoryController
    extends StateNotifier<AsyncValue<List<SpeedTestResult>>> {
  HistoryController(this._repository) : super(const AsyncValue.loading()) {
    unawaited(reload());
  }

  final HistoryRepository _repository;

  Future<void> reload() async {
    state = const AsyncValue.loading();
    try {
      final List<SpeedTestResult> result = await _repository.getAll();
      state = AsyncValue.data(result);
    } catch (error, stackTrace) {
      state = AsyncValue.error(error, stackTrace);
    }
  }
}

final StateNotifierProvider<
  HistoryController,
  AsyncValue<List<SpeedTestResult>>
>
historyControllerProvider =
    StateNotifierProvider<HistoryController, AsyncValue<List<SpeedTestResult>>>(
      (Ref ref) {
        return HistoryController(ref.watch(historyRepositoryProvider));
      },
    );

class SpeedTestEngineController
    extends StateNotifier<AsyncValue<SpeedTestEngine>> {
  SpeedTestEngineController(this._repository)
    : super(const AsyncValue.loading()) {
    unawaited(load());
  }

  final SpeedTestEngineRepository _repository;

  Future<void> load() async {
    state = const AsyncValue.loading();
    try {
      final SpeedTestEngine selected = await _repository.getSelectedEngine();
      state = AsyncValue.data(selected);
    } catch (error, stackTrace) {
      state = AsyncValue.error(error, stackTrace);
    }
  }

  Future<void> setSelectedEngine(SpeedTestEngine engine) async {
    await _repository.setSelectedEngine(engine);
    state = AsyncValue.data(engine);
  }
}

final StateNotifierProvider<
  SpeedTestEngineController,
  AsyncValue<SpeedTestEngine>
>
speedTestEngineControllerProvider =
    StateNotifierProvider<
      SpeedTestEngineController,
      AsyncValue<SpeedTestEngine>
    >((Ref ref) {
      return SpeedTestEngineController(
        ref.watch(speedTestEngineRepositoryProvider),
      );
    });

class DebugLogController
    extends StateNotifier<AsyncValue<List<DebugLogEntry>>> {
  DebugLogController(this._repository, this._uuid)
    : super(const AsyncValue.loading()) {
    unawaited(reload());
  }

  static const int _maxEntries = 500;

  final DebugLogRepository _repository;
  final Uuid _uuid;

  Future<void> reload() async {
    state = const AsyncValue.loading();
    try {
      final List<DebugLogEntry> logs = await _repository.getAll();
      state = AsyncValue.data(logs);
    } catch (error, stackTrace) {
      state = AsyncValue.error(error, stackTrace);
    }
  }

  Future<void> append({
    required String level,
    required String category,
    required String message,
    String? details,
  }) async {
    final DebugLogEntry entry = DebugLogEntry(
      id: _uuid.v4(),
      timestampIso: DateTime.now().toIso8601String(),
      level: level,
      category: category,
      message: message,
      details: details,
    );
    await _repository.append(entry);

    final List<DebugLogEntry> current = state.valueOrNull ?? <DebugLogEntry>[];
    final List<DebugLogEntry> next = <DebugLogEntry>[
      entry,
      ...current,
    ].take(_maxEntries).toList();
    state = AsyncValue.data(next);
  }

  Future<void> clear() async {
    await _repository.clear();
    state = const AsyncValue.data(<DebugLogEntry>[]);
  }
}

final StateNotifierProvider<DebugLogController, AsyncValue<List<DebugLogEntry>>>
debugLogControllerProvider =
    StateNotifierProvider<DebugLogController, AsyncValue<List<DebugLogEntry>>>((
      Ref ref,
    ) {
      return DebugLogController(
        ref.watch(debugLogRepositoryProvider),
        ref.watch(uuidProvider),
      );
    });

final StateProvider<ConnectionType?> historyFilterProvider =
    StateProvider<ConnectionType?>((Ref ref) {
      return null;
    });

final Provider<AsyncValue<List<SpeedTestResult>>> filteredHistoryProvider =
    Provider<AsyncValue<List<SpeedTestResult>>>((Ref ref) {
      final AsyncValue<List<SpeedTestResult>> history = ref.watch(
        historyControllerProvider,
      );
      final ConnectionType? filter = ref.watch(historyFilterProvider);
      return history.whenData((List<SpeedTestResult> items) {
        if (filter == null) {
          return items;
        }
        return items
            .where((SpeedTestResult item) => item.connectionType == filter)
            .toList();
      });
    });

enum TestPhase { idle, download, upload, done, error, cancelled }

class SpeedTestState {
  const SpeedTestState({
    required this.phase,
    required this.running,
    required this.progress,
    this.currentMbps,
    this.errorMessage,
    this.result,
  });

  factory SpeedTestState.initial() =>
      const SpeedTestState(phase: TestPhase.idle, running: false, progress: 0);

  final TestPhase phase;
  final bool running;
  final double progress;
  final double? currentMbps;
  final String? errorMessage;
  final SpeedTestResult? result;

  SpeedTestState copyWith({
    TestPhase? phase,
    bool? running,
    double? progress,
    double? currentMbps,
    String? errorMessage,
    SpeedTestResult? result,
    bool clearError = false,
    bool clearResult = false,
  }) {
    return SpeedTestState(
      phase: phase ?? this.phase,
      running: running ?? this.running,
      progress: progress ?? this.progress,
      currentMbps: currentMbps ?? this.currentMbps,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      result: clearResult ? null : (result ?? this.result),
    );
  }
}

final Provider<RunSpeedTestUseCase> runSpeedTestUseCaseProvider =
    Provider<RunSpeedTestUseCase>((Ref ref) {
      return RunSpeedTestUseCase(
        locateApiClient: ref.watch(locateApiClientProvider),
        speedtestChannel: ref.watch(speedtestChannelProvider),
        cliSpeedtestChannel: ref.watch(cliSpeedtestChannelProvider),
        uuid: ref.watch(uuidProvider),
      );
    });

class SpeedTestController extends StateNotifier<SpeedTestState> {
  SpeedTestController(this.ref) : super(SpeedTestState.initial());

  final Ref ref;
  bool _cancelRequested = false;

  Future<void> _logEvent({
    required String level,
    required String category,
    required String message,
    Map<String, dynamic>? details,
  }) async {
    try {
      await ref
          .read(debugLogControllerProvider.notifier)
          .append(
            level: level,
            category: category,
            message: message,
            details: details == null
                ? null
                : const JsonEncoder.withIndent("  ").convert(details),
          );
    } catch (_) {
      // Logging failures should not affect test flow.
    }
  }

  String _stackSummary(StackTrace stackTrace) {
    final List<String> lines = stackTrace
        .toString()
        .split("\n")
        .map((String line) => line.trim())
        .where((String line) => line.isNotEmpty)
        .take(5)
        .toList();
    return lines.join("\n");
  }

  Map<String, dynamic>? _platformExceptionDetails(PlatformException exception) {
    final dynamic rawDetails = exception.details;
    if (rawDetails is Map<Object?, Object?>) {
      return rawDetails.map(
        (Object? key, Object? value) =>
            MapEntry((key ?? "unknown").toString(), value?.toString()),
      );
    }
    if (rawDetails == null) {
      return null;
    }
    return <String, dynamic>{"details": rawDetails.toString()};
  }

  String _mapNativeError(Object error) {
    if (error is PlatformException) {
      switch (error.code) {
        case "binary_missing":
          return "CLIバイナリが見つかりません。アプリを再ビルドして同梱設定を確認してください。";
        case "binary_not_executable":
          return "CLIバイナリを実行できません。ネイティブ同梱設定と端末互換性を確認してください。";
        case "cli_timeout":
          return "CLI測定がタイムアウトしました。通信環境を確認して再試行してください。";
        case "cli_failed":
          return "CLI測定が失敗しました。詳細: ${error.message}";
        case "cli_provider_unavailable":
          return "CLIプロバイダ設定が不正です。SPEEDTEST_CLI_PROVIDER_ORDER を確認してください。";
        case "json_parse_failed":
          return "CLI結果の解析に失敗しました。詳細: ${error.message}";
      }
    }
    return "測定中にエラーが発生しました: $error";
  }

  Future<ConnectionType?> _connectionOrNullIfOffline() async {
    final List<ConnectivityResult> results = await ref
        .read(connectivityProvider)
        .checkConnectivity();
    if (results.contains(ConnectivityResult.none)) {
      return null;
    }
    if (results.contains(ConnectivityResult.wifi)) {
      return ConnectionType.wifi;
    }
    if (results.contains(ConnectivityResult.mobile)) {
      return ConnectionType.mobile;
    }
    return ConnectionType.unknown;
  }

  Future<void> start() async {
    if (state.running) {
      unawaited(
        _logEvent(
          level: "warning",
          category: "speedtest",
          message: "start() called while already running",
        ),
      );
      return;
    }
    final ConsentSnapshot? consent = ref
        .read(consentControllerProvider)
        .valueOrNull;
    if (consent == null || !consent.granted) {
      unawaited(
        _logEvent(
          level: "warning",
          category: "speedtest",
          message: "Start blocked: user consent not granted",
        ),
      );
      state = state.copyWith(
        phase: TestPhase.error,
        running: false,
        errorMessage: "同意が必要です。設定または同意画面で同意してください。",
      );
      return;
    }

    final ConnectionType? connection = await _connectionOrNullIfOffline();
    if (connection == null) {
      unawaited(
        _logEvent(
          level: "warning",
          category: "speedtest",
          message: "Start blocked: device offline",
        ),
      );
      state = state.copyWith(
        phase: TestPhase.error,
        running: false,
        errorMessage: "オフラインのため測定できません。",
      );
      return;
    }
    final SpeedTestEngine selectedEngine =
        ref.read(speedTestEngineControllerProvider).valueOrNull ??
        SpeedTestEngine.ndt7;
    if (selectedEngine.isWebFlow) {
      unawaited(
        _logEvent(
          level: "warning",
          category: "speedtest",
          message: "Native start blocked for web flow engine",
          details: <String, dynamic>{"engine": selectedEngine.name},
        ),
      );
      state = state.copyWith(
        phase: TestPhase.error,
        running: false,
        errorMessage: "${selectedEngine.label} はWeb測定画面から実行してください。",
      );
      return;
    }
    final EngineAvailability availability =
        ref.read(engineAvailabilityProvider)[selectedEngine] ??
        const EngineAvailability.unavailable("設定を確認してください。");
    if (!availability.available) {
      unawaited(
        _logEvent(
          level: "warning",
          category: "speedtest",
          message: "Start blocked: engine unavailable",
          details: <String, dynamic>{
            "engine": selectedEngine.name,
            "reason": availability.reason,
          },
        ),
      );
      state = state.copyWith(
        phase: TestPhase.error,
        running: false,
        errorMessage:
            availability.reason ?? "${selectedEngine.label} は利用できません。",
      );
      return;
    }

    _cancelRequested = false;
    unawaited(
      _logEvent(
        level: "info",
        category: "speedtest",
        message: "Speed test started",
        details: <String, dynamic>{
          "engine": selectedEngine.name,
          "connectionType": connection.name,
        },
      ),
    );
    state = state.copyWith(
      phase: TestPhase.download,
      running: true,
      progress: 0,
      currentMbps: 0,
      clearError: true,
      clearResult: true,
    );

    try {
      String? lastProgressPhase;
      final SpeedTestResult result = await ref
          .read(runSpeedTestUseCaseProvider)
          .execute(
            connectionType: connection,
            engine: selectedEngine,
            config: ref.read(runtimeConfigProvider),
            onProgress: (NativeSpeedtestProgress progress) {
              final TestPhase phase = progress.phase == "upload"
                  ? TestPhase.upload
                  : TestPhase.download;
              if (lastProgressPhase != progress.phase) {
                lastProgressPhase = progress.phase;
                unawaited(
                  _logEvent(
                    level: "info",
                    category: "speedtest_progress",
                    message: "Phase changed: ${progress.phase}",
                    details: <String, dynamic>{
                      "engine": selectedEngine.name,
                      "progress": progress.progress,
                      "mbps": progress.mbps,
                    },
                  ),
                );
              }
              state = state.copyWith(
                phase: phase,
                running: true,
                progress: progress.progress.clamp(0, 1),
                currentMbps: progress.mbps,
              );
            },
          );
      await ref.read(historyRepositoryProvider).save(result);
      await ref.read(historyControllerProvider.notifier).reload();
      unawaited(
        _logEvent(
          level: "info",
          category: "speedtest",
          message: "Speed test completed",
          details: <String, dynamic>{
            "engine": selectedEngine.name,
            "downloadMbps": result.downloadMbps,
            "uploadMbps": result.uploadMbps,
            "serverInfo": result.serverInfo,
          },
        ),
      );
      state = state.copyWith(
        phase: TestPhase.done,
        running: false,
        progress: 1,
        currentMbps: null,
        result: result,
        clearError: true,
      );
    } on LocateApiException catch (error, stackTrace) {
      unawaited(
        _logEvent(
          level: "error",
          category: "speedtest",
          message: "Locate API failed",
          details: <String, dynamic>{
            "error": error.toString(),
            "stackTrace": _stackSummary(stackTrace),
          },
        ),
      );
      state = state.copyWith(
        phase: TestPhase.error,
        running: false,
        errorMessage: "測定先取得に失敗しました。リトライしてください。",
      );
    } on UnsupportedSpeedTestEngineException catch (error, stackTrace) {
      unawaited(
        _logEvent(
          level: "error",
          category: "speedtest",
          message: "Unsupported speed test engine",
          details: <String, dynamic>{
            "engine": error.engine.name,
            "reason": error.reason,
            "stackTrace": _stackSummary(stackTrace),
          },
        ),
      );
      state = state.copyWith(
        phase: TestPhase.error,
        running: false,
        errorMessage: error.reason ?? "${error.engine.label} は利用できません。",
      );
    } catch (error, stackTrace) {
      if (_cancelRequested) {
        unawaited(
          _logEvent(
            level: "info",
            category: "speedtest",
            message: "Speed test cancelled while running",
          ),
        );
        state = state.copyWith(
          phase: TestPhase.cancelled,
          running: false,
          errorMessage: "測定をキャンセルしました。",
        );
        return;
      }
      if (error is PlatformException) {
        unawaited(
          _logEvent(
            level: "error",
            category: "speedtest_native",
            message: "Native speed test failed (${error.code})",
            details: <String, dynamic>{
              "code": error.code,
              "message": error.message,
              "details": _platformExceptionDetails(error),
              "stackTrace": _stackSummary(stackTrace),
            },
          ),
        );
      } else {
        unawaited(
          _logEvent(
            level: "error",
            category: "speedtest",
            message: "Unhandled speed test exception",
            details: <String, dynamic>{
              "error": error.toString(),
              "stackTrace": _stackSummary(stackTrace),
            },
          ),
        );
      }
      state = state.copyWith(
        phase: TestPhase.error,
        running: false,
        errorMessage: _mapNativeError(error),
      );
    }
  }

  Future<void> cancel() async {
    if (!state.running) {
      unawaited(
        _logEvent(
          level: "warning",
          category: "speedtest",
          message: "cancel() called but no running test",
        ),
      );
      return;
    }
    _cancelRequested = true;
    await ref.read(runSpeedTestUseCaseProvider).cancel();
    unawaited(
      _logEvent(
        level: "info",
        category: "speedtest",
        message: "Cancel requested",
      ),
    );
    state = state.copyWith(
      phase: TestPhase.cancelled,
      running: false,
      errorMessage: "測定をキャンセルしました。",
    );
  }

  void clearResult() {
    state = state.copyWith(clearResult: true);
  }

  void clearError() {
    state = state.copyWith(clearError: true);
  }
}

final StateNotifierProvider<SpeedTestController, SpeedTestState>
speedTestControllerProvider =
    StateNotifierProvider<SpeedTestController, SpeedTestState>((Ref ref) {
      return SpeedTestController(ref);
    });

final FutureProvider<ConnectionType> currentConnectionTypeProvider =
    FutureProvider<ConnectionType>((Ref ref) async {
      final List<ConnectivityResult> results = await ref
          .watch(connectivityProvider)
          .checkConnectivity();
      if (results.contains(ConnectivityResult.wifi)) {
        return ConnectionType.wifi;
      }
      if (results.contains(ConnectivityResult.mobile)) {
        return ConnectionType.mobile;
      }
      return ConnectionType.unknown;
    });

Future<void> initStorage() async {
  await Hive.openBox<dynamic>(historyBoxName);
  await Hive.openBox<dynamic>(settingsBoxName);
  await Hive.openBox<dynamic>(debugLogBoxName);
}
