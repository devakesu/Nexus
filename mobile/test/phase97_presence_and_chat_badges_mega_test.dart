import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/features/chats/providers/presence_provider.dart';
import 'package:nexus/features/chats/widgets/presence_badge.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Phase 97 - Presence and Chat Badges Mega Tests', () {
    test('PresenceInfo model properties', () {
      final info = PresenceInfo(
        isOnline: true,
        lastActiveAt: DateTime.now().subtract(const Duration(minutes: 5)),
      );
      expect(info.isOnline, isTrue);
      expect(info.lastActiveAt, isNotNull);
    });

    testWidgets(
      'PresenceBadge renders fallback when no presence info is loaded',
      (
        tester,
      ) async {
        await tester.pumpWidget(
          const ProviderScope(
            child: MaterialApp(
              home: Scaffold(
                body: PresenceBadge(
                  peerUserId: 'u1',
                  poll: false,
                  fallback: Text('Offline'),
                ),
              ),
            ),
          ),
        );

        await tester.pump();
        expect(find.text('Offline'), findsOneWidget);
      },
    );
  });
}
