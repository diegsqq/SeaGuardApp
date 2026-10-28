import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:logger/logger.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart';
import '../community/community_screen.dart' as community;
import 'educational_screen.dart';
import 'educational_section_page.dart';
import 'navbar_screen.dart';
import 'report_activities_page.dart';
import 'logsighting_page.dart';
import 'weather_service.dart';
import 'marine_life_page.dart';
import 'weather_ocean_alerts_screen.dart';
import 'package:sea_guard/l10n/app_localizations.dart';
import 'package:sea_guard/utils/loading_delay.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen>
    with WidgetsBindingObserver {
  final ImagePicker _picker = ImagePicker();
  final Logger _log = Logger(printer: PrettyPrinter(methodCount: 0));
  static const Duration _weatherRefreshInterval = Duration(minutes: 10);

  int _selectedIndex = 0;
  List<Map<String, dynamic>> _weatherData = [];
  bool _loadingWeather = true;
  Position? _currentPosition;
  bool _interactionLocked = false;
  bool _guardLoading = true;
  String _lockMessage = '';
  Timer? _weatherRefreshTimer;
  bool _weatherRefreshInFlight = false;

  bool _isActive(dynamic value) {
    if (value == null) return true;
    if (value is bool) return value;
    return value.toString().toLowerCase() == 'true';
  }

  bool _isArchived(dynamic value) {
    if (value == null) return false;
    if (value is bool) return value;
    return value.toString().toLowerCase() == 'true';
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initWeather();
    _startWeatherAutoRefresh();
    _loadAccessGuard();
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
      _refreshWeatherInBackground();
    }
  }

  void _startWeatherAutoRefresh() {
    _weatherRefreshTimer?.cancel();
    _weatherRefreshTimer = Timer.periodic(_weatherRefreshInterval, (_) {
      _refreshWeatherInBackground();
    });
  }

  Future<void> _refreshWeatherInBackground() async {
    if (_weatherRefreshInFlight) return;
    _weatherRefreshInFlight = true;
    try {
      await _loadWeather(showLoader: false, notifyOnFailure: false);
    } finally {
      _weatherRefreshInFlight = false;
    }
  }

  Future<void> _loadWeather({
    bool showLoader = true,
    bool notifyOnFailure = true,
  }) async {
    _log.i('Fetching weather forecast...');
    final hadData = _weatherData.isNotEmpty;
    final shouldShowLoader = mounted && (showLoader || !hadData);
    if (shouldShowLoader) {
      setState(() {
        _loadingWeather = true;
      });
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
      _log.i('Raw weather data: $data');

      if (!mounted) return;
      setState(() {
        _weatherData = data;
        _loadingWeather = false;
      });

      _log.i('Weather data loaded. Count: ${_weatherData.length}');
    } catch (e, stack) {
      _log.e('Error loading weather data', error: e, stackTrace: stack);
      if (!mounted) return;
      setState(() {
        _loadingWeather = false;
        if (!hadData) {
          _weatherData = [];
        }
      });
      if (mounted && notifyOnFailure) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text(
              'Failed to load weather data. Please check your connection and try again.',
            ),
            duration: const Duration(seconds: 4),
          ),
        );
      }
      _log.w('Weather data failed to load, showing empty state');
    }
  }

  Future<void> _initWeather() async {
    await _getLocation();
    await _loadWeather();
  }

  Future<void> _getLocation() async {
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        _log.w('Location services disabled, using fallback coords');
        return;
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        _log.w('Location permission denied, using fallback coords');
        return;
      }

      try {
        final pos = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.high,
          ),
        );
        _currentPosition = pos;
        _log.i('Got location: ${pos.latitude}, ${pos.longitude}');
      } catch (e) {
        final last = await Geolocator.getLastKnownPosition();
        if (last != null) {
          _currentPosition = last;
          _log.i(
            'Using last known location: ${last.latitude}, ${last.longitude}',
          );
        } else {
          rethrow;
        }
      }
    } catch (e, s) {
      _log.w(
        'Failed to get location, using fallback coords',
        error: e,
        stackTrace: s,
      );
    }
  }

  Future<void> _refreshWeather() async {
    await _getLocation();
    await _loadWeather();
  }

  Future<void> _loadAccessGuard() async {
    // PCG verification gating removed: keep the dashboard fully interactive.
    if (!mounted) return;
    setState(() {
      _interactionLocked = false;
      _guardLoading = false;
      _lockMessage = '';
    });
  }

  void _openPreview(XFile image) {
    _log.i('Opening image preview: ${image.path}');
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => Scaffold(
          appBar: AppBar(title: const Text('Scan Preview')),
          body: Center(
            child: Image.file(File(image.path), fit: BoxFit.contain),
          ),
        ),
      ),
    );
  }

  Future<void> _scanWithCamera() async {
    final image = await _picker.pickImage(source: ImageSource.camera);
    if (!mounted || image == null) return;
    _openPreview(image);
  }

  Future<void> _scanWithGallery() async {
    final image = await _picker.pickImage(source: ImageSource.gallery);
    if (!mounted || image == null) return;
    _openPreview(image);
  }

  void _onItemTapped(int index) {
    if (index == 0) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const DashboardScreen()),
      );
    } else if (index == 1) {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const community.CommunityScreen()),
      );
    } else if (index == 2) {
      showModalBottomSheet(
        context: context,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
        ),
        builder: (_) => Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt),
              title: const Text('Camera'),
              onTap: _scanWithCamera,
            ),
            ListTile(
              leading: const Icon(Icons.upload_file),
              title: const Text('Upload'),
              onTap: _scanWithGallery,
            ),
          ],
        ),
      );
    } else {
      setState(() => _selectedIndex = index);
    }
  }

  String _withUnit(String value, String unit, {bool addSpace = true}) {
    if (value.isEmpty) return '--';
    final spacer = addSpace && unit.isNotEmpty ? ' ' : '';
    return '$value$spacer$unit';
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

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final primaryColor = const Color(0xFF0F2548);
    final backgroundColor = const Color(0xFFF2F6FB);
    final weather = _weatherData.isNotEmpty ? _weatherData.first : null;
    final wind = (weather?['wind'] ?? '').toString();
    final humidity = (weather?['humidity'] ?? '').toString();
    final temp = (weather?['temp'] ?? '').toString();
    final currentTemp = temp.isNotEmpty ? temp : '--';
    final visibility = (weather?['visibility'] ?? '').toString();
    final isSafe = _isSafeToFish(weather);
    final safetyColor = isSafe
        ? const Color(0xFF4CAF70)
        : const Color(0xFFCF3A4B);
    final safetyLabel = isSafe
        ? AppLocalizations.of(context)!.safeToFish
        : 'No fishing';
    final safetyIcon = isSafe
        ? 'assets/safe to fish.jpg'
        : 'assets/no fishing.jpg';
    final metricTileWidth = (size.width * 0.46).clamp(150.0, 190.0).toDouble();

    return Scaffold(
      backgroundColor: backgroundColor,
      bottomNavigationBar: CustomBottomNavBar(
        currentIndex: _selectedIndex,
        onTap: _onItemTapped,
      ),

      body: SafeArea(
        child: Stack(
          children: [
            Positioned(
              top: -90,
              right: -70,
              child: Container(
                width: 230,
                height: 230,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFF9CC7E9).withValues(alpha: 0.28),
                ),
              ),
            ),
            Positioned(
              top: 140,
              left: -80,
              child: Container(
                width: 180,
                height: 180,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFFCCE4F8).withValues(alpha: 0.42),
                ),
              ),
            ),
            AbsorbPointer(
              absorbing: _interactionLocked,
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 32),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      AppLocalizations.of(context)!.dashboard.toUpperCase(),
                      style: TextStyle(
                        fontSize: 34,
                        fontWeight: FontWeight.w900,
                        color: primaryColor,
                        letterSpacing: 0.7,
                        height: 1.05,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Real-time marine conditions and quick actions',
                      style: TextStyle(
                        color: primaryColor.withValues(alpha: 0.62),
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 14),
                    RefreshIndicator(
                      onRefresh: _refreshWeather,
                      color: primaryColor,
                      child: _loadingWeather
                          ? ListView(
                              physics: const AlwaysScrollableScrollPhysics(),
                              shrinkWrap: true,
                              children: [
                                SizedBox(
                                  height: size.height * 0.22,
                                  child: const Center(
                                    child: CircularProgressIndicator(),
                                  ),
                                ),
                              ],
                            )
                          : ListView(
                              physics: const AlwaysScrollableScrollPhysics(),
                              shrinkWrap: true,
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(16),
                                  decoration: BoxDecoration(
                                    gradient: const LinearGradient(
                                      begin: Alignment.topLeft,
                                      end: Alignment.bottomRight,
                                      colors: [Colors.white, Color(0xFFF2FAFF)],
                                    ),
                                    borderRadius: BorderRadius.circular(24),
                                    border: Border.all(
                                      color: const Color(0xFFD4E7F7),
                                    ),
                                    boxShadow: [
                                      BoxShadow(
                                        color: primaryColor.withValues(
                                          alpha: 0.08,
                                        ),
                                        blurRadius: 20,
                                        offset: const Offset(0, 10),
                                      ),
                                    ],
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.spaceBetween,
                                        children: [
                                          Text(
                                            AppLocalizations.of(
                                              context,
                                            )!.todaysForecast,
                                            style: TextStyle(
                                              fontSize: 18,
                                              fontWeight: FontWeight.w800,
                                              color: primaryColor,
                                            ),
                                          ),
                                          Container(
                                            constraints: const BoxConstraints(
                                              maxWidth: 168,
                                            ),
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 14,
                                              vertical: 8,
                                            ),
                                            decoration: BoxDecoration(
                                              color: safetyColor,
                                              borderRadius:
                                                  BorderRadius.circular(999),
                                              boxShadow: [
                                                BoxShadow(
                                                  color: safetyColor.withValues(
                                                    alpha: 0.28,
                                                  ),
                                                  blurRadius: 12,
                                                  offset: const Offset(0, 6),
                                                ),
                                              ],
                                            ),
                                            child: Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                Flexible(
                                                  child: Text(
                                                    safetyLabel,
                                                    maxLines: 1,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                    style: const TextStyle(
                                                      color: Colors.white,
                                                      fontWeight:
                                                          FontWeight.w800,
                                                      fontSize: 16,
                                                    ),
                                                  ),
                                                ),
                                                const SizedBox(width: 8),
                                                Container(
                                                  decoration:
                                                      const BoxDecoration(
                                                        color: Colors.white,
                                                        shape: BoxShape.circle,
                                                      ),
                                                  padding: const EdgeInsets.all(
                                                    4,
                                                  ),
                                                  child: Image.asset(
                                                    safetyIcon,
                                                    height: 16,
                                                    width: 16,
                                                    fit: BoxFit.contain,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 8),
                                      Row(
                                        children: [
                                          Text(
                                            currentTemp,
                                            style: TextStyle(
                                              fontSize: 30,
                                              fontWeight: FontWeight.w900,
                                              color: primaryColor,
                                              height: 1.0,
                                            ),
                                          ),
                                          const SizedBox(width: 6),
                                          Icon(
                                            Icons.thermostat_rounded,
                                            color: primaryColor,
                                            size: 19,
                                          ),
                                        ],
                                      ),
                                      Align(
                                        alignment: Alignment.centerRight,
                                        child: TextButton(
                                          onPressed: () {
                                            Navigator.push(
                                              context,
                                              MaterialPageRoute(
                                                builder: (_) =>
                                                    const WeatherOceanAlertsScreen(),
                                              ),
                                            );
                                          },
                                          style: TextButton.styleFrom(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 8,
                                            ),
                                            minimumSize: const Size(0, 36),
                                            tapTargetSize: MaterialTapTargetSize
                                                .shrinkWrap,
                                            foregroundColor: primaryColor,
                                          ),
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Text(
                                                '${AppLocalizations.of(context)!.seeMore} details',
                                                style: TextStyle(
                                                  fontSize: 13,
                                                  fontWeight: FontWeight.w700,
                                                  color: primaryColor
                                                      .withValues(alpha: 0.82),
                                                ),
                                              ),
                                              const SizedBox(width: 6),
                                              Icon(
                                                Icons.chevron_right_rounded,
                                                size: 20,
                                                color: primaryColor.withValues(
                                                  alpha: 0.82,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                      const SizedBox(height: 8),
                                      SizedBox(
                                        height: 92,
                                        child: ListView(
                                          scrollDirection: Axis.horizontal,
                                          physics:
                                              const BouncingScrollPhysics(),
                                          children: [
                                            _buildMetricTile(
                                              icon: Icons.air_rounded,
                                              label: 'Wind',
                                              value: _withUnit(wind, 'km/h'),
                                              accentColor: const Color(
                                                0xFF1B76B7,
                                              ),
                                              width: metricTileWidth,
                                            ),
                                            const SizedBox(width: 10),
                                            _buildMetricTile(
                                              icon: Icons.water_drop_rounded,
                                              label: 'Humidity',
                                              value: _withUnit(
                                                humidity,
                                                '%',
                                                addSpace: false,
                                              ),
                                              accentColor: const Color(
                                                0xFF2B9A8C,
                                              ),
                                              width: metricTileWidth,
                                            ),
                                            const SizedBox(width: 10),
                                            _buildMetricTile(
                                              icon: Icons.thermostat_rounded,
                                              label: 'Temperature',
                                              value: currentTemp,
                                              accentColor: const Color(
                                                0xFFE26B3A,
                                              ),
                                              width: metricTileWidth,
                                            ),
                                            const SizedBox(width: 10),
                                            _buildMetricTile(
                                              icon:
                                                  Icons.remove_red_eye_outlined,
                                              label: 'Visibility',
                                              value: _withUnit(
                                                visibility,
                                                'km',
                                              ),
                                              accentColor: const Color(
                                                0xFF5A5ECF,
                                              ),
                                              width: metricTileWidth,
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                    ),
                    const SizedBox(height: 18),
                    Row(
                      children: [
                        Expanded(
                          child: _buildPrimaryAction(
                            color: const Color(0xFF0A2F56),
                            secondaryColor: const Color(0xFF134C84),
                            icon: Icons.warning_amber_rounded,
                            label: AppLocalizations.of(
                              context,
                            )!.reportIllegalActivities,
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => const ReportActivitiesPage(),
                                ),
                              );
                            },
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _buildPrimaryAction(
                            color: const Color(0xFF0A2F56),
                            secondaryColor: const Color(0xFF1D5B8E),
                            icon: Icons.bar_chart_rounded,
                            label: AppLocalizations.of(context)!.marineLife,
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => const MarineLifePage(),
                                ),
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Material(
                      color: Colors.transparent,
                      child: Ink(
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [Color(0xFF08345E), Color(0xFF0C4A7D)],
                          ),
                          borderRadius: BorderRadius.circular(18),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(
                                0xFF0A2F56,
                              ).withValues(alpha: 0.28),
                              blurRadius: 16,
                              offset: const Offset(0, 8),
                            ),
                          ],
                        ),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(18),
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const LogSightingPage(),
                              ),
                            );
                          },
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 16,
                            ),
                            child: Row(
                              children: [
                                Container(
                                  width: 34,
                                  height: 34,
                                  decoration: BoxDecoration(
                                    color: Colors.white.withValues(alpha: 0.18),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: const Icon(
                                    Icons.photo_camera_back_rounded,
                                    color: Colors.white,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    AppLocalizations.of(
                                      context,
                                    )!.marineSighting,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w800,
                                      fontSize: 17,
                                    ),
                                  ),
                                ),
                                const Icon(
                                  Icons.arrow_forward_rounded,
                                  color: Colors.white,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                      stream: FirebaseFirestore.instance
                          .collection('educational_resources')
                          .snapshots(),
                      builder: (context, snapshot) {
                        if (snapshot.hasError) {
                          return const Padding(
                            padding: EdgeInsets.all(12),
                            child: Text(
                              'Failed to load educational resources',
                              style: TextStyle(color: Colors.red),
                            ),
                          );
                        }
                        if (!snapshot.hasData) {
                          return const Padding(
                            padding: EdgeInsets.all(12),
                            child: Center(child: CircularProgressIndicator()),
                          );
                        }

                        final docs = snapshot.data!.docs;
                        final resources = docs
                            .map((d) => d.data())
                            .where(
                              (data) =>
                                  _isActive(data['active']) &&
                                  !_isArchived(data['archived']),
                            )
                            .toList();

                        final categorySet = <String>{};
                        bool hasVideo = false;
                        for (final r in resources) {
                          final cat = (r['categoryName'] ?? '')
                              .toString()
                              .trim();
                          if (cat.isNotEmpty) categorySet.add(cat);
                          final yt = (r['youtubeId'] ?? '').toString().trim();
                          final type = (r['type'] ?? '')
                              .toString()
                              .toLowerCase();
                          if (yt.isNotEmpty || type == 'video') hasVideo = true;
                        }
                        if (hasVideo) {
                          categorySet.add('Video & Infographics Section');
                        }

                        final categories = categorySet.toList()..sort();

                        if (categories.isEmpty) {
                          return Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: const Color(0xFFD4E3F0),
                              ),
                            ),
                            child: const Text(
                              'No educational resources available.',
                            ),
                          );
                        }

                        final firstCategory = categories.first;

                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  AppLocalizations.of(
                                    context,
                                  )!.educationalResources,
                                  style: TextStyle(
                                    fontWeight: FontWeight.w900,
                                    fontSize: 22,
                                    color: primaryColor,
                                    letterSpacing: 0.2,
                                  ),
                                ),
                                TextButton(
                                  onPressed: () {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) => EducationalSectionPage(
                                          selectedCategory: firstCategory,
                                        ),
                                      ),
                                    );
                                  },
                                  style: TextButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                    ),
                                    minimumSize: const Size(0, 36),
                                    tapTargetSize:
                                        MaterialTapTargetSize.shrinkWrap,
                                    foregroundColor: primaryColor,
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        AppLocalizations.of(context)!.seeMore,
                                        style: const TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                      const SizedBox(width: 6),
                                      const Icon(
                                        Icons.chevron_right_rounded,
                                        size: 20,
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            ...categories.asMap().entries.map((entry) {
                              final index = entry.key;
                              final category = entry.value;
                              const categoryIcons = [
                                Icons.gavel_rounded,
                                Icons.eco_rounded,
                                Icons.ondemand_video_rounded,
                                Icons.menu_book_rounded,
                              ];

                              return _buildResourceTile(
                                title: category,
                                icon:
                                    categoryIcons[index % categoryIcons.length],
                                onTap: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => EducationalScreen(
                                        initialCategory: category,
                                      ),
                                    ),
                                  );
                                },
                              );
                            }),
                          ],
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
            if (_guardLoading)
              const Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: LinearProgressIndicator(minHeight: 2),
              ),
            if (_interactionLocked && !_guardLoading)
              Positioned(
                bottom: 18,
                left: 16,
                right: 16,
                child: IgnorePointer(
                  ignoring: true,
                  child: Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.8),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(
                          Icons.lock_clock,
                          color: Colors.white,
                          size: 20,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            _lockMessage.isNotEmpty
                                ? _lockMessage
                                : 'Your account is pending verification. Actions are disabled until approval.',
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
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
      ),
    );
  }

  Widget _buildMetricTile({
    required IconData icon,
    required String label,
    required String value,
    required Color accentColor,
    double? width,
  }) {
    final parts = value.split(' ');
    final mainValue = parts.isNotEmpty ? parts.first : value;
    final unit = parts.length > 1 ? parts.sublist(1).join(' ') : '';

    return Container(
      width: width,
      decoration: BoxDecoration(
        color: accentColor.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: accentColor.withValues(alpha: 0.2)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Container(
                width: 26,
                height: 26,
                decoration: BoxDecoration(
                  color: accentColor.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, color: accentColor, size: 16),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: accentColor.withValues(alpha: 0.88),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          RichText(
            text: TextSpan(
              children: [
                TextSpan(
                  text: mainValue,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    color: Color(0xFF0F2548),
                  ),
                ),
                if (unit.isNotEmpty)
                  TextSpan(
                    text: ' $unit',
                    style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF40566F),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPrimaryAction({
    required Color color,
    Color? secondaryColor,
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    final endColor = secondaryColor ?? Color.lerp(color, Colors.black, 0.16)!;
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 104),
      child: Material(
        color: Colors.transparent,
        child: Ink(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [color, endColor],
            ),
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: color.withValues(alpha: 0.28),
                blurRadius: 16,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(20),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.16),
                      borderRadius: BorderRadius.circular(11),
                    ),
                    child: Icon(icon, size: 20, color: Colors.white),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    label,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    softWrap: true,
                    overflow: TextOverflow.visible,
                    style: const TextStyle(
                      fontSize: 13.2,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildResourceTile({
    required String title,
    required VoidCallback onTap,
    IconData icon = Icons.menu_book_rounded,
  }) {
    return Material(
      color: Colors.transparent,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFD7E6F5)),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF0F2548).withValues(alpha: 0.05),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: ListTile(
          leading: Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: const Color(0xFFECF5FF),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: const Color(0xFF0F2548), size: 18),
          ),
          title: Text(
            title,
            style: const TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 14.5,
              color: Colors.black87,
            ),
          ),
          trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 15),
          onTap: onTap,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 14,
            vertical: 5,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      ),
    );
  }
}
