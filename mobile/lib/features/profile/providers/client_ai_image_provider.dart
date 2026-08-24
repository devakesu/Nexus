import 'dart:io';
import 'dart:ui' as ui;

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_image_labeling/google_mlkit_image_labeling.dart';
import 'package:nexus/core/config/app_config.dart';
import 'package:path_provider/path_provider.dart';
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

    final updatedDeletions = List<String>.from(state.pendingDeletions);
    // If we are replacing an existing remote path, queue it for deletion
    if (slotIndex < state.remotePaths.length &&
        state.remotePaths[slotIndex].isNotEmpty) {
      updatedDeletions.add(state.remotePaths[slotIndex]);
    }

    final updatedPending = Map<int, File>.from(state.pendingUploads)
      ..[slotIndex] = localFile;

    // Mark this slot pending immediately so the UI can overlay a spinner on
    // the freshly-picked image right away, instead of only once AI tagging
    // (below) and the eventual network upload happen to be in flight.
    state = state.copyWith(
      pendingUploads: updatedPending,
      pendingDeletions: updatedDeletions,
      isProcessingAI: true,
    );

    // 1. Run your Local Client-Side AI Inference Core directly on-device
    final freshlyComputedTags = await _runOnDeviceVisionModel(
      localFile,
      userBranch: userBranch,
    );

    if (!ref.mounted) return;

    final updatedTags = Map<int, List<String>>.from(state.slotSpecificVibeTags)
      ..[slotIndex] = freshlyComputedTags;

    state = state.copyWith(
      slotSpecificVibeTags: updatedTags,
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
    }

    if (slotIndex > 0) {
      // Shift normal pics (1, 2, 3, 4) down
      for (var i = slotIndex; i < 4; i++) {
        updatedRemote[i] = updatedRemote[i + 1];
      }
      updatedRemote[4] = '';
    } else {
      updatedRemote[0] = '';
    }

    // Re-index remaining pending and tags consistent with shifting
    final updatedPending = <int, File>{};
    state.pendingUploads.forEach((k, v) {
      if (k < slotIndex) {
        updatedPending[k] = v;
      } else if (k > slotIndex) {
        if (slotIndex > 0) {
          updatedPending[k - 1] = v;
        } else {
          updatedPending[k] = v;
        }
      }
    });

    final updatedTags = <int, List<String>>{};
    state.slotSpecificVibeTags.forEach((k, v) {
      if (k < slotIndex) {
        updatedTags[k] = v;
      } else if (k > slotIndex) {
        if (slotIndex > 0) {
          updatedTags[k - 1] = v;
        } else {
          updatedTags[k] = v;
        }
      }
    });

    state = state.copyWith(
      remotePaths: updatedRemote,
      pendingUploads: updatedPending,
      slotSpecificVibeTags: updatedTags,
      pendingDeletions: updatedDeletions,
    );
  }

  void swapImageSlots(int fromIndex, int toIndex) {
    backupState();
    final updatedRemote = List<String>.from(state.remotePaths);
    final tempRemote = updatedRemote[fromIndex];
    updatedRemote[fromIndex] = updatedRemote[toIndex];
    updatedRemote[toIndex] = tempRemote;

    final updatedPending = Map<int, File>.from(state.pendingUploads);
    final fromFile = updatedPending[fromIndex];
    final toFile = updatedPending[toIndex];
    if (fromFile != null) {
      updatedPending[toIndex] = fromFile;
    } else {
      updatedPending.remove(toIndex);
    }
    if (toFile != null) {
      updatedPending[fromIndex] = toFile;
    } else {
      updatedPending.remove(fromIndex);
    }

    final updatedTags = Map<int, List<String>>.from(state.slotSpecificVibeTags);
    final fromTags = updatedTags[fromIndex];
    final toTags = updatedTags[toIndex];
    if (fromTags != null) {
      updatedTags[toIndex] = fromTags;
    } else {
      updatedTags.remove(toIndex);
    }
    if (toTags != null) {
      updatedTags[fromIndex] = toTags;
    } else {
      updatedTags.remove(fromIndex);
    }

    state = state.copyWith(
      remotePaths: updatedRemote,
      pendingUploads: updatedPending,
      slotSpecificVibeTags: updatedTags,
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

      // Truncate to maximum 15 tags to prevent backend size validation failures
      final truncatedTags = unifiedUniqueTags.take(15).toList();

      // 3. Dispatch unified payload containing storage URLs and tags to FastAPI
      final config = AppConfig.current;

      await dioClient.post<dynamic>(
        '${config.backendUrl}/api/v1/profile/media',
        data: {
          'profile_pic': finalOrderedPaths[0],
          'normal_pics': finalOrderedPaths
              .sublist(1)
              .where((p) => p.isNotEmpty)
              .toList(),
          'ai_vibe_tags': truncatedTags.isNotEmpty
              ? truncatedTags
              : ['ambient-vibe'],
        },
      );

      if (!ref.mounted) return;

      // 4. Purge old remote files from Supabase Storage bucket ONLY after sync is successful
      if (state.pendingDeletions.isNotEmpty) {
        try {
          await storage.remove(state.pendingDeletions);
        } on Object catch (e) {
          // Non-fatal: log storage removal error but proceed with transaction
          if (kDebugMode) {
            debugPrint(
              '[ClientAIImageManager] Failed to remove old media files: $e',
            );
          }
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
          if (kDebugMode) {
            debugPrint(
              '[ClientAIImageManager] Failed to roll back uploaded media files on failure: $err',
            );
          }
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
    'outerwear',
    'footwear',
    't-shirt',
    'shirt',
    'jeans',
    'pants',
    'shoe',
    'shoes',
    'wood',
    'glass',
    'metal',
    'plastic',
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
    'keyboard': 'workspace-steez',
    'glasses': 'geek-chic',
    'eyewear': 'geek-chic',
    'desk': 'workspace-steez',
    'office': 'deep-work',

    // Coffee Culture & Lifestyle
    'coffee': 'caffeine-addict',
    'espresso': 'caffeine-addict',
    'cafe': 'coffee-shop-steez',
    'cafeteria': 'coffee-shop-steez',
    'mug': 'ambient-brew',
    'cup': 'ambient-brew',
    'teapot': 'ambient-brew',
    'restaurant': 'foodie-orbit',
    'food': 'foodie-orbit',
    'cuisine': 'foodie-orbit',
    'dish': 'foodie-orbit',
    'meal': 'foodie-orbit',

    // Food, Desserts & Drinks
    'pizza': 'foodie-orbit',
    'burger': 'foodie-orbit',
    'sandwich': 'foodie-orbit',
    'cake': 'sweet-tooth',
    'dessert': 'sweet-tooth',
    'bakery': 'sweet-tooth',
    'ice-cream': 'sweet-tooth',
    'chocolate': 'sweet-tooth',
    'wine': 'nightlife-vibe',
    'beer': 'nightlife-vibe',
    'cocktail': 'nightlife-vibe',
    'bar': 'nightlife-vibe',

    // Creative & Intellectual
    'book': 'intellectual',
    'books': 'book-worm-era',
    'notebook': 'intellectual',
    'library': 'quiet-hours',
    'bookcase': 'quiet-hours',
    'musical-instrument': 'analog-vibe',
    'guitar': 'indie-vibe',
    'acoustic-guitar': 'indie-vibe',
    'electric-guitar': 'indie-vibe',
    'piano': 'classical-vibe',
    'keyboard-instrument': 'classical-vibe',
    'drum': 'sonic-era',
    'drums': 'sonic-era',
    'audio-equipment': 'sonic-era',
    'headphones': 'sonic-era',
    'earphones': 'sonic-era',
    'microphone': 'creative-expression',
    'art': 'creative-expression',
    'painting': 'creative-expression',
    'easel': 'creative-expression',
    'canvas': 'creative-expression',

    // Nature, Environment & Travel/Escapism
    'plant': 'solarpunk',
    'houseplant': 'solarpunk',
    'tree': 'canopy-escape',
    'trees': 'canopy-escape',
    'forest': 'canopy-escape',
    'woodland': 'canopy-escape',
    'vegetation': 'organic-vibe',
    'nature': 'organic-vibe',
    'sky': 'celestial-vibe',
    'night': 'midnight-era',
    'sunset': 'golden-hour-club',
    'sunrise': 'early-bird',
    'mountain': 'wanderlust',
    'hill': 'wanderlust',
    'lake': 'wanderlust',
    'river': 'wanderlust',
    'valley': 'wanderlust',
    'beach': 'wanderlust',
    'ocean': 'wanderlust',
    'sea': 'wanderlust',
    'sand': 'wanderlust',
    'backpack': 'wanderlust',
    'sleeping-bag': 'wanderlust',
    'tent': 'wanderlust',
    'campground': 'wanderlust',

    // Pets & Animals
    'cat': 'feline-friend',
    'kitten': 'feline-friend',
    'dog': 'canine-energy',
    'puppy': 'canine-energy',
    'pet': 'animal-lover',
    'horse': 'equestrian-vibe',
    'bird': 'nature-lover',

    // Fashion, Styles & Presentation
    'suit': 'dapper-era',
    'groom': 'dapper-era',
    'tuxedo': 'dapper-era',
    'blazer': 'dapper-era',
    'windsor-tie': 'dapper-era',
    'necktie': 'dapper-era',
    'cardigan': 'dapper-era',
    'jersey': 'active-orbit',
    'activewear': 'active-orbit',
    'sneaker': 'streetwear-steez',
    'sneakers': 'streetwear-steez',
    'runningshoe': 'active-orbit',
    'sunglasses': 'sun-club',
    'sunglass': 'sun-club',

    // Vehicles & Adventure
    'car': 'motor-enthusiast',
    'sports-car': 'motor-enthusiast',
    'convertible': 'motor-enthusiast',
    'motorcycle': 'adventure-seeker',
    'scooter': 'adventure-seeker',
    'bicycle': 'active-orbit',
    'bike': 'active-orbit',

    // Games & Recreation
    'gamepad': 'gamer-era',
    'controller': 'gamer-era',
    'joystick': 'gamer-era',
    'board-game': 'tabletop-steez',
    'chess': 'tabletop-steez',

    // Tools & Artifacts
    'spatula': 'foodie-orbit',
    'paintbrush': 'creative-expression',
    'mortarboard': 'academic-era',
  };

  /// Runs local machine vision calculations with strict filtering layers.
  Future<List<String>> processImageToAestheticTags({
    required File imageFile,
    required String userBranch,
  }) async {
    // Pre-compress and optimize the image footprint to safeguard NPU memory scales
    final optimizedFile = await _downscaleInferenceTarget(imageFile);
    final inputImage = InputImage.fromFile(optimizedFile);

    // Copy model asset to local support directory to resolve the file path for native ML Kit
    final modelPath = await _getLocalModelPath();
    final imageLabeler = ImageLabeler(
      options: LocalLabelerOptions(
        modelPath: modelPath,
      ),
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

        // STEP D: Fallback Sanitization - Disabled.
        // We only allow curated aesthetic tags from the translation matrix
        // or semantic filters to prevent literal object names from polluting the vibes.
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
      if (kDebugMode) {
        debugPrint(
          '[VisionBroker Critical] On-device labeling execution aborted: $e',
        );
      }
      return ['cosmic-dreamer'];
    } finally {
      await imageLabeler.close(); // Hard memory-leak prevention lock
      if (optimizedFile.path != imageFile.path && optimizedFile.existsSync()) {
        optimizedFile
            .deleteSync(); // Delete localized temporary downscaled frames
      }
    }
  }

  /// Low-resolution thumbnail factory downscaling target scopes to maximize NPU efficiency
  Future<File> _downscaleInferenceTarget(File file) async {
    try {
      final bytes = await file.readAsBytes();
      final codec = await ui.instantiateImageCodec(
        bytes,
        targetWidth: 640,
      );
      final frameInfo = await codec.getNextFrame();
      final image = frameInfo.image;

      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) return file;

      final scaledBytes = byteData.buffer.asUint8List();

      final tempDir = Directory.systemTemp;
      final tempFile = File(
        '${tempDir.path}/scaled_${DateTime.now().microsecondsSinceEpoch}.png',
      );
      await tempFile.writeAsBytes(scaledBytes);
      return tempFile;
    } on Object catch (_) {
      return file;
    }
  }

  Future<String> _getLocalModelPath() async {
    final supportDir = await getApplicationSupportDirectory();
    final localFile = File('${supportDir.path}/model.tflite');

    // Always overwrite to ensure changes in assets/model.tflite are updated on the device
    final byteData = await rootBundle.load('assets/model.tflite');
    await localFile.writeAsBytes(
      byteData.buffer.asUint8List(
        byteData.offsetInBytes,
        byteData.lengthInBytes,
      ),
    );
    return localFile.path;
  }
}
