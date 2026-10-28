import 'dart:convert';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:youtube_player_flutter/youtube_player_flutter.dart';

import '../../l10n/app_localizations.dart';
import 'educational_section_page.dart';

class EducationalScreen extends StatefulWidget {
  final String? initialCategory;

  const EducationalScreen({super.key, this.initialCategory});

  @override
  State<EducationalScreen> createState() => _EducationalScreenState();
}

class _EducationalScreenState extends State<EducationalScreen> {
  static const String _videoCategory = 'Video & Infographics Section';
  static const String _defaultCategory = 'Sustainable Fishing Laws';

  static const Color _pageTop = Color(0xFFE8F4FF);
  static const Color _pageBottom = Color(0xFFF8FCFF);
  static const Color _ink = Color(0xFF102A43);
  static const Color _subtleInk = Color(0xFF486581);

  String _selectedCategory = _defaultCategory;
  YoutubePlayerController? _ytController;
  String? _currentVideoId;
  final Map<String, Future<String?>> _storageUrlCache = {};

  @override
  void initState() {
    super.initState();
    _selectedCategory = _initialCategory();
  }

  @override
  void dispose() {
    _ytController?.dispose();
    super.dispose();
  }

  String _initialCategory() {
    final incoming = widget.initialCategory?.trim();
    if (incoming != null && incoming.isNotEmpty) return incoming;
    return _defaultCategory;
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

  DateTime? _parseUpdatedAt(dynamic value) {
    if (value is Timestamp) return value.toDate();
    if (value is String && value.isNotEmpty) return DateTime.tryParse(value);
    return null;
  }

  String _formatDate(DateTime? value) {
    if (value == null) return '';
    final mm = value.month.toString().padLeft(2, '0');
    final dd = value.day.toString().padLeft(2, '0');
    return '${value.year}-$mm-$dd';
  }

  String _normalizeYoutubeId(dynamic value) {
    final raw = (value ?? '').toString().trim();
    if (raw.isEmpty) return '';
    final parsed = YoutubePlayer.convertUrlToId(raw);
    return (parsed ?? raw).trim();
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

  void _showAttachmentError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  String _primaryLink(Map<String, dynamic>? res) {
    if (res == null) return '';
    final type = (res['type'] as String? ?? '').toLowerCase();
    final youtubeId = _normalizeYoutubeId(res['youtubeId']);
    final pdf = _cleanText(res['pdfUrl']);
    final image = _cleanText(res['image']);
    if (youtubeId.isNotEmpty) return 'https://www.youtube.com/watch?v=$youtubeId';
    if (type == 'pdf' && pdf.isNotEmpty) return pdf;
    if (pdf.isNotEmpty) return pdf;
    if (image.isNotEmpty) return image;
    return '';
  }

  String? _thumbUrl(Map<String, dynamic>? res) {
    if (res == null) return null;
    final youtubeId = _normalizeYoutubeId(res['youtubeId']);
    if (youtubeId.isNotEmpty) {
      return 'https://img.youtube.com/vi/$youtubeId/0.jpg';
    }
    return null;
  }

  String _primaryImage(Map<String, dynamic>? res) {
    if (res == null) return '';
    return _cleanText(res['image']);
  }

  bool _hasPdfAttachment(Map<String, dynamic>? res) {
    if (res == null) return false;
    return _cleanText(res['pdfUrl']).isNotEmpty;
  }

  String _primaryActionLabel(Map<String, dynamic>? res) {
    if (res == null) return 'Open Attachment';
    final youtubeId = _normalizeYoutubeId(res['youtubeId']);
    final pdfUrl = _cleanText(res['pdfUrl']);
    final imageUrl = _cleanText(res['image']);
    final type = _cleanText(res['type']).toLowerCase();
    if (youtubeId.isNotEmpty) return 'Watch Video';
    if (imageUrl.isNotEmpty && pdfUrl.isEmpty) return 'View Image';
    if (pdfUrl.isNotEmpty && (type == 'pdf' || pdfUrl.toLowerCase().contains('.pdf'))) {
      return 'View PDF';
    }
    if (pdfUrl.isNotEmpty) return 'Open File';
    if (imageUrl.isNotEmpty) return 'View Image';
    return 'Open Attachment';
  }

  IconData _primaryActionIcon(Map<String, dynamic>? res) {
    if (res == null) return Icons.open_in_new_rounded;
    final youtubeId = _normalizeYoutubeId(res['youtubeId']);
    final pdfUrl = _cleanText(res['pdfUrl']);
    final imageUrl = _cleanText(res['image']);
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
    final lower = url.toLowerCase();
    return lower.contains('.pdf') ? 'View PDF' : 'Open File';
  }

  IconData _secondaryFileIcon(String url) {
    final lower = url.toLowerCase();
    return lower.contains('.pdf')
        ? Icons.picture_as_pdf_rounded
        : Icons.attach_file_rounded;
  }

  String _resourceTypeLabel({
    required String type,
    required String youtubeId,
  }) {
    if (youtubeId.isNotEmpty) return 'VIDEO';
    if (type.trim().isEmpty) return 'DOC';
    return type.trim().toUpperCase();
  }

  void _startInlineVideo(String videoId) {
    if (videoId.isEmpty) return;
    if (_currentVideoId != videoId) {
      _ytController?.dispose();
      _ytController = YoutubePlayerController(
        initialVideoId: videoId,
        flags: const YoutubePlayerFlags(
          autoPlay: true,
          mute: false,
          enableCaption: true,
        ),
      );
      _currentVideoId = videoId;
      _ytController!.addListener(() {
        if (mounted) setState(() {});
      });
    } else {
      _ytController?.play();
    }
    setState(() {});
  }

  Future<void> _openLink(String url) async {
    if (url.isEmpty) return;
    final resolved = await _resolveAttachmentUrl(url);
    if (resolved == null || resolved.isEmpty) {
      _showAttachmentError('Could not open this attachment.');
      return;
    }

    if (_looksLikeImageReference(resolved)) {
      final provider = _imageProviderFromResolved(resolved);
      if (provider != null && mounted) {
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => _AttachmentImagePage(provider: provider),
          ),
        );
        return;
      }
    }

    final uri = Uri.tryParse(resolved);
    if (uri == null) {
      _showAttachmentError('Could not open this attachment.');
      return;
    }

    final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!opened) {
      _showAttachmentError('Could not open this attachment.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final pageTitle = _selectedCategory == _videoCategory
        ? l.videoInfographicsSection
        : _selectedCategory;
    return Scaffold(
      backgroundColor: _pageBottom,
      appBar: AppBar(
        title: Text(
          pageTitle,
          style: const TextStyle(
            fontFamily: 'serif',
            fontWeight: FontWeight.w800,
            color: _ink,
            fontSize: 22,
            letterSpacing: 0.2,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        centerTitle: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
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
            onPressed: () {
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(
                  builder: (_) => EducationalSectionPage(
                    selectedCategory: _selectedCategory,
                  ),
                ),
              );
            },
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
        child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: FirebaseFirestore.instance
              .collection('educational_resources')
              .snapshots(),
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return const Center(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: Text(
                    'Failed to load educational resources. Please try again.',
                    style: TextStyle(color: Colors.red),
                    textAlign: TextAlign.center,
                  ),
                ),
              );
            }

            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }

            final docs = snapshot.data!.docs;
            final parsed = docs.map((d) {
              final data = d.data();
              final rawCategory = data['categoryName'];
              final categoryName =
                  (rawCategory == null || rawCategory.toString().trim().isEmpty)
                  ? _defaultCategory
                  : rawCategory.toString();
              return {
                'id': d.id,
                'categoryName': categoryName,
                'title': _cleanText(data['title']),
                'description': _cleanText(data['description']),
                'type': _cleanText(data['type']).isEmpty
                    ? 'pdf'
                    : _cleanText(data['type']),
                'updatedAt': _parseUpdatedAt(data['updatedAt']),
                'active': _isActive(data['active']),
                'archived': _isArchived(data['archived']),
                'pdfUrl': _cleanText(data['pdfUrl']),
                'image': _cleanText(data['image']),
                'youtubeId': _normalizeYoutubeId(data['youtubeId']),
              };
            }).toList();

            final resources = parsed
                .where((r) => r['active'] == true && r['archived'] != true)
                .toList();

            final categorySet = <String>{};
            bool hasVideo = false;
            for (final r in resources) {
              final category = (r['categoryName'] as String? ?? '').trim();
              if (category.isNotEmpty) categorySet.add(category);
              final yt = _normalizeYoutubeId(r['youtubeId']);
              final type = (r['type'] as String? ?? '').toLowerCase();
              if (yt.isNotEmpty || type == 'video') hasVideo = true;
            }
            if (hasVideo) categorySet.add(_videoCategory);

            final categories = categorySet.toList()..sort();
            if (categories.isEmpty) {
              return const Center(child: Text('No resources found.'));
            }

            if (!categories.contains(_selectedCategory)) {
              _selectedCategory = categories.first;
            }

            final selectedResources = _selectedCategory == _videoCategory
                ? resources
                : resources
                      .where(
                        (r) =>
                            (r['categoryName'] as String).trim() ==
                            _selectedCategory,
                      )
                      .toList();

            Map<String, dynamic> hero = <String, dynamic>{};
            if (selectedResources.isNotEmpty) {
              hero = selectedResources.firstWhere(
                (r) => _primaryLink(r).isNotEmpty,
                orElse: () => selectedResources.first,
              );
            }

            final heroId = (hero['id'] ?? '').toString();
            final rest = selectedResources
                .where((resource) => (resource['id'] ?? '').toString() != heroId)
                .toList();

            return SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (hero.isNotEmpty)
                    _HeroSection(
                      title: (hero['title'] as String?)?.trim().isNotEmpty == true
                          ? (hero['title'] as String)
                          : 'Protecting Our Ocean',
                      subtitle:
                          (hero['description'] as String?)?.trim().isNotEmpty ==
                              true
                          ? (hero['description'] as String)
                          : 'Sustainable fishing for future generations',
                      link: _primaryLink(hero),
                      pdfUrl: _cleanText(hero['pdfUrl']),
                      imageUrl: _primaryImage(hero),
                      thumbUrl: _thumbUrl(hero),
                      youtubeId: _normalizeYoutubeId(hero['youtubeId']),
                      typeLabel: _resourceTypeLabel(
                        type: (hero['type'] as String? ?? ''),
                        youtubeId: _normalizeYoutubeId(hero['youtubeId']),
                      ),
                      primaryLabel: _primaryActionLabel(hero),
                      primaryIcon: _primaryActionIcon(hero),
                      hasPdfAttachment: _hasPdfAttachment(hero),
                      resolveAttachmentUrl: _resolveAttachmentUrl,
                      imageProviderFromResolved: _imageProviderFromResolved,
                      secondaryFileLabel: _secondaryFileLabel,
                      secondaryFileIcon: _secondaryFileIcon,
                      updatedAt: _formatDate(hero['updatedAt'] as DateTime?),
                      controller: _ytController,
                      onPlay: _startInlineVideo,
                      onLinkTap: _openLink,
                    ),
                  const SizedBox(height: 18),
                  if (rest.isEmpty && hero.isNotEmpty)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.86),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: const Color(0xFFD8E4F0)),
                      ),
                      child: const Text(
                        'No additional resources in this category yet.',
                        style: TextStyle(
                          color: _subtleInk,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    )
                  else if (selectedResources.isEmpty)
                    const Center(
                      child: Padding(
                        padding: EdgeInsets.symmetric(vertical: 24),
                        child: Text(
                          'No resources found.',
                          style: TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                    )
                  else ...[
                    Text(
                      'More Resources',
                      style: TextStyle(
                        color: _ink.withValues(alpha: 0.95),
                        fontFamily: 'serif',
                        fontWeight: FontWeight.w800,
                        fontSize: 18.2,
                        letterSpacing: 0.15,
                      ),
                    ),
                    const SizedBox(height: 10),
                    for (final res in rest.isEmpty ? selectedResources : rest)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: _ResourceTile(
                          title: (res['title'] as String?)?.trim().isNotEmpty ==
                                  true
                              ? (res['title'] as String)
                              : 'Untitled Resource',
                          description: (res['description'] as String?)?.trim() ?? '',
                          typeLabel: _resourceTypeLabel(
                            type: (res['type'] as String? ?? ''),
                            youtubeId: _normalizeYoutubeId(res['youtubeId']),
                          ),
                          updatedAt: _formatDate(res['updatedAt'] as DateTime?),
                          link: _primaryLink(res),
                          youtubeId: _normalizeYoutubeId(res['youtubeId']),
                          leadingIcon: _primaryActionIcon(res),
                          onPlay: _startInlineVideo,
                          onLinkTap: _openLink,
                        ),
                      ),
                  ],
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _HeroSection extends StatelessWidget {
  final String title;
  final String subtitle;
  final String link;
  final String pdfUrl;
  final String imageUrl;
  final String? thumbUrl;
  final String youtubeId;
  final String typeLabel;
  final String primaryLabel;
  final IconData primaryIcon;
  final bool hasPdfAttachment;
  final Future<String?> Function(String) resolveAttachmentUrl;
  final ImageProvider<Object>? Function(String) imageProviderFromResolved;
  final String Function(String) secondaryFileLabel;
  final IconData Function(String) secondaryFileIcon;
  final String updatedAt;
  final YoutubePlayerController? controller;
  final void Function(String) onPlay;
  final Future<void> Function(String) onLinkTap;

  const _HeroSection({
    required this.title,
    required this.subtitle,
    required this.link,
    required this.pdfUrl,
    required this.imageUrl,
    required this.thumbUrl,
    required this.youtubeId,
    required this.typeLabel,
    required this.primaryLabel,
    required this.primaryIcon,
    required this.hasPdfAttachment,
    required this.resolveAttachmentUrl,
    required this.imageProviderFromResolved,
    required this.secondaryFileLabel,
    required this.secondaryFileIcon,
    required this.updatedAt,
    required this.controller,
    required this.onPlay,
    required this.onLinkTap,
  });

  @override
  Widget build(BuildContext context) {
    final hasLink = link.isNotEmpty;
    final canInlinePlay = youtubeId.isNotEmpty;
    final hasPdf = hasPdfAttachment && pdfUrl.isNotEmpty;
    final showPlayer = canInlinePlay && controller != null;
    final hasThumb = thumbUrl != null && thumbUrl!.isNotEmpty;
    final hasImage = imageUrl.isNotEmpty;
    final showMedia = showPlayer || canInlinePlay || hasThumb || hasImage;

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Colors.white, Color(0xFFF4F9FF)],
        ),
        border: Border.all(color: const Color(0xFFD8E4F0)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF8DA7C3).withValues(alpha: 0.16),
            blurRadius: 12,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (showMedia)
            ClipRRect(
              borderRadius: BorderRadius.circular(18),
              child: AspectRatio(
                aspectRatio: 16 / 9,
                child: showPlayer
                    ? YoutubePlayer(
                        controller: controller!,
                        showVideoProgressIndicator: true,
                      )
                    : GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: canInlinePlay
                            ? () => onPlay(youtubeId)
                            : hasLink
                            ? () => onLinkTap(link)
                            : null,
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            _HeroMediaBackground(
                              imageUrl: imageUrl,
                              thumbUrl: thumbUrl,
                              resolveAttachmentUrl: resolveAttachmentUrl,
                              imageProviderFromResolved:
                                  imageProviderFromResolved,
                            ),
                            Container(
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                  colors: [
                                    Colors.black.withValues(alpha: 0.2),
                                    Colors.black.withValues(alpha: 0.55),
                                  ],
                                ),
                              ),
                            ),
                            Positioned(
                              top: 10,
                              left: 10,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 9,
                                  vertical: 5,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.22),
                                  borderRadius: BorderRadius.circular(999),
                                  border: Border.all(color: Colors.white30),
                                ),
                                child: Text(
                                  typeLabel,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w800,
                                    fontSize: 11.5,
                                  ),
                                ),
                              ),
                            ),
                            Center(
                              child: Container(
                                width: 66,
                                height: 66,
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.22),
                                  border: Border.all(color: Colors.white54),
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(
                                  canInlinePlay
                                      ? Icons.play_arrow_rounded
                                      : Icons.open_in_new_rounded,
                                  color: Colors.white,
                                  size: 34,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
              ),
            ),
          const SizedBox(height: 12),
          Text(
            title,
            style: const TextStyle(
              color: Color(0xFF102A43),
              fontWeight: FontWeight.w800,
              fontSize: 18,
              height: 1.2,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            subtitle,
            style: const TextStyle(
              color: Color(0xFF486581),
              fontSize: 13.4,
              height: 1.45,
            ),
          ),
          if (updatedAt.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              'Updated $updatedAt',
              style: const TextStyle(
                color: Color(0xFF627D98),
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
          const SizedBox(height: 12),
          if (canInlinePlay || hasLink)
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: hasLink ? () => onLinkTap(link) : null,
                icon: Icon(primaryIcon, size: 20),
                label: Text(primaryLabel),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF124F8A),
                  foregroundColor: Colors.white,
                  minimumSize: const Size(double.infinity, 48),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
              ),
            ),
          if (hasPdf) ...[
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () => onLinkTap(pdfUrl),
                icon: Icon(secondaryFileIcon(pdfUrl), size: 20),
                label: Text(secondaryFileLabel(pdfUrl)),
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
    );
  }
}

class _HeroMediaBackground extends StatelessWidget {
  final String imageUrl;
  final String? thumbUrl;
  final Future<String?> Function(String) resolveAttachmentUrl;
  final ImageProvider<Object>? Function(String) imageProviderFromResolved;

  const _HeroMediaBackground({
    required this.imageUrl,
    required this.thumbUrl,
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

    if (thumbUrl != null && thumbUrl!.isNotEmpty) {
      return Image.network(
        thumbUrl!,
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

class _ResourceTile extends StatelessWidget {
  final String title;
  final String description;
  final String typeLabel;
  final String updatedAt;
  final String link;
  final String youtubeId;
  final IconData leadingIcon;
  final void Function(String) onPlay;
  final Future<void> Function(String) onLinkTap;

  const _ResourceTile({
    required this.title,
    required this.description,
    required this.typeLabel,
    required this.updatedAt,
    required this.link,
    required this.youtubeId,
    required this.leadingIcon,
    required this.onPlay,
    required this.onLinkTap,
  });

  @override
  Widget build(BuildContext context) {
    final hasLink = link.isNotEmpty;
    final isVideo = youtubeId.isNotEmpty;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: isVideo
            ? () => onPlay(youtubeId)
            : hasLink
            ? () => onLinkTap(link)
            : null,
        child: Ink(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Colors.white, Color(0xFFF7FBFF)],
            ),
            border: Border.all(color: const Color(0xFFD8E4F0)),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF8DA7C3).withValues(alpha: 0.12),
                blurRadius: 10,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(13),
                  color: isVideo
                      ? const Color(0xFFD6EBFF)
                      : const Color(0xFFEAF1FF),
                ),
                child: Icon(
                  isVideo ? Icons.play_arrow_rounded : leadingIcon,
                  color: const Color(0xFF124F8A),
                  size: 24,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: Color(0xFF102A43),
                        fontWeight: FontWeight.w800,
                        fontSize: 14.6,
                        height: 1.22,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (description.isNotEmpty) ...[
                      const SizedBox(height: 5),
                      Text(
                        description,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xFF486581),
                          fontSize: 12.7,
                          height: 1.35,
                        ),
                      ),
                    ],
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 9,
                            vertical: 5,
                          ),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(999),
                            color: const Color(0xFFEAF1FF),
                          ),
                          child: Text(
                            typeLabel,
                            style: const TextStyle(
                              color: Color(0xFF124F8A),
                              fontWeight: FontWeight.w800,
                              fontSize: 11.4,
                            ),
                          ),
                        ),
                        if (updatedAt.isNotEmpty)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 9,
                              vertical: 5,
                            ),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(999),
                              color: const Color(0xFFF1F5FA),
                            ),
                            child: Text(
                              updatedAt,
                              style: const TextStyle(
                                color: Color(0xFF627D98),
                                fontWeight: FontWeight.w700,
                                fontSize: 11.3,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              if (isVideo || hasLink) ...[
                const SizedBox(width: 10),
                Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(9),
                    color: const Color(0xFFEAF1FF),
                  ),
                  child: Icon(
                    isVideo ? Icons.play_arrow_rounded : Icons.open_in_new_rounded,
                    color: const Color(0xFF124F8A),
                    size: 18,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _AttachmentImagePage extends StatelessWidget {
  final ImageProvider<Object> provider;

  const _AttachmentImagePage({required this.provider});

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
