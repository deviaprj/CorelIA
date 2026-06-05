import 'dart:async';
import 'package:geolocator/geolocator.dart';
import 'location_service.dart';

/// Native (mobile) implementation using geolocator.
class LocationService {
  LocationData? _cached;

  Future<LocationData?> getCurrentLocation() async {
    if (_cached != null) return _cached;

    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) return null;

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) return null;
      }
      if (permission == LocationPermission.deniedForever) return null;

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.low,
        ),
      );

      _cached = LocationData(
        latitude: position.latitude,
        longitude: position.longitude,
      );
      return _cached;
    } catch (_) {
      return null;
    }
  }

  void clearCache() => _cached = null;
}
