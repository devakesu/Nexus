import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:emoji_picker_flutter/emoji_picker_flutter.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:nexus/providers/chat_conversation_provider.dart';
import 'package:nexus/screens/chats/widgets/location_picker_sheet.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

class ChatComposer extends StatefulWidget {
  const ChatComposer({
    required this.themeColor,
    required this.enabled,
    required this.sending,
    required this.onSend,
    required this.onSendImage,
    required this.onSendVoice,
    required this.onSendLocation,
    required this.onPlanEvent,
    super.key,
  });

  final Color themeColor;
  final bool enabled;
  final bool sending;
  final Future<void> Function(String text) onSend;
  final Future<void> Function(Uint8List bytes, String mimeType) onSendImage;
  final Future<void> Function(Uint8List bytes, String mimeType, int durationMs)
  onSendVoice;
  final Future<void> Function(double lat, double lng, String? label)
  onSendLocation;
  final VoidCallback onPlanEvent;

  @override
  State<ChatComposer> createState() => _ChatComposerState();
}

class _ChatComposerState extends State<ChatComposer> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  final _recorder = AudioRecorder();
  bool _emojiVisible = false;
  bool _recording = false;
  Duration _recordingElapsed = Duration.zero;
  Timer? _recordingTicker;

  @override
  void dispose() {
    _recordingTicker?.cancel();
    unawaited(_recorder.dispose());
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _toggleEmoji() {
    if (_emojiVisible) {
      setState(() => _emojiVisible = false);
      _focusNode.requestFocus();
    } else {
      _focusNode.unfocus();
      setState(() => _emojiVisible = true);
    }
  }

  Future<void> _handleSend() async {
    final text = _controller.text.trim();
    if (text.isEmpty || !widget.enabled || widget.sending) return;
    _controller.clear();
    await widget.onSend(text);
  }

  Future<void> _showAttachMenu() async {
    final option = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(LucideIcons.image),
              title: const Text('Photo'),
              onTap: () => Navigator.pop(ctx, 'photo'),
            ),
            ListTile(
              leading: const Icon(LucideIcons.mapPin),
              title: const Text('Location'),
              onTap: () => Navigator.pop(ctx, 'location'),
            ),
            ListTile(
              leading: const Icon(LucideIcons.calendarPlus),
              title: const Text('Plan a date'),
              onTap: () => Navigator.pop(ctx, 'event'),
            ),
          ],
        ),
      ),
    );
    if (option == null || !mounted) return;
    switch (option) {
      case 'photo':
        await _pickImage();
      case 'location':
        await _shareLocation();
      case 'event':
        widget.onPlanEvent();
    }
  }

  Future<void> _shareLocation() async {
    final result = await Navigator.of(context).push<LocationPointer>(
      MaterialPageRoute<LocationPointer>(
        fullscreenDialog: true,
        builder: (_) => LocationPickerSheet(themeColor: widget.themeColor),
      ),
    );
    if (result == null) return;
    await widget.onSendLocation(result.lat, result.lng, result.label);
  }

  Future<void> _pickImage() async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(LucideIcons.camera),
              title: const Text('Camera'),
              onTap: () => Navigator.pop(ctx, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(LucideIcons.image),
              title: const Text('Gallery'),
              onTap: () => Navigator.pop(ctx, ImageSource.gallery),
            ),
          ],
        ),
      ),
    );
    if (source == null || !mounted) return;

    final picked = await ImagePicker().pickImage(
      source: source,
      imageQuality: 82,
    );
    if (picked == null) return;

    final bytes = await picked.readAsBytes();
    await widget.onSendImage(bytes, picked.mimeType ?? 'image/jpeg');
  }

  Future<void> _startRecording() async {
    if (!widget.enabled) return;
    if (!await _recorder.hasPermission()) return;
    final dir = await getTemporaryDirectory();
    final path = '${dir.path}/rec_${DateTime.now().microsecondsSinceEpoch}.m4a';
    await _recorder.start(const RecordConfig(), path: path);
    if (!mounted) return;
    setState(() {
      _recording = true;
      _recordingElapsed = Duration.zero;
    });
    _recordingTicker = Timer.periodic(const Duration(milliseconds: 200), (_) {
      if (!mounted) return;
      setState(() => _recordingElapsed += const Duration(milliseconds: 200));
    });
  }

  Future<void> _stopRecording({required bool send}) async {
    _recordingTicker?.cancel();
    final path = await _recorder.stop();
    final elapsed = _recordingElapsed;
    if (mounted) setState(() => _recording = false);

    if (path == null) return;
    final file = File(path);
    if (!send) {
      if (file.existsSync()) await file.delete();
      return;
    }
    final bytes = await file.readAsBytes();
    if (file.existsSync()) await file.delete();
    await widget.onSendVoice(bytes, 'audio/m4a', elapsed.inMilliseconds);
  }

  String _formatElapsed(Duration d) {
    final minutes = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border(
              top: BorderSide(color: Colors.black.withValues(alpha: 0.06)),
            ),
          ),
          child: SafeArea(
            top: false,
            child: _recording ? _buildRecordingRow() : _buildComposerRow(),
          ),
        ),
        Offstage(
          offstage: !_emojiVisible,
          child: SizedBox(
            height: 256,
            child: EmojiPicker(
              textEditingController: _controller,
              config: Config(
                emojiViewConfig: const EmojiViewConfig(
                  backgroundColor: Colors.white,
                ),
                categoryViewConfig: CategoryViewConfig(
                  indicatorColor: widget.themeColor,
                  iconColorSelected: widget.themeColor,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildRecordingRow() {
    return Row(
      children: [
        IconButton(
          icon: const Icon(LucideIcons.trash2, color: Color(0xFF94A3B8)),
          tooltip: 'Discard recording',
          onPressed: () => unawaited(_stopRecording(send: false)),
        ),
        const SizedBox(width: 4),
        Container(
          width: 8,
          height: 8,
          decoration: const BoxDecoration(
            color: Color(0xFFEF4444),
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 8),
        Text(
          _formatElapsed(_recordingElapsed),
          style: const TextStyle(color: Color(0xFF334155), fontSize: 14),
        ),
        const Spacer(),
        CircleAvatar(
          radius: 20,
          backgroundColor: widget.themeColor,
          child: IconButton(
            icon: const Icon(LucideIcons.send, color: Colors.white, size: 18),
            tooltip: 'Send voice message',
            onPressed: () => unawaited(_stopRecording(send: true)),
          ),
        ),
      ],
    );
  }

  Widget _buildComposerRow() {
    final hasText = _controller.text.trim().isNotEmpty;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        IconButton(
          icon: Icon(
            _emojiVisible ? LucideIcons.keyboard : LucideIcons.smile,
            color: const Color(0xFF94A3B8),
          ),
          tooltip: _emojiVisible ? 'Show keyboard' : 'Show emoji picker',
          onPressed: widget.enabled ? _toggleEmoji : null,
        ),
        Expanded(
          child: Container(
            constraints: const BoxConstraints(maxHeight: 120),
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(
              color: const Color(0xFFF1F5F9),
              borderRadius: BorderRadius.circular(22),
            ),
            child: TextField(
              controller: _controller,
              focusNode: _focusNode,
              enabled: widget.enabled,
              minLines: 1,
              maxLines: 5,
              textCapitalization: TextCapitalization.sentences,
              onChanged: (_) => setState(() {}),
              onTap: () {
                if (_emojiVisible) setState(() => _emojiVisible = false);
              },
              decoration: InputDecoration(
                border: InputBorder.none,
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 10),
                hintText: widget.enabled
                    ? 'Message…'
                    : 'Waiting for a secure connection…',
              ),
            ),
          ),
        ),
        IconButton(
          icon: const Icon(LucideIcons.paperclip, color: Color(0xFF94A3B8)),
          tooltip: 'Attach',
          onPressed: widget.enabled ? () => unawaited(_showAttachMenu()) : null,
        ),
        CircleAvatar(
          radius: 20,
          backgroundColor: widget.enabled
              ? widget.themeColor
              : const Color(0xFFCBD5E1),
          child: widget.sending
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : IconButton(
                  icon: Icon(
                    hasText ? LucideIcons.send : LucideIcons.mic,
                    color: Colors.white,
                    size: 18,
                  ),
                  tooltip: hasText ? 'Send message' : 'Record voice message',
                  onPressed: !widget.enabled
                      ? null
                      : hasText
                      ? _handleSend
                      : () => unawaited(_startRecording()),
                ),
        ),
      ],
    );
  }
}
