import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:emoji_picker_flutter/emoji_picker_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart' hide Config;
import 'package:image_picker/image_picker.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:nexus/core/widgets/aesthetic_loaders.dart';
import 'package:nexus/core/widgets/nexus_toast.dart';
import 'package:nexus/features/chats/providers/chat_conversation_provider.dart';
import 'package:nexus/features/chats/widgets/location_picker_sheet.dart';
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
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.3),
      builder: (ctx) {
        return Container(
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.98),
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(28),
              topRight: Radius.circular(28),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.1),
                blurRadius: 20,
                offset: const Offset(0, -5),
              ),
            ],
          ),
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 38,
                    height: 5,
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'Share Content',
                    style: GoogleFonts.inter(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: const Color(0xFF0F172A),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _buildAttachGridItem(
                        ctx,
                        icon: LucideIcons.image,
                        label: 'Media / Photos',
                        value: 'photo',
                        gradientColors: [
                          const Color(0xFF818CF8),
                          const Color(0xFF6366F1),
                        ],
                        delayMs: 0,
                      ),
                      _buildAttachGridItem(
                        ctx,
                        icon: LucideIcons.mapPin,
                        label: 'Location',
                        value: 'location',
                        gradientColors: [
                          const Color(0xFF34D399),
                          const Color(0xFF059669),
                        ],
                        delayMs: 60,
                      ),
                      _buildAttachGridItem(
                        ctx,
                        icon: LucideIcons.calendarPlus,
                        label: 'Plan a Date',
                        value: 'event',
                        gradientColors: [
                          const Color(0xFFFB7185),
                          const Color(0xFFF43F5E),
                        ],
                        delayMs: 120,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
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

  Widget _buildAttachGridItem(
    BuildContext ctx, {
    required IconData icon,
    required String label,
    required String value,
    required List<Color> gradientColors,
    required int delayMs,
  }) {
    return GestureDetector(
          onTap: () => Navigator.pop(ctx, value),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: gradientColors,
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: gradientColors.last.withValues(alpha: 0.3),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Icon(
                  icon,
                  color: Colors.white,
                  size: 26,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                label,
                style: GoogleFonts.inter(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: const Color(0xFF475569),
                ),
              ),
            ],
          ),
        )
        .animate()
        .scale(
          delay: Duration(milliseconds: delayMs),
          duration: 350.ms,
          curve: Curves.easeOutBack,
        )
        .fadeIn(
          delay: Duration(milliseconds: delayMs),
        );
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
      backgroundColor: Colors.transparent,
      builder: (ctx) => Material(
        color: Colors.white.withValues(alpha: 0.98),
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(24),
          topRight: Radius.circular(24),
        ),
        clipBehavior: Clip.antiAlias,
        child: SafeArea(
          child: Wrap(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Center(
                  child: Container(
                    width: 38,
                    height: 5,
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                ),
              ),
              ListTile(
                leading: const Icon(
                  LucideIcons.camera,
                  color: Color(0xFF64748B),
                ),
                title: Text(
                  'Camera',
                  style: GoogleFonts.inter(fontWeight: FontWeight.w500),
                ),
                onTap: () => Navigator.pop(ctx, ImageSource.camera),
              ),
              ListTile(
                leading: const Icon(
                  LucideIcons.image,
                  color: Color(0xFF64748B),
                ),
                title: Text(
                  'Gallery',
                  style: GoogleFonts.inter(fontWeight: FontWeight.w500),
                ),
                onTap: () => Navigator.pop(ctx, ImageSource.gallery),
              ),
            ],
          ),
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
    final keyboardHeight = MediaQuery.of(context).viewInsets.bottom;
    final screenHeight = MediaQuery.of(context).size.height;
    final safeEmojiHeight = math
        .max(0, screenHeight - keyboardHeight - 200)
        .toDouble();
    final emojiHeight = math.min(320, safeEmojiHeight).toDouble();

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.95),
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(20),
              topRight: Radius.circular(20),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 10,
                offset: const Offset(0, -3),
              ),
            ],
            border: Border(
              top: BorderSide(color: Colors.black.withValues(alpha: 0.05)),
            ),
          ),
          child: SafeArea(
            top: false,
            child: _recording ? _buildRecordingRow() : _buildComposerRow(),
          ),
        ),
        Offstage(
          offstage: !_emojiVisible || emojiHeight < 50,
          child: SizedBox(
            height: emojiHeight,
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
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onHorizontalDragUpdate: (details) {
        if (details.primaryDelta != null && details.primaryDelta! < -8) {
          unawaited(_stopRecording(send: false));
          NexusToast.show(context, 'Recording discarded');
        }
      },
      child:
          Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFFFEF2F2),
                  borderRadius: BorderRadius.circular(28),
                  border: Border.all(color: const Color(0xFFFEE2E2)),
                ),
                child: Row(
                  children: [
                    IconButton(
                          icon: const Icon(
                            LucideIcons.trash2,
                            color: Color(0xFFEF4444),
                          ),
                          tooltip: 'Discard recording',
                          onPressed: () =>
                              unawaited(_stopRecording(send: false)),
                        )
                        .animate(
                          onPlay: (controller) =>
                              controller.repeat(reverse: true),
                        )
                        .shake(hz: 2, duration: 2.seconds),
                    const SizedBox(width: 8),
                    Container(
                          width: 8,
                          height: 8,
                          decoration: const BoxDecoration(
                            color: Color(0xFFEF4444),
                            shape: BoxShape.circle,
                          ),
                        )
                        .animate(
                          onPlay: (controller) =>
                              controller.repeat(reverse: true),
                        )
                        .scale(
                          begin: const Offset(0.7, 0.7),
                          end: const Offset(1.2, 1.2),
                          duration: 800.ms,
                        )
                        .fadeIn(begin: 0.5, duration: 800.ms),
                    const SizedBox(width: 8),
                    Text(
                      _formatElapsed(_recordingElapsed),
                      style: GoogleFonts.jetBrainsMono(
                        color: const Color(0xFF1E293B),
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Center(
                        child: AnimatedRecordingWave(),
                      ),
                    ),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                              LucideIcons.chevronLeft,
                              size: 14,
                              color: Color(0xFF94A3B8),
                            )
                            .animate(
                              onPlay: (controller) => controller.repeat(),
                            )
                            .moveX(begin: 4, end: -4, duration: 1.seconds)
                            .fadeOut(duration: 1.seconds),
                        const SizedBox(width: 2),
                        Text(
                          'Swipe left to cancel',
                          style: GoogleFonts.inter(
                            color: const Color(0xFF94A3B8),
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(width: 12),
                    GestureDetector(
                      onTap: () => unawaited(_stopRecording(send: true)),
                      child: Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: widget.themeColor,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: widget.themeColor.withValues(alpha: 0.35),
                              blurRadius: 10,
                              offset: const Offset(0, 3),
                            ),
                          ],
                        ),
                        child: const Center(
                          child: Icon(
                            LucideIcons.send,
                            color: Colors.white,
                            size: 18,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              )
              .animate()
              .slideX(
                begin: 0.1,
                end: 0,
                duration: 250.ms,
                curve: Curves.easeOutQuad,
              )
              .fadeIn(duration: 200.ms),
    );
  }

  Widget _buildComposerRow() {
    final hasText = _controller.text.trim().isNotEmpty;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        GestureDetector(
              onTap: widget.enabled ? _toggleEmoji : null,
              child: Container(
                padding: const EdgeInsets.all(8),
                child: Icon(
                  _emojiVisible ? LucideIcons.keyboard : LucideIcons.smile,
                  color: const Color(0xFF64748B),
                  size: 22,
                ),
              ),
            )
            .animate(target: widget.enabled ? 1.0 : 0.5)
            .fade()
            .scale(begin: const Offset(0.9, 0.9), duration: 150.ms),
        const SizedBox(width: 4),
        Expanded(
          child: Container(
            constraints: const BoxConstraints(maxHeight: 120),
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: const Color(0xFFE2E8F0),
                width: 1.5,
              ),
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
              style: GoogleFonts.inter(
                fontSize: 14.5,
                color: const Color(0xFF1E293B),
              ),
              decoration: InputDecoration(
                border: InputBorder.none,
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 10),
                hintText: widget.enabled
                    ? 'Message…'
                    : 'Waiting for a secure connection…',
                hintStyle: GoogleFonts.inter(
                  color: const Color(0xFF94A3B8),
                  fontSize: 14.5,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 4),
        GestureDetector(
              onTap: widget.enabled ? () => unawaited(_showAttachMenu()) : null,
              child: Container(
                padding: const EdgeInsets.all(8),
                child: const Icon(
                  LucideIcons.paperclip,
                  color: Color(0xFF64748B),
                  size: 22,
                ),
              ),
            )
            .animate(target: widget.enabled ? 1.0 : 0.5)
            .fade()
            .scale(begin: const Offset(0.9, 0.9), duration: 150.ms),
        const SizedBox(width: 6),
        GestureDetector(
              onTap: !widget.enabled
                  ? null
                  : hasText
                  ? _handleSend
                  : () => unawaited(_startRecording()),
              child: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: widget.enabled
                      ? widget.themeColor
                      : const Color(0xFFE2E8F0),
                  shape: BoxShape.circle,
                  boxShadow: widget.enabled
                      ? [
                          BoxShadow(
                            color: widget.themeColor.withValues(alpha: 0.3),
                            blurRadius: 8,
                            offset: const Offset(0, 3),
                          ),
                        ]
                      : null,
                ),
                child: widget.sending
                    ? const Center(child: NexusOrbitLoader(size: 18))
                    : Center(
                        child: Icon(
                          hasText ? LucideIcons.send : LucideIcons.mic,
                          color: Colors.white,
                          size: 18,
                        ),
                      ),
              ),
            )
            .animate(target: widget.enabled ? 1.0 : 0.5)
            .fade()
            .scale(begin: const Offset(0.95, 0.95), duration: 150.ms),
      ],
    );
  }
}

class AnimatedRecordingWave extends StatefulWidget {
  const AnimatedRecordingWave({super.key});

  @override
  State<AnimatedRecordingWave> createState() => _AnimatedRecordingWaveState();
}

class _AnimatedRecordingWaveState extends State<AnimatedRecordingWave>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  final List<double> _baseHeights = [12, 24, 18, 30, 14, 22, 28, 16, 20, 10];

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );
    unawaited(_controller.repeat());
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final availableWidth = constraints.maxWidth;
        // Each bar takes 6 pixels (3 width + 3 margin)
        final maxBars = (availableWidth / 6).floor().clamp(
          0,
          _baseHeights.length,
        );
        if (maxBars <= 1) {
          return const SizedBox.shrink();
        }
        return AnimatedBuilder(
          animation: _controller,
          builder: (context, child) {
            return Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(maxBars, (index) {
                final sineVal = math.sin(
                  _controller.value * 2 * math.pi + (index * 0.8),
                );
                final height =
                    _baseHeights[index] * (0.3 + 0.7 * (sineVal.abs()));
                return Container(
                  width: 3,
                  height: height.clamp(4.0, 30.0),
                  margin: const EdgeInsets.symmetric(horizontal: 1.5),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEF4444),
                    borderRadius: BorderRadius.circular(1.5),
                  ),
                );
              }),
            );
          },
        );
      },
    );
  }
}
