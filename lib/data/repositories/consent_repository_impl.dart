import "package:hive/hive.dart";

import "../../domain/repositories/consent_repository.dart";

class ConsentRepositoryImpl implements ConsentRepository {
  ConsentRepositoryImpl(this._settingsBox);

  static const String consentKey = "consent_granted";
  static const String promptedKey = "consent_prompted";

  final Box<dynamic> _settingsBox;

  @override
  Future<bool> isConsentGranted() async {
    return (_settingsBox.get(consentKey) as bool?) ?? false;
  }

  @override
  Future<void> setConsentGranted(bool granted) async {
    await _settingsBox.put(consentKey, granted);
  }

  @override
  Future<bool> hasSeenConsentPrompt() async {
    return (_settingsBox.get(promptedKey) as bool?) ?? false;
  }

  @override
  Future<void> setHasSeenConsentPrompt(bool seen) async {
    await _settingsBox.put(promptedKey, seen);
  }
}
