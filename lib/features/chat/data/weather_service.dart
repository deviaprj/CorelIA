import 'package:dio/dio.dart';
import '../../../core/constants.dart';

class WeatherData {
  final String city;
  final String country;
  final double temperature;
  final double feelsLike;
  final String description;
  final int humidity;
  final double windSpeed;
  final String icon;
  final bool isRaining;
  final List<HourlyForecast> hourlyForecast;
  final List<DailyForecast> dailyForecast;

  const WeatherData({
    required this.city,
    required this.country,
    required this.temperature,
    required this.feelsLike,
    required this.description,
    required this.humidity,
    required this.windSpeed,
    required this.icon,
    required this.isRaining,
    this.hourlyForecast = const [],
    this.dailyForecast = const [],
  });
}

class HourlyForecast {
  final DateTime time;
  final double temp;
  final String description;
  final bool isRaining;

  const HourlyForecast({
    required this.time,
    required this.temp,
    required this.description,
    required this.isRaining,
  });
}

class DailyForecast {
  final DateTime date;
  final double minTemp;
  final double maxTemp;
  final String description;

  const DailyForecast({
    required this.date,
    required this.minTemp,
    required this.maxTemp,
    required this.description,
  });
}

class WeatherService {
  static const _baseUrl = 'https://api.openweathermap.org/data/2.5';
  static const _geoUrl = 'https://api.openweathermap.org/geo/1.0';

  final Dio _dio;

  WeatherService() : _dio = Dio(BaseOptions(baseUrl: _baseUrl));

  String? get _apiKey => AppConstants.openWeatherApiKey;

  // ── Type helpers ────────────────────────────────────────────────────────

  static String _s(dynamic v, [String def = '']) => (v as String?) ?? def;
  static double _d(dynamic v, [double def = 0.0]) =>
      (v as num?)?.toDouble() ?? def;
  static int _i(dynamic v, [int def = 0]) => (v as int?) ?? def;

  Future<WeatherData?> getCurrentWeather({
    double? lat,
    double? lon,
    String? city,
    String? postalCode,
    String countryCode = 'FR',
  }) async {
    final key = _apiKey;
    if (key == null || key.isEmpty) return null;

    try {
      double? latitude = lat;
      double? longitude = lon;
      String? cityName = city;

      if (city != null && latitude == null) {
        final geoData = await _geocode(city, countryCode);
        if (geoData != null) {
          latitude = _d(geoData['lat']);
          longitude = _d(geoData['lon']);
          cityName = _s(geoData['name']);
        }
      } else if (postalCode != null && latitude == null) {
        final geoData = await _geocodeByZip(postalCode, countryCode);
        if (geoData != null) {
          latitude = _d(geoData['lat']);
          longitude = _d(geoData['lon']);
          cityName = _s(geoData['name']);
        }
      }

      if (latitude == null || longitude == null) return null;

      // Get current weather
      final weatherResp =
          await _dio.get('$_baseUrl/weather', queryParameters: {
        'lat': latitude,
        'lon': longitude,
        'appid': key,
        'units': 'metric',
        'lang': 'fr',
      });

      if (weatherResp.statusCode != 200) return null;
      final w = weatherResp.data as Map<String, dynamic>;
      final desc = (w['weather'] as List?)?.cast<Map<String, dynamic>>() ?? [];
      final isRaining = desc.isNotEmpty &&
          (_s(desc[0]['main']) == 'Rain' ||
              _s(desc[0]['main']) == 'Drizzle' ||
              _s(desc[0]['main']) == 'Thunderstorm');

      // Get forecast
      final forecastResp =
          await _dio.get('$_baseUrl/forecast', queryParameters: {
        'lat': latitude,
        'lon': longitude,
        'appid': key,
        'units': 'metric',
        'lang': 'fr',
      });

      final hourly = <HourlyForecast>[];
      final daily = <DailyForecast>[];
      final seenDays = <DateTime>{};

      if (forecastResp.statusCode == 200) {
        final list = (forecastResp.data['list'] as List?)
                ?.cast<Map<String, dynamic>>() ??
            [];
        for (final item in list.take(24)) {
          final dt = DateTime.fromMillisecondsSinceEpoch(
              (_i(item['dt'])) * 1000);
          final wList = (item['weather'] as List?)
                  ?.cast<Map<String, dynamic>>() ??
              [];
          final raining = wList.isNotEmpty &&
              (_s(wList[0]['main']) == 'Rain' ||
                  _s(wList[0]['main']) == 'Drizzle');
          final main =
              item['main'] as Map<String, dynamic>? ?? {};
          hourly.add(HourlyForecast(
            time: dt,
            temp: _d(main['temp']),
            description: wList.isNotEmpty ? _s(wList[0]['description']) : '',
            isRaining: raining,
          ));

          final day = DateTime(dt.year, dt.month, dt.day);
          if (seenDays.add(day)) {
            daily.add(DailyForecast(
              date: day,
              minTemp: _d(main['temp_min']),
              maxTemp: _d(main['temp_max']),
              description:
                  wList.isNotEmpty ? _s(wList[0]['description']) : '',
            ));
          }
        }
      }

      final main = w['main'] as Map<String, dynamic>? ?? {};
      final wind = w['wind'] as Map<String, dynamic>? ?? {};
      final sys = w['sys'] as Map<String, dynamic>? ?? {};

      return WeatherData(
        city: cityName ?? _s(w['name']),
        country: _s(sys['country']),
        temperature: _d(main['temp']),
        feelsLike: _d(main['feels_like']),
        description: desc.isNotEmpty ? _s(desc[0]['description']) : '',
        humidity: _i(main['humidity']),
        windSpeed: _d(wind['speed']),
        icon: desc.isNotEmpty ? _s(desc[0]['icon'], '01d') : '01d',
        isRaining: isRaining,
        hourlyForecast: hourly,
        dailyForecast: daily,
      );
    } catch (e) {
      return null;
    }
  }

  Future<Map<String, dynamic>?> _geocode(
      String city, String countryCode) async {
    final key = _apiKey;
    if (key == null || key.isEmpty) return null;
    try {
      final resp = await _dio.get('$_geoUrl/direct', queryParameters: {
        'q': '$city,$countryCode',
        'limit': 1,
        'appid': key,
      });
      if (resp.statusCode == 200 && (resp.data as List).isNotEmpty) {
        return (resp.data as List)[0] as Map<String, dynamic>;
      }
    } catch (_) {}
    return null;
  }

  Future<Map<String, dynamic>?> _geocodeByZip(
      String zip, String countryCode) async {
    final key = _apiKey;
    if (key == null || key.isEmpty) return null;
    try {
      final resp = await _dio.get('$_geoUrl/zip', queryParameters: {
        'zip': '$zip,$countryCode',
        'appid': key,
      });
      if (resp.statusCode == 200 && resp.data != null) {
        return resp.data as Map<String, dynamic>;
      }
    } catch (_) {}
    return null;
  }

  /// Format weather as readable markdown for chat display
  static String formatMarkdown(WeatherData w) {
    final rainText =
        w.isRaining ? '🌧️ **Pluie attendue**' : '☀️ Pas de pluie';
    final buf = StringBuffer();
    buf.writeln('## 🌤️ Météo — ${w.city}, ${w.country}');
    buf.writeln();
    buf.writeln('| Info | Valeur |');
    buf.writeln('|------|--------|');
    buf.writeln(
        '| 🌡️ Température | **${w.temperature.round()}°C** (ressenti ${w.feelsLike.round()}°C) |');
    buf.writeln('| 📝 Conditions | ${w.description} |');
    buf.writeln('| 💧 Humidité | ${w.humidity}% |');
    buf.writeln('| 💨 Vent | ${w.windSpeed.toStringAsFixed(1)} km/h |');
    buf.writeln('| 🌧️ Pluie | $rainText |');

    if (w.hourlyForecast.isNotEmpty) {
      buf.writeln();
      buf.writeln('### Prévisions horaires (24h)');
      buf.writeln('| Heure | Temp | Conditions |');
      buf.writeln('|-------|------|------------|');
      for (final h in w.hourlyForecast.take(12)) {
        final hour = '${h.time.hour.toString().padLeft(2, '0')}h';
        final rain = h.isRaining ? ' 🌧️' : '';
        buf.writeln('| $hour | ${h.temp.round()}°C | ${h.description}$rain |');
      }
    }

    if (w.dailyForecast.isNotEmpty) {
      buf.writeln();
      buf.writeln('### Prévisions journalières');
      buf.writeln('| Jour | Min | Max | Conditions |');
      buf.writeln('|------|-----|-----|------------|');
      for (final d in w.dailyForecast.take(5)) {
        const dayNames = [
          'Dim', 'Lun', 'Mar', 'Mer', 'Jeu', 'Ven', 'Sam'
        ];
        final day =
            '${dayNames[d.date.weekday % 7]} ${d.date.day}/${d.date.month}';
        buf.writeln(
            '| $day | ${d.minTemp.round()}°C | ${d.maxTemp.round()}°C | ${d.description} |');
      }
    }

    return buf.toString();
  }
}
