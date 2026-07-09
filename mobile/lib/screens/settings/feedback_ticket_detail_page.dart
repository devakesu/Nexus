import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:nexus/config/app_config.dart';
import 'package:nexus/screens/settings/feedback_shared.dart';
import 'package:nexus/utils/network_utils.dart';
import 'package:nexus/widgets/aesthetic_loaders.dart';
import 'package:nexus/widgets/nexus_toast.dart';
import 'package:nexus/widgets/scale_pressable.dart';

class FeedbackTicketDetailPage extends StatefulWidget {
  const FeedbackTicketDetailPage({required this.reportId, super.key});

  final String reportId;

  @override
  State<FeedbackTicketDetailPage> createState() =>
      _FeedbackTicketDetailPageState();
}

class _FeedbackTicketDetailPageState extends State<FeedbackTicketDetailPage> {
  static const _gradientStart = Color(0xFF4F46E5);
  static const _gradientEnd = Color(0xFF7C3AED);

  late final Dio _dio;
  final TextEditingController _commentController = TextEditingController();

  bool _loading = true;
  bool _sendingComment = false;
  bool _closing = false;
  String? _error;
  FeedbackTicketDetail? _ticket;

  @override
  void initState() {
    super.initState();
    _dio = createDio();
    unawaited(_load());
  }

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await NetworkUtils.requireAccessToken();
      final response = await _dio.get<Map<String, dynamic>>(
        '${AppConfig.current.backendUrl}/api/v1/feedback/${widget.reportId}',
        );
      if (mounted && response.data != null) {
        setState(() => _ticket = FeedbackTicketDetail.fromJson(response.data!));
      }
    } on DioException catch (e) {
      if (mounted) {
        final detail = (e.response?.data as Map<String, dynamic>?)?['detail'];
        setState(
          () => _error = detail is String ? detail : 'Failed to load ticket.',
        );
      }
    } on Exception {
      if (mounted) setState(() => _error = 'Failed to load ticket.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _sendComment() async {
    final body = _commentController.text.trim();
    if (body.isEmpty || _sendingComment) return;

    setState(() => _sendingComment = true);
    try {
      await NetworkUtils.requireAccessToken();
      await _dio.post<Map<String, dynamic>>(
        '${AppConfig.current.backendUrl}/api/v1/feedback/${widget.reportId}/comments',
        data: {'body': body},
        );
      _commentController.clear();
      await _load();
    } on DioException catch (e) {
      if (mounted) {
        final detail = (e.response?.data as Map<String, dynamic>?)?['detail'];
        NexusToast.show(
          context,
          detail is String ? detail : 'Failed to send comment.',
          type: NexusToastType.error,
        );
      }
    } on Exception {
      if (mounted) {
        NexusToast.show(
          context,
          'Failed to send comment.',
          type: NexusToastType.error,
        );
      }
    } finally {
      if (mounted) setState(() => _sendingComment = false);
    }
  }

  Future<void> _closeTicket() async {
    final reasonController = TextEditingController();
    final reason = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          'Close this ticket?',
          style: GoogleFonts.manrope(fontWeight: FontWeight.w800),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              "Let us know why you're closing it — resolved, no longer relevant, etc.",
              style: GoogleFonts.inter(
                fontSize: 13,
                color: const Color(0xFF64748B),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: reasonController,
              autofocus: true,
              maxLines: 3,
              decoration: InputDecoration(
                hintText: 'Reason for closing',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF0F172A),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            onPressed: () {
              final value = reasonController.text.trim();
              if (value.length < 3) return;
              Navigator.of(ctx).pop(value);
            },
            child: const Text('Close Ticket'),
          ),
        ],
      ),
    );
    if (reason == null || !mounted) return;

    setState(() => _closing = true);
    try {
      await NetworkUtils.requireAccessToken();
      final response = await _dio.post<Map<String, dynamic>>(
        '${AppConfig.current.backendUrl}/api/v1/feedback/${widget.reportId}/close',
        data: {'reason': reason},
        );
      if (response.data != null && mounted) {
        NexusToast.show(context, 'Ticket closed.');
        Navigator.of(context).pop();
        return;
      }
    } on DioException catch (e) {
      if (mounted) {
        final detail = (e.response?.data as Map<String, dynamic>?)?['detail'];
        NexusToast.show(
          context,
          detail is String ? detail : 'Failed to close ticket.',
          type: NexusToastType.error,
        );
      }
    } on Exception {
      if (mounted) {
        NexusToast.show(
          context,
          'Failed to close ticket.',
          type: NexusToastType.error,
        );
      }
    }
    if (mounted) setState(() => _closing = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F6FA),
      appBar: _buildAppBar(),
      body: _buildBody(),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return PreferredSize(
      preferredSize: const Size.fromHeight(kToolbarHeight),
      child: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [_gradientStart, _gradientEnd],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(LucideIcons.chevronLeft, color: Colors.white),
            tooltip: 'Back',
            onPressed: () => Navigator.of(context).pop(),
          ),
          title: Text(
            _ticket != null ? '#${feedbackTicketRef(_ticket!.id)}' : 'Ticket',
            style: GoogleFonts.manrope(
              color: Colors.white,
              fontWeight: FontWeight.w800,
              fontSize: 18,
            ),
          ),
          centerTitle: true,
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: NexusOrbitLoader(size: 48, lightMode: true));
    }
    if (_error != null || _ticket == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                LucideIcons.circleAlert,
                size: 32,
                color: Color(0xFFCBD5E1),
              ),
              const SizedBox(height: 12),
              Text(
                _error ?? 'Ticket not found.',
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(color: const Color(0xFF64748B)),
              ),
            ],
          ),
        ),
      );
    }

    final ticket = _ticket!;
    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
            children: [
              _buildHeaderCard(ticket),
              const SizedBox(height: 16),
              _buildTimelineCard(ticket),
              const SizedBox(height: 16),
              _buildCommentsCard(ticket),
              if (!ticket.status.isTerminal) ...[
                const SizedBox(height: 16),
                _buildCloseButton(),
              ],
            ],
          ),
        ),
        if (!ticket.status.isTerminal) _buildCommentComposer(),
      ],
    );
  }

  Widget _buildHeaderCard(FeedbackTicketDetail ticket) {
    return Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(ticket.queryType.icon, size: 15, color: _gradientEnd),
                  const SizedBox(width: 6),
                  Text(
                    ticket.queryType.label.toUpperCase(),
                    style: GoogleFonts.manrope(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: _gradientEnd,
                      letterSpacing: 0.8,
                    ),
                  ),
                  const Spacer(),
                  FeedbackStatusBadge(status: ticket.status),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                ticket.subject,
                style: GoogleFonts.manrope(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  color: const Color(0xFF0F172A),
                ),
              ),
              const SizedBox(height: 10),
              Text(
                ticket.message,
                style: GoogleFonts.inter(
                  fontSize: 13.5,
                  color: const Color(0xFF475569),
                  height: 1.5,
                ),
              ),
              if (ticket.githubIssueUrl != null) ...[
                const SizedBox(height: 12),
                Row(
                  children: [
                    const Icon(
                      LucideIcons.externalLink,
                      size: 14,
                      color: Color(0xFF94A3B8),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        ticket.githubIssueUrl!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          color: const Color(0xFF64748B),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
              if (ticket.attachmentPaths.isNotEmpty) ...[
                const SizedBox(height: 12),
                Row(
                  children: [
                    const Icon(
                      LucideIcons.image,
                      size: 14,
                      color: Color(0xFF94A3B8),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      '${ticket.attachmentPaths.length} attachment'
                      '${ticket.attachmentPaths.length == 1 ? '' : 's'}',
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        color: const Color(0xFF64748B),
                      ),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 10),
              Text(
                'Opened ${feedbackRelativeTime(ticket.createdAt)}',
                style: GoogleFonts.inter(
                  fontSize: 11,
                  color: const Color(0xFF475569),
                ),
              ),
            ],
          ),
        )
        .animate()
        .fadeIn(duration: 300.ms)
        .slideY(begin: 0.04, end: 0, duration: 300.ms);
  }

  Widget _buildTimelineCard(FeedbackTicketDetail ticket) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'TIMELINE',
            style: GoogleFonts.manrope(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              color: const Color(0xFF64748B),
              letterSpacing: 1,
            ),
          ),
          const SizedBox(height: 14),
          for (var i = 0; i < ticket.statusHistory.length; i++)
            _buildTimelineEntry(
              ticket.statusHistory[i],
              isLast: i == ticket.statusHistory.length - 1,
            ),
        ],
      ),
    );
  }

  Widget _buildTimelineEntry(
    FeedbackStatusHistoryEntry entry, {
    required bool isLast,
  }) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: entry.status.color,
                  shape: BoxShape.circle,
                ),
              ),
              if (!isLast)
                Expanded(
                  child: Container(width: 1.5, color: const Color(0xFFE2E8F0)),
                ),
            ],
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: isLast ? 0 : 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    entry.status.label,
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFF0F172A),
                    ),
                  ),
                  if (entry.note != null && entry.note!.trim().isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      entry.note!,
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        color: const Color(0xFF64748B),
                        height: 1.4,
                      ),
                    ),
                  ],
                  const SizedBox(height: 2),
                  Text(
                    feedbackRelativeTime(entry.createdAt),
                    style: GoogleFonts.inter(
                      fontSize: 11,
                      color: const Color(0xFF475569),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCommentsCard(FeedbackTicketDetail ticket) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'DISCUSSION',
            style: GoogleFonts.manrope(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              color: const Color(0xFF64748B),
              letterSpacing: 1,
            ),
          ),
          const SizedBox(height: 14),
          if (ticket.comments.isEmpty)
            Text(
              'No replies yet.',
              style: GoogleFonts.inter(
                fontSize: 13,
                color: const Color(0xFF475569),
              ),
            )
          else
            for (final comment in ticket.comments)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Align(
                  alignment: comment.isOwn
                      ? Alignment.centerRight
                      : Alignment.centerLeft,
                  child: Container(
                    constraints: const BoxConstraints(maxWidth: 280),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: comment.isOwn
                          ? _gradientEnd.withValues(alpha: 0.1)
                          : const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          comment.body,
                          style: GoogleFonts.inter(
                            fontSize: 13,
                            color: const Color(0xFF0F172A),
                            height: 1.4,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          feedbackRelativeTime(comment.createdAt),
                          style: GoogleFonts.inter(
                            fontSize: 10,
                            color: const Color(0xFF475569),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
        ],
      ),
    );
  }

  Widget _buildCommentComposer() {
    return Container(
      padding: EdgeInsets.fromLTRB(
        16,
        12,
        16,
        12 + MediaQuery.of(context).padding.bottom,
      ),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Color(0xFFE2E8F0))),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _commentController,
              minLines: 1,
              maxLines: 4,
              style: GoogleFonts.inter(fontSize: 13.5),
              decoration: InputDecoration(
                hintText: 'Add a comment…',
                hintStyle: GoogleFonts.inter(
                  fontSize: 13,
                  color: const Color(0xFF475569),
                ),
                filled: true,
                fillColor: const Color(0xFFF8FAFC),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(20),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          ScalePressable(
            onTap: _sendingComment ? () {} : _sendComment,
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: const BoxDecoration(
                color: _gradientEnd,
                shape: BoxShape.circle,
              ),
              child: _sendingComment
                  ? const NexusOrbitLoader(size: 16)
                  : const Icon(LucideIcons.send, size: 16, color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCloseButton() {
    return ScalePressable(
      onTap: _closing ? () {} : _closeTicket,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFE2E8F0)),
        ),
        child: Center(
          child: _closing
              ? const NexusOrbitLoader(size: 20, lightMode: true)
              : Text(
                  'Close Ticket',
                  style: GoogleFonts.manrope(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w800,
                    color: const Color(0xFF64748B),
                  ),
                ),
        ),
      ),
    );
  }
}
