import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:nexus/theme/app_colors.dart';

// ---------------------------------------------------------------------------
// Query type (help / feedback / bug report)
// ---------------------------------------------------------------------------

enum FeedbackQueryType {
  help,
  suspended,
  legalGrievance,
  feedback,
  bugReport,
  security,
  other,
}

extension FeedbackQueryTypeX on FeedbackQueryType {
  String get apiValue => switch (this) {
    FeedbackQueryType.help => 'help',
    FeedbackQueryType.suspended => 'suspended',
    FeedbackQueryType.legalGrievance => 'legal_grievance',
    FeedbackQueryType.feedback => 'feedback',
    FeedbackQueryType.bugReport => 'bug_report',
    FeedbackQueryType.security => 'security',
    FeedbackQueryType.other => 'other',
  };

  String get label => switch (this) {
    FeedbackQueryType.help => 'General Support',
    FeedbackQueryType.suspended => 'Suspended Account',
    FeedbackQueryType.legalGrievance => 'Legal Grievance',
    FeedbackQueryType.feedback => 'Product Feedback',
    FeedbackQueryType.bugReport => 'Bug Report',
    FeedbackQueryType.security => 'Security & Privacy',
    FeedbackQueryType.other => 'Other Inquiry',
  };

  String get description => switch (this) {
    FeedbackQueryType.help => 'Get help with account, orbits or settings',
    FeedbackQueryType.suspended => 'Appeal account suspension or restriction',
    FeedbackQueryType.legalGrievance => 'File formal complaint or legal notice',
    FeedbackQueryType.feedback => 'Share suggestions or feature requests',
    FeedbackQueryType.bugReport => 'Report crashes or broken functionality',
    FeedbackQueryType.security => 'Vulnerability disclosure or privacy',
    FeedbackQueryType.other => 'Questions or general inquiries',
  };

  IconData get icon => switch (this) {
    FeedbackQueryType.help => LucideIcons.circleHelp,
    FeedbackQueryType.suspended => LucideIcons.shieldOff,
    FeedbackQueryType.legalGrievance => LucideIcons.scale,
    FeedbackQueryType.feedback => LucideIcons.lightbulb,
    FeedbackQueryType.bugReport => LucideIcons.bug,
    FeedbackQueryType.security => LucideIcons.lock,
    FeedbackQueryType.other => LucideIcons.messageSquare,
  };

  Color get accentColor => switch (this) {
    FeedbackQueryType.help => const Color(0xFF3B82F6), // Blue
    FeedbackQueryType.suspended => const Color(0xFFEF4444), // Red
    FeedbackQueryType.legalGrievance => const Color(0xFF8B5CF6), // Purple
    FeedbackQueryType.feedback => const Color(0xFFF59E0B), // Amber
    FeedbackQueryType.bugReport => const Color(0xFFEC4899), // Pink
    FeedbackQueryType.security => const Color(0xFF10B981), // Emerald
    FeedbackQueryType.other => const Color(0xFF6366F1), // Indigo
  };

  String get subjectHint => switch (this) {
    FeedbackQueryType.help => 'e.g. How do I pause my Orbits?',
    FeedbackQueryType.suspended => 'e.g. Appeal for suspended account',
    FeedbackQueryType.legalGrievance =>
      'e.g. Formal grievance regarding privacy',
    FeedbackQueryType.feedback => 'e.g. Add a dark mode toggle',
    FeedbackQueryType.bugReport => 'e.g. Chat crashes when sending a photo',
    FeedbackQueryType.security => 'e.g. Security advisory or privacy question',
    FeedbackQueryType.other => 'e.g. Inquiry about Nexus services',
  };

  String get messageHint => switch (this) {
    FeedbackQueryType.help =>
      'Tell us what you were trying to do and where you got stuck.',
    FeedbackQueryType.suspended =>
      'Provide details and context for your account suspension appeal.',
    FeedbackQueryType.legalGrievance =>
      'Describe your formal legal complaint or statutory grievance in detail.',
    FeedbackQueryType.feedback =>
      "Share what's on your mind - we read every word.",
    FeedbackQueryType.bugReport =>
      'What did you expect to happen, and what happened instead? '
          'Steps to reproduce help a lot.',
    FeedbackQueryType.security =>
      'Describe the security vulnerability or privacy concern in detail.',
    FeedbackQueryType.other =>
      'Please describe your issue or question in detail.',
  };
}

FeedbackQueryType feedbackQueryTypeFromApiValue(String value) {
  return switch (value) {
    'suspended' => FeedbackQueryType.suspended,
    'legal_grievance' || 'grievance' => FeedbackQueryType.legalGrievance,
    'security' => FeedbackQueryType.security,
    'feedback' => FeedbackQueryType.feedback,
    'bug_report' => FeedbackQueryType.bugReport,
    'other' => FeedbackQueryType.other,
    _ => FeedbackQueryType.help,
  };
}

// ---------------------------------------------------------------------------
// Status
// ---------------------------------------------------------------------------

enum FeedbackStatus { open, inProgress, resolved, closed }

extension FeedbackStatusX on FeedbackStatus {
  String get apiValue => switch (this) {
    FeedbackStatus.open => 'open',
    FeedbackStatus.inProgress => 'in_progress',
    FeedbackStatus.resolved => 'resolved',
    FeedbackStatus.closed => 'closed',
  };

  String get label => switch (this) {
    FeedbackStatus.open => 'Open',
    FeedbackStatus.inProgress => 'In Progress',
    FeedbackStatus.resolved => 'Resolved',
    FeedbackStatus.closed => 'Closed',
  };

  Color get color => switch (this) {
    FeedbackStatus.open => AppColors.safetyBlue,
    FeedbackStatus.inProgress => const Color(0xFFD97706),
    FeedbackStatus.resolved => AppColors.success,
    FeedbackStatus.closed => const Color(0xFF64748B),
  };

  IconData get icon => switch (this) {
    FeedbackStatus.open => LucideIcons.circleDot,
    FeedbackStatus.inProgress => LucideIcons.loader,
    FeedbackStatus.resolved => LucideIcons.checkCircle2,
    FeedbackStatus.closed => LucideIcons.circleSlash,
  };

  bool get isTerminal =>
      this == FeedbackStatus.closed || this == FeedbackStatus.resolved;
}

FeedbackStatus feedbackStatusFromApiValue(String value) {
  return switch (value) {
    'in_progress' => FeedbackStatus.inProgress,
    'resolved' => FeedbackStatus.resolved,
    'closed' => FeedbackStatus.closed,
    _ => FeedbackStatus.open,
  };
}

class FeedbackStatusBadge extends StatelessWidget {
  const FeedbackStatusBadge({
    required this.status,
    super.key,
    this.compact = false,
  });

  final FeedbackStatus status;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 8 : 10,
        vertical: compact ? 3 : 5,
      ),
      decoration: BoxDecoration(
        color: status.color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(status.icon, size: compact ? 10 : 12, color: status.color),
          const SizedBox(width: 4),
          Text(
            status.label,
            style: GoogleFonts.manrope(
              fontSize: compact ? 10 : 11,
              fontWeight: FontWeight.w800,
              color: status.color,
              letterSpacing: 0.3,
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Data models
// ---------------------------------------------------------------------------

class FeedbackTicketSummary {
  FeedbackTicketSummary({
    required this.id,
    required this.queryType,
    required this.subject,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
  });

  factory FeedbackTicketSummary.fromJson(Map<String, dynamic> json) {
    return FeedbackTicketSummary(
      id: json['id'] as String,
      queryType: feedbackQueryTypeFromApiValue(json['query_type'] as String),
      subject: json['subject'] as String,
      status: feedbackStatusFromApiValue(json['status'] as String),
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
  }

  final String id;
  final FeedbackQueryType queryType;
  final String subject;
  final FeedbackStatus status;
  final DateTime createdAt;
  final DateTime updatedAt;
}

class FeedbackStatusHistoryEntry {
  FeedbackStatusHistoryEntry({
    required this.status,
    required this.createdAt,
    this.note,
    this.changedBy,
  });

  factory FeedbackStatusHistoryEntry.fromJson(Map<String, dynamic> json) {
    return FeedbackStatusHistoryEntry(
      status: feedbackStatusFromApiValue(json['status'] as String),
      note: json['note'] as String?,
      changedBy: json['changed_by'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  final FeedbackStatus status;
  final String? note;
  final String? changedBy;
  final DateTime createdAt;
}

class FeedbackCommentEntry {
  FeedbackCommentEntry({
    required this.id,
    required this.authorId,
    required this.body,
    required this.createdAt,
    required this.isOwn,
  });

  factory FeedbackCommentEntry.fromJson(Map<String, dynamic> json) {
    return FeedbackCommentEntry(
      id: json['id'] as String,
      authorId: json['author_id'] as String,
      body: json['body'] as String,
      createdAt: DateTime.parse(json['created_at'] as String),
      isOwn: json['is_own'] as bool? ?? false,
    );
  }

  final String id;
  final String authorId;
  final String body;
  final DateTime createdAt;
  final bool isOwn;
}

class FeedbackTicketDetail {
  FeedbackTicketDetail({
    required this.id,
    required this.queryType,
    required this.subject,
    required this.message,
    required this.attachmentPaths,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
    required this.statusHistory,
    required this.comments,
    this.githubIssueUrl,
    this.appVersion,
    this.platform,
  });

  factory FeedbackTicketDetail.fromJson(Map<String, dynamic> json) {
    return FeedbackTicketDetail(
      id: json['id'] as String,
      queryType: feedbackQueryTypeFromApiValue(json['query_type'] as String),
      subject: json['subject'] as String,
      message: json['message'] as String,
      githubIssueUrl: json['github_issue_url'] as String?,
      attachmentPaths: (json['attachment_paths'] as List<dynamic>? ?? [])
          .map((e) => e.toString())
          .toList(),
      appVersion: json['app_version'] as String?,
      platform: json['platform'] as String?,
      status: feedbackStatusFromApiValue(json['status'] as String),
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
      statusHistory: (json['status_history'] as List<dynamic>? ?? [])
          .map(
            (e) =>
                FeedbackStatusHistoryEntry.fromJson(e as Map<String, dynamic>),
          )
          .toList(),
      comments: (json['comments'] as List<dynamic>? ?? [])
          .map((e) => FeedbackCommentEntry.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }

  final String id;
  final FeedbackQueryType queryType;
  final String subject;
  final String message;
  final String? githubIssueUrl;
  final List<String> attachmentPaths;
  final String? appVersion;
  final String? platform;
  final FeedbackStatus status;
  final DateTime createdAt;
  final DateTime updatedAt;
  final List<FeedbackStatusHistoryEntry> statusHistory;
  final List<FeedbackCommentEntry> comments;
}

// ---------------------------------------------------------------------------
// Shared formatting
// ---------------------------------------------------------------------------

String feedbackTicketRef(String id) =>
    id.length >= 8 ? id.substring(0, 8).toUpperCase() : id.toUpperCase();

String feedbackRelativeTime(DateTime dt) {
  final diff = DateTime.now().toUtc().difference(dt.toUtc());
  if (diff.inMinutes < 1) return 'just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
  if (diff.inHours < 24) return '${diff.inHours}h ago';
  if (diff.inDays < 30) return '${diff.inDays}d ago';
  return '${dt.day}/${dt.month}/${dt.year}';
}
