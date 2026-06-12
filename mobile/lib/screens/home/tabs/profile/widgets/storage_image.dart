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
    super.key,
  });

  final String imagePath;
  final double? width;
  final double? height;
  final BoxFit fit;

  @override
  Widget build(BuildContext context) {
    if (imagePath.startsWith('/') || imagePath.contains('/data/user/')) {
      return Image.file(
        File(imagePath),
        width: width,
        height: height,
        fit: fit,
      );
    }
    
    final publicUrl = Supabase.instance.client.storage.from('user_media').getPublicUrl(imagePath);
    final authenticatedUrl = publicUrl.replaceFirst('/public/', '/authenticated/');
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
      errorBuilder: (context, error, stackTrace) {
        return Container(
          color: const Color(0xFF161B26),
          width: width,
          height: height,
          child: const Center(
            child: Icon(LucideIcons.imageOff, color: Colors.white24, size: 24),
          ),
        );
      },
    );
  }
}
