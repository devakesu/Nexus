import 'package:dio/dio.dart';
import 'package:nexus/core/utils/network_utils.dart';

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

void setupGlobalMockNetwork() {
  final dio = createDio();
  dio.interceptors.removeWhere((i) => i is _MockNetworkInterceptor);
  dio.interceptors.insert(0, _MockNetworkInterceptor());
}

class _MockNetworkInterceptor extends Interceptor {
  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    if (options.extra['bypass_mock'] == true ||
        !createDio().httpClientAdapter.runtimeType.toString().contains(
          'IOHttpClientAdapter',
        )) {
      return handler.next(options);
    }

    final path = options.path;

    if (path.contains('/api/v1/profile/details') ||
        (path.endsWith('/profile/details'))) {
      return handler.resolve(
        Response(
          requestOptions: options,
          statusCode: 200,
          data: kFullMockProfile,
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

    return handler.next(options);
  }
}
