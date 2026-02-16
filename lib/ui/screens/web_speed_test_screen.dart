import "dart:async";

import "package:connectivity_plus/connectivity_plus.dart";
import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:webview_flutter/webview_flutter.dart";

import "../../app/providers.dart";
import "../../domain/models/connection_type.dart";
import "../../domain/models/speed_test_engine.dart";
import "../../domain/models/speed_test_result.dart";
import "../../platform/web_speedtest_bridge.dart";
import "../../platform/web_speedtest_scripts.dart";
import "result_screen.dart";

class WebSpeedTestScreen extends ConsumerStatefulWidget {
  const WebSpeedTestScreen({super.key, required this.engine});

  final SpeedTestEngine engine;

  @override
  ConsumerState<WebSpeedTestScreen> createState() => _WebSpeedTestScreenState();
}

class _WebSpeedTestScreenState extends ConsumerState<WebSpeedTestScreen> {
  late final WebViewController _controller;
  bool _completed = false;
  bool _loading = true;
  String _phaseLabel = "測定準備中";
  double _progress = 0;
  double _currentMbps = 0;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    final Uri? target = _targetUri();
    if (target == null) {
      _errorMessage = "URL設定が不正です。";
      _loading = false;
      return;
    }
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..addJavaScriptChannel(
        "SpeedTestBridge",
        onMessageReceived: _onBridgeMessage,
      )
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (String _) async {
            await _controller.runJavaScript(baseBridgeScript);
            final String script = buildWebStartScript(widget.engine);
            if (script.isNotEmpty) {
              await _controller.runJavaScript(script);
            }
            setState(() {
              _loading = false;
            });
          },
        ),
      )
      ..loadRequest(target);
  }

  Uri? _targetUri() {
    final config = ref.read(runtimeConfigProvider);
    final String? raw = switch (widget.engine) {
      SpeedTestEngine.nperf => config.nperfWebUrl,
      SpeedTestEngine.openSpeedTest => config.openSpeedTestUrl,
      SpeedTestEngine.cloudflareWeb => config.cloudflareUrl,
      _ => null,
    };
    if (raw == null) {
      return null;
    }
    return Uri.tryParse(raw);
  }

  Future<ConnectionType?> _connectionTypeOrNull() async {
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

  Future<void> _onBridgeMessage(JavaScriptMessage message) async {
    if (_completed) {
      return;
    }
    final WebSpeedtestBridgeMessage parsed;
    try {
      parsed = WebSpeedtestBridgeMessage.tryParse(message.message);
    } catch (_) {
      return;
    }
    if (!mounted) {
      return;
    }
    if (parsed.type == "progress") {
      setState(() {
        _phaseLabel = parsed.phase == "upload" ? "UL測定中" : "DL測定中";
        _progress = (parsed.progress ?? _progress).clamp(0, 1);
        _currentMbps = parsed.mbps ?? _currentMbps;
      });
      return;
    }
    if (parsed.type == "error") {
      setState(() {
        _errorMessage = parsed.error ?? "Web測定でエラーが発生しました。";
      });
      return;
    }
    if (parsed.type != "result") {
      return;
    }

    final double download = parsed.downloadMbps ?? 0;
    final double upload = parsed.uploadMbps ?? 0;
    if (download <= 0 && upload <= 0) {
      setState(() {
        _errorMessage = "測定結果を取得できませんでした。";
      });
      return;
    }
    _completed = true;

    final ConnectionType? connection = await _connectionTypeOrNull();
    if (!mounted) {
      return;
    }
    if (connection == null) {
      setState(() {
        _errorMessage = "オフラインのため結果を保存できません。";
      });
      return;
    }
    final SpeedTestResult result = SpeedTestResult(
      id: ref.read(uuidProvider).v4(),
      timestampIso: DateTime.now().toIso8601String(),
      downloadMbps: download,
      uploadMbps: upload,
      connectionType: connection,
      engine: widget.engine,
      serverInfo: parsed.serverInfo,
    );
    await ref.read(historyRepositoryProvider).save(result);
    await ref.read(historyControllerProvider.notifier).reload();
    if (!mounted) {
      return;
    }
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(builder: (_) => ResultScreen(result: result)),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_errorMessage != null) {
      return Scaffold(
        appBar: AppBar(title: Text(widget.engine.label)),
        body: Center(child: Text(_errorMessage!)),
      );
    }
    return Scaffold(
      appBar: AppBar(title: Text(widget.engine.label)),
      body: Column(
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Text(_phaseLabel, textAlign: TextAlign.center),
                const SizedBox(height: 8),
                LinearProgressIndicator(
                  value: _progress > 0 ? _progress : null,
                ),
                const SizedBox(height: 8),
                Text(
                  "${_currentMbps.toStringAsFixed(1)} Mbps",
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: Stack(
              children: <Widget>[
                WebViewWidget(controller: _controller),
                if (_loading) const Center(child: CircularProgressIndicator()),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
