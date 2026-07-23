import 'dart:convert';
import 'package:http/http.dart' as http;

final String apiBase = _resolveApiBase();

String _resolveApiBase() {
  const override = String.fromEnvironment('APIGUARD_API');
  if (override.isNotEmpty) return override;
  try {
    final here = Uri.base;
    if ((here.scheme == 'http' || here.scheme == 'https') && here.port == 8080) {
      return '';
    }
  } catch (_) {}
  return 'http://localhost:8080';
}

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
    final resp = await _http.get(
        Uri.parse('$apiBase/api/apis/${Uri.encodeComponent(api)}/spec/latest'),
        headers: _headers());
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
      return SourcesStatus(false, null, null, null, const []);
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
    req.files.add(http.MultipartFile.fromBytes('file', bytes, filename: filename));
    final resp = await http.Response.fromStream(await _http.send(req));
    if (resp.statusCode >= 400) {
      throw Exception(_extractError(resp.body, resp.statusCode));
    }
    final j = jsonDecode(utf8.decode(resp.bodyBytes));
    return ExtractedSpec(j['title'], j['version'], j['spec'] ?? '');
  }

  Future<dynamic> _post(String path, Map<String, dynamic> body) async {
    final resp = await _http.post(Uri.parse('$apiBase$path'),
        headers: _headers({'Content-Type': 'application/json'}), body: jsonEncode(body));
    if (resp.statusCode >= 400) {
      throw Exception(_extractError(resp.body, resp.statusCode));
    }
    return jsonDecode(utf8.decode(resp.bodyBytes));
  }

  String _extractError(String body, int status) {
    try {
      final j = jsonDecode(body);
      if (j is Map && j['error'] != null) return j['error'].toString();
    } catch (_) {}
    return 'Request failed ($status)';
  }

  Future<dynamic> _get(String path) async {
    final resp = await _http.get(Uri.parse('$apiBase$path'), headers: _headers());
    if (resp.statusCode == 401) {
      throw Exception('This server requires an API key — set it via the key button in the sidebar.');
    }
    if (resp.statusCode >= 400) {
      throw Exception('GET $path failed: ${resp.statusCode} ${resp.body}');
    }
    return jsonDecode(utf8.decode(resp.bodyBytes));
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
      j['status'] ?? 'UNKNOWN', j['name'] ?? 'Wakegraph', j['version'] ?? '',
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
  ConsumerDto(this.consumer, this.ownerTeam, this.reviewers, this.slackChannel,
      this.sourceRepo, this.matchedField);
  factory ConsumerDto.fromJson(Map<String, dynamic> j) => ConsumerDto(
      j['consumer'], j['ownerTeam'],
      (j['reviewers'] as List?)?.map((e) => e.toString()).toList() ?? [],
      j['slackChannel'], j['sourceRepo'], j['matchedField']);
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
  final int consumerCount;
  final List<ConsumerDto> downstream;
  final List<UpstreamDto> upstream;
  PropagationField(this.endpoint, this.field, this.consumerCount, this.downstream, this.upstream);
  factory PropagationField.fromJson(Map<String, dynamic> j) => PropagationField(
      j['endpoint'], j['field'], j['consumerCount'] ?? 0,
      (j['downstream'] as List?)?.map((e) => ConsumerDto.fromJson(e)).toList() ?? [],
      (j['upstream'] as List?)?.map((e) => UpstreamDto.fromJson(e)).toList() ?? []);
}

class PropagationResult {
  final String api;
  final String? title, version;
  final int endpoints, fields, impactedFields, impactedConsumers;
  final List<PropagationField> items;
  PropagationResult(this.api, this.title, this.version, this.endpoints, this.fields,
      this.impactedFields, this.impactedConsumers, this.items);
  factory PropagationResult.fromJson(Map<String, dynamic> j) => PropagationResult(
      j['api'] ?? '', j['title'], j['version'],
      j['endpoints'] ?? 0, j['fields'] ?? 0, j['impactedFields'] ?? 0, j['impactedConsumers'] ?? 0,
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
  GraphEdge(this.from, this.to, this.label, this.risk, this.via);
  factory GraphEdge.fromJson(Map<String, dynamic> j) => GraphEdge(
      j['from'], j['to'], j['label'] ?? '', j['risk'] ?? 'none',
      (j['via'] as List?)?.map((e) => e.toString()).toList() ?? const []);
}

class GraphDto {
  final List<GraphNode> nodes;
  final List<GraphEdge> edges;
  GraphDto(this.nodes, this.edges);
  factory GraphDto.fromJson(Map<String, dynamic> j) => GraphDto(
      (j['nodes'] as List).map((e) => GraphNode.fromJson(e)).toList(),
      (j['edges'] as List).map((e) => GraphEdge.fromJson(e)).toList());
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

class SourcesStatus {
  final bool anypointConfigured;
  final String? anypointOrg, anypointEnv, anypointBaseUrl;
  final List<String> repos;
  SourcesStatus(this.anypointConfigured, this.anypointOrg, this.anypointEnv,
      this.anypointBaseUrl, this.repos);
  factory SourcesStatus.fromJson(Map<String, dynamic> j) => SourcesStatus(
      j['anypointConfigured'] == true, j['anypointOrg'], j['anypointEnv'],
      j['anypointBaseUrl'],
      (j['repos'] as List?)?.map((e) => e.toString()).toList() ?? const []);
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
