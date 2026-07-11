/// Lightweight client-side mirror of app/core/moderation.py's
/// validate_display_name. This is a UX nicety for instant feedback only -
/// the backend is authoritative, and any mismatch between the two lists
/// just surfaces the backend's own rejection message when it happens.
class NameModerationResult {
  const NameModerationResult.valid() : error = null;
  const NameModerationResult.invalid(String message) : error = message;

  final String? error;

  bool get isValid => error == null;
}

final RegExp _digitRegExp = RegExp('[0-9]');
final RegExp _nonAlphaRegExp = RegExp('[^a-z]');

const Set<String> _bannedNameTitles = {
  'dr', 'doctor', 'prof', 'professor', 'mr', 'mrs', 'ms', 'miss',
  'sir', 'madam', 'esq', 'phd', 'md', 'rev', 'reverend',
  'capt', 'captain', 'col', 'colonel', 'sgt', 'sergeant',
  'lt', 'lieutenant', 'hon', 'honorable', 'judge', 'president', 'senator',
};

const Set<String> _bannedNameSubstrings = {
  'fuck', 'shit', 'bitch', 'asshole', 'bastard', 'cunt', 'dick',
  'piss', 'slut', 'whore', 'faggot', 'nigger', 'nigga', 'retard',
  'rape', 'molest', 'pedo', 'nazi', 'hitler', 'cock', 'pussy',
  'twat', 'wanker', 'motherfucker', 'dumbass', 'jackass',
};

NameModerationResult validateDisplayNameClientSide(String name) {
  if (_digitRegExp.hasMatch(name)) {
    return const NameModerationResult.invalid(
      "Display name can't contain numbers.",
    );
  }

  final tokens = name.toLowerCase().split(RegExp(r'\s+'));
  for (final token in tokens) {
    final stripped = token.replaceAll(_nonAlphaRegExp, '');
    if (_bannedNameTitles.contains(stripped)) {
      return const NameModerationResult.invalid(
        'Titles like "Dr." or "Professor" aren\'t allowed in display names.',
      );
    }
  }

  final normalized = name.toLowerCase().replaceAll(_nonAlphaRegExp, '');
  for (final word in _bannedNameSubstrings) {
    if (normalized.contains(word)) {
      return const NameModerationResult.invalid(
        "That name isn't allowed — please choose another.",
      );
    }
  }

  return const NameModerationResult.valid();
}
