"""Chat, messages, presence, events, and key-exchange Pydantic models."""

from datetime import datetime
from typing import Any, Literal

from pydantic import Base64Bytes, BaseModel, Field, field_validator, model_validator

from app.core.config import DiscoveryTab


class ChatConversationItem(BaseModel):
    """Chatconversationitem class representation."""
    conversation_id: str
    matched_user_id: str
    name: str | None = None
    age: int | None = None
    profile_pic: str | None = None
    last_message_at: datetime
    has_unread: bool = False
    unread_count: int = 0


class ChatsListResponse(BaseModel):
    """Chatslistresponse class representation."""
    conversations: list[ChatConversationItem]


class ChatCandidateItem(BaseModel):
    """A match with no conversation started yet - shown in the New Chat picker."""

    match_id: str
    matched_user_id: str
    name: str | None = None
    age: int | None = None
    profile_pic: str | None = None
    matched_at: datetime


class ChatCandidatesResponse(BaseModel):
    """Chatcandidatesresponse class representation."""
    candidates: list[ChatCandidateItem]


class CreateChatRequest(BaseModel):
    """Createchatrequest class representation."""
    match_id: str = Field(..., min_length=1)

    @field_validator("match_id")
    @classmethod
    def validate_match_id_uuid(cls, v: str) -> str:
        """Executes validate match id uuid operation.

            Args:
                v: Input v parameter.

            Returns:
                str: Response payload or result."""
        import uuid

        try:
            uuid.UUID(v)
        except ValueError as e:
            raise ValueError("match_id must be a valid UUID") from e
        return v


class CreateChatResponse(BaseModel):
    """Createchatresponse class representation."""
    conversation_id: str
    matched_user_id: str
    tab: DiscoveryTab


class UploadIdentityKeyRequest(BaseModel):
    """Uploadidentitykeyrequest class representation."""
    identity_public_key: Base64Bytes
    registration_id: int = Field(..., ge=1, le=0x7FFFFFFF)


class UploadSignedPrekeyRequest(BaseModel):
    """Uploadsignedprekeyrequest class representation."""
    key_id: int = Field(..., ge=0)
    public_key: Base64Bytes
    signature: Base64Bytes


class OneTimePrekeyItem(BaseModel):
    """Onetimeprekeyitem class representation."""
    key_id: int = Field(..., ge=0)
    public_key: Base64Bytes


class UploadOneTimePrekeysRequest(BaseModel):
    """Uploadonetimeprekeysrequest class representation."""
    prekeys: list[OneTimePrekeyItem] = Field(..., min_length=1, max_length=200)


class OneTimePrekeyCountResponse(BaseModel):
    """Onetimeprekeycountresponse class representation."""
    count: int


class KeyBundleResponse(BaseModel):
    """Keybundleresponse class representation."""
    user_id: str
    identity_public_key: Base64Bytes
    registration_id: int
    signed_prekey_id: int
    signed_prekey_public: Base64Bytes
    signed_prekey_signature: Base64Bytes
    one_time_prekey_id: int | None = None
    one_time_prekey_public: Base64Bytes | None = None
    one_time_prekey_used: bool


class EstablishSessionRequest(BaseModel):
    """Establishsessionrequest class representation."""
    conversation_id: str = Field(..., min_length=1)

    @field_validator("conversation_id")
    @classmethod
    def validate_conversation_id_uuid(cls, v: str) -> str:
        """Executes validate conversation id uuid operation.

            Args:
                v: Input v parameter.

            Returns:
                str: Response payload or result."""
        import uuid

        try:
            uuid.UUID(v)
        except ValueError as e:
            raise ValueError("conversation_id must be a valid UUID") from e
        return v


class SendMessageRequest(BaseModel):
    """A ciphertext envelope - the server never sees plaintext or keys."""

    message_type: Literal["text", "image", "voice", "event", "location"] = "text"
    ciphertext: str = Field(..., min_length=1, max_length=200_000)
    ciphertext_metadata: dict[str, Any] = Field(
        default_factory=dict,
        max_length=20,
        description="Bounded Signal protocol metadata (string/int/bool values only).",
    )

    @field_validator("ciphertext")
    @classmethod
    def validate_base64(cls, v: str) -> str:
        """Executes validate base64 operation.

            Args:
                v: Input v parameter.

            Returns:
                str: Response payload or result."""
        import base64

        try:
            base64.b64decode(v, validate=True)
        except Exception as e:
            raise ValueError("ciphertext must be valid base64") from e
        return v


class SendMessageResponse(BaseModel):
    """Sendmessageresponse class representation."""
    message_id: str
    created_at: datetime


class PresenceHeartbeatRequest(BaseModel):
    """Presenceheartbeatrequest class representation."""
    is_online: bool = True


class BatchPresenceRequest(BaseModel):
    """Batch presence lookup request."""
    user_ids: list[str] = Field(..., min_length=1, max_length=50)


class PresenceResponse(BaseModel):
    """is_online/last_active_at are both null if the peer has Active Status
    off, has no active match with the caller, or has never been active -
    these cases are deliberately indistinguishable from the outside."""

    is_online: bool | None = None
    last_active_at: datetime | None = None


class MarkMessagesReadResponse(BaseModel):
    """Markmessagesreadresponse class representation."""
    marked_count: int


class CreateEventRequest(BaseModel):
    """
    Balanced storage: event_time/location are plaintext (needed for
    reminder scheduling); title/notes travel as a ratchet-encrypted
    ciphertext envelope, identical to a normal text message.
    """

    event_time: datetime
    location_lat: float | None = Field(default=None, ge=-90, le=90)
    location_lng: float | None = Field(default=None, ge=-180, le=180)
    location_label: str | None = Field(default=None, max_length=200)
    ciphertext: str = Field(..., min_length=1, max_length=200_000)
    ciphertext_metadata: dict[str, Any] = Field(
        default_factory=dict,
        max_length=20,
        description="Bounded Signal protocol metadata (string/int/bool values only).",
    )
    # Meetup Safety auto-configure (Milestone F) - personal to whichever
    # participant creates the event, not shared conversation state.
    safety_enabled: bool = False
    safety_interval_seconds: int | None = Field(default=None, gt=0, le=86400)

    @field_validator("ciphertext")
    @classmethod
    def validate_base64(cls, v: str) -> str:
        """Executes validate base64 operation.

            Args:
                v: Input v parameter.

            Returns:
                str: Response payload or result."""
        import base64

        try:
            base64.b64decode(v, validate=True)
        except Exception as e:
            raise ValueError("ciphertext must be valid base64") from e
        return v

    @model_validator(mode="after")
    def validate_safety_interval(self) -> "CreateEventRequest":
        """Executes validate safety interval operation.

            Returns:
                'CreateEventRequest': Response payload or result."""
        if self.safety_enabled and self.safety_interval_seconds is None:
            raise ValueError(
                "safety_interval_seconds is required when safety_enabled is set",
            )
        return self


class EventResponse(BaseModel):
    """Eventresponse class representation."""
    event_id: str
    message_id: str
    conversation_id: str
    event_time: datetime
    location_lat: float | None = None
    location_lng: float | None = None
    location_label: str | None = None
    status: Literal["proposed", "confirmed", "cancelled"]
    created_at: datetime
    safety_enabled: bool = False
    safety_interval_seconds: int | None = None


class UpdateEventStatusRequest(BaseModel):
    """Updateeventstatusrequest class representation."""
    status: Literal["confirmed", "cancelled"]
