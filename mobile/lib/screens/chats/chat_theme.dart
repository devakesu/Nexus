import 'package:flutter/material.dart';

/// Gradient pair for a discovery tab, matching the colors already used in
/// CommonHeader so the Chats page visually matches the rest of the app.
class ChatTabTheme {
  const ChatTabTheme(this.primary, this.secondary);

  final Color primary;
  final Color secondary;
}

const Map<String, ChatTabTheme> kChatTabThemes = {
  'Dating': ChatTabTheme(Color(0xFFFF2A54), Color(0xFFFF6B8B)),
  'Friends': ChatTabTheme(Color(0xFFD32F2F), Color(0xFFF57C00)),
  'Professional': ChatTabTheme(Color(0xFF00796B), Color(0xFF0097A7)),
};

ChatTabTheme chatTabTheme(String tab) =>
    kChatTabThemes[tab] ?? kChatTabThemes['Dating']!;
