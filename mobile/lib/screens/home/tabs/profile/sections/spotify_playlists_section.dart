import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:nexus/features/spotify/models/spotify_playlist.dart';
import 'package:nexus/features/spotify/providers/spotify_provider.dart';
import 'package:nexus/screens/home/tabs/profile/widgets/universe_section.dart';
import 'package:nexus/widgets/aesthetic_loaders.dart';
import 'package:url_launcher/url_launcher.dart';

/// Private, owner-only "Your Playlists" section. Wired only into
/// ProfileTab's section list - never into ProfileDetailSheet (the
/// peer-facing profile view), which has no code path that could render
/// this even by accident since it only destructures fields it explicitly
/// asks for from its data map.
class SpotifyPlaylistsSection extends ConsumerWidget {
  const SpotifyPlaylistsSection({super.key});

  static const _spotifyGreen = Color(0xFF1DB954);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final statusAsync = ref.watch(spotifyStatusProvider);

    return UniverseSection(
      icon: LucideIcons.listMusic,
      title: 'Your Playlists',
      description: 'Detailed playlists synced from Spotify',
      cardColor: const Color(0xFFEFFAF3),
      borderColor: _spotifyGreen.withValues(alpha: 0.40),
      accentColor: _spotifyGreen,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(LucideIcons.lock, size: 12, color: Colors.black45),
              const SizedBox(width: 6),
              Text(
                'Only visible to you',
                style: TextStyle(
                  color: Colors.black.withValues(alpha: 0.5),
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          statusAsync.when(
            data: (status) => _StatusBody(status: status),
            loading: () => const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Center(child: NexusOrbitLoader(size: 24)),
            ),
            error: (_, _) => Text(
              "Couldn't load your playlist status.",
              style: TextStyle(
                color: Colors.black.withValues(alpha: 0.45),
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusBody extends StatelessWidget {
  const _StatusBody({required this.status});

  final SpotifyConnectionStatus status;

  @override
  Widget build(BuildContext context) {
    if (!status.connected) {
      return Text(
        'Connect Spotify above to sync your playlists here.',
        style: TextStyle(
          color: Colors.black.withValues(alpha: 0.45),
          fontSize: 12,
          height: 1.4,
        ),
      );
    }

    final lastSynced = status.lastSyncedAt;
    final subtitle = status.playlistCount == 0
        ? 'Syncing your playlists…'
        : '${status.playlistCount} playlist${status.playlistCount == 1 ? '' : 's'}'
              '${lastSynced != null ? ' · synced ${_relativeTime(lastSynced)}' : ''}';

    return GestureDetector(
      onTap: () => _openPlaylistsSheet(context),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: SpotifyPlaylistsSection._spotifyGreen.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: SpotifyPlaylistsSection._spotifyGreen.withValues(
              alpha: 0.30,
            ),
          ),
        ),
        child: Row(
          children: [
            const Icon(
              LucideIcons.listMusic,
              size: 16,
              color: SpotifyPlaylistsSection._spotifyGreen,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                subtitle,
                style: const TextStyle(
                  color: Color(0xFF0F172A),
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
  }
}

String _relativeTime(DateTime time) {
  final diff = DateTime.now().toUtc().difference(time.toUtc());
  if (diff.inMinutes < 1) return 'just now';
  if (diff.inHours < 1) return '${diff.inMinutes}m ago';
  if (diff.inDays < 1) return '${diff.inHours}h ago';
  return '${diff.inDays}d ago';
}

Future<void> _openPlaylistsSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (sheetCtx) {
      return DraggableScrollableSheet(
        initialChildSize: 0.85,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        expand: false,
        builder: (dsCtx, scrollController) {
          return _SpotifyPlaylistsSheetContent(scrollController: scrollController);
        },
      );
    },
  );
}

class _SpotifyPlaylistsSheetContent extends ConsumerWidget {
  const _SpotifyPlaylistsSheetContent({required this.scrollController});

  final ScrollController scrollController;

  static const _spotifyGreen = Color(0xFF1DB954);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playlistsAsync = ref.watch(spotifyPlaylistsControllerProvider);

    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF090D1A),
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Column(
        children: [
          const SizedBox(height: 12),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.white24,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 16),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                Icon(LucideIcons.listMusic, size: 18, color: _spotifyGreen),
                SizedBox(width: 8),
                Text(
                  'Your Playlists',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Text(
              'Only visible to you. Never shown on your public profile.',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.4),
                fontSize: 11,
              ),
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: playlistsAsync.when(
              data: (payload) => _PlaylistList(
                payload: payload,
                scrollController: scrollController,
              ),
              loading: () => const Center(child: NexusOrbitLoader(size: 40)),
              error: (_, _) => Center(
                child: Text(
                  "Couldn't load your playlists.",
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.5)),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PlaylistList extends StatelessWidget {
  const _PlaylistList({required this.payload, required this.scrollController});

  final SpotifyPlaylistsPayload payload;
  final ScrollController scrollController;

  @override
  Widget build(BuildContext context) {
    if (payload.playlists.isEmpty) {
      return Center(
        child: Text(
          payload.connected
              ? 'No owned or collaborative playlists found yet.'
              : 'Connect Spotify to sync your playlists.',
          style: TextStyle(color: Colors.white.withValues(alpha: 0.5)),
        ),
      );
    }

    return ListView.builder(
      controller: scrollController,
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
      itemCount: payload.playlists.length,
      itemBuilder: (context, index) => _PlaylistTile(
        playlist: payload.playlists[index],
      ),
    );
  }
}

class _PlaylistTile extends StatelessWidget {
  const _PlaylistTile({required this.playlist});

  final SpotifyPlaylist playlist;

  static const _spotifyGreen = Color(0xFF1DB954);

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          title: Text(
            playlist.name,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
          subtitle: Row(
            children: [
              Text(
                '${playlist.trackCount} track${playlist.trackCount == 1 ? '' : 's'}',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.4),
                  fontSize: 11,
                ),
              ),
              if (playlist.isCollaborative) ...[
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: _spotifyGreen.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Text(
                    'Collaborative',
                    style: TextStyle(
                      color: _spotifyGreen,
                      fontSize: 9,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ],
          ),
          trailing: IconButton(
            icon: const Icon(
              LucideIcons.externalLink,
              size: 16,
              color: Colors.white38,
            ),
            tooltip: 'Open in Spotify',
            onPressed: () => unawaited(_openInSpotify(playlist.spotifyUrl)),
          ),
          collapsedIconColor: Colors.white38,
          iconColor: Colors.white70,
          children: playlist.tracks
              .map(
                (track) => Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
                  child: Row(
                    children: [
                      const Icon(
                        LucideIcons.music,
                        size: 12,
                        color: Colors.white24,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              track.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                              ),
                            ),
                            if (track.artistLine.isNotEmpty)
                              Text(
                                track.artistLine,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.4),
                                  fontSize: 11,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              )
              .toList(),
        ),
      ),
    );
  }

  Future<void> _openInSpotify(String url) async {
    if (url.isEmpty) return;
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}
