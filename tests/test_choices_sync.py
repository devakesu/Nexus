import json
from pathlib import Path

from app.core.choices import (
    CAUSES_SUPPORTED_CHOICES,
    CHILDREN_PLANS_CHOICES,
    DATING_FOR_OPTIONS,
    DRINKING_CHOICES,
    FILTER_SUB_INTERESTS,
    GENDER_CHOICES,
    LANGUAGES_CHOICES,
    LOOKING_FOR_OPTIONS,
    PARTNER_VALUES_CHOICES,
    PETS_CHOICES,
    PRONOUNS_CHOICES,
    RELIGIOUS_BELIEFS_CHOICES,
    SEARCH_BUCKETS,
    SEXUALITY_CHOICES,
    SMOKING_CHOICES,
    TECH_SKILLS_CHOICES,
    VALID_INTERESTS,
    export_choices_dict,
    export_to_file,
)


def test_choices_json_asset_exists_and_matches_export(tmp_path: Path) -> None:
    """Verify that mobile/assets/config/choices.json is in sync with backend choices."""
    repo_root = Path(__file__).resolve().parents[1]
    asset_file = repo_root / "mobile" / "assets" / "config" / "choices.json"

    # Export to temp path to verify export_to_file
    temp_target = tmp_path / "choices.json"
    export_to_file(temp_target)
    assert temp_target.exists()

    assert asset_file.exists(), f"Missing choices.json at {asset_file}"

    with asset_file.open(encoding="utf-8") as f:
        disk_data = json.load(f)

    generated_data = export_choices_dict()

    # Compare top-level keys
    assert set(disk_data.keys()) == set(generated_data.keys())

    # Verify each list matches
    assert disk_data["genders"] == generated_data["genders"]
    assert disk_data["sexualities"] == generated_data["sexualities"]
    assert disk_data["pronouns"] == generated_data["pronouns"]
    assert disk_data["languages"] == generated_data["languages"]
    assert disk_data["drinking"] == generated_data["drinking"]
    assert disk_data["smoking"] == generated_data["smoking"]
    assert disk_data["children_plans"] == generated_data["children_plans"]
    assert disk_data["religious_beliefs"] == generated_data["religious_beliefs"]
    assert disk_data["causes_supported"] == generated_data["causes_supported"]
    assert disk_data["pets"] == generated_data["pets"]
    assert disk_data["partner_values"] == generated_data["partner_values"]
    assert disk_data["tech_skills"] == generated_data["tech_skills"]
    assert disk_data["sub_interests"] == generated_data["sub_interests"]
    assert disk_data["dating_for_options"] == generated_data["dating_for_options"]
    assert disk_data["looking_for_options"] == generated_data["looking_for_options"]
    assert disk_data["search_buckets"] == generated_data["search_buckets"]


def test_choices_match_backend_validation_sets() -> None:
    """Ensure choice sets used by Pydantic validation match the exported lists."""
    data = export_choices_dict()

    assert set(data["genders"]) == GENDER_CHOICES
    assert set(data["sexualities"]) == SEXUALITY_CHOICES
    assert set(data["pronouns"]) == PRONOUNS_CHOICES
    assert set(data["languages"]) == LANGUAGES_CHOICES
    assert set(data["drinking"]) == DRINKING_CHOICES
    assert set(data["smoking"]) == SMOKING_CHOICES
    assert set(data["children_plans"]) == CHILDREN_PLANS_CHOICES
    assert set(data["religious_beliefs"]) == RELIGIOUS_BELIEFS_CHOICES
    assert set(data["causes_supported"]) == CAUSES_SUPPORTED_CHOICES
    assert set(data["pets"]) == PETS_CHOICES
    assert data["partner_values"] == PARTNER_VALUES_CHOICES
    assert data["tech_skills"] == TECH_SKILLS_CHOICES
    assert data["sub_interests"] == FILTER_SUB_INTERESTS
    assert data["dating_for_options"] == DATING_FOR_OPTIONS
    assert data["looking_for_options"] == LOOKING_FOR_OPTIONS
    assert data["search_buckets"] == SEARCH_BUCKETS


def test_interests_categories_structure() -> None:
    """Verify interest categories hierarchy integrity."""
    data = export_choices_dict()
    categories = data["interests_categories"]

    assert len(categories) == 12
    all_sub_interests_in_cats: set[str] = set()

    for cat in categories:
        assert "name" in cat
        assert "icon" in cat
        assert "parents" in cat
        for parent in cat["parents"]:
            assert "name" in parent
            assert "sub_interests" in parent
            assert parent["name"] in VALID_INTERESTS
            for sub in parent["sub_interests"]:
                all_sub_interests_in_cats.add(sub)

    # Flattened VALID_INTERESTS
    expected_all_subs = {s for subs in VALID_INTERESTS.values() for s in subs}
    assert all_sub_interests_in_cats == expected_all_subs
