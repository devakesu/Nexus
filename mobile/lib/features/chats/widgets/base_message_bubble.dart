import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class BaseMessageBubble extends StatelessWidget {
  const BaseMessageBubble({
    required this.isMine,
    required this.themeColor,
    required this.timeFormatted,
    required this.child,
    this.backgroundColor,
    this.textColor,
    this.padding,
    super.key,
  });

  final bool isMine;
  final Color themeColor;
  final String timeFormatted;
  final Widget child;
  final Color? backgroundColor;
  final Color? textColor;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    final bgColor =
        backgroundColor ?? (isMine ? themeColor : const Color(0xFF1E293B));
    final txtColor =
        textColor ??
        (isMine ? Colors.white : Colors.white.withValues(alpha: 0.85));

    return Align(
      alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 12),
        padding:
            padding ?? const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: Radius.circular(isMine ? 16 : 4),
            bottomRight: Radius.circular(isMine ? 4 : 16),
          ),
        ),
        child: Column(
          crossAxisAlignment: isMine
              ? CrossAxisAlignment.end
              : CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            child,
            const SizedBox(height: 4),
            Text(
              timeFormatted,
              style: GoogleFonts.inter(
                fontSize: 10,
                color: txtColor.withValues(alpha: 0.6),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
