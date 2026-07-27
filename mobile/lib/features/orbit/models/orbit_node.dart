class OrbitNode {
  OrbitNode({
    required this.id,
    required this.name,
    required this.x,
    required this.y,
    required this.orbitTier,
    required this.score,
    required this.profilePic,
    this.gender,
    this.sexuality,
    this.connectionType,
    this.matchStatus,
    this.isNew = false,
  });

  factory OrbitNode.fromJson(Map<String, dynamic> json) {
    return OrbitNode(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? 'Anonymous',
      x: (json['x'] as num?)?.toDouble() ?? 0.0,
      y: (json['y'] as num?)?.toDouble() ?? 0.0,
      orbitTier: (json['orbit_tier'] as num?)?.toInt() ?? 0,
      score: (json['score'] as num?)?.toDouble() ?? 0.0,
      profilePic: json['profile_pic']?.toString(),
      gender: json['gender']?.toString(),
      sexuality: json['sexuality']?.toString(),
      connectionType: json['connection_type']?.toString(),
      matchStatus: json['match_status']?.toString(),
      isNew: json['is_new'] as bool? ?? false,
    );
  }

  final String id;
  final String name;
  final double x;
  final double y;
  final int orbitTier;
  final double score;
  final String? profilePic;
  final String? gender;
  final String? sexuality;
  final String? connectionType;
  final String? matchStatus;
  final bool isNew;

  OrbitNode copyWith({
    String? id,
    String? name,
    double? x,
    double? y,
    int? orbitTier,
    double? score,
    String? profilePic,
    String? gender,
    String? sexuality,
    String? connectionType,
    String? matchStatus,
    bool? isNew,
  }) {
    return OrbitNode(
      id: id ?? this.id,
      name: name ?? this.name,
      x: x ?? this.x,
      y: y ?? this.y,
      orbitTier: orbitTier ?? this.orbitTier,
      score: score ?? this.score,
      profilePic: profilePic ?? this.profilePic,
      gender: gender ?? this.gender,
      sexuality: sexuality ?? this.sexuality,
      connectionType: connectionType ?? this.connectionType,
      matchStatus: matchStatus ?? this.matchStatus,
      isNew: isNew ?? this.isNew,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'x': x,
      'y': y,
      'orbit_tier': orbitTier,
      'score': score,
      'profile_pic': profilePic,
      'gender': gender,
      'sexuality': sexuality,
      'connection_type': connectionType,
      'match_status': matchStatus,
      'is_new': isNew,
    };
  }
}

class OrbitPrefetchResult {
  OrbitPrefetchResult({
    required this.nodes,
    required this.sessionId,
    required this.profilePicUrl,
    this.showBuckets = const [],
    this.datingFor = const [],
    this.partnerValues = const [],
  });

  final List<OrbitNode> nodes;
  final String? sessionId;
  final String? profilePicUrl;
  final List<String> showBuckets;
  final List<String> datingFor;
  final List<String> partnerValues;
}
