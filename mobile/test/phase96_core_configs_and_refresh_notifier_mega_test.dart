import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/core/config/app_config.dart';
import 'package:nexus/core/config/filter_options.dart';
import 'package:nexus/core/utils/app_refresh_notifier.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Phase 96 - Core Configs & Refresh Notifier Mega Tests', () {
    test(
      'AppRefreshNotifier and compatibility aliases stream events',
      () async {
        bool? orbitState;
        final sub1 = AppRefreshNotifier.orbitStream.listen((state) {
          orbitState = state;
        });

        var profileChanged = false;
        final sub2 = AppRefreshNotifier.profileStream.listen((_) {
          profileChanged = true;
        });

        OrbitRefreshNotifier.notifyActivated();
        await Future<void>.delayed(const Duration(milliseconds: 10));
        expect(orbitState, isTrue);

        OrbitRefreshNotifier.notifyDeactivated();
        await Future<void>.delayed(const Duration(milliseconds: 10));
        expect(orbitState, isFalse);

        ProfileRefreshNotifier.notifyChanged();
        await Future<void>.delayed(const Duration(milliseconds: 10));
        expect(profileChanged, isTrue);

        await sub1.cancel();
        await sub2.cancel();
      },
    );

    test('FilterOptions constants and lists validation', () {
      expect(interestsCategories.isNotEmpty, isTrue);
      expect(interestsCategories.first.parents.isNotEmpty, isTrue);
    });

    test('AppConfig environments and base URLs', () {
      expect(AppConfig.current.backendUrl.isNotEmpty, isTrue);
    });
  });
}
