/// Returns a sensible grid column count for the given available width.
///
/// Nexus's card grids (Likes, Waves, Handshakes, onboarding branch picker)
/// were fixed at a phone-only column count regardless of viewport, so
/// tablets and unfolded foldables stretched cards awkwardly wide instead of
/// gaining columns. Wrap the grid in a `LayoutBuilder` and pass
/// `constraints.maxWidth` here instead of hardcoding `crossAxisCount`.
int gridColumnsForWidth(double width, {int base = 2}) {
  if (width >= 900) return base + 2;
  if (width >= 600) return base + 1;
  return base;
}
