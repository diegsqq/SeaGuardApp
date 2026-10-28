import 'package:flutter/material.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import '../l10n/app_localizations.dart';
import '../screens/dashboard/weather_service.dart';
import '../utils/loading_delay.dart';
import '../utils/responsive.dart';
import 'admin_report_emergency.dart';
import 'admin_weather_ocean_alert.dart';
import 'illegal_reports.dart';
import 'share_location.dart';

class AdminDashboard extends StatelessWidget {
  const AdminDashboard({super.key});

  @override
  Widget build(BuildContext context) => const AdminDashboardHome();
}

class AdminDashboardHome extends StatefulWidget {
  const AdminDashboardHome({super.key});

  @override
  State<AdminDashboardHome> createState() => _AdminDashboardHomeState();
}

class _AdminDashboardHomeState extends State<AdminDashboardHome> {
  static const Color _ink = Color(0xFF0A2239);
  static const Color _ocean = Color(0xFF0D4D69);
  static const Color _mist = Color(0xFFF4FBFD);
  static const Color _surface = Colors.white;

  final WeatherService _weatherService = WeatherService();
  List<Map<String, dynamic>> _forecast = [];
  bool _loadingWeather = true;
  String fishingStatus = "safe";
  Position? _currentPosition;
  String _locationLabel = 'Fetching location...';
  bool _interactionLocked = false;
  bool _guardLoading = true;
  String _lockMessage = '';

  @override
  void initState() {
    super.initState();
    _initData();
    _loadAccessGuard();
  }

  Future<void> _initData() async {
    await _getLocation();
    await _loadWeather();
  }

  Future<void> _getLocation() async {
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        setState(() => _locationLabel = 'Location off (using default)');
        return;
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
        setState(() => _locationLabel = 'Permission denied (using default)');
        return;
      }

      try {
        final pos = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
        );
        _currentPosition = pos;
        await _setAddressFromCoords(pos);
      } catch (_) {
        final last = await Geolocator.getLastKnownPosition();
        if (last != null) {
          _currentPosition = last;
          await _setAddressFromCoords(last);
        } else {
          setState(() => _locationLabel = 'Using default location');
        }
      }
    } catch (_) {
      setState(() => _locationLabel = 'Using default location');
    }
  }

  Future<void> _loadWeather() async {
    setState(() => _loadingWeather = true);
    try {
      final data = await withMinimumLoadingTime(
        _weatherService.fetchHourlyForecast(
          lat: _currentPosition?.latitude ?? 16.0431,
          lon: _currentPosition?.longitude ?? 120.3333,
        ),
      );
      if (!mounted) return;
      setState(() {
        _forecast = data;
        fishingStatus = _deriveSafety(data);
        _loadingWeather = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingWeather = false);
    }
  }

  Future<void> _refresh() async {
    await _getLocation();
    await _loadWeather();
    await _loadAccessGuard();
  }

  Future<void> _loadAccessGuard() async {
    // PCG verification gating removed: keep admin dashboard fully interactive.
    if (!mounted) return;
    setState(() {
      _interactionLocked = false;
      _guardLoading = false;
      _lockMessage = '';
    });
  }

  Future<void> _setAddressFromCoords(Position pos) async {
    try {
      final placemarks = await placemarkFromCoordinates(pos.latitude, pos.longitude);
      if (placemarks.isNotEmpty) {
        final place = placemarks.first;
        final city = place.locality?.isNotEmpty == true ? place.locality : place.subAdministrativeArea;
        final admin = place.administrativeArea;
        final country = place.country;
        final buffer = [
          if (city != null && city.isNotEmpty) city,
          if (admin != null && admin.isNotEmpty) admin,
          if (country != null && country.isNotEmpty) country,
        ].where((e) => e.isNotEmpty).join(', ');
        if (buffer.isNotEmpty) {
          setState(() => _locationLabel = buffer);
          return;
        }
      }
    } catch (_) {
      // Fall back below
    }
    setState(() {
      _locationLabel =
          'Lat ${pos.latitude.toStringAsFixed(3)}, Lon ${pos.longitude.toStringAsFixed(3)}';
    });
  }

  String _deriveSafety(List<Map<String, dynamic>> items) {
    if (items.isEmpty) return "safe";
    final first = items.first;
    final wind = double.tryParse(first['wind']?.toString() ?? '') ?? 0;
    final visibility = double.tryParse(first['visibility']?.toString() ?? '') ?? 10;
    if (wind >= 35 || visibility < 2) return "danger";
    if (wind >= 20) return "moderate";
    return "safe";
  }

  Color _statusColor() {
    switch (fishingStatus) {
      case "danger":
        return const Color(0xFFE45A46);
      case "moderate":
        return const Color(0xFFF59E0B);
      default:
        return const Color(0xFF22A06B);
    }
  }

  IconData _statusIcon() {
    switch (fishingStatus) {
      case "danger":
        return Icons.gpp_bad_rounded;
      case "moderate":
        return Icons.warning_amber_rounded;
      default:
        return Icons.sailing_rounded;
    }
  }

  String _statusText() {
    switch (fishingStatus) {
      case "danger":
        return "No fishing";
      case "moderate":
        return "Use caution";
      default:
        return "Safe to fish";
    }
  }

  String _statusSubtitle() {
    switch (fishingStatus) {
      case "danger":
        return "Restrict small craft and delay departures.";
      case "moderate":
        return "Review gusts and surf before dispatching.";
      default:
        return "Conditions are calm enough for routine movement.";
    }
  }

  String _formatNumber(dynamic value, String suffix) {
    final str = (value ?? '').toString();
    if (str.isEmpty) return '--';
    final num? parsed = double.tryParse(str);
    if (parsed != null) {
      final display = parsed % 1 == 0 ? parsed.toInt().toString() : parsed.toStringAsFixed(1);
      return '$display$suffix';
    }
    return '$str$suffix';
  }

  double _parseDouble(dynamic value) {
    if (value == null) return double.nan;
    final parsed = double.tryParse(value.toString());
    return parsed ?? double.nan;
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

  String _formatTemp(dynamic value) {
    final cleaned = (value ?? '').toString().replaceAll(RegExp('[^0-9\\-\\.]'), '');
    if (cleaned.isEmpty) return '--';
    return '$cleaned c';
  }

  Widget _surfaceCard({
    required Widget child,
    EdgeInsetsGeometry padding = const EdgeInsets.all(20),
  }) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: _surface.withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: const Color(0xFFD7EAF1)),
        boxShadow: [
          BoxShadow(
            color: _ink.withValues(alpha: 0.08),
            blurRadius: 26,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      child: child,
    );
  }

  Widget _buildPageHeader(AppLocalizations l) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: const Color(0xFFE1F4F8),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: const Color(0xFFC6E7EF)),
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.shield_outlined, size: 18, color: _ocean),
              SizedBox(width: 8),
              Text(
                'PCG Operations',
                style: TextStyle(
                  color: _ocean,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.2,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        Text(
          l.adminDashboardTitle,
          style: const TextStyle(
            fontSize: 34,
            fontWeight: FontWeight.w900,
            color: _ink,
            letterSpacing: -0.6,
            height: 0.95,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          'Track marine conditions, incident flow, and response-ready tools from one command deck.',
          style: TextStyle(
            fontSize: 14.5,
            color: _ink.withValues(alpha: 0.65),
            fontWeight: FontWeight.w600,
            height: 1.45,
          ),
        ),
      ],
    );
  }

  Widget _statusPill() {
    final color = _statusColor();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.24)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(_statusIcon(), size: 18, color: color),
          const SizedBox(width: 8),
          Text(
            _statusText(),
            style: TextStyle(
              color: color,
              fontSize: 13,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }

  Widget _forecastHero(
    BuildContext context,
    AppLocalizations l, {
    required String tempValue,
  }) {
    return Container(
      padding: const EdgeInsets.fromLTRB(22, 22, 22, 20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFF08263F),
            Color(0xFF0D4D69),
            Color(0xFF1A97AB),
          ],
        ),
        borderRadius: BorderRadius.circular(32),
        boxShadow: [
          BoxShadow(
            color: _ocean.withValues(alpha: 0.26),
            blurRadius: 30,
            offset: const Offset(0, 16),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 12,
            runSpacing: 12,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.12),
                  ),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.radar_rounded, color: Colors.white, size: 16),
                    SizedBox(width: 8),
                    Text(
                      'Coastal Outlook',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              _statusPill(),
            ],
          ),
          const SizedBox(height: 20),
          Text(
            l.adminTodaysForecast,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 26,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.3,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _locationLabel,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.76),
              fontSize: 14,
              fontWeight: FontWeight.w600,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 22),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                tempValue,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 56,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -1.8,
                  height: 0.95,
                ),
              ),
              if (tempValue != '--')
                Padding(
                  padding: const EdgeInsets.only(left: 6, bottom: 8),
                  child: Text(
                    'C',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.76),
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              const Spacer(),
              Flexible(
                child: TextButton.icon(
                  onPressed: _interactionLocked
                      ? null
                      : () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const AdminWeatherOceanAlerts(),
                            ),
                          );
                        },
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.white,
                    backgroundColor: Colors.white.withValues(alpha: 0.12),
                    disabledForegroundColor:
                        Colors.white.withValues(alpha: 0.4),
                    disabledBackgroundColor:
                        Colors.white.withValues(alpha: 0.08),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  icon: const Icon(Icons.arrow_outward_rounded, size: 18),
                  label: Text(
                    l.adminSeeMore,
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            _statusSubtitle(),
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.74),
              fontSize: 13.5,
              fontWeight: FontWeight.w600,
              height: 1.45,
            ),
          ),
          if (_loadingWeather) ...[
            const SizedBox(height: 18),
            ClipRRect(
              borderRadius: BorderRadius.circular(99),
              child: const LinearProgressIndicator(
                minHeight: 5,
                backgroundColor: Color(0x40FFFFFF),
                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _sectionHeader({
    required String title,
    required String subtitle,
    Widget? trailing,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: _ink,
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.2,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                subtitle,
                style: TextStyle(
                  color: _ink.withValues(alpha: 0.62),
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
        if (trailing != null) ...[
          const SizedBox(width: 12),
          trailing,
        ],
      ],
    );
  }

  Widget _metricCard({
    required IconData icon,
    required String label,
    required String value,
    required Color accentColor,
    double valueFontSize = 19,
    double? width,
  }) {
    return Container(
      width: width,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _surface.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: accentColor.withValues(alpha: 0.18)),
        boxShadow: [
          BoxShadow(
            color: accentColor.withValues(alpha: 0.08),
            blurRadius: 18,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: accentColor.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: accentColor, size: 20),
          ),
          const SizedBox(height: 14),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: _ink.withValues(alpha: 0.62),
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: _ink,
              fontSize: valueFontSize,
              fontWeight: FontWeight.w900,
              height: 1.15,
            ),
          ),
        ],
      ),
    );
  }

  Widget _metricSlider(
    BuildContext context, {
    required List<Map<String, Object>> metrics,
  }) {
    final screenWidth = MediaQuery.of(context).size.width;
    final cardWidth = screenWidth < 380 ? 166.0 : 178.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              Icons.swipe_rounded,
              size: 16,
              color: _ink.withValues(alpha: 0.54),
            ),
            const SizedBox(width: 6),
            Text(
              'Swipe for more conditions',
              style: TextStyle(
                color: _ink.withValues(alpha: 0.54),
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 170,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            itemCount: metrics.length,
            separatorBuilder: (_, __) => const SizedBox(width: 12),
            itemBuilder: (context, index) {
              final item = metrics[index];
              return _metricCard(
                icon: item['icon'] as IconData,
                label: item['label'] as String,
                value: item['value'] as String,
                accentColor: item['accent'] as Color,
                valueFontSize: item['label'] == 'Coastal Water' ? 17 : 19,
                width: cardWidth,
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _illegalReportsCard(AppLocalizations l) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: _interactionLocked
            ? null
            : () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const IllegalReportsPage(),
                  ),
                );
              },
        borderRadius: BorderRadius.circular(28),
        child: Ink(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Color(0xFFFFF7F0),
                Color(0xFFFFEFE2),
              ],
            ),
            borderRadius: BorderRadius.circular(28),
            border: Border.all(color: const Color(0xFFFFD8B0)),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFFBD6B1A).withValues(alpha: 0.08),
                blurRadius: 18,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: const Color(0xFFB76117).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: const Icon(
                  Icons.warning_amber_rounded,
                  size: 28,
                  color: Color(0xFFB76117),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l.adminIllegalActivitiesReports,
                      style: const TextStyle(
                        color: _ink,
                        fontWeight: FontWeight.w900,
                        fontSize: 19,
                        letterSpacing: -0.2,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Review field complaints, validate evidence, and escalate active cases.',
                      style: TextStyle(
                        color: _ink.withValues(alpha: 0.62),
                        fontWeight: FontWeight.w600,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(
                  Icons.arrow_forward_rounded,
                  color: _ink,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _actionCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required List<Color> colors,
    required VoidCallback onTap,
  }) {
    final enabled = !_interactionLocked;
    return Opacity(
      opacity: enabled ? 1 : 0.55,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 204),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: enabled ? onTap : null,
            borderRadius: BorderRadius.circular(28),
            child: Ink(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: colors,
                ),
                borderRadius: BorderRadius.circular(28),
                boxShadow: [
                  BoxShadow(
                    color: colors.first.withValues(alpha: 0.24),
                    blurRadius: 22,
                    offset: const Offset(0, 12),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.16),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Icon(icon, color: Colors.white, size: 24),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 21,
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -0.3,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 13.5,
                      color: Colors.white.withValues(alpha: 0.82),
                      fontWeight: FontWeight.w600,
                      height: 1.45,
                    ),
                  ),
                  const SizedBox(height: 18),
                  const Row(
                    children: [
                      Text(
                        'Open',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      SizedBox(width: 8),
                      Icon(
                        Icons.arrow_forward_rounded,
                        color: Colors.white,
                        size: 18,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _lockBanner() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _ink.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.18),
            blurRadius: 18,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.lock_clock_rounded,
              color: Colors.white,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              _lockMessage.isNotEmpty
                  ? _lockMessage
                  : 'Your PCG verification is pending. Actions are disabled until approval.',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final maxWidth = Responsive.maxContentWidth(context);
    final current = _forecast.isNotEmpty
        ? _forecast.first
        : {
            'wind': '12',
            'humidity': '68',
            'temp': '30',
            'visibility': '10',
          };

    final windText = _formatNumber(current['wind'], ' km/h');
    final humidityText = _formatNumber(current['humidity'], '%');
    final tempText = _formatTemp(current['temp']);
    final tempValue =
        tempText == '--' ? tempText : tempText.replaceAll(' c', '');
    final visibilityText = _formatNumber(current['visibility'], ' km');
    final windValue = _parseDouble(current['wind']);
    final wavesText = _waveRange(windValue);
    final galeText = _galeStatus(windValue);
    final coastalText = _coastalWaterText(windValue);

    final metrics = <Map<String, Object>>[
      {
        'icon': Icons.air_rounded,
        'label': 'Wind',
        'value': windText,
        'accent': const Color(0xFF2876F7),
      },
      {
        'icon': Icons.water_drop_rounded,
        'label': 'Humidity',
        'value': humidityText,
        'accent': const Color(0xFF1A97AB),
      },
      {
        'icon': Icons.thermostat_rounded,
        'label': 'Temperature',
        'value': tempText.toUpperCase(),
        'accent': const Color(0xFFE56A54),
      },
      {
        'icon': Icons.visibility_rounded,
        'label': 'Visibility',
        'value': visibilityText,
        'accent': const Color(0xFF7C5CFA),
      },
      {
        'icon': Icons.waves_outlined,
        'label': 'Waves',
        'value': wavesText,
        'accent': const Color(0xFF0E7490),
      },
      {
        'icon': Icons.warning_amber_rounded,
        'label': 'Gale Warning',
        'value': galeText,
        'accent': const Color(0xFFB7791F),
      },
      {
        'icon': Icons.water,
        'label': 'Coastal Water',
        'value': coastalText,
        'accent': const Color(0xFF0F4C81),
      },
    ];

    return Scaffold(
      backgroundColor: _mist,
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFFE3F5FA),
              Color(0xFFF8FCFE),
            ],
          ),
        ),
        child: Stack(
          children: [
            const Positioned(
              top: -70,
              right: -40,
              child: _BackgroundOrb(
                size: 220,
                color: Color(0x3328A9C3),
              ),
            ),
            const Positioned(
              top: 160,
              left: -80,
              child: _BackgroundOrb(
                size: 240,
                color: Color(0x1A0D4D69),
              ),
            ),
            SafeArea(
              child: Center(
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: maxWidth),
                  child: RefreshIndicator(
                    onRefresh: _refresh,
                    color: _ocean,
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final horizontalPadding = Responsive.value<double>(
                          context,
                          mobile: 18,
                          tablet: 24,
                          desktop: 28,
                        );
                        final useMetricSlider = constraints.maxWidth < 720;
                        final metricColumns = constraints.maxWidth >= 920
                            ? 4
                            : constraints.maxWidth >= 620
                                ? 3
                                : 2;
                        final actionRow = constraints.maxWidth >= 720;

                        return SingleChildScrollView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          padding: EdgeInsets.fromLTRB(
                            horizontalPadding,
                            18,
                            horizontalPadding,
                            22,
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (_guardLoading)
                                const Padding(
                                  padding: EdgeInsets.only(bottom: 12),
                                  child: LinearProgressIndicator(minHeight: 2),
                                ),
                              _buildPageHeader(l),
                              if (_interactionLocked && !_guardLoading) ...[
                                const SizedBox(height: 18),
                                _lockBanner(),
                              ],
                              const SizedBox(height: 22),
                              _forecastHero(
                                context,
                                l,
                                tempValue: tempValue,
                              ),
                              const SizedBox(height: 24),
                              _surfaceCard(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    _sectionHeader(
                                      title: 'Marine Conditions',
                                      subtitle:
                                          'Operational readings pulled from the latest forecast snapshot.',
                                      trailing: Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 12,
                                          vertical: 8,
                                        ),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFFE9F6FB),
                                          borderRadius:
                                              BorderRadius.circular(999),
                                        ),
                                        child: Text(
                                          _loadingWeather ? 'Updating' : 'Live',
                                          style: const TextStyle(
                                            color: _ocean,
                                            fontWeight: FontWeight.w800,
                                          ),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 18),
                                    if (useMetricSlider)
                                      _metricSlider(
                                        context,
                                        metrics: metrics,
                                      )
                                    else
                                      GridView.builder(
                                        shrinkWrap: true,
                                        physics:
                                            const NeverScrollableScrollPhysics(),
                                        itemCount: metrics.length,
                                        gridDelegate:
                                            SliverGridDelegateWithFixedCrossAxisCount(
                                          crossAxisCount: metricColumns,
                                          crossAxisSpacing: 12,
                                          mainAxisSpacing: 12,
                                          mainAxisExtent: 152,
                                        ),
                                        itemBuilder: (context, index) {
                                          final item = metrics[index];
                                          return _metricCard(
                                            icon: item['icon'] as IconData,
                                            label: item['label'] as String,
                                            value: item['value'] as String,
                                            accentColor:
                                                item['accent'] as Color,
                                            valueFontSize:
                                                item['label'] ==
                                                        'Coastal Water'
                                                    ? 17
                                                    : 19,
                                          );
                                        },
                                      ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 24),
                              _sectionHeader(
                                title: 'Response Shortcuts',
                                subtitle:
                                    'Move from observation to action without leaving the command deck.',
                              ),
                              const SizedBox(height: 16),
                              _illegalReportsCard(l),
                              const SizedBox(height: 16),
                              if (actionRow)
                                IntrinsicHeight(
                                  child: Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      Expanded(
                                        child: _actionCard(
                                          icon: Icons.emergency_share_rounded,
                                          title: l.adminReportEmergency,
                                          subtitle:
                                              'Broadcast an urgent field incident and route it to the right responders.',
                                          colors: const [
                                            Color(0xFFE34D4D),
                                            Color(0xFFFF7A5C),
                                          ],
                                          onTap: () {
                                            Navigator.push(
                                              context,
                                              MaterialPageRoute(
                                                builder: (_) =>
                                                    const AdminReportEmergencyPage(),
                                              ),
                                            );
                                          },
                                        ),
                                      ),
                                      const SizedBox(width: 14),
                                      Expanded(
                                        child: _actionCard(
                                          icon: Icons.my_location_rounded,
                                          title: 'Share Location',
                                          subtitle:
                                              'Send your current coordinates to PCG for live coordination support.',
                                          colors: const [
                                            Color(0xFF0A335B),
                                            Color(0xFF0F6A86),
                                          ],
                                          onTap: () {
                                            Navigator.push(
                                              context,
                                              MaterialPageRoute(
                                                builder: (_) =>
                                                    const ShareLocationPage(
                                                  emergencyLevel: 'Safe',
                                                  notifyAll: false,
                                                ),
                                              ),
                                            );
                                          },
                                        ),
                                      ),
                                    ],
                                  ),
                                )
                              else ...[
                                _actionCard(
                                  icon: Icons.emergency_share_rounded,
                                  title: l.adminReportEmergency,
                                  subtitle:
                                      'Broadcast an urgent field incident and route it to the right responders.',
                                  colors: const [
                                    Color(0xFFE34D4D),
                                    Color(0xFFFF7A5C),
                                  ],
                                  onTap: () {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) =>
                                            const AdminReportEmergencyPage(),
                                      ),
                                    );
                                  },
                                ),
                                const SizedBox(height: 14),
                                _actionCard(
                                  icon: Icons.my_location_rounded,
                                  title: 'Share Location',
                                  subtitle:
                                      'Send your current coordinates to PCG for live coordination support.',
                                  colors: const [
                                    Color(0xFF0A335B),
                                    Color(0xFF0F6A86),
                                  ],
                                  onTap: () {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) =>
                                            const ShareLocationPage(
                                          emergencyLevel: 'Safe',
                                          notifyAll: false,
                                        ),
                                      ),
                                    );
                                  },
                                ),
                              ],
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BackgroundOrb extends StatelessWidget {
  const _BackgroundOrb({
    required this.size,
    required this.color,
  });

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: [
              color,
              color.withValues(alpha: 0),
            ],
          ),
        ),
      ),
    );
  }
}
