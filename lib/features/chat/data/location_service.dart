export 'location_service_io.dart'
    if (dart.library.html) 'location_service_web.dart';

/// Shared location data model (available on all platforms).
class LocationData {
  final double latitude;
  final double longitude;
  final String? city;
  final String? country;

  const LocationData({
    required this.latitude,
    required this.longitude,
    this.city,
    this.country,
  });
}
