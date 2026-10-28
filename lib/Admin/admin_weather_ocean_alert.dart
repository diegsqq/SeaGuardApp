import 'dart:async';
import 'package:flutter/material.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:intl/intl.dart';
import 'package:logger/logger.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import '../utils/responsive.dart';
import '../utils/loading_delay.dart';
import '../screens/dashboard/weather_service.dart';

class AdminWeatherOceanAlerts extends StatefulWidget {
  const AdminWeatherOceanAlerts({super.key});

  @override
  State<AdminWeatherOceanAlerts> createState() => _AdminWeatherOceanAlertsState();
}

class _AdminWeatherOceanAlertsState extends State<AdminWeatherOceanAlerts> {
  static const Color _pageTop = Color(0xFFE4F5FF);
  static const Color _pageBottom = Color(0xFFF8FCFF);
  static const Color _ink = Color(0xFF102A43);
  static const Color _mutedInk = Color(0xFF52697E);
  static const Color _heroStart = Color(0xFF125D88);
  static const Color _heroEnd = Color(0xFF178AA4);

  final Logger _log = Logger(printer: PrettyPrinter(methodCount: 0));
  List<Map<String, dynamic>> _weatherData = [];
  List<Map<String, dynamic>> _dailyWeather = [];
  bool _loading = true;
  Position? _currentPosition;
  String _locationName = 'Fetching location...';
  Timer? _weatherTimer;
  bool _pushing = false;
  static const String _signatureKey = 'admin_weather_signature';
  final FlutterLocalNotificationsPlugin _localNotifications = FlutterLocalNotificationsPlugin();
  bool _localReady = false;

  @override
  void initState() {
    super.initState();
    _initLocalNotifications();
    _getLocation();
  }

  @override
  void dispose() {
    _weatherTimer?.cancel();
    super.dispose();
  }

  Future<void> _initLocalNotifications() async {
    try {
      const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
      const initSettings = InitializationSettings(android: androidInit);
      await _localNotifications.initialize(initSettings);
      _localReady = true;
    } catch (e) {
      _log.w('Admin local notification init failed: $e');
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

      if (permission == LocationPermission.deniedForever || permission == LocationPermission.unableToDetermine) {
        setState(() => _locationName = 'Location permission permanently denied');
        await Geolocator.openAppSettings();
        await _loadWeather();
        return;
      }

      Position? position;
      try {
        position = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.high,
            timeLimit: Duration(seconds: 20),
          ),
        ).timeout(const Duration(seconds: 25));
      } on TimeoutException {
        _log.w('Location timeout, trying last known');
        position = await Geolocator.getLastKnownPosition();
      } catch (e) {
        _log.w('Location error, trying last known: $e');
        position = await Geolocator.getLastKnownPosition();
      }

      if (position == null) {
        setState(() => _locationName = 'Unable to get location. Using default.');
        await _loadWeather();
        return;
      }

      String locationName = '${position.latitude.toStringAsFixed(5)}, ${position.longitude.toStringAsFixed(5)}';
      try {
        final placemarks = await placemarkFromCoordinates(position.latitude, position.longitude);
        if (placemarks.isNotEmpty) {
          final place = placemarks.first;
          final name = '${place.locality ?? ''}, ${place.administrativeArea ?? ''}'.trim();
          if (name.isNotEmpty && name != ',') {
            locationName = name.replaceAll(RegExp(r'^,\\s*'), '').replaceAll(RegExp(r',\\s*\$'), '');
          } else if (place.country != null && place.country!.isNotEmpty) {
            locationName = place.country!;
          }
        }
      } catch (e) {
        _log.w('Reverse geocoding failed: $e');
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

  Future<void> _loadWeather() async {
    setState(() => _loading = true);
    try {
      final weatherService = WeatherService();
      final data = await withMinimumLoadingTime(
        weatherService
          .fetchHourlyForecast(
            lat: _currentPosition?.latitude ?? 16.0431,
            lon: _currentPosition?.longitude ?? 120.3333,
          )
          .timeout(const Duration(seconds: 15)),
      );
      if (!mounted) return;
      setState(() {
        _weatherData = data;
        _dailyWeather = _groupByDay(data);
        _loading = false;
      });
      await _maybePushWeatherNotification();
      _startPeriodicPush();
    } catch (e) {
      _log.e('Error loading weather data', error: e);
      if (!mounted) return;
      setState(() {
        _weatherData = [];
        _dailyWeather = [];
        _loading = false;
      });
    }
  }

  Widget _getWeatherIcon(String iconCode, {double size = 28}) {
    Widget fallbackIcon(String code) {
      final isDay = code.endsWith('d');
      if (code.startsWith('02') || code.startsWith('03') || code.startsWith('04')) {
        return Icon(Icons.cloud, size: size, color: Colors.blueGrey);
      }
      if (code.startsWith('09') || code.startsWith('10')) {
        return Icon(Icons.umbrella, size: size, color: Colors.blue);
      }
      if (code.startsWith('11')) {
        return Icon(Icons.flash_on, size: size, color: Colors.amber);
      }
      if (code.startsWith('13')) {
        return Icon(Icons.ac_unit, size: size, color: Colors.lightBlue);
      }
      return Icon(
        isDay ? Icons.wb_sunny : Icons.nightlight_round,
        size: size,
        color: isDay ? Colors.amber : Colors.blueGrey,
      );
    }

    if (iconCode.startsWith('http') || iconCode.startsWith('//')) {
      final url = iconCode.startsWith('//') ? 'https:$iconCode' : iconCode;
      return Image.network(
        url,
        width: size,
        height: size,
        fit: BoxFit.contain,
        errorBuilder: (_, __, ___) => fallbackIcon(iconCode),
      );
    }

    final url = 'https://openweathermap.org/img/wn/$iconCode@2x.png';
    return Image.network(
      url,
      width: size,
      height: size,
      fit: BoxFit.contain,
      errorBuilder: (_, __, ___) => fallbackIcon(iconCode),
    );
  }

  num _toNum(dynamic value) {
    if (value is num) return value;
    if (value is String) {
      final parsed = double.tryParse(value.replaceAll(RegExp('[^0-9\\.-]'), ''));
      if (parsed != null) return parsed;
    }
    return 0;
  }

  String _tempText(dynamic val) {
    final num temp = _toNum(val);
    return '${temp.round()}\u00B0C';
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
    if (index == 0) return 'Today';
    if (raw is DateTime) return DateFormat('EEE').format(raw);
    if (day['day'] != null) return day['day'].toString();
    return index == 0 ? 'Today' : 'Day ${index + 1}';
  }

  List<Map<String, dynamic>> _groupByDay(List<Map<String, dynamic>> items) {
    final Map<String, Map<String, dynamic>> grouped = {};
    for (final item in items) {
      final raw = item['rawTime'];
      DateTime dt;
      if (raw is DateTime) {
        dt = raw;
      } else if (raw is String) {
        dt = DateTime.tryParse(raw) ?? DateTime.now();
      } else {
        dt = DateTime.now();
      }
      final key = DateFormat('yyyy-MM-dd').format(dt.toLocal());
      grouped.putIfAbsent(key, () {
        return {
          ...item,
          'rawTime': dt,
        };
      });
    }
    final list = grouped.values.toList()
      ..sort((a, b) {
        final da = a['rawTime'] as DateTime;
        final db = b['rawTime'] as DateTime;
        return da.compareTo(db);
      });
    return list;
  }

  _SafetyStatus _safetyStatusFor(Map<String, dynamic>? day) {
    if (day == null) {
      return const _SafetyStatus(label: 'Unknown', color: Colors.grey, textColor: Colors.white);
    }
    final wind = _toNum(day['wind']);
    final visibility = _toNum(day['visibility']);
    final bool safe = wind < 25 && visibility >= 3;
    if (safe) {
      return const _SafetyStatus(label: 'Safe to fish', color: Colors.green, textColor: Colors.white);
    }
    return const _SafetyStatus(label: 'No fishing', color: Colors.red, textColor: Colors.white);
  }

  String _waveRange(num windKph) {
    if (windKph >= 35) return '3-5 m';
    if (windKph >= 20) return '1.5-4 m';
    return '0.6-2.5 m';
  }

  String _galeStatus(num windKph) {
    if (windKph >= 35) return 'Strong-Gale';
    if (windKph >= 20) return 'Mod-Strong';
    return 'Light-Mod';
  }

  String _coastalWaterText(num windKph) {
    if (windKph >= 35) return 'Rough-Very';
    if (windKph >= 20) return 'Mod-Rough';
    return 'Slight-Mod';
  }

  String _highTideLabel(DateTime now) => 'Today';
  String _lowTideLabel(DateTime now) => 'Tomorrow';
  String _highTideTime(DateTime now) => DateFormat('h:mm a').format(DateTime(now.year, now.month, now.day, 15, 45));
  String _lowTideTime(DateTime now) =>
      DateFormat('h:mm a').format(DateTime(now.year, now.month, now.day, 9, 25).add(const Duration(days: 1)));

  Future<void> _startPeriodicPush() async {
    _weatherTimer ??= Timer.periodic(const Duration(minutes: 30), (_) async {
      await _maybePushWeatherNotification();
    });
  }

  Future<void> _maybePushWeatherNotification() async {
    if (_weatherData.isEmpty || _pushing) return;
    _pushing = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      final now = DateTime.now();
      final current = _weatherData.first;
      final windValue = _toNum(current['wind'] ?? 0);
      final wavesText = _waveRange(windValue);
      final galeText = _galeStatus(windValue);
      final coastalText = _coastalWaterText(windValue);
      final humidityText = '${_toNum(current['humidity'] ?? 0).round()}%';
      final visibilityText = '${_toNum(current['visibility'] ?? 0).round()} km';
      final tempText = _tempText(current['temp'] ?? 28);
      final safety = _safetyStatusFor(current).label;
      final highTide = '${_highTideLabel(now)} ${_highTideTime(now)}';
      final lowTide = '${_lowTideLabel(now)} ${_lowTideTime(now)}';

      final signature = [
        _locationName,
        safety,
        highTide,
        lowTide,
        windValue.round(),
        wavesText,
        galeText,
        coastalText,
        humidityText,
        visibilityText,
        tempText,
      ].join('|');

      final last = prefs.getString(_signatureKey);
      if (last == signature) return;
      await prefs.setString(_signatureKey, signature);

      final message =
          'Safety: $safety. High tide $highTide, Low tide $lowTide. Wind ${windValue.round()} km/h, Temp $tempText, Waves $wavesText, Gale $galeText, Coastal $coastalText, Humidity $humidityText, Visibility $visibilityText.';

      final notifications = FirebaseFirestore.instance.collection('notifications');
      final batch = FirebaseFirestore.instance.batch();
      Map<String, dynamic> base(String? role) => {
            'targetRole': role,
            'title': 'Weather & Ocean Alert',
            'message': message,
            'category': 'weather',
            'type': 'weather_alert',
            'timestamp': FieldValue.serverTimestamp(),
            'isRead': false,
            'location': _locationName,
            'highTide': highTide,
            'lowTide': lowTide,
            'wind': '${windValue.round()} km/h',
            'temperature': tempText,
            'waves': wavesText,
            'gale': galeText,
            'coastal': coastalText,
            'humidity': humidityText,
            'visibility': visibilityText,
            'safety': safety,
          };

      batch.set(notifications.doc(), base('web-admin-pcg'));
      batch.set(notifications.doc(), base('web-admin-bfar'));
      await batch.commit();
      await _showLocalWeatherNotification(message);
    } catch (e) {
      _log.w('Weather notification push failed: $e');
    } finally {
      _pushing = false;
    }
  }

  Future<void> _showLocalWeatherNotification(String body) async {
    if (!_localReady) return;
    try {
      await _localNotifications.show(
        DateTime.now().millisecondsSinceEpoch ~/ 1000,
        'Weather & Ocean Alert',
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
      _log.w('Admin local weather notification failed: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final padding = Responsive.pagePadding(context);
    final maxWidth = Responsive.maxContentWidth(context);
    final width = MediaQuery.of(context).size.width;
    final currentWeather = _weatherData.isNotEmpty ? _weatherData[0] : null;

    final currentTemp = _tempText(currentWeather?['temp'] ?? 28);
    final currentDesc =
        (currentWeather?['desc'] as String?)?.isNotEmpty == true ? currentWeather!['desc'] as String : 'Sunny';
    final currentIcon = currentWeather?['icon'] as String? ?? '01d';
    final dateText = _formatDate(currentWeather);
    final windText = '${_toNum(currentWeather?['wind'] ?? 12).round()} km/h';
    final humidityText = '${_toNum(currentWeather?['humidity'] ?? 68).round()}%';
    final visibilityText = '${_toNum(currentWeather?['visibility'] ?? 10).round()} km';
    final windValue = _toNum(currentWeather?['wind'] ?? 0);
    final wavesText = _waveRange(windValue);
    final galeText = _galeStatus(windValue);
    final coastalText = _coastalWaterText(windValue);
    final safetyStatus = _safetyStatusFor(currentWeather);
    final isSafeNow = safetyStatus.label.toLowerCase().contains('safe');

    final metrics = <_ConditionMetric>[
      _ConditionMetric(
        icon: Icons.air_rounded,
        label: 'Wind',
        value: windText,
        accent: const Color(0xFF2675AC),
      ),
      _ConditionMetric(
        icon: Icons.water_drop_rounded,
        label: 'Humidity',
        value: humidityText,
        accent: const Color(0xFF2E9A82),
      ),
      _ConditionMetric(
        icon: Icons.thermostat_rounded,
        label: 'Temperature',
        value: currentTemp,
        accent: const Color(0xFFE37A35),
      ),
      _ConditionMetric(
        icon: Icons.visibility_rounded,
        label: 'Visibility',
        value: visibilityText,
        accent: const Color(0xFF5862C8),
      ),
      _ConditionMetric(
        icon: Icons.waves_rounded,
        label: 'Waves',
        value: wavesText,
        accent: const Color(0xFF2C82AE),
      ),
      _ConditionMetric(
        icon: Icons.warning_amber_rounded,
        label: 'Gale Warning',
        value: galeText,
        accent: const Color(0xFFC66B27),
      ),
      _ConditionMetric(
        icon: Icons.water_rounded,
        label: 'Coastal Water',
        value: coastalText,
        accent: const Color(0xFF4B7891),
      ),
    ];

    return Scaffold(
      backgroundColor: _pageBottom,
      appBar: AppBar(
        title: const Text(
          'Weather & Ocean Alerts',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontFamily: 'serif',
            fontWeight: FontWeight.w900,
            color: _ink,
            fontSize: 30,
          ),
        ),
        centerTitle: true,
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: _ink),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _loading ? null : _loadWeather,
            icon: const Icon(Icons.refresh_rounded, color: _ink, size: 30),
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
                  ? const Center(child: CircularProgressIndicator())
                  : SingleChildScrollView(
                      padding: EdgeInsets.fromLTRB(
                        padding,
                        16,
                        padding,
                        padding + 16,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.fromLTRB(18, 18, 18, 22),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(28),
                              gradient: const LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: [_heroStart, _heroEnd],
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: _heroStart.withValues(alpha: 0.24),
                                  blurRadius: 28,
                                  offset: const Offset(0, 14),
                                ),
                              ],
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Container(
                                  constraints: BoxConstraints(
                                    maxWidth: width < 420
                                        ? width - (padding * 2) - 74
                                        : 420,
                                  ),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 14,
                                    vertical: 9,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withValues(alpha: 0.20),
                                    borderRadius: BorderRadius.circular(999),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(
                                        Icons.location_on_rounded,
                                        color: Colors.white,
                                        size: 18,
                                      ),
                                      const SizedBox(width: 8),
                                      Flexible(
                                        child: Text(
                                          _locationName,
                                          overflow: TextOverflow.ellipsis,
                                          maxLines: 1,
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 15,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 24),
                                Row(
                                  children: [
                                    Container(
                                      width: 92,
                                      height: 92,
                                      decoration: BoxDecoration(
                                        color: Colors.white.withValues(
                                          alpha: 0.17,
                                        ),
                                        borderRadius: BorderRadius.circular(22),
                                      ),
                                      child: Center(
                                        child: _getWeatherIcon(
                                          currentIcon,
                                          size: 58,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 18),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            currentTemp,
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontSize: 45,
                                              fontWeight: FontWeight.w900,
                                              height: 1,
                                            ),
                                          ),
                                          const SizedBox(height: 8),
                                          Text(
                                            currentDesc,
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontSize: 20,
                                              fontWeight: FontWeight.w700,
                                              height: 1.15,
                                            ),
                                          ),
                                          const SizedBox(height: 6),
                                          Text(
                                            dateText,
                                            style: TextStyle(
                                              color: Colors.white.withValues(
                                                alpha: 0.78,
                                              ),
                                              fontSize: 16,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 24),
                                Wrap(
                                  spacing: 10,
                                  runSpacing: 10,
                                  children: [
                                    _heroChip(
                                      icon: Icons.water_drop_outlined,
                                      text: humidityText,
                                    ),
                                    _heroChip(
                                      icon: Icons.air_rounded,
                                      text: windText,
                                    ),
                                    _heroChip(
                                      icon: isSafeNow
                                          ? Icons.check_circle_outline_rounded
                                          : Icons.warning_amber_rounded,
                                      text: safetyStatus.label,
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 26),
                          const Text(
                            'Marine Conditions',
                            style: TextStyle(
                              color: _ink,
                              fontSize: 24,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          const SizedBox(height: 14),
                          GridView.builder(
                            itemCount: metrics.length,
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            gridDelegate:
                                const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 2,
                              crossAxisSpacing: 14,
                              mainAxisSpacing: 14,
                              mainAxisExtent: 136,
                            ),
                            itemBuilder: (context, index) {
                              final metric = metrics[index];
                              return _InfoCard(metric: metric);
                            },
                          ),
                          const SizedBox(height: 22),
                          _safetySection(),
                          const SizedBox(height: 16),
                          _tideRow(),
                          const SizedBox(height: 20),
                          _weatherAlertsCard(),
                        ],
                      ),
                    ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _heroChip({
    required IconData icon,
    required String text,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.white, size: 18),
          const SizedBox(width: 8),
          Text(
            text,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 14.5,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }

  Widget _safetySection() {
    final today = _dailyWeather.isNotEmpty ? _dailyWeather[0] : null;
    final tomorrow = _dailyWeather.length > 1 ? _dailyWeather[1] : null;
    final nextDay = _dailyWeather.length > 2 ? _dailyWeather[2] : null;
    final statuses = [
      ('Today', _safetyStatusFor(today)),
      ('Tomorrow', _safetyStatusFor(tomorrow)),
      ('Later', _safetyStatusFor(nextDay)),
    ];

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.96),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFD8E8F5)),
        boxShadow: [
          BoxShadow(
            color: _heroStart.withValues(alpha: 0.07),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Fishing Safety Indicator',
            style: TextStyle(
              color: _ink,
              fontWeight: FontWeight.w900,
              fontSize: 18,
            ),
          ),
          const SizedBox(height: 12),
          ...statuses.map(
            (item) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _safetyRow(
                item.$1,
                item.$2.label,
                item.$2.color,
                textColor: item.$2.textColor,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _weatherAlertsCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.96),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFD8E8F5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Weather Alerts',
            style: TextStyle(
              color: _ink,
              fontWeight: FontWeight.w900,
              fontSize: 18,
            ),
          ),
          const SizedBox(height: 12),
          ..._dailyWeather.take(7).toList().asMap().entries.map((entry) {
            final idx = entry.key;
            final day = entry.value;
            final label = _dayLabel(day, idx);
            final cond = (day['desc'] as String?)?.isNotEmpty == true
                ? day['desc'] as String
                : 'N/A';
            final tempVal = _toNum(day['temp']);
            final hi = tempVal.round();
            final lo = (tempVal - 2).round();
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _WeatherRow(
                iconWidget: _getWeatherIcon(day['icon'] as String? ?? ''),
                label: label,
                condition: cond,
                tempHigh: hi,
                tempLow: lo,
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _safetyRow(String label, String status, Color color, {Color textColor = Colors.white}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.18)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 14.5,
                color: _ink,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              status,
              style: TextStyle(
                color: textColor,
                fontWeight: FontWeight.w800,
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _pillBox({required String title, required String value, required String time}) {
    return Container(
      width: 150,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.96),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFD8E8F5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontWeight: FontWeight.w900,
              fontSize: 14,
              color: _ink,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(
              fontSize: 12.5,
              color: _mutedInk,
              fontWeight: FontWeight.w700,
            ),
          ),
          Text(
            time,
            style: const TextStyle(
              fontSize: 15,
              color: _ink,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }

  Widget _tideRow() {
    final now = DateTime.now();
    final cycleIndex = now.toUtc().millisecondsSinceEpoch ~/ const Duration(hours: 6).inMilliseconds;
    final isHighNow = cycleIndex.isEven;
    final currentLabel = isHighNow ? 'High Tide' : 'Low Tide';
    final nextLabel = isHighNow ? 'Low Tide' : 'High Tide';
    final currentTime = DateFormat('h:mm a').format(now);
    final nextTimeDate = now.add(const Duration(hours: 6));
    final nextTime = DateFormat('h:mm a').format(nextTimeDate);

    String dayLabel(DateTime dt) {
      final today = DateTime(now.year, now.month, now.day);
      final target = DateTime(dt.year, dt.month, dt.day);
      if (target == today) return 'Today';
      if (target == today.add(const Duration(days: 1))) return 'Tomorrow';
      return DateFormat('MMM d').format(target);
    }

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        _pillBox(title: currentLabel, value: dayLabel(now), time: currentTime),
        _pillBox(title: 'Next: $nextLabel', value: dayLabel(nextTimeDate), time: nextTime),
      ],
    );
  }
}

class _ConditionMetric {
  final IconData icon;
  final String label;
  final String value;
  final Color accent;

  const _ConditionMetric({
    required this.icon,
    required this.label,
    required this.value,
    required this.accent,
  });
}

class _InfoCard extends StatelessWidget {
  final _ConditionMetric metric;

  const _InfoCard({required this.metric});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.98),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFD8E8F5)),
        boxShadow: [
          BoxShadow(
            color: metric.accent.withValues(alpha: 0.07),
            blurRadius: 14,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: metric.accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Icon(metric.icon, color: metric.accent, size: 21),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  metric.label,
                  style: const TextStyle(
                    fontSize: 15,
                    color: _AdminWeatherOceanAlertsState._mutedInk,
                    fontWeight: FontWeight.w700,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          Text(
            metric.value,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w900,
              color: _AdminWeatherOceanAlertsState._ink,
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
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        SizedBox(width: 26, height: 26, child: Center(child: iconWidget)),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(label, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
              Text(condition, style: const TextStyle(fontSize: 14, color: Colors.black87)),
            ],
          ),
        ),
        Text(
          '$tempHigh° / $tempLow°',
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
        ),
      ],
    );
  }
}

class _SafetyStatus {
  final String label;
  final Color color;
  final Color textColor;

  const _SafetyStatus({
    required this.label,
    required this.color,
    required this.textColor,
  });
}
