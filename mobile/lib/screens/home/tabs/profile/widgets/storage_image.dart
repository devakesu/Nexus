import 'dart:io';

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
    final authenticatedUrl =
        publicUrl.replaceFirst('/public/', '/authenticated/');
    final session = Supabase.instance.client.auth.currentSession;
    final token = session?.accessToken;
    final apikey = AppConfig.current.supabasePublishableKey;

    return Image.network(
      authenticatedUrl,
      headers: {
        if (token != null) 'Authorization': 'Bearer $token',
        'apikey': apikey,
      },
      width: width,
      height: height,
      fit: fit,
      errorBuilder: (_, _, _) => _buildError(),
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
