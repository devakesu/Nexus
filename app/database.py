from typing import Dict, List, Tuple, Any, Optional
from supabase import create_client, Client
from postgrest.exceptions import APIError
from app.config import settings
from app.models import DiscoveryFilters

supabase_client: Client = create_client(settings.supabase_url, settings.supabase_service_role_key)

def fetch_stage_1_candidates(
    viewer_id: str, 
    active_tab: str, 
    filters: DiscoveryFilters
) -> Tuple[Optional[Dict[str, Any]], List[Dict[str, Any]]]:
    """
    Executes a dynamically structured Stage 1 Database Filtering Pass.
    Defensively catches PostgREST row collection boundaries to mitigate 500 ASGI crashes.
    """
    # 1. Fetch user anchor profile wrapped in a defensive block
    try:
        viewer_res = supabase_client.table("profiles").select("*").eq("id", viewer_id).single().execute()
        viewer = viewer_res.data
    except APIError as e:
        # Code PGRST116 explicitly means '0 rows returned' 
        if e.code == "PGRST116":
            return None, []
        raise e
    
    if not viewer or not isinstance(viewer, dict):
        return None, []
        
    # 2. Initialize selective base builder pointer
    query = supabase_client.table("profiles").select("*")
    
    query = query.neq("id", viewer_id)
    query = query.eq("is_profile_complete", True)
    query = query.eq("is_deactivated", False)
    
    # 3. Dynamic Filter Chain Injectors
    if filters.years:
        query = query.in_("year", filters.years)
    if filters.drinking:
        query = query.in_("drinking", filters.drinking)
    if filters.smoking:
        query = query.in_("smoking", filters.smoking)
    if filters.branches:
        query = query.in_("branch", filters.branches)
    if filters.role:
        query = query.eq("role", filters.role)
        
    query = query.gte("age", filters.min_age)
    query = query.lte("age", filters.max_age)

    # 4. Handle Tab Extraction Paths
    if active_tab != "Dating":
        res = query.limit(100).execute()
        raw_data = res.data if isinstance(res.data, list) else []
        candidates = [c for c in raw_data if isinstance(c, dict)]
        return viewer, candidates
        
    target_buckets = viewer.get("target_buckets")
    search_buckets = viewer.get("search_buckets")
    
    if not isinstance(target_buckets, list) or not isinstance(search_buckets, list) or not search_buckets:
        return viewer, []
        
    res = query.ov("search_buckets", target_buckets).execute()
    if not isinstance(res.data, list):
        return viewer, []
        
    valid_candidates: List[Dict[str, Any]] = []
    viewer_search_prime = search_buckets[0]
    
    for candidate in res.data:
        if not isinstance(candidate, dict):
            continue
            
        c_target_buckets = candidate.get("target_buckets")
        if isinstance(c_target_buckets, list) and viewer_search_prime in c_target_buckets:
            valid_candidates.append(candidate)
            
    return viewer, valid_candidates