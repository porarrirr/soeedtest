abstract class ConsentRepository {
  Future<bool> isConsentGranted();

  Future<void> setConsentGranted(bool granted);

  Future<bool> hasSeenConsentPrompt();

  Future<void> setHasSeenConsentPrompt(bool seen);
}
