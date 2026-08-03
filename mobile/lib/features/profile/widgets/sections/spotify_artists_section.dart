import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:nexus/core/theme/app_colors.dart';
import 'package:nexus/core/widgets/aesthetic_loaders.dart';
import 'package:nexus/features/profile/widgets/profile_visibility_badge.dart';
import 'package:nexus/features/profile/widgets/sections/spotify_playlists_section.dart';
import 'package:nexus/features/profile/widgets/universe_section.dart';
import 'package:nexus/features/spotify/providers/spotify_provider.dart';

class SpotifyMusicSection extends ConsumerWidget {
  const SpotifyMusicSection({
    required this.topArtists,
    required this.onArtistRemoved,
    required this.onSpotifyConnect,
    this.onSpotifyDisconnect,
    this.isSaving = false,
    this.isConnecting = false,
    this.artistsVisibilityToggle,
    super.key,
  });

  final List<String> topArtists;
  final ValueChanged<String> onArtistRemoved;
  final VoidCallback onSpotifyConnect;
  final VoidCallback? onSpotifyDisconnect;
  final bool isSaving;
  final bool isConnecting;
  final Widget? artistsVisibilityToggle;

  static const _spotifyGreen = Color(0xFF1DB954);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final statusAsync = ref.watch(spotifyStatusProvider);
    final isConnected = topArtists.isNotEmpty;

    return UniverseSection(
      icon: LucideIcons.music,
      title: 'Music - Artists & Playlists',
      description: 'Your top artists and synced playlists from Spotify',
      cardColor: const Color(0xFFEFFAF3),
      borderColor: _spotifyGreen.withValues(alpha: 0.40),
      accentColor: _spotifyGreen,
      visibilityBadge: ProfileVisibilityBadge.datingAndFriends(),
      child: Stack(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (isConnected) ...[
                // Top Artists Subsection
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
                    if (artistsVisibilityToggle != null) ...[
                      const SizedBox(width: 8),
                      artistsVisibilityToggle!,
                    ],
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
                const SizedBox(height: 20),

                // Playlists Subsection
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'YOUR PLAYLISTS',
                      style: TextStyle(
                        color: Colors.black.withValues(alpha: 0.45),
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.2,
                      ),
                    ),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          LucideIcons.lock,
                          size: 10,
                          color: Colors.black38,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          'Only visible to you',
                          style: TextStyle(
                            color: Colors.black.withValues(alpha: 0.35),
                            fontSize: 9,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                statusAsync.when(
                  data: (status) {
                    if (!status.connected) {
                      return const SizedBox.shrink();
                    }
                    final lastSynced = status.lastSyncedAt;
                    final subtitle = lastSynced == null
                        ? 'Syncing your playlists…'
                        : '${status.playlistCount} playlist${status.playlistCount == 1 ? '' : 's'}'
                              ' · synced ${_relativeTimeShort(lastSynced)}';

                    return GestureDetector(
                      onTap: () => openPlaylistsSheet(context),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 12,
                        ),
                        decoration: BoxDecoration(
                          color: _spotifyGreen.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: _spotifyGreen.withValues(alpha: 0.30),
                          ),
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              LucideIcons.listMusic,
                              size: 16,
                              color: _spotifyGreen,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                subtitle,
                                style: const TextStyle(
                                  color: AppColors.ink,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            const Icon(
                              LucideIcons.chevronRight,
                              size: 16,
                              color: Colors.black38,
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                  loading: () => const Center(
                    child: Padding(
                      padding: EdgeInsets.symmetric(vertical: 8),
                      child: NexusOrbitLoader(size: 20),
                    ),
                  ),
                  error: (_, _) => Text(
                    "Couldn't load playlists.",
                    style: TextStyle(
                      color: Colors.black.withValues(alpha: 0.45),
                      fontSize: 12,
                    ),
                  ),
                ),
                const SizedBox(height: 20),
              ] else ...[
                const _EmptyState(),
                const SizedBox(height: 16),
              ],

              _ConnectButton(
                hasArtists: isConnected,
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
              if (isConnected && onSpotifyDisconnect != null) ...[
                const SizedBox(height: 16),
                Align(
                  alignment: Alignment.centerRight,
                  child: GestureDetector(
                    onTap: onSpotifyDisconnect,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.red.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: Colors.red.withValues(alpha: 0.20),
                          width: 0.8,
                        ),
                      ),
                      child: Text(
                        'Disconnect Spotify',
                        style: TextStyle(
                          color: Colors.red.withValues(alpha: 0.65),
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
          // ── Syncing overlay ────────────────────────────────────────────────
          Positioned.fill(
            child: AnimatedOpacity(
              duration: const Duration(milliseconds: 300),
              opacity: isConnecting ? 1.0 : 0.0,
              child: IgnorePointer(
                ignoring: !isConnecting,
                child: Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFFEFFAF3).withValues(alpha: 0.88),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  alignment: Alignment.center,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const NexusOrbitLoader(size: 36),
                      const SizedBox(height: 14),
                      Text(
                        'Syncing with Spotify…',
                        style: TextStyle(
                          color: const Color(
                            0xFF1DB954,
                          ).withValues(alpha: 0.85),
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _relativeTimeShort(DateTime time) {
    final diff = DateTime.now().toUtc().difference(time.toUtc());
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inHours < 1) return '${diff.inMinutes}m ago';
    if (diff.inDays < 1) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
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
              color: AppColors.ink,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(width: 2),
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
      width: double.infinity,
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
                const NexusOrbitLoader(size: 14, lightMode: true)
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
              const NexusOrbitLoader(size: 16)
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
