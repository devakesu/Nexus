"""Predefined validation choice sets and taxonomy mappings.

Contains canonical sets for user profile options including gender identities, sexualities,
pronouns, spoken languages, supported causes, pets, lifestyle habits, and structured
interest taxonomies. All symbols are re-exported here for backward compatibility.
"""

from app.core.choices.discovery_options import (
    DATING_FOR_OPTIONS,
    FILTER_SUB_INTERESTS,
    LOOKING_FOR_OPTIONS,
    PARTNER_VALUES_CHOICES,
    SEARCH_BUCKETS,
    TECH_SKILLS_CHOICES,
)
from app.core.choices.exporter import export_choices_dict, export_to_file
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
    "DATING_FOR_OPTIONS",
    "DRINKING_CHOICES",
    "FILTER_SUB_INTERESTS",
    "GENDER_CHOICES",
    "LANGUAGES_CHOICES",
    "LOOKING_FOR_OPTIONS",
    "PARTNER_VALUES_CHOICES",
    "PETS_CHOICES",
    "PRONOUNS_CHOICES",
    "RELIGIOUS_BELIEFS_CHOICES",
    "SEARCH_BUCKETS",
    "SEXUALITY_CHOICES",
    "SMOKING_CHOICES",
    "TECH_SKILLS_CHOICES",
    "VALID_INTERESTS",
    "export_choices_dict",
    "export_to_file",
]
