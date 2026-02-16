import "dart:async";

import "package:connectivity_plus/connectivity_plus.dart";
import "package:dio/dio.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:hive/hive.dart";
import "package:uuid/uuid.dart";

import "../data/network/locate_api_client.dart";
import "../data/repositories/consent_repository_impl.dart";
import "../data/repositories/history_repository_impl.dart";
import "../data/repositories/speed_test_engine_repository_impl.dart";
import "../data/storage/hive_boxes.dart";
import "../domain/models/connection_type.dart";
import "../domain/models/speed_test_engine.dart";
import "../domain/models/speed_test_result.dart";
import "../domain/repositories/consent_repository.dart";
import "../domain/repositories/history_repository.dart";
import "../domain/repositories/speed_test_engine_repository.dart";
import "../domain/usecases/run_speed_test_usecase.dart";
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
        uuid: ref.watch(uuidProvider),
      );
    });

class SpeedTestController extends StateNotifier<SpeedTestState> {
  SpeedTestController(this.ref) : super(SpeedTestState.initial());

  final Ref ref;
  bool _cancelRequested = false;

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
      return;
    }
    final ConsentSnapshot? consent = ref
        .read(consentControllerProvider)
        .valueOrNull;
    if (consent == null || !consent.granted) {
      state = state.copyWith(
        phase: TestPhase.error,
        running: false,
        errorMessage: "同意が必要です。設定または同意画面で同意してください。",
      );
      return;
    }

    final ConnectionType? connection = await _connectionOrNullIfOffline();
    if (connection == null) {
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
    if (!selectedEngine.isImplemented) {
      state = state.copyWith(
        phase: TestPhase.error,
        running: false,
        errorMessage: "${selectedEngine.label} は未対応です。設定で実装済みエンジンを選択してください。",
      );
      return;
    }

    _cancelRequested = false;
    state = state.copyWith(
      phase: TestPhase.download,
      running: true,
      progress: 0,
      currentMbps: 0,
      clearError: true,
      clearResult: true,
    );

    try {
      final SpeedTestResult result = await ref
          .read(runSpeedTestUseCaseProvider)
          .execute(
            connectionType: connection,
            engine: selectedEngine,
            onProgress: (NativeSpeedtestProgress progress) {
              final TestPhase phase = progress.phase == "upload"
                  ? TestPhase.upload
                  : TestPhase.download;
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
      state = state.copyWith(
        phase: TestPhase.done,
        running: false,
        progress: 1,
        currentMbps: null,
        result: result,
        clearError: true,
      );
    } on LocateApiException catch (_) {
      state = state.copyWith(
        phase: TestPhase.error,
        running: false,
        errorMessage: "測定先取得に失敗しました。リトライしてください。",
      );
    } on UnsupportedSpeedTestEngineException catch (error) {
      state = state.copyWith(
        phase: TestPhase.error,
        running: false,
        errorMessage: "${error.engine.label} は未対応です。設定で実装済みエンジンを選択してください。",
      );
    } catch (error) {
      if (_cancelRequested) {
        state = state.copyWith(
          phase: TestPhase.cancelled,
          running: false,
          errorMessage: "測定をキャンセルしました。",
        );
        return;
      }
      state = state.copyWith(
        phase: TestPhase.error,
        running: false,
        errorMessage: "測定中にエラーが発生しました: $error",
      );
    }
  }

  Future<void> cancel() async {
    if (!state.running) {
      return;
    }
    _cancelRequested = true;
    await ref.read(runSpeedTestUseCaseProvider).cancel();
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
}
