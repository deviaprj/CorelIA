import 'dart:async';
import 'dart:html' as html;
import 'location_service.dart';

/// Web implementation using browser Geolocation API.
class LocationService {
  LocationData? _cached;

  Future<LocationData?> getCurrentLocation() async {
    if (_cached != null) return _cached;

    try {
      final geolocation = html.window.navigator.geolocation;
      if (geolocation == null) return null;

      final position = await geolocation.getCurrentPosition(
        timeout: const Duration(seconds: 10),
      );

      final coords = position.coords;
      if (coords == null) return null;

      final lat = coords.latitude;
      final lon = coords.longitude;
      if (lat == null || lon == null) return null;

      _cached = LocationData(
        latitude: (lat as num).toDouble(),
        longitude: (lon as num).toDouble(),
      );
      return _cached;
    } catch (_) {
      return null;
    }
  }

  void clearCache() => _cached = null;
}
