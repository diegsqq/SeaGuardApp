import 'package:firebase_core/firebase_core.dart';

// Base URL for deployed Firebase Cloud Functions.
// Optional overrides:
// - --dart-define=FUNCTIONS_BASE_URL=https://<region>-<project>.cloudfunctions.net
// - --dart-define=FUNCTIONS_REGION=us-central1
const String _functionsBaseUrlOverride = String.fromEnvironment(
  'FUNCTIONS_BASE_URL',
  defaultValue: '',
);

const String _functionsRegion = String.fromEnvironment(
  'FUNCTIONS_REGION',
  defaultValue: 'us-central1',
);

String _resolveFunctionsBaseUrl() {
  final override = _functionsBaseUrlOverride.trim();
  if (override.isNotEmpty) return override;

  try {
    final projectId = Firebase.app().options.projectId;
    if (projectId.isNotEmpty) {
      return 'https://$_functionsRegion-$projectId.cloudfunctions.net';
    }
  } catch (_) {
    // Firebase may not be initialized yet; fall back to a sane default below.
  }

  return 'https://$_functionsRegion-seaguardproject2025.cloudfunctions.net';
}

Uri functionsUri(String path) => Uri.parse('${_resolveFunctionsBaseUrl()}/$path');

List<Uri> functionUriCandidates(String path) {
  final trimmedPath = path.trim();
  if (trimmedPath.isEmpty) return const [];

  final override = _functionsBaseUrlOverride.trim();
  if (override.isNotEmpty) {
    return [Uri.parse('$override/$trimmedPath')];
  }

  var projectId = 'seaguardproject2025';
  try {
    final configuredProjectId = Firebase.app().options.projectId;
    if (configuredProjectId.isNotEmpty) {
      projectId = configuredProjectId;
    }
  } catch (_) {
    // Keep default when Firebase isn't initialized yet.
  }

  final regions = <String>[
    _functionsRegion,
    'us-central1',
    'asia-southeast1',
  ];

  final seen = <String>{};
  final uris = <Uri>[];
  for (final region in regions) {
    final candidateRegion = region.trim();
    if (candidateRegion.isEmpty) continue;
    final url =
        'https://$candidateRegion-$projectId.cloudfunctions.net/$trimmedPath';
    if (seen.add(url)) {
      uris.add(Uri.parse(url));
    }
  }
  return uris;
}
