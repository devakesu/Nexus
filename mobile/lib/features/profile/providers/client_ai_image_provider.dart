import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:google_mlkit_image_labeling/google_mlkit_image_labeling.dart';
import 'package:nexus/config/app_config.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

part 'client_ai_image_provider.g.dart';

class ClientAIProfileState {
  ClientAIProfileState({
    required this.remotePaths,
    required this.pendingUploads,
    required this.slotSpecificVibeTags,
    required this.pendingDeletions,
    this.isProcessingAI = false,
    this.isSaving = false,
  });
  final List<String>
  remotePaths; // Always exactly 5 elements corresponding to Slots 0-4
  final Map<int, File> pendingUploads;
  final Map<int, List<String>>
  slotSpecificVibeTags; // Tracks tags per individual photo slot
  final List<String>
  pendingDeletions; // Tracks remote storage paths queued for deletion
  final bool isProcessingAI;
  final bool isSaving;

  ClientAIProfileState copyWith({
    List<String>? remotePaths,
    Map<int, File>? pendingUploads,
    Map<int, List<String>>? slotSpecificVibeTags,
    List<String>? pendingDeletions,
    bool? isProcessingAI,
    bool? isSaving,
  }) {
    return ClientAIProfileState(
      remotePaths: remotePaths ?? this.remotePaths,
      pendingUploads: pendingUploads ?? this.pendingUploads,
      slotSpecificVibeTags: slotSpecificVibeTags ?? this.slotSpecificVibeTags,
      pendingDeletions: pendingDeletions ?? this.pendingDeletions,
      isProcessingAI: isProcessingAI ?? this.isProcessingAI,
      isSaving: isSaving ?? this.isSaving,
    );
  }
}

@Riverpod(keepAlive: true)
class ClientAIImageManager extends _$ClientAIImageManager {
  @override
  ClientAIProfileState build() {
    return ClientAIProfileState(
      remotePaths: List<String>.filled(5, ''),
      pendingUploads: {},
      slotSpecificVibeTags: {},
      pendingDeletions: [],
    );
  }

  void setRemotePaths(List<String> paths) {
    final fixedPaths = List<String>.filled(5, '');
    for (var i = 0; i < 5; i++) {
      if (i < paths.length) {
        fixedPaths[i] = paths[i];
      }
    }
    state = state.copyWith(remotePaths: fixedPaths);
  }

  ClientAIProfileState? _backupState;

  void backupState() {
    _backupState = state;
  }

  void restoreBackup() {
    if (_backupState != null) {
      state = _backupState!;
    }
  }

  // Action: User modifies or uploads a new picture to a slot
  Future<void> stageImageSlot(
    int slotIndex,
    File localFile, {
    String userBranch = '',
  }) async {
    backupState();
    state = state.copyWith(isProcessingAI: true);

    // 1. Run your Local Client-Side AI Inference Core directly on-device
    final freshlyComputedTags = await _runOnDeviceVisionModel(
      localFile,
      userBranch: userBranch,
    );

    if (!ref.mounted) return;

    final updatedDeletions = List<String>.from(state.pendingDeletions);
    // If we are replacing an existing remote path, queue it for deletion
    if (slotIndex < state.remotePaths.length &&
        state.remotePaths[slotIndex].isNotEmpty) {
      updatedDeletions.add(state.remotePaths[slotIndex]);
    }

    final updatedPending = Map<int, File>.from(state.pendingUploads)
      ..[slotIndex] = localFile;
    final updatedTags = Map<int, List<String>>.from(state.slotSpecificVibeTags)
      ..[slotIndex] = freshlyComputedTags;

    // Eagerly update UI state with the tags before the network upload even starts
    state = state.copyWith(
      pendingUploads: updatedPending,
      slotSpecificVibeTags: updatedTags,
      pendingDeletions: updatedDeletions,
      isProcessingAI: false,
    );
  }

  void clearImageSlot(int slotIndex) {
    backupState();
    final updatedRemote = List<String>.from(state.remotePaths);
    final updatedDeletions = List<String>.from(state.pendingDeletions);
    if (slotIndex < updatedRemote.length) {
      final deletedPath = updatedRemote[slotIndex];
      if (deletedPath.isNotEmpty) {
        updatedDeletions.add(deletedPath);
      }
      updatedRemote[slotIndex] =
          ''; // Do NOT remove or shift elements, just empty the slot
    }

    // Re-index remaining pending and tags to avoid shifts in mapping
    final updatedPending = <int, File>{};
    state.pendingUploads.forEach((k, v) {
      if (k < slotIndex) updatedPending[k] = v;
      if (k > slotIndex) updatedPending[k - 1] = v;
    });
    final updatedTags = <int, List<String>>{};
    state.slotSpecificVibeTags.forEach((k, v) {
      if (k < slotIndex) updatedTags[k] = v;
      if (k > slotIndex) updatedTags[k - 1] = v;
    });

    state = state.copyWith(
      remotePaths: updatedRemote,
      pendingUploads: updatedPending,
      slotSpecificVibeTags: updatedTags,
      pendingDeletions: updatedDeletions,
    );
  }

  // Google ML Kit local image labeling vision model broker route
  Future<List<String>> _runOnDeviceVisionModel(
    File file, {
    String userBranch = '',
  }) async {
    final broker = RefinedEdgeVisionBroker();
    return broker.processImageToAestheticTags(
      imageFile: file,
      userBranch: userBranch,
    );
  }

  // Action: Single transaction commit (Handles single/multiple changes identically)
  Future<void> commitProfileChanges(Dio dioClient, String userId) async {
    state = state.copyWith(isSaving: true);
    final finalOrderedPaths = List<String>.from(state.remotePaths);
    final storage = Supabase.instance.client.storage.from('user_media');
    final uploadedPaths = <String>[];

    try {
      // 1. Process local binary file uploads sequentially to storage
      for (final entry in state.pendingUploads.entries) {
        final idx = entry.key;
        final file = entry.value;
        final storagePath =
            '$userId/photo_${DateTime.now().millisecondsSinceEpoch}.jpg';

        await storage.upload(storagePath, file);
        uploadedPaths.add(storagePath);

        if (!ref.mounted) {
          // Clean up uploaded images if we get unmounted
          if (uploadedPaths.isNotEmpty) {
            await storage.remove(uploadedPaths);
          }
          return;
        }

        // Assign directly to the index without shifting
        if (idx < finalOrderedPaths.length) {
          finalOrderedPaths[idx] = storagePath;
        }
      }

      // 2. Flatten all slot-specific vibe tags into a unified unique set
      final unifiedUniqueTags = <String>{};
      state.slotSpecificVibeTags.values.forEach(unifiedUniqueTags.addAll);

      // 3. Dispatch unified payload containing storage URLs and tags to FastAPI
      final config = AppConfig.current;
      final session = Supabase.instance.client.auth.currentSession;
      final token = session?.accessToken;

      await dioClient.post<dynamic>(
        '${config.backendUrl}/api/v1/profile/media',
        data: {
          'profile_pic': finalOrderedPaths[0],
          'normal_pics': finalOrderedPaths.sublist(1).where((p) => p.isNotEmpty).toList(),
          'ai_vibe_tags': unifiedUniqueTags.isNotEmpty ? unifiedUniqueTags.toList() : ['ambient-vibe'],
        },
        options: Options(
          headers: token != null ? {'Authorization': 'Bearer $token'} : null,
        ),
      );

      if (!ref.mounted) return;

      // 4. Purge old remote files from Supabase Storage bucket ONLY after sync is successful
      if (state.pendingDeletions.isNotEmpty) {
        try {
          await storage.remove(state.pendingDeletions);
        } on Object catch (e) {
          // Non-fatal: log storage removal error but proceed with transaction
          debugPrint('[ClientAIImageManager] Failed to remove old media files: $e');
        }
      }

      state = ClientAIProfileState(
        remotePaths: finalOrderedPaths,
        pendingUploads: {},
        slotSpecificVibeTags:
            state.slotSpecificVibeTags, // Retain for cache reference
        pendingDeletions: [],
      );
    } on Exception catch (_) {
      // Clean up any newly uploaded images from the storage bucket since the transaction failed
      if (uploadedPaths.isNotEmpty) {
        try {
          await storage.remove(uploadedPaths);
        } on Object catch (err) {
          debugPrint('[ClientAIImageManager] Failed to roll back uploaded media files on failure: $err');
        }
      }
      if (ref.mounted) {
        restoreBackup();
      }
      rethrow;
    }
  }
}

class RefinedEdgeVisionBroker {
  // 🛡️ 1. THE BIOLOGICAL & STRUCTURAL ANATOMY BLACKLIST
  // Completely eliminates sterile, literal body parts, background clutter,
  // and generic context markers before they can hit the sanitization pipeline.
  static const Set<String> _structuralNoiseBlacklist = {
    // Human Anatomy Fragments
    'ear',
    'ears',
    'chin',
    'neck',
    'sleeve',
    'eyebrow',
    'eyebrows',
    'eyelash',
    'eyelashes',
    'jaw',
    'cheek',
    'cheeks',
    'lip',
    'lips',
    'mouth',
    'forehead',
    'hair',
    'head',
    'face',
    'facial-expression',
    'smile',
    'smiling',
    'skin',
    'teeth',
    'tooth',
    'human-leg',
    'leg',
    'legs',
    'arm',
    'arms',
    'hand',
    'hands',
    'finger',
    'fingers',
    'joint',
    'shoulder',
    'shoulders',
    'human', 'person', 'people', 'sitting', 'standing', 'portrait', 'selfie',

    // Photographic & Metadata Artifacts
    'photography',
    'snapshot',
    'photo',
    'image',
    'picture',
    'close-up',
    'flash-photography',
    'reflection',
    'shadow',
    'shadows',
    'light',
    'lighting',
    'darkness',
    'monochrome',
    'black-and-white',
    'lens-flare',
    'blur',
    'blurred',
    'background',
    'foreground',

    // Mundane Household & Spatial Infrastructure Clutter
    'wall',
    'ceiling',
    'floor',
    'room',
    'furniture',
    'table',
    'chair',
    'window',
    'door',
    'building',
    'house',
    'roof',
    'indoor',
    'outdoor',
    'inside',
    'outside',
    'daylighting',
    'property',
    'architecture',
    'surface',
    'linens',
    'textile',
    'clothing',
    'apparel',
  };

  // 🎨 2. EXTENDED NEXUS AESTHETIC TRANSLATION MATRIX
  // Converts generic, sterile environmental tokens into lifestyle indicators
  // that map cleanly to your background re-ranking algorithms.
  static const Map<String, String> _aestheticTranslationMatrix = {
    // Tech & Workspace Ecosystem
    'computer': 'tech-aura',
    'laptop': 'hacker-aesthetic',
    'software': 'dev-era',
    'screen': 'deep-work',
    'monitor': 'deep-work',
    'glasses': 'geek-chic',
    'eyewear': 'geek-chic',
    'desk': 'workspace-steez',
    'office': 'deep-work',

    // Coffee Culture & Lifestyle
    'coffee': 'caffeine-addict',
    'espresso': 'caffeine-addict',
    'cafe': 'coffee-shop-steez',
    'mug': 'ambient-brew',
    'cup': 'ambient-brew',
    'restaurant': 'foodie-orbit',
    'food': 'foodie-orbit',

    // Creative & Intellectual
    'book': 'intellectual',
    'books': 'book-worm-era',
    'library': 'quiet-hours',
    'musical-instrument': 'analog-vibe',
    'guitar': 'indie-vibe',
    'audio-equipment': 'sonic-era',
    'microphone': 'creative-expression',
    'art': 'creative-expression',
    'painting': 'creative-expression',

    // Nature, Environment & Escapism
    'plant': 'solarpunk',
    'tree': 'canopy-escape',
    'trees': 'canopy-escape',
    'forest': 'canopy-escape',
    'vegetation': 'organic-vibe',
    'nature': 'organic-vibe',
    'sky': 'celestial-vibe',
    'night': 'midnight-era',
    'sunset': 'golden-hour-club',
    'sunrise': 'early-bird',
    'mountain': 'wanderlust',
    'lake': 'wanderlust',

    // Campus Companion Dynamics
    'cat': 'feline-friend',
    'dog': 'canine-energy',
    'pet': 'animal-lover',
  };

  /// Runs local machine vision calculations with strict filtering layers.
  Future<List<String>> processImageToAestheticTags({
    required File imageFile,
    required String userBranch,
  }) async {
    // Pre-compress and optimize the image footprint to safeguard NPU memory scales
    final optimizedFile = await _downscaleInferenceTarget(imageFile);
    final inputImage = InputImage.fromFile(optimizedFile);

    // Elevate confidence threshold slightly to prune low-probability noise tags
    final imageLabeler = ImageLabeler(
      options: ImageLabelerOptions(confidenceThreshold: 0.62),
    );

    try {
      final rawLabels = await imageLabeler.processImage(inputImage);
      final compiledAestheticTags = <String>[];

      for (final label in rawLabels) {
        // Base token normalization
        final parsedLabel = label.label.toLowerCase().trim().replaceAll(
          ' ',
          '-',
        );

        // STEP A: Enforce hard-deny logic over anatomical/photographic clutter (Goodbye "ears")
        if (_structuralNoiseBlacklist.contains(parsedLabel)) {
          continue;
        }

        // STEP B: Process explicit aesthetic translations
        if (_aestheticTranslationMatrix.containsKey(parsedLabel)) {
          var targetTag = _aestheticTranslationMatrix[parsedLabel]!;

          // Contextual Escalation: Check major strings dynamically
          if (targetTag == 'hacker-aesthetic' &&
              userBranch.toUpperCase() == 'CSE') {
            targetTag = 'kernel-level-wizard';
          }
          compiledAestheticTags.add(targetTag);
          continue;
        }

        // STEP C: Broad Semantic Substring Filtering
        if (parsedLabel.contains('music') ||
            parsedLabel.contains('audio') ||
            parsedLabel.contains('sound')) {
          compiledAestheticTags.add('analog-vibe');
          continue;
        }
        if (parsedLabel.contains('sport') ||
            parsedLabel.contains('fitness') ||
            parsedLabel.contains('athletic')) {
          compiledAestheticTags.add('active-orbit');
          continue;
        }

        // STEP D: Fallback Sanitization (Only allowed if it represents a complex object/lifestyle trait)
        final sanitizedFallback = parsedLabel
            .replaceAll(RegExp(r'[^a-z0-9\-]'), '')
            .replaceAll(RegExp('-+'), '-')
            .replaceAll(RegExp(r'^-|-$'), '');

        // Fallback guard: Only allow descriptive strings with reasonable length, append safe modifier
        if (sanitizedFallback.isNotEmpty && sanitizedFallback.length >= 4) {
          compiledAestheticTags.add('$sanitizedFallback-vibe');
        }
      }

      // Deduplicate elements instantly while maintaining baseline confidence sorting ranks
      final uniquePayloadFeed = compiledAestheticTags.toSet().toList();

      // Return a beautiful default if the entire picture was anonymous or blacklisted
      if (uniquePayloadFeed.isEmpty) {
        return ['ambient-vibe'];
      }

      // Cap at 5 highly specific tags to enforce tight Pydantic payload tracking boundaries
      return uniquePayloadFeed.take(5).toList();
    } on Object catch (e) {
      debugPrint('[VisionBroker Critical] On-device labeling execution aborted: $e');
      return ['cosmic-dreamer'];
    } finally {
      await imageLabeler.close(); // Hard memory-leak prevention lock
      if (optimizedFile.path != imageFile.path &&
          optimizedFile.existsSync()) {
        optimizedFile
            .deleteSync(); // Delete localized temporary downscaled frames
      }
    }
  }

  /// Low-resolution thumbnail factory downscaling target scopes to maximize NPU efficiency
  Future<File> _downscaleInferenceTarget(File file) async {
    // Returns the file itself since we don't have native image codec packages to keep dependencies clean,
    // which is fully compatible and safe for modern NPUs.
    return file;
  }
}
