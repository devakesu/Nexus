import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:nexus/screens/auth_gate.dart';
import 'package:nexus/screens/chats/chat_conversation_page.dart';
import 'package:nexus/screens/chats/chats_page.dart';
import 'package:nexus/screens/legal_terms_page.dart';
import 'package:nexus/screens/orbit_screen.dart';
import 'package:nexus/screens/settings/blocked_users_page.dart';
import 'package:nexus/screens/settings/community_guidelines_page.dart';
import 'package:nexus/screens/settings/delete_account_page.dart';
import 'package:nexus/screens/settings/email_notification_settings_page.dart';
import 'package:nexus/screens/settings/feedback_page.dart';
import 'package:nexus/screens/settings/help_center_page.dart';
import 'package:nexus/screens/settings/hidden_users_page.dart';
import 'package:nexus/screens/settings/privacy_settings_page.dart';
import 'package:nexus/screens/settings/safety_center_page.dart';
import 'package:nexus/utils/error_handler.dart';

final goRouter = GoRouter(
  navigatorKey: ErrorHandler.navigatorKey,
  initialLocation: '/',
  routes: [
    GoRoute(
      path: '/',
      builder: (context, state) {
        const flavor = String.fromEnvironment('FLUTTER_APP_FLAVOR');
        const isMec = flavor == 'nexus_mec';
        const appName = isMec ? 'Nexus MEC' : 'Nexus';
        return const AuthGate(appName: appName);
      },
    ),
    GoRoute(
      path: '/login',
      builder: (context, state) {
        const flavor = String.fromEnvironment('FLUTTER_APP_FLAVOR');
        const isMec = flavor == 'nexus_mec';
        const appName = isMec ? 'Nexus MEC' : 'Nexus';
        return const AuthGate(appName: appName);
      },
    ),
    GoRoute(
      path: '/orbit',
      builder: (context, state) {
        final extra = state.extra as Map<String, dynamic>?;
        if (extra == null ||
            extra['tab'] == null ||
            extra['themeColor'] == null) {
          const flavor = String.fromEnvironment('FLUTTER_APP_FLAVOR');
          const isMec = flavor == 'nexus_mec';
          const appName = isMec ? 'Nexus MEC' : 'Nexus';
          return const AuthGate(appName: appName);
        }
        return OrbitScreen(
          tab: extra['tab']! as String,
          themeColor: extra['themeColor']! as Color,
          prefetchFuture:
              extra['prefetchFuture'] as Future<OrbitPrefetchResult?>?,
        );
      },
    ),
    GoRoute(
      path: '/chats',
      builder: (context, state) => const ChatsPage(),
    ),
    GoRoute(
      path: '/chat-conversation',
      builder: (context, state) {
        final extra = state.extra as Map<String, dynamic>?;
        if (extra == null ||
            extra['conversationId'] == null ||
            extra['matchedUserId'] == null ||
            extra['tab'] == null ||
            extra['name'] == null) {
          const flavor = String.fromEnvironment('FLUTTER_APP_FLAVOR');
          const isMec = flavor == 'nexus_mec';
          const appName = isMec ? 'Nexus MEC' : 'Nexus';
          return const AuthGate(appName: appName);
        }
        return ChatConversationPage(
          conversationId: extra['conversationId']! as String,
          matchedUserId: extra['matchedUserId']! as String,
          tab: extra['tab']! as String,
          name: extra['name']! as String,
          profilePic: extra['profilePic'] as String?,
        );
      },
    ),
    GoRoute(
      path: '/settings/blocked-users',
      builder: (context, state) => const BlockedUsersPage(),
    ),
    GoRoute(
      path: '/settings/privacy',
      builder: (context, state) => const PrivacySettingsPage(),
    ),
    GoRoute(
      path: '/settings/hidden-users',
      builder: (context, state) => const HiddenUsersPage(),
    ),
    GoRoute(
      path: '/settings/safety-center',
      builder: (context, state) => const SafetyCenterPage(),
    ),
    GoRoute(
      path: '/settings/help-center',
      builder: (context, state) => const HelpCenterPage(),
    ),
    GoRoute(
      path: '/settings/feedback',
      builder: (context, state) => const FeedbackPage(),
    ),
    GoRoute(
      path: '/settings/delete-account',
      builder: (context, state) => const DeleteAccountPage(),
    ),
    GoRoute(
      path: '/settings/email-notifications',
      builder: (context, state) => const EmailNotificationSettingsPage(),
    ),
    GoRoute(
      path: '/settings/community-guidelines',
      builder: (context, state) => const CommunityGuidelinesPage(),
    ),
    GoRoute(
      path: '/legal',
      builder: (context, state) => const LegalTermsPage(),
    ),
  ],
);
