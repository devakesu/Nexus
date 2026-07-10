import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:nexus/providers/chat_conversation_provider.dart';
import 'package:nexus/theme/app_colors.dart';
import 'package:nexus/widgets/aesthetic_loaders.dart';

/// Decrypts and renders an image attachment, fetched lazily (not eagerly
/// for the whole message list) via [ChatConversationController.fetchMediaBytes].
class ImageMessageBubble extends ConsumerStatefulWidget {
  const ImageMessageBubble({
    required this.pointer,
    required this.conversationId,
    required this.peerUserId,
    super.key,
  });

  final MediaPointer pointer;
  final String conversationId;
  final String peerUserId;

  @override
  ConsumerState<ImageMessageBubble> createState() => _ImageMessageBubbleState();
}

class _ImageMessageBubbleState extends ConsumerState<ImageMessageBubble> {
  Uint8List? _bytes;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    try {
      final notifier = ref.read(
        chatConversationControllerProvider(
          widget.conversationId,
          widget.peerUserId,
        ).notifier,
      );
      final bytes = await notifier.fetchMediaBytes(widget.pointer);
      if (!mounted) return;
      setState(() {
        _bytes = bytes;
        _loading = false;
      });
    } on Exception {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  void _openFullScreen() {
    final bytes = _bytes;
    if (bytes == null) return;
    unawaited(
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          fullscreenDialog: true,
          builder: (_) => _FullScreenImageViewer(bytes: bytes),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    const size = 220.0;
    if (_loading) {
      return const SizedBox(
        width: size,
        height: size,
        child: DecoratedBox(
          decoration: BoxDecoration(color: Color(0xFFF1F5F9)),
          child: Center(child: NexusOrbitLoader(size: 32)),
        ),
      );
    }
    final bytes = _bytes;
    if (bytes == null) {
      return const SizedBox(
        width: size,
        height: 120,
        child: DecoratedBox(
          decoration: BoxDecoration(color: Color(0xFFFEF2F2)),
          child: Center(
            child: Icon(LucideIcons.imageOff, color: AppColors.error),
          ),
        ),
      );
    }
    return GestureDetector(
      onTap: _openFullScreen,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: Image.memory(
          bytes,
          width: size,
          height: size,
          fit: BoxFit.cover,
        ),
      ),
    );
  }
}

class _FullScreenImageViewer extends StatelessWidget {
  const _FullScreenImageViewer({required this.bytes});

  final Uint8List bytes;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      extendBodyBehindAppBar: true,
      body: Center(
        child: InteractiveViewer(child: Image.memory(bytes)),
      ),
    );
  }
}
