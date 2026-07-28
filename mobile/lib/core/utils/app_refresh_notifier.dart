import 'dart:async';

/// Unified app refresh notifier replacing individual single-purpose notifier classes.
abstract final class AppRefreshNotifier {
  static final StreamController<bool> _orbitController =
      StreamController<bool>.broadcast();
  static final StreamController<void> _profileController =
      StreamController<void>.broadcast();

  static Stream<bool> get orbitStream => _orbitController.stream;
  static Stream<void> get profileStream => _profileController.stream;

  /// Notify orbit activation (true) or deactivation (false).
  static void notifyOrbitStateChanged({required bool active}) {
    _orbitController.add(active);
  }

  /// Notify profile data refresh requested.
  static void notifyProfileChanged() {
    _profileController.add(null);
  }
}

/// Backward compatibility class alias for OrbitRefreshNotifier
abstract final class OrbitRefreshNotifier {
  static Stream<bool> get stream => AppRefreshNotifier.orbitStream;
  static void notifyActivated() =>
      AppRefreshNotifier.notifyOrbitStateChanged(active: true);
  static void notifyDeactivated() =>
      AppRefreshNotifier.notifyOrbitStateChanged(active: false);
}

/// Backward compatibility class alias for ProfileRefreshNotifier
abstract final class ProfileRefreshNotifier {
  static Stream<void> get stream => AppRefreshNotifier.profileStream;
  static void notifyChanged() => AppRefreshNotifier.notifyProfileChanged();
}
