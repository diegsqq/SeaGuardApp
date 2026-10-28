import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../utils/responsive.dart';

class AdminEmergencyReportDetailsPage extends StatelessWidget {
  final Map<String, dynamic> notification;

  const AdminEmergencyReportDetailsPage({
    super.key,
    required this.notification,
  });

  double? _tryDouble(dynamic value) {
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value);
    return null;
  }

  String _formatTimestamp(dynamic timestamp) {
    if (timestamp is Timestamp) {
      final dt = timestamp.toDate().toLocal();
      final y = dt.year.toString().padLeft(4, '0');
      final m = dt.month.toString().padLeft(2, '0');
      final d = dt.day.toString().padLeft(2, '0');
      final hh = dt.hour.toString().padLeft(2, '0');
      final mm = dt.minute.toString().padLeft(2, '0');
      return '$y-$m-$d $hh:$mm';
    }
    return '';
  }

  String _emergencyLevel() {
    final direct = (notification['emergencyLevel'] ?? '').toString().trim();
    if (direct.isNotEmpty) return direct;

    final message = (notification['message'] ?? '').toString();
    final match = RegExp(r'Level:\s*([A-Za-z]+)', caseSensitive: false).firstMatch(message);
    return match?.group(1)?.trim() ?? '';
  }

  Color _levelColor(String level) {
    switch (level.toLowerCase()) {
      case 'danger':
        return Colors.red;
      case 'moderate':
        return Colors.orange;
      case 'safe':
        return Colors.green;
      default:
        return Colors.blueGrey;
    }
  }

  String _locationLabel() {
    final direct = (notification['locationLabel'] ?? '').toString().trim();
    if (direct.isNotEmpty) return direct;

    final message = (notification['message'] ?? '').toString();
    final match = RegExp(r'Location:\s*(.+)$', caseSensitive: false).firstMatch(message);
    return match?.group(1)?.trim() ?? '';
  }

  Future<void> _openMap(BuildContext context) async {
    final mapUrlRaw = (notification['mapUrl'] ?? '').toString().trim();
    final lat = _tryDouble(notification['lat']);
    final lng = _tryDouble(notification['lng']);

    final url = mapUrlRaw.isNotEmpty
        ? mapUrlRaw
        : (lat != null && lng != null ? 'https://www.google.com/maps?q=$lat,$lng' : '');

    if (url.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No map location available for this report.')),
      );
      return;
    }

    final uri = Uri.tryParse(url);
    if (uri == null) return;
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open the map link.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final padding = Responsive.pagePadding(context);
    final maxWidth = Responsive.maxContentWidth(context);
    final title = (notification['title'] ?? 'Emergency Report').toString();
    final message = (notification['message'] ?? '').toString();
    final reporterName = (notification['reporterName'] ?? notification['reporterLabel'] ?? '').toString();
    final reporterId = (notification['reporterId'] ?? '').toString();
    final level = _emergencyLevel();
    final levelColor = _levelColor(level);
    final location = _locationLabel();
    final time = _formatTimestamp(notification['timestamp']);
    final lat = _tryDouble(notification['lat']);
    final lng = _tryDouble(notification['lng']);

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0.6,
        title: const Text(
          'Emergency Report',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxWidth),
            child: Padding(
              padding: EdgeInsets.all(padding),
              child: Column(
                children: [
                  Expanded(
                    child: SingleChildScrollView(
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: Colors.grey.shade300),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.04),
                              blurRadius: 8,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                  decoration: BoxDecoration(
                                    color: levelColor.withOpacity(0.12),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Text(
                                    level.isNotEmpty ? level : 'Emergency',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w800,
                                      color: levelColor,
                                    ),
                                  ),
                                ),
                                const Spacer(),
                                if (time.isNotEmpty)
                                  Text(
                                    time,
                                    style: const TextStyle(
                                      fontSize: 12,
                                      color: Colors.black54,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Text(
                              title,
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            if (reporterName.isNotEmpty || reporterId.isNotEmpty) ...[
                              const SizedBox(height: 6),
                              Text(
                                'Reported by: ${reporterName.isNotEmpty ? reporterName : reporterId}',
                                style: const TextStyle(
                                  fontSize: 13,
                                  color: Colors.black87,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                            if (location.isNotEmpty) ...[
                              const SizedBox(height: 10),
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Icon(Icons.location_on_outlined, size: 18, color: Colors.black87),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      location,
                                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                            if (lat != null && lng != null) ...[
                              const SizedBox(height: 8),
                              Text(
                                'Coordinates: ${lat.toStringAsFixed(5)}, ${lng.toStringAsFixed(5)}',
                                style: const TextStyle(
                                  fontSize: 12.5,
                                  color: Colors.black54,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                            if (message.isNotEmpty) ...[
                              const SizedBox(height: 12),
                              Text(
                                message,
                                style: const TextStyle(fontSize: 14, color: Colors.black87),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton.icon(
                      onPressed: () => _openMap(context),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF1E2D52),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                      icon: const Icon(Icons.map_outlined),
                      label: const Text(
                        'Open Map',
                        style: TextStyle(fontWeight: FontWeight.w800),
                      ),
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
}
