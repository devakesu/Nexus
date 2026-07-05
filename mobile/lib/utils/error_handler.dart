import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

enum ErrorLevel {
  info,
  warning,
  error,
  critical,
}

class ErrorHandler {
  /// Global navigator key to access overlay and dialog context without local BuildContext
  static final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

  /// List of active toasts to manage their offsets / preventing overlapping if needed
  static OverlayEntry? _activeToast;
  static Timer? _toastTimer;

  /// Sanitizes sensitive information (emails, passwords, JWT tokens, keys) from a string.
  static String sanitize(String message) {
    var sanitized = message;

    // 1. Sanitize emails, but allow support@ addresses to remain visible
    final emailRegex = RegExp(
      r'[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}',
    );
    sanitized = sanitized.replaceAllMapped(emailRegex, (match) {
      final matchedEmail = match.group(0)!;
      if (matchedEmail.toLowerCase().startsWith('support@')) {
        return matchedEmail;
      }
      return '[EMAIL_REDACTED]';
    });

    // 2. Sanitize authorization/bearer tokens and keys
    final tokenRegex = RegExp(
      r'(bearer|auth|token|authorization|key|password|secret|jwt)[=\s:]+([A-Za-z0-9-_=]+\.[A-Za-z0-9-_=]+\.?[A-Za-z0-9-_.+/=]*)',
      caseSensitive: false,
    );
    sanitized = sanitized.replaceAllMapped(tokenRegex, (match) {
      final prefix = match.group(1);
      return '$prefix: [REDACTED_SENSITIVE]';
    });

    // 3. Sanitize typical JSON fields or raw query parameters with passwords/secrets
    final fieldRegex = RegExp(
      r'("password"|"secret"|"token"|"key"|"jwt")\s*[:=]\s*("[^"]+"|[^\s,}]+)',
      caseSensitive: false,
    );
    return sanitized.replaceAllMapped(fieldRegex, (match) {
      final field = match.group(1);
      return '$field: "[REDACTED_SENSITIVE]"';
    });
  }

  /// Public API to get a sanitized, user-friendly message for any error.
  static String getFriendlyMessage(dynamic error, [String? customMessage]) {
    final rawMessage = customMessage ?? error?.toString() ?? 'An unexpected error occurred.';
    return _getFriendlyMessage(error, sanitize(rawMessage));
  }

  /// Translates common exceptions or error strings into friendly user-facing messages.
  static String _getFriendlyMessage(dynamic error, String message) {
    if (error is DioException) {
      if (error.response != null) {
        final data = error.response!.data;
        if (data is Map && data.containsKey('detail')) {
          return data['detail'].toString();
        }
        final statusCode = error.response!.statusCode;
        if (statusCode == 401) {
          return 'Session expired. Please sign in again.';
        }
        if (statusCode == 403) {
          return 'Access denied. You do not have permission to access this resource.';
        }
        if (statusCode == 429) {
          return 'Too many requests. Please wait a moment before trying again.';
        }
        if (statusCode != null && statusCode >= 500) {
          return 'Server error ($statusCode). Please try again later.';
        }
      }
      return 'Connection error. Please check your internet connection and try again.';
    }

    if (error is AuthException) {
      final code = error.code;
      final msg = error.message.toLowerCase();

      if (code == 'otp_expired' ||
          (msg.contains('otp') && msg.contains('expired')) ||
          msg.contains('token has expired or is invalid')) {
        return 'The verification code you entered is invalid or has expired. Please check and try again.';
      }
      if (code == 'invalid_grant' ||
          msg.contains('invalid grant') ||
          msg.contains('invalid credentials')) {
        return 'Invalid login credentials. Please try again.';
      }
      if (code == 'over_email_send_rate_limit' ||
          code == 'over_sms_send_rate_limit' ||
          msg.contains('rate limit') ||
          msg.contains('too many requests')) {
        return 'Too many requests. Please wait a moment before trying again.';
      }
      if (code == 'user_not_found') {
        return 'No account was found with those details.';
      }
      return error.message;
    }

    final lower = message.toLowerCase();
    if (lower.contains('otp_expired') ||
        lower.contains('token has expired or is invalid') ||
        (lower.contains('invalid') && lower.contains('otp')) ||
        (lower.contains('expired') && lower.contains('otp'))) {
      return 'The verification code you entered is invalid or has expired. Please check and try again.';
    }

    if (lower.contains('invalid_grant') || lower.contains('invalid credentials')) {
      return 'Invalid credentials. Please check and try again.';
    }

    if (lower.contains('rate limit') || lower.contains('too many requests')) {
      return 'Too many requests. Please wait a moment before trying again.';
    }

    if (lower.contains('network') ||
        lower.contains('connection failed') ||
        lower.contains('socketexception') ||
        lower.contains('dioexception')) {
      return 'Network connection issue. Please check your internet connection and try again.';
    }

    var cleaned = message;
    if (cleaned.startsWith('Access denied: ')) {
      cleaned = cleaned.substring('Access denied: '.length);
    }
    if (cleaned.startsWith('Exception: ')) {
      cleaned = cleaned.substring('Exception: '.length);
    }
    return cleaned;
  }

  /// Centralized handler for all errors and exceptions.
  /// Logs to Sentry and displays UI messages to the user based on the level.
  static void handleError(
    dynamic error, {
    StackTrace? stackTrace,
    ErrorLevel level = ErrorLevel.error,
    String? customMessage,
    bool showUi = true,
  }) {
    // 1. Sanitize input parameters
    final rawMessage = customMessage ?? error?.toString() ?? 'An unexpected error occurred.';
    final sanitizedMessage = sanitize(rawMessage);

    // Log to console in debug mode
    debugPrint('[ErrorHandler] [$level] $sanitizedMessage');
    if (stackTrace != null) {
      debugPrint(stackTrace.toString());
    }

    // 2. Log to Sentry asynchronously
    unawaited(_logToSentry(error, stackTrace, level, sanitizedMessage));

    // 3. Display UI if requested
    if (showUi) {
      final friendlyMessage = _getFriendlyMessage(error, sanitizedMessage);
      _showErrorUi(friendlyMessage, level);
    }
  }

  /// Internal Sentry logging logic
  static Future<void> _logToSentry(
    dynamic error,
    StackTrace? stackTrace,
    ErrorLevel level,
    String sanitizedMessage,
  ) async {
    try {
      final sentryLevel = _getSentryLevel(level);

      if (error != null) {
        // If error is an exception/object, capture it
        await Sentry.captureException(
          error,
          stackTrace: stackTrace,
          withScope: (scope) async {
            scope.level = sentryLevel;
            await scope.setTag('custom_message', sanitizedMessage);
          },
        );
      } else {
        // If no exception object but we have a message, capture as message
        await Sentry.captureMessage(
          sanitizedMessage,
          level: sentryLevel,
        );
      }
    } on Object catch (e) {
      debugPrint('Failed to send error logs to Sentry: $e');
    }
  }

  /// Maps internal ErrorLevel to SentryLevel
  static SentryLevel _getSentryLevel(ErrorLevel level) {
    switch (level) {
      case ErrorLevel.info:
        return SentryLevel.info;
      case ErrorLevel.warning:
        return SentryLevel.warning;
      case ErrorLevel.error:
        return SentryLevel.error;
      case ErrorLevel.critical:
        return SentryLevel.fatal;
    }
  }

  /// Displays the appropriate UI element (Toast or Dialog)
  static void _showErrorUi(String message, ErrorLevel level) {
    final context = navigatorKey.currentContext;
    if (context == null) {
      // Navigator not yet ready, defer to next frame
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _showErrorUi(message, level);
      });
      return;
    }

    if (level == ErrorLevel.info || level == ErrorLevel.warning) {
      _displayToast(context, message, level);
    } else {
      _displayDialog(context, message, level);
    }
  }

  /// Displays a modern, floating Toast notification using OverlayEntry and flutter_animate
  static void _displayToast(BuildContext context, String message, ErrorLevel level) {
    _toastTimer?.cancel();
    _activeToast?.remove();
    _activeToast = null;

    final overlayState = Overlay.of(context);
    
    // Choose colors/icons based on level
    final isWarning = level == ErrorLevel.warning;
    final accentColor = isWarning ? const Color(0xFFFFB300) : const Color(0xFFFF7597);
    final icon = isWarning ? Icons.warning_amber_rounded : Icons.info_outline_rounded;
    final title = isWarning ? 'Warning' : 'Information';

    final entry = OverlayEntry(
      builder: (context) {
        return Positioned(
          top: MediaQuery.of(context).padding.top + 16,
          left: 16,
          right: 16,
          child: SafeArea(
            top: false,
            child: Material(
              color: Colors.transparent,
              child: Container(
                decoration: BoxDecoration(
                  color: const Color(0xFF161B26).withValues(alpha: 0.9),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: accentColor.withValues(alpha: 0.3),
                    width: 1.5,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: accentColor.withValues(alpha: 0.1),
                      blurRadius: 16,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Row(
                  children: [
                    Icon(icon, color: accentColor, size: 24),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            title,
                            style: TextStyle(
                              color: accentColor,
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            message,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                              height: 1.3,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, color: Colors.white60, size: 18),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      onPressed: () {
                        _toastTimer?.cancel();
                        _activeToast?.remove();
                        _activeToast = null;
                      },
                    ),
                  ],
                ),
              )
                  .animate()
                  .slideY(
                    begin: -0.3,
                    end: 0,
                    duration: 350.ms,
                    curve: Curves.easeOutBack,
                  )
                  .fadeIn(duration: 300.ms),
            ),
          ),
        );
      },
    );

    _activeToast = entry;
    Future.delayed(Duration.zero, () {
      if (!context.mounted) return;
      overlayState.insert(entry);
    });

    // Automatically remove toast after 4 seconds
    _toastTimer = Timer(const Duration(seconds: 4), () {
      entry.remove();
      if (_activeToast == entry) {
        _activeToast = null;
      }
    });
  }

  /// Displays an elegant, premium error Dialog
  static void _displayDialog(BuildContext context, String message, ErrorLevel level) {
    final isCritical = level == ErrorLevel.critical;
    final dialogAccentColor = isCritical ? const Color(0xFFD32F2F) : const Color(0xFFE53935);
    final icon = isCritical ? Icons.report_problem_rounded : Icons.error_outline_rounded;
    final title = isCritical ? 'Critical System Error' : 'An Error Occurred';

    Future.delayed(Duration.zero, () {
      if (!context.mounted) return;
      unawaited(showDialog<void>(
        context: context,
        barrierDismissible: !isCritical, // Force critical errors to require interaction/acknowledgement
        barrierColor: Colors.black.withValues(alpha: 0.75),
        builder: (context) {
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
          child: Container(
            decoration: BoxDecoration(
              color: const Color(0xFF161B26),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: dialogAccentColor.withValues(alpha: 0.4),
                width: 2,
              ),
              boxShadow: [
                BoxShadow(
                  color: dialogAccentColor.withValues(alpha: 0.15),
                  blurRadius: 32,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Glow icon header
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: dialogAccentColor.withValues(alpha: 0.1),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: dialogAccentColor.withValues(alpha: 0.3),
                          width: 1.5,
                        ),
                      ),
                      child: Icon(
                        icon,
                        color: dialogAccentColor,
                        size: 44,
                      ),
                    )
                        .animate()
                        .scale(
                          begin: const Offset(0.8, 0.8),
                          end: const Offset(1, 1),
                          duration: 400.ms,
                          curve: Curves.elasticOut,
                        ),
                    const SizedBox(height: 20),
                    
                    // Title
                    Text(
                      title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.5,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 12),
                    
                    // Message
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
                      decoration: BoxDecoration(
                        color: const Color(0xFF07080A),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.05),
                        ),
                      ),
                      child: Text(
                        message,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.85),
                          fontSize: 14,
                          height: 1.45,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                    const SizedBox(height: 24),
                    
                    // Dialog buttons
                    Column(
                      children: [
                        if (isCritical) ...[
                          SizedBox(
                            width: double.infinity,
                            height: 48,
                            child: ElevatedButton.icon(
                              onPressed: () {
                                // Action is left as a placeholder for now
                                debugPrint('Contact Support tapped.');
                              },
                              icon: const Icon(Icons.support_agent_rounded, color: Colors.white),
                              label: const Text(
                                'Contact Support',
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ),
                               style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFFFF7597),
                                shadowColor: const Color(0xFFFF7597).withValues(alpha: 0.3),
                                elevation: 4,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                        ],
                        SizedBox(
                          width: double.infinity,
                          height: 46,
                          child: OutlinedButton(
                            onPressed: () {
                              if (isCritical) {
                                unawaited(SystemNavigator.pop());
                              } else {
                                Navigator.of(context).pop();
                              }
                            },
                            style: OutlinedButton.styleFrom(
                              side: BorderSide(
                                color: Colors.white.withValues(alpha: 0.2),
                                width: 1.5,
                              ),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12)),
                            ),
                            child: Text(
                              isCritical ? 'Close App' : 'Dismiss',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          )
              .animate()
              .scale(
                begin: const Offset(0.9, 0.9),
                end: const Offset(1, 1),
                duration: 250.ms,
                curve: Curves.easeOutBack,
              )
              .fadeIn(duration: 200.ms),
        );
      },
    ));
    });
  }
}
