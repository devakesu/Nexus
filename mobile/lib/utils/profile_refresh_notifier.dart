import 'dart:async';

/// A simple broadcast notifier to request profile tab data refreshes when changes
/// occur on settings or consent withdrawal screens.
abstract final class ProfileRefreshNotifier {
  static final StreamController<void> _controller =
      StreamController<void>.broadcast();

  static Stream<void> get stream => _controller.stream;

  static void notifyChanged() {
    _controller.add(null);
  }
}
