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
    super.key,
  });

  final MediaPointer pointer;
  final String conversationId;
  final String peerUserId;
  final bool isMine;

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
    final iconColor = isMine ? Colors.white : const Color(0xFF0F172A);
    final subColor = isMine
        ? Colors.white.withValues(alpha: 0.8)
        : const Color(0xFF94A3B8);

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
                color: (isMine ? Colors.white : const Color(0xFF0F172A))
                    .withValues(alpha: 0.12),
              ),
              child: _loading
                  ? Padding(
                      padding: const EdgeInsets.all(9),
                      child: NexusOrbitLoader(
                        size: 18,
                        lightMode: !isMine,
                      ),
                    )
                  : Icon(
                      _failed
                          ? LucideIcons.triangleAlert
                          : (_ready && _player.playing
                                ? LucideIcons.pause
                                : LucideIcons.play),
                      color: iconColor,
                      size: 18,
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
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SizedBox(
                            height: 4,
                            child: LinearProgressIndicator(
                              value: total.inMilliseconds > 0
                                  ? (position.inMilliseconds /
                                            total.inMilliseconds)
                                        .clamp(0.0, 1.0)
                                  : 0,
                              backgroundColor:
                                  (isMine
                                          ? Colors.white
                                          : const Color(0xFF0F172A))
                                      .withValues(alpha: 0.12),
                              valueColor: AlwaysStoppedAnimation(
                                isMine ? Colors.white : const Color(0xFF0F172A),
                              ),
                            ),
                          ),
                          const SizedBox(height: 4),
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
