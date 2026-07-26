"""Display-name content moderation: profanity, titles, and digits.

This is the authoritative check - the Flutter client has a lightweight
mirror (mobile/lib/screens/home/tabs/profile/utils/name_moderation.dart)
for instant feedback, but any mismatch is resolved in this module's favor.
"""

import re

_DIGIT_RE = re.compile(r"[0-9]")
_NON_ALPHA_RE = re.compile(r"[^a-z]")

# Whole-token titles - matched per lowercased, non-alpha-stripped token, so
# a name only gets rejected when one of these appears as a standalone
# segment (e.g. "Dr Smith" or "Smith, MD"), not as a substring of an
# unrelated name (e.g. "Amrita", "Marina").
BANNED_NAME_TITLES: frozenset[str] = frozenset(
    {
        "dr",
        "doctor",
        "prof",
        "professor",
        "mr",
        "mrs",
        "ms",
        "miss",
        "sir",
        "madam",
        "esq",
        "phd",
        "md",
        "rev",
        "reverend",
        "capt",
        "captain",
        "col",
        "colonel",
        "sgt",
        "sergeant",
        "lt",
        "lieutenant",
        "hon",
        "honorable",
        "judge",
        "president",
        "senator",
    },
)

# Curated lowercase profanity/offensive-language list, matched as a
# substring scan against the name with all non-alpha characters stripped
# (catches concatenation evasion like "JohnFuckSmith"). This accepts the
# known "Scunthorpe problem" tradeoff (rare innocent collisions) in
# exchange for simplicity - this list can be hand-tuned over time without
# a client release since it lives entirely server-side.
BANNED_NAME_SUBSTRINGS: frozenset[str] = frozenset(
    {
        "fuck",
        "shit",
        "bitch",
        "asshole",
        "bastard",
        "cunt",
        "dick",
        "piss",
        "slut",
        "whore",
        "faggot",
        "nigger",
        "nigga",
        "retard",
        "rape",
        "molest",
        "pedo",
        "nazi",
        "hitler",
        "cock",
        "pussy",
        "twat",
        "wanker",
        "motherfucker",
        "dumbass",
        "jackass",
    },
)


class NameModerationError(Exception):
    """Raised when a proposed display name fails moderation.

    `detail` is a plain human-readable string, safe to pass straight into
    HTTPException(detail=...) - never raised via a Pydantic validator, so
    it always reaches the client as a JSON string rather than FastAPI's
    default 422 list-of-errors shape.
    """

    def __init__(self, reason: str, detail: str) -> None:
        """Initialize NameModerationError with rejection reason and detailed message.

        Args:
            reason: Category of moderation failure ("digits", "title", or "profanity").
            detail: Safe, human-readable error explanation for client display.
        """
        self.reason = reason  # "digits" | "title" | "profanity"
        self.detail = detail
        super().__init__(detail)


def validate_display_name(name: str) -> None:
    """Validates a proposed display name string against moderation rules.

    Checks for prohibited digits, honorary titles, and offensive substrings.

    Args:
        name: Proposed display name string to validate.

    Raises:
        NameModerationError: If name contains digits, title tokens, or profanity substrings.
    """
    if _DIGIT_RE.search(name):
        raise NameModerationError(
            "digits",
            "Display name can't contain numbers.",
        )

    tokens = name.lower().split()
    for token in tokens:
        stripped = _NON_ALPHA_RE.sub("", token)
        if stripped in BANNED_NAME_TITLES:
            raise NameModerationError(
                "title",
                'Titles like "Dr." or "Professor" aren\'t allowed in display names.',
            )

    normalized = _NON_ALPHA_RE.sub("", name.lower())
    for word in BANNED_NAME_SUBSTRINGS:
        if word in normalized:
            raise NameModerationError(
                "profanity",
                "That name isn't allowed - please choose another.",
            )

