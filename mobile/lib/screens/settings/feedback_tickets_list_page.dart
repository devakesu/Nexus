import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:nexus/config/app_config.dart';
import 'package:nexus/screens/settings/feedback_shared.dart';
import 'package:nexus/screens/settings/feedback_ticket_detail_page.dart';
import 'package:nexus/utils/network_utils.dart';
import 'package:nexus/widgets/aesthetic_loaders.dart';
import 'package:nexus/widgets/scale_pressable.dart';

class FeedbackTicketsListPage extends StatefulWidget {
  const FeedbackTicketsListPage({super.key});

  @override
  State<FeedbackTicketsListPage> createState() =>
      _FeedbackTicketsListPageState();
}

class _FeedbackTicketsListPageState extends State<FeedbackTicketsListPage> {
  static const _gradientStart = Color(0xFF4F46E5);
  static const _gradientEnd = Color(0xFF7C3AED);

  late final Dio _dio;
  bool _loading = true;
  String? _error;
  List<FeedbackTicketSummary> _tickets = [];

  @override
  void initState() {
    super.initState();
    _dio = createDio();
    unawaited(_load());
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final token = await NetworkUtils.requireAccessToken();
      final response = await _dio.get<List<dynamic>>(
        '${AppConfig.current.backendUrl}/api/v1/feedback/mine',
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );
      final tickets = (response.data ?? [])
          .map((e) => FeedbackTicketSummary.fromJson(e as Map<String, dynamic>))
          .toList();
      if (mounted) setState(() => _tickets = tickets);
    } on Exception {
      if (mounted) setState(() => _error = 'Failed to load your tickets.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _openTicket(String reportId) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => FeedbackTicketDetailPage(reportId: reportId),
      ),
    );
    unawaited(_load());
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
            'Your Tickets',
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
    if (_error != null) {
      return Center(
        child: Text(
          _error!,
          style: GoogleFonts.inter(color: const Color(0xFF64748B)),
        ),
      );
    }
    if (_tickets.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(LucideIcons.inbox, size: 32, color: Color(0xFFCBD5E1)),
              const SizedBox(height: 12),
              Text(
                "You haven't submitted any tickets yet.",
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(color: const Color(0xFF64748B)),
              ),
            ],
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 40),
        itemCount: _tickets.length,
        itemBuilder: (context, i) {
          final ticket = _tickets[i];
          return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _buildTicketCard(ticket),
              )
              .animate()
              .fadeIn(delay: (i * 30).ms, duration: 250.ms)
              .slideY(begin: 0.03, end: 0, duration: 250.ms);
        },
      ),
    );
  }

  Widget _buildTicketCard(FeedbackTicketSummary ticket) {
    return ScalePressable(
      onTap: () => _openTicket(ticket.id),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFE2E8F0)),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(9),
              decoration: BoxDecoration(
                color: _gradientEnd.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(ticket.queryType.icon, size: 17, color: _gradientEnd),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    ticket.subject,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.inter(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: const Color(0xFF0F172A),
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '#${feedbackTicketRef(ticket.id)} · ${feedbackRelativeTime(ticket.createdAt)}',
                    style: GoogleFonts.inter(
                      fontSize: 11.5,
                      color: const Color(0xFF475569),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            FeedbackStatusBadge(status: ticket.status),
          ],
        ),
      ),
    );
  }
}
