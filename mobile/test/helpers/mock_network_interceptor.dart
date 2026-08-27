import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:nexus/core/utils/network_utils.dart';

Map<String, dynamic>? globalMockProfileOverride;

const kFullMockProfile = <String, dynamic>{
  'name': 'Alex Rivera',
  'birth_date': '1998-05-15',
  'gender': 'Non-binary',
  'bio': 'Software engineer and climber in SF.',
  'ordered_images': [
    'https://images.unsplash.com/photo-1534528741775-53994a69daeb?w=500',
    'https://images.unsplash.com/photo-1507003211169-0a1dd7228f2d?w=500',
    'https://images.unsplash.com/photo-1517841905240-472988babdf9?w=500',
  ],
  'interests': ['Coding', 'Climbing', 'Coffee', 'Sci-Fi', 'Running', 'Cooking'],
  'hometown_city': 'Seattle',
  'current_city': 'San Francisco',
  'drinking_preference': 'Socially',
  'smoking_preference': 'Never',
  'languages_spoken': ['English', 'Spanish'],
  'job_title': 'Senior Engineer',
  'company': 'Tech Corp',
  'university': 'Stanford University',
  'major': 'Computer Science',
  'graduation_year': 2020,
  'dating_intent': 'Long-term partnership',
  'children_plans': 'Want children',
  'religious_beliefs': 'Agnostic',
  'sexual_orientation': 'Queer',
  'tech_skills': ['Flutter', 'Dart', 'Python', 'Go'],
  'professional_interests': ['Startups', 'AI/ML'],
  'friendship_goals': ['Explore city', 'Weekend sports'],
  'dealbreakers': ['Smoking'],
  'partner_values': ['Honesty', 'Ambition'],
  'dating_target_buckets': ['Women', 'Non-binary'],
  'dating_for': ['Relationship'],
  'is_dating_active': true,
  'is_friends_active': true,
  'is_professional_active': true,
  'dating_orbit_active': true,
  'friends_orbit_active': true,
  'professional_orbit_active': true,
  'instagram_handle': 'alex_climbs',
  'spotify_top_artists': ['Radiohead', 'Bon Iver', 'Phoebe Bridgers'],
  'spotify_playlists': [
    {'name': 'Deep Focus', 'url': 'https://open.spotify.com/playlist/123'},
  ],
};

const kFullMockHub = <String, dynamic>{
  'profileDetails': kFullMockProfile,
  'unseenCount': 2,
  'likes': [
    {
      'actor_id': 'u2',
      'name': 'Taylor',
      'age': 26,
      'gender': 'Woman',
      'bio': 'Designer and photographer',
      'city': 'San Francisco',
      'avatar_url':
          'https://images.unsplash.com/photo-1494790108377-be9c29b29330?w=500',
      'compatibility_score': 94,
    },
  ],
  'matches': [
    {
      'match_id': 'm1',
      'matched_user_id': 'u2',
      'conversation_id': 'c1',
      'name': 'Taylor',
      'avatar_url':
          'https://images.unsplash.com/photo-1494790108377-be9c29b29330?w=500',
      'last_message': 'Hey!',
      'last_active_at': '2026-08-27T12:00:00Z',
    },
  ],
};

final kFullMockTicketDetail = <String, dynamic>{
  'id': 'tk_123',
  'query_type': 'feedback',
  'subject': 'App Feedback',
  'message': 'Everything is working smoothly!',
  'github_issue_url': null,
  'attachment_paths': <String>[],
  'app_version': '1.0.8',
  'platform': 'iOS',
  'status': 'open',
  'created_at': '2026-08-27T12:00:00.000Z',
  'updated_at': '2026-08-27T12:00:00.000Z',
  'status_history': <Map<String, dynamic>>[
    {
      'status': 'open',
      'created_at': '2026-08-27T12:00:00.000Z',
      'note': 'Ticket submitted',
    },
  ],
  'comments': <Map<String, dynamic>>[
    {
      'id': 'c_1',
      'author_id': 'staff_1',
      'body': 'Thanks for submitting!',
      'created_at': '2026-08-27T12:30:00.000Z',
      'is_own': false,
    },
  ],
};

void setupGlobalMockNetwork() {
  final dio = createDio();
  dio.interceptors.removeWhere((i) => i is _MockNetworkInterceptor);
  dio.interceptors.insert(0, _MockNetworkInterceptor());
}

class _MockNetworkInterceptor extends Interceptor {
  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    if (options.extra['bypass_mock'] == true ||
        options.headers['bypass_mock'] == true) {
      return handler.next(options);
    }

    final adapter = createDio().httpClientAdapter;
    if (adapter is! IOHttpClientAdapter) {
      return handler.next(options);
    }

    final path = options.path;

    if (path.contains('/api/v1/profile/details') ||
        (path.endsWith('/profile/details'))) {
      return handler.resolve(
        Response(
          requestOptions: options,
          statusCode: 200,
          data: globalMockProfileOverride ?? kFullMockProfile,
        ),
      );
    }

    if (path.contains('/api/v1/profile/email-notification-settings') ||
        path.endsWith('/email-notification-settings')) {
      return handler.resolve(
        Response(
          requestOptions: options,
          statusCode: 200,
          data: {
            'email_notify_matches': true,
            'email_notify_messages': true,
            'email_notify_digest': true,
            'email_notify_product_updates': true,
            'email_notify_promotions': true,
          },
        ),
      );
    }

    if (path.contains('/api/v1/profile/privacy-settings') ||
        path.endsWith('/privacy-settings')) {
      return handler.resolve(
        Response(
          requestOptions: options,
          statusCode: 200,
          data: {
            'hidden_fields': <String>[],
            'share_active_status': true,
            'share_read_receipts': true,
          },
        ),
      );
    }

    if (path.contains('/api/v1/discover') || path.endsWith('/discover')) {
      return handler.resolve(
        Response(
          requestOptions: options,
          statusCode: 200,
          data: {
            'nodes': [
              {
                'id': 'n1',
                'name': 'Sarah',
                'x': 100.0,
                'y': 200.0,
                'orbit_tier': 1,
                'score': 92.0,
                'profile_pic': 'https://example.com/pic.png',
                'gender': 'Woman',
              },
              {
                'id': 'n2',
                'name': 'Jordan',
                'x': -150.0,
                'y': 150.0,
                'orbit_tier': 2,
                'score': 85.0,
                'profile_pic': 'https://example.com/pic2.png',
                'gender': 'Man',
              },
            ],
            'session_id': 'sess-123',
          },
        ),
      );
    }

    if (path.contains('/discovery-hub') || path.endsWith('/hub')) {
      return handler.resolve(
        Response(
          requestOptions: options,
          statusCode: 200,
          data: kFullMockHub,
        ),
      );
    }

    if (path.contains('/record-match-action') ||
        path.contains('/match/action')) {
      return handler.resolve(
        Response(
          requestOptions: options,
          statusCode: 200,
          data: {'status': 'success', 'match_id': 'm1'},
        ),
      );
    }

    if (path.contains('/api/v1/feedback/mine')) {
      return handler.resolve(
        Response(
          requestOptions: options,
          statusCode: 200,
          data: [
            {
              'id': 'tk_123',
              'query_type': 'feedback',
              'subject': 'App Feedback',
              'message': 'Everything is working smoothly!',
              'status': 'open',
              'created_at': '2026-08-27T12:00:00.000Z',
              'updated_at': '2026-08-27T12:00:00.000Z',
            },
          ],
        ),
      );
    }

    if (path.contains('/comments') && path.contains('/feedback/')) {
      return handler.resolve(
        Response(
          requestOptions: options,
          statusCode: 200,
          data: {'status': 'success', 'comment_id': 'c_1'},
        ),
      );
    }

    if (path.contains('/close') && path.contains('/feedback/')) {
      return handler.resolve(
        Response(
          requestOptions: options,
          statusCode: 200,
          data: {'status': 'success'},
        ),
      );
    }

    if (path.contains('/submit') && path.contains('/feedback')) {
      return handler.resolve(
        Response(
          requestOptions: options,
          statusCode: 200,
          data: {
            'status': 'success',
            'report_id': 'tk_123',
            'ticket_id': 'tk_123',
          },
        ),
      );
    }

    if (path.contains('/feedback') || path.contains('/tickets')) {
      return handler.resolve(
        Response(
          requestOptions: options,
          statusCode: 200,
          data: kFullMockTicketDetail,
        ),
      );
    }

    return handler.next(options);
  }
}
