import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:just_audio/just_audio.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:nexus/providers/chat_conversation_provider.dart';
import 'package:nexus/widgets/aesthetic_loaders.dart';
import 'package:path_provider/path_provider.dart';

/// Decrypts a voice note to a private temp file (cleared on dispose) and
/// plays it via just_audio - simpler and more robust than a custom
/// StreamAudioSource, and voice notes are small enough that decrypting the
/// whole file up front is a non-issue.
class VoiceMessageBubble extends ConsumerStatefulWidget {
  const VoiceMessageBubble({
    required this.pointer,
    required this.conversationId,
    required this.peerUserId,
    required this.isMine,
    this.themeColor,
    super.key,
  });

  final MediaPointer pointer;
  final String conversationId;
  final String peerUserId;
  final bool isMine;
  final Color? themeColor;

  @override
  ConsumerState<VoiceMessageBubble> createState() => _VoiceMessageBubbleState();
}

class _VoiceMessageBubbleState extends ConsumerState<VoiceMessageBubble>
    with AutomaticKeepAliveClientMixin<VoiceMessageBubble> {
  final _player = AudioPlayer();
  File? _tempFile;
  bool _loading = false;
  bool _failed = false;
  bool _ready = false;

  // Without this, scrolling a played bubble off-screen and back would tear
  // down the AudioPlayer and temp file (see dispose()/_cleanupTempFile())
  // and force _ensureLoaded() to redo everything from scratch next tap.
  @override
  bool get wantKeepAlive => true;

  @override
  void dispose() {
    unawaited(_player.dispose());
    _cleanupTempFile();
    super.dispose();
  }

  void _cleanupTempFile() {
    final file = _tempFile;
    if (file != null && file.existsSync()) {
      try {
        file.deleteSync();
      } on Object catch (_) {
        // Best-effort cleanup.
      }
    }
  }

  Future<void> _ensureLoaded() async {
    if (_ready || _loading) return;
    setState(() => _loading = true);
    try {
      final notifier = ref.read(
        chatConversationControllerProvider(
          widget.conversationId,
          widget.peerUserId,
        ).notifier,
      );
      final bytes = await notifier.fetchMediaBytes(widget.pointer);
      final dir = await getTemporaryDirectory();
      final file = File(
        '${dir.path}/voice_${DateTime.now().microsecondsSinceEpoch}.m4a',
      );
      await file.writeAsBytes(bytes);
      _tempFile = file;
      await _player.setFilePath(file.path);
      if (!mounted) return;
      setState(() {
        _ready = true;
        _loading = false;
      });
    } on Exception {
      if (!mounted) return;
      setState(() {
        _failed = true;
        _loading = false;
      });
    }
  }

  Future<void> _togglePlay() async {
    if (_failed) return;
    await _ensureLoaded();
    if (!_ready) return;
    if (_player.playing) {
      await _player.pause();
    } else {
      if (_player.position >= (_player.duration ?? Duration.zero)) {
        await _player.seek(Duration.zero);
      }
      await _player.play();
    }
  }

  String _formatDuration(Duration d) {
    final minutes = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final isMine = widget.isMine;
    final primaryThemeColor = widget.themeColor ?? const Color(0xFF6366F1);
    final subColor = isMine
        ? Colors.white.withValues(alpha: 0.8)
        : const Color(0xFF64748B);
    final waveHighlightColor = isMine ? Colors.white : primaryThemeColor;

    return SizedBox(
      width: 200,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          GestureDetector(
            onTap: _togglePlay,
            child: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: (isMine ? Colors.white : primaryThemeColor)
                    .withValues(alpha: 0.15),
              ),
              child: _loading
                  ? Padding(
                      padding: const EdgeInsets.all(9),
                      child: NexusOrbitLoader(
                        size: 18,
                        lightMode: !isMine,
                      ),
                    )
                  : StreamBuilder<PlayerState>(
                      stream: _player.playerStateStream,
                      builder: (context, snapshot) {
                        final state = snapshot.data;
                        final playing = state?.playing ?? false;
                        final completed = state?.processingState == ProcessingState.completed;
                        final showPause = _ready && playing && !completed;

                        return Icon(
                          _failed
                              ? LucideIcons.triangleAlert
                              : (showPause ? LucideIcons.pause : LucideIcons.play),
                          color: isMine ? Colors.white : primaryThemeColor,
                          size: 18,
                        );
                      },
                    ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _failed
                ? Text(
                    'Voice message unavailable',
                    style: GoogleFonts.inter(fontSize: 12.5, color: subColor),
                  )
                : StreamBuilder<Duration>(
                    stream: _player.positionStream,
                    builder: (context, snapshot) {
                      final position = snapshot.data ?? Duration.zero;
                      final total =
                          _player.duration ??
                          Duration(
                            milliseconds: widget.pointer.durationMs ?? 0,
                          );
                      final progress = total.inMilliseconds > 0
                          ? (position.inMilliseconds / total.inMilliseconds).clamp(0.0, 1.0)
                          : 0.0;
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          StaticVoiceWaveform(
                            progress: progress,
                            isMine: isMine,
                            color: waveHighlightColor,
                          ),
                          const SizedBox(height: 6),
                          Text(
                            _formatDuration(_ready ? position : total),
                            style: GoogleFonts.inter(
                              fontSize: 11,
                              color: subColor,
                            ),
                          ),
                        ],
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class StaticVoiceWaveform extends StatelessWidget {
  const StaticVoiceWaveform({
    required this.progress,
    required this.isMine,
    required this.color,
    super.key,
  });

  final double progress;
  final bool isMine;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final heights = [10.0, 16.0, 12.0, 22.0, 8.0, 18.0, 14.0, 24.0, 10.0, 16.0, 12.0, 20.0, 6.0, 14.0, 10.0];
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: List.generate(heights.length, (index) {
        final barProgress = index / heights.length;
        final isPlayed = progress >= barProgress;
        return Container(
          width: 3,
          height: heights[index],
          decoration: BoxDecoration(
            color: isPlayed
                ? color
                : color.withValues(alpha: 0.25),
            borderRadius: BorderRadius.circular(1.5),
          ),
        );
      }),
    );
  }
}
