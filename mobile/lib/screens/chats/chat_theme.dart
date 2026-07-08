import 'package:flutter/material.dart';

/// Gradient pair for a discovery tab, matching the colors already used in
/// CommonHeader so the Chats page visually matches the rest of the app.
class ChatTabTheme {
  const ChatTabTheme(this.primary, this.secondary);

  final Color primary;
  final Color secondary;
}

// Primaries match each mode's Mode Signal color from the bottom nav
// (custom_bottom_nav_bar.dart) exactly — DESIGN.md's Mode Signal Rule
// requires one consistent accent per mode across nav, chat, and filters.
// Secondaries are a lightened tint of that same primary, used only as the
// gradient's far stop.
const Map<String, ChatTabTheme> kChatTabThemes = {
  'Dating': ChatTabTheme(Color(0xFFFF4F81), Color(0xFFFF8DAD)),
  'Friends': ChatTabTheme(Color(0xFFA45E00), Color(0xFFC49659)),
  'Professional': ChatTabTheme(Color(0xFF007E6D), Color(0xFF59ABA0)),
};

ChatTabTheme chatTabTheme(String tab) =>
    kChatTabThemes[tab] ?? kChatTabThemes['Dating']!;
