import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:nexus/config/app_config.dart';
import 'package:nexus/theme/app_colors.dart';

class _PlaceSuggestion {
  const _PlaceSuggestion({
    required this.description,
    this.placeId,
  });

  final String description;
  final String? placeId;
}

class PlaceAutocompleteField extends StatefulWidget {
  const PlaceAutocompleteField({
    required this.label,
    required this.initialValue,
    required this.hintText,
    required this.prefixIcon,
    required this.onChanged,
    this.onFieldSubmitted,
    this.isSaving = false,
    this.focusNode,
    super.key,
  });

  final String label;
  final String initialValue;
  final String hintText;
  final IconData prefixIcon;
  final ValueChanged<String> onChanged;
  final ValueChanged<String>? onFieldSubmitted;
  final bool isSaving;
  final FocusNode? focusNode;

  @override
  State<PlaceAutocompleteField> createState() => PlaceAutocompleteFieldState();
}

class PlaceAutocompleteFieldState extends State<PlaceAutocompleteField> {
  late FocusNode _focusNode;
  bool _isFocused = false;

  static const List<String> _allPlaces = [
    'New York, NY',
    'San Francisco, CA',
    'Los Angeles, CA',
    'Chicago, IL',
    'Boston, MA',
    'Seattle, WA',
    'Austin, TX',
    'Miami, FL',
    'Denver, CO',
    'Atlanta, GA',
    'London, UK',
    'Paris, France',
    'Berlin, Germany',
    'Tokyo, Japan',
    'Singapore',
    'Sydney, Australia',
    'Toronto, Canada',
    'Mumbai, India',
    'Delhi, India',
    'Bangalore, India',
    'Hyderabad, India',
    'Chennai, India',
    'Pune, India',
    'Kolkata, India',
    'San Jose, CA',
    'Portland, OR',
  ];

  static const Map<String, LatLng> _cityCoordinates = {
    'New York, NY': LatLng(40.7128, -74.0060),
    'San Francisco, CA': LatLng(37.7749, -122.4194),
    'Los Angeles, CA': LatLng(34.0522, -118.2437),
    'Chicago, IL': LatLng(41.8781, -87.6298),
    'Boston, MA': LatLng(42.3601, -71.0589),
    'Seattle, WA': LatLng(47.6062, -122.3321),
    'Austin, TX': LatLng(30.2672, -97.7431),
    'Miami, FL': LatLng(25.7617, -80.1918),
    'Denver, CO': LatLng(39.7392, -104.9903),
    'Atlanta, GA': LatLng(33.7490, -84.3880),
    'London, UK': LatLng(51.5074, -0.1278),
    'Paris, France': LatLng(48.8566, 2.3522),
    'Berlin, Germany': LatLng(52.5200, 13.4050),
    'Tokyo, Japan': LatLng(35.6762, 139.6503),
    'Singapore': LatLng(1.3521, 103.8198),
    'Sydney, Australia': LatLng(-33.8688, 151.2093),
    'Toronto, Canada': LatLng(43.6532, -79.3832),
    'Mumbai, India': LatLng(19.0760, 72.8777),
    'Delhi, India': LatLng(28.7041, 77.1025),
    'Bangalore, India': LatLng(12.9716, 77.5946),
    'Hyderabad, India': LatLng(17.3850, 78.4867),
    'Chennai, India': LatLng(13.0827, 80.2707),
    'Pune, India': LatLng(18.5204, 73.8567),
    'Kolkata, India': LatLng(22.5726, 88.3639),
    'San Jose, CA': LatLng(37.3382, -121.8863),
    'Portland, OR': LatLng(45.5152, -122.6784),
  };

  LatLng _getCoordinatesForCity(String city) {
    if (city.isEmpty) return const LatLng(12.9716, 77.5946); // Bangalore fallback
    final trimmed = city.trim();
    if (_cityCoordinates.containsKey(trimmed)) {
      return _cityCoordinates[trimmed]!;
    }
    for (final entry in _cityCoordinates.entries) {
      if (entry.key.toLowerCase() == trimmed.toLowerCase()) {
        return entry.value;
      }
    }
    for (final entry in _cityCoordinates.entries) {
      if (entry.key.toLowerCase().contains(trimmed.toLowerCase()) ||
          trimmed.toLowerCase().contains(entry.key.toLowerCase())) {
        return entry.value;
      }
    }
    return const LatLng(40.7128, -74.0060); // New York fallback
  }

  @override
  void initState() {
    super.initState();
    _focusNode = widget.focusNode ?? FocusNode();
    _focusNode.addListener(() {
      if (!mounted) return;
      setState(() {
        _isFocused = _focusNode.hasFocus;
      });
      if (_focusNode.hasFocus) {
        _focusNode.unfocus();
        openLocationPicker();
      }
    });
  }

  @override
  void dispose() {
    if (widget.focusNode == null) {
      _focusNode.dispose();
    }
    super.dispose();
  }

  void openLocationPicker() {
    unawaited(
      showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (context) => _LocationPickerSheet(
          label: widget.label,
          initialValue: widget.initialValue,
          allPlaces: _allPlaces,
          getCoordinatesForCity: _getCoordinatesForCity,
          onConfirmed: (selectedValue) {
            widget.onChanged(selectedValue);
            widget.onFieldSubmitted?.call(selectedValue);
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    const pulsarPink = AppColors.pulsarPink;
    final valueToShow = widget.initialValue;

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.label.toUpperCase(),
            style: TextStyle(
              color: Colors.black.withValues(alpha: 0.5),
              fontSize: 10,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 8),
          GestureDetector(
            onTap: openLocationPicker,
            behavior: HitTestBehavior.opaque,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                gradient: _isFocused
                    ? const LinearGradient(
                        colors: [Color(0xFF00E5FF), pulsarPink],
                      )
                    : LinearGradient(
                        colors: [
                          Colors.black.withValues(alpha: 0.08),
                          Colors.black.withValues(alpha: 0.08),
                        ],
                      ),
                boxShadow: _isFocused
                    ? [
                        BoxShadow(
                          color: pulsarPink.withValues(alpha: 0.2),
                          blurRadius: 12,
                          spreadRadius: 1,
                        ),
                      ]
                    : [],
              ),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                margin: const EdgeInsets.all(1.2),
                padding: const EdgeInsets.symmetric(vertical: 13, horizontal: 12),
                decoration: BoxDecoration(
                  color: _isFocused ? Colors.white : const Color(0xFFF3F4F6),
                  borderRadius: BorderRadius.circular(15),
                ),
                child: Stack(
                  children: [
                    Row(
                      children: [
                        Icon(
                          widget.prefixIcon,
                          color: _isFocused ? pulsarPink : Colors.black38,
                          size: 18,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            valueToShow.isNotEmpty ? valueToShow : widget.hintText,
                            style: TextStyle(
                              color: valueToShow.isNotEmpty
                                  ? const Color(0xFF0F172A)
                                  : Colors.black.withValues(alpha: 0.3),
                              fontSize: 14,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const Icon(
                          LucideIcons.chevronRight,
                          color: Colors.black26,
                          size: 16,
                        ),
                      ],
                    ),
                    if (widget.isSaving)
                      const Positioned(
                        left: 0,
                        right: 0,
                        bottom: 0,
                        child: ClipRRect(
                          borderRadius: BorderRadius.only(
                            bottomLeft: Radius.circular(15),
                            bottomRight: Radius.circular(15),
                          ),
                          child: SizedBox(
                            height: 2,
                            child: LinearProgressIndicator(
                              backgroundColor: Colors.transparent,
                              valueColor: AlwaysStoppedAnimation<Color>(
                                pulsarPink,
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LocationPickerSheet extends StatefulWidget {
  const _LocationPickerSheet({
    required this.label,
    required this.initialValue,
    required this.allPlaces,
    required this.getCoordinatesForCity,
    required this.onConfirmed,
  });

  final String label;
  final String initialValue;
  final List<String> allPlaces;
  final LatLng Function(String) getCoordinatesForCity;
  final ValueChanged<String> onConfirmed;

  @override
  State<_LocationPickerSheet> createState() => _LocationPickerSheetState();
}

class _LocationPickerSheetState extends State<_LocationPickerSheet> {
  late TextEditingController _searchController;
  late String _selectedLocation;
  late LatLng _currentLatLng;
  GoogleMapController? _mapController;
  List<_PlaceSuggestion> _suggestions = [];
  bool _isFocused = false;
  bool _isLoading = false;
  final Dio _dio = Dio();

  @override
  void initState() {
    super.initState();
    _selectedLocation = widget.initialValue;
    _currentLatLng = widget.getCoordinatesForCity(_selectedLocation);
    _searchController = TextEditingController(text: _selectedLocation);
  }

  @override
  void dispose() {
    _searchController.dispose();
    _dio.close();
    super.dispose();
  }

  Future<void> _onSearchChanged(String text) async {
    if (text.trim().isEmpty) {
      setState(() {
        _suggestions = [];
      });
      return;
    }

    final apiKey = AppConfig.current.googlePlacesApiKey;
    if (apiKey.isEmpty) {
      // Graceful fallback to mock data search
      final query = text.toLowerCase();
      setState(() {
        _suggestions = widget.allPlaces
            .where((place) => place.toLowerCase().contains(query))
            .map((p) => _PlaceSuggestion(description: p))
            .toList();
      });
      return;
    }

    setState(() => _isLoading = true);
    try {
      final response = await _dio.get<Map<String, dynamic>>(
        'https://maps.googleapis.com/maps/api/place/autocomplete/json',
        queryParameters: {
          'input': text,
          'types': '(cities)',
          'key': apiKey,
        },
      );

      if (!mounted) return;
      if (response.data != null && response.data!['status'] == 'OK') {
        final predictions = response.data!['predictions'] as List<dynamic>;
        setState(() {
          _suggestions = predictions.map((item) {
            final pred = item as Map<String, dynamic>;
            return _PlaceSuggestion(
              description: pred['description'] as String,
              placeId: pred['place_id'] as String,
            );
          }).toList();
        });
      } else {
        debugPrint('Google Places Autocomplete API Error: ${response.data}');
        setState(() {
          _suggestions = [];
        });
      }
    } on Object catch (e) {
      debugPrint('Google Places Autocomplete Request Exception: $e');
      if (!mounted) return;
      // Fallback on network errors
      final query = text.toLowerCase();
      setState(() {
        _suggestions = widget.allPlaces
            .where((place) => place.toLowerCase().contains(query))
            .map((p) => _PlaceSuggestion(description: p))
            .toList();
      });
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _selectPlace(_PlaceSuggestion suggestion) async {
    final description = suggestion.description;
    var latLng = widget.getCoordinatesForCity(description);

    final apiKey = AppConfig.current.googlePlacesApiKey;
    if (suggestion.placeId != null && apiKey.isNotEmpty) {
      setState(() => _isLoading = true);
      try {
        final response = await _dio.get<Map<String, dynamic>>(
          'https://maps.googleapis.com/maps/api/place/details/json',
          queryParameters: {
            'place_id': suggestion.placeId,
            'fields': 'geometry',
            'key': apiKey,
          },
        );
        if (response.data != null && response.data!['status'] == 'OK') {
          final result = response.data!['result'] as Map<String, dynamic>;
          final geometry = result['geometry'] as Map<String, dynamic>;
          final loc = geometry['location'] as Map<String, dynamic>;
          latLng = LatLng(
            (loc['lat'] as num).toDouble(),
            (loc['lng'] as num).toDouble(),
          );
        } else {
          debugPrint('Google Places Details API Error: ${response.data}');
        }
      } on Object catch (e) {
        debugPrint('Google Places Details Request Exception: $e');
        // Fall back to default coordinate lookup if API details fetch fails
      } finally {
        if (mounted) {
          setState(() => _isLoading = false);
        }
      }
    }

    setState(() {
      _selectedLocation = description;
      _currentLatLng = latLng;
      _searchController.text = description;
      _suggestions = [];
    });

    if (_mapController != null) {
      unawaited(
        _mapController!.animateCamera(
          CameraUpdate.newCameraPosition(
            CameraPosition(
              target: latLng,
              zoom: 11.5,
            ),
          ),
        ),
      );
    }
    if (!mounted) return;
    FocusScope.of(context).unfocus();
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    const pulsarPink = AppColors.pulsarPink;

    return Container(
      height: 600 + bottomInset,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(28),
        ),
      ),
      child: Column(
        children: [
          // Drag handle indicator
          const SizedBox(height: 12),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 16),

          // Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Select ${widget.label}',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: const Color(0xFF0F172A),
                  ),
                ),
                GestureDetector(
                  onTap: () => Navigator.pop(context),
                  behavior: HitTestBehavior.opaque,
                  child: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.05),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      LucideIcons.x,
                      size: 18,
                      color: Colors.black54,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Google Map display (Decoration)
          if (bottomInset == 0) ...[
            Container(
              height: 200,
              margin: const EdgeInsets.symmetric(horizontal: 20),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: Colors.black.withValues(alpha: 0.08),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.04),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(19),
                child: Stack(
                  children: [
                    GoogleMap(
                      initialCameraPosition: CameraPosition(
                        target: _currentLatLng,
                        zoom: 11.5,
                      ),
                      onMapCreated: (controller) => _mapController = controller,
                      scrollGesturesEnabled: false,
                      zoomGesturesEnabled: false,
                      tiltGesturesEnabled: false,
                      rotateGesturesEnabled: false,
                      zoomControlsEnabled: false,
                      myLocationButtonEnabled: false,
                      compassEnabled: false,
                      mapToolbarEnabled: false,
                      circles: {
                        Circle(
                          circleId: const CircleId('general_area'),
                          center: _currentLatLng,
                          radius: 6000, // 6km radius showing the general area
                          fillColor: pulsarPink.withValues(alpha: 0.15),
                          strokeColor: pulsarPink.withValues(alpha: 0.4),
                          strokeWidth: 2,
                        ),
                      },
                      markers: {
                        Marker(
                          markerId: const MarkerId('center'),
                          position: _currentLatLng,
                          icon: BitmapDescriptor.defaultMarkerWithHue(
                            BitmapDescriptor.hueRose,
                          ),
                        ),
                      },
                    ),
                    // Decorative overlay label
                    Positioned(
                      right: 12,
                      bottom: 12,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.7),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              LucideIcons.globe,
                              color: Colors.white,
                              size: 12,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              'General Area (Not Scrollable)',
                              style: GoogleFonts.plusJakartaSans(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    if (_isLoading)
                      ColoredBox(
                        color: Colors.white.withValues(alpha: 0.4),
                        child: const Center(
                          child: CircularProgressIndicator(
                            valueColor: AlwaysStoppedAnimation<Color>(pulsarPink),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
          ],

          // Search Field
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                gradient: _isFocused
                    ? const LinearGradient(
                        colors: [Color(0xFF00E5FF), pulsarPink],
                      )
                    : LinearGradient(
                        colors: [
                          Colors.black.withValues(alpha: 0.08),
                          Colors.black.withValues(alpha: 0.08),
                        ],
                      ),
              ),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                margin: const EdgeInsets.all(1.2),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(15),
                ),
                child: Focus(
                  onFocusChange: (hasFocus) {
                    setState(() {
                      _isFocused = hasFocus;
                    });
                  },
                  child: TextFormField(
                    controller: _searchController,
                    onChanged: _onSearchChanged,
                    style: const TextStyle(
                      color: Color(0xFF0F172A),
                      fontSize: 14,
                    ),
                    decoration: InputDecoration(
                      prefixIcon: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: Icon(
                          LucideIcons.search,
                          color: _isFocused ? pulsarPink : Colors.black38,
                          size: 18,
                        ),
                      ),
                      prefixIconConstraints: const BoxConstraints(
                        minWidth: 40,
                        minHeight: 40,
                      ),
                      hintText: 'Type to search locations...',
                      hintStyle: TextStyle(
                        color: Colors.black.withValues(alpha: 0.3),
                        fontSize: 14,
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        vertical: 13,
                      ),
                      border: InputBorder.none,
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),

          // Suggestions / Placeholder Area
          Expanded(
            child: Stack(
              children: [
                if (_suggestions.isEmpty &&
                    _searchController.text.isNotEmpty &&
                    _searchController.text != _selectedLocation &&
                    !_isLoading)
                  Center(
                    child: Text(
                      'No matching locations found.\nPlease choose a location from search.',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.plusJakartaSans(
                        color: Colors.black38,
                        fontSize: 14,
                      ),
                    ),
                  )
                else if (_suggestions.isNotEmpty)
                  ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    itemCount: _suggestions.length,
                    itemBuilder: (context, index) {
                      final suggestion = _suggestions[index];
                      return Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF8FAFC),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: Colors.black.withValues(alpha: 0.04),
                          ),
                        ),
                        child: Material(
                          color: Colors.transparent,
                          borderRadius: BorderRadius.circular(12),
                          clipBehavior: Clip.antiAlias,
                          child: ListTile(
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16,
                            ),
                            dense: true,
                            leading: const Icon(
                              LucideIcons.mapPin,
                              color: pulsarPink,
                              size: 16,
                            ),
                            title: Text(
                              suggestion.description,
                              style: GoogleFonts.plusJakartaSans(
                                color: const Color(0xFF0F172A),
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            onTap: () => _selectPlace(suggestion),
                          ),
                        ),
                      );
                    },
                  )
                else if (_isLoading)
                  const Center(
                    child: CircularProgressIndicator(
                      valueColor: AlwaysStoppedAnimation<Color>(pulsarPink),
                    ),
                  )
                else
                  // Standard instructions view
                  Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 40),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            LucideIcons.search,
                            color: pulsarPink.withValues(alpha: 0.3),
                            size: 48,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            _selectedLocation.isNotEmpty
                                ? 'Selected: $_selectedLocation'
                                : 'Search above to choose a city',
                            textAlign: TextAlign.center,
                            style: GoogleFonts.plusJakartaSans(
                              color: Colors.black87,
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Only locations selected from autocomplete search are valid options.',
                            textAlign: TextAlign.center,
                            style: GoogleFonts.plusJakartaSans(
                              color: Colors.black38,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),

          // Confirm Button
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
            child: SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: _selectedLocation.isNotEmpty && !_isLoading
                    ? () {
                        widget.onConfirmed(_selectedLocation);
                        Navigator.pop(context);
                      }
                    : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: pulsarPink,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: Colors.black12,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                child: Text(
                  'Confirm Selection',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
