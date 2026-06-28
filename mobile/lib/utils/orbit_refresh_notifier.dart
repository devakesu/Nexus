import 'dart:async';

/// Broadcast stream that fires whenever any orbit tab changes its active state.
/// The boolean payload is `true` when an orbit was activated, `false` when
/// deactivated.  Broadcast streams always deliver — unlike ValueNotifier, they
/// don't skip when the same direction fires twice in a row.
class OrbitRefreshNotifier {
  OrbitRefreshNotifier._();

  static final StreamController<bool> _controller =
      StreamController<bool>.broadcast();

  static Stream<bool> get stream => _controller.stream;

  /// Call after successfully setting is_X_active = true.
  static void notifyActivated() => _controller.add(true);

  /// Call after successfully setting is_X_active = false (also used by
  /// Pause Matching which deactivates all three at once).
  static void notifyDeactivated() => _controller.add(false);
}
