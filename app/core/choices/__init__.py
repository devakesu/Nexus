"""Predefined validation choice sets and taxonomy mappings.

Contains canonical sets for user profile options including gender identities, sexualities,
pronouns, spoken languages, supported causes, pets, lifestyle habits, and structured
interest taxonomies. All symbols are re-exported here for backward compatibility.
"""

from app.core.choices.interests import VALID_INTERESTS
from app.core.choices.profile_options import (
    CAUSES_SUPPORTED_CHOICES,
    CHILDREN_PLANS_CHOICES,
    DRINKING_CHOICES,
    GENDER_CHOICES,
    LANGUAGES_CHOICES,
    PETS_CHOICES,
    PRONOUNS_CHOICES,
    RELIGIOUS_BELIEFS_CHOICES,
    SEXUALITY_CHOICES,
    SMOKING_CHOICES,
)

__all__ = [
    "CAUSES_SUPPORTED_CHOICES",
    "CHILDREN_PLANS_CHOICES",
    "DRINKING_CHOICES",
    "GENDER_CHOICES",
    "LANGUAGES_CHOICES",
    "PETS_CHOICES",
    "PRONOUNS_CHOICES",
    "RELIGIOUS_BELIEFS_CHOICES",
    "SEXUALITY_CHOICES",
    "SMOKING_CHOICES",
    "VALID_INTERESTS",
]
