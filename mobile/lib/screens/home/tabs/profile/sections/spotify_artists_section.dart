import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:nexus/screens/home/tabs/profile/widgets/universe_section.dart';
import 'package:nexus/widgets/aesthetic_loaders.dart';

class SpotifyArtistsSection extends StatelessWidget {
  const SpotifyArtistsSection({
    required this.topArtists,
    required this.onArtistRemoved,
    required this.onSpotifyConnect,
    this.onSpotifyDisconnect,
    this.isSaving = false,
    this.isConnecting = false,
    super.key,
  });

  final List<String> topArtists;
  final ValueChanged<String> onArtistRemoved;
  final VoidCallback onSpotifyConnect;
  final VoidCallback? onSpotifyDisconnect;
  final bool isSaving;
  final bool isConnecting;

  static const _spotifyGreen = Color(0xFF1DB954);

  @override
  Widget build(BuildContext context) {
    return UniverseSection(
      icon: LucideIcons.music2,
      title: 'Top Artists',
      description: 'Fetched from your Spotify listening history and playlists',
      cardColor: const Color(0xFFEFFAF3),
      borderColor: _spotifyGreen.withValues(alpha: 0.40),
      accentColor: _spotifyGreen,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (topArtists.isNotEmpty) ...[
            Row(
              children: [
                Text(
                  'TOP ARTISTS',
                  style: TextStyle(
                    color: Colors.black.withValues(alpha: 0.45),
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.2,
                  ),
                ),
                if (isSaving) ...[
                  const SizedBox(width: 8),
                  const NexusOrbitLoader(size: 20),
                ],
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: topArtists.map((artist) {
                return _ArtistChip(
                  name: artist,
                  onRemove: () => onArtistRemoved(artist),
                );
              }).toList(),
            ),
            const SizedBox(height: 16),
          ] else ...[
            const _EmptyState(),
            const SizedBox(height: 16),
          ],
          _ConnectButton(
            hasArtists: topArtists.isNotEmpty,
            isConnecting: isConnecting,
            onTap: onSpotifyConnect,
          ),
          const SizedBox(height: 8),
          Text(
            'Authorizes read-only access to your listening history and playlists. No playback control.',
            style: TextStyle(
              color: Colors.black.withValues(alpha: 0.38),
              fontSize: 10,
              height: 1.5,
            ),
          ),
          if (topArtists.isNotEmpty && onSpotifyDisconnect != null) ...[
            const SizedBox(height: 10),
            GestureDetector(
              onTap: onSpotifyDisconnect,
              child: Text(
                'Disconnect Spotify',
                style: TextStyle(
                  color: Colors.red.withValues(alpha: 0.55),
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ArtistChip extends StatelessWidget {
  const _ArtistChip({
    required this.name,
    required this.onRemove,
  });

  final String name;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 6, 8, 6),
      decoration: BoxDecoration(
        color: const Color(0xFF1DB954).withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: const Color(0xFF1DB954).withValues(alpha: 0.30),
          width: 0.8,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            LucideIcons.music,
            size: 11,
            color: Color(0xFF1DB954),
          ),
          const SizedBox(width: 6),
          Text(
            name,
            style: const TextStyle(
              color: Color(0xFF0F172A),
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(width: 2),
          // 24x24 rather than the usual 44px minimum: this sits in a Wrap of
          // several compact chips, where a 44px target per chip would blow
          // out the pill shape. 24x24 still clears WCAG 2.2 AA's floor for
          // dense inline controls.
          Semantics(
            button: true,
            label: 'Remove $name',
            excludeSemantics: true,
            onTap: onRemove,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onRemove,
              child: const SizedBox(
                width: 24,
                height: 24,
                child: Center(
                  child: Icon(
                    LucideIcons.x,
                    size: 12,
                    color: Colors.black45,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 20),
      child: Column(
        children: [
          Icon(
            LucideIcons.music2,
            size: 32,
            color: Colors.black.withValues(alpha: 0.15),
          ),
          const SizedBox(height: 10),
          Text(
            'No top artists yet',
            style: TextStyle(
              color: Colors.black.withValues(alpha: 0.5),
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Connect Spotify to auto-fill from your listening history',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.black.withValues(alpha: 0.38),
              fontSize: 11,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}

class _ConnectButton extends StatelessWidget {
  const _ConnectButton({
    required this.hasArtists,
    required this.isConnecting,
    required this.onTap,
  });

  final bool hasArtists;
  final bool isConnecting;
  final VoidCallback onTap;

  static const _spotifyGreen = Color(0xFF1DB954);

  @override
  Widget build(BuildContext context) {
    if (hasArtists) {
      // Secondary resync button
      return GestureDetector(
        onTap: isConnecting ? null : onTap,
        child: Container(
          height: 40,
          decoration: BoxDecoration(
            color: _spotifyGreen.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: _spotifyGreen.withValues(alpha: 0.35),
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (isConnecting)
                const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(_spotifyGreen),
                  ),
                )
              else
                const Icon(
                  LucideIcons.refreshCw,
                  size: 14,
                  color: _spotifyGreen,
                ),
              const SizedBox(width: 8),
              Text(
                isConnecting ? 'Connecting...' : 'Sync from Spotify',
                style: const TextStyle(
                  color: _spotifyGreen,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      );
    }

    // Primary connect button
    return GestureDetector(
      onTap: isConnecting ? null : onTap,
      child: Container(
        height: 48,
        decoration: BoxDecoration(
          color: isConnecting
              ? _spotifyGreen.withValues(alpha: 0.7)
              : _spotifyGreen,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: _spotifyGreen.withValues(alpha: 0.35),
              blurRadius: 16,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (isConnecting)
              const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                ),
              )
            else
              const Icon(LucideIcons.music2, size: 16, color: Colors.white),
            const SizedBox(width: 10),
            Text(
              isConnecting ? 'Opening Spotify...' : 'Connect with Spotify',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.3,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
