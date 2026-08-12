import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:apiguard_dashboard/api.dart';

/// A server whose sync can be driven through its real states, so the flows that only exist after a
/// sync finishes — success with nothing found, and outright failure — can actually be exercised.
class SyncStage {
  /// idle | running | done | failed
  String state = 'idle';
  String phase = 'Starting…';
  int reposDone = 0;
  int reposTotal = 1;
  String? error;
  int totalApps = 0;
  String? note;

  /// Nodes the estate reports once the sync has finished.
  String graphNodes = '';
  String graphEdges = '';

  List<String> repos = ['https://github.com/acme/orders-exp-api'];
  bool anypointConfigured = false;

  void succeedWithNothing() {
    state = 'done';
    phase = 'Done';
    reposDone = 1;
    totalApps = 0;
    note = 'No Mule apps were found.';
  }

  void fail(String message) {
    state = 'failed';
    phase = 'Failed';
    error = message;
  }

  String _progressJson() => jsonEncode({
        'state': state,
        'phase': phase,
        'reposDone': reposDone,
        'reposTotal': reposTotal,
        'error': error,
        'startedAt': DateTime.now().millisecondsSinceEpoch,
        'repoResults': const [],
        'result': state == 'done'
            ? {
                'anypoint': null,
                'repos': const [],
                'totalApps': totalApps,
                'note': note,
                'unchangedRepos': 0,
              }
            : null,
      });

  ApiClient client() => ApiClient(
        client: MockClient((req) async {
          final p = req.url.path;
          String body;
          if (p == '/api/graph') {
            body = '{"nodes":[$graphNodes],"edges":[$graphEdges],'
                '"coverage":{"dependencies":0,"endpointLevel":0,"fieldLevel":0}}';
          } else if (p == '/api/sources') {
            body = jsonEncode({
              'anypointConfigured': anypointConfigured,
              'anypointOrg': null,
              'anypointEnv': null,
              'anypointBaseUrl': null,
              'repos': repos,
              'repoDetails': const [],
            });
          } else if (p == '/api/sources/local-candidates') {
            body = '[]';
          } else if (p == '/api/sources/sync/start') {
            state = 'running';
            body = _progressJson();
          } else if (p == '/api/sources/sync/status') {
            body = _progressJson();
          } else if (p == '/api/insights') {
            body = '[]';
          } else if (p == '/api/health') {
            body = '{"status":"UP","name":"BlipRadius","version":"0.1.0","uptimeSeconds":1}';
          } else {
            body = '{}';
          }
          return http.Response(body, 200, headers: {'content-type': 'application/json'});
        }),
      );
}
