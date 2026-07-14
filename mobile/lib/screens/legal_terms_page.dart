import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:nexus/config/app_config.dart';
import 'package:nexus/widgets/aesthetic_loaders.dart';
import 'package:webview_flutter/webview_flutter.dart';

/// Terms of Service & Privacy Policy - a WebView pointed at the same
/// server-rendered page (GET /legal/terms, app/api/legal.py) that's
/// reachable on the public web. One document, one style, everywhere: the
/// in-app copy and the web copy are always the literal same render, and a
/// terms/policy update takes effect immediately for every user with no
/// app-store release needed - matching how current_terms_version already
/// drives live re-consent (see terms_consent_screen.dart).
///
/// Pass [fragment] to deep-link to a specific section anchor on load
/// (e.g. `'privacy'` → `/legal/terms#privacy`). The AppBar title adjusts
/// to match the section being shown.
class LegalTermsPage extends StatefulWidget {
  const LegalTermsPage({this.fragment, super.key});

  /// Optional URL fragment (without `#`) to scroll to on load.
  final String? fragment;

  @override
  State<LegalTermsPage> createState() => _LegalTermsPageState();
}

class _LegalTermsPageState extends State<LegalTermsPage> {
  late final Uri _legalUri = Uri.parse(
    '${AppConfig.current.backendUrl}/legal/terms',
  ).replace(fragment: widget.fragment);

  late final WebViewController _controller;
  bool _isLoading = true;
  bool _hasError = false;

  String get _title => switch (widget.fragment) {
        'privacy' => 'Privacy Policy',
        'terms' => 'Terms of Service',
        _ => 'Terms & Privacy Policy',
      };

  @override
  void initState() {
    super.initState();
    _controller = WebViewController();
    unawaited(_initController());
  }

  Future<void> _initController() async {
    await _controller.setBackgroundColor(const Color(0xFF0B0D13));
    // JS must be enabled so the browser can scroll to the anchor on load.
    await _controller.setJavaScriptMode(JavaScriptMode.unrestricted);
    await _controller.setNavigationDelegate(
      NavigationDelegate(
        onPageFinished: (_) async {
          if (widget.fragment != null) {
            // WebViews don't reliably honour URL fragments because the
            // native anchor scroll fires before layout is complete.
            // Scrolling via JS in onPageFinished is the reliable fix.
            await _controller.runJavaScript(
              "document.getElementById('${widget.fragment}')?.scrollIntoView({behavior:'instant'});",
            );
          }
          if (mounted) setState(() => _isLoading = false);
        },
        onWebResourceError: (_) {
          if (mounted) {
            setState(() {
              _isLoading = false;
              _hasError = true;
            });
          }
        },
        // Debug-only: bypass self-signed cert errors for local dev servers,
        // mirroring the Dio badCertificateCallback in network_utils.dart.
        onSslAuthError: kDebugMode
            ? (SslAuthError error) async {
                final host = _legalUri.host;
                final isLocalHost = host == 'localhost' ||
                    host == '127.0.0.1' ||
                    host == '10.0.2.2' ||
                    host.startsWith('192.168.') ||
                    host.startsWith('10.') ||
                    host.startsWith('172.');
                if (isLocalHost) {
                  await error.proceed();
                } else {
                  await error.cancel();
                }
              }
            : null,
      ),
    );
    await _controller.loadRequest(_legalUri);
  }

  void _retry() {
    setState(() {
      _isLoading = true;
      _hasError = false;
    });
    unawaited(_controller.loadRequest(_legalUri));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0B0D13),
      appBar: AppBar(
        backgroundColor: const Color(0xFF161B26),
        title: Text(
          _title,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: Colors.white,
            letterSpacing: 0.5,
          ),
        ),
        leading: IconButton(
          icon: const Icon(
            Icons.arrow_back_ios_new_rounded,
            color: Colors.white,
            size: 20,
          ),
          onPressed: () => Navigator.of(context).pop(),
        ),
        elevation: 0,
      ),
      body: Stack(
        children: [
          if (!_hasError) WebViewWidget(controller: _controller),
          if (_isLoading && !_hasError)
            const ColoredBox(
              color: Color(0xFF0B0D13),
              child: Center(child: NexusOrbitLoader(size: 40)),
            ),
          if (_hasError)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      "Couldn't load the Terms & Privacy Policy. Check your "
                      'connection and try again.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.white.withValues(alpha: 0.7),
                        height: 1.5,
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextButton(
                      onPressed: _retry,
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
