# Repository Guidelines

## Project Structure & Module Organization
- `lib/` contains application code, organized by layer:
  - `lib/ui/screens/` for Flutter screens.
  - `lib/domain/` for models, repository contracts, and use cases.
  - `lib/data/` for repository implementations, Hive storage, and network clients.
  - `lib/platform/` for Flutter-native channel integration.
  - `lib/app/providers.dart` for Riverpod wiring.
- `test/` contains unit tests (`*_test.dart`), currently focused on repository behavior.
- Platform runners and native code live in `android/`, `ios/`, `macos/`, `linux/`, `windows/`, and `web/`.
- CI workflows are in `.github/workflows/`.

## Build, Test, and Development Commands
- `flutter pub get` installs Dart/Flutter dependencies.
- `flutter analyze` runs static analysis using `flutter_lints`.
- `flutter test` runs all tests in `test/`.
- `flutter run -d <device>` launches locally (example: `flutter run -d chrome`).
- `flutter build apk --debug` builds Android debug APK (matches Android CI).
- `flutter build ipa --release --no-codesign` builds unsigned iOS artifacts (matches iOS CI).

## Coding Style & Naming Conventions
- Follow `analysis_options.yaml` (`package:flutter_lints/flutter.yaml`).
- Use `dart format .` before opening a PR.
- Use Dart naming conventions:
  - files/directories: `snake_case`
  - classes/enums: `PascalCase`
  - methods/variables: `lowerCamelCase`
  - constants: `lowerCamelCase` unless a plugin/API requires otherwise.
- Keep layer boundaries clear: UI should depend on domain abstractions, not direct storage/network details.

## Testing Guidelines
- Use `flutter_test` with `group`, `setUp`, `tearDown`, and focused `test(...)` names.
- Name tests by behavior, e.g., `"saves and returns newest first"`.
- Add or update tests for every domain/data logic change and bug fix.
- No enforced coverage threshold yet; prefer meaningful assertions over snapshot-style checks.

## Commit & Pull Request Guidelines
- This repository currently has no commit history, so no established commit pattern exists yet.
- Use Conventional Commits going forward (e.g., `feat: add consent reset flow`, `fix: sort history descending`).
- PRs should include:
  - concise summary and rationale
  - linked issue/ticket when available
  - test evidence (`flutter analyze`, `flutter test`)
  - screenshots or recordings for UI changes (`lib/ui/screens/`).

## Security & Configuration Notes
- Do not commit secrets, signing files, or private keys.
- iOS CI builds without code signing; handle production signing in secure CI/CD configuration.
