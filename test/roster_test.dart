import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_storage_lab/database_helper.dart';
import 'package:local_storage_lab/main.dart';

// UI-only test double. These tests do not prove SQLite or process persistence.
class MemoryHelper extends DatabaseHelper {
  final rows = <Map<String, dynamic>>[];
  int nextId = 10;
  bool failWrite = false;
  bool failRead = false;
  bool failReadAfterWrite = false;

  @override
  Future<List<Map<String, dynamic>>> queryAllRows() async {
    if (failRead) throw StateError('Simulated read failure');
    return rows.map((row) => Map<String, dynamic>.from(row)).toList();
  }

  @override
  Future<int> queryRowCount() async => rows.length;
  @override
  Future<int> insert(Map<String, dynamic> row) async {
    if (failWrite) throw StateError('Simulated write failure');
    expect(row.containsKey('_id'), false);
    final id = nextId++;
    rows.add({...row, '_id': id});
    if (failReadAfterWrite) failRead = true;
    return id;
  }

  @override
  Future<int> update(Map<String, dynamic> row) async {
    final index = rows.indexWhere((item) => item['_id'] == row['_id']);
    if (index < 0) return 0;
    rows[index] = Map.of(row);
    return 1;
  }

  @override
  Future<int> delete(int id) async {
    final before = rows.length;
    rows.removeWhere((row) => row['_id'] == id);
    return before - rows.length;
  }
}

Future<void> input(WidgetTester tester, String name, String age) async {
  await tester.enterText(find.byType(TextFormField).at(0), name);
  await tester.enterText(find.byType(TextFormField).at(1), age);
}

Future<void> press(WidgetTester tester, String label) async {
  final target = find.text(label);
  await tester.ensureVisible(target);
  await tester.tap(target);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('validation rejects all five inputs and accepts boundaries', (
    tester,
  ) async {
    final db = MemoryHelper();
    await tester.pumpWidget(MaterialApp(home: RosterScreen(helper: db)));
    await tester.pumpAndSettle();
    expect(find.text('No festival guests yet'), findsOneWidget);
    for (final entry in [
      ('   ', '21'),
      ('Maple', 'abc'),
      ('Maple', '1.5'),
      ('Maple', '-1'),
      ('Maple', '131'),
    ]) {
      await input(tester, entry.$1, entry.$2);
      await press(tester, 'Add');
      expect(db.rows, isEmpty);
    }
    await input(tester, ' Acorn ', '0');
    await press(tester, 'Add');
    await input(tester, 'Oak', '130');
    await press(tester, 'Add');
    expect(db.rows.map((r) => r['age']), [0, 130]);
    expect(db.rows.first['name'], 'Acorn');
    expect(find.text('Record count: 2'), findsOneWidget);
  });
  testWidgets('duplicate names edit by ID and cancel preserves database', (
    tester,
  ) async {
    final db = MemoryHelper();
    db.rows.addAll([
      {'_id': 7, 'name': 'River', 'age': 21},
      {'_id': 19, 'name': 'River', 'age': 34},
    ]);
    await tester.pumpWidget(MaterialApp(home: RosterScreen(helper: db)));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Edit').last);
    await tester.tap(find.text('Edit').last);
    await tester.pumpAndSettle();
    await input(tester, 'River', '99');
    await press(tester, 'Cancel edit');
    expect(db.rows.last['age'], 34);
    await tester.ensureVisible(find.text('Edit').last);
    await tester.tap(find.text('Edit').last);
    await tester.pumpAndSettle();
    await input(tester, 'River', '35');
    await press(tester, 'Save');
    expect(db.rows.first['age'], 21);
    expect(db.rows.last['age'], 35);
    expect(find.text('Saved ID 19. Updated 1 row.'), findsOneWidget);
  });
  testWidgets('failed write preserves input and releases busy flag', (
    tester,
  ) async {
    final db = MemoryHelper()..failWrite = true;
    await tester.pumpWidget(MaterialApp(home: RosterScreen(helper: db)));
    await tester.pumpAndSettle();
    await input(tester, 'River', '21');
    await press(tester, 'Add');
    expect(find.text('River'), findsOneWidget);
    expect(db.rows, isEmpty);
    db.failWrite = false;
    await press(tester, 'Add');
    expect(db.rows.length, 1);
  });
  testWidgets('refresh failure after save never repeats insert', (
    tester,
  ) async {
    final db = MemoryHelper()..failReadAfterWrite = true;
    await tester.pumpWidget(MaterialApp(home: RosterScreen(helper: db)));
    await tester.pumpAndSettle();
    await input(tester, 'River', '21');
    await press(tester, 'Add');
    expect(find.textContaining('Saved, but refresh failed'), findsOneWidget);
    expect(db.rows.length, 1);
    db.failRead = false;
    await press(tester, 'Refresh');
    expect(db.rows.length, 1);
    expect(find.text('Record count: 1'), findsOneWidget);
  });
}
