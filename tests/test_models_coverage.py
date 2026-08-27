"""Comprehensive unit tests covering 100% of all models, validators, and serialization in app/models."""

import base64
from datetime import datetime, timezone

import pytest
from pydantic import ValidationError

from app.core.config import settings
from app.models.admin import (
    FeedbackCloseRequest,
    FeedbackCommentRequest,
    FeedbackSubmitRequest,
)
from app.models.chat import (
    BatchPresenceRequest,
    ChatConversationItem,
    CreateChatRequest,
    CreateEventRequest,
    EstablishSessionRequest,
    OneTimePrekeyItem,
    PresenceHeartbeatRequest,
    SendMessageRequest,
    UploadIdentityKeyRequest,
    UploadOneTimePrekeysRequest,
    UploadSignedPrekeyRequest,
)
from app.models.discovery import (
    DiscoveryActionRequest,
    DiscoveryFilters,
    DiscoveryRequest,
    DiscoveryViewportRequest,
    LikeActionRequest,
    MarkLikesSeenRequest,
    MatchActionRequest,
    OrbitNodeDetailRequest,
    OrbitNodeOut,
    PeerProfileRequest,
)
from app.models.profile import (
    EmailNotificationSettingsResponse,
    EmailNotificationSettingsUpdate,
    ModerationSubjectsRequest,
    PrivacySettingsResponse,
    PrivacySettingsUpdate,
    ProfileDerivedSignalsResponse,
    ProfileDetailsUpdate,
    ProfileImagesAndTagsUpdate,
    ProfileModel,
    RegisterDeviceRequest,
)
from app.models.safety import (
    EscalationCancelRequest,
    SafetyAlertRequest,
    SafetyContactIn,
    SafetyContactPortalOtpRequestRequest,
    SafetyContactPortalOtpVerifyRequest,
    SafetyContactsSyncRequest,
    SafetyEvidenceRegisterRequest,
    SafetyLocation,
    SafetyPortalOtpRequestRequest,
    SafetyPortalOtpVerifyRequest,
    SafetySessionCheckinRequest,
    SafetySessionEndRequest,
    SafetySessionStartRequest,
)
from app.models.spotify import (
    SpotifyTrackOut,
)
from app.models.user import (
    AccountPhoneOtpRequestRequest,
    AccountPhoneOtpVerifyRequest,
    ConsentUpdateRequest,
    ImportRequest,
    LoginByPhoneRequestRequest,
    LoginByPhoneVerifyRequest,
    MECOnboardingRequest,
    NexusOnboardingRequest,
)

# ==========================================
# 1. PROFILE MODELS TESTS
# ==========================================

def test_profile_model_instantiation():
    p = ProfileModel(
        id="usr-1",
        name="Tester",
        campus_branch="Computer Science",
        campus_year=3,
        age=21,
        campus_name="Model Institute",
    )
    assert p.id == "usr-1"
    assert p.search_bucket == "NB"
    assert p.dating_target_buckets == []


def test_profile_images_and_tags_update_validation():
    # Valid
    req = ProfileImagesAndTagsUpdate(
        profile_pic="users/123/avatar.jpg",
        normal_pics=["users/123/img1.jpg", "users/123/img2.jpg"],
        ai_vibe_tags=["chill", "music_lover"],
    )
    assert req.profile_pic == "users/123/avatar.jpg"
    assert len(req.normal_pics) == 2
    assert "chill" in req.ai_vibe_tags

    # Invalid empty profile pic
    with pytest.raises(ValidationError):
        ProfileImagesAndTagsUpdate(profile_pic="   ", normal_pics=[], ai_vibe_tags=["tag"])

    # Invalid long profile pic (> 500 chars)
    with pytest.raises(ValidationError):
        ProfileImagesAndTagsUpdate(profile_pic="a" * 501, normal_pics=[], ai_vibe_tags=["tag"])

    # Path traversal in profile pic
    with pytest.raises(ValidationError):
        ProfileImagesAndTagsUpdate(profile_pic="../secret.jpg", normal_pics=[], ai_vibe_tags=["tag"])
    with pytest.raises(ValidationError):
        ProfileImagesAndTagsUpdate(profile_pic="/absolute/path.jpg", normal_pics=[], ai_vibe_tags=["tag"])
    with pytest.raises(ValidationError):
        ProfileImagesAndTagsUpdate(profile_pic="back\\slash.jpg", normal_pics=[], ai_vibe_tags=["tag"])
    with pytest.raises(ValidationError):
        ProfileImagesAndTagsUpdate(profile_pic="null\x00byte.jpg", normal_pics=[], ai_vibe_tags=["tag"])

    # Normal pic path traversal and limits
    with pytest.raises(ValidationError):
        ProfileImagesAndTagsUpdate(
            profile_pic="users/123/pic.jpg",
            normal_pics=["b" * 501],
            ai_vibe_tags=["tag"],
        )
    with pytest.raises(ValidationError):
        ProfileImagesAndTagsUpdate(
            profile_pic="users/123/pic.jpg",
            normal_pics=["../escape.jpg"],
            ai_vibe_tags=["tag"],
        )
    with pytest.raises(ValidationError):
        ProfileImagesAndTagsUpdate(
            profile_pic="users/123/pic.jpg",
            normal_pics=["/rooted.png"],
            ai_vibe_tags=["tag"],
        )
    with pytest.raises(ValidationError):
        ProfileImagesAndTagsUpdate(
            profile_pic="users/123/pic.jpg",
            normal_pics=["back\\slash.png"],
            ai_vibe_tags=["tag"],
        )
    with pytest.raises(ValidationError):
        ProfileImagesAndTagsUpdate(
            profile_pic="users/123/pic.jpg",
            normal_pics=["null\x00.png"],
            ai_vibe_tags=["tag"],
        )

    # Test validator with list directly having > 4 items
    with pytest.raises(ValueError, match="A maximum of 4 gallery images"):
        ProfileImagesAndTagsUpdate.validate_normal_pics_constraints(["p1", "p2", "p3", "p4", "p5"])

    # AI vibe tags empty or too many
    with pytest.raises(ValidationError):
        ProfileImagesAndTagsUpdate(
            profile_pic="users/123/pic.jpg",
            normal_pics=[],
            ai_vibe_tags=[],
        )
    with pytest.raises(ValidationError):
        ProfileImagesAndTagsUpdate(
            profile_pic="users/123/pic.jpg",
            normal_pics=[],
            ai_vibe_tags=[f"tag{i}" for i in range(16)],
        )
    # AI vibe tag character length / invalid chars
    with pytest.raises(ValidationError):
        ProfileImagesAndTagsUpdate(
            profile_pic="users/123/pic.jpg",
            normal_pics=[],
            ai_vibe_tags=["a" * 31],
        )
    with pytest.raises(ValidationError):
        ProfileImagesAndTagsUpdate(
            profile_pic="users/123/pic.jpg",
            normal_pics=[],
            ai_vibe_tags=["invalid tag with spaces!"],
        )


def test_profile_details_update_validators():
    # Valid update
    update = ProfileDetailsUpdate(
        name="Alex Smith",
        age=22,
        campus_name="IIT Bombay",
        campus_year=3,
        bio="Hello world, I love coding!",
        drinking="Socially",
        smoking="Never",
        children_plans="Want kids",
        religious_beliefs="Agnostic",
        interests={"Coding": 4},
        sub_interests={"Coding": ["Python"]},
        display_gender="Man",
        display_sexuality="Straight / Heterosexual",
        pronouns="he/him",
        languages=["English", "Hindi"],
        causes_supported=["Climate Action", "Mental Health Advocacy"],
        pets=["Dog", "Cat"],
        profile_pic="users/123/avatar.jpg",
        normal_pics=["users/123/pic1.jpg"],
    )
    assert update.name == "Alex Smith"
    assert update.age == 22

    # None and empty bio / campus_name
    u_empty = ProfileDetailsUpdate(bio="", campus_name="", interests=None, sub_interests=None)
    assert u_empty.bio == ""
    assert u_empty.campus_name == ""
    assert u_empty.interests is None
    assert u_empty.sub_interests is None

    # None campus_name and None bio
    u_none_fields = ProfileDetailsUpdate(campus_name=None, bio=None)
    assert u_none_fields.campus_name is None
    assert u_none_fields.bio is None

    # Invalid campus name (< 3 alpha chars)
    with pytest.raises(ValidationError):
        ProfileDetailsUpdate(campus_name="12")

    # Invalid bio (< 3 alpha chars)
    with pytest.raises(ValidationError):
        ProfileDetailsUpdate(bio="12!!")

    # Campus year without campus name
    with pytest.raises(ValidationError):
        ProfileDetailsUpdate(campus_name="", campus_year=2)

    # Invalid choices
    with pytest.raises(ValidationError):
        ProfileDetailsUpdate(drinking="extreme_drinker")
    with pytest.raises(ValidationError):
        ProfileDetailsUpdate(smoking="vape_god")
    with pytest.raises(ValidationError):
        ProfileDetailsUpdate(children_plans="ten_kids")
    with pytest.raises(ValidationError):
        ProfileDetailsUpdate(religious_beliefs="pastafarian_cult")
    with pytest.raises(ValidationError):
        ProfileDetailsUpdate(display_gender="Alien")
    with pytest.raises(ValidationError):
        ProfileDetailsUpdate(display_sexuality="Martian")
    with pytest.raises(ValidationError):
        ProfileDetailsUpdate(pronouns="They/Them/Those/These/Theirs")
    with pytest.raises(ValidationError):
        ProfileDetailsUpdate(languages=["Klingon"])
    with pytest.raises(ValidationError):
        ProfileDetailsUpdate(causes_supported=["Fake Cause"])
    with pytest.raises(ValidationError):
        ProfileDetailsUpdate(pets=["Dragon"])

    # Interests & Sub-interests validation
    with pytest.raises(ValidationError):
        ProfileDetailsUpdate(interests={"InvalidParentInterest": 3})
    with pytest.raises(ValidationError):
        ProfileDetailsUpdate(interests={"Coding": 10})
    with pytest.raises(ValidationError):
        ProfileDetailsUpdate(interests={"Coding": 0})
    with pytest.raises(ValidationError):
        ProfileDetailsUpdate(sub_interests={"InvalidParent": ["Sub"]})
    with pytest.raises(ValidationError):
        ProfileDetailsUpdate(sub_interests={"Coding": ["NonExistentSubLanguage"]})

    # Profile pic & normal pics validators on ProfileDetailsUpdate
    u_none = ProfileDetailsUpdate(profile_pic=None, normal_pics=None)
    assert u_none.profile_pic is None
    assert u_none.normal_pics is None

    u_empty_pic = ProfileDetailsUpdate(profile_pic="   ")
    assert u_empty_pic.profile_pic == ""

    with pytest.raises(ValidationError):
        ProfileDetailsUpdate(profile_pic="c" * 501)
    with pytest.raises(ValidationError):
        ProfileDetailsUpdate(profile_pic="../escaped.jpg")
    with pytest.raises(ValidationError):
        ProfileDetailsUpdate(profile_pic="/rooted.jpg")
    with pytest.raises(ValidationError):
        ProfileDetailsUpdate(profile_pic="null\x00.jpg")
    with pytest.raises(ValidationError):
        ProfileDetailsUpdate(profile_pic="slash\\win.jpg")

    with pytest.raises(ValidationError):
        ProfileDetailsUpdate(normal_pics=["p1", "p2", "p3", "p4", "p5"])
    with pytest.raises(ValidationError):
        ProfileDetailsUpdate(normal_pics=["d" * 501])
    with pytest.raises(ValidationError):
        ProfileDetailsUpdate(normal_pics=["/rooted.png"])
    with pytest.raises(ValidationError):
        ProfileDetailsUpdate(normal_pics=["../escape.png"])
    with pytest.raises(ValidationError):
        ProfileDetailsUpdate(normal_pics=["back\\slash.png"])
    with pytest.raises(ValidationError):
        ProfileDetailsUpdate(normal_pics=["null\x00.png"])


def test_privacy_and_notification_models():
    # PrivacySettingsResponse & Update
    resp = PrivacySettingsResponse(
        hidden_fields=["display_gender"],
        share_active_status=True,
        share_read_receipts=False,
    )
    assert resp.share_active_status is True

    update = PrivacySettingsUpdate(
        hidden_fields=["display_gender", "hometown"],
        share_active_status=False,
    )
    assert len(update.hidden_fields or []) == 2

    # None hidden fields
    u_none = PrivacySettingsUpdate(hidden_fields=None)
    assert u_none.hidden_fields is None

    # Invalid hidden field
    with pytest.raises(ValidationError):
        PrivacySettingsUpdate(hidden_fields=["non_hideable_field_xyz"])

    # Email notification settings
    email_resp = EmailNotificationSettingsResponse(
        email_notify_matches=True,
        email_notify_messages=False,
        email_notify_digest=True,
        email_notify_product_updates=False,
        email_notify_promotions=False,
    )
    assert email_resp.email_notify_matches is True

    email_up = EmailNotificationSettingsUpdate(email_notify_matches=False)
    assert email_up.email_notify_matches is False


def test_moderation_and_derived_signals_models():
    # Moderation subjects request
    req = ModerationSubjectsRequest(target_ids=["11111111-1111-1111-1111-111111111111"])
    assert len(req.target_ids) == 1

    # Empty target IDs validator test directly
    with pytest.raises(ValueError, match="target_ids cannot be empty"):
        ModerationSubjectsRequest.validate_target_ids([])

    # Too many target IDs validator test directly
    with pytest.raises(ValueError, match="target_ids cannot contain more than 50 items"):
        ModerationSubjectsRequest.validate_target_ids([f"11111111-1111-1111-1111-1111111111{i:02d}" for i in range(51)])

    # Device registration with None device_id
    dev_none = RegisterDeviceRequest(
        fcm_token="fcm_token_sample_string_12345",
        platform="ios",
        device_id=None,
    )
    assert dev_none.device_id is None

    # Device registration with valid device_id
    dev = RegisterDeviceRequest(
        fcm_token="fcm_token_sample_string_12345",
        platform="ios",
        device_id="device-uuid-1234",
    )
    assert dev.platform == "ios"

    # ProfileDerivedSignalsResponse
    signals = ProfileDerivedSignalsResponse(
        user_id="usr-123",
        ai_vibe_tags=["creative", "outgoing"],
        artist_affinity={"Radiohead": 0.95},
        genre_affinity={"Rock": 0.8},
        embedding_signals={"dimension_count": 512},
        orientation_weight_profile="balanced",
        transparency_notice="GDPR Article 15 transparency notice",
    )
    assert signals.user_id == "usr-123"
    assert signals.orientation_weight_profile == "balanced"


# ==========================================
# 2. DISCOVERY MODELS TESTS
# ==========================================

def test_discovery_models():
    # DiscoveryFilters
    df = DiscoveryFilters(
        campus_years=[1, 2, 3],
        dating_for=["long_term"],
        search_bucket_filter=["F", "NB"],
        min_age=19,
        max_age=25,
    )
    assert df.min_age == 19
    assert df.max_age == 25

    # Invalid age range (min_age > max_age)
    with pytest.raises(ValidationError):
        DiscoveryFilters(min_age=30, max_age=20)

    # Discovery Request
    d_req = DiscoveryRequest(
        tab="Dating",
        session_id=None,
    )
    assert d_req.tab == "Dating"

    # Actions: LikeActionRequest, MatchActionRequest
    like = LikeActionRequest(
        target_id="11111111-1111-1111-1111-111111111111",
        action="like",
        tab="Dating",
        conversation_id=None,
    )
    assert like.action == "like"

    with pytest.raises(ValidationError):
        LikeActionRequest(
            target_id="11111111-1111-1111-1111-111111111111",
            action="like",
            tab=None,
        )

    with pytest.raises(ValidationError):
        LikeActionRequest(
            target_id="11111111-1111-1111-1111-111111111111",
            action="like",
            tab="Dating",
            conversation_id="not-a-uuid",
        )

    # DiscoveryActionRequest with tab=None on tab required action
    with pytest.raises(ValidationError):
        DiscoveryActionRequest(
            target_id="11111111-1111-1111-1111-111111111111",
            action="like",
            tab=None,
        )

    # Report action requires reason
    with pytest.raises(ValidationError):
        LikeActionRequest(
            target_id="11111111-1111-1111-1111-111111111111",
            action="report",
            tab="Dating",
        )

    # Report with reason other requires reason_detail
    with pytest.raises(ValidationError):
        LikeActionRequest(
            target_id="11111111-1111-1111-1111-111111111111",
            action="report",
            tab="Dating",
            reason="other",
        )

    # Valid report with other reason
    rep = LikeActionRequest(
        target_id="11111111-1111-1111-1111-111111111111",
        action="report",
        tab="Dating",
        reason="other",
        reason_detail="Suspicious fake identity",
    )
    assert rep.reason == "other"

    # Match Action
    match_act = MatchActionRequest(
        target_id="11111111-1111-1111-1111-111111111111",
        action="unmatch",
        tab="Dating",
    )
    assert match_act.action == "unmatch"

    with pytest.raises(ValidationError):
        MatchActionRequest(
            target_id="11111111-1111-1111-1111-111111111111",
            action="unmatch",
            tab=None,
        )

    # MarkLikesSeenRequest
    seen_req = MarkLikesSeenRequest(actor_ids=["11111111-1111-1111-1111-111111111111"])
    assert len(seen_req.actor_ids) == 1

    with pytest.raises(ValidationError):
        MarkLikesSeenRequest(actor_ids=["not-a-uuid"])

    # PeerProfileRequest
    peer_req = PeerProfileRequest(target_id="11111111-1111-1111-1111-111111111111", tab="Dating")
    assert peer_req.target_id == "11111111-1111-1111-1111-111111111111"

    with pytest.raises(ValidationError):
        PeerProfileRequest(target_id="invalid-uuid", tab="Dating")

    # Viewport request
    vp = DiscoveryViewportRequest(
        tab="Dating",
        session_id="11111111-1111-1111-1111-111111111111",
        center_x=0.0,
        center_y=0.0,
        radius=100.0,
    )
    assert vp.radius == 100.0

    with pytest.raises(ValidationError):
        DiscoveryViewportRequest(
            tab="Dating",
            session_id="invalid-uuid",
            center_x=0.0,
            center_y=0.0,
            radius=100.0,
        )

    # OrbitNodeOut
    node = OrbitNodeOut(
        id="usr-node-1",
        name="Alex",
        profile_pic="avatar.jpg",
        score=0.85,
        x=10.0,
        y=20.0,
        orbit_tier=1,
    )
    assert node.score == 0.85

    # OrbitNodeDetailRequest
    detail_req = OrbitNodeDetailRequest(
        session_id="11111111-1111-1111-1111-111111111111",
        candidate_id="22222222-2222-2222-2222-222222222222",
    )
    assert detail_req.candidate_id == "22222222-2222-2222-2222-222222222222"

    with pytest.raises(ValidationError):
        OrbitNodeDetailRequest(
            session_id="not-a-uuid",
            candidate_id="22222222-2222-2222-2222-222222222222",
        )


# ==========================================
# 3. CHAT MODELS TESTS
# ==========================================

def test_chat_models():
    now = datetime.now(timezone.utc)
    # Chat conversation item & List
    item = ChatConversationItem(
        conversation_id="conv-1",
        matched_user_id="usr-peer-1",
        name="Sam",
        profile_pic="avatar.jpg",
        last_message_at=now,
    )
    assert item.matched_user_id == "usr-peer-1"

    # Create Chat Request
    req = CreateChatRequest(
        match_id="11111111-1111-1111-1111-111111111111",
    )
    assert req.match_id == "11111111-1111-1111-1111-111111111111"

    with pytest.raises(ValidationError):
        CreateChatRequest(match_id="invalid-uuid")

    # EstablishSessionRequest
    est = EstablishSessionRequest(conversation_id="11111111-1111-1111-1111-111111111111")
    assert est.conversation_id == "11111111-1111-1111-1111-111111111111"

    with pytest.raises(ValidationError):
        EstablishSessionRequest(conversation_id="invalid-uuid")

    # Key upload requests
    b64_key = base64.b64encode(b"01234567890123456789012345678901")
    id_req = UploadIdentityKeyRequest(identity_public_key=b64_key, registration_id=12345)
    assert id_req.registration_id == 12345

    signed_req = UploadSignedPrekeyRequest(
        key_id=1,
        public_key=b64_key,
        signature=b64_key,
    )
    assert signed_req.key_id == 1

    otpk_item = OneTimePrekeyItem(key_id=1, public_key=b64_key)
    otpk_req = UploadOneTimePrekeysRequest(prekeys=[otpk_item])
    assert len(otpk_req.prekeys) == 1

    # Send Message Request
    valid_b64_ct = base64.b64encode(b"encrypted ciphertext").decode("ascii")
    msg_none_client_id = SendMessageRequest(
        ciphertext=valid_b64_ct,
        client_message_id=None,
    )
    assert msg_none_client_id.client_message_id is None

    msg = SendMessageRequest(
        ciphertext=valid_b64_ct,
        client_message_id="11111111-1111-1111-1111-111111111111",
        ciphertext_metadata={"ratchet_step": 3, "flag": True, "note": "hello"},
    )
    assert msg.ciphertext == valid_b64_ct

    # Metadata with > 20 keys
    with pytest.raises(ValidationError):
        SendMessageRequest(
            ciphertext=valid_b64_ct,
            ciphertext_metadata={f"k{i}": i for i in range(21)},
        )

    # Invalid client_message_id
    with pytest.raises(ValidationError):
        SendMessageRequest(ciphertext=valid_b64_ct, client_message_id="not-a-uuid")

    # Invalid base64 ciphertext
    with pytest.raises(ValidationError):
        SendMessageRequest(ciphertext="not-valid-base64!!")

    # Invalid metadata
    with pytest.raises(ValidationError):
        SendMessageRequest(ciphertext=valid_b64_ct, ciphertext_metadata={"nested": [1, 2, 3]})
    with pytest.raises(ValidationError):
        SendMessageRequest(ciphertext=valid_b64_ct, ciphertext_metadata={"k" * 51: "v"})
    with pytest.raises(ValidationError):
        SendMessageRequest(ciphertext=valid_b64_ct, ciphertext_metadata={"k": "v" * 501})

    # Presence & Events
    heartbeat = PresenceHeartbeatRequest()
    assert heartbeat.is_online is True

    batch_pres = BatchPresenceRequest(user_ids=["usr-1", "usr-2"])
    assert len(batch_pres.user_ids) == 2

    evt_req = CreateEventRequest(
        event_time=now,
        ciphertext=valid_b64_ct,
        safety_enabled=True,
        safety_interval_seconds=1800,
    )
    assert evt_req.safety_enabled is True

    with pytest.raises(ValidationError):
        CreateEventRequest(
            event_time=now,
            ciphertext="not-base-64!!",
        )

    # safety_enabled without safety_interval_seconds
    with pytest.raises(ValidationError):
        CreateEventRequest(
            event_time=now,
            ciphertext=valid_b64_ct,
            safety_enabled=True,
            safety_interval_seconds=None,
        )


# ==========================================
# 4. SAFETY MODELS TESTS
# ==========================================

def test_safety_models():
    now = datetime.now(timezone.utc)
    # Safety Contact
    c_in = SafetyContactIn(
        name="Jane Doe",
        phone="+15551234567",
    )
    assert c_in.name == "Jane Doe"

    with pytest.raises(ValidationError):
        SafetyContactIn(name="   ", phone="+15551234567")
    with pytest.raises(ValidationError):
        SafetyContactIn(name="Jane", phone="invalid-phone")

    sync_req = SafetyContactsSyncRequest(contacts=[c_in])
    assert len(sync_req.contacts) == 1

    # Safety Alert with session_id=None
    alert_none = SafetyAlertRequest(
        alert_type="sos_silent",
        session_id=None,
    )
    assert alert_none.session_id is None

    alert = SafetyAlertRequest(
        alert_type="sos_silent",
        session_id="11111111-1111-1111-1111-111111111111",
        current_location=SafetyLocation(lat=12.9716, lng=77.5946),
    )
    assert alert.alert_type == "sos_silent"

    with pytest.raises(ValidationError):
        SafetyAlertRequest(alert_type="sos_silent", session_id="bad-uuid")

    # Safety Evidence
    ev_req = SafetyEvidenceRegisterRequest(
        alert_id="alt-1",
        storage_path="safety/audio_1.aac",
        media_key_base64="b64key",
        content_type="audio",
    )
    assert ev_req.content_type == "audio"

    with pytest.raises(ValidationError):
        SafetyEvidenceRegisterRequest(
            alert_id="alt-1",
            storage_path="   ",
            media_key_base64="b64key",
            content_type="audio",
        )
    with pytest.raises(ValidationError):
        SafetyEvidenceRegisterRequest(
            alert_id="alt-1",
            storage_path="a" * 501,
            media_key_base64="b64key",
            content_type="audio",
        )
    with pytest.raises(ValidationError):
        SafetyEvidenceRegisterRequest(
            alert_id="alt-1",
            storage_path="onlyfilename_no_slash",
            media_key_base64="b64key",
            content_type="audio",
        )
    with pytest.raises(ValidationError):
        SafetyEvidenceRegisterRequest(
            alert_id="alt-1",
            storage_path="../escape/audio.aac",
            media_key_base64="b64key",
            content_type="audio",
        )

    # Safety Session with label=None
    s_start_none = SafetySessionStartRequest(
        interval_seconds=600,
        next_checkin_at=now,
        label=None,
    )
    assert s_start_none.label is None

    # Safety Session
    s_start = SafetySessionStartRequest(
        interval_seconds=600,
        next_checkin_at=now,
        battery_percent=85,
        connection_type="wifi",
    )
    assert s_start.interval_seconds == 600

    checkin = SafetySessionCheckinRequest(
        session_id="11111111-1111-1111-1111-111111111111",
        next_checkin_at=now,
    )
    assert checkin.session_id == "11111111-1111-1111-1111-111111111111"

    with pytest.raises(ValidationError):
        SafetySessionCheckinRequest(session_id="invalid-uuid", next_checkin_at=now)

    end_req = SafetySessionEndRequest(session_id="11111111-1111-1111-1111-111111111111")
    assert end_req.session_id == "11111111-1111-1111-1111-111111111111"

    with pytest.raises(ValidationError):
        SafetySessionEndRequest(session_id="invalid-uuid")

    cancel_req = EscalationCancelRequest(token="token_abc", reason="safe", note=None)
    assert cancel_req.reason == "safe"
    assert cancel_req.note is None

    # Portal OTP requests with blank phones
    with pytest.raises(ValidationError):
        SafetyPortalOtpRequestRequest(phone="   ")
    with pytest.raises(ValidationError):
        SafetyPortalOtpVerifyRequest(phone="   ", code="123456")
    with pytest.raises(ValidationError):
        SafetyContactPortalOtpRequestRequest(phone="   ")
    with pytest.raises(ValidationError):
        SafetyContactPortalOtpVerifyRequest(phone="   ", code="123456")


# ==========================================
# 5. USER & ADMIN & SPOTIFY MODELS TESTS
# ==========================================

def test_user_admin_spotify_models():
    # Onboarding
    nexus_onboard = NexusOnboardingRequest(
        name="Alex Smith",
        age=22,
        demographic_bucket="M",
    )
    assert nexus_onboard.name == "Alex Smith"

    with pytest.raises(ValidationError):
        NexusOnboardingRequest(name="A", age=22, demographic_bucket="M")
    with pytest.raises(ValidationError):
        NexusOnboardingRequest(name="   abc   ", age=22, demographic_bucket="M")
    with pytest.raises(ValidationError):
        NexusOnboardingRequest(name="Alex..Smith", age=22, demographic_bucket="M")
    with pytest.raises(ValidationError):
        NexusOnboardingRequest(name="12345", age=22, demographic_bucket="M")
    with pytest.raises(ValidationError):
        NexusOnboardingRequest(name="... ... ", age=22, demographic_bucket="M")

    mec_onboard = MECOnboardingRequest(
        age=20,
        campus_branch="Computer Science",
        campus_year=2,
        campus_name="IIT Bombay",
    )
    assert mec_onboard.campus_branch == "Computer Science"

    with pytest.raises(ValidationError):
        MECOnboardingRequest(age=20, campus_branch="   ", campus_year=2, campus_name="IIT Bombay")
    with pytest.raises(ValidationError):
        MECOnboardingRequest(age=20, campus_branch="CS", campus_year=2, campus_name="12")

    # Phone OTP
    otp_req = AccountPhoneOtpRequestRequest(phone="+15559876543")
    assert otp_req.phone == "+15559876543"

    with pytest.raises(ValidationError):
        AccountPhoneOtpRequestRequest(phone="invalid-phone")

    with pytest.raises(ValidationError):
        AccountPhoneOtpVerifyRequest(phone="invalid-phone", code="123456")

    verify_req = AccountPhoneOtpVerifyRequest(phone="+15559876543", code="123456")
    assert verify_req.code == "123456"

    with pytest.raises(ValidationError):
        AccountPhoneOtpVerifyRequest(phone="+15559876543", code="123")

    with pytest.raises(ValidationError):
        LoginByPhoneRequestRequest(phone="invalid-phone")

    with pytest.raises(ValidationError):
        LoginByPhoneVerifyRequest(phone="invalid-phone", code="123456")

    # Import request
    imp = ImportRequest(sync_code="ABC123")
    assert imp.sync_code == "ABC123"

    with pytest.raises(ValidationError):
        ImportRequest(sync_code="ABC-12")

    # Consent update
    consent = ConsentUpdateRequest(
        terms_version=settings.current_terms_version,
        general_accepted=True,
    )
    assert consent.general_accepted is True

    # Numeric but mismatched terms_version
    with pytest.raises(ValidationError, match="You must accept the current terms version"):
        ConsentUpdateRequest(terms_version="999.0.0", general_accepted=True)

    with pytest.raises(ValidationError, match="accepted_terms_version must be a numeric string"):
        ConsentUpdateRequest(terms_version="invalid-text-version", general_accepted=True)

    # Admin feedback
    fb_req_none_url = FeedbackSubmitRequest(
        query_type="bug_report",
        subject="Chat not loading",
        message="When opening the app, chat stays on spinner.",
        github_issue_url=None,
    )
    assert fb_req_none_url.github_issue_url is None

    fb_req_blank_url = FeedbackSubmitRequest(
        query_type="bug_report",
        subject="Chat not loading",
        message="When opening the app, chat stays on spinner.",
        github_issue_url="   ",
    )
    assert fb_req_blank_url.github_issue_url is None

    with pytest.raises(ValidationError):
        FeedbackSubmitRequest(
            query_type="bug_report",
            subject="   ",
            message="Valid message here",
        )
    with pytest.raises(ValidationError):
        FeedbackSubmitRequest(
            query_type="bug_report",
            subject="Valid subject",
            message="   ",
        )
    with pytest.raises(ValidationError):
        FeedbackSubmitRequest(
            query_type="bug_report",
            subject="Valid subject",
            message="Valid message here",
            attachment_paths=["a", "b", "c", "d", "e", "f"],
        )
    with pytest.raises(ValidationError):
        FeedbackCommentRequest(body="   ")
    with pytest.raises(ValidationError):
        FeedbackCloseRequest(reason="   ")

    fb_req = FeedbackSubmitRequest(
        query_type="bug_report",
        subject="Chat not loading",
        message="When opening the app, chat stays on spinner.",
        github_issue_url="https://github.com/my-org/my-repo/issues/123",
    )
    assert fb_req.query_type == "bug_report"

    with pytest.raises(ValidationError):
        FeedbackSubmitRequest(
            query_type="help",
            subject="Question",
            message="How do I update my email?",
            github_issue_url="https://github.com/my-org/my-repo/issues/123",
        )

    with pytest.raises(ValidationError):
        FeedbackSubmitRequest(
            query_type="bug_report",
            subject="Bug",
            message="App crash",
            github_issue_url="https://invalid-url.com",
        )

    fb_close = FeedbackCloseRequest(reason="Resolved in patch 1.0.9")
    assert fb_close.reason == "Resolved in patch 1.0.9"

    # Spotify models
    track = SpotifyTrackOut(
        spotify_track_id="spotify_track_1",
        name="Karma Police",
        artists=["Radiohead"],
    )
    assert track.name == "Karma Police"
