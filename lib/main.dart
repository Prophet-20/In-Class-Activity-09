import 'package:flutter/material.dart';

import 'database_helper.dart';
import 'catalogue_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final helper = DatabaseHelper();
  try {
    await helper.init();
  } catch (error, stackTrace) {
    debugPrint('Database initialization failed: $error\n$stackTrace');
    runApp(
      const MaterialApp(
        home: Scaffold(
          body: SafeArea(
            child: Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'Could not open local storage. Restart the app and check the logs.',
                ),
              ),
            ),
          ),
        ),
      ),
    );
    return;
  }
  runApp(DirectoryApp(helper: helper));
}

class DirectoryApp extends StatelessWidget {
  const DirectoryApp({super.key, required this.helper});
  final DatabaseHelper helper;

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Card Catalogue',
    home: CatalogueScreen(helper: helper),
  );
}

class RosterScreen extends StatefulWidget {
  const RosterScreen({super.key, required this.helper});
  final DatabaseHelper helper;

  @override
  State<RosterScreen> createState() => _RosterScreenState();
}

class _RosterScreenState extends State<RosterScreen> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _age = TextEditingController();
  List<Map<String, dynamic>> _rows = [];
  int? _count;
  int? _selectedId;
  bool _busy = false;
  String? _readError;
  String? _feedback;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  @override
  void dispose() {
    _name.dispose();
    _age.dispose();
    super.dispose();
  }

  // Caller holds the busy flag; a read failure never repeats a write.
  Future<bool> _readRows() async {
    try {
      final rows = await widget.helper.queryAllRows();
      final count = await widget.helper.queryRowCount();
      if (!mounted) return false;
      setState(() {
        _rows = rows;
        _count = count;
        _readError = null;
      });
      return true;
    } catch (error, stackTrace) {
      debugPrint('Roster read failed: $error\n$stackTrace');
      if (mounted) {
        setState(
          () => _readError = 'Could not read the roster. Tap Refresh to retry.',
        );
      }
      return false;
    }
  }

  Future<void> _refresh() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await _readRows();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _clearForm() {
    _selectedId = null;
    _name.clear();
    _age.clear();
    _form.currentState?.reset();
  }

  Future<void> _save() async {
    if (_busy || !_form.currentState!.validate()) return;
    final id = _selectedId;
    final row = <String, dynamic>{
      DatabaseHelper.columnName: _name.text.trim(),
      DatabaseHelper.columnAge: int.tryParse(_age.text.trim())!,
      DatabaseHelper.columnId: ?id,
    };
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _feedback = null;
    });
    try {
      final result = id == null
          ? await widget.helper.insert(row)
          : await widget.helper.update(row);
      if (!mounted) return;
      if (id != null && result != 1) {
        setState(
          () => _feedback = result == 0
              ? 'ID $id no longer exists. Updated 0 rows; review the refreshed list.'
              : 'Unexpected update result: $result rows. Review the roster.',
        );
        await _readRows();
        return;
      }
      setState(() {
        _clearForm();
        _feedback = id == null
            ? 'Added guest with ID $result.'
            : 'Saved ID $id. Updated $result row.';
      });
      final refreshed = await _readRows();
      if (mounted && !refreshed) {
        setState(
          () => _feedback =
              '${_feedback!} Saved, but refresh failed. Tap Refresh.',
        );
      }
    } catch (error, stackTrace) {
      debugPrint('Roster write failed: $error\n$stackTrace');
      if (mounted) {
        setState(
          () => _feedback =
              'Could not save. Your input is preserved. Check logs and retry.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _edit(Map<String, dynamic> row) {
    if (_busy) return;
    setState(() {
      _form.currentState?.reset();
      _selectedId = row[DatabaseHelper.columnId] as int;
      _name.text = row[DatabaseHelper.columnName] as String;
      _age.text = '${row[DatabaseHelper.columnAge]}';
      _feedback = 'Editing ID $_selectedId.';
    });
  }

  Future<void> _delete(Map<String, dynamic> row) async {
    if (_busy) return;
    final id = row[DatabaseHelper.columnId] as int;
    final name = row[DatabaseHelper.columnName] as String;
    setState(() => _busy = true);
    try {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Delete guest?'),
          content: Text('Delete ID $id — $name? This cannot be undone.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Delete'),
            ),
          ],
        ),
      );
      if (!mounted) return;
      if (confirmed != true) {
        setState(() => _feedback = 'Deletion canceled. No rows changed.');
        return;
      }
      final affected = await widget.helper.delete(id);
      if (!mounted) return;
      if (affected != 1) {
        setState(
          () => _feedback = affected == 0
              ? 'ID $id no longer exists. Deleted 0 rows.'
              : 'Unexpected delete result: $affected rows. Review the roster.',
        );
        await _readRows();
        return;
      }
      setState(() {
        if (_selectedId == id) _clearForm();
        _feedback = 'Deleted ID $id. Deleted $affected row.';
      });
      final refreshed = await _readRows();
      if (mounted && !refreshed) {
        setState(
          () => _feedback = 'Deleted ID $id, but refresh failed. Tap Refresh.',
        );
      }
    } catch (error, stackTrace) {
      debugPrint('Roster delete failed: $error\n$stackTrace');
      if (mounted) {
        setState(() => _feedback = 'Could not delete. Check logs and retry.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Fall Festival Roster')),
    body: SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            _selectedId == null
                ? 'Register a guest'
                : 'Editing guest ID $_selectedId',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 12),
          Form(
            key: _form,
            child: Column(
              children: [
                TextFormField(
                  controller: _name,
                  enabled: !_busy,
                  decoration: const InputDecoration(
                    labelText: 'Name',
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) => (value ?? '').trim().isEmpty
                      ? 'Enter a nonempty name.'
                      : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _age,
                  enabled: !_busy,
                  decoration: const InputDecoration(
                    labelText: 'Age',
                    helperText: 'Whole number from 0 through 130',
                    border: OutlineInputBorder(),
                  ),
                  keyboardType: const TextInputType.numberWithOptions(
                    signed: true,
                    decimal: true,
                  ),
                  validator: (value) {
                    final text = (value ?? '').trim();
                    final age = int.tryParse(text);
                    if (!RegExp(r'^[+-]?[0-9]+$').hasMatch(text) ||
                        age == null) {
                      return 'Enter a whole-number age.';
                    }
                    if (age < 0 || age > 130) {
                      return 'Age must be from 0 through 130.';
                    }
                    return null;
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton(
                onPressed: _busy ? null : _save,
                child: Text(_selectedId == null ? 'Add' : 'Save'),
              ),
              OutlinedButton(
                onPressed: _busy || _selectedId == null
                    ? null
                    : () {
                        setState(() {
                          _clearForm();
                          _feedback = 'Edit canceled. No rows changed.';
                        });
                      },
                child: const Text('Cancel edit'),
              ),
              OutlinedButton(
                onPressed: _busy ? null : _refresh,
                child: const Text('Refresh'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (_busy)
            const LinearProgressIndicator(semanticsLabel: 'Loading roster'),
          if (_feedback != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(_feedback!),
            ),
          if (_readError != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(_readError!),
            ),
          Text(
            _count == null
                ? 'Record count: unavailable'
                : 'Record count: $_count${_readError == null ? '' : ' (last loaded)'}',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const Divider(),
          if (!_busy && _readError == null && _count == 0)
            const Text('No festival guests yet'),
          for (final row in _rows)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'ID ${row[DatabaseHelper.columnId]} • ${row[DatabaseHelper.columnName]} • Age ${row[DatabaseHelper.columnAge]}',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    Row(
                      children: [
                        TextButton(
                          onPressed: _busy ? null : () => _edit(row),
                          child: const Text('Edit'),
                        ),
                        TextButton(
                          onPressed: _busy ? null : () => _delete(row),
                          child: const Text('Delete'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    ),
  );
}
