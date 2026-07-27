"""Spotify integration Pydantic models."""

from datetime import datetime

from pydantic import BaseModel, Field


class SpotifyTrackOut(BaseModel):
    """Spotifytrackout class representation."""
    spotify_track_id: str | None = None
    name: str
    artists: list[str] = Field(default_factory=list)


class SpotifyPlaylistOut(BaseModel):
    """Spotifyplaylistout class representation."""
    id: str
    spotify_playlist_id: str
    name: str
    is_collaborative: bool
    track_count: int
    tracks: list[SpotifyTrackOut] = []
    synced_at: datetime | None = None
    spotify_url: str


class SpotifyPlaylistsResponse(BaseModel):
    """Spotifyplaylistsresponse class representation."""
    connected: bool
    last_synced_at: datetime | None = None
    playlists: list[SpotifyPlaylistOut] = []


class SpotifyStatusResponse(BaseModel):
    """Spotifystatusresponse class representation."""
    connected: bool
    last_synced_at: datetime | None = None
    playlist_count: int = 0
