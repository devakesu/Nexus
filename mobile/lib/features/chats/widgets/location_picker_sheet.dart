import 'dart:async';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:nexus/core/widgets/aesthetic_loaders.dart';
import 'package:nexus/features/chats/providers/chat_conversation_provider.dart';

/// Full-screen location picker: current-location button (via geolocator),
/// tap-to-drop-pin, and a basic/satellite MapType toggle. Pops with a
/// [LocationPointer] on confirm, or null if dismissed.
class LocationPickerSheet extends StatefulWidget {
  const LocationPickerSheet({required this.themeColor, super.key});

  final Color themeColor;

  @override
  State<LocationPickerSheet> createState() => _LocationPickerSheetState();
}

class _LocationPickerSheetState extends State<LocationPickerSheet> {
  static const _fallback = LatLng(12.9716, 77.5946);

  GoogleMapController? _mapController;
  LatLng _selected = _fallback;
  MapType _mapType = MapType.normal;
  bool _loadingLocation = true;
  final _labelController = TextEditingController();

  @override
  void initState() {
    super.initState();
    unawaited(_goToCurrentLocation());
  }

  @override
  void dispose() {
    _labelController.dispose();
    super.dispose();
  }

  Future<void> _goToCurrentLocation() async {
    setState(() => _loadingLocation = true);
    try {
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return;
      }
      if (!await Geolocator.isLocationServiceEnabled()) return;

      Position? position;
      try {
        position = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.medium,
            timeLimit: Duration(seconds: 10),
          ),
        );
      } on Object {
        position = await Geolocator.getLastKnownPosition();
      }
      if (position == null || !mounted) return;
      final latLng = LatLng(position.latitude, position.longitude);
      setState(() => _selected = latLng);
      unawaited(
        _mapController?.animateCamera(CameraUpdate.newLatLng(latLng)),
      );
    } on Exception {
      // Keep the fallback/previously-selected location if this fails.
    } finally {
      if (mounted) setState(() => _loadingLocation = false);
    }
  }

  void _confirm() {
    final label = _labelController.text.trim();
    Navigator.of(context).pop(
      LocationPointer(
        lat: _selected.latitude,
        lng: _selected.longitude,
        label: label.isEmpty ? null : label,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Choose a location'),
        backgroundColor: widget.themeColor,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: Icon(
              _mapType == MapType.normal
                  ? LucideIcons.satellite
                  : LucideIcons.map,
            ),
            tooltip: _mapType == MapType.normal
                ? 'Satellite view'
                : 'Standard view',
            onPressed: () => setState(
              () => _mapType = _mapType == MapType.normal
                  ? MapType.satellite
                  : MapType.normal,
            ),
          ),
        ],
      ),
      body: Stack(
        children: [
          GoogleMap(
            initialCameraPosition: CameraPosition(target: _selected, zoom: 15),
            mapType: _mapType,
            onMapCreated: (controller) => _mapController = controller,
            onTap: (latLng) => setState(() => _selected = latLng),
            markers: {
              Marker(markerId: const MarkerId('selected'), position: _selected),
            },
          ),
          if (_loadingLocation)
            const Positioned(
              top: 16,
              left: 0,
              right: 0,
              child: Center(child: NexusOrbitLoader(size: 32, lightMode: true)),
            ),
          Positioned(
            right: 16,
            bottom: 150,
            child: FloatingActionButton(
              heroTag: 'current-location',
              backgroundColor: Colors.white,
              onPressed: () => unawaited(_goToCurrentLocation()),
              child: Icon(LucideIcons.locate, color: widget.themeColor),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Container(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 20),
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: _labelController,
                    decoration: InputDecoration(
                      hintText: 'Label (optional), e.g. Blue Bottle Coffee',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      const Icon(
                        LucideIcons.info,
                        size: 13,
                        color: Color(0xFF64748B),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          'Your exact pin coordinates will be shared with the other participant.',
                          style: GoogleFonts.inter(
                            fontSize: 11.5,
                            color: const Color(0xFF64748B),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _confirm,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: widget.themeColor,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: Text(
                        'Use this location',
                        style: GoogleFonts.manrope(fontWeight: FontWeight.w700),
                      ),
                    ),
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
