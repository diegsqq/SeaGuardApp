import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../../utils/loading_delay.dart';
import '../../utils/responsive.dart';
import '../detection/detection_screen.dart';
import 'marine_details_page.dart';

class MarineLifePage extends StatefulWidget {
  const MarineLifePage({super.key});

  @override
  State<MarineLifePage> createState() => _MarineLifePageState();
}

class _MarineLifePageState extends State<MarineLifePage> {
  static const Color _pageTop = Color(0xFFEAF4FF);
  static const Color _pageBottom = Color(0xFFF8FCFF);
  static const Color _ink = Color(0xFF102A43);
  static const Color _subtleInk = Color(0xFF486581);

  static const Map<String, String> _photoOverrides = {
    // Fallbacks when Firestore photo is missing or unusable
    'apolemichthys-trimaculatus':
        'https://www.fishbase.se/images/thumbnails/jpg/tn_Aptri_uc.jpg',
    'bangus': 'asset:assets/milkfish.png',
    'milkfish': 'asset:assets/milkfish.png',
    'chanos-chanos': 'asset:assets/milkfish.png',
    'carp': 'asset:assets/carp.png',
    'catfish': 'asset:assets/catfish.png',
    'hito': 'asset:assets/catfish.png',
    'mackerel': 'asset:assets/mackarel.png',
    'mackarel': 'asset:assets/mackarel.png',
    'sardine': 'asset:assets/sardine.png',
    'sardines': 'asset:assets/sardine.png',
    'tilapia': 'asset:assets/tilapia.png',
    'apahap':
        'https://upload.wikimedia.org/wikipedia/commons/thumb/9/9e/Lates_calcarifer_scox.jpg/320px-Lates_calcarifer_scox.jpg',
    'asian-seabass':
        'https://upload.wikimedia.org/wikipedia/commons/thumb/9/9e/Lates_calcarifer_scox.jpg/320px-Lates_calcarifer_scox.jpg',
    'lates-calcarifer':
        'https://upload.wikimedia.org/wikipedia/commons/thumb/9/9e/Lates_calcarifer_scox.jpg/320px-Lates_calcarifer_scox.jpg',
    'litopenaeus-vannamei':
        'https://upload.wikimedia.org/wikipedia/commons/thumb/7/7d/Litopenaeus_vannamei_01.jpg/320px-Litopenaeus_vannamei_01.jpg',
  };

  final Map<String, Future<String?>> _storageUrlCache = {};
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _statsSub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _speciesSub;
  String _selectedSector = 'All';
  List<Map<String, dynamic>> _species = [];
  List<Map<String, dynamic>> _filteredSpecies = [];
  List<String> _sectors = ['All'];
  List<QueryDocumentSnapshot<Map<String, dynamic>>> _statsDocs = const [];
  Map<String, Map<String, dynamic>> _speciesMetadataIndex = const {};
  List<Map<String, dynamic>> _speciesMetadataDocs = const [];

  bool _isLoading = true;
  final TextEditingController _searchController = TextEditingController();
  static const Duration _initialLoadTimeout = Duration(seconds: 12);
  String? _loadErrorMessage;
  Timer? _loadingGuardTimer;
  Future<void>? _minimumLoadingDelay;

  @override
  void initState() {
    super.initState();
    _listenToCollections();
    _searchController.addListener(_onSearchChanged);
    unawaited(_loadInitialData());
  }

  @override
  void dispose() {
    _loadingGuardTimer?.cancel();
    _statsSub?.cancel();
    _speciesSub?.cancel();
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    super.dispose();
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
      case 'nan':
        return '';
      default:
        return text;
    }
  }

  String _pickFirstText(
    List<dynamic> values, {
    String fallback = '',
  }) {
    for (final value in values) {
      final cleaned = _cleanText(value);
      if (cleaned.isNotEmpty) return cleaned;
    }
    return fallback;
  }

  String _stripTrailingParenLabel(dynamic value) {
    final cleaned = _cleanText(value);
    if (cleaned.isEmpty) return '';
    final match = RegExp(r'^(.*?)\s*\(([^()]+)\)\s*$').firstMatch(cleaned);
    if (match == null) return cleaned;
    final base = _cleanText(match.group(1));
    return base.isNotEmpty ? base : cleaned;
  }

  String _extractTrailingParenLabel(dynamic value) {
    final cleaned = _cleanText(value);
    if (cleaned.isEmpty) return '';
    final match = RegExp(r'^(.*?)\s*\(([^()]+)\)\s*$').firstMatch(cleaned);
    if (match == null) return '';
    final base = _cleanText(match.group(1));
    final label = _cleanText(match.group(2));
    if (base.isEmpty || label.isEmpty) return '';
    return label;
  }

  List<String> _lookupVariants(dynamic value) {
    final cleaned = _cleanText(value);
    if (cleaned.isEmpty) return const [];

    final lower = cleaned.toLowerCase();
    final withoutParen = cleaned.split('(').first.trim();
    final withoutComma = cleaned.split(',').first.trim();

    return <String>{
      lower,
      lower.replaceAll(' ', ''),
      _slug(cleaned),
      _slug(withoutParen),
      _slug(withoutComma),
      withoutParen.toLowerCase(),
      withoutComma.toLowerCase(),
      cleaned.replaceAll(' ', '-').toLowerCase(),
      cleaned.replaceAll(' ', '_').toLowerCase(),
    }.where((entry) => entry.trim().isNotEmpty).toList();
  }

  void _listenToCollections() {
    _statsSub = FirebaseFirestore.instance
        .collection('marine_life_stats')
        .snapshots()
        .listen((snapshot) {
          _statsDocs = snapshot.docs;
          unawaited(_rebuildFishList());
        }, onError: (e) {
          if (!mounted) return;
          setState(() {
            _isLoading = false;
            if (_species.isEmpty) {
              _loadErrorMessage =
                  'Unable to load fish production data right now. Check your connection and tap Retry.';
            }
          });
          debugPrint('Error streaming marine_life_stats: $e');
        });

    _speciesSub = FirebaseFirestore.instance
        .collection('species_database')
        .snapshots()
        .listen((snapshot) {
          _rebuildSpeciesMetadataIndex(snapshot.docs);
          unawaited(_rebuildFishList());
        }, onError: (e) {
          if (!mounted) return;
          debugPrint('Error streaming species_database: $e');
          unawaited(_rebuildFishList());
        });
  }

  void _startLoadingGuard() {
    _loadingGuardTimer?.cancel();
    _loadingGuardTimer = Timer(_initialLoadTimeout, () {
      if (!mounted || !_isLoading) return;
      setState(() {
        _isLoading = false;
        _loadErrorMessage =
            'Unable to load fish production data right now. Check your connection and tap Retry.';
      });
    });
  }

  Future<void> _loadInitialData({bool showLoader = true}) async {
    if (showLoader && mounted) {
      _minimumLoadingDelay = Future<void>.delayed(appLoadingDelay);
      setState(() {
        _isLoading = true;
        _loadErrorMessage = null;
      });
    }
    _startLoadingGuard();
    unawaited(_loadInitialStats());
    unawaited(_loadInitialMetadata());
  }

  Future<void> _loadInitialStats() async {
    try {
      final statsSnapshot = await FirebaseFirestore.instance
          .collection('marine_life_stats')
          .get()
          .timeout(_initialLoadTimeout);
      if (!mounted) return;
      _statsDocs = statsSnapshot.docs;
      unawaited(_rebuildFishList());
    } catch (e) {
      debugPrint('Error loading marine_life_stats: $e');
    }
  }

  Future<void> _loadInitialMetadata() async {
    try {
      final speciesSnapshot = await FirebaseFirestore.instance
          .collection('species_database')
          .get()
          .timeout(_initialLoadTimeout);
      if (!mounted) return;
      _rebuildSpeciesMetadataIndex(speciesSnapshot.docs);
      unawaited(_rebuildFishList());
    } catch (e) {
      debugPrint('Error loading species_database: $e');
    }
  }

  void _rebuildSpeciesMetadataIndex(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) {
    final index = <String, Map<String, dynamic>>{};
    final entries = <Map<String, dynamic>>[];

    for (final doc in docs) {
      final data = doc.data();
      final entry = <String, dynamic>{...data, 'id': doc.id};
      entries.add(entry);

      final keys = <String>{
        ..._lookupVariants(doc.id),
        ..._lookupVariants(data['englishName']),
        ..._lookupVariants(data['name']),
        ..._lookupVariants(data['scientificName']),
        ..._lookupVariants(data['localName']),
        ..._lookupVariants(data['commonName']),
        ..._lookupVariants(data['vernacularName']),
      };

      for (final key in keys) {
        index.putIfAbsent(key, () => entry);
      }
    }

    _speciesMetadataIndex = index;
    _speciesMetadataDocs = entries;
  }

  Map<String, dynamic>? _lookupSpeciesMetadata(
    String docId,
    Map<String, dynamic> data,
  ) {
    final lookupKeys = <String>{
      ..._lookupVariants(docId),
      ..._lookupVariants(data['englishName']),
      ..._lookupVariants(data['name']),
      ..._lookupVariants(data['scientificName']),
      ..._lookupVariants(data['localName']),
    };

    for (final key in lookupKeys) {
      final match = _speciesMetadataIndex[key];
      if (match != null) return match;
    }

    final needle = _pickFirstText(
      [data['englishName'], data['name'], docId],
    ).toLowerCase();
    if (needle.isEmpty) return null;

    Map<String, dynamic>? bestMatch;
    var bestScore = 0;

    for (final entry in _speciesMetadataDocs) {
      final fields = <String>[
        _cleanText(entry['id']).toLowerCase(),
        _cleanText(entry['englishName']).toLowerCase(),
        _cleanText(entry['name']).toLowerCase(),
        _cleanText(entry['scientificName']).toLowerCase(),
        _cleanText(entry['localName']).toLowerCase(),
      ].where((value) => value.isNotEmpty).toList();

      var score = 0;
      for (final field in fields) {
        if (field == needle || _slug(field) == _slug(needle)) {
          score = 4;
          break;
        }
        if (field.contains(needle) || needle.contains(field)) {
          score = 2;
        }
      }

      if (score > bestScore) {
        bestScore = score;
        bestMatch = entry;
      }
    }

    return bestScore > 0 ? bestMatch : null;
  }

  List<String> _collectImageCandidates(
    Map<String, dynamic> primary,
    Map<String, dynamic>? secondary,
  ) {
    final seen = <String>{};
    final out = <String>[];

    void addCandidate(dynamic value) {
      final cleaned = _cleanText(value);
      if (cleaned.isEmpty || !seen.add(cleaned)) return;
      out.add(cleaned);
    }

    for (final key in const [
      'photo',
      'imageUrl',
      'image',
      'photoRaw',
      'storagePath',
      'imagePath',
    ]) {
      addCandidate(primary[key]);
    }

    if (secondary != null) {
      for (final key in const [
        'photo',
        'imageUrl',
        'image',
        'photoRaw',
        'storagePath',
        'imagePath',
      ]) {
        addCandidate(secondary[key]);
      }
    }

    return out;
  }

  String _deriveDataSource(
    Map<String, dynamic> data,
    Map<String, dynamic>? metadata,
  ) {
    final explicit = _pickFirstText([
      data['dataSource'],
      data['source'],
      data['reference'],
      data['origin'],
      data['provider'],
      data['institution'],
      data['agency'],
      metadata?['dataSource'],
      metadata?['source'],
      metadata?['reference'],
      metadata?['origin'],
      metadata?['provider'],
      metadata?['institution'],
      metadata?['agency'],
    ]);
    if (explicit.isNotEmpty) return explicit;

    if (data.isNotEmpty && metadata != null) {
      return 'Production record from marine_life_stats; species profile from species_database.';
    }
    if (metadata != null) return 'Species profile from species_database.';
    return 'Production record from marine_life_stats.';
  }

  Map<String, dynamic> _mapStat(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? {};
    final metadata = _lookupSpeciesMetadata(doc.id, data);
    String m(dynamic v) => _formatMetric(v);

    final rawName = _pickFirstText([
      data['englishName'],
      data['name'],
      metadata?['englishName'],
      metadata?['name'],
      doc.id,
    ], fallback: doc.id);
    final inferredLocalName = _extractTrailingParenLabel(rawName);
    final name = _stripTrailingParenLabel(rawName);
    final localName = _pickFirstText([
      data['localName'],
      data['local_name'],
      metadata?['localName'],
      metadata?['local_name'],
      metadata?['commonName'],
      metadata?['vernacularName'],
      inferredLocalName,
    ]);
    final scientificName = _pickFirstText([
      data['scientificName'],
      data['scientific_name'],
      metadata?['scientificName'],
      metadata?['scientific_name'],
    ]);
    final family = _pickFirstText([data['family'], metadata?['family']]);
    final habitat = _pickFirstText([
      data['habitat'],
      data['location'],
      metadata?['habitat'],
      metadata?['location'],
    ]);
    final about = _pickFirstText([
      data['about'],
      data['description'],
      data['content'],
      metadata?['about'],
      metadata?['description'],
      metadata?['content'],
    ]);
    final sector = _pickFirstText([data['sector'], metadata?['sector']]);
    final frequency = _pickFirstText([data['frequency'], metadata?['frequency']]);
    final year = _pickFirstText([data['year'], metadata?['year']]);
    final imageCandidates = _collectImageCandidates(data, metadata);
    final rawPhoto = imageCandidates.isNotEmpty ? imageCandidates.first : '';
    final photo = _resolveImageUrl(
      rawPhoto,
      doc.id,
      fallbackName: name,
      scientificName: scientificName,
    );

    return {
      'id': doc.id,
      'name': name.isEmpty ? doc.id : name,
      'englishName': name.isEmpty ? doc.id : name,
      'localName': localName,
      'scientificName': scientificName,
      'family': family,
      'habitat': habitat,
      'about': about,
      'sector': sector,
      'frequency': frequency,
      'year': year,
      'dataSource': _deriveDataSource(data, metadata),
      'photoRaw': rawPhoto,
      'photoCandidates': imageCandidates,
      'photo': photo,
      'updatedAt': _parseUpdatedAt(data['updatedAt'] ?? data['lastEntryDate']),
      'lastEntryDate': _parseUpdatedAt(data['lastEntryDate']),
      'lastEntryKg': m(data['lastEntryKg']),
      'lastEntryMt': m(data['lastEntryMt']),
      'q1': m(data['q1'] ?? (data['q'] is List && data['q'].length > 0 ? data['q'][0] : null)),
      'q2': m(data['q2'] ?? (data['q'] is List && data['q'].length > 1 ? data['q'][1] : null)),
      'q3': m(data['q3'] ?? (data['q'] is List && data['q'].length > 2 ? data['q'][2] : null)),
      'q4': m(data['q4'] ?? (data['q'] is List && data['q'].length > 3 ? data['q'][3] : null)),
      'annual': m(data['annual'] ?? data['annualTotal'] ?? data['total'] ?? ''),
    };
  }

  Map<String, dynamic> _mapMetadata(Map<String, dynamic> metadata) {
    final id = _pickFirstText([
      metadata['id'],
      metadata['englishName'],
      metadata['name'],
      metadata['scientificName'],
    ], fallback: 'species');
    final rawName = _pickFirstText([
      metadata['englishName'],
      metadata['name'],
      id,
    ], fallback: id);
    final inferredLocalName = _extractTrailingParenLabel(rawName);
    final name = _stripTrailingParenLabel(rawName);
    final localName = _pickFirstText([
      metadata['localName'],
      metadata['local_name'],
      metadata['commonName'],
      metadata['vernacularName'],
      inferredLocalName,
    ]);
    final scientificName = _pickFirstText([
      metadata['scientificName'],
      metadata['scientific_name'],
    ]);
    final family = _pickFirstText([metadata['family']]);
    final habitat = _pickFirstText([metadata['habitat'], metadata['location']]);
    final about = _pickFirstText([
      metadata['about'],
      metadata['description'],
      metadata['content'],
    ]);
    final sector = _pickFirstText([metadata['sector']]);
    final frequency = _pickFirstText([metadata['frequency']]);
    final year = _pickFirstText([metadata['year']]);
    final imageCandidates = _collectImageCandidates(metadata, null);
    final rawPhoto = imageCandidates.isNotEmpty ? imageCandidates.first : '';
    final photo = _resolveImageUrl(
      rawPhoto,
      id,
      fallbackName: name,
      scientificName: scientificName,
    );

    return {
      'id': id,
      'name': name,
      'englishName': name,
      'localName': localName,
      'scientificName': scientificName,
      'family': family,
      'habitat': habitat,
      'about': about,
      'sector': sector,
      'frequency': frequency,
      'year': year,
      'dataSource': _deriveDataSource(const {}, metadata),
      'photoRaw': rawPhoto,
      'photoCandidates': imageCandidates,
      'photo': photo,
      'updatedAt': _parseUpdatedAt(
        metadata['updatedAt'] ?? metadata['lastEntryDate'],
      ),
      'lastEntryDate': null,
      'lastEntryKg': '',
      'lastEntryMt': '',
      'q1': '',
      'q2': '',
      'q3': '',
      'q4': '',
      'annual': '',
    };
  }

  Future<void> _rebuildFishList() async {
    final data = (_statsDocs.isNotEmpty
            ? _statsDocs.map(_mapStat).toList()
            : _speciesMetadataDocs.map(_mapMetadata).toList())
      ..sort((a, b) {
        final left = _primaryName(a).toLowerCase();
        final right = _primaryName(b).toLowerCase();
        return left.compareTo(right);
      });
    final sectors = data
        .map((s) => _cleanText(s['sector']))
        .where((s) => s.isNotEmpty)
        .toSet()
        .toList()
      ..sort();

    if (_isLoading) {
      await (_minimumLoadingDelay ?? Future<void>.value());
    }
    if (!mounted) return;

    setState(() {
      _species = data;
      _sectors = ['All', ...sectors];
      _isLoading = false;
      _loadErrorMessage = null;
    });
    _loadingGuardTimer?.cancel();
    _applyFilters();
  }

  void _onSearchChanged() {
    _applyFilters();
  }

  DateTime? _parseUpdatedAt(dynamic value) {
    if (value is Timestamp) return value.toDate();
    if (value is String && value.isNotEmpty) {
      return DateTime.tryParse(value);
    }
    return null;
  }

  void _applyFilters() {
    final query = _searchController.text.trim().toLowerCase();
    final sectorFilter = _selectedSector.toLowerCase();

    final filtered = _species.where((species) {
      final matchesSector = _selectedSector == 'All' ||
          (species['sector'] ?? '').toString().toLowerCase() == sectorFilter;
      final matchesQuery = query.isEmpty || _matchesQuery(species, query);
      return matchesSector && matchesQuery;
    }).toList();

    setState(() {
      _filteredSpecies = filtered;
    });
  }

  bool _matchesQuery(Map<String, dynamic> species, String query) {
    return _fieldContains(species, 'name', query) ||
        _fieldContains(species, 'englishName', query) ||
        _fieldContains(species, 'localName', query) ||
        _fieldContains(species, 'scientificName', query) ||
        _fieldContains(species, 'sector', query) ||
        _fieldContains(species, 'frequency', query) ||
        _fieldContains(species, 'year', query);
  }

  bool _fieldContains(Map<String, dynamic> species, String key, String query) {
    final value = (species[key] ?? '').toString().toLowerCase();
    return value.contains(query);
  }

  @override
  Widget build(BuildContext context) {
    final padding = Responsive.pagePadding(context);
    final canPop = Navigator.canPop(context);
    return Scaffold(
      backgroundColor: _pageBottom,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
        elevation: 0,
        title: const FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            'Fish Production Data',
            maxLines: 1,
            style: TextStyle(
              fontFamily: 'serif',
              fontSize: 28,
              fontWeight: FontWeight.w800,
              color: _ink,
              letterSpacing: 0.2,
            ),
          ),
        ),
        titleSpacing: 2,
        leadingWidth: canPop ? 68 : null,
        leading: canPop
            ? Padding(
                padding: const EdgeInsets.only(left: 12),
                child: IconButton(
                  style: IconButton.styleFrom(
                    backgroundColor: Colors.white.withValues(alpha: 0.94),
                    foregroundColor: _ink,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18),
                ),
              )
            : null,
        centerTitle: false,
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
              constraints: BoxConstraints(
                maxWidth: Responsive.maxContentWidth(context),
              ),
              child: Padding(
                padding: EdgeInsets.fromLTRB(padding, 12, padding, 8),
                child: Column(
                  children: [
                    _buildHeaderCard(),
                    SizedBox(height: Responsive.verticalSpace(context) - 6),
                    _buildSearchBar(),
                    const SizedBox(height: 10),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: _buildFilterDropdown(),
                    ),
                    SizedBox(height: Responsive.verticalSpace(context) - 2),
                    Expanded(
                      child: _isLoading
                          ? const Center(child: CircularProgressIndicator())
                          : _filteredSpecies.isEmpty
                              ? _buildEmptyState()
                              : ListView.separated(
                                  padding: const EdgeInsets.only(bottom: 12),
                                  itemCount: _filteredSpecies.length,
                                  separatorBuilder: (_, __) =>
                                      const SizedBox(height: 12),
                                  itemBuilder: (context, index) {
                                    return _buildFishCard(_filteredSpecies[index]);
                                  },
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

  Widget _buildHeaderCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF12365B), Color(0xFF1F6EA8)],
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF12365B).withValues(alpha: 0.3),
            blurRadius: 14,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white24),
            ),
            child: const Icon(Icons.insights_rounded, color: Colors.white),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Fish Production Records',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  'Browse local names, source details, and quarterly production totals for each species.',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.9),
                    fontSize: 12.4,
                    height: 1.3,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _isLoading
                      ? 'Loading production records...'
                      : _loadErrorMessage != null && _species.isEmpty
                      ? 'Unable to reach fish production data right now.'
                      : '${_filteredSpecies.length} shown of ${_species.length} species',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.82),
                    fontSize: 12.1,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          IconButton(
            tooltip: 'Detect fish',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const DetectionScreen(
                    launchMode: DetectionLaunchMode.camera,
                  ),
                ),
              );
            },
            style: IconButton.styleFrom(
              backgroundColor: Colors.white.withValues(alpha: 0.16),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            icon: const Icon(Icons.photo_camera_outlined),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    final message =
        _loadErrorMessage ??
        'No production data found for the current search/filter.';
    final showRetry = _loadErrorMessage != null;
    return Center(
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.92),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0xFFD8E4F0)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: _subtleInk,
                fontWeight: FontWeight.w600,
              ),
            ),
            if (showRetry) ...[
              const SizedBox(height: 14),
              FilledButton.icon(
                onPressed: () => unawaited(_loadInitialData()),
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Retry'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildSearchBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Colors.white, Color(0xFFF4F9FF)],
        ),
        border: Border.all(color: const Color(0xFFD8E4F0)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF8DA7C3).withValues(alpha: 0.14),
            blurRadius: 10,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        children: [
          const Icon(Icons.search_rounded, color: _subtleInk, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              controller: _searchController,
              style: const TextStyle(
                color: _ink,
                fontWeight: FontWeight.w600,
                fontSize: 14.2,
              ),
              decoration: const InputDecoration(
                border: InputBorder.none,
                hintText: 'Search species',
                hintStyle: TextStyle(
                  color: _subtleInk,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),
          if (_searchController.text.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.close_rounded, color: _subtleInk),
              onPressed: () => _searchController.clear(),
              visualDensity: VisualDensity.compact,
              tooltip: 'Clear search',
            ),
        ],
      ),
    );
  }

  Widget _buildFilterDropdown() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      constraints: const BoxConstraints(minWidth: 150, maxWidth: 280),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Colors.white, Color(0xFFF5FAFF)],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFD8E4F0)),
      ),
      child: Row(
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: const Color(0xFFEAF1FF),
              borderRadius: BorderRadius.circular(9),
            ),
            child: const Icon(Icons.tune_rounded, size: 16, color: _ink),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: _selectedSector,
                isExpanded: true,
                icon: const Icon(Icons.keyboard_arrow_down_rounded, color: _ink),
                items: _sectors
                    .map(
                      (sector) => DropdownMenuItem<String>(
                        value: sector,
                        child: Text(
                          sector,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: _ink,
                          ),
                        ),
                      ),
                    )
                    .toList(),
                onChanged: (value) {
                  if (value == null) return;
                  setState(() => _selectedSector = value);
                  _applyFilters();
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _primaryName(Map<String, dynamic> species) {
    final localName = _cleanText(species['localName']);
    if (localName.isNotEmpty) return localName;
    final englishName = _cleanText(species['englishName']);
    if (englishName.isNotEmpty) return englishName;
    return _cleanText(species['name']);
  }

  String _secondaryName(Map<String, dynamic> species) {
    final primary = _primaryName(species).toLowerCase();
    for (final candidate in [
      _cleanText(species['englishName']),
      _cleanText(species['scientificName']),
      _cleanText(species['name']),
    ]) {
      if (candidate.isEmpty) continue;
      if (candidate.toLowerCase() == primary) continue;
      return candidate;
    }
    return '';
  }

  Widget _buildFishCard(Map<String, dynamic> fish) {
    final imageUrl = _cleanText(fish['photo']);
    final displayName = _primaryName(fish);
    final secondaryName = _secondaryName(fish);
    final scientificName = _cleanText(fish['scientificName']);
    final about = _cleanText(fish['about']);
    final dataSource = _cleanText(fish['dataSource']);
    final year = _cleanText(fish['year']);
    final sector = _cleanText(fish['sector']);
    final frequency = _cleanText(fish['frequency']);
    final rawPhoto = _cleanText(fish['photoRaw']);
    final rawCandidates =
        (fish['photoCandidates'] is List)
            ? List<String>.from(
                (fish['photoCandidates'] as List)
                    .map((item) => item.toString())
                    .where((item) => item.trim().isNotEmpty),
              )
            : const <String>[];
    final docId = (fish['id'] ?? '').toString();
    final annual = (fish['annual'] ?? '').toString();
    final q1 = (fish['q1'] ?? '').toString();
    final q2 = (fish['q2'] ?? '').toString();
    final q3 = (fish['q3'] ?? '').toString();
    final q4 = (fish['q4'] ?? '').toString();
    final hasProduction = [annual, q1, q2, q3, q4].any((v) => v.isNotEmpty);

    void openDetails() {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => MarineDetailsPage(fish: fish),
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final isVeryNarrow = constraints.maxWidth < 320;
        final isCompact = constraints.maxWidth < 390;
        final imageWidth = isVeryNarrow
            ? constraints.maxWidth
            : isCompact
                ? 112.0
                : 128.0;
        final imageHeight = isVeryNarrow
            ? 150.0
            : isCompact
                ? 88.0
                : 100.0;
        final cardPadding = isCompact ? 10.0 : 12.0;

        final imageFrame = _fishImageFrame(
          width: imageWidth,
          height: imageHeight,
          resolvedUrl: imageUrl,
          name: displayName,
          scientificName: scientificName,
          docId: docId,
          rawPath: rawPhoto,
          rawCandidates: rawCandidates,
        );

        final summary = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    displayName,
                    maxLines: isVeryNarrow ? 3 : 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: _ink,
                      height: 1.12,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 36,
                  height: 36,
                  child: IconButton(
                    onPressed: openDetails,
                    style: IconButton.styleFrom(
                      backgroundColor: const Color(0xFFEAF1FF),
                      foregroundColor: _ink,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(11),
                      ),
                    ),
                    icon: const Icon(Icons.open_in_new_rounded, size: 18),
                    padding: EdgeInsets.zero,
                    splashRadius: 18,
                    tooltip: 'Open details',
                  ),
                ),
              ],
            ),
            if (secondaryName.isNotEmpty) ...[
              const SizedBox(height: 5),
              Text(
                secondaryName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 13.5,
                  color: _subtleInk,
                  fontWeight: FontWeight.w700,
                  fontStyle: FontStyle.italic,
                  height: 1.2,
                ),
              ),
            ],
            const SizedBox(height: 4),
            const Text(
              'Per Metric Ton',
              style: TextStyle(
                fontSize: 12,
                color: _subtleInk,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.1,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                if (year.isNotEmpty) _metaPill('Year $year'),
                if (sector.isNotEmpty) _metaPill(sector),
                if (frequency.isNotEmpty) _metaPill(frequency),
              ],
            ),
          ],
        );

        return Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: openDetails,
            child: Ink(
              padding: EdgeInsets.all(cardPadding),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Colors.white, Color(0xFFF7FBFF)],
                ),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: const Color(0xFFD8E4F0)),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF8DA7C3).withValues(alpha: 0.13),
                    blurRadius: 10,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (isVeryNarrow) ...[
                    imageFrame,
                    const SizedBox(height: 10),
                    summary,
                  ] else
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        imageFrame,
                        const SizedBox(width: 12),
                        Expanded(child: summary),
                      ],
                    ),
                  if (about.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Text(
                      about,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12.8,
                        color: _subtleInk,
                        height: 1.35,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                  if (dataSource.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Padding(
                          padding: EdgeInsets.only(top: 1),
                          child: Icon(
                            Icons.source_outlined,
                            size: 14,
                            color: _subtleInk,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            dataSource,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 12.1,
                              color: _subtleInk,
                              height: 1.3,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 10),
                  if (hasProduction)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.fromLTRB(10, 9, 10, 9),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF2F7FD),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: const Color(0xFFE2ECF7)),
                      ),
                      child: Column(
                        children: [
                          _productionRow([q1, q2, q3, q4, annual]),
                          const SizedBox(height: 5),
                          _productionRowLabels(
                            const ['Q1', 'Q2', 'Q3', 'Q4', 'Annual'],
                          ),
                        ],
                      ),
                    )
                  else
                    const Padding(
                      padding: EdgeInsets.only(top: 2),
                      child: Text(
                        'No production data yet',
                        style: TextStyle(
                          fontSize: 12.2,
                          color: _subtleInk,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _fishImageFrame({
    required double width,
    required double height,
    required String resolvedUrl,
    required String name,
    required String scientificName,
    required String docId,
    required String rawPath,
    required List<String> rawCandidates,
  }) {
    return Container(
      width: width,
      height: height,
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE0EBF6)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF8DA7C3).withValues(alpha: 0.12),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: DecoratedBox(
          decoration: const BoxDecoration(color: Color(0xFFF8FBFF)),
          child: _buildSpeciesImage(
            resolvedUrl: resolvedUrl,
            name: name,
            scientificName: scientificName,
            docId: docId,
            rawPath: rawPath,
            rawCandidates: rawCandidates,
          ),
        ),
      ),
    );
  }

  Widget _metaPill(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFFEAF1FF),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 11.2,
          fontWeight: FontWeight.w700,
          color: _ink,
        ),
      ),
    );
  }

  Widget _buildSpeciesImage({
    required String resolvedUrl,
    required String name,
    String scientificName = '',
    required String docId,
    String? rawPath,
    List<String> rawCandidates = const [],
  }) {
    final overrideUrl = _overrideForImage(
      docId: docId,
      name: name,
      scientificName: scientificName,
    );
    final directCandidates = <String>[
      resolvedUrl,
      for (final raw in rawCandidates)
        _resolveImageUrl(
          raw,
          docId,
          fallbackName: name,
          scientificName: scientificName,
        ),
    ].where((candidate) => candidate.trim().isNotEmpty).toList();

    for (final candidate in directCandidates) {
      if (candidate.startsWith('data:image')) {
        final bytes = _bytesFromDataUrl(candidate);
        if (bytes != null) {
          return Image.memory(
            bytes,
            fit: BoxFit.contain,
            errorBuilder: (_, __, ___) => _placeholderImage(name),
          );
        }
      }
      if (candidate.startsWith('asset:')) {
        return Image.asset(
          candidate.replaceFirst('asset:', ''),
          fit: BoxFit.contain,
          errorBuilder: (_, __, ___) => _placeholderImage(name),
        );
      }
      if (candidate.startsWith('http')) {
        return _networkImageWithFallback(
          candidate,
          name: name,
          fallbackUrl: overrideUrl,
        );
      }
    }

    final dedupedStorageCandidates = <String>{
      if (rawPath != null) ..._candidatePathsFromRaw(rawPath),
      for (final raw in rawCandidates) ..._candidatePathsFromRaw(raw),
      ..._guessStoragePaths(docId, displayName: name),
      if (scientificName.trim().isNotEmpty) ..._guessStoragePaths(scientificName),
    }.toList();
    final candidates = <String>[
      ...dedupedStorageCandidates,
    ];

    if (candidates.isEmpty) {
      if (overrideUrl != null && overrideUrl.isNotEmpty) {
        if (overrideUrl.startsWith('asset:')) {
          return Image.asset(
            overrideUrl.replaceFirst('asset:', ''),
            fit: BoxFit.contain,
            errorBuilder: (_, __, ___) => _placeholderImage(name),
          );
        }
        return _networkImageWithFallback(overrideUrl, name: name);
      }
      return _placeholderImage(name);
    }

    final primary = candidates.first;
    final fallbacks = candidates.skip(1).toList();

    return FutureBuilder<String?>(
      future: _getStorageUrl(primary, fallbacks),
      builder: (context, snapshot) {
        final url = snapshot.data;
        if (url != null && url.isNotEmpty) {
          return _networkImageWithFallback(
            url,
            name: name,
            fallbackUrl: overrideUrl,
          );
        }
        if (snapshot.connectionState == ConnectionState.waiting) {
          return _placeholderImage(name);
        }
        if (overrideUrl != null && overrideUrl.isNotEmpty) {
          if (overrideUrl.startsWith('asset:')) {
            return Image.asset(
              overrideUrl.replaceFirst('asset:', ''),
              fit: BoxFit.contain,
              errorBuilder: (_, __, ___) => _placeholderImage(name),
            );
          }
          return _networkImageWithFallback(overrideUrl, name: name);
        }
        return _placeholderImage(name);
      },
    );
  }

  Widget _networkImageWithFallback(
    String url, {
    required String name,
    String? fallbackUrl,
  }) {
    return Image.network(
      url,
      fit: BoxFit.contain,
      errorBuilder: (_, __, ___) {
        if (fallbackUrl != null &&
            fallbackUrl.isNotEmpty &&
            fallbackUrl != url) {
          if (fallbackUrl.startsWith('asset:')) {
            return Image.asset(
              fallbackUrl.replaceFirst('asset:', ''),
              fit: BoxFit.contain,
              errorBuilder: (_, __, ___) => _placeholderImage(name),
            );
          }
          return Image.network(
            fallbackUrl,
            fit: BoxFit.contain,
            errorBuilder: (_, __, ___) => _placeholderImage(name),
          );
        }
        return _placeholderImage(name);
      },
    );
  }

  Widget _placeholderImage(String name) {
    final initial = name.isNotEmpty ? name.substring(0, 1).toUpperCase() : '?';
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFEAF1FF),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Center(
        child: Text(
          initial,
          style: const TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w800,
            color: _subtleInk,
          ),
        ),
      ),
    );
  }

  String _resolveImageUrl(
    String url,
    String docId, {
    String? fallbackName,
    String? scientificName,
  }) {
    final trimmed = url.trim();
    if (trimmed.isEmpty) {
      return _overrideForImage(
            docId: docId,
            name: fallbackName,
            scientificName: scientificName,
          ) ??
          '';
    }
    if (trimmed.startsWith('data:image')) {
      return trimmed;
    }
    if (trimmed.startsWith('=IMAGE(')) {
      final extracted = _extractUrlFromImageFormula(trimmed);
      if (extracted != null && extracted.isNotEmpty) {
        return _resolveImageUrl(
          extracted,
          docId,
          fallbackName: fallbackName,
          scientificName: scientificName,
        );
      }
      return _overrideForImage(
            docId: docId,
            name: fallbackName,
            scientificName: scientificName,
          ) ??
          '';
    }
    if (trimmed.startsWith('asset:')) {
      return trimmed;
    }
    if (trimmed.startsWith('gs://')) {
      return _overrideForImage(
            docId: docId,
            name: fallbackName,
            scientificName: scientificName,
          ) ??
          '';
    }

    // Paths like "marine_life_stats/x.jpg" are Storage-relative, not web URLs.
    if (!trimmed.contains('://')) {
      final firstSegment = trimmed.split('/').first;
      final looksLikeDomain = firstSegment.contains('.');
      if (!looksLikeDomain) {
        return _overrideForImage(
              docId: docId,
              name: fallbackName,
              scientificName: scientificName,
            ) ??
            '';
      }
    }

    try {
      Uri uri = Uri.parse(trimmed);

      if (uri.scheme.isEmpty) {
        uri = Uri.parse('https://$trimmed');
      }
      if (uri.host.isEmpty) {
        return _overrideForImage(
              docId: docId,
              name: fallbackName,
              scientificName: scientificName,
            ) ??
            '';
      }

      final host = uri.host.toLowerCase();
      final isLocalHost =
          host == '127.0.0.1' || host == 'localhost' || host == '0.0.0.0';
      final isAndroidEmulator =
          !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

      if (isLocalHost) {
        if (isAndroidEmulator &&
            (uri.scheme == 'http' || uri.scheme == 'https')) {
          final mapped = uri.replace(host: '10.0.2.2');
          final normalized = mapped.toString();
          if (normalized.isNotEmpty) {
            return normalized;
          }
        }
        return _overrideForImage(
              docId: docId,
              name: fallbackName,
              scientificName: scientificName,
            ) ??
            '';
      }

      if (uri.scheme == 'http') {
        uri = uri.replace(scheme: 'https');
      }
      if (uri.scheme != 'https') {
        return _overrideForImage(
              docId: docId,
              name: fallbackName,
              scientificName: scientificName,
            ) ??
            '';
      }

      final normalized = uri.toString();
      if (normalized.isNotEmpty) {
        return normalized;
      }
    } catch (_) {
    }
    return _overrideForImage(
          docId: docId,
          name: fallbackName,
          scientificName: scientificName,
        ) ??
        '';
  }

  String? _overrideForId(String id) {
    final slug = _slug(id);
    return _photoOverrides[id] ?? _photoOverrides[slug];
  }

  String? _overrideForImage({
    required String docId,
    String? name,
    String? scientificName,
  }) {
    final byId = _overrideForId(docId);
    if (byId != null && byId.isNotEmpty) return byId;
    if (name != null && name.trim().isNotEmpty) {
      final byName = _photoOverrides[_slug(name)];
      if (byName != null && byName.isNotEmpty) return byName;
    }
    if (scientificName != null && scientificName.trim().isNotEmpty) {
      final byScientific = _photoOverrides[_slug(scientificName)];
      if (byScientific != null && byScientific.isNotEmpty) {
        return byScientific;
      }
    }
    return null;
  }

  String _slug(String input) {
    return input
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'-+'), '-')
        .replaceAll(RegExp(r'^-|-$'), '');
  }

  /// Extract possible Firebase Storage relative paths from raw URLs that point to local dev servers.
  List<String> _candidatePathsFromRaw(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return const [];
    if (trimmed.startsWith('gs://')) return [trimmed];

    // If already looks like a storage path (no scheme), keep as-is.
    final uri = Uri.tryParse(trimmed);
    if (uri == null) return const [];

    // Relative path without scheme/host.
    if (uri.scheme.isEmpty && uri.host.isEmpty) {
      return [trimmed.replaceAll('\\', '/')];
    }

    // Convert local dev URLs like http://127.0.0.1:8000/storage/species_photos/foo.jpg to storage path species_photos/foo.jpg
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

  String? _extractUrlFromImageFormula(String formula) {
    // Supports =IMAGE("http://...") or =IMAGE('http://...')
    final regex =
        RegExp("=IMAGE\\(['\"]([^'\"]+)['\"].*\\)", caseSensitive: false);
    final match = regex.firstMatch(formula);
    if (match != null && match.groupCount >= 1) {
      final inner = match.group(1);
      if (inner != null && inner.trim().isNotEmpty) {
        return inner.trim();
      }
    }
    return null;
  }

  String _formatMetric(dynamic value) {
    final str = _cleanText(value).replaceAll(',', '');
    if (str.isEmpty) return '';
    final num? parsed = num.tryParse(str);
    if (parsed == null) return str;
    return parsed.toStringAsFixed(parsed % 1 == 0 ? 0 : 2);
  }

  Uint8List? _bytesFromDataUrl(String value) {
    try {
      final comma = value.indexOf(',');
      if (comma == -1) return null;
      return base64Decode(value.substring(comma + 1));
    } catch (_) {
      return null;
    }
  }

  Widget _productionRow(List<String> values) {
    return Row(
      children: values
          .map(
            (v) => Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    v.isNotEmpty ? v : '-',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 14.2,
                      color: _ink,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
            ),
          )
          .toList(),
    );
  }

  Widget _productionRowLabels(List<String> labels) {
    return Row(
      children: labels
          .map(
            (v) => Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 1),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    v,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 11.7,
                      fontWeight: FontWeight.w700,
                      color: _subtleInk,
                    ),
                  ),
                ),
              ),
            ),
          )
          .toList(),
    );
  }

  List<String> _guessStoragePaths(String docId, {String? displayName}) {
    final ids = <String>{};
    void addId(String value) {
      final v = value.trim();
      if (v.isEmpty) return;
      ids.add(v);
      ids.add(_slug(v));
      ids.add(_slug(v).replaceAll('-', '_'));
      ids.add(v.replaceAll(' ', '-'));
      ids.add(v.replaceAll(' ', '_'));
    }

    addId(docId);
    if (displayName != null) addId(displayName);
    ids.removeWhere((e) => e.trim().isEmpty);
    if (ids.isEmpty) return const [];

    const folders = <String>[
      'marine_life_stats',
      'species_database',
      'species_photos',
      'marine_life',
    ];
    const exts = <String>['jpg', 'jpeg', 'png', 'webp'];
    final out = <String>[];
    for (final id in ids) {
      for (final folder in folders) {
        for (final ext in exts) {
          out.add('$folder/$id.$ext');
        }
      }
    }
    return out;
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

}
