"""Discovery filter and match preference choice sets.

Contains canonical choices for partner values, tech skills, dating intentions,
professional intentions, and discovery search buckets.
"""

# Partner core values (Dating filter & profile coordinates)
PARTNER_VALUES_CHOICES: list[str] = [
    "Authenticity",
    "Empathy",
    "Ambition",
    "Loyalty",
    "Honesty",
    "Kindness",
    "Growth Mindset",
    "Creativity",
    "Emotional Maturity",
    "Humor & Wit",
    "Respect",
    "Adventure",
    "Communication",
    "Curiosity",
    "Compassion",
    "Family-oriented",
    "Financial Stability",
    "Independence",
    "Open-mindedness",
    "Self-awareness",
    "Trustworthiness",
]

# Professional tab tech skills / expertise
TECH_SKILLS_CHOICES: list[str] = [
    "AI/ML",
    "Web Dev",
    "Mobile Dev",
    "Backend",
    "Cloud/DevOps",
    "Data Science",
    "Cybersecurity",
    "Blockchain",
    "Game Dev",
    "UI/UX",
    "Embedded Systems",
    "Open Source",
]

# Dating tab - maps to `dating_for` TEXT[] column codes.
DATING_FOR_OPTIONS: list[dict[str, str]] = [
    {"code": "short", "label": "Short-term"},
    {"code": "long", "label": "Long-term"},
    {"code": "casual", "label": "Casual Dating"},
    {"code": "fling", "label": "Fling"},
    {"code": "hookups", "label": "Hookups"},
    {"code": "fwb", "label": "Friends w/ Benefits"},
    {"code": "monogamous", "label": "Monogamous"},
    {"code": "polyamorous", "label": "Polyamorous"},
    {"code": "open_rel", "label": "Open Relationship"},
    {"code": "marriage", "label": "Marriage-minded"},
    {"code": "platonic", "label": "Platonic"},
    {"code": "unsure", "label": "Figuring it out"},
]

# Professional tab - maps to encrypted `looking_for` list field.
LOOKING_FOR_OPTIONS: list[dict[str, str]] = [
    {"code": "networking", "label": "Networking"},
    {"code": "mentorship", "label": "Mentorship"},
    {"code": "cofounder", "label": "Co-founder"},
    {"code": "freelance", "label": "Freelance"},
    {"code": "internship", "label": "Internship"},
    {"code": "long", "label": "Long-term role"},
    {"code": "short", "label": "Short-term project"},
]

# Dating tab - candidate search bucket mappings.
SEARCH_BUCKETS: list[dict[str, str]] = [
    {"code": "M", "label": "Men"},
    {"code": "F", "label": "Women"},
    {"code": "NB", "label": "Non-binary"},
]

# Flat sub-interest values for discovery filters
FILTER_SUB_INTERESTS: list[str] = [
    "Photography",
    "Hiking",
    "Gaming",
    "Cooking",
    "Reading",
    "Fitness",
    "Travel",
    "Music",
    "Art",
    "Dance",
    "Theatre",
    "Yoga",
    "Cycling",
    "Swimming",
    "Running",
    "Football",
    "Cricket",
    "Chess",
    "Coding",
    "Startups",
    "Finance",
    "Writing",
    "Podcasting",
    "Films",
    "Anime",
    "Fashion",
    "Sustainability",
    "Volunteering",
]

__all__ = [
    "DATING_FOR_OPTIONS",
    "FILTER_SUB_INTERESTS",
    "LOOKING_FOR_OPTIONS",
    "PARTNER_VALUES_CHOICES",
    "SEARCH_BUCKETS",
    "TECH_SKILLS_CHOICES",
]
