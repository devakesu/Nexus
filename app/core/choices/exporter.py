"""Choice sets exporter.

Serializes canonical Python choice sets from app.core.choices into the
JSON asset mobile/assets/config/choices.json for Flutter client consumption.
"""

from __future__ import annotations

import json
from pathlib import Path
from typing import Any

from app.core.choices.discovery_options import (
    DATING_FOR_OPTIONS,
    FILTER_SUB_INTERESTS,
    LOOKING_FOR_OPTIONS,
    PARTNER_VALUES_CHOICES,
    SEARCH_BUCKETS,
    TECH_SKILLS_CHOICES,
)
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

# Ordered list mappings matching canonical UI definitions
GENDERS_ORDERED: list[str] = [
    "Man",
    "Woman",
    "Cisgender Man",
    "Cisgender Woman",
    "Transgender Man",
    "Transgender Woman",
    "Transgender",
    "Non-binary",
    "Genderqueer",
    "Genderfluid",
    "Agender",
    "Gender Non-Conforming",
    "Androgynous",
    "Neutrois",
    "Maverique",
    "Bigender",
    "Trigender",
    "Multigender",
    "Pangender",
    "Demiboy",
    "Demigirl",
    "Demi-non-binary",
    "Two-Spirit",
    "Third Gender",
    "Intersex",
    "Xenogender",
    "Queer",
    "Questioning",
    "Prefer not to say",
]

SEXUALITIES_ORDERED: list[str] = [
    "Straight / Heterosexual",
    "Gay",
    "Lesbian",
    "Bisexual",
    "Pansexual",
    "Omnisexual",
    "Polysexual",
    "Asexual",
    "Graysexual",
    "Demisexual",
    "Cupiosexual",
    "Lithosexual",
    "Aromantic",
    "Aroace",
    "Greyromantic",
    "Demiromantic",
    "Sapphic",
    "Achillean",
    "Queer",
    "Fluid",
    "Skoliosexual",
    "Questioning",
    "Prefer not to say",
]

PRONOUNS_ORDERED: list[str] = [
    "he/him",
    "she/her",
    "they/them",
    "he/they",
    "she/they",
    "he/she",
    "he/she/they",
    "xe/xem",
    "ze/zir",
    "ze/hir",
    "ey/em",
    "fae/faer",
    "per/per",
    "e/em",
    "ve/ver",
    "it/its",
    "any/all",
    "Use my name",
    "Prefer not to say",
]

LANGUAGES_ORDERED: list[str] = [
    "English",
    "Mandarin Chinese",
    "Hindi",
    "Spanish",
    "French",
    "Arabic",
    "Bengali",
    "Portuguese",
    "Russian",
    "Urdu",
    "Indonesian / Malay",
    "German",
    "Japanese",
    "Telugu",
    "Marathi",
    "Tamil",
    "Cantonese",
    "Korean",
    "Vietnamese",
    "Turkish",
    "Italian",
    "Punjabi",
    "Gujarati",
    "Persian / Farsi",
    "Polish",
    "Ukrainian",
    "Kannada",
    "Malayalam",
    "Burmese",
    "Thai",
    "Sinhala",
    "Nepali",
    "Tagalog / Filipino",
    "Javanese",
    "Sundanese",
    "Wu Chinese",
    "Swahili",
    "Hausa",
    "Yoruba",
    "Igbo",
    "Amharic",
    "Oromo",
    "Tigrinya",
    "Somali",
    "Zulu",
    "Xhosa",
    "Shona",
    "Kinyarwanda",
    "Lingala",
    "Fula",
    "Wolof",
    "Twi / Akan",
    "Nyanja / Chewa",
    "Sotho",
    "Tswana",
    "Afrikaans",
    "Pashto",
    "Dari",
    "Sindhi",
    "Maithili",
    "Assamese",
    "Khmer",
    "Lao",
    "Uzbek",
    "Kazakh",
    "Kyrgyz",
    "Turkmen",
    "Tajik",
    "Azerbaijani",
    "Georgian",
    "Armenian",
    "Kurdish",
    "Mongolian",
    "Tibetan",
    "Uyghur",
    "Dutch",
    "Greek",
    "Swedish",
    "Norwegian",
    "Danish",
    "Finnish",
    "Hungarian",
    "Romanian",
    "Czech",
    "Slovak",
    "Bulgarian",
    "Serbian",
    "Croatian",
    "Bosnian",
    "Slovenian",
    "Macedonian",
    "Albanian",
    "Lithuanian",
    "Latvian",
    "Estonian",
    "Belarusian",
    "Catalan",
    "Galician",
    "Basque",
    "Welsh",
    "Irish",
    "Scottish Gaelic",
    "Icelandic",
    "Maltese",
    "Luxembourgish",
    "Hebrew",
    "Malagasy",
    "Fijian",
    "Māori",
    "Hawaiian",
    "Samoan",
    "Tongan",
    "American Sign Language (ASL)",
    "British Sign Language (BSL)",
    "International Sign",
    "Esperanto",
    "Latin",
    "Other",
]

DRINKING_ORDERED: list[str] = [
    "Never",
    "Occasionally",
    "Socially",
    "Regularly",
]

SMOKING_ORDERED: list[str] = [
    "Never",
    "Occasionally",
    "Socially",
    "Regularly",
]

CHILDREN_PLANS_ORDERED: list[str] = [
    "Want kids",
    "Don't want kids",
    "Undecided",
    "Not specified",
]

RELIGIOUS_BELIEFS_ORDERED: list[str] = [
    "Atheist",
    "Agnostic",
    "Secular Humanist",
    "Deist",
    "Pantheist",
    "Spiritual but not religious",
    "New Age",
    "Pagan / Wiccan",
    "Christian",
    "Catholic",
    "Protestant",
    "Orthodox Christian",
    "Muslim (Sunni)",
    "Muslim (Shia)",
    "Jewish",
    "Jewish (Orthodox)",
    "Hindu",
    "Buddhist",
    "Sikh",
    "Jain",
    "Taoist",
    "Shinto",
    "Confucianist",
    "Bahá'í",
    "Zoroastrian",
    "Rastafari",
    "Druze",
    "Yazidi",
    "Unitarian Universalist",
    "Indigenous / Traditional",
    "Animist",
    "Other",
    "Prefer not to say",
]

CAUSES_SUPPORTED_ORDERED: list[str] = [
    "Climate Action",
    "Renewable Energy",
    "Biodiversity & Wildlife",
    "Ocean Conservation",
    "Deforestation & Reforestation",
    "Clean Air",
    "Clean Water & Sanitation",
    "Zero Waste & Recycling",
    "Sustainable Agriculture",
    "Animal Protection",
    "Veganism & Animal Rights",
    "Human Rights",
    "Gender Equality",
    "LGBTQ+ Rights",
    "Racial Justice",
    "Indigenous Rights",
    "Disability Rights",
    "Children's Rights",
    "Elder Care",
    "Refugee & Migrant Rights",
    "Anti-Trafficking",
    "Prison Reform",
    "Voting Rights & Democracy",
    "Mental Health Advocacy",
    "Global Health",
    "Reproductive Rights",
    "Substance Abuse & Recovery",
    "Nutrition & Food Security",
    "Rare Disease Research",
    "Education Access",
    "Digital Literacy",
    "Economic Development",
    "Poverty Alleviation",
    "Fair Trade",
    "Entrepreneurship & Small Business",
    "Financial Inclusion",
    "Scientific Research",
    "Tech Ethics",
    "AI Safety",
    "Open Source & Open Knowledge",
    "Space Exploration",
    "Arts & Culture Preservation",
    "Community Development",
    "Volunteerism",
    "Religious Freedom",
    "Free Speech & Press Freedom",
    "Disaster Relief",
    "Hunger & Food Banks",
    "Homelessness",
    "Peace & Conflict Resolution",
    "Nuclear Disarmament",
]

PETS_ORDERED: list[str] = [
    "Dog",
    "Cat",
    "Rabbit",
    "Ferret",
    "Hamster",
    "Guinea Pig",
    "Gerbil",
    "Mouse",
    "Rat",
    "Chinchilla",
    "Hedgehog",
    "Sugar Glider",
    "Degu",
    "Prairie Dog",
    "Parrot",
    "Budgie / Parakeet",
    "Cockatiel",
    "Cockatoo",
    "Lovebird",
    "Finch / Canary",
    "Macaw",
    "Pigeon / Dove",
    "Chicken / Poultry",
    "Gecko",
    "Bearded Dragon",
    "Tortoise / Turtle",
    "Snake",
    "Iguana",
    "Chameleon",
    "Monitor Lizard",
    "Frog / Toad",
    "Axolotl",
    "Salamander",
    "Fish (Freshwater)",
    "Fish (Marine / Reef)",
    "Shrimp / Crayfish",
    "Crab",
    "Tarantula",
    "Scorpion",
    "Stick Insect",
    "Snail",
    "Horse / Pony",
    "Goat",
    "Sheep",
    "Pig (Micro)",
    "Alpaca / Llama",
    "No Pets",
]

CATEGORY_METADATA: list[dict[str, Any]] = [
    {
        "name": "Tech & Science",
        "icon": "cpu",
        "parents": [
            "Coding",
            "Science & Discovery",
            "Gadgets & Hardware",
            "Math & Logic",
        ],
    },
    {
        "name": "Entertainment & Media",
        "icon": "film",
        "parents": [
            "TV & Series",
            "Movies & Cinema",
            "Gaming",
            "Music",
            "Comedy & Memes",
            "Podcasts & Audio",
        ],
    },
    {
        "name": "Sports & Outdoors",
        "icon": "activity",
        "parents": [
            "Fitness & Training",
            "Martial Arts & Combat",
            "Team Sports",
            "Individual Sports",
            "Water & Winter Sports",
            "Outdoor Adventure",
            "Watching Sports",
        ],
    },
    {
        "name": "Creative & Arts",
        "icon": "palette",
        "parents": [
            "Visual Arts",
            "Design & Styling",
            "Photography & Video",
            "Performing Arts",
            "Writing & Literature",
            "Crafts & DIY",
        ],
    },
    {
        "name": "Books & Literature",
        "icon": "bookOpen",
        "parents": [
            "Fiction",
            "Non-Fiction",
            "Reading Habits",
        ],
    },
    {
        "name": "Food & Drink",
        "icon": "utensils",
        "parents": [
            "Cooking & Culinary",
            "Beverages",
            "Food Culture",
        ],
    },
    {
        "name": "Travel & Lifestyle",
        "icon": "compass",
        "parents": [
            "Travel Style",
            "Destinations",
            "Travel Interests",
        ],
    },
    {
        "name": "Lifestyle & Wellness",
        "icon": "sparkles",
        "parents": [
            "Mind & Wellbeing",
            "Nature & Gardening",
            "Fashion & Style",
            "Collecting & Hobbies",
            "Pets & Animals",
        ],
    },
    {
        "name": "Career & Finance",
        "icon": "briefcase",
        "parents": [
            "Investing",
            "Business & Entrepreneurship",
            "Personal Finance",
        ],
    },
    {
        "name": "Social & Activism",
        "icon": "heartHandshake",
        "parents": [
            "Community & Volunteering",
            "Activism & Advocacy",
            "Politics & Society",
            "Language & Culture",
        ],
    },
    {
        "name": "Spirituality & Esoteric",
        "icon": "moonStar",
        "parents": [
            "Spiritual Practices",
            "Mystical & Esoteric",
            "Paranormal & Unexplained",
        ],
    },
    {
        "name": "Cars & Motors",
        "icon": "car",
        "parents": [
            "Cars",
            "Motorcycles & Bikes",
            "Aviation & Marine",
        ],
    },
]


def build_interests_categories() -> list[dict[str, Any]]:
    """Construct hierarchical interest categories payload."""
    categories: list[dict[str, Any]] = []
    for cat in CATEGORY_METADATA:
        parents_data: list[dict[str, Any]] = []
        for p_name in cat["parents"]:
            sub_set = VALID_INTERESTS.get(p_name, set())
            parents_data.append({
                "name": p_name,
                "sub_interests": sorted(list(sub_set)),
            })
        categories.append({
            "name": cat["name"],
            "icon": cat["icon"],
            "parents": parents_data,
        })
    return categories


def validate_choice_consistency() -> None:
    """Ensure ordered options lists match the corresponding validation sets."""
    assert set(GENDERS_ORDERED) == GENDER_CHOICES, "Gender choices mismatch"
    assert set(SEXUALITIES_ORDERED) == SEXUALITY_CHOICES, "Sexuality choices mismatch"
    assert set(PRONOUNS_ORDERED) == PRONOUNS_CHOICES, "Pronouns choices mismatch"
    assert set(LANGUAGES_ORDERED) == LANGUAGES_CHOICES, "Languages choices mismatch"
    assert set(DRINKING_ORDERED) == DRINKING_CHOICES, "Drinking choices mismatch"
    assert set(SMOKING_ORDERED) == SMOKING_CHOICES, "Smoking choices mismatch"
    assert set(CHILDREN_PLANS_ORDERED) == CHILDREN_PLANS_CHOICES, "Children plans choices mismatch"
    assert set(RELIGIOUS_BELIEFS_ORDERED) == RELIGIOUS_BELIEFS_CHOICES, "Religious beliefs choices mismatch"
    assert set(CAUSES_SUPPORTED_ORDERED) == CAUSES_SUPPORTED_CHOICES, "Causes choices mismatch"
    assert set(PETS_ORDERED) == PETS_CHOICES, "Pets choices mismatch"


def export_choices_dict() -> dict[str, Any]:
    """Generate the complete canonical choices dictionary."""
    validate_choice_consistency()
    return {
        "version": "1.0.0",
        "genders": GENDERS_ORDERED,
        "sexualities": SEXUALITIES_ORDERED,
        "pronouns": PRONOUNS_ORDERED,
        "languages": LANGUAGES_ORDERED,
        "drinking": DRINKING_ORDERED,
        "smoking": SMOKING_ORDERED,
        "children_plans": CHILDREN_PLANS_ORDERED,
        "religious_beliefs": RELIGIOUS_BELIEFS_ORDERED,
        "causes_supported": CAUSES_SUPPORTED_ORDERED,
        "pets": PETS_ORDERED,
        "partner_values": PARTNER_VALUES_CHOICES,
        "tech_skills": TECH_SKILLS_CHOICES,
        "sub_interests": FILTER_SUB_INTERESTS,
        "dating_for_options": DATING_FOR_OPTIONS,
        "looking_for_options": LOOKING_FOR_OPTIONS,
        "search_buckets": SEARCH_BUCKETS,
        "interests_categories": build_interests_categories(),
    }


def export_to_file(target_path: Path | str | None = None) -> Path:
    """Export choices dictionary to JSON file."""
    if target_path is None:
        target_path = (
            Path(__file__).resolve().parents[3]
            / "mobile"
            / "assets"
            / "config"
            / "choices.json"
        )
    target_path = Path(target_path)
    target_path.parent.mkdir(parents=True, exist_ok=True)
    payload = export_choices_dict()
    with target_path.open("w", encoding="utf-8") as f:
        json.dump(payload, f, indent=2, ensure_ascii=False)
        f.write("\n")
    return target_path


if __name__ == "__main__":
    out_file = export_to_file()
    print(f"Exported choices JSON to {out_file}")
