import 'dart:async';
import 'package:flutter/material.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:intl/intl.dart';
import 'package:logger/logger.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../utils/responsive.dart';
import '../../utils/loading_delay.dart';
import 'weather_service.dart';

class WeatherOceanAlertsScreen extends StatefulWidget {
  const WeatherOceanAlertsScreen({super.key});

  @override
  State<WeatherOceanAlertsScreen> createState() =>
      _WeatherOceanAlertsScreenState();
}

class _WeatherOceanAlertsScreenState extends State<WeatherOceanAlertsScreen>
    with WidgetsBindingObserver {
  static const Color _pageTop = Color(0xFFDFF1FF);
  static const Color _pageBottom = Color(0xFFF7FCFF);
  static const Color _ink = Color(0xFF102A43);
  static const Color _mutedInk = Color(0xFF4E667D);
  static const Color _heroStart = Color(0xFF0E4D7A);
  static const Color _heroEnd = Color(0xFF1A7DA0);
  static const Duration _weatherRefreshInterval = Duration(minutes: 10);

  final Logger _log = Logger(printer: PrettyPrinter(methodCount: 0));
  List<Map<String, dynamic>> _weatherData = [];
  bool _loading = true;
  Position? _currentPosition;
  String _locationName = 'Fetching location...';
  final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();
  bool _localNotificationsReady = false;
  bool _hasAutoNotifiedOnOpen = false;
  Timer? _weatherRefreshTimer;
  bool _weatherRefreshInFlight = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initLocalNotifications();
    _getLocation();
    _startWeatherAutoRefresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _weatherRefreshTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _refreshWeatherSilently();
    }
  }

  void _startWeatherAutoRefresh() {
    _weatherRefreshTimer?.cancel();
    _weatherRefreshTimer = Timer.periodic(_weatherRefreshInterval, (_) {
      _refreshWeatherSilently();
    });
  }

  Future<void> _refreshWeatherSilently() async {
    if (_weatherRefreshInFlight) return;
    _weatherRefreshInFlight = true;
    try {
      await _loadWeather(showLoader: false);
    } finally {
      _weatherRefreshInFlight = false;
    }
  }

  Future<void> _initLocalNotifications() async {
    try {
      const initSettings = InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      );
      await _localNotifications.initialize(initSettings);
      _localNotificationsReady = true;
    } catch (e) {
      _log.w('Local notification init failed: $e');
    }
  }

  Future<void> _getLocation() async {
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        setState(() => _locationName = 'Location services disabled');
        await _loadWeather();
        return;
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          setState(() => _locationName = 'Location permission denied');
          await _loadWeather();
          return;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        setState(
          () => _locationName = 'Location permission permanently denied',
        );
        await _loadWeather();
        return;
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      );
      final placemarks = await placemarkFromCoordinates(
        position.latitude,
        position.longitude,
      );
      String locationName = 'Unknown location';
      if (placemarks.isNotEmpty) {
        final place = placemarks.first;
        locationName =
            '${place.locality ?? ''}, ${place.administrativeArea ?? ''}'.trim();
        if (locationName.startsWith(', ')) {
          locationName = locationName.substring(2);
        }
        if (locationName.endsWith(', ')) {
          locationName = locationName.substring(0, locationName.length - 2);
        }
        if (locationName.isEmpty) locationName = place.country ?? 'Unknown';
      }

      setState(() {
        _currentPosition = position;
        _locationName = locationName;
      });

      await _loadWeather();
    } catch (e) {
      _log.e('Error getting location', error: e);
      setState(() => _locationName = 'Error fetching location');
      await _loadWeather();
    }
  }

  Future<void> _loadWeather({bool showLoader = true}) async {
    final hadData = _weatherData.isNotEmpty;
    final shouldShowLoader = mounted && (showLoader || !hadData);
    if (shouldShowLoader) {
      setState(() => _loading = true);
    }
    try {
      final weatherService = WeatherService();
      final dataFuture = weatherService.fetchHourlyForecast(
        lat: _currentPosition?.latitude ?? 16.0431,
        lon: _currentPosition?.longitude ?? 120.3333,
      );
      final data = shouldShowLoader
          ? await withMinimumLoadingTime(dataFuture)
          : await dataFuture;
      if (!mounted) return;
      setState(() {
        _weatherData = data;
        _loading = false;
      });
      if (!_hasAutoNotifiedOnOpen) {
        _hasAutoNotifiedOnOpen = true;
        await _maybeNotifyWeatherChange(force: true);
      } else {
        await _maybeNotifyWeatherChange();
      }
    } catch (e) {
      _log.e('Error loading weather data', error: e);
      if (!mounted) return;
      setState(() {
        _loading = false;
        if (!hadData) {
          _weatherData = [];
        }
      });
    }
  }

  IconData _getWeatherIcon(String iconCode) {
    switch (iconCode) {
      case '01d':
      case '01n':
        return Icons.wb_sunny;
      case '02d':
      case '02n':
      case '03d':
      case '03n':
      case '04d':
      case '04n':
        return Icons.cloud;
      case '09d':
      case '09n':
      case '10d':
      case '10n':
        return Icons.umbrella;
      case '11d':
      case '11n':
        return Icons.flash_on;
      case '13d':
      case '13n':
        return Icons.ac_unit;
      default:
        return Icons.help_outline;
    }
  }

  /// Returns a widget that respects API icon URLs (https://...) or falls back to a Material icon code.
  Widget _buildWeatherIconWidget(
    String icon, {
    double size = 70,
    Color color = Colors.amber,
  }) {
    if (icon.startsWith('http')) {
      return Image.network(
        icon,
        width: size,
        height: size,
        errorBuilder: (_, __, ___) =>
            Icon(_getWeatherIcon(icon), color: color, size: size),
      );
    }
    return Icon(_getWeatherIcon(icon), color: color, size: size);
  }

  num _toNum(dynamic value) {
    if (value is num) return value;
    if (value is String) {
      final parsed = double.tryParse(
        value.replaceAll(RegExp('[^0-9\\.-]'), ''),
      );
      if (parsed != null) return parsed;
    }
    return 0;
  }

  String _tempText(dynamic val) => '${_toNum(val).round()}\u00B0C';

  String _withUnit(dynamic val, String unit) {
    if (val == null) return '--';
    final raw = val.toString().trim();
    if (raw.isEmpty) return '--';
    final numeric = double.tryParse(raw.replaceAll(RegExp('[^0-9\\.-]'), ''));
    if (numeric != null) {
      return numeric == numeric.roundToDouble()
          ? '${numeric.toInt()} $unit'
          : '${numeric.toStringAsFixed(1)} $unit';
    }
    return '$raw $unit';
  }

  double _parseDouble(dynamic val) {
    if (val is num) return val.toDouble();
    if (val is String) {
      final cleaned = val.replaceAll(RegExp('[^0-9\\.-]'), '');
      final parsed = double.tryParse(cleaned);
      if (parsed != null) return parsed;
    }
    return double.nan;
  }

  bool _isSafeToFish(Map<String, dynamic>? weather) {
    if (weather == null) return true;
    final wind = _parseDouble(weather['wind']);
    final humidity = _parseDouble(weather['humidity']);
    final visibility = _parseDouble(weather['visibility']);

    final windOk = wind.isNaN ? true : wind <= 20;
    final humidityOk = humidity.isNaN ? true : humidity <= 85;
    final visibilityOk = visibility.isNaN ? true : visibility >= 5;

    return windOk && humidityOk && visibilityOk;
  }

  /// Returns (label, color, textColor) for the safety chip based on an item in _weatherData.
  (String, Color, Color) _safetyStatusForIndex(int index) {
    if (_weatherData.length > index) {
      final safe = _isSafeToFish(_weatherData[index]);
      return safe
          ? ('Safe to fish', Colors.green.shade500, Colors.white)
          : ('No fishing', Colors.red, Colors.white);
    }
    return ('Moderate', Colors.amber.shade400, Colors.black87);
  }

  String _formatDate(Map<String, dynamic>? entry) {
    final raw = entry?['rawTime'];
    DateTime dt;
    if (raw is DateTime) {
      dt = raw;
    } else {
      dt = DateTime.now();
    }
    return DateFormat('MMMM dd, yyyy').format(dt);
  }

  String _dayLabel(Map<String, dynamic> day, int index) {
    final raw = day['rawTime'];
    if (index == 0 && raw is DateTime) return 'Today';
    if (raw is DateTime) return DateFormat('EEE').format(raw);
    if (day['day'] != null) return day['day'].toString();
    return index == 0 ? 'Today' : 'Day ${index + 1}';
  }

  String _waveRange(double windKph) {
    if (windKph.isNaN) return '--';
    if (windKph >= 35) return '3-5 m';
    if (windKph >= 20) return '1.5-4 m';
    return '0.6-2.5 m';
  }

  String _galeStatus(double windKph) {
    if (windKph.isNaN) return '--';
    if (windKph >= 35) return 'Gale';
    if (windKph >= 20) return 'Strong Breeze';
    return 'Light-Moderate';
  }

  String _coastalWaterText(double windKph) {
    if (windKph.isNaN) return '--';
    if (windKph >= 35) return 'Rough-Very Rough';
    if (windKph >= 20) return 'Moderate-Rough';
    return 'Slight-Moderate';
  }

  String _highTideLabel(DateTime now) => 'Today';

  String _lowTideLabel(DateTime now) => 'Tomorrow';

  String _highTideTime(DateTime now) {
    final dt = DateTime(now.year, now.month, now.day, 15, 45);
    return DateFormat('h:mm a').format(dt);
  }

  String _lowTideTime(DateTime now) {
    final dt = DateTime(
      now.year,
      now.month,
      now.day,
      9,
      25,
    ).add(const Duration(days: 1));
    return DateFormat('h:mm a').format(dt);
  }

  ({
    String message,
    String windText,
    String wavesText,
    String galeText,
    String coastalText,
    String highTideLabel,
    String highTideTime,
    String lowTideLabel,
    String lowTideTime,
    bool isSafe,
    String fishingLine,
    String desc,
  })
  _buildWeatherAlertDetails(Map<String, dynamic> current, DateTime now) {
    final windText = _withUnit(current['wind'], 'km/h');
    final windValue = _parseDouble(current['wind']);
    final wavesText = _waveRange(windValue);
    final galeText = _galeStatus(windValue);
    final coastalText = _coastalWaterText(windValue);
    final desc = (current['desc'] ?? 'Weather update').toString();
    final highTideTime = _highTideTime(now);
    final lowTideTime = _lowTideTime(now);
    final highTideLabel = _highTideLabel(now);
    final lowTideLabel = _lowTideLabel(now);
    final isSafe = _isSafeToFish(current);
    final fishingLine = isSafe
        ? 'Safe to fish.'
        : 'No fishing here due to current conditions.';

    final message =
        'High tide $highTideLabel at $highTideTime. Low tide $lowTideLabel at $lowTideTime. $desc. Wind $windText, Waves $wavesText, Gale $galeText. $fishingLine';

    return (
      message: message,
      windText: windText,
      wavesText: wavesText,
      galeText: galeText,
      coastalText: coastalText,
      highTideLabel: highTideLabel,
      highTideTime: highTideTime,
      lowTideLabel: lowTideLabel,
      lowTideTime: lowTideTime,
      isSafe: isSafe,
      fishingLine: fishingLine,
      desc: desc,
    );
  }

  Future<void> _maybeNotifyWeatherChange({bool force = false}) async {
    if (!mounted || _weatherData.isEmpty) return;
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final now = DateTime.now();
    final current = _weatherData.first;
    final details = _buildWeatherAlertDetails(current, now);

    final signature = [
      _locationName,
      details.desc,
      details.windText,
      details.wavesText,
      details.galeText,
      details.coastalText,
      details.highTideTime,
      details.lowTideTime,
      details.isSafe ? 'safe' : 'no_fishing',
    ].join('|');

    final prefs = await SharedPreferences.getInstance();
    final last = prefs.getString('last_weather_signature');
    if (!force && last == signature) return;
    await prefs.setString('last_weather_signature', signature);

    try {
      await FirebaseFirestore.instance.collection('notifications').add({
        'targetUserId': user.uid,
        'title': 'Weather & Ocean Alert',
        'message': details.message,
        'category': 'weather',
        'type': 'weather_alert',
        'timestamp': FieldValue.serverTimestamp(),
        'isRead': false,
        'location': _locationName,
        'highTide': '${details.highTideLabel} ${details.highTideTime}',
        'lowTide': '${details.lowTideLabel} ${details.lowTideTime}',
        'fishingStatus': details.isSafe ? 'safe' : 'no_fishing',
        'fishingMessage': details.fishingLine,
      });
    } catch (e) {
      _log.w('Firestore weather notification failed: $e');
    }

    await _showLocalWeatherNotification(
      title: 'Weather & Ocean Alert',
      body: details.message,
    );
  }

  Future<void> _showLocalWeatherNotification({
    required String title,
    required String body,
  }) async {
    if (!_localNotificationsReady) return;
    try {
      await _localNotifications.show(
        DateTime.now().millisecondsSinceEpoch ~/ 1000,
        title,
        body,
        const NotificationDetails(
          android: AndroidNotificationDetails(
            'default_channel',
            'General Notifications',
            channelDescription: 'Default channel for general notifications.',
            importance: Importance.high,
            priority: Priority.high,
            icon: '@mipmap/ic_launcher',
          ),
        ),
      );
    } catch (e) {
      _log.w('Local weather notification failed: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final padding = Responsive.pagePadding(context);
    final maxWidth = Responsive.maxContentWidth(context);
    final width = MediaQuery.of(context).size.width;
    final metricColumns = width >= 900 ? 4 : 2;
    final now = DateTime.now();
    final currentWeather = _weatherData.isNotEmpty ? _weatherData[0] : null;

    final currentTemp = _tempText(currentWeather?['temp'] ?? 28);
    final currentDesc = (currentWeather?['desc'] as String?)?.isNotEmpty == true
        ? currentWeather!['desc'] as String
        : 'Sunny';
    final currentIcon = currentWeather?['icon'] as String? ?? '01d';
    final dateText = _formatDate(currentWeather);
    final windText = _withUnit(currentWeather?['wind'], 'km/h');
    final humidityText = _withUnit(currentWeather?['humidity'], '%');
    final feelsLikeText = _tempText(
      currentWeather?['feelslike'] ?? currentWeather?['temp'] ?? 28,
    );
    final visibilityText = _withUnit(currentWeather?['visibility'], 'km');
    final windValue = _parseDouble(currentWeather?['wind']);
    final wavesText = _waveRange(windValue);
    final galeText = _galeStatus(windValue);
    final coastalText = _coastalWaterText(windValue);
    final safetyToday = _safetyStatusForIndex(0);
    final safetyTomorrow = _safetyStatusForIndex(
      _weatherData.length > 1 ? 1 : 0,
    );
    final safetyLater = _safetyStatusForIndex(
      _weatherData.length > 2 ? 2 : 0,
    );
    final isSafeNow = _isSafeToFish(currentWeather);

    final metrics = <_MetricData>[
      _MetricData(
        icon: Icons.air_rounded,
        label: 'Wind',
        value: windText,
        accent: const Color(0xFF2F74B5),
      ),
      _MetricData(
        icon: Icons.water_drop_rounded,
        label: 'Humidity',
        value: humidityText,
        accent: const Color(0xFF2A8F7A),
      ),
      _MetricData(
        icon: Icons.device_thermostat_rounded,
        label: 'Feels Like',
        value: feelsLikeText,
        accent: const Color(0xFFE17832),
      ),
      _MetricData(
        icon: Icons.visibility_rounded,
        label: 'Visibility',
        value: visibilityText,
        accent: const Color(0xFF596AC9),
      ),
    ];

    return Scaffold(
      backgroundColor: _pageBottom,
      appBar: AppBar(
        title: const Text(
          'Weather & Ocean Alerts',
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w800,
            color: _ink,
          ),
        ),
        centerTitle: false,
        titleSpacing: 0,
        backgroundColor: Colors.transparent,
        foregroundColor: _ink,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        actions: [
          IconButton(
            onPressed: _loading ? null : _loadWeather,
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Refresh weather',
          ),
        ],
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [_pageTop, _pageBottom],
          ),
        ),
        child: SafeArea(
          top: false,
          child: Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: maxWidth),
              child: _loading
                  ? const _LoadingWeatherCard()
                  : SingleChildScrollView(
                      padding: EdgeInsets.fromLTRB(
                        padding,
                        padding * 0.4,
                        padding,
                        padding,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.fromLTRB(18, 18, 18, 20),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(26),
                              gradient: const LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: [_heroStart, _heroEnd],
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: const Color(
                                    0xFF0E4D7A,
                                  ).withOpacity(0.24),
                                  blurRadius: 26,
                                  offset: const Offset(0, 12),
                                ),
                              ],
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 8,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withOpacity(0.18),
                                    borderRadius: BorderRadius.circular(999),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(
                                        Icons.location_on_rounded,
                                        size: 16,
                                        color: Colors.white,
                                      ),
                                      const SizedBox(width: 5),
                                      Flexible(
                                        child: Text(
                                          _locationName,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 13.5,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 18),
                                Row(
                                  children: [
                                    Container(
                                      width: 72,
                                      height: 72,
                                      decoration: BoxDecoration(
                                        color: Colors.white.withOpacity(0.15),
                                        borderRadius: BorderRadius.circular(20),
                                      ),
                                      child: Center(
                                        child: _buildWeatherIconWidget(
                                          currentIcon,
                                          size: 50,
                                          color: const Color(0xFFFFDE6A),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 14),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            currentTemp,
                                            style: const TextStyle(
                                              fontSize: 38,
                                              height: 1.0,
                                              fontWeight: FontWeight.w800,
                                              color: Colors.white,
                                            ),
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            currentDesc,
                                            style: const TextStyle(
                                              fontSize: 15.5,
                                              color: Colors.white,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            dateText,
                                            style: TextStyle(
                                              fontSize: 13.4,
                                              color: Colors.white.withOpacity(
                                                0.88,
                                              ),
                                              fontWeight: FontWeight.w500,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          SizedBox(
                            height: Responsive.verticalSpace(context) + 2,
                          ),
                          const Text(
                            'Marine Conditions',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                              color: _ink,
                            ),
                          ),
                          const SizedBox(height: 10),
                          GridView.builder(
                            itemCount: metrics.length,
                            physics: const NeverScrollableScrollPhysics(),
                            shrinkWrap: true,
                            gridDelegate:
                                SliverGridDelegateWithFixedCrossAxisCount(
                                  crossAxisCount: metricColumns,
                                  crossAxisSpacing: 12,
                                  mainAxisSpacing: 12,
                                  mainAxisExtent: 96,
                                ),
                            itemBuilder: (context, index) {
                              final metric = metrics[index];
                              return _InfoCard(metric: metric);
                            },
                          ),
                          SizedBox(height: Responsive.verticalSpace(context)),
                          _oceanAdvisoryCard(
                            wavesText: wavesText,
                            galeText: galeText,
                            coastalText: coastalText,
                            isSafeNow: isSafeNow,
                          ),
                          SizedBox(height: Responsive.verticalSpace(context)),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.94),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: const Color(0xFFD4E5F5),
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Fishing Safety Indicator',
                                  style: TextStyle(
                                    fontSize: 17,
                                    fontWeight: FontWeight.w800,
                                    color: _ink,
                                  ),
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  isSafeNow
                                      ? 'Current conditions are favorable for fishing.'
                                      : 'Current conditions are risky for fishing activity.',
                                  style: const TextStyle(
                                    fontSize: 13.5,
                                    color: _mutedInk,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                const SizedBox(height: 12),
                                _safetyRow(
                                  'Today',
                                  safetyToday.$1,
                                  safetyToday.$2,
                                  textColor: safetyToday.$3,
                                ),
                                const SizedBox(height: 9),
                                _safetyRow(
                                  'Tomorrow',
                                  safetyTomorrow.$1,
                                  safetyTomorrow.$2,
                                  textColor: safetyTomorrow.$3,
                                ),
                                const SizedBox(height: 9),
                                _safetyRow(
                                  'Later',
                                  safetyLater.$1,
                                  safetyLater.$2,
                                  textColor: safetyLater.$3,
                                ),
                              ],
                            ),
                          ),
                          SizedBox(height: Responsive.verticalSpace(context)),
                          Row(
                            children: [
                              Expanded(
                                child: _pillBox(
                                  title: 'High Tide',
                                  value: _highTideLabel(now),
                                  time: _highTideTime(now),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: _pillBox(
                                  title: 'Low Tide',
                                  value: _lowTideLabel(now),
                                  time: _lowTideTime(now),
                                ),
                              ),
                            ],
                          ),
                          SizedBox(height: Responsive.verticalSpace(context)),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.fromLTRB(16, 16, 16, 10),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.95),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: const Color(0xFFD4E5F5),
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Weather Outlook',
                                  style: TextStyle(
                                    fontSize: 17,
                                    fontWeight: FontWeight.w800,
                                    color: _ink,
                                  ),
                                ),
                                const SizedBox(height: 12),
                                ..._weatherData
                                    .take(7)
                                    .toList()
                                    .asMap()
                                    .entries
                                    .map((entry) {
                                      final idx = entry.key;
                                      final day = entry.value;
                                      final label = _dayLabel(day, idx);
                                      final cond =
                                          (day['desc'] as String?)
                                                  ?.isNotEmpty ==
                                              true
                                          ? day['desc'] as String
                                          : 'N/A';
                                      final tempVal = _toNum(day['temp']);
                                      final hi = tempVal.round();
                                      final lo = (tempVal - 2).round();
                                      return Padding(
                                        padding: const EdgeInsets.only(
                                          bottom: 8,
                                        ),
                                        child: _WeatherRow(
                                          iconWidget: _buildWeatherIconWidget(
                                            day['icon'] as String? ?? '',
                                            size: 24,
                                            color: const Color(0xFF2C4A6A),
                                          ),
                                          label: label,
                                          condition: cond,
                                          tempHigh: hi,
                                          tempLow: lo,
                                        ),
                                      );
                                    }),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _safetyRow(
    String label,
    String status,
    Color color, {
    Color textColor = Colors.white,
  }) {
    final statusColor = color;
    final isSafe = status.toLowerCase().contains('safe');
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: statusColor.withOpacity(0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: statusColor.withOpacity(0.24)),
      ),
      child: Row(
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: statusColor,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              isSafe ? Icons.check_rounded : Icons.close_rounded,
              color: textColor,
              size: 17,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 14,
                color: _ink,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
            decoration: BoxDecoration(
              color: statusColor,
              borderRadius: BorderRadius.circular(999),
              boxShadow: [
                BoxShadow(
                  color: statusColor.withOpacity(0.22),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Text(
              status,
              style: TextStyle(
                color: textColor,
                fontWeight: FontWeight.w700,
                fontSize: 12.8,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _oceanAdvisoryCard({
    required String wavesText,
    required String galeText,
    required String coastalText,
    required bool isSafeNow,
  }) {
    final statusColor = isSafeNow
        ? const Color(0xFF21A55B)
        : const Color(0xFFE23D34);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.96),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFD4E5F5)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0E4D7A).withOpacity(0.08),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: const Color(0xFFE8F6FF),
                  borderRadius: BorderRadius.circular(13),
                ),
                child: const Icon(
                  Icons.sailing_rounded,
                  color: Color(0xFF0E6D93),
                  size: 21,
                ),
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Ocean Advisory',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        color: _ink,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'Near-shore conditions for small vessels',
                      style: TextStyle(
                        fontSize: 12.5,
                        color: _mutedInk,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: statusColor.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  isSafeNow ? 'Clear' : 'Caution',
                  style: TextStyle(
                    color: statusColor,
                    fontSize: 12.2,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _marineFact(
                  icon: Icons.waves_rounded,
                  label: 'Waves',
                  value: wavesText,
                  accent: const Color(0xFF2771A7),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _marineFact(
                  icon: Icons.warning_amber_rounded,
                  label: 'Gale',
                  value: galeText,
                  accent: const Color(0xFFCC6A1C),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _marineFact(
            icon: Icons.water_rounded,
            label: 'Coastal Water',
            value: coastalText,
            accent: const Color(0xFF21648A),
            wide: true,
          ),
        ],
      ),
    );
  }

  Widget _marineFact({
    required IconData icon,
    required String label,
    required String value,
    required Color accent,
    bool wide = false,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
      decoration: BoxDecoration(
        color: accent.withOpacity(0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: accent.withOpacity(0.16)),
      ),
      child: Row(
        children: [
          Icon(icon, color: accent, size: 20),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    color: _mutedInk,
                    fontSize: 12.2,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: TextStyle(
                    color: wide ? _ink : accent,
                    fontSize: wide ? 15.5 : 14.5,
                    fontWeight: FontWeight.w800,
                    height: 1.1,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _pillBox({
    required String title,
    required String value,
    required String time,
  }) {
    return Container(
      width: 150,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFEBF7FF), Color(0xFFDDEFFF)],
        ),
        border: Border.all(color: const Color(0xFFBBD8EE)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 14.2,
              color: _ink,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(
              fontSize: 12.2,
              color: _mutedInk,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 1),
          Text(
            time,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: _ink,
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  final _MetricData metric;

  const _InfoCard({required this.metric});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.95),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFD3E4F4)),
        boxShadow: [
          BoxShadow(
            color: metric.accent.withOpacity(0.12),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
            children: [
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: metric.accent.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Icon(metric.icon, size: 17, color: metric.accent),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  metric.label,
                  style: const TextStyle(
                    fontSize: 12.8,
                    color: _WeatherOceanAlertsScreenState._mutedInk,
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 9),
          Text(
            metric.value,
            style: const TextStyle(
              fontSize: 16.3,
              fontWeight: FontWeight.w800,
              color: _WeatherOceanAlertsScreenState._ink,
              height: 1.05,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

class _WeatherRow extends StatelessWidget {
  final Widget iconWidget;
  final String label;
  final String condition;
  final int tempHigh;
  final int tempLow;

  const _WeatherRow({
    required this.iconWidget,
    required this.label,
    required this.condition,
    required this.tempHigh,
    required this.tempLow,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      decoration: BoxDecoration(
        color: const Color(0xFFF3FAFF),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFD6E8F6)),
      ),
      child: Row(
        children: [
          iconWidget,
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 13.6,
                    fontWeight: FontWeight.w700,
                    color: _WeatherOceanAlertsScreenState._ink,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  condition,
                  style: const TextStyle(
                    fontSize: 12.2,
                    color: _WeatherOceanAlertsScreenState._mutedInk,
                    fontWeight: FontWeight.w500,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '$tempHigh°C / $tempLow°C',
            style: const TextStyle(
              fontWeight: FontWeight.w800,
              color: _WeatherOceanAlertsScreenState._ink,
            ),
          ),
        ],
      ),
    );
  }
}

class _MetricData {
  final IconData icon;
  final String label;
  final String value;
  final Color accent;

  const _MetricData({
    required this.icon,
    required this.label,
    required this.value,
    required this.accent,
  });
}

class _LoadingWeatherCard extends StatelessWidget {
  const _LoadingWeatherCard();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: 170,
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 22),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.95),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0xFFD4E5F5)),
        ),
        child: const Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 26,
              height: 26,
              child: CircularProgressIndicator(strokeWidth: 2.2),
            ),
            SizedBox(height: 10),
            Text(
              'Loading weather...',
              style: TextStyle(
                fontSize: 13.2,
                color: _WeatherOceanAlertsScreenState._mutedInk,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
