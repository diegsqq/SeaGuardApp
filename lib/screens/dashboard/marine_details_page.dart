import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';

import '../../utils/functions_config.dart';
import '../../utils/responsive.dart';

class MarineDetailsPage extends StatefulWidget {
  /// Expects a fish production map coming from Firestore (`marine_life_stats`
  /// collection, or `species_database` as fallback).
  /// Keys we use: name/englishName, sector, frequency, year, q1..q4, annual,
  /// updatedAt (DateTime?), lastEntry*, image/photo, id.
  final Map<String, dynamic> fish;

  const MarineDetailsPage({super.key, required this.fish});

  @override
  State<MarineDetailsPage> createState() => _MarineDetailsPageState();
}

class _MarineDetailsPageState extends State<MarineDetailsPage> {
  static const Color _pageTop = Color(0xFFEAF4FF);
  static const Color _pageBottom = Color(0xFFF8FCFF);
  static const Color _ink = Color(0xFF102A43);
  static const Color _subtleInk = Color(0xFF486581);

  static const Map<String, String> _photoOverrides = {
    'apolemichthys-trimaculatus':
        'https://www.fishbase.se/images/thumbnails/jpg/tn_Aptri_uc.jpg',
    'chanos-chanos':
        'https://upload.wikimedia.org/wikipedia/commons/thumb/a/a9/Chanos_chanos.jpg/320px-Chanos_chanos.jpg',
    'lates-calcarifer':
        'https://upload.wikimedia.org/wikipedia/commons/thumb/9/9e/Lates_calcarifer_scox.jpg/320px-Lates_calcarifer_scox.jpg',
    'litopenaeus-vannamei':
        'https://upload.wikimedia.org/wikipedia/commons/thumb/7/7d/Litopenaeus_vannamei_01.jpg/320px-Litopenaeus_vannamei_01.jpg',
    'penaeus-monodon':
        'https://upload.wikimedia.org/wikipedia/commons/thumb/8/83/Giant_tiger_prawn.jpg/320px-Giant_tiger_prawn.jpg',
  };

  final Map<String, Future<String?>> _storageUrlCache = {};
  late final Future<_AiSectionData> _aiSectionsFuture;

  @override
  void initState() {
    super.initState();
    _aiSectionsFuture = _loadAiSectionData();
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

  List<String> _stringList(dynamic raw) {
    if (raw is! List) return const [];
    return raw
        .map((item) => _cleanText(item))
        .where((item) => item.isNotEmpty)
        .toList();
  }

  String _formatUpdatedAt(dynamic value) {
    DateTime? date;
    if (value is DateTime) {
      date = value;
    } else if (value is String && value.isNotEmpty) {
      date = DateTime.tryParse(value);
    }
    if (date == null) return '';
    return DateFormat('MMM d, yyyy').format(date);
  }

  String _displayName({
    required String englishName,
    required String localName,
  }) {
    if (localName.isNotEmpty) return localName;
    return englishName;
  }

  String _supportingName({
    required String primaryName,
    required String englishName,
    required String scientificName,
  }) {
    for (final candidate in [englishName, scientificName]) {
      if (candidate.isEmpty) continue;
      if (candidate.toLowerCase() == primaryName.toLowerCase()) continue;
      return candidate;
    }
    return '';
  }

  @override
  Widget build(BuildContext context) {
    final padding = Responsive.pagePadding(context);
    final maxWidth = Responsive.maxContentWidth(context);

    final String englishName =
        _cleanText(widget.fish['englishName']) != ''
            ? _cleanText(widget.fish['englishName'])
            : _cleanText(widget.fish['name']);
    final String localName = _cleanText(widget.fish['localName']);
    final String scientificName = _cleanText(widget.fish['scientificName']);
    final String displayName = _displayName(
      englishName: englishName,
      localName: localName,
    );
    final String supportingName = _supportingName(
      primaryName: displayName,
      englishName: englishName,
      scientificName: scientificName,
    );
    final String family = _cleanText(widget.fish['family']);
    final String habitat = _cleanText(widget.fish['habitat']);
    final String about = _cleanText(widget.fish['about']);
    final String dataSource = _cleanText(widget.fish['dataSource']);
    final String rawPhoto =
        _cleanText(widget.fish['photoRaw']) != ''
            ? _cleanText(widget.fish['photoRaw'])
            : _cleanText(widget.fish['photo']);
    final List<String> photoCandidates = _stringList(widget.fish['photoCandidates']);
    final String docId = (widget.fish['id'] ?? '').toString();
    final String sector = _cleanText(widget.fish['sector']);
    final String frequency = _cleanText(widget.fish['frequency']);
    final String year = _cleanText(widget.fish['year']);

    final String photoUrl = _resolveImageUrl(
      _cleanText(widget.fish['photo']) != ''
          ? _cleanText(widget.fish['photo'])
          : _cleanText(widget.fish['imageUrl']),
      id: docId,
      fallbackName: displayName,
      scientificName: scientificName,
    );

    final String lastEntryKgRaw = _cleanText(widget.fish['lastEntryKg']);
    final String lastEntryMtRaw = _cleanText(widget.fish['lastEntryMt']);
    final String lastEntryDate = _formatUpdatedAt(widget.fish['lastEntryDate']);
    final String lastEntryKg = lastEntryKgRaw == '0' ? '' : lastEntryKgRaw;
    final String lastEntryMt = lastEntryMtRaw == '0' ? '' : lastEntryMtRaw;

    final String annual = _cleanText(widget.fish['annual']);
    final String q1 = _cleanText(widget.fish['q1']);
    final String q2 = _cleanText(widget.fish['q2']);
    final String q3 = _cleanText(widget.fish['q3']);
    final String q4 = _cleanText(widget.fish['q4']);

    final bool hasProduction = [annual, q1, q2, q3, q4].any(
      (v) => v.isNotEmpty,
    );
    final bool hasLastEntry =
        lastEntryDate.isNotEmpty || lastEntryKg.isNotEmpty || lastEntryMt.isNotEmpty;

    final details = <MapEntry<String, String>>[
      if (localName.isNotEmpty) MapEntry('Local Name', localName),
      if (englishName.isNotEmpty &&
          englishName.toLowerCase() != displayName.toLowerCase())
        MapEntry('English Name', englishName),
      if (scientificName.isNotEmpty &&
          scientificName.toLowerCase() != displayName.toLowerCase())
        MapEntry('Scientific Name', scientificName),
      if (family.isNotEmpty) MapEntry('Family', family),
      if (sector.isNotEmpty) MapEntry('Sector', sector),
      if (frequency.isNotEmpty) MapEntry('Frequency', frequency),
      if (year.isNotEmpty) MapEntry('Year', year),
      if (dataSource.isNotEmpty) MapEntry('Data Source', dataSource),
    ];

    final needsAiBackfill = habitat.trim().isEmpty || about.trim().isEmpty;

    return Scaffold(
      backgroundColor: _pageBottom,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
        elevation: 0,
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
        title: const Text(
          'Fish Production Data',
          style: TextStyle(
            fontFamily: 'serif',
            fontSize: 30,
            fontWeight: FontWeight.w800,
            color: _ink,
            letterSpacing: 0.2,
          ),
        ),
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
              constraints: BoxConstraints(maxWidth: maxWidth),
              child: SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(padding, 12, padding, padding),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildHeroCard(
                      primaryName: displayName,
                      supportingName: supportingName,
                      sector: sector,
                      frequency: frequency,
                      year: year,
                      photo: _buildPhoto(
                        resolvedUrl: photoUrl,
                        rawPath: rawPhoto,
                        rawCandidates: photoCandidates,
                        docId: docId,
                        fallbackLabel: displayName,
                        scientificName: scientificName,
                      ),
                    ),
                    const SizedBox(height: 14),
                    if (details.isNotEmpty) _buildInfoCard(details),
                    const SizedBox(height: 12),
                    if (needsAiBackfill)
                      FutureBuilder<_AiSectionData>(
                        future: _aiSectionsFuture,
                        builder: (context, snapshot) {
                          final aiData = snapshot.data;
                          final envText = habitat.trim().isNotEmpty
                              ? habitat
                              : (aiData?.environment ??
                                    _localEnvironmentFallback(
                                      fishName: displayName,
                                      sector: sector,
                                    ));
                          final aboutText = about.trim().isNotEmpty
                              ? about
                              : (aiData?.about ??
                                    _localAboutFallback(
                                      fishName: displayName,
                                      scientificName: scientificName,
                                      family: family,
                                    ));
                          final aiSource = (aiData?.source ?? '').toLowerCase();
                          final label = aiSource == 'http'
                              ? 'AI'
                              : aiSource.isNotEmpty
                              ? 'AI local'
                              : null;
                          final waiting = snapshot.connectionState ==
                              ConnectionState.waiting;

                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _buildSectionCard(
                                icon: Icons.public_rounded,
                                title: 'Environment',
                                value: envText,
                                sourceLabel: habitat.trim().isEmpty ? label : null,
                                loading: waiting && habitat.trim().isEmpty,
                              ),
                              const SizedBox(height: 12),
                              _buildSectionCard(
                                icon: Icons.menu_book_rounded,
                                title: 'About $displayName',
                                value: aboutText,
                                sourceLabel: about.trim().isEmpty ? label : null,
                                loading: waiting && about.trim().isEmpty,
                              ),
                            ],
                          );
                        },
                      )
                    else ...[
                      _buildSectionCard(
                        icon: Icons.public_rounded,
                        title: 'Environment',
                        value: habitat,
                      ),
                      const SizedBox(height: 12),
                      _buildSectionCard(
                        icon: Icons.menu_book_rounded,
                        title: 'About $displayName',
                        value: about,
                      ),
                    ],
                    const SizedBox(height: 12),
                    if (hasProduction)
                      _productionTable(
                        q1: q1,
                        q2: q2,
                        q3: q3,
                        q4: q4,
                        annual: annual,
                      )
                    else
                      _buildSectionCard(
                        icon: Icons.bar_chart_rounded,
                        title: 'Production',
                        value: 'No production data available.',
                      ),
                    if (hasLastEntry) ...[
                      const SizedBox(height: 12),
                      _buildLastEntryCard(
                        date: lastEntryDate,
                        kg: lastEntryKg,
                        mt: lastEntryMt,
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<_AiSectionData> _loadAiSectionData() async {
    final localName = _cleanText(widget.fish['localName']);
    final fishName = _displayName(
      englishName: _cleanText(widget.fish['englishName']).isNotEmpty
          ? _cleanText(widget.fish['englishName'])
          : _cleanText(widget.fish['name']),
      localName: localName,
    );
    final scientificName = _cleanText(widget.fish['scientificName']);
    final family = _cleanText(widget.fish['family']);
    final sector = _cleanText(widget.fish['sector']);
    final frequency = _cleanText(widget.fish['frequency']);
    final year = _cleanText(widget.fish['year']);
    final habitat = _cleanText(widget.fish['habitat']);
    final about = _cleanText(widget.fish['about']);
    final docId = _cleanText(widget.fish['id']);
    final photoUrl = _resolveImageUrl(
      _cleanText(widget.fish['photo']).isNotEmpty
          ? _cleanText(widget.fish['photo'])
          : _cleanText(widget.fish['imageUrl']),
      id: docId,
      fallbackName: fishName,
      scientificName: scientificName,
    );

    if (habitat.isNotEmpty && about.isNotEmpty) {
      return _AiSectionData(environment: habitat, about: about, source: '');
    }

    final shareText = [
      if (localName.isNotEmpty) 'Local name: $localName',
      if (family.isNotEmpty) 'Family: $family',
      if (sector.isNotEmpty) 'Sector: $sector',
      if (frequency.isNotEmpty) 'Frequency: $frequency',
      if (year.isNotEmpty) 'Year: $year',
    ].join('\n');

    final payloadBase = <String, dynamic>{
      'englishName': fishName,
      if (scientificName.isNotEmpty) 'scientificName': scientificName,
      if (habitat.isNotEmpty) 'habitat': habitat,
      if (about.isNotEmpty) 'description': about,
      if (photoUrl.isNotEmpty) 'imageUrl': photoUrl,
      if (shareText.isNotEmpty) 'shareText': shareText,
      'history': const <Map<String, String>>[],
    };

    String resolvedEnvironment = habitat;
    String resolvedAbout = about;
    var source = '';

    if (resolvedEnvironment.isEmpty) {
      final envReply = await _askFishAssistantHttp({
        ...payloadBase,
        'question':
            'Write one concise sentence describing the typical habitat/environment for this species. No markdown.',
      });
      if (envReply != null && envReply.answer.trim().isNotEmpty) {
        resolvedEnvironment = _cleanAiText(envReply.answer);
        source = envReply.source;
      } else {
        resolvedEnvironment = _localEnvironmentFallback(
          fishName: fishName,
          sector: sector,
        );
        source = source.isEmpty ? 'local' : source;
      }
    }

    if (resolvedAbout.isEmpty) {
      final aboutReply = await _askFishAssistantHttp({
        ...payloadBase,
        'question':
            'Write two concise sentences about this fish species, including practical importance. No markdown.',
      });
      if (aboutReply != null && aboutReply.answer.trim().isNotEmpty) {
        resolvedAbout = _cleanAiText(aboutReply.answer);
        if (source.isEmpty) source = aboutReply.source;
      } else {
        resolvedAbout = _localAboutFallback(
          fishName: fishName,
          scientificName: scientificName,
          family: family,
        );
        if (source.isEmpty) source = 'local';
      }
    }

    if (resolvedEnvironment.trim().isEmpty) {
      resolvedEnvironment = _localEnvironmentFallback(
        fishName: fishName,
        sector: sector,
      );
      if (source.isEmpty) source = 'local';
    }
    if (resolvedAbout.trim().isEmpty) {
      resolvedAbout = _localAboutFallback(
        fishName: fishName,
        scientificName: scientificName,
        family: family,
      );
      if (source.isEmpty) source = 'local';
    }

    return _AiSectionData(
      environment: resolvedEnvironment,
      about: resolvedAbout,
      source: source,
    );
  }

  String _cleanAiText(String text) {
    return text
        .replaceAll('\r\n', '\n')
        .replaceAll('\r', '\n')
        .replaceAll(RegExp(r'\n{3,}'), '\n\n')
        .trim();
  }

  String _localEnvironmentFallback({
    required String fishName,
    required String sector,
  }) {
    final base = fishName.isNotEmpty ? fishName : 'This species';
    if (sector.toLowerCase().contains('aquaculture')) {
      return '$base is commonly managed in aquaculture waters with stable temperature and good water quality.';
    }
    return '$base is typically found in coastal and marine-influenced waters where salinity and habitat conditions support feeding and growth.';
  }

  String _localAboutFallback({
    required String fishName,
    required String scientificName,
    required String family,
  }) {
    final base = fishName.isNotEmpty ? fishName : 'This species';
    final sci = scientificName.isNotEmpty ? ' ($scientificName)' : '';
    final fam = family.isNotEmpty ? ' It belongs to the $family family.' : '';
    return '$base$sci is an economically important fish used for local food supply and fisheries monitoring.$fam';
  }

  Future<_AiAnswer?> _askFishAssistantHttp(Map<String, dynamic> payload) async {
    const endpoints = <String>[
      'ai/ask/fish',
      'ai-ask-fish',
      'aiAskFish',
      'ai/assistant',
      'ai-assistant',
      'aiAssistant',
    ];

    for (final path in endpoints) {
      final uris = functionUriCandidates(path);
      for (final uri in uris) {
        try {
          final resp = await http
              .post(
                uri,
                headers: const {'Content-Type': 'application/json'},
                body: jsonEncode(payload),
              )
              .timeout(const Duration(seconds: 12));
          if (resp.statusCode != 200) continue;

          final decoded = jsonDecode(resp.body);
          if (decoded is! Map) continue;

          final body = Map<String, dynamic>.from(
            decoded.cast<String, dynamic>(),
          );
          final answer = (body['answer'] ??
                  (body['data'] is Map ? body['data']['answer'] : null))
              .toString()
              .trim();
          if (answer.isEmpty) continue;
          final source = (body['source'] ?? 'http').toString();
          return _AiAnswer(answer: answer, source: source);
        } catch (_) {}
      }
    }
    return null;
  }

  Widget _buildHeroCard({
    required String primaryName,
    required String supportingName,
    required String sector,
    required String frequency,
    required String year,
    required Widget photo,
  }) {
    return Container(
      width: double.infinity,
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
          Text(
            primaryName,
            style: const TextStyle(
              fontSize: 31,
              height: 1.05,
              fontWeight: FontWeight.w800,
              color: _ink,
            ),
          ),
          if (supportingName.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              supportingName,
              style: const TextStyle(
                fontSize: 14.5,
                color: _subtleInk,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (year.isNotEmpty) _pill('Year $year'),
              if (sector.isNotEmpty) _pill(sector),
              if (frequency.isNotEmpty) _pill(frequency),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: AspectRatio(
              aspectRatio: 4 / 3,
              child: photo,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoCard(List<MapEntry<String, String>> entries) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFD8E4F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.info_outline_rounded, size: 18, color: Color(0xFF124F8A)),
              SizedBox(width: 8),
              Text(
                'Species Profile',
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  color: _ink,
                  fontSize: 15,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ...entries.map(_infoRow),
        ],
      ),
    );
  }

  Widget _infoRow(MapEntry<String, String> entry) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              entry.key,
              style: const TextStyle(
                fontSize: 13.3,
                color: _subtleInk,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              entry.value,
              style: const TextStyle(
                fontSize: 13.8,
                color: _ink,
                fontWeight: FontWeight.w700,
                height: 1.3,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionCard({
    required IconData icon,
    required String title,
    required String value,
    String? sourceLabel,
    bool loading = false,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFD8E4F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: const Color(0xFFEAF1FF),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Icon(icon, size: 17, color: _ink),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                    color: _ink,
                  ),
                ),
              ),
              if (sourceLabel != null && sourceLabel.isNotEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEAF1FF),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    sourceLabel,
                    style: const TextStyle(
                      color: _ink,
                      fontSize: 11.2,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          if (loading)
            const Row(
              children: [
                SizedBox(
                  width: 15,
                  height: 15,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Generating summary with AI...',
                    style: TextStyle(
                      fontSize: 13.2,
                      color: _subtleInk,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            )
          else
            Text(
              value,
              style: const TextStyle(
                fontSize: 13.7,
                color: _subtleInk,
                height: 1.45,
                fontWeight: FontWeight.w600,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildLastEntryCard({
    required String date,
    required String kg,
    required String mt,
  }) {
    final values = <String>[
      if (date.isNotEmpty) 'Date $date',
      if (kg.isNotEmpty) 'KG $kg',
      if (mt.isNotEmpty) 'MT $mt',
    ];
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF133A60), Color(0xFF1E6CA5)],
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF133A60).withValues(alpha: 0.3),
            blurRadius: 12,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.schedule_rounded, color: Colors.white, size: 18),
              SizedBox(width: 8),
              Text(
                'Last Entry',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: values
                .map(
                  (v) => Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: Colors.white30),
                    ),
                    child: Text(
                      v,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12.3,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                )
                .toList(),
          ),
        ],
      ),
    );
  }

  Widget _pill(String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFFEAF1FF),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: _ink,
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _productionTable({
    required String q1,
    required String q2,
    required String q3,
    required String q4,
    required String annual,
  }) {
    final rows = <MapEntry<String, String>>[
      MapEntry('Q1', q1),
      MapEntry('Q2', q2),
      MapEntry('Q3', q3),
      MapEntry('Q4', q4),
      MapEntry('Annual', annual),
    ];

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Colors.white, Color(0xFFF6FAFF)],
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
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: const Color(0xFFEAF1FF),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(17),
                topRight: Radius.circular(17),
              ),
              border: Border(
                bottom: BorderSide(
                  color: const Color(0xFFC9DAEC).withValues(alpha: 0.8),
                ),
              ),
            ),
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Quarter',
                  style: TextStyle(
                    color: _ink,
                    fontWeight: FontWeight.w800,
                    fontSize: 14.5,
                  ),
                ),
                Text(
                  'Total (MT)',
                  style: TextStyle(
                    color: _ink,
                    fontWeight: FontWeight.w800,
                    fontSize: 14.5,
                  ),
                ),
              ],
            ),
          ),
          ...rows.asMap().entries.map((entry) {
            final index = entry.key;
            final row = entry.value;
            final isLast = index == rows.length - 1;
            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
              decoration: BoxDecoration(
                color: index.isEven
                    ? Colors.white.withValues(alpha: 0.86)
                    : const Color(0xFFF5F9FF),
                border: Border(
                  bottom: BorderSide(
                    color: isLast ? Colors.transparent : const Color(0xFFE2ECF7),
                  ),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    row.key,
                    style: TextStyle(
                      color: _ink.withValues(alpha: 0.95),
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                    ),
                  ),
                  Text(
                    row.value.isNotEmpty ? row.value : '--',
                    style: TextStyle(
                      color: _ink.withValues(alpha: 0.95),
                      fontWeight: FontWeight.w800,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  String _resolveImageUrl(
    String url, {
    String? id,
    String? fallbackName,
    String? scientificName,
  }) {
    final trimmed = url.trim();
    if (trimmed.isEmpty) {
      return _overrideFor(id, fallbackName, scientificName: scientificName) ??
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
          id: id,
          fallbackName: fallbackName,
          scientificName: scientificName,
        );
      }
      return _overrideFor(id, fallbackName, scientificName: scientificName) ??
          '';
    }
    if (trimmed.startsWith('asset:')) {
      return trimmed;
    }
    if (trimmed.startsWith('gs://')) {
      return _overrideFor(id, fallbackName, scientificName: scientificName) ??
          '';
    }

    try {
      Uri uri = Uri.parse(trimmed);

      if (uri.scheme.isEmpty) {
        uri = Uri.parse('https://$trimmed');
      }

      final host = uri.host.toLowerCase();
      final isLocalHost =
          host == '127.0.0.1' || host == 'localhost' || host == '0.0.0.0';

      if (isLocalHost && !kIsWeb && Platform.isAndroid) {
        uri = uri.replace(host: '10.0.2.2');
        final normalized = uri.toString();
        if (normalized.isNotEmpty) return normalized;
      }

      if (uri.scheme == 'http') {
        uri = uri.replace(scheme: 'https');
      }

      final normalized = uri.toString();
      if (normalized.isNotEmpty && !isLocalHost) return normalized;
    } catch (_) {}

    return _overrideFor(id, fallbackName, scientificName: scientificName) ??
        '';
  }

  String? _overrideFor(
    String? id,
    String? fallbackName, {
    String? scientificName,
  }) {
    if (id != null && id.trim().isNotEmpty) {
      final direct = _photoOverrides[id.trim()];
      if (direct != null && direct.isNotEmpty) return direct;
      final slug = _slug(id);
      final bySlug = _photoOverrides[slug];
      if (bySlug != null && bySlug.isNotEmpty) return bySlug;
    }
    if (fallbackName != null && fallbackName.trim().isNotEmpty) {
      final byNameSlug = _photoOverrides[_slug(fallbackName)];
      if (byNameSlug != null && byNameSlug.isNotEmpty) return byNameSlug;
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

  String? _extractUrlFromImageFormula(String formula) {
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

  void _openPhotoViewer({
    required String title,
    Uint8List? bytes,
    String? imageUrl,
    String? assetPath,
  }) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _SpeciesImageViewerPage(
          title: title,
          bytes: bytes,
          imageUrl: imageUrl,
          assetPath: assetPath,
        ),
      ),
    );
  }

  Widget _photoPreviewShell({
    required String fallbackLabel,
    required Widget child,
    VoidCallback? onTap,
  }) {
    final content = Container(
      color: const Color(0xFFF0F6FD),
      child: Stack(
        fit: StackFit.expand,
        children: [
          Padding(
            padding: const EdgeInsets.all(10),
            child: Center(child: child),
          ),
          if (onTap != null)
            Positioned(
              right: 10,
              bottom: 10,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.58),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.zoom_in_map_rounded,
                      size: 14,
                      color: Colors.white,
                    ),
                    SizedBox(width: 6),
                    Text(
                      'Tap to zoom',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 11.8,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );

    if (onTap == null) return content;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: content,
      ),
    );
  }

  Widget _loadingPhotoPreview() {
    return Container(
      color: const Color(0xFFF0F6FD),
      child: const Center(
        child: CircularProgressIndicator(strokeWidth: 2.4),
      ),
    );
  }

  Widget _buildPhoto({
    required String resolvedUrl,
    required String rawPath,
    List<String> rawCandidates = const [],
    required String docId,
    required String fallbackLabel,
    String scientificName = '',
  }) {
    final overrideUrl = _overrideFor(
      docId,
      fallbackLabel,
      scientificName: scientificName,
    );
    final directCandidates = <String>[
      resolvedUrl,
      for (final raw in rawCandidates)
        _resolveImageUrl(
          raw,
          id: docId,
          fallbackName: fallbackLabel,
          scientificName: scientificName,
        ),
      if (overrideUrl != null && overrideUrl.isNotEmpty) overrideUrl,
    ].where((candidate) => candidate.trim().isNotEmpty).toList();

    for (final candidate in directCandidates) {
      if (candidate.startsWith('data:image')) {
        final bytes = _bytesFromDataUrl(candidate);
        if (bytes != null) {
          return _photoPreviewShell(
            fallbackLabel: fallbackLabel,
            onTap: () => _openPhotoViewer(
              title: fallbackLabel,
              bytes: bytes,
            ),
            child: Image.memory(
              bytes,
              fit: BoxFit.contain,
              errorBuilder: (_, __, ___) => _photoPlaceholder(fallbackLabel),
            ),
          );
        }
      }
      if (candidate.startsWith('asset:')) {
        final assetPath = candidate.replaceFirst('asset:', '');
        return _photoPreviewShell(
          fallbackLabel: fallbackLabel,
          onTap: () => _openPhotoViewer(
            title: fallbackLabel,
            assetPath: assetPath,
          ),
          child: Image.asset(
            assetPath,
            fit: BoxFit.contain,
            errorBuilder: (_, __, ___) => _photoPlaceholder(fallbackLabel),
          ),
        );
      }
      if (candidate.startsWith('http')) {
        return _photoPreviewShell(
          fallbackLabel: fallbackLabel,
          onTap: () => _openPhotoViewer(
            title: fallbackLabel,
            imageUrl: candidate,
          ),
          child: Image.network(
            candidate,
            fit: BoxFit.contain,
            errorBuilder: (_, __, ___) => _photoPlaceholder(fallbackLabel),
          ),
        );
      }
    }

    if (resolvedUrl.isNotEmpty && resolvedUrl.startsWith('asset:')) {
      final assetPath = resolvedUrl.replaceFirst('asset:', '');
      return _photoPreviewShell(
        fallbackLabel: fallbackLabel,
        onTap: () => _openPhotoViewer(
          title: fallbackLabel,
          assetPath: assetPath,
        ),
        child: Image.asset(
          assetPath,
          fit: BoxFit.contain,
          errorBuilder: (_, __, ___) => _photoPlaceholder(fallbackLabel),
        ),
      );
    }

    final candidates = <String>{
      if (rawPath.trim().isNotEmpty) ..._candidatePathsFromRaw(rawPath.trim()),
      for (final raw in rawCandidates) ..._candidatePathsFromRaw(raw),
      ..._guessStoragePaths(docId),
      ..._guessStoragePaths(_slug(fallbackLabel)),
      if (scientificName.trim().isNotEmpty) ..._guessStoragePaths(_slug(scientificName)),
    }.toList();
    if (candidates.isEmpty) {
      if (overrideUrl != null && overrideUrl.isNotEmpty) {
        return _photoPreviewShell(
          fallbackLabel: fallbackLabel,
          onTap: () => _openPhotoViewer(
            title: fallbackLabel,
            imageUrl: overrideUrl,
          ),
          child: Image.network(
            overrideUrl,
            fit: BoxFit.contain,
            errorBuilder: (_, __, ___) => _photoPlaceholder(fallbackLabel),
          ),
        );
      }
      return _photoPlaceholder(fallbackLabel);
    }

    final primary = candidates.first;
    final fallbacks = candidates.skip(1).toList();

    return FutureBuilder<String?>(
      future: _getStorageUrl(primary, fallbacks),
      builder: (context, snapshot) {
        final url = snapshot.data;
        if (url != null && url.isNotEmpty) {
          return _photoPreviewShell(
            fallbackLabel: fallbackLabel,
            onTap: () => _openPhotoViewer(
              title: fallbackLabel,
              imageUrl: url,
            ),
            child: Image.network(
              url,
              fit: BoxFit.contain,
              errorBuilder: (_, __, ___) => _photoPlaceholder(fallbackLabel),
            ),
          );
        }
        if (snapshot.connectionState == ConnectionState.waiting) {
          return _loadingPhotoPreview();
        }
        if (overrideUrl != null && overrideUrl.isNotEmpty) {
          return _photoPreviewShell(
            fallbackLabel: fallbackLabel,
            onTap: () => _openPhotoViewer(
              title: fallbackLabel,
              imageUrl: overrideUrl,
            ),
            child: Image.network(
              overrideUrl,
              fit: BoxFit.contain,
              errorBuilder: (_, __, ___) => _photoPlaceholder(fallbackLabel),
            ),
          );
        }
        return _photoPlaceholder(fallbackLabel);
      },
    );
  }

  Widget _photoPlaceholder(String name) {
    final letter = name.isNotEmpty ? name.substring(0, 1).toUpperCase() : '?';
    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFD7E8FB), Color(0xFFBCD8F4)],
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Center(
        child: Text(
          letter,
          style: const TextStyle(
            fontSize: 40,
            fontWeight: FontWeight.w800,
            color: _subtleInk,
          ),
        ),
      ),
    );
  }

  List<String> _guessStoragePaths(String id) {
    if (id.isEmpty) return const [];
    return [
      'marine_life_stats/$id.jpg',
      'marine_life_stats/$id.jpeg',
      'marine_life_stats/$id.png',
      'marine_life_stats/$id.webp',
      'species_database/$id.jpg',
      'species_database/$id.jpeg',
      'species_database/$id.png',
      'species_database/$id.webp',
      'species_photos/$id.jpg',
      'species_photos/$id.jpeg',
      'species_photos/$id.png',
      'species_photos/$id.webp',
    ];
  }

  List<String> _candidatePathsFromRaw(String raw) {
    final trimmed = raw.trim();
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
      if (relative.isNotEmpty) return [relative];
    }

    return const [];
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

class _SpeciesImageViewerPage extends StatelessWidget {
  final String title;
  final Uint8List? bytes;
  final String? imageUrl;
  final String? assetPath;

  const _SpeciesImageViewerPage({
    required this.title,
    this.bytes,
    this.imageUrl,
    this.assetPath,
  });

  Widget _placeholder() {
    final letter = title.isNotEmpty ? title.substring(0, 1).toUpperCase() : '?';
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFD7E8FB), Color(0xFFBCD8F4)],
        ),
      ),
      child: Center(
        child: Text(
          letter,
          style: const TextStyle(
            fontSize: 56,
            fontWeight: FontWeight.w800,
            color: Color(0xFF486581),
          ),
        ),
      ),
    );
  }

  Widget _imageWidget() {
    if (bytes != null) {
      return Image.memory(
        bytes!,
        fit: BoxFit.contain,
        errorBuilder: (_, __, ___) => _placeholder(),
      );
    }
    if (assetPath != null && assetPath!.trim().isNotEmpty) {
      return Image.asset(
        assetPath!,
        fit: BoxFit.contain,
        errorBuilder: (_, __, ___) => _placeholder(),
      );
    }
    if (imageUrl != null && imageUrl!.trim().isNotEmpty) {
      return Image.network(
        imageUrl!,
        fit: BoxFit.contain,
        errorBuilder: (_, __, ___) => _placeholder(),
      );
    }
    return _placeholder();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        title: Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return Stack(
              children: [
                Positioned.fill(
                  child: InteractiveViewer(
                    minScale: 1,
                    maxScale: 5,
                    clipBehavior: Clip.none,
                    child: SizedBox(
                      width: constraints.maxWidth,
                      height: constraints.maxHeight,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 56),
                        child: _imageWidget(),
                      ),
                    ),
                  ),
                ),
                Positioned(
                  left: 16,
                  right: 16,
                  bottom: 16,
                  child: IgnorePointer(
                    child: Center(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.55),
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(color: Colors.white24),
                        ),
                        child: const Text(
                          'Pinch to zoom',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 12.4,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _AiAnswer {
  final String answer;
  final String source;

  _AiAnswer({required this.answer, required this.source});
}

class _AiSectionData {
  final String environment;
  final String about;
  final String source;

  _AiSectionData({
    required this.environment,
    required this.about,
    required this.source,
  });
}
