import 'dart:async';
import 'location_service.dart';

/// Native (mobile) implementation.
/// Requires geolocator package in pubspec.yaml for actual location.
/// Falls back to null when geolocator is not configured.
class LocationService {
  LocationData? _cached;

  Future<LocationData?> getCurrentLocation() async {
    if (_cached != null) return _cached;
    // geolocator package required for native location:
    //   geolocator: ^13.0.0
    // Add to pubspec.yaml + flutter pub get to enable.
    return null;
  }

  void clearCache() => _cached = null;
}
