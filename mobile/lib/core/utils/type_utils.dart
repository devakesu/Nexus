import 'package:intl/intl.dart';

/// Formats build timestamp string into human readable string.
String formatBuildTimestamp(String timestamp) {
  if (timestamp.isEmpty || timestamp == 'local') {
    return 'Local build';
  }
  try {
    final parsed = DateTime.tryParse(timestamp);
    if (parsed != null) {
      return DateFormat('MMM d, y HH:mm').format(parsed.toLocal());
    }
    final millis = int.tryParse(timestamp);
    if (millis != null) {
      final dt = DateTime.fromMillisecondsSinceEpoch(millis);
      return DateFormat('MMM d, y HH:mm').format(dt.toLocal());
    }
  } on Object catch (_) {}
  return timestamp;
}
