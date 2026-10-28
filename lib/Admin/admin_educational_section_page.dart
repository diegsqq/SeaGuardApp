import 'dart:convert';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import '../l10n/app_localizations.dart';
import '../utils/responsive.dart';

class AdminEducationalSectionPage extends StatefulWidget {
  final String? initialCategory;
  const AdminEducationalSectionPage({super.key, this.initialCategory});

  @override
  State<AdminEducationalSectionPage> createState() => _AdminEducationalSectionPageState();
}

class _AdminEducationalSectionPageState extends State<AdminEducationalSectionPage> {
  static const String _videoCategory = 'Video & Infographics Section';
  static const Color _pageTop = Color(0xFFE8F4FF);
  static const Color _pageBottom = Color(0xFFF7FCFF);
  static const Color _ink = Color(0xFF102A43);
  static const Color _subtleInk = Color(0xFF486581);
  static const Color _cardBorder = Color(0xFFD8E4F0);
  static const Color _activeStart = Color(0xFF124F8A);

  String? _selectedCategory;
  final Map<String, Future<String?>> _storageUrlCache = {};

  @override
  void initState() {
    super.initState();
    _selectedCategory = widget.initialCategory?.trim();
  }

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

  String _formatDate(dynamic value) {
    try {
      if (value is Timestamp) {
        return DateFormat('MMM dd, yyyy').format(value.toDate());
      }
      if (value is DateTime) {
        return DateFormat('MMM dd, yyyy').format(value);
      }
      if (value is String && value.isNotEmpty) {
        return DateFormat('MMM dd, yyyy').format(DateTime.parse(value));
      }
    } catch (_) {}
    return '';
  }

  DateTime _parseDate(dynamic value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    if (value is String && value.isNotEmpty) {
      return DateTime.tryParse(value) ?? DateTime.fromMillisecondsSinceEpoch(0);
    }
    return DateTime.fromMillisecondsSinceEpoch(0);
  }

  String _normalizeYoutubeId(dynamic value) {
    final raw = (value ?? '').toString().trim();
    if (raw.isEmpty) return '';
    final uri = Uri.tryParse(raw);
    if (uri == null) return raw;
    if (uri.host.contains('youtube.com')) {
      final watchId = uri.queryParameters['v'];
      if (watchId != null && watchId.isNotEmpty) return watchId;
    }
    if (uri.host.contains('youtu.be') && uri.pathSegments.isNotEmpty) {
      return uri.pathSegments.first;
    }
    return raw;
  }

  String _cleanText(dynamic value) {
    final text = (value ?? '').toString().trim();
    if (text.isEmpty) return '';
    switch (text.toLowerCase()) {
      case 'undefined':
      case 'null':
      case 'n/a':
      case 'na':
      case 'none':
      case 'nil':
        return '';
      default:
        return text;
    }
  }

  Uint8List? _bytesFromDataUrl(String value) {
    try {
      final commaIndex = value.indexOf(',');
      if (commaIndex == -1) return null;
      return base64Decode(value.substring(commaIndex + 1));
    } catch (_) {
      return null;
    }
  }

  ImageProvider<Object>? _imageProviderFromResolved(String resolved) {
    if (resolved.isEmpty) return null;
    if (resolved.startsWith('data:image')) {
      final bytes = _bytesFromDataUrl(resolved);
      if (bytes == null) return null;
      return MemoryImage(bytes);
    }
    if (resolved.startsWith('http://') || resolved.startsWith('https://')) {
      return NetworkImage(resolved);
    }
    return null;
  }

  bool _isLocalHost(String host) {
    final normalized = host.toLowerCase();
    return normalized == '127.0.0.1' ||
        normalized == 'localhost' ||
        normalized == '0.0.0.0';
  }

  List<String> _candidateStoragePathsFromRaw(String raw) {
    final trimmed = _cleanText(raw);
    if (trimmed.isEmpty) return const [];
    if (trimmed.startsWith('gs://')) return [trimmed];

    final uri = Uri.tryParse(trimmed);
    if (uri == null) return const [];

    if (uri.scheme.isEmpty && uri.host.isEmpty) {
      return [trimmed.replaceAll('\\', '/')];
    }

    final segments = uri.pathSegments;
    final storageIndex = segments.indexOf('storage');
    if (storageIndex != -1 && storageIndex + 1 < segments.length) {
      final relative = segments.sublist(storageIndex + 1).join('/');
      if (relative.isNotEmpty) {
        return [relative];
      }
    }

    return const [];
  }

  bool _isVideoResource(Map<String, dynamic> post) {
    final youtubeId = _normalizeYoutubeId(post['youtubeId']);
    final type = (post['type'] ?? '').toString().toLowerCase();
    return youtubeId.isNotEmpty || type == 'video';
  }

  bool _looksLikeImageReference(String raw) {
    final trimmed = _cleanText(raw).toLowerCase();
    if (trimmed.isEmpty) return false;
    if (trimmed.startsWith('data:image')) return true;
    final withoutQuery = trimmed.split('?').first;
    return RegExp(r'\.(png|jpe?g|gif|webp|bmp|svg)$').hasMatch(withoutQuery);
  }

  Future<String?> _getStorageUrl(String primary, List<String> fallbacks) {
    final cacheKey = [primary, ...fallbacks].join('|');
    if (_storageUrlCache.containsKey(cacheKey)) {
      return _storageUrlCache[cacheKey]!;
    }

    final future = () async {
      for (final candidate in [primary, ...fallbacks]) {
        final url = await _tryStoragePath(candidate);
        if (url != null && url.isNotEmpty) return url;
      }
      return null;
    }();

    _storageUrlCache[cacheKey] = future;
    return future;
  }

  Future<String?> _tryStoragePath(String path) async {
    if (path.isEmpty) return null;
    try {
      final ref = path.startsWith('gs://')
          ? FirebaseStorage.instance.refFromURL(path)
          : FirebaseStorage.instance.ref(path);
      return await ref.getDownloadURL();
    } catch (_) {
      return null;
    }
  }

  Future<String?> _resolveAttachmentUrl(String raw) async {
    final trimmed = _cleanText(raw);
    if (trimmed.isEmpty) return null;
    if (trimmed.startsWith('data:image')) return trimmed;

    if (trimmed.startsWith('gs://')) {
      return _getStorageUrl(trimmed, const []);
    }

    final storageCandidates = _candidateStoragePathsFromRaw(trimmed);
    if (storageCandidates.isNotEmpty) {
      final storageUrl = await _getStorageUrl(
        storageCandidates.first,
        storageCandidates.skip(1).toList(),
      );
      if (storageUrl != null && storageUrl.isNotEmpty) return storageUrl;
    }

    final uri = Uri.tryParse(trimmed);
    if (uri == null) return null;
    if (uri.hasScheme && (uri.scheme == 'http' || uri.scheme == 'https')) {
      if (_isLocalHost(uri.host) &&
          !kIsWeb &&
          defaultTargetPlatform == TargetPlatform.android) {
        return uri.replace(host: '10.0.2.2').toString();
      }
      return uri.toString();
    }

    if (!trimmed.contains('://')) {
      return _getStorageUrl(trimmed.replaceAll('\\', '/'), const []);
    }

    return null;
  }

  String _primaryLink(Map<String, dynamic> post) {
    final youtubeId = _normalizeYoutubeId(post['youtubeId']);
    if (youtubeId.isNotEmpty) {
      return 'https://www.youtube.com/watch?v=$youtubeId';
    }
    final pdfUrl = _cleanText(post['pdfUrl']);
    if (pdfUrl.isNotEmpty) return pdfUrl;
    return _cleanText(post['image']);
  }

  String _primaryImage(Map<String, dynamic> post) {
    return _cleanText(post['image']);
  }

  bool _hasPdfAttachment(Map<String, dynamic> post) {
    return _cleanText(post['pdfUrl']).isNotEmpty;
  }

  String _primaryActionLabel(Map<String, dynamic> post) {
    final youtubeId = _normalizeYoutubeId(post['youtubeId']);
    final pdfUrl = _cleanText(post['pdfUrl']);
    final imageUrl = _cleanText(post['image']);
    final type = _cleanText(post['type']).toLowerCase();
    if (youtubeId.isNotEmpty) return 'Open Video';
    if (imageUrl.isNotEmpty && pdfUrl.isEmpty) return 'View Image';
    if (pdfUrl.isNotEmpty &&
        (type == 'pdf' || pdfUrl.toLowerCase().contains('.pdf'))) {
      return 'View PDF';
    }
    if (pdfUrl.isNotEmpty) return 'Open File';
    if (imageUrl.isNotEmpty) return 'View Image';
    return 'Open Attachment';
  }

  IconData _primaryActionIcon(Map<String, dynamic> post) {
    final youtubeId = _normalizeYoutubeId(post['youtubeId']);
    final pdfUrl = _cleanText(post['pdfUrl']);
    final imageUrl = _cleanText(post['image']);
    if (youtubeId.isNotEmpty) return Icons.play_circle_fill_rounded;
    if (imageUrl.isNotEmpty && pdfUrl.isEmpty) return Icons.image_rounded;
    if (pdfUrl.isNotEmpty && pdfUrl.toLowerCase().contains('.pdf')) {
      return Icons.picture_as_pdf_rounded;
    }
    if (pdfUrl.isNotEmpty) return Icons.attach_file_rounded;
    if (imageUrl.isNotEmpty) return Icons.image_rounded;
    return Icons.open_in_new_rounded;
  }

  String _secondaryFileLabel(String url) {
    return url.toLowerCase().contains('.pdf') ? 'View PDF' : 'Open File';
  }

  IconData _secondaryFileIcon(String url) {
    return url.toLowerCase().contains('.pdf')
        ? Icons.picture_as_pdf_rounded
        : Icons.attach_file_rounded;
  }

  String _resourceTypeLabel(Map<String, dynamic> post) {
    if (_normalizeYoutubeId(post['youtubeId']).isNotEmpty) return 'VIDEO';
    final type = (post['type'] ?? '').toString().trim();
    if (type.isEmpty) return 'DOC';
    return type.toUpperCase();
  }

  IconData _categoryIcon(String category) {
    final key = category.toLowerCase();
    if (key.contains('law') ||
        key.contains('circular') ||
        key.contains('policy')) {
      return Icons.gavel_rounded;
    }
    if (key.contains('sustainable') ||
        key.contains('conservation') ||
        key.contains('environment')) {
      return Icons.eco_rounded;
    }
    if (key.contains('safety') || key.contains('advisory')) {
      return Icons.shield_rounded;
    }
    if (key.contains('video') || key.contains('infographic')) {
      return Icons.play_circle_fill_rounded;
    }
    return Icons.menu_book_rounded;
  }

  Future<void> _openExternal(BuildContext context, String url) async {
    final resolved = await _resolveAttachmentUrl(url);
    if (resolved == null || resolved.isEmpty) return;

    if (_looksLikeImageReference(resolved)) {
      final provider = _imageProviderFromResolved(resolved);
      if (provider != null && context.mounted) {
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => _AdminAttachmentImagePage(provider: provider),
          ),
        );
        return;
      }
    }

    final uri = Uri.tryParse(resolved);
    if (uri == null) return;

    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open link')),
      );
    }
  }

  Widget _buildBfarPostCard(BuildContext context, Map<String, dynamic> post) {
    final title = (post['title'] ?? '').toString().trim();
    final description =
        (post['description'] ?? post['content'] ?? '').toString().trim();
    final categoryName = (post['categoryName'] ?? '').toString().trim();
    final updatedAt = _formatDate(post['updatedAt'] ?? post['createdAt']);
    final imageUrl = _primaryImage(post);
    final youtubeId = _normalizeYoutubeId(post['youtubeId']);
    final hasPreviewMedia = imageUrl.isNotEmpty || youtubeId.isNotEmpty;
    final primaryLink = _primaryLink(post);
    final typeLabel = _resourceTypeLabel(post);
    final hasPdfAttachment = _hasPdfAttachment(post);
    final pdfUrl = _cleanText(post['pdfUrl']);

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Colors.white, Color(0xFFF6FAFF)],
        ),
        border: Border.all(color: _cardBorder),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF8DA7C3).withValues(alpha: 0.12),
            blurRadius: 12,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (hasPreviewMedia)
            ClipRRect(
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(23),
              ),
              child: AspectRatio(
                aspectRatio: 16 / 9,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    _AdminPreviewMedia(
                      imageUrl: imageUrl,
                      youtubeId: youtubeId,
                      resolveAttachmentUrl: _resolveAttachmentUrl,
                      imageProviderFromResolved: _imageProviderFromResolved,
                    ),
                    Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.black.withValues(alpha: 0.16),
                            Colors.black.withValues(alpha: 0.44),
                          ],
                        ),
                      ),
                    ),
                    Positioned(
                      top: 12,
                      left: 12,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.18),
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(color: Colors.white30),
                        ),
                        child: Text(
                          typeLabel,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11.6,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (!hasPreviewMedia)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEAF1FF),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      typeLabel,
                      style: const TextStyle(
                        color: Color(0xFF124F8A),
                        fontSize: 11.6,
                        fontWeight: FontWeight.w800,
                      ),
                      ),
                    ),
                if (categoryName.isNotEmpty || updatedAt.isNotEmpty) ...[
                  if (!hasPreviewMedia) const SizedBox(height: 10),
                  Row(
                    children: [
                      if (categoryName.isNotEmpty)
                        Expanded(
                          child: Text(
                            categoryName,
                            style: const TextStyle(
                              color: _subtleInk,
                              fontWeight: FontWeight.w700,
                              fontSize: 12.2,
                            ),
                          ),
                        ),
                      if (updatedAt.isNotEmpty)
                        Text(
                          updatedAt,
                          style: const TextStyle(
                            color: Color(0xFF627D98),
                            fontWeight: FontWeight.w700,
                            fontSize: 12,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                ],
                Text(
                  title.isNotEmpty ? title : 'Untitled Resource',
                  style: const TextStyle(
                    color: _ink,
                    fontWeight: FontWeight.w800,
                    fontSize: 17,
                    height: 1.2,
                  ),
                ),
                if (description.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    description,
                    style: const TextStyle(
                      color: _subtleInk,
                      fontSize: 13.2,
                      height: 1.48,
                    ),
                  ),
                ],
                const SizedBox(height: 14),
                if (primaryLink.isNotEmpty)
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: () => _openExternal(context, primaryLink),
                      icon: Icon(_primaryActionIcon(post), size: 20),
                      label: Text(_primaryActionLabel(post)),
                      style: FilledButton.styleFrom(
                        backgroundColor: _activeStart,
                        foregroundColor: Colors.white,
                        minimumSize: const Size(double.infinity, 48),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                    ),
                  ),
                if (hasPdfAttachment && imageUrl.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () => _openExternal(context, pdfUrl),
                      icon: Icon(_secondaryFileIcon(pdfUrl), size: 20),
                      label: Text(_secondaryFileLabel(pdfUrl)),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFF102A43),
                        side: const BorderSide(color: Color(0xFFC5D5E6)),
                        backgroundColor: Colors.white,
                        minimumSize: const Size(double.infinity, 46),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        textStyle: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final padding = Responsive.pagePadding(context);
    final maxWidth = Responsive.maxContentWidth(context);

    return Scaffold(
      backgroundColor: _pageBottom,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        leadingWidth: 68,
        leading: Padding(
          padding: const EdgeInsets.only(left: 12),
          child: IconButton(
            style: IconButton.styleFrom(
              backgroundColor: Colors.white.withValues(alpha: 0.94),
              foregroundColor: _ink,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18),
            onPressed: () => Navigator.pop(context),
          ),
        ),
        centerTitle: true,
        title: Text(
          l.educationalSectionPageTitle,
          style: const TextStyle(
            color: _ink,
            fontFamily: 'serif',
            fontWeight: FontWeight.w800,
            fontSize: 24,
            letterSpacing: 0.2,
          ),
        ),
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
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: maxWidth),
              child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: FirebaseFirestore.instance
                    .collection('educational_resources')
                    .snapshots(),
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    return SingleChildScrollView(
                      padding: EdgeInsets.fromLTRB(
                        padding,
                        18,
                        padding,
                        padding,
                      ),
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(18),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.92),
                          borderRadius: BorderRadius.circular(22),
                          border: Border.all(color: _cardBorder),
                        ),
                        child: const Text(
                          'Failed to load educational resources.',
                          style: TextStyle(
                            color: Color(0xFFBA1A1A),
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    );
                  }

                  if (!snapshot.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  final posts = snapshot.data!.docs.map((doc) {
                    final data = doc.data();
                    return <String, dynamic>{
                      'id': doc.id,
                      'title': _cleanText(data['title']),
                      'description':
                          _cleanText(data['description']).isNotEmpty
                              ? _cleanText(data['description'])
                              : _cleanText(data['content']),
                      'content': _cleanText(data['content']),
                      'categoryName': _cleanText(data['categoryName']),
                      'type': _cleanText(data['type']),
                      'pdfUrl': _cleanText(data['pdfUrl']),
                      'youtubeId': data['youtubeId'],
                      'image': _cleanText(data['image']),
                      'createdAt': data['createdAt'] ?? data['created_at'],
                      'updatedAt': data['updatedAt'] ?? data['updated_at'],
                      'active': data['active'],
                      'archived': data['archived'],
                    };
                  }).where((post) {
                    return _isActive(post['active']) &&
                        !_isArchived(post['archived']);
                  }).toList()
                    ..sort((a, b) {
                      final ad = _parseDate(a['updatedAt'] ?? a['createdAt']);
                      final bd = _parseDate(b['updatedAt'] ?? b['createdAt']);
                      return bd.compareTo(ad);
                    });

                  final categoryCounts = <String, int>{};
                  var videoCount = 0;
                  for (final post in posts) {
                    final cat = (post['categoryName'] ?? '').toString().trim();
                    if (cat.isNotEmpty) {
                      categoryCounts[cat] = (categoryCounts[cat] ?? 0) + 1;
                    }
                    if (_isVideoResource(post)) {
                      videoCount++;
                    }
                  }

                  final sortedCats = categoryCounts.keys.toList()..sort();
                  if (videoCount > 0 && !sortedCats.contains(_videoCategory)) {
                    sortedCats.add(_videoCategory);
                  }

                  if (sortedCats.isEmpty) {
                    return SingleChildScrollView(
                      padding: EdgeInsets.fromLTRB(
                        padding,
                        18,
                        padding,
                        padding,
                      ),
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(18),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.92),
                          borderRadius: BorderRadius.circular(22),
                          border: Border.all(color: _cardBorder),
                        ),
                        child: const Text(
                          'No educational resources available yet.',
                          style: TextStyle(
                            color: _subtleInk,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    );
                  }

                  if (_selectedCategory == null ||
                      _selectedCategory!.isEmpty ||
                      !sortedCats.contains(_selectedCategory)) {
                    _selectedCategory = sortedCats.first;
                  }

                  final filtered = _selectedCategory == _videoCategory
                      ? posts.where(_isVideoResource).toList()
                      : posts
                          .where(
                            (post) =>
                                (post['categoryName'] ?? '')
                                    .toString()
                                    .trim() ==
                                _selectedCategory,
                          )
                          .toList();

                  final latestDate = filtered.isEmpty
                      ? ''
                      : _formatDate(
                          filtered.first['updatedAt'] ?? filtered.first['createdAt'],
                        );
                  final selectedIcon = _categoryIcon(_selectedCategory ?? '');
                  final selectedCount = filtered.length;

                  return SingleChildScrollView(
                    padding: EdgeInsets.fromLTRB(
                      padding,
                      18,
                      padding,
                      padding,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          padding: const EdgeInsets.fromLTRB(20, 20, 20, 18),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(28),
                            gradient: const LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [Color(0xFF0F365A), Color(0xFF1D76B8)],
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: const Color(0xFF0F365A).withValues(
                                  alpha: 0.28,
                                ),
                                blurRadius: 24,
                                offset: const Offset(0, 12),
                              ),
                            ],
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Container(
                                    width: 48,
                                    height: 48,
                                    decoration: BoxDecoration(
                                      color: Colors.white.withValues(alpha: 0.16),
                                      borderRadius: BorderRadius.circular(15),
                                      border: Border.all(color: Colors.white24),
                                    ),
                                    child: Icon(
                                      selectedIcon,
                                      color: Colors.white,
                                      size: 26,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Text(
                                      _selectedCategory ?? l.educationalSectionPageTitle,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontFamily: 'serif',
                                        fontWeight: FontWeight.w800,
                                        fontSize: 24,
                                        height: 1.08,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              Text(
                                'Browse the current learning materials, PDFs, and visual explainers published for this topic.',
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.9),
                                  fontSize: 13.4,
                                  height: 1.48,
                                ),
                              ),
                              const SizedBox(height: 16),
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: [
                                  _buildStatPill(
                                    icon: Icons.auto_stories_rounded,
                                    label: selectedCount == 1
                                        ? '1 resource'
                                        : '$selectedCount resources',
                                  ),
                                  _buildStatPill(
                                    icon: Icons.grid_view_rounded,
                                    label: '${categoryCounts.length} topics',
                                  ),
                                  if (latestDate.isNotEmpty)
                                    _buildStatPill(
                                      icon: Icons.schedule_rounded,
                                      label: latestDate,
                                    ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 18),
                        Container(
                          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(20),
                            gradient: const LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [Colors.white, Color(0xFFF4F9FF)],
                            ),
                            border: Border.all(color: _cardBorder),
                            boxShadow: [
                              BoxShadow(
                                color: const Color(0xFF8DA7C3).withValues(
                                  alpha: 0.14,
                                ),
                                blurRadius: 10,
                                offset: const Offset(0, 6),
                              ),
                            ],
                          ),
                          child: DropdownButtonFormField<String>(
                            value: _selectedCategory,
                            icon: const Icon(
                              Icons.keyboard_arrow_down_rounded,
                              color: _ink,
                            ),
                            decoration: const InputDecoration(
                              labelText: 'Category',
                              labelStyle: TextStyle(
                                color: _subtleInk,
                                fontWeight: FontWeight.w600,
                              ),
                              border: InputBorder.none,
                              isDense: true,
                            ),
                            style: const TextStyle(
                              color: _ink,
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                            ),
                            dropdownColor: Colors.white,
                            items: sortedCats
                                .map(
                                  (category) => DropdownMenuItem(
                                    value: category,
                                    child: Text(category),
                                  ),
                                )
                                .toList(),
                            onChanged: (value) {
                              if (value == null) return;
                              setState(() => _selectedCategory = value);
                            },
                          ),
                        ),
                        const SizedBox(height: 18),
                        if (filtered.isEmpty)
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(18),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.92),
                              borderRadius: BorderRadius.circular(22),
                              border: Border.all(color: _cardBorder),
                            ),
                            child: const Text(
                              'No BFAR posts published in this category yet.',
                              style: TextStyle(
                                color: _subtleInk,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          )
                        else
                          ...filtered.map(
                            (post) => _buildBfarPostCard(context, post),
                          ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStatPill({required IconData icon, required String label}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white30),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: Colors.white),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 11.8,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _AdminPreviewMedia extends StatelessWidget {
  final String imageUrl;
  final String youtubeId;
  final Future<String?> Function(String) resolveAttachmentUrl;
  final ImageProvider<Object>? Function(String) imageProviderFromResolved;

  const _AdminPreviewMedia({
    required this.imageUrl,
    required this.youtubeId,
    required this.resolveAttachmentUrl,
    required this.imageProviderFromResolved,
  });

  @override
  Widget build(BuildContext context) {
    final fallback = Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF10385B), Color(0xFF071B2D)],
        ),
      ),
      child: const Center(
        child: Icon(
          Icons.auto_stories_rounded,
          color: Colors.white54,
          size: 38,
        ),
      ),
    );

    if (youtubeId.isNotEmpty) {
      return Image.network(
        'https://img.youtube.com/vi/$youtubeId/0.jpg',
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => fallback,
      );
    }

    if (imageUrl.isEmpty) return fallback;

    return FutureBuilder<String?>(
      future: resolveAttachmentUrl(imageUrl),
      builder: (context, snapshot) {
        final resolved = snapshot.data ?? '';
        final provider = resolved.isNotEmpty
            ? imageProviderFromResolved(resolved)
            : null;
        if (provider != null) {
          return Image(
            image: provider,
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) => fallback,
          );
        }
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Stack(
            fit: StackFit.expand,
            children: [
              fallback,
              const Center(
                child: SizedBox(
                  width: 26,
                  height: 26,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.6,
                    color: Colors.white70,
                  ),
                ),
              ),
            ],
          );
        }
        return fallback;
      },
    );
  }
}

class _AdminAttachmentImagePage extends StatelessWidget {
  final ImageProvider<Object> provider;

  const _AdminAttachmentImagePage({required this.provider});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text(
          'Attached Image',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      body: Center(
        child: InteractiveViewer(
          minScale: 0.7,
          maxScale: 4,
          child: Image(image: provider, fit: BoxFit.contain),
        ),
      ),
    );
  }
}
