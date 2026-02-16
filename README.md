# Speed Test (Flutter)

iOS / Android 対応の回線速度測定アプリです。  
設定画面から測定エンジンを選択できます（現状は M-Lab NDT7 が実装済み）。

## Features

- 初回同意画面（同意前は測定不可）
- 手動スピードテスト（DL/UL）
- 測定進捗表示（DL/ULフェーズ）
- ローカル履歴保存（Hive）
- 履歴一覧・詳細・簡易フィルタ（Wi-Fi / Mobile）
- 設定で同意撤回
- 測定エンジン選択（NDT7 / nPerf / OpenSpeedTest / Cloudflare）
- 結果テキスト共有

## Architecture

- Flutter (Dart) + Riverpod
- Locate API: `https://locate.measurementlab.net/v2/nearest/ndt/ndt7`
- Flutter ⇄ Native
  - `MethodChannel`: `speedtest`
  - `EventChannel`: `speedtest_progress`
- Android: ndt7-client-android の実装を組み込み（`ndt7`）
- iOS: `NDT7` (ndt7-client-ios) CocoaPods（`ndt7`）

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
