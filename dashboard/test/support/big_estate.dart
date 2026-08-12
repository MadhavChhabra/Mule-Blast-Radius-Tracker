import 'dart:convert';
import 'dart:math';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:apiguard_dashboard/api.dart';

/// A synthetic estate the size of a real Anypoint org. The user's own org is ~1177 assets, so the
/// map has to stay usable at that scale, not just at the four-node demo size.
String bigEstateJson({int apis = 1000, int seed = 7}) {
  final rnd = Random(seed);
  const layers = ['APP', 'EXPERIENCE', 'PROCESS', 'SYSTEM', 'BACKEND'];
  final nodes = <Map<String, dynamic>>[];
  final byLayer = <String, List<String>>{for (final l in layers) l: []};

  for (int i = 0; i < apis; i++) {
    final layer = layers[i % layers.length];
    final id = '${layer.toLowerCase()}-api-$i';
    byLayer[layer]!.add(id);
    nodes.add({
      'id': id,
      'label': id,
      'layer': layer,
      'api': layer != 'APP',
      'dependsOn': 0,
      'dependedOnBy': 0,
    });
  }

  final edges = <Map<String, dynamic>>[];
  void link(String from, String to) {
    edges.add({
      'from': from,
      'to': to,
      'label': '',
      'risk': rnd.nextInt(12) == 0 ? 'breaking' : (rnd.nextInt(3) == 0 ? 'safe' : 'none'),
      'via': const <String>[],
      'endpointLevel': rnd.nextBool(),
      'fieldLevel': rnd.nextInt(4) == 0,
    });
  }

  // Consumers point one layer to the right, the way an API-led estate actually wires up.
  for (int i = 0; i < layers.length - 1; i++) {
    final from = byLayer[layers[i]]!;
    final to = byLayer[layers[i + 1]]!;
    for (final f in from) {
      final n = 1 + rnd.nextInt(2);
      for (int k = 0; k < n; k++) {
        link(f, to[rnd.nextInt(to.length)]);
      }
    }
  }

  final counts = <String, int>{};
  for (final e in edges) {
    counts[e['to'] as String] = (counts[e['to'] as String] ?? 0) + 1;
  }
  for (final n in nodes) {
    n['dependedOnBy'] = counts[n['id']] ?? 0;
  }

  return jsonEncode({
    'nodes': nodes,
    'edges': edges,
    'coverage': {
      'dependencies': edges.length,
      'endpointLevel': edges.where((e) => e['endpointLevel'] == true).length,
      'fieldLevel': edges.where((e) => e['fieldLevel'] == true).length,
    },
  });
}

/// An estate built from an explicit graph body, for data nobody expects: hostile names, self
/// loops, cycles, edges pointing at nodes that are not there.
ApiClient estateFrom(String graphJson) => bigEstateApi(graphJson: graphJson);

ApiClient bigEstateApi({int apis = 1000, String? graphJson}) {
  final graph = graphJson ?? bigEstateJson(apis: apis);
  return ApiClient(
    client: MockClient((req) async {
      final p = req.url.path;
      String body;
      if (p == '/api/graph') {
        body = graph;
      } else if (p == '/api/insights') {
        body = '[]';
      } else if (p == '/api/health') {
        body = '{"status":"UP","name":"BlipRadius","version":"0.1.0","uptimeSeconds":5}';
      } else if (p.endsWith('/reach')) {
        body = '{"api":"x","direct":[],"transitive":[]}';
      } else {
        body = '{}';
      }
      return http.Response(body, 200, headers: {'content-type': 'application/json'});
    }),
  );
}
