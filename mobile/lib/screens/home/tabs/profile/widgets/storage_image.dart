import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:nexus/config/app_config.dart';
import 'package:nexus/widgets/aesthetic_loaders.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Resolves the same [ImageProvider] + cache key [StorageImage] would use
/// for a remote path, so callers can [precacheImage] ahead of the widget
/// actually mounting (e.g. warming the cache for upcoming Orbit candidates).
/// Returns null for local file paths (already instant, nothing to prefetch)
/// or empty/invalid input.
ImageProvider? resolveStorageImageProvider(String? imagePath) {
  if (imagePath == null || imagePath.isEmpty) return null;
  if (imagePath.startsWith('/') || imagePath.contains('/data/user/')) {
    return null;
  }

  if (imagePath.startsWith('http://') || imagePath.startsWith('https://')) {
    return CachedNetworkImageProvider(
      imagePath,
      cacheKey: Uri.tryParse(imagePath)?.path ?? imagePath,
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

  return CachedNetworkImageProvider(
    authenticatedUrl,
    cacheKey: imagePath,
    headers: {
      'apikey': apikey,
      if (token != null) 'Authorization': 'Bearer $token',
    },
  );
}

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

    if (imagePath.startsWith('http://') || imagePath.startsWith('https://')) {
      // Other users' photos: the user_media bucket's SELECT policy is
      // owner-only, so these arrive as a ready-to-use, already-authorized
      // signed URL from the backend rather than a raw storage path - use it
      // directly instead of re-deriving a (would-be-403) bucket URL below.
      return CachedNetworkImage(
        imageUrl: imagePath,
        // Stable cache key across token refreshes - the signed URL's query
        // string rotates but the underlying storage path doesn't.
        cacheKey: Uri.tryParse(imagePath)?.path ?? imagePath,
        width: width,
        height: height,
        fit: fit,
        placeholder: (context, url) => Container(
          width: width,
          height: height,
          color: const Color(0xFF1E2332),
          child: const Center(
            child: NexusOrbitLoader(size: 28),
          ),
        ),
        errorWidget: (context, url, error) => _buildError(),
      );
    }

    // Own storage path: the requester is the owner, so a direct
    // owner-scoped read against the bucket is still allowed.
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
        'apikey': apikey,
        if (token != null) 'Authorization': 'Bearer $token',
      },
      width: width,
      height: height,
      fit: fit,
      placeholder: (context, url) => Container(
        width: width,
        height: height,
        color: const Color(0xFF1E2332),
        child: const Center(
          child: NexusOrbitLoader(size: 28),
        ),
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
