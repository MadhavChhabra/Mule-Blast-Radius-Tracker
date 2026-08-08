import 'package:flutter_test/flutter_test.dart';
import 'package:apiguard_dashboard/api.dart';

void main() {
  test('invalidating the estate notifies live surfaces', () {
    final api = ApiClient();
    final before = ApiClient.estateRevision.value;
    var notified = 0;
    void listener() => notified++;
    ApiClient.estateRevision.addListener(listener);
    api.invalidateGraph();
    ApiClient.estateRevision.removeListener(listener);
    expect(ApiClient.estateRevision.value, greaterThan(before));
    expect(notified, 1);
  });
}
