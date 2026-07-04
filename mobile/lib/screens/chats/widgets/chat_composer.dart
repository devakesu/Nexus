import 'package:emoji_picker_flutter/emoji_picker_flutter.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

class ChatComposer extends StatefulWidget {
  const ChatComposer({
    required this.themeColor,
    required this.enabled,
    required this.sending,
    required this.onSend,
    super.key,
  });

  final Color themeColor;
  final bool enabled;
  final bool sending;
  final Future<void> Function(String text) onSend;

  @override
  State<ChatComposer> createState() => _ChatComposerState();
}

class _ChatComposerState extends State<ChatComposer> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  bool _emojiVisible = false;

  @override
  void dispose() {
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
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                IconButton(
                  icon: Icon(
                    _emojiVisible ? LucideIcons.keyboard : LucideIcons.smile,
                    color: const Color(0xFF94A3B8),
                  ),
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
                const SizedBox(width: 6),
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
                          icon: const Icon(
                            LucideIcons.send,
                            color: Colors.white,
                            size: 18,
                          ),
                          onPressed: widget.enabled ? _handleSend : null,
                        ),
                ),
              ],
            ),
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
}
