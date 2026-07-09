import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:nexus/config/app_config.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class StorageImage extends StatelessWidget {
  const StorageImage({
    required this.imagePath,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.errorWidget,
    super.key,
  });

  final String imagePath;
  final double? width;
  final double? height;
  final BoxFit fit;

  /// Shown when the image fails to load. Defaults to a dark container with an imageOff icon.
  final Widget? errorWidget;

  @override
  Widget build(BuildContext context) {
    if (imagePath.startsWith('/') || imagePath.contains('/data/user/')) {
      return Image.file(
        File(imagePath),
        width: width,
        height: height,
        fit: fit,
        errorBuilder: (_, e, s) => _buildError(),
      );
    }

    final publicUrl = Supabase.instance.client.storage
        .from('user_media')
        .getPublicUrl(imagePath);
    final authenticatedUrl = publicUrl.replaceFirst(
      '/public/',
      '/authenticated/',
    );
    final session = Supabase.instance.client.auth.currentSession;
    final token = session?.accessToken;
    final apikey = AppConfig.current.supabasePublishableKey;

    return CachedNetworkImage(
      imageUrl: authenticatedUrl,
      // Stable cache key - doesn't change when the auth token rotates.
      cacheKey: imagePath,
      httpHeaders: {
        if (token != null) 'apikey': apikey,
      },
      width: width,
      height: height,
      fit: fit,
      placeholder: (context, url) => _StorageImageShimmer(
        width: width,
        height: height,
      ),
      errorWidget: (context, url, error) => _buildError(),
    );
  }

  Widget _buildError() {
    if (errorWidget != null) return errorWidget!;
    return Container(
      color: const Color(0xFF161B26),
      width: width,
      height: height,
      child: const Center(
        child: Icon(LucideIcons.imageOff, color: Colors.white24, size: 24),
      ),
    );
  }
}

class _StorageImageShimmer extends StatefulWidget {
  const _StorageImageShimmer({this.width, this.height});

  final double? width;
  final double? height;

  @override
  State<_StorageImageShimmer> createState() => _StorageImageShimmerState();
}

class _StorageImageShimmerState extends State<_StorageImageShimmer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    );
    // TickerFuture from repeat() never needs to be awaited - it resolves only on stop/dispose.
    // ignore: discarded_futures
    _ctrl.repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, _) => ShaderMask(
        blendMode: BlendMode.srcATop,
        shaderCallback: (bounds) => LinearGradient(
          begin: Alignment(_ctrl.value * 3 - 1.5, 0),
          end: Alignment(_ctrl.value * 3 - 0.8, 0),
          colors: [
            Colors.transparent,
            Colors.white.withValues(alpha: 0.12),
            Colors.transparent,
          ],
        ).createShader(bounds),
        child: Container(
          width: widget.width,
          height: widget.height,
          color: const Color(0xFF1E2332),
        ),
      ),
    );
  }
}
