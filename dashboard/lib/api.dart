import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

final String apiBase = _resolveApiBase();

/// A release bundle is always served by the BlipRadius server itself, so it talks to its own origin
/// — whatever port, hostname or reverse proxy it sits behind. Only `flutter run -d chrome`, which
/// serves a debug build from a throwaway port with no API on it, needs the localhost fallback.
String _resolveApiBase() {
  const override = String.fromEnvironment('APIGUARD_API');
  if (override.isNotEmpty) return override;
  const released = bool.fromEnvironment('dart.vm.product');
  if (!released) return 'http://localhost:8080';
  try {
    final here = Uri.base;
    if (here.scheme != 'http' && here.scheme != 'https') return 'http://localhost:8080';
  } catch (_) {
    return 'http://localhost:8080';
  }
  return '';
}

const Duration _requestTimeout = Duration(seconds: 30);
const Duration _uploadTimeout = Duration(seconds: 60);

class ApiClient {
  final http.Client _http;

  ApiClient({http.Client? client}) : _http = client ?? http.Client();

  static String? apiKey;

  Map<String, String> _headers([Map<String, String>? extra]) => {
        if (apiKey != null && apiKey!.isNotEmpty) 'X-API-Key': apiKey!,
        ...?extra,
      };

  Future<GraphDto>? _graphCache;

  Future<GraphDto> graph({bool refresh = false}) {
    if (refresh || _graphCache == null) {
      _graphCache = _get('/api/graph').then((r) => GraphDto.fromJson(r));
    }
    return _graphCache!;
  }

  void invalidateGraph() => _graphCache = null;

  Future<List<ApiInfo>> apis() async {
    final r = await _get('/api/apis');
    return (r as List).map((e) => ApiInfo.fromJson(e)).toList();
  }

  Future<List<ChangeDto>> changes(String apiName) async {
    final r = await _get('/api/apis/${Uri.encodeComponent(apiName)}/changes');
    return (r as List).map((e) => ChangeDto.fromJson(e)).toList();
  }

  Future<List<ChangelogEntry>> changelog({String? api}) async {
    final q = api == null ? '' : '?api=${Uri.encodeQueryComponent(api)}';
    final r = await _get('/api/changelog$q');
    return (r as List).map((e) => ChangelogEntry.fromJson(e)).toList();
  }

  Future<ExplorerResult> explore(String api, String endpoint, String? field) async {
    var path = '/api/explorer?api=${Uri.encodeQueryComponent(api)}'
        '&endpoint=${Uri.encodeQueryComponent(endpoint)}';
    if (field != null && field.isNotEmpty) {
      path += '&field=${Uri.encodeQueryComponent(field)}';
    }
    return ExplorerResult.fromJson(await _get(path));
  }

  Future<EndpointInspect> inspectEndpoint(String api, {String? endpoint}) async {
    var path = '/api/endpoint?api=${Uri.encodeQueryComponent(api)}';
    if (endpoint != null && endpoint.isNotEmpty) {
      path += '&endpoint=${Uri.encodeQueryComponent(endpoint)}';
    }
    return EndpointInspect.fromJson(await _get(path));
  }

  Future<List<ManifestDto>> manifests() async {
    final r = await _get('/api/manifests');
    return (r as List).map((e) => ManifestDto.fromJson(e)).toList();
  }

  Future<SearchResults> search(String q) async {
    final r = await _get('/api/search?q=${Uri.encodeQueryComponent(q)}');
    return SearchResults.fromJson(r);
  }

  Future<List<InsightFinding>> insights() async {
    final r = await _get('/api/insights');
    return (r as List).map((e) => InsightFinding.fromJson(e)).toList();
  }

  Future<List<AuditEvent>> audit({int limit = 50}) async {
    final r = await _get('/api/audit?limit=$limit');
    return (r as List).map((e) => AuditEvent.fromJson(e)).toList();
  }

  Future<HealthInfo> health() async => HealthInfo.fromJson(await _get('/api/health'));

  Future<AnalyzeResult> analyze({
    required String api,
    required String oldSpec,
    required String newSpec,
    String? repo,
    String? fromLabel,
    String? toLabel,
  }) async {
    final r = await _post('/api/analyze', {
      'api': api,
      'oldSpec': oldSpec,
      'newSpec': newSpec,
      if (repo != null) 'repo': repo,
      'fromLabel': fromLabel ?? 'before',
      'toLabel': toLabel ?? 'after',
      'notifyPr': false,
    });
    return AnalyzeResult.fromJson(r);
  }

  Future<PropagationResult> propagate({required String api, required String spec}) async {
    final r = await _post('/api/propagation', {'api': api, 'spec': spec});
    return PropagationResult.fromJson(r);
  }

  Future<LatestSpec?> latestSpec(String api) async {
    final resp = await _guard(
        () => _http.get(Uri.parse('$apiBase/api/apis/${Uri.encodeComponent(api)}/spec/latest'),
            headers: _headers()),
        _requestTimeout);
    if (resp.statusCode == 204 || resp.statusCode >= 400) return null;
    final j = jsonDecode(utf8.decode(resp.bodyBytes));
    final spec = (j['spec'] ?? '').toString();
    if (spec.trim().isEmpty) return null;
    return LatestSpec(j['versionLabel'], j['savedAt'], spec);
  }

  Future<SourcesStatus> sourcesStatus() async {
    try {
      return SourcesStatus.fromJson(await _get('/api/sources'));
    } catch (_) {
      return SourcesStatus(false, null, null, null, const [], const []);
    }
  }

  Future<SourcesStatus> sourcesConfigureAnypoint({
    required String clientId,
    required String clientSecret,
    String? orgId,
    String? environment,
  }) async {
    final r = await _post('/api/sources/anypoint', {
      'clientId': clientId,
      'clientSecret': clientSecret,
      if (orgId != null && orgId.isNotEmpty) 'orgId': orgId,
      if (environment != null && environment.isNotEmpty) 'environment': environment,
    });
    return SourcesStatus.fromJson(r);
  }

  Future<List<LocalCandidate>> localCandidates() async {
    try {
      final r = await _get('/api/sources/local-candidates');
      return (r as List).map((e) => LocalCandidate.fromJson(e)).toList();
    } catch (_) {
      return const [];
    }
  }

  Future<ConnectionTest> testAnypoint() async =>
      ConnectionTest.fromJson(await _post('/api/sources/anypoint/test', {}));

  Future<Reach> reach(String api) async =>
      Reach.fromJson(await _get('/api/apis/${Uri.encodeComponent(api)}/reach'));

  Future<SourcesStatus> sourcesDisconnectAnypoint() async =>
      SourcesStatus.fromJson(await _post('/api/sources/anypoint/disconnect', {}));

  Future<SourcesStatus> sourcesAddRepo(String url) async =>
      SourcesStatus.fromJson(await _post('/api/sources/repos', {'url': url}));

  Future<SourcesStatus> sourcesRemoveRepo(String url) async =>
      SourcesStatus.fromJson(await _post('/api/sources/repos/remove', {'url': url}));

  Future<SyncAllResult> syncEverything() async {
    final r = await _post('/api/sources/sync', {});
    invalidateGraph();
    return SyncAllResult.fromJson(r);
  }

  Future<SyncProgress> startSync() async =>
      SyncProgress.fromJson(await _post('/api/sources/sync/start', {}));

  Future<SyncProgress> syncStatus() async =>
      SyncProgress.fromJson(await _get('/api/sources/sync/status'));

  Future<SyncProgress> cancelSync() async =>
      SyncProgress.fromJson(await _post('/api/sources/sync/cancel', {}));

  Future<AnypointLinks> anypointLinks({String? api}) async {
    try {
      final q = api == null ? '' : '?api=${Uri.encodeQueryComponent(api)}';
      final r = await _get('/api/anypoint/links$q');
      return AnypointLinks.fromJson(r);
    } catch (_) {
      return const AnypointLinks(null, null, null);
    }
  }

  Future<ExtractedSpec> extractSpecFromZip(List<int> bytes, String filename) async {
    final req = http.MultipartRequest('POST', Uri.parse('$apiBase/api/spec/from-zip'));
    req.headers.addAll(_headers());
    req.files.add(http.MultipartFile.fromBytes('file', bytes, filename: filename));
    final resp = await _guard(
        () async => http.Response.fromStream(await _http.send(req)), _uploadTimeout);
    if (resp.statusCode >= 400) {
      throw Exception(_extractError(resp.body, resp.statusCode));
    }
    final j = jsonDecode(utf8.decode(resp.bodyBytes));
    return ExtractedSpec(j['title'], j['version'], j['spec'] ?? '');
  }

  Future<dynamic> _post(String path, Map<String, dynamic> body) async {
    final resp = await _guard(
        () => _http.post(Uri.parse('$apiBase$path'),
            headers: _headers({'Content-Type': 'application/json'}), body: jsonEncode(body)),
        _requestTimeout);
    if (resp.statusCode >= 400) {
      throw Exception(_extractError(resp.body, resp.statusCode));
    }
    return jsonDecode(utf8.decode(resp.bodyBytes));
  }

  Future<dynamic> _get(String path) async {
    final resp = await _guard(
        () => _http.get(Uri.parse('$apiBase$path'), headers: _headers()), _requestTimeout);
    if (resp.statusCode >= 400) {
      throw Exception(_extractError(resp.body, resp.statusCode));
    }
    return jsonDecode(utf8.decode(resp.bodyBytes));
  }

  /// A hung or unreachable server must surface as a real error the screens can show and retry,
  /// not as a spinner that never resolves.
  Future<http.Response> _guard(Future<http.Response> Function() send, Duration timeout) async {
    try {
      return await send().timeout(timeout);
    } on TimeoutException {
      throw Exception('The BlipRadius server did not respond within '
          '${timeout.inSeconds}s. It may be busy syncing, or unreachable.');
    } on http.ClientException catch (e) {
      throw Exception('Could not reach the BlipRadius server at '
          '${apiBase.isEmpty ? "this address" : apiBase}. ${e.message}');
    }
  }

  String _extractError(String body, int status) {
    if (status == 401) {
      return 'This server requires an API key — set it via the key button in the sidebar.';
    }
    try {
      final j = jsonDecode(body);
      if (j is Map && j['error'] != null) return j['error'].toString();
    } catch (_) {}
    if (status == 403) return 'Not allowed (403).';
    if (status == 404) return 'Not found (404).';
    if (status == 429) return 'The server is rate-limiting requests (429). Try again shortly.';
    if (status >= 500) return 'The BlipRadius server hit an error ($status). Check its logs.';
    return 'Request failed ($status)';
  }
}

class ApiInfo {
  final int id;
  final String name;
  final String? repo;
  ApiInfo(this.id, this.name, this.repo);
  factory ApiInfo.fromJson(Map<String, dynamic> j) =>
      ApiInfo(j['id'], j['name'], j['repo']);
}

class HealthInfo {
  final String status, name, version;
  final int uptimeSeconds;
  final bool authRequired;
  HealthInfo(this.status, this.name, this.version, this.uptimeSeconds, this.authRequired);
  bool get up => status == 'UP';
  factory HealthInfo.fromJson(Map<String, dynamic> j) => HealthInfo(
      j['status'] ?? 'UNKNOWN', j['name'] ?? 'BlipRadius', j['version'] ?? '',
      j['uptimeSeconds'] ?? 0, j['authRequired'] == true);
}

class ChangeDto {
  final String classification, kind;
  final String? endpoint, jsonPointer, field, description, remediation;
  ChangeDto(this.classification, this.kind, this.endpoint, this.jsonPointer,
      this.field, this.description, this.remediation);
  factory ChangeDto.fromJson(Map<String, dynamic> j) => ChangeDto(
      j['classification'], j['kind'], j['endpoint'], j['jsonPointer'],
      j['field'], j['description'], j['remediation']);
}

class ConsumerDto {
  final String consumer;
  final String? ownerTeam, slackChannel, sourceRepo, matchedField;
  final List<String> reviewers;

  /// False when this consumer matched only because we have no field-level data for it.
  final bool fieldConfirmed;
  ConsumerDto(this.consumer, this.ownerTeam, this.reviewers, this.slackChannel,
      this.sourceRepo, this.matchedField, this.fieldConfirmed);
  factory ConsumerDto.fromJson(Map<String, dynamic> j) => ConsumerDto(
      j['consumer'], j['ownerTeam'],
      (j['reviewers'] as List?)?.map((e) => e.toString()).toList() ?? [],
      j['slackChannel'], j['sourceRepo'], j['matchedField'], j['fieldConfirmed'] != false);
}

class UpstreamDto {
  final String? api, endpoint, field;
  UpstreamDto(this.api, this.endpoint, this.field);
  factory UpstreamDto.fromJson(Map<String, dynamic> j) =>
      UpstreamDto(j['api'], j['endpoint'], j['field']);
}

class ExplorerResult {
  final String api, endpoint;
  final String? field;
  final List<ConsumerDto> downstream;
  final List<UpstreamDto> upstream;
  ExplorerResult(this.api, this.endpoint, this.field, this.downstream, this.upstream);
  factory ExplorerResult.fromJson(Map<String, dynamic> j) => ExplorerResult(
      j['api'], j['endpoint'], j['field'],
      (j['downstream'] as List).map((e) => ConsumerDto.fromJson(e)).toList(),
      (j['upstream'] as List).map((e) => UpstreamDto.fromJson(e)).toList());
}

class EndpointProducer {
  final String api, layer, endpoint;
  final List<String> fields;
  EndpointProducer(this.api, this.layer, this.endpoint, this.fields);
  factory EndpointProducer.fromJson(Map<String, dynamic> j) => EndpointProducer(
      j['api'] ?? '', j['layer'] ?? 'UNKNOWN', j['endpoint'] ?? '',
      (j['fields'] as List?)?.map((e) => e.toString()).toList() ?? []);
}

class EndpointConsumer {
  final String consumer, layer;
  final String? viaEndpoint, ownerTeam, slackChannel, sourceRepo;
  final List<String> fields, reviewers;
  EndpointConsumer(this.consumer, this.layer, this.viaEndpoint, this.fields, this.ownerTeam,
      this.reviewers, this.slackChannel, this.sourceRepo);
  factory EndpointConsumer.fromJson(Map<String, dynamic> j) => EndpointConsumer(
      j['consumer'] ?? '', j['layer'] ?? 'UNKNOWN', j['viaEndpoint'],
      (j['fields'] as List?)?.map((e) => e.toString()).toList() ?? [],
      j['ownerTeam'],
      (j['reviewers'] as List?)?.map((e) => e.toString()).toList() ?? [],
      j['slackChannel'], j['sourceRepo']);
}

class EndpointInspect {
  final String api, layer;
  final String? endpoint;
  final List<String> endpoints;
  final List<EndpointProducer> calls, appLevelCalls;
  final List<EndpointConsumer> calledBy;
  EndpointInspect(this.api, this.layer, this.endpoint, this.endpoints, this.calls, this.appLevelCalls,
      this.calledBy);
  factory EndpointInspect.fromJson(Map<String, dynamic> j) => EndpointInspect(
      j['api'] ?? '', j['layer'] ?? 'UNKNOWN', j['endpoint'],
      (j['endpoints'] as List?)?.map((e) => e.toString()).toList() ?? [],
      (j['calls'] as List?)?.map((e) => EndpointProducer.fromJson(e)).toList() ?? [],
      (j['appLevelCalls'] as List?)?.map((e) => EndpointProducer.fromJson(e)).toList() ?? [],
      (j['calledBy'] as List?)?.map((e) => EndpointConsumer.fromJson(e)).toList() ?? []);
}

class PropagationField {
  final String endpoint, field;

  /// 'response' — consumers read this field. 'request' — callers have to send it.
  final String side;
  final int consumerCount, confirmedCount;
  final List<ConsumerDto> downstream;
  final List<UpstreamDto> upstream;
  PropagationField(this.endpoint, this.field, this.side, this.consumerCount, this.confirmedCount,
      this.downstream, this.upstream);

  bool get isRequest => side == 'request';

  /// Consumers matched without field-level evidence — reported, but not proven readers.
  int get unknownCount => consumerCount - confirmedCount;
  factory PropagationField.fromJson(Map<String, dynamic> j) => PropagationField(
      j['endpoint'], j['field'], j['side'] ?? 'response',
      j['consumerCount'] ?? 0, j['confirmedCount'] ?? 0,
      (j['downstream'] as List?)?.map((e) => ConsumerDto.fromJson(e)).toList() ?? [],
      (j['upstream'] as List?)?.map((e) => UpstreamDto.fromJson(e)).toList() ?? []);
}

class PropagationResult {
  final String api;
  final String? title, version;
  final int endpoints, fields, impactedFields, impactedConsumers, unknownConsumers;
  final List<PropagationField> items;
  PropagationResult(this.api, this.title, this.version, this.endpoints, this.fields,
      this.impactedFields, this.impactedConsumers, this.unknownConsumers, this.items);
  int get confirmedFields => items.where((f) => f.confirmedCount > 0).length;
  factory PropagationResult.fromJson(Map<String, dynamic> j) => PropagationResult(
      j['api'] ?? '', j['title'], j['version'],
      j['endpoints'] ?? 0, j['fields'] ?? 0, j['impactedFields'] ?? 0, j['impactedConsumers'] ?? 0,
      j['unknownConsumers'] ?? 0,
      (j['items'] as List?)?.map((e) => PropagationField.fromJson(e)).toList() ?? []);
}

class GraphNode {
  final String id, label, layer;
  final bool api;
  final int dependsOn, dependedOnBy;
  final String? ownerTeam;
  final List<String> reviewers;
  GraphNode(this.id, this.label, this.layer, this.api, this.dependsOn, this.dependedOnBy,
      this.ownerTeam, this.reviewers);
  factory GraphNode.fromJson(Map<String, dynamic> j) => GraphNode(
      j['id'], j['label'], j['layer'] ?? 'UNKNOWN', j['api'] == true,
      j['dependsOn'] ?? 0, j['dependedOnBy'] ?? 0, j['ownerTeam'],
      (j['reviewers'] as List?)?.map((e) => e.toString()).toList() ?? const []);
}

class GraphEdge {
  final String from, to, label, risk;
  final List<String> via;

  /// Whether this dependency is known per-endpoint / per-field, or only app-to-app.
  final bool endpointLevel, fieldLevel;
  GraphEdge(this.from, this.to, this.label, this.risk, this.via,
      this.endpointLevel, this.fieldLevel);
  factory GraphEdge.fromJson(Map<String, dynamic> j) => GraphEdge(
      j['from'], j['to'], j['label'] ?? '', j['risk'] ?? 'none',
      (j['via'] as List?)?.map((e) => e.toString()).toList() ?? const [],
      j['endpointLevel'] == true, j['fieldLevel'] == true);
}

class GraphCoverage {
  final int dependencies, endpointLevel, fieldLevel;
  const GraphCoverage(this.dependencies, this.endpointLevel, this.fieldLevel);
  bool get isComplete => dependencies > 0 && endpointLevel == dependencies;
  int get shallow => dependencies - endpointLevel;
  double get ratio => dependencies == 0 ? 0 : endpointLevel / dependencies;
  factory GraphCoverage.fromJson(Map<String, dynamic>? j) => j == null
      ? const GraphCoverage(0, 0, 0)
      : GraphCoverage(j['dependencies'] ?? 0, j['endpointLevel'] ?? 0, j['fieldLevel'] ?? 0);
}

class GraphDto {
  final List<GraphNode> nodes;
  final List<GraphEdge> edges;
  final GraphCoverage coverage;
  GraphDto(this.nodes, this.edges, this.coverage);
  factory GraphDto.fromJson(Map<String, dynamic> j) => GraphDto(
      (j['nodes'] as List).map((e) => GraphNode.fromJson(e)).toList(),
      (j['edges'] as List).map((e) => GraphEdge.fromJson(e)).toList(),
      GraphCoverage.fromJson(j['coverage'] as Map<String, dynamic>?));
}

class ChangelogEntry {
  final int id;
  final String? api, versionLabel, publishedAt;
  final String markdown;
  ChangelogEntry(this.id, this.api, this.versionLabel, this.markdown, this.publishedAt);
  factory ChangelogEntry.fromJson(Map<String, dynamic> j) => ChangelogEntry(
      j['id'], j['api'], j['versionLabel'], j['markdown'] ?? '', j['publishedAt']);
}

class EdgeDto {
  final String? api, endpoint, field;
  EdgeDto(this.api, this.endpoint, this.field);
  factory EdgeDto.fromJson(Map<String, dynamic> j) =>
      EdgeDto(j['api'], j['endpoint'], j['field']);
}

class ManifestDto {
  final String consumer;
  final String? ownerTeam, slackChannel, sourceRepo, updatedAt;
  final List<String> reviewers;
  final List<EdgeDto> edges;
  final bool discoveredOnly;
  ManifestDto(this.consumer, this.ownerTeam, this.reviewers, this.slackChannel,
      this.sourceRepo, this.edges, this.updatedAt, this.discoveredOnly);
  factory ManifestDto.fromJson(Map<String, dynamic> j) => ManifestDto(
      j['consumer'], j['ownerTeam'],
      (j['reviewers'] as List?)?.map((e) => e.toString()).toList() ?? [],
      j['slackChannel'], j['sourceRepo'],
      (j['edges'] as List?)?.map((e) => EdgeDto.fromJson(e)).toList() ?? [],
      j['updatedAt'], j['discoveredOnly'] == true);
}

class Summary {
  final int total;
  final int breaking, safe, additive, impactedConsumers;
  Summary(this.total, this.breaking, this.safe, this.additive, this.impactedConsumers);
  factory Summary.fromJson(Map<String, dynamic> j) => Summary(
      j['total'] ?? 0, j['breaking'] ?? 0, j['safe'] ?? 0, j['additive'] ?? 0,
      j['impactedConsumers'] ?? 0);
}

class Impact {
  final ChangeDto change;
  final List<ConsumerDto> downstream;
  final List<UpstreamDto> upstream;
  Impact(this.change, this.downstream, this.upstream);
  factory Impact.fromJson(Map<String, dynamic> j) => Impact(
      ChangeDto.fromJson(j['change']),
      (j['downstream'] as List?)?.map((e) => ConsumerDto.fromJson(e)).toList() ?? [],
      (j['upstream'] as List?)?.map((e) => UpstreamDto.fromJson(e)).toList() ?? []);
}

class Advisory {
  final String recommendedBump;
  final String? currentVersion, nextVersion;
  final int riskScore;
  final String riskLevel;
  Advisory(this.recommendedBump, this.currentVersion, this.nextVersion, this.riskScore, this.riskLevel);
  factory Advisory.fromJson(Map<String, dynamic>? j) => j == null
      ? Advisory('NONE', null, null, 0, 'NONE')
      : Advisory(j['recommendedBump'] ?? 'NONE', j['currentVersion'], j['nextVersion'],
          j['riskScore'] ?? 0, j['riskLevel'] ?? 'NONE');
}

class AnalyzeResult {
  final String api;
  final Summary summary;
  final Advisory advisory;
  final List<Impact> impacts;
  final String changelog;
  AnalyzeResult(this.api, this.summary, this.advisory, this.impacts, this.changelog);
  factory AnalyzeResult.fromJson(Map<String, dynamic> j) => AnalyzeResult(
      j['api'] ?? '', Summary.fromJson(j['summary']), Advisory.fromJson(j['advisory']),
      (j['impacts'] as List?)?.map((e) => Impact.fromJson(e)).toList() ?? [],
      j['changelog'] ?? '');
}

class ExtractedSpec {
  final String? title, version;
  final String spec;
  ExtractedSpec(this.title, this.version, this.spec);
}

class LatestSpec {
  final String? versionLabel, savedAt;
  final String spec;
  LatestSpec(this.versionLabel, this.savedAt, this.spec);
}

class LocalCandidate {
  final String path, name;
  final int projects;
  const LocalCandidate(this.path, this.name, this.projects);
  factory LocalCandidate.fromJson(Map<String, dynamic> j) =>
      LocalCandidate(j['path'] ?? '', j['name'] ?? '', j['projects'] ?? 0);
}

class ConnectionTest {
  final bool ok;
  final String? orgId, environment, message;
  final int environments;
  const ConnectionTest(this.ok, this.orgId, this.environment, this.environments, this.message);
  factory ConnectionTest.fromJson(Map<String, dynamic> j) => ConnectionTest(
      j['ok'] == true, j['orgId'], j['environment'], j['environments'] ?? 0, j['message']);
}

class Reach {
  final String api;
  final List<String> direct, transitive;
  const Reach(this.api, this.direct, this.transitive);
  factory Reach.fromJson(Map<String, dynamic> j) => Reach(
      j['api'] ?? '',
      (j['direct'] as List?)?.map((e) => e.toString()).toList() ?? const [],
      (j['transitive'] as List?)?.map((e) => e.toString()).toList() ?? const []);
}

class RepoSource {
  final String url;
  final String? lastSyncedAt, lastError;
  final int? lastApps;
  const RepoSource(this.url, this.lastSyncedAt, this.lastApps, this.lastError);
  bool get neverSynced => lastSyncedAt == null;
  factory RepoSource.fromJson(Map<String, dynamic> j) =>
      RepoSource(j['url'] ?? '', j['lastSyncedAt'], j['lastApps'], j['lastError']);
}

class SourcesStatus {
  final bool anypointConfigured;
  final String? anypointOrg, anypointEnv, anypointBaseUrl;
  final List<String> repos;
  final List<RepoSource> repoDetails;
  SourcesStatus(this.anypointConfigured, this.anypointOrg, this.anypointEnv,
      this.anypointBaseUrl, this.repos, this.repoDetails);
  RepoSource? detailFor(String url) {
    for (final d in repoDetails) {
      if (d.url == url) return d;
    }
    return null;
  }

  factory SourcesStatus.fromJson(Map<String, dynamic> j) => SourcesStatus(
      j['anypointConfigured'] == true, j['anypointOrg'], j['anypointEnv'],
      j['anypointBaseUrl'],
      (j['repos'] as List?)?.map((e) => e.toString()).toList() ?? const [],
      (j['repoDetails'] as List?)?.map((e) => RepoSource.fromJson(e)).toList() ?? const []);
}

class RepoResult {
  final String url;
  final int apps;
  final List<String> appNames;
  final String? error;
  RepoResult(this.url, this.apps, this.appNames, this.error);
  factory RepoResult.fromJson(Map<String, dynamic> j) => RepoResult(
      j['url'] ?? '', j['apps'] ?? 0,
      (j['appNames'] as List?)?.map((e) => e.toString()).toList() ?? const [], j['error']);
}

class SyncAllResult {
  final bool anypointRan;
  final AnypointSync? anypoint;
  final List<RepoResult> repos;
  final int totalApps;
  final String? note;
  SyncAllResult(this.anypointRan, this.anypoint, this.repos, this.totalApps, this.note);
  factory SyncAllResult.fromJson(Map<String, dynamic> j) => SyncAllResult(
      j['anypointRan'] == true,
      j['anypoint'] == null ? null : AnypointSync.fromJson(j['anypoint']),
      (j['repos'] as List?)?.map((e) => RepoResult.fromJson(e)).toList() ?? const [],
      j['totalApps'] ?? 0, j['note']);
}

class SearchApiHit {
  final String api;
  const SearchApiHit(this.api);
  factory SearchApiHit.fromJson(Map<String, dynamic> j) => SearchApiHit(j['api'] ?? '');
}

class SearchEndpointHit {
  final String api, endpoint;
  const SearchEndpointHit(this.api, this.endpoint);
  factory SearchEndpointHit.fromJson(Map<String, dynamic> j) =>
      SearchEndpointHit(j['api'] ?? '', j['endpoint'] ?? '');
}

class SearchFieldHit {
  final String api, endpoint, field;
  const SearchFieldHit(this.api, this.endpoint, this.field);
  factory SearchFieldHit.fromJson(Map<String, dynamic> j) =>
      SearchFieldHit(j['api'] ?? '', j['endpoint'] ?? '', j['field'] ?? '');
}

class SearchResults {
  final List<SearchApiHit> apis;
  final List<SearchEndpointHit> endpoints;
  final List<SearchFieldHit> fields;
  const SearchResults(this.apis, this.endpoints, this.fields);
  bool get isEmpty => apis.isEmpty && endpoints.isEmpty && fields.isEmpty;
  factory SearchResults.fromJson(Map<String, dynamic> j) => SearchResults(
      (j['apis'] as List?)?.map((e) => SearchApiHit.fromJson(e)).toList() ?? const [],
      (j['endpoints'] as List?)?.map((e) => SearchEndpointHit.fromJson(e)).toList() ?? const [],
      (j['fields'] as List?)?.map((e) => SearchFieldHit.fromJson(e)).toList() ?? const []);
}

class InsightFinding {
  final String rule;
  final String severity;
  final String title;
  final String detail;
  final List<String> apis;
  InsightFinding(this.rule, this.severity, this.title, this.detail, this.apis);
  factory InsightFinding.fromJson(Map<String, dynamic> j) => InsightFinding(
      j['rule'] ?? '', j['severity'] ?? 'info', j['title'] ?? '', j['detail'] ?? '',
      (j['apis'] as List?)?.map((e) => e.toString()).toList() ?? const []);
}

class AuditEvent {
  final int? id;
  final String? ts, actor, subject, detail;
  final String action;
  AuditEvent(this.id, this.ts, this.actor, this.action, this.subject, this.detail);
  factory AuditEvent.fromJson(Map<String, dynamic> j) => AuditEvent(
      j['id'], j['ts'], j['actor'], j['action'] ?? '', j['subject'], j['detail']);
}

class SyncProgress {
  final String state;
  final String? phase;
  final int reposDone;
  final int reposTotal;
  final List<RepoResult> repoResults;
  final SyncAllResult? result;
  final String? error;
  final int startedAt;
  SyncProgress(this.state, this.phase, this.reposDone, this.reposTotal, this.repoResults,
      this.result, this.error, this.startedAt);
  bool get isRunning => state == 'running';
  bool get isDone => state == 'done';
  bool get isFailed => state == 'failed';
  Duration get elapsed => startedAt <= 0
      ? Duration.zero
      : Duration(milliseconds: DateTime.now().millisecondsSinceEpoch - startedAt);
  factory SyncProgress.fromJson(Map<String, dynamic> j) => SyncProgress(
      j['state'] ?? 'idle',
      j['phase'],
      j['reposDone'] ?? 0,
      j['reposTotal'] ?? 0,
      (j['repoResults'] as List?)?.map((e) => RepoResult.fromJson(e)).toList() ?? const [],
      j['result'] == null ? null : SyncAllResult.fromJson(j['result']),
      j['error'],
      j['startedAt'] ?? 0);
}

class AnypointLinks {
  final String? exchange, apiManager, designCenter;
  const AnypointLinks(this.exchange, this.apiManager, this.designCenter);
  bool get isEmpty => exchange == null && apiManager == null && designCenter == null;
  factory AnypointLinks.fromJson(Map<String, dynamic> j) =>
      AnypointLinks(j['exchange'], j['apiManager'], j['designCenter']);
}

class AnypointSync {
  final String? orgId, environmentName, note;
  final int apis, contracts, exchangeAssets, dependencyEdges, consumersIngested;
  final bool rateLimited;
  final List<String> consumers;
  AnypointSync(this.orgId, this.environmentName, this.apis, this.contracts,
      this.exchangeAssets, this.dependencyEdges, this.consumersIngested, this.rateLimited,
      this.note, this.consumers);
  factory AnypointSync.fromJson(Map<String, dynamic> j) => AnypointSync(
      j['orgId'], j['environmentName'], j['apis'] ?? 0, j['contracts'] ?? 0,
      j['exchangeAssets'] ?? 0, j['dependencyEdges'] ?? 0, j['consumersIngested'] ?? 0,
      j['rateLimited'] == true, j['note'],
      (j['consumers'] as List?)?.map((e) => e.toString()).toList() ?? []);
}
