import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';

class WeatherService {
  final _client = http.Client();
  final String _apiKey = 'c3546aea86ac4befa4b101500252307';

  Future<http.Response> _getWithRetry(Uri url) async {
    const maxAttempts = 3;
    http.Response? response;
    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      try {
        response = await _client.get(url).timeout(const Duration(seconds: 10));
        return response;
      } on TimeoutException catch (_) {
        if (attempt == maxAttempts) rethrow;
        await Future.delayed(Duration(milliseconds: 300 * attempt));
      } on SocketException catch (_) {
        if (attempt == maxAttempts) rethrow;
        await Future.delayed(Duration(milliseconds: 300 * attempt));
      }
    }
    throw Exception('Failed to fetch weather data after $maxAttempts attempts');
  }

  List<Map<String, dynamic>> _fallbackForecast() {
    final now = DateTime.now();
    return List.generate(4, (i) {
      final t = now.add(Duration(hours: i));
      final icon = i == 0
          ? '01d'
          : i == 1
              ? '02d'
              : i == 2
                  ? '03d'
                  : '04d';
      return {
        'time': i == 0 ? 'Now' : DateFormat.Hm().format(t),
        'date': DateFormat('MMM d').format(t),
        'rawTime': t,
        'icon': icon,
        'temp': '27\u00B0C',
        'desc': 'Cloudy',
        'fallback': true,
        'wind': '12',
        'humidity': '68',
        'feelslike': '28',
        'visibility': '10',
      };
    });
  }
  Future<List<Map<String, dynamic>>> fetchHourlyForecast({
    required double lat,
    required double lon,
  }) async {
    final q = '$lat,$lon';
    final url = Uri.parse(
      'https://api.weatherapi.com/v1/forecast.json?key=$_apiKey&q=$q&days=5&aqi=no&alerts=no',
    );

    try {
      final response = await _getWithRetry(url);
      if (response.statusCode != 200) {
        final body = response.body.isNotEmpty ? response.body : 'Empty response';
        throw Exception('Failed to fetch weather data (status ${response.statusCode}): $body');
      }

      final Map<String, dynamic> jsonBody = jsonDecode(response.body) as Map<String, dynamic>;
      final forecast = jsonBody['forecast']?['forecastday'] as List<dynamic>?;
      final current = jsonBody['current'] as Map<String, dynamic>?;
      final location = jsonBody['location'] as Map<String, dynamic>?;
      if (forecast == null || forecast.isEmpty || current == null) {
        throw Exception('Weather response missing current or forecastday');
      }

      DateTime currentTime;
      try {
        currentTime = DateTime.parse(
          (location?['localtime'] ?? '').toString(),
        ).toLocal();
      } catch (_) {
        currentTime = DateTime.now();
      }

      Map<String, dynamic> _entryFromParts({
        required DateTime time,
        required dynamic tempValue,
        required dynamic windValue,
        required dynamic humidityValue,
        required dynamic feelsLikeValue,
        required dynamic visibilityValue,
        required Map<String, dynamic>? condition,
        String? timeLabel,
      }) {
        final conditionMap = condition ?? const <String, dynamic>{};
        final iconRaw = (conditionMap['icon'] ?? '').toString();
        final iconUrl = iconRaw.isNotEmpty
            ? (iconRaw.startsWith('http') ? iconRaw : 'https:$iconRaw')
            : '';
        final temp = tempValue != null
            ? '${(tempValue as num).round()}\u00B0C'
            : '--';
        return {
          'time': timeLabel ?? DateFormat.Hm().format(time),
          'date': DateFormat('MMM d').format(time),
          'rawTime': time,
          'icon': iconUrl.isNotEmpty ? iconUrl : '01d',
          'temp': temp,
          'desc': (conditionMap['text'] ?? '').toString(),
          'wind': windValue?.toString() ?? '',
          'humidity': humidityValue?.toString() ?? '',
          'feelslike': feelsLikeValue?.toString() ?? '',
          'visibility': visibilityValue?.toString() ?? '',
        };
      }

      final result = <Map<String, dynamic>>[
        _entryFromParts(
          time: currentTime,
          timeLabel: 'Now',
          tempValue: current['temp_c'],
          windValue: current['wind_kph'],
          humidityValue: current['humidity'],
          feelsLikeValue: current['feelslike_c'],
          visibilityValue: current['vis_km'],
          condition: current['condition'] as Map<String, dynamic>?,
        ),
      ];

      for (final day in forecast.skip(1)) {
        final dayMap = day as Map<String, dynamic>;
        final dayInfo = dayMap['day'] as Map<String, dynamic>? ?? {};
        DateTime time;
        try {
          time = DateTime.parse((dayMap['date'] ?? '').toString()).toLocal();
        } catch (_) {
          time = currentTime;
        }

        result.add(
          _entryFromParts(
            time: time,
            tempValue: dayInfo['avgtemp_c'] ?? dayInfo['maxtemp_c'],
            windValue: dayInfo['maxwind_kph'],
            humidityValue: dayInfo['avghumidity'],
            feelsLikeValue: dayInfo['avgtemp_c'],
            visibilityValue: dayInfo['avgvis_km'],
            condition: dayInfo['condition'] as Map<String, dynamic>?,
          ),
        );
      }

      if (result.isEmpty) {
        return _fallbackForecast();
      }
      return result;
    } catch (_) {
      return _fallbackForecast();
    }
  }
}
