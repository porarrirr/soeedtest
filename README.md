# Speed Test (Flutter)

iOS / Android 対応の回線速度測定アプリです。  
設定画面から測定エンジンを選択できます。

## Features

- 初回同意画面（同意前は測定不可）
- 手動スピードテスト（DL/UL）
- 測定進捗表示（DL/ULフェーズ）
- ローカル履歴保存（Hive）
- 履歴一覧・詳細・簡易フィルタ（Wi-Fi / Mobile）
- 設定で同意撤回
- 測定エンジン選択（NDT7 / nPerf / OpenSpeedTest / Cloudflare / Speedtest CLI）
- 結果テキスト共有
- OpenSpeedTest / Cloudflare の WebView 実行
- Speedtest CLI（Androidのみ）
- デバッグログ保存・確認画面（設定 > デバッグログ）

## Architecture

- Flutter (Dart) + Riverpod
- Locate API: `https://locate.measurementlab.net/v2/nearest/ndt/ndt7`
- Flutter ⇄ Native
  - `MethodChannel`: `speedtest`
  - `EventChannel`: `speedtest_progress`
- Android: ndt7-client-android + Ookla CLI 実行（`ndt7` / `nperf` / `speedtestCli`）
- iOS: `NDT7` (ndt7-client-ios) CocoaPods（`ndt7` / `nperf`）

## Runtime Config (`--dart-define`)

- `SPEEDTEST_NPERF_ANDROID_CONFIG`
- `SPEEDTEST_NPERF_IOS_CONFIG`
- `SPEEDTEST_NPERF_WEB_URL`
- `SPEEDTEST_OPEN_SPEED_TEST_URL`
- `SPEEDTEST_CLOUDFLARE_URL`（未指定時: `https://speed.cloudflare.com`）
- `SPEEDTEST_CLI_PROVIDER_ORDER`（例: `ookla,python`）

## Android CLI Binary Provisioning

- `scripts/fetch_cli_binaries.sh` は Ookla CLI の Linux `.tgz` を展開し、`android/app/src/main/assets/cli/<abi>/speedtest`、`android/app/src/main/cli-binaries/<abi>/speedtest`、`android/app/src/main/jniLibs/<abi>/libspeedtest.so` に配置します。
- 必須: `OOKLA_CLI_AARCH64_TGZ_URL`
- 任意: `OOKLA_CLI_ARMHF_TGZ_URL`
- 任意: `OOKLA_CLI_X86_64_TGZ_URL`
- 任意: `OOKLA_CLI_X86_TGZ_URL`
- iOS では Speedtest CLI は未対応です。
- `android/app/src/main/cli-binaries/<abi>/speedtest` にバイナリを置くと、Androidビルド時に自動で `assets/cli` と `jniLibs` へコピーされ、APKへ同封されます。
- Android実行時は `nativeLibraryDir/libspeedtest.so` を優先実行します（`filesDir` 実行拒否端末対策）。
- `arm64-v8a` バイナリがない場合、Androidビルドは失敗します（開発時のみ `SPEEDTEST_ALLOW_MISSING_CLI=true` で回避可能）。

## Local Commands

```bash
flutter pub get
flutter analyze
flutter test
flutter build apk --debug
```

## GitHub Actions

- Android: `.github/workflows/android.yml`
  - `app-debug.apk` を Artifacts 出力
- iOS: `.github/workflows/ios.yml`
  - `flutter build ipa --release --no-codesign`
  - unsigned 相当成果物を Artifacts 出力

## Notes

- iOS workflow は署名なし成果物（no-codesign）です。
- 本番配布向けの署名付きIPAが必要な場合は、証明書とプロビジョニング設定を追加してください。
