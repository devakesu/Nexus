from pydantic import BaseModel, Field
from typing import List, Dict, Literal, Optional

class ProfileModel(BaseModel):
    id: str
    name: str
    branch: str
    year: int
    age: int
    sex: str
    display_gender: str
    display_sexuality: str
    search_buckets: List[str]
    target_buckets: List[str]
    drinking: str
    smoking: str
    activities: List[str]
    interests: Dict[str, int]
    sub_interests: Dict[str, List[str]]
    value_dimensions: Dict[str, float]
    role: Optional[str] = None
    looking_for: Optional[List[str]] = []
    identity_embedding: Optional[List[float]] = None
    career_embedding: Optional[List[float]] = None
    bio_embedding: Optional[List[float]] = None

from pydantic import BaseModel, Field
from typing import List, Optional

class DiscoveryFilters(BaseModel):
    """
    Enterprise Data Transfer Object (DTO) for selective profile filtering.
    Enforces rigid input schema bounds to mitigate malicious object injections.
    """
    years: Optional[List[int]] = Field(default=None, description="Array of target campus academic years.")
    
    # Enforce strict value checks at the application entrypoint boundary
    drinking: Optional[List[str]] = Field(default=None, description="Target drinking lifestyle profiles.")
    smoking: Optional[List[str]] = Field(default=None, description="Target smoking lifestyle profiles.")
    branches: Optional[List[str]] = Field(default=None, description="Target engineering branch categories.")
    role: Optional[str] = Field(default=None, max_length=100, description="Target professional role designation.")
    
    # Contiguous boundaries matching our database constraints
    min_age: int = Field(default=18, ge=18, le=27, description="Minimum age constraint boundary.")
    max_age: int = Field(default=27, ge=18, le=27, description="Maximum age constraint boundary.")

class DiscoveryRequest(BaseModel):
    """
    Unified encrypted POST body payload wrapper.
    Absorbs the 'tab' field into the body to prevent proxy metadata leak pathways.
    """
    tab: Literal["Dating", "Friends", "Professional"] = Field(..., description="Target matching pipeline matrix.")
    filters: Optional[DiscoveryFilters] = Field(default_factory=DiscoveryFilters, description="Dynamic compound filter parameters configuration.")