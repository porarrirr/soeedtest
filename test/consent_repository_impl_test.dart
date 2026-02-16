import "package:flutter_test/flutter_test.dart";
import "package:hive/hive.dart";
import "package:hive_test/hive_test.dart";
import "package:iosandrodispeedtesy/data/repositories/consent_repository_impl.dart";

void main() {
  group("ConsentRepositoryImpl", () {
    late Box<dynamic> settingsBox;
    late ConsentRepositoryImpl repository;

    setUp(() async {
      await setUpTestHive();
      settingsBox = await Hive.openBox<dynamic>("settings_test_box");
      repository = ConsentRepositoryImpl(settingsBox);
    });

    tearDown(() async {
      await settingsBox.deleteFromDisk();
      await tearDownTestHive();
    });

    test("defaults to not granted and not prompted", () async {
      expect(await repository.isConsentGranted(), isFalse);
      expect(await repository.hasSeenConsentPrompt(), isFalse);
    });

    test("stores consent and prompted flags", () async {
      await repository.setConsentGranted(true);
      await repository.setHasSeenConsentPrompt(true);

      expect(await repository.isConsentGranted(), isTrue);
      expect(await repository.hasSeenConsentPrompt(), isTrue);
    });
  });
}
