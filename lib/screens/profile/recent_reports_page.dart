import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class RecentReportsPage extends StatefulWidget {
  final String initialTab;

  const RecentReportsPage({super.key, this.initialTab = 'Reports'});

  @override
  State<RecentReportsPage> createState() => _RecentReportsPageState();
}

class _RecentReportsPageState extends State<RecentReportsPage> {
  late String _selectedTab;
  static const Color _ink = Color(0xFF102A43);
  static const Color _mutedInk = Color(0xFF5B7083);
  static const Color _surface = Color(0xFFF3F7FC);
  static const Color _surfaceRaised = Color(0xFFE3ECF7);
  static const Color _brand = Color(0xFF0E3764);

  @override
  void initState() {
    super.initState();
    _selectedTab = widget.initialTab;
  }

  Widget _buildEmptyState({
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 74,
              height: 74,
              decoration: BoxDecoration(
                color: const Color(0xFFE9F2FF),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Icon(icon, size: 36, color: _brand),
            ),
            const SizedBox(height: 16),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: _ink,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 14,
                color: _mutedInk,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Stream<QuerySnapshot> _getUserReports() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    return FirebaseFirestore.instance
        .collection('reports')
        .where('uid', isEqualTo: uid)
        .snapshots();
  }

  Stream<QuerySnapshot> _getUserSightings() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    return FirebaseFirestore.instance
        .collection('sightings')
        .where('userId', isEqualTo: uid)
        .snapshots();
  }

  String _formatDate(dynamic value) {
    if (value is Timestamp) {
      return DateFormat('yyyy-MM-dd HH:mm:ss').format(value.toDate());
    }
    if (value is DateTime) {
      return DateFormat('yyyy-MM-dd HH:mm:ss').format(value);
    }
    if (value is String && value.isNotEmpty) {
      final parsed = DateTime.tryParse(value);
      if (parsed != null) {
        return DateFormat('yyyy-MM-dd HH:mm:ss').format(parsed);
      }
      return value;
    }
    return 'No date';
  }

  DateTime _asDateTime(dynamic value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    if (value is String) {
      final parsed = DateTime.tryParse(value);
      if (parsed != null) return parsed;
    }
    return DateTime.fromMillisecondsSinceEpoch(0);
  }

  dynamic _bestSightingReportTimestamp(Map<String, dynamic> sighting) {
    return sighting['sightingAt'] ??
        sighting['sightingDateTime'] ??
        sighting['sightingDateTimeString'] ??
        sighting['manilaDateTime'] ??
        sighting['reportedAt'] ??
        sighting['createdAt'] ??
        sighting['manilaTimeString'] ??
        sighting['reportedTimeString'];
  }

  dynamic _bestReportIncidentTimestamp(Map<String, dynamic> report) {
    return report['incidentAt'] ??
        report['incidentDateTime'] ??
        report['incidentDateTimeString'] ??
        report['incidentDate'] ??
        report['occurredAt'] ??
        report['date'] ??
        report['submittedAt'];
  }

  double? _asDouble(dynamic value) {
    if (value is num) return value.toDouble();
    if (value is String && value.trim().isNotEmpty) {
      return double.tryParse(value.trim());
    }
    return null;
  }

  Future<String?> _resolveImageUrl(dynamic raw) async {
    if (raw == null) return null;
    final url = raw.toString();
    if (url.isEmpty) return null;
    final isWindowsPath = RegExp(r'^[A-Za-z]:[\\\\/]').hasMatch(url);
    if (url.startsWith('file://')) return url;
    if (url.startsWith('/') || isWindowsPath) return "file://$url";
    if (url.startsWith('data:image')) return url;
    if (url.startsWith('gs://')) {
      try {
        return await FirebaseStorage.instance.refFromURL(url).getDownloadURL();
      } catch (_) {
        return null;
      }
    }
    if (url.startsWith('http')) return url;
    try {
      return await FirebaseStorage.instance.ref(url).getDownloadURL();
    } catch (_) {
      return null;
    }
  }

  ImageProvider<Object>? _providerFromResolved(String resolved) {
    try {
      if (resolved.startsWith('data:image')) {
        final parts = resolved.split(',');
        final b64 = parts.length > 1
            ? parts[1]
            : parts.first.replaceFirst('data:image/jpeg;base64,', '');
        final bytes = base64Decode(b64);
        return MemoryImage(bytes);
      }
      if (resolved.startsWith('file://')) {
        return FileImage(File(resolved.replaceFirst('file://', '')));
      }
      return NetworkImage(resolved);
    } catch (_) {
      return null;
    }
  }

  void _openImageViewer(
    BuildContext context,
    List<String> sources,
    int initialIndex,
    String heroTag,
  ) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _ImageGalleryView(
          sources: sources,
          initialIndex: initialIndex,
          heroTag: heroTag,
          resolveImage: _resolveImageUrl,
          providerFromResolved: _providerFromResolved,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tabSelected = _selectedTab == 'Reports';
    return Scaffold(
      backgroundColor: _surface,
      appBar: AppBar(
        title: const Text(
          "Recent Reports",
          style: TextStyle(
            fontWeight: FontWeight.w900,
            fontSize: 31,
            letterSpacing: 0.2,
            color: _ink,
          ),
        ),
        leading: const BackButton(),
        backgroundColor: _surface,
        foregroundColor: _ink,
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: _surfaceRaised,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: () => setState(() => _selectedTab = 'Reports'),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        curve: Curves.easeOutCubic,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        decoration: BoxDecoration(
                          color: tabSelected ? _brand : Colors.transparent,
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: tabSelected
                              ? [
                                  BoxShadow(
                                    color: _brand.withValues(alpha: 0.24),
                                    blurRadius: 10,
                                    offset: const Offset(0, 4),
                                  ),
                                ]
                              : null,
                        ),
                        child: Text(
                          'Reports',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            color: tabSelected ? Colors.white : _ink,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: () => setState(() => _selectedTab = 'Sightings'),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        curve: Curves.easeOutCubic,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        decoration: BoxDecoration(
                          color: !tabSelected ? _brand : Colors.transparent,
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: !tabSelected
                              ? [
                                  BoxShadow(
                                    color: _brand.withValues(alpha: 0.24),
                                    blurRadius: 10,
                                    offset: const Offset(0, 4),
                                  ),
                                ]
                              : null,
                        ),
                        child: Text(
                          'Sightings',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            color: !tabSelected ? Colors.white : _ink,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              child: _selectedTab == 'Reports'
                  ? _buildReportsList()
                  : _buildSightingsList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildReportsList() {
    return StreamBuilder<QuerySnapshot>(
      stream: _getUserReports(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                "Couldn't load reports: ${snapshot.error}",
                textAlign: TextAlign.center,
              ),
            ),
          );
        }
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return _buildEmptyState(
            icon: Icons.report_gmailerrorred_rounded,
            title: 'No reports yet',
            subtitle: 'Your submitted reports will appear here.',
          );
        }

        final reports = snapshot.data!.docs.toList()
          ..sort((a, b) {
            final aData = a.data() as Map<String, dynamic>;
            final bData = b.data() as Map<String, dynamic>;
            final aTs = aData['submittedAt'] is Timestamp
                ? (aData['submittedAt'] as Timestamp).toDate()
                : DateTime.tryParse("${aData['date'] ?? ''}") ??
                      DateTime.fromMillisecondsSinceEpoch(0);
            final bTs = bData['submittedAt'] is Timestamp
                ? (bData['submittedAt'] as Timestamp).toDate()
                : DateTime.tryParse("${bData['date'] ?? ''}") ??
                      DateTime.fromMillisecondsSinceEpoch(0);
            return bTs.compareTo(aTs);
          });

        return ListView.builder(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
          itemCount: reports.length,
          itemBuilder: (context, index) {
            final data = reports[index].data() as Map<String, dynamic>;
            final title = data['title'] ?? 'Untitled report';
            final location = data['location'] ?? 'Unknown location';
            final date = _formatDate(_bestReportIncidentTimestamp(data));
            final description = data['description'] ?? 'No description';
            final imagesRaw =
                data['photoUrls'] ??
                data['photo_urls'] ??
                data['localImagePath'] ??
                data['imageUrl'];
            final status = (data['status'] ?? data['actionStatus'] ?? 'Pending')
                .toString();
            final double? lat = _asDouble(data['latitude'] ?? data['lat']);
            final double? lng = _asDouble(
              data['longitude'] ?? data['lng'] ?? data['long'],
            );

            return _ReportCard(
              title: title.toString(),
              location: location.toString(),
              date: date,
              description: description.toString(),
              status: status,
              dateLabel: 'Incident',
              imagesRaw: imagesRaw,
              resolveImage: _resolveImageUrl,
              providerFromResolved: _providerFromResolved,
              onTapImage: (index, sources, heroTag) =>
                  _openImageViewer(context, sources, index, heroTag),
              latitude: lat,
              longitude: lng,
              onUpdate: null,
            );
          },
        );
      },
    );
  }

  Widget _buildSightingsList() {
    return StreamBuilder<QuerySnapshot>(
      stream: _getUserSightings(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                "Couldn't load sightings: ${snapshot.error}",
                textAlign: TextAlign.center,
              ),
            ),
          );
        }
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return _buildEmptyState(
            icon: Icons.visibility_outlined,
            title: 'No sightings yet',
            subtitle: 'Your verified sightings will appear in this tab.',
          );
        }

        final sightings = snapshot.data!.docs.toList()
          ..sort((a, b) {
            final aData = a.data() as Map<String, dynamic>;
            final bData = b.data() as Map<String, dynamic>;
            final aTs = _asDateTime(_bestSightingReportTimestamp(aData));
            final bTs = _asDateTime(_bestSightingReportTimestamp(bData));
            return bTs.compareTo(aTs);
          });

        return ListView.builder(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
          itemCount: sightings.length,
          itemBuilder: (context, index) {
            final data = sightings[index].data() as Map<String, dynamic>;
            final title = (data['species'] ?? data['title'] ?? 'Sighting')
                .toString();
            final location =
                (data['location'] ?? data['address'] ?? 'Unknown location')
                    .toString();
            final description =
                (data['bfarNotes'] ?? data['notes'] ?? 'No notes').toString();
            final date = _formatDate(_bestSightingReportTimestamp(data));
            final status = (data['decision'] ?? data['status'] ?? 'Pending')
                .toString();
            final imagesRaw = data['imageUrls'] ?? data['imageUrl'];
            final double? lat = _asDouble(data['latitude'] ?? data['lat']);
            final double? lng = _asDouble(
              data['longitude'] ?? data['lng'] ?? data['long'],
            );

            return _ReportCard(
              title: title,
              location: location,
              date: date,
              description: description,
              status: status,
              dateLabel: 'Sighting',
              imagesRaw: imagesRaw,
              resolveImage: _resolveImageUrl,
              providerFromResolved: _providerFromResolved,
              onTapImage: (index, sources, heroTag) =>
                  _openImageViewer(context, sources, index, heroTag),
              latitude: lat,
              longitude: lng,
              onUpdate: null,
            );
          },
        );
      },
    );
  }
}

class _ReportCard extends StatelessWidget {
  final String title;
  final String location;
  final String date;
  final String description;
  final String status;
  final String dateLabel;
  final dynamic imagesRaw;
  final Future<String?> Function(dynamic) resolveImage;
  final ImageProvider<Object>? Function(String) providerFromResolved;
  final void Function(int index, List<String> sources, String heroTag)
  onTapImage;
  final VoidCallback? onUpdate;
  final double? latitude;
  final double? longitude;

  const _ReportCard({
    required this.title,
    required this.location,
    required this.date,
    required this.description,
    required this.status,
    this.dateLabel = 'Date',
    required this.imagesRaw,
    required this.resolveImage,
    required this.providerFromResolved,
    required this.onTapImage,
    this.onUpdate,
    this.latitude,
    this.longitude,
  });

  ({Color bg, Color fg, Color border}) _statusStyle(String value) {
    final lower = value.toLowerCase();
    if (lower.contains('resolv') || lower.contains('close')) {
      return (
        bg: const Color(0xFFE6F4EA),
        fg: const Color(0xFF1E7D3A),
        border: const Color(0xFFBDE3C5),
      );
    }
    if (lower.contains('dispatch')) {
      return (
        bg: const Color(0xFFFFF7CC),
        fg: const Color(0xFF8A6D1F),
        border: const Color(0xFFF2E5A8),
      );
    }
    if (lower.contains('ack')) {
      return (
        bg: const Color(0xFFD9E8FB),
        fg: const Color(0xFF2D5F9A),
        border: const Color(0xFFBFD5F2),
      );
    }
    if (lower.contains('reject') || lower.contains('declin')) {
      return (
        bg: const Color(0xFFFDE8E8),
        fg: const Color(0xFFB42318),
        border: const Color(0xFFF6CCCC),
      );
    }
    return (
      bg: const Color(0xFFE5E9F0),
      fg: const Color(0xFF334E68),
      border: const Color(0xFFD0D8E4),
    );
  }

  List<String> _normalizedImages(dynamic raw) {
    if (raw == null) return [];
    if (raw is List) {
      return raw
          .where((e) => e != null && e.toString().trim().isNotEmpty)
          .map((e) => e.toString())
          .toList();
    }
    final single = raw.toString().trim();
    return single.isEmpty ? [] : [single];
  }

  @override
  Widget build(BuildContext context) {
    final statusColors = _statusStyle(status);
    final images = _normalizedImages(imagesRaw);

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFD8E6F4)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF102A43).withValues(alpha: 0.06),
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 20,
                    color: Color(0xFF102A43),
                    height: 1.1,
                  ),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 2,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: statusColors.bg,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: statusColors.border),
                ),
                child: Text(
                  status.isEmpty ? 'Pending' : status,
                  style: TextStyle(
                    color: statusColors.fg,
                    fontWeight: FontWeight.w700,
                    fontSize: 12.5,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 26,
                height: 26,
                decoration: BoxDecoration(
                  color: const Color(0xFFEAF3FF),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.place,
                  size: 16,
                  color: Color(0xFF1D5B8E),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  location,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF243B53),
                    height: 1.2,
                  ),
                ),
              ),
            ],
          ),
          if (latitude != null && longitude != null) ...[
            const SizedBox(height: 4),
            Text(
              'Coordinates: ${latitude!.toStringAsFixed(5)}, ${longitude!.toStringAsFixed(5)}',
              style: const TextStyle(
                fontSize: 13.2,
                color: Color(0xFF486581),
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
          const SizedBox(height: 8),
          Text(
            description,
            style: const TextStyle(
              fontSize: 14.5,
              color: Color(0xFF334E68),
              height: 1.3,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              const Icon(
                Icons.calendar_today,
                size: 16,
                color: Color(0xFF627D98),
              ),
              const SizedBox(width: 6),
              Text(
                dateLabel.isEmpty ? date : '$dateLabel: $date',
                style: const TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF486581),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (images.isNotEmpty)
            SizedBox(
              height: 76,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: images.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (context, index) {
                  final source = images[index];
                  return FutureBuilder<String?>(
                    future: resolveImage(source),
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return Container(
                          width: 96,
                          decoration: BoxDecoration(
                            color: const Color(0xFFF3F7FC),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: const Color(0xFFD8E6F4)),
                          ),
                          alignment: Alignment.center,
                          child: const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        );
                      }
                      final resolved = snapshot.data;
                      if (resolved == null || resolved.isEmpty) {
                        return Container(
                          width: 96,
                          decoration: BoxDecoration(
                            color: const Color(0xFFF3F7FC),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: const Color(0xFFD8E6F4)),
                          ),
                          alignment: Alignment.center,
                          child: const Icon(
                            Icons.image_not_supported,
                            color: Colors.grey,
                          ),
                        );
                      }
                      final provider = providerFromResolved(resolved);
                      if (provider == null) {
                        return Container(
                          width: 96,
                          decoration: BoxDecoration(
                            color: const Color(0xFFF3F7FC),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: const Color(0xFFD8E6F4)),
                          ),
                          alignment: Alignment.center,
                          child: const Icon(
                            Icons.image_not_supported,
                            color: Colors.grey,
                          ),
                        );
                      }
                      final heroTag = 'recent-report-img-$source-$index';
                      return GestureDetector(
                        onTap: () => onTapImage(index, images, heroTag),
                        child: Hero(
                          tag: heroTag,
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(10),
                            child: Image(
                              image: provider,
                              width: 96,
                              height: 76,
                              fit: BoxFit.cover,
                              errorBuilder: (context, error, stackTrace) =>
                                  const Icon(
                                    Icons.broken_image,
                                    color: Colors.grey,
                                  ),
                            ),
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          const SizedBox(height: 10),
          if (onUpdate != null)
            Align(
              alignment: Alignment.centerRight,
              child: SizedBox(
                height: 36,
                child: ElevatedButton(
                  onPressed: onUpdate,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1F2A44),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 18),
                    elevation: 0,
                  ),
                  child: const Text(
                    'Update',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _ImageGalleryView extends StatefulWidget {
  final List<String> sources;
  final int initialIndex;
  final String heroTag;
  final Future<String?> Function(dynamic) resolveImage;
  final ImageProvider<Object>? Function(String) providerFromResolved;

  const _ImageGalleryView({
    required this.sources,
    required this.initialIndex,
    required this.heroTag,
    required this.resolveImage,
    required this.providerFromResolved,
  });

  @override
  State<_ImageGalleryView> createState() => _ImageGalleryViewState();
}

class _ImageGalleryViewState extends State<_ImageGalleryView> {
  late final PageController _controller;
  late int _currentIndex;

  @override
  void initState() {
    super.initState();
    final start = widget.sources.isEmpty
        ? 0
        : widget.initialIndex.clamp(0, widget.sources.length - 1);
    _currentIndex = start.toInt();
    _controller = PageController(initialPage: _currentIndex);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            if (widget.sources.isEmpty)
              const Center(
                child: Text(
                  'No images available',
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              )
            else
              PageView.builder(
                controller: _controller,
                onPageChanged: (index) => setState(() => _currentIndex = index),
                itemCount: widget.sources.length,
                itemBuilder: (context, index) {
                  final source = widget.sources[index];
                  return FutureBuilder<String?>(
                    future: widget.resolveImage(source),
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return const Center(
                          child: CircularProgressIndicator(
                            color: Colors.white70,
                            strokeWidth: 2,
                          ),
                        );
                      }
                      if (snapshot.hasError) {
                        return Center(
                          child: Text(
                            'Could not load image',
                            style: const TextStyle(
                              color: Colors.white70,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        );
                      }
                      final resolved = snapshot.data;
                      if (resolved == null || resolved.isEmpty) {
                        return const Center(
                          child: Text(
                            'No image found',
                            style: TextStyle(
                              color: Colors.white70,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        );
                      }
                      final provider = widget.providerFromResolved(resolved);
                      if (provider == null) {
                        return const Center(
                          child: Text(
                            'Unsupported image',
                            style: TextStyle(
                              color: Colors.white70,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        );
                      }

                      final image = InteractiveViewer(
                        minScale: 0.8,
                        maxScale: 4.0,
                        child: Image(
                          image: provider,
                          fit: BoxFit.contain,
                          width: double.infinity,
                          height: double.infinity,
                        ),
                      );

                      final useHero = index == widget.initialIndex;
                      Widget child = image;
                      if (useHero) {
                        child = HeroMode(
                          enabled: index == _currentIndex,
                          child: Hero(tag: widget.heroTag, child: image),
                        );
                      }

                      return Center(child: child);
                    },
                  );
                },
              ),
            Positioned(
              top: 12,
              left: 12,
              child: CircleAvatar(
                backgroundColor: Colors.black54,
                child: IconButton(
                  icon: const Icon(Icons.close, color: Colors.white),
                  onPressed: () => Navigator.pop(context),
                ),
              ),
            ),
            if (widget.sources.length > 1)
              Positioned(
                bottom: 20,
                left: 0,
                right: 0,
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      '${_currentIndex + 1}/${widget.sources.length}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
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
