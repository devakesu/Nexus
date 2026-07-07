import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:nexus/config/app_config.dart';
import 'package:nexus/utils/network_utils.dart';
import 'package:nexus/widgets/nexus_toast.dart';
import 'package:nexus/widgets/scale_pressable.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

enum _QueryType { help, feedback, bugReport }

extension on _QueryType {
  String get apiValue => switch (this) {
    _QueryType.help => 'help',
    _QueryType.feedback => 'feedback',
    _QueryType.bugReport => 'bug_report',
  };

  String get label => switch (this) {
    _QueryType.help => 'Help',
    _QueryType.feedback => 'Feedback',
    _QueryType.bugReport => 'Bug Report',
  };

  String get description => switch (this) {
    _QueryType.help => "I'm stuck on something",
    _QueryType.feedback => 'I have a suggestion',
    _QueryType.bugReport => 'Something is broken',
  };

  IconData get icon => switch (this) {
    _QueryType.help => LucideIcons.circleHelp,
    _QueryType.feedback => LucideIcons.lightbulb,
    _QueryType.bugReport => LucideIcons.bug,
  };

  String get subjectHint => switch (this) {
    _QueryType.help => 'e.g. How do I pause my Orbits?',
    _QueryType.feedback => 'e.g. Add a dark mode toggle',
    _QueryType.bugReport => 'e.g. Chat crashes when sending a photo',
  };

  String get messageHint => switch (this) {
    _QueryType.help => 'Tell us what you were trying to do and where you got stuck.',
    _QueryType.feedback => "Share what's on your mind — we read every word.",
    _QueryType.bugReport =>
      'What did you expect to happen, and what happened instead? '
          'Steps to reproduce help a lot.',
  };
}

class _PendingAttachment {
  _PendingAttachment({required this.id, required this.file});

  final String id;
  final File file;
  bool uploading = false;
  bool failed = false;
  String? storagePath;
}

class FeedbackPage extends StatefulWidget {
  const FeedbackPage({super.key});

  @override
  State<FeedbackPage> createState() => _FeedbackPageState();
}

class _FeedbackPageState extends State<FeedbackPage> {
  static const _gradientStart = Color(0xFF4F46E5);
  static const _gradientEnd = Color(0xFF7C3AED);
  static const _maxAttachments = 5;
  static const int _maxAttachmentBytes = 8 * 1024 * 1024;

  late final Dio _dio;
  final SupabaseClient _supabase = Supabase.instance.client;

  _QueryType _queryType = _QueryType.help;
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _contactEmailController;
  final TextEditingController _subjectController = TextEditingController();
  final TextEditingController _messageController = TextEditingController();
  final TextEditingController _githubUrlController = TextEditingController();

  final List<_PendingAttachment> _attachments = [];

  bool _submitting = false;
  PackageInfo? _packageInfo;

  @override
  void initState() {
    super.initState();
    _dio = createDio();
    final user = _supabase.auth.currentUser;
    _contactEmailController = TextEditingController(text: user?.email ?? '');
    unawaited(_loadPackageInfo());
  }

  Future<void> _loadPackageInfo() async {
    final info = await PackageInfo.fromPlatform();
    if (mounted) setState(() => _packageInfo = info);
  }

  @override
  void dispose() {
    _contactEmailController.dispose();
    _subjectController.dispose();
    _messageController.dispose();
    _githubUrlController.dispose();
    super.dispose();
  }

  String? get _greetingName {
    final metadata = _supabase.auth.currentUser?.userMetadata;
    final name = metadata?['name'] as String?;
    return (name != null && name.trim().isNotEmpty) ? name.trim() : null;
  }

  Future<void> _pickAttachment() async {
    if (_attachments.length >= _maxAttachments) {
      NexusToast.show(
        context,
        'You can attach up to $_maxAttachments images.',
      );
      return;
    }
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(LucideIcons.camera, color: _gradientEnd),
              title: Text('Camera', style: GoogleFonts.inter(fontWeight: FontWeight.w600)),
              onTap: () => Navigator.pop(ctx, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(LucideIcons.image, color: _gradientEnd),
              title: Text('Gallery', style: GoogleFonts.inter(fontWeight: FontWeight.w600)),
              onTap: () => Navigator.pop(ctx, ImageSource.gallery),
            ),
          ],
        ),
      ),
    );
    if (source == null || !mounted) return;

    final picked = await ImagePicker().pickImage(source: source, imageQuality: 85);
    if (picked == null || !mounted) return;

    final file = File(picked.path);
    final size = await file.length();
    if (size > _maxAttachmentBytes) {
      if (mounted) {
        NexusToast.show(
          context,
          'That image is too large (max 8MB).',
          type: NexusToastType.error,
        );
      }
      return;
    }

    setState(() {
      _attachments.add(_PendingAttachment(id: const Uuid().v4(), file: file));
    });
  }

  void _removeAttachment(String id) {
    setState(() => _attachments.removeWhere((a) => a.id == id));
  }

  Future<bool> _uploadAttachments(String userId) async {
    final storage = _supabase.storage.from('feedback_attachments');
    for (final attachment in _attachments) {
      if (attachment.storagePath != null) continue;
      setState(() => attachment.uploading = true);
      try {
        final ext = attachment.file.path.split('.').last.toLowerCase();
        final path = '$userId/${attachment.id}.$ext';
        await storage.upload(path, attachment.file);
        attachment.storagePath = path;
      } on Exception {
        attachment.failed = true;
        if (mounted) setState(() {});
        return false;
      } finally {
        if (mounted) setState(() => attachment.uploading = false);
      }
    }
    return true;
  }

  Future<void> _rollbackUploadedAttachments() async {
    final paths = _attachments
        .map((a) => a.storagePath)
        .whereType<String>()
        .toList();
    if (paths.isEmpty) return;
    try {
      await _supabase.storage.from('feedback_attachments').remove(paths);
    } on Exception {
      // Best-effort cleanup; orphaned attachments are harmless.
    }
    for (final attachment in _attachments) {
      attachment.storagePath = null;
    }
  }

  Future<void> _submit() async {
    if (_submitting) return;
    final formState = _formKey.currentState;
    if (formState == null || !formState.validate()) return;

    final session = _supabase.auth.currentSession;
    if (session == null) {
      NexusToast.show(context, 'Not signed in.', type: NexusToastType.error);
      return;
    }
    final userId = session.user.id;

    setState(() => _submitting = true);

    final attachmentsOk = await _uploadAttachments(userId);
    if (!attachmentsOk) {
      if (mounted) {
        setState(() => _submitting = false);
        NexusToast.show(
          context,
          'One of your attachments failed to upload. Remove it and try again.',
          type: NexusToastType.error,
        );
      }
      return;
    }

    final attachmentPaths = _attachments
        .map((a) => a.storagePath)
        .whereType<String>()
        .toList();

    try {
      final token = session.accessToken;
      final appVersion = _packageInfo != null
          ? '${_packageInfo!.version}+${_packageInfo!.buildNumber}'
          : null;
      final platform = Platform.isIOS ? 'ios' : 'android';

      final contactEmail = _contactEmailController.text.trim();
      final githubUrl = _githubUrlController.text.trim();

      final response = await _dio.post<Map<String, dynamic>>(
        '${AppConfig.current.backendUrl}/api/v1/feedback/submit',
        data: {
          'query_type': _queryType.apiValue,
          'subject': _subjectController.text.trim(),
          'message': _messageController.text.trim(),
          if (contactEmail.isNotEmpty) 'contact_email': contactEmail,
          if (_queryType == _QueryType.bugReport && githubUrl.isNotEmpty)
            'github_issue_url': githubUrl,
          'attachment_paths': attachmentPaths,
          'app_version': ?appVersion,
          'platform': platform,
        },
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );

      if (!mounted) return;
      final ticketId = response.data?['id'] as String?;
      final ref = (ticketId != null && ticketId.length >= 8)
          ? ticketId.substring(0, 8).toUpperCase()
          : null;

      setState(() => _submitting = false);
      await _showSuccessDialog(ref);
    } on DioException catch (e) {
      await _rollbackUploadedAttachments();
      if (mounted) {
        setState(() => _submitting = false);
        final detail = (e.response?.data as Map<String, dynamic>?)?['detail'];
        final message = detail is String
            ? detail
            : 'Failed to submit. Please try again.';
        NexusToast.show(context, message, type: NexusToastType.error);
      }
    } on Exception {
      await _rollbackUploadedAttachments();
      if (mounted) {
        setState(() => _submitting = false);
        NexusToast.show(
          context,
          'Failed to submit. Please try again.',
          type: NexusToastType.error,
        );
      }
    }
  }

  Future<void> _showSuccessDialog(String? ref) async {
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                    padding: const EdgeInsets.all(16),
                    decoration: const BoxDecoration(
                      color: Color(0xFFECFDF5),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      LucideIcons.checkCheck,
                      color: Color(0xFF0D9488),
                      size: 36,
                    ),
                  )
                  .animate()
                  .scale(
                    begin: const Offset(0.6, 0.6),
                    end: const Offset(1, 1),
                    duration: 350.ms,
                    curve: Curves.easeOutBack,
                  ),
              const SizedBox(height: 18),
              Text(
                'Thanks — we got it!',
                style: GoogleFonts.manrope(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: const Color(0xFF0F172A),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                ref != null
                    ? "Ticket #$ref is now open. We've sent a confirmation "
                          'to your email, and typically reply within 24-48 hours.'
                    : "Your ticket is now open. We've sent a confirmation to "
                          'your email, and typically reply within 24-48 hours.',
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(
                  fontSize: 13.5,
                  color: const Color(0xFF64748B),
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 22),
              ScalePressable(
                onTap: () {
                  Navigator.of(ctx).pop();
                  Navigator.of(context).pop();
                },
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0F172A),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Center(
                    child: Text(
                      'Done',
                      style: GoogleFonts.manrope(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F6FA),
      appBar: _buildAppBar(),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 40),
          children: [
            _buildIntro(),
            const SizedBox(height: 16),
            _buildQueryTypeSelector(),
            const SizedBox(height: 16),
            _buildFormCard(),
            const SizedBox(height: 20),
            _buildSubmitButton(),
            const SizedBox(height: 12),
            _buildPrivacyNote(),
          ],
        ),
      ),
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
          boxShadow: [
            BoxShadow(
              color: Color(0x334F46E5),
              blurRadius: 12,
              offset: Offset(0, 4),
            ),
          ],
        ),
        child: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(LucideIcons.chevronLeft, color: Colors.white),
            onPressed: () => Navigator.of(context).pop(),
          ),
          title: Text(
            'Help, Feedback & Bug Report',
            style: GoogleFonts.manrope(
              color: Colors.white,
              fontWeight: FontWeight.w800,
              fontSize: 16,
            ),
          ),
          centerTitle: true,
        ),
      ),
    );
  }

  Widget _buildIntro() {
    final name = _greetingName;
    return Row(
          children: [
            Container(
                  padding: const EdgeInsets.all(12),
                  decoration: const BoxDecoration(
                    color: Color(0xFFEDE9FE),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    LucideIcons.mailPlus,
                    color: _gradientEnd,
                    size: 22,
                  ),
                )
                .animate(onPlay: (c) => c.repeat(reverse: true))
                .scale(
                  begin: const Offset(0.94, 0.94),
                  end: const Offset(1.06, 1.06),
                  duration: 2400.ms,
                  curve: Curves.easeInOut,
                ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name != null ? "We're here for you, $name" : "We're here to help",
                    style: GoogleFonts.manrope(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: const Color(0xFF0F172A),
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    'This reaches our team directly — no bots in between.',
                    style: GoogleFonts.inter(
                      fontSize: 12.5,
                      color: const Color(0xFF64748B),
                    ),
                  ),
                ],
              ),
            ),
          ],
        )
        .animate()
        .fadeIn(duration: 300.ms)
        .slideY(begin: 0.05, end: 0, duration: 300.ms);
  }

  Widget _buildQueryTypeSelector() {
    return Row(
      children: _QueryType.values.map((type) {
        final selected = _queryType == type;
        return Expanded(
          child: Padding(
            padding: EdgeInsets.only(
              right: type == _QueryType.values.last ? 0 : 10,
            ),
            child: ScalePressable(
              onTap: () => setState(() => _queryType = type),
              child: AnimatedContainer(
                duration: 200.ms,
                padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
                decoration: BoxDecoration(
                  color: selected ? _gradientEnd.withValues(alpha: 0.08) : Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: selected ? _gradientEnd : const Color(0xFFE2E8F0),
                    width: selected ? 1.5 : 1,
                  ),
                ),
                child: Column(
                  children: [
                    Icon(
                      type.icon,
                      size: 20,
                      color: selected ? _gradientEnd : const Color(0xFF94A3B8),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      type.label,
                      textAlign: TextAlign.center,
                      style: GoogleFonts.manrope(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: selected ? const Color(0xFF0F172A) : const Color(0xFF64748B),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      type.description,
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.inter(
                        fontSize: 10,
                        color: const Color(0xFF94A3B8),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      }).toList(),
    ).animate().fadeIn(delay: 60.ms, duration: 300.ms);
  }

  Widget _buildFormCard() {
    return Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: const Color(0xFFE2E8F0)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.02),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildLabel('CONTACT EMAIL'),
              const SizedBox(height: 8),
              _buildTextField(
                controller: _contactEmailController,
                hint: 'you@example.com',
                icon: LucideIcons.mail,
                keyboardType: TextInputType.emailAddress,
                validator: (v) {
                  final value = v?.trim() ?? '';
                  if (value.isEmpty) return null;
                  final ok = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(value);
                  return ok ? null : 'Enter a valid email address.';
                },
              ),
              const SizedBox(height: 18),
              _buildLabel('SUBJECT'),
              const SizedBox(height: 8),
              _buildTextField(
                controller: _subjectController,
                hint: _queryType.subjectHint,
                icon: LucideIcons.type,
                maxLength: 150,
                validator: (v) {
                  final value = v?.trim() ?? '';
                  if (value.length < 3) return 'Subject must be at least 3 characters.';
                  return null;
                },
              ),
              const SizedBox(height: 18),
              _buildLabel('MESSAGE'),
              const SizedBox(height: 8),
              _buildTextField(
                controller: _messageController,
                hint: _queryType.messageHint,
                icon: LucideIcons.messageSquare,
                maxLines: 6,
                maxLength: 5000,
                validator: (v) {
                  final value = v?.trim() ?? '';
                  if (value.length < 10) return 'Please share a few more details.';
                  return null;
                },
              ),
              AnimatedSize(
                duration: 200.ms,
                child: _queryType == _QueryType.bugReport
                    ? Padding(
                        padding: const EdgeInsets.only(top: 18),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _buildLabel('GITHUB ISSUE (OPTIONAL)'),
                            const SizedBox(height: 8),
                            _buildTextField(
                              controller: _githubUrlController,
                              hint: 'https://github.com/org/repo/issues/123',
                              icon: LucideIcons.externalLink,
                              keyboardType: TextInputType.url,
                              validator: (v) {
                                final value = v?.trim() ?? '';
                                if (value.isEmpty) return null;
                                final ok = RegExp(
                                  r'^https://github\.com/[^/\s]+/[^/\s]+/issues/\d+/?$',
                                ).hasMatch(value);
                                return ok
                                    ? null
                                    : 'Must look like a GitHub issue link.';
                              },
                            ),
                          ],
                        ),
                      )
                    : const SizedBox.shrink(),
              ),
              const SizedBox(height: 18),
              _buildLabel('ATTACHMENTS (OPTIONAL)'),
              const SizedBox(height: 8),
              _buildAttachmentsRow(),
            ],
          ),
        )
        .animate()
        .fadeIn(delay: 100.ms, duration: 300.ms)
        .slideY(begin: 0.04, end: 0, duration: 300.ms);
  }

  Widget _buildLabel(String text) {
    return Text(
      text,
      style: GoogleFonts.manrope(
        fontSize: 11,
        fontWeight: FontWeight.w800,
        color: const Color(0xFF64748B),
        letterSpacing: 1,
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String hint,
    required IconData icon,
    TextInputType? keyboardType,
    int maxLines = 1,
    int? maxLength,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      maxLines: maxLines,
      maxLength: maxLength,
      validator: validator,
      style: GoogleFonts.inter(fontSize: 14, color: const Color(0xFF0F172A)),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: GoogleFonts.inter(fontSize: 13, color: const Color(0xFF94A3B8)),
        prefixIcon: maxLines == 1
            ? Icon(icon, size: 18, color: const Color(0xFF94A3B8))
            : null,
        filled: true,
        fillColor: const Color(0xFFF8FAFC),
        counterStyle: GoogleFonts.inter(fontSize: 10.5, color: const Color(0xFFCBD5E1)),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: _gradientEnd, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFFEF4444)),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      ),
    );
  }

  Widget _buildAttachmentsRow() {
    return SizedBox(
      height: 76,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          ..._attachments.map(
            (a) => Padding(
              padding: const EdgeInsets.only(right: 10),
              child: _buildAttachmentThumb(a),
            ),
          ),
          if (_attachments.length < _maxAttachments) _buildAddAttachmentTile(),
        ],
      ),
    );
  }

  Widget _buildAttachmentThumb(_PendingAttachment attachment) {
    return Stack(
      children: [
        Container(
          width: 76,
          height: 76,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: attachment.failed ? const Color(0xFFEF4444) : const Color(0xFFE2E8F0),
            ),
            image: DecorationImage(
              image: FileImage(attachment.file),
              fit: BoxFit.cover,
            ),
          ),
        ),
        if (attachment.uploading)
          Container(
            width: 76,
            height: 76,
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.35),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Center(
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
              ),
            ),
          ),
        Positioned(
          top: 4,
          right: 4,
          child: ScalePressable(
            onTap: () => _removeAttachment(attachment.id),
            child: Container(
              padding: const EdgeInsets.all(3),
              decoration: const BoxDecoration(
                color: Color(0xFF0F172A),
                shape: BoxShape.circle,
              ),
              child: const Icon(LucideIcons.x, size: 11, color: Colors.white),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildAddAttachmentTile() {
    return ScalePressable(
      onTap: _pickAttachment,
      child: Container(
        width: 76,
        height: 76,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          color: const Color(0xFFF8FAFC),
          border: Border.all(
            color: const Color(0xFFCBD5E1),
          ),
        ),
        child: const Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(LucideIcons.plus, size: 18, color: Color(0xFF94A3B8)),
            SizedBox(height: 4),
            Text(
              'Add',
              style: TextStyle(fontSize: 10, color: Color(0xFF94A3B8)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSubmitButton() {
    return ScalePressable(
      onTap: _submitting ? () {} : _submit,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 15),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [_gradientStart, _gradientEnd],
          ),
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: _gradientEnd.withValues(alpha: 0.25),
              blurRadius: 16,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Center(
          child: _submitting
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2.2, color: Colors.white),
                )
              : Text(
                  'Submit',
                  style: GoogleFonts.manrope(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
        ),
      ),
    ).animate().fadeIn(delay: 140.ms, duration: 300.ms);
  }

  Widget _buildPrivacyNote() {
    return Text(
      'Your app version and platform are shared automatically to help us '
      'troubleshoot faster. We never share your ticket with anyone else.',
      textAlign: TextAlign.center,
      style: GoogleFonts.inter(
        fontSize: 11,
        color: const Color(0xFF94A3B8),
        height: 1.4,
      ),
    );
  }
}
