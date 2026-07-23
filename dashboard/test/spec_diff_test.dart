import 'package:flutter_test/flutter_test.dart';
import 'package:apiguard_dashboard/widgets/spec_diff.dart';

void main() {
  group('computeLineDiff', () {
    test('identical text is all context', () {
      final d = computeLineDiff('a\nb\nc', 'a\nb\nc');
      expect(d.every((l) => l.op == DiffOp.context), isTrue);
      expect(d.length, 3);
      expect(d[0].oldNo, 1);
      expect(d[0].newNo, 1);
    });

    test('a removed line is marked remove with an old number only', () {
      final d = computeLineDiff('a\nb\nc', 'a\nc');
      final removed = d.where((l) => l.op == DiffOp.remove).toList();
      expect(removed.length, 1);
      expect(removed.first.text, 'b');
      expect(removed.first.oldNo, 2);
      expect(removed.first.newNo, isNull);
    });

    test('an added line is marked add with a new number only', () {
      final d = computeLineDiff('a\nc', 'a\nb\nc');
      final added = d.where((l) => l.op == DiffOp.add).toList();
      expect(added.length, 1);
      expect(added.first.text, 'b');
      expect(added.first.newNo, 2);
      expect(added.first.oldNo, isNull);
    });

    test('a changed line becomes one remove plus one add', () {
      final d = computeLineDiff('name: old', 'name: new');
      expect(d.where((l) => l.op == DiffOp.remove).length, 1);
      expect(d.where((l) => l.op == DiffOp.add).length, 1);
    });

    test('empty old text makes every new line an add', () {
      final d = computeLineDiff('', 'x\ny');
      expect(d.length, 2);
      expect(d.every((l) => l.op == DiffOp.add), isTrue);
    });

    test('handles CRLF without spurious diffs', () {
      final d = computeLineDiff('a\r\nb', 'a\nb');
      expect(d.every((l) => l.op == DiffOp.context), isTrue);
    });
  });

  group('collapseContext', () {
    test('collapses long unchanged runs into a single ellipsis marker', () {
      final oldText = List.generate(30, (i) => 'line$i').join('\n');
      final newText = oldText.replaceFirst('line15', 'line15-changed');
      final full = computeLineDiff(oldText, newText);
      final collapsed = collapseContext(full, pad: 2);
      expect(collapsed.length, lessThan(full.length));
      expect(collapsed.where((l) => l.text == '⋯').isNotEmpty, isTrue);
      // The change and its immediate neighbours survive.
      expect(collapsed.where((l) => l.op != DiffOp.context).isNotEmpty, isTrue);
    });
  });
}
