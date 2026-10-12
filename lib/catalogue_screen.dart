import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:sqflite/sqflite.dart';

import 'catalogue_models.dart';
import 'database_helper.dart';
import 'main.dart' show RosterScreen;

class CatalogueScreen extends StatefulWidget {
  const CatalogueScreen({super.key, required this.helper});
  final DatabaseHelper helper;
  @override
  State<CatalogueScreen> createState() => _CatalogueScreenState();
}

class _CatalogueScreenState extends State<CatalogueScreen> {
  List<Folder> _folders = [];
  List<CardRecord> _cards = [];
  Folder? _selected;
  bool _busy = false;
  String? _error;
  String? _feedback;
  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<bool> _read() async {
    try {
      final folders = await widget.helper.getFoldersWithCounts();
      final matches = folders.where((f) => f.id == _selected?.id);
      final selected = matches.isEmpty ? null : matches.first;
      final cards = selected == null
          ? <CardRecord>[]
          : await widget.helper.getCards(selected.id!);
      if (!mounted) return false;
      setState(() {
        _folders = folders;
        _selected = selected;
        _cards = cards;
        _error = null;
      });
      return true;
    } catch (error, stack) {
      debugPrint('Catalogue read failed: $error\n$stack');
      if (mounted) {
        setState(
          () => _error = 'Could not load records. Retry the read; do not recreate saved cards.',
        );
      }
      return false;
    }
  }

  Future<void> _refresh() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await _read();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _addFolder() async {
    if (_busy) return;
    final result = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _FolderDialog(helper: widget.helper),
    );
    if (!mounted || result == null) return;
    setState(() => _feedback = result);
    await _refresh();
  }

  Future<void> _editCard([CardRecord? card]) async {
    if (_busy || _selected == null) return;
    final result = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => _CardForm(
          helper: widget.helper,
          folders: _folders,
          initialFolderId: _selected!.id!,
          card: card,
        ),
      ),
    );
    if (!mounted || result == null) return;
    setState(() => _feedback = result);
    await _refresh();
  }

  Future<void> _delete({Folder? folder, CardRecord? card}) async {
    if (_busy) return;
    final name = folder?.name ?? card!.title;
    final id = folder?.id ?? card!.id!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete "$name" (ID $id)?'),
        content: Text(
          folder != null
              ? 'This permanently deletes this folder and its ${folder.cardCount} cards. Other folders are kept.'
              : 'This deletes only this card by its ID.',
        ),
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
    setState(() {
      _busy = true;
      _feedback = null;
    });
    try {
      final affected = folder != null
          ? await widget.helper.deleteFolder(id)
          : await widget.helper.deleteCard(id);
      if (!mounted) return;
      setState(
        () => _feedback = affected == 1
            ? 'Deleted ID $id; affected rows: $affected.'
            : 'Nothing deleted: ID $id no longer exists (affected rows: $affected).',
      );
      await _read(); // A refresh failure must never repeat a successful write.
    } catch (error, stack) {
      debugPrint('Delete failed: $error\n$stack');
      if (mounted) {
        setState(() => _feedback = 'Delete failed. Check logs and retry.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _diagnostics() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final data = await widget.helper.diagnostics();
      final text = const JsonEncoder.withIndent('  ').convert(data);
      debugPrint('CATALOGUE_DIAGNOSTICS\n$text');
      if (!mounted) return;
      await Navigator.of(context).push<void>(
        MaterialPageRoute(
          builder: (_) => Scaffold(
            appBar: AppBar(title: const Text('Read-only database evidence')),
            body: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: SelectableText(text),
            ),
          ),
        ),
      );
    } catch (error, stack) {
      debugPrint('Diagnostics failed: $error\n$stack');
      if (mounted) setState(() => _feedback = 'Could not read diagnostics.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(_selected == null ? 'Card Catalogue' : _selected!.name),
      leading: _selected == null
          ? null
          : IconButton(
              tooltip: 'All folders',
              icon: const Icon(Icons.arrow_back),
              onPressed: _busy
                  ? null
                  : () => setState(() {
                      _selected = null;
                      _cards = [];
                      _feedback = null;
                      _error = null;
                    }),
            ),
      actions: [
        IconButton(
          tooltip: 'Refresh',
          onPressed: _busy ? null : _refresh,
          icon: const Icon(Icons.refresh),
        ),
        IconButton(
          tooltip: 'Database evidence',
          onPressed: _busy ? null : _diagnostics,
          icon: const Icon(Icons.info_outline),
        ),
      ],
    ),
    body: Column(
      children: [
        if (_busy) const LinearProgressIndicator(),
        if (_feedback != null)
          Padding(
            padding: const EdgeInsets.all(12),
            child: Text(_feedback!, key: const Key('feedback')),
          ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
                TextButton(
                  onPressed: _busy ? null : _refresh,
                  child: const Text('Retry read'),
                ),
              ],
            ),
          ),
        if (_selected == null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Expanded(child: Text('${_folders.length} folders • SQLite v2')),
                TextButton(
                  onPressed: _busy
                      ? null
                      : () => Navigator.of(context).push<void>(
                          MaterialPageRoute(
                            builder: (_) => RosterScreen(helper: widget.helper),
                          ),
                        ),
                  child: const Text('Part I guests'),
                ),
              ],
            ),
          ),
        if (_selected != null)
          Padding(
            padding: const EdgeInsets.all(12),
            child: Text(
              'Folder ID ${_selected!.id} • ${_selected!.cardCount} cards',
            ),
          ),
        Expanded(
          child: _error != null
              ? const SizedBox.shrink()
              : _selected == null
              ? _folderList()
              : _cardList(),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: FilledButton.icon(
              onPressed: _busy
                  ? null
                  : (_selected == null ? _addFolder : () => _editCard()),
              icon: const Icon(Icons.add),
              label: Text(_selected == null ? 'Create folder' : 'Add card'),
            ),
          ),
        ),
      ],
    ),
  );
  Widget _folderList() => _folders.isEmpty
      ? Center(
          child: Text(
            _busy
                ? 'Loading folders…'
                : 'No folders yet. Create your first folder.',
          ),
        )
      : ListView.builder(
          itemCount: _folders.length,
          itemBuilder: (context, i) {
            final folder = _folders[i];
            return ListTile(
              leading: const Icon(Icons.folder_outlined),
              title: Text(folder.name),
              subtitle: Text('ID ${folder.id} • ${folder.cardCount} cards'),
              onTap: _busy
                  ? null
                  : () {
                      setState(() {
                        _selected = folder;
                        _feedback = null;
                      });
                      _refresh();
                    },
              trailing: IconButton(
                tooltip: 'Delete folder ${folder.name}',
                icon: const Icon(Icons.delete_outline),
                onPressed: _busy ? null : () => _delete(folder: folder),
              ),
            );
          },
        );
  Widget _cardList() => _cards.isEmpty
      ? Center(
          child: Text(
            _busy ? 'Loading cards…' : 'This folder is empty. Add a card.',
          ),
        )
      : ListView.builder(
          itemCount: _cards.length,
          itemBuilder: (context, i) {
            final card = _cards[i];
            return Card(
              child: ListTile(
                leading: CardArtwork(card: card),
                title: Text(card.title),
                subtitle: Text(
                  'ID ${card.id} • ${card.suit} • folder ${card.folderId}\n${card.notes.isEmpty ? "No notes" : card.notes}',
                ),
                isThreeLine: true,
                onTap: _busy ? null : () => _editCard(card),
                trailing: IconButton(
                  tooltip: 'Delete card ID ${card.id}',
                  icon: const Icon(Icons.delete_outline),
                  onPressed: _busy ? null : () => _delete(card: card),
                ),
              ),
            );
          },
        );
}

class CardArtwork extends StatelessWidget {
  const CardArtwork({super.key, required this.card});
  final CardRecord card;
  Widget _fallback() => Semantics(
    label: '${card.suit} suit fallback',
    child: SizedBox(
      width: 42,
      height: 48,
      child: Center(
        child: Text(
          suitSymbols[card.suit] ?? '?',
          style: TextStyle(
            fontSize: 32,
            color: ['Hearts', 'Diamonds'].contains(card.suit)
                ? Colors.red.shade800
                : Colors.black,
          ),
        ),
      ),
    ),
  );
  @override
  Widget build(BuildContext context) {
    final ref = card.imageRef;
    if (ref == null || ref.isEmpty) return _fallback();
    if (!ref.startsWith('assets/') || ref.contains('..')) return _fallback();
    return Image.asset(
      ref,
      width: 42,
      height: 48,
      fit: BoxFit.contain,
      errorBuilder: (_, error, stack) => _fallback(),
    );
  }
}

class _FolderDialog extends StatefulWidget {
  const _FolderDialog({required this.helper});
  final DatabaseHelper helper;
  @override
  State<_FolderDialog> createState() => _FolderDialogState();
}

class _FolderDialogState extends State<_FolderDialog> {
  final _name = TextEditingController();
  final _form = GlobalKey<FormState>();
  bool _busy = false;
  String? _error;
  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_busy || !_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final id = await widget.helper.insertFolder(_name.text);
      if (mounted) Navigator.pop(context, 'Created folder ID $id.');
    } catch (error, stack) {
      debugPrint('Folder insert failed: $error\n$stack');
      if (mounted) {
        setState(
          () => _error =
              error is DatabaseException && error.isUniqueConstraintError()
              ? 'That folder name already exists. Choose another name.'
              : 'Could not save. Your name is preserved; retry.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy,
    child: AlertDialog(
      title: const Text('Create folder'),
      content: Form(
        key: _form,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              controller: _name,
              enabled: !_busy,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'Folder name'),
              validator: (s) => (s?.trim().isEmpty ?? true)
                  ? 'Enter a nonblank folder name.'
                  : null,
            ),
            if (_error != null)
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _busy ? null : _save,
          child: Text(_busy ? 'Saving…' : 'Create'),
        ),
      ],
    ),
  );
}

class _CardForm extends StatefulWidget {
  const _CardForm({
    required this.helper,
    required this.folders,
    required this.initialFolderId,
    this.card,
  });
  final DatabaseHelper helper;
  final List<Folder> folders;
  final int initialFolderId;
  final CardRecord? card;
  @override
  State<_CardForm> createState() => _CardFormState();
}

class _CardFormState extends State<_CardForm> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _title;
  late final TextEditingController _notes;
  late final TextEditingController _image;
  late String _suit;
  late int _folderId;
  bool _busy = false;
  String? _error;
  @override
  void initState() {
    super.initState();
    _title = TextEditingController(text: widget.card?.title ?? '');
    _notes = TextEditingController(text: widget.card?.notes ?? '');
    _image = TextEditingController(text: widget.card?.imageRef ?? '');
    _suit = widget.card?.suit ?? suits.first;
    _folderId = widget.card?.folderId ?? widget.initialFolderId;
  }

  @override
  void dispose() {
    _title.dispose();
    _notes.dispose();
    _image.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_busy || !_form.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _error = null;
    });
    final record = CardRecord(
      id: widget.card?.id,
      title: _title.text.trim(),
      suit: _suit,
      folderId: _folderId,
      notes: _notes.text,
      imageRef: _image.text.trim().isEmpty ? null : _image.text.trim(),
    );
    try {
      final result = record.id == null
          ? await widget.helper.insertCard(record)
          : await widget.helper.updateCard(record);
      if (!mounted) return;
      if (record.id != null && result != 1) {
        setState(
          () => _error =
              'Updated $result rows. This card no longer exists. Cancel and refresh.',
        );
        return;
      }
      Navigator.pop(
        context,
        record.id == null
            ? 'Inserted card ID $result.'
            : 'Saved card ID ${record.id}; affected rows: $result.',
      );
    } catch (error, stack) {
      debugPrint('Card save failed: $error\n$stack');
      if (mounted) {
        setState(
          () => _error = 'Could not save. Input is preserved. Verify the folder still exists and retry.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy,
    child: Scaffold(
      appBar: AppBar(
        title: Text(
          widget.card == null ? 'Add card' : 'Edit card ID ${widget.card!.id}',
        ),
      ),
      body: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            TextFormField(
              controller: _title,
              enabled: !_busy,
              decoration: const InputDecoration(labelText: 'Title'),
              validator: (s) => (s?.trim().isEmpty ?? true)
                  ? 'Enter a nonblank title.'
                  : null,
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              initialValue: _suit,
              decoration: const InputDecoration(labelText: 'Suit'),
              items: suits
                  .map((s) => DropdownMenuItem(value: s, child: Text(s)))
                  .toList(),
              onChanged: _busy ? null : (s) => setState(() => _suit = s!),
              validator: (s) => suits.contains(s) ? null : 'Choose one suit.',
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<int>(
              initialValue: _folderId,
              decoration: const InputDecoration(labelText: 'Folder'),
              items: widget.folders
                  .map(
                    (f) => DropdownMenuItem(
                      value: f.id,
                      child: Text('${f.name} (ID ${f.id})'),
                    ),
                  )
                  .toList(),
              onChanged: _busy ? null : (id) => setState(() => _folderId = id!),
              validator: (id) => widget.folders.any((f) => f.id == id)
                  ? null
                  : 'Choose an existing folder.',
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _notes,
              enabled: !_busy,
              maxLines: 3,
              decoration: const InputDecoration(labelText: 'Notes (optional)'),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _image,
              enabled: !_busy,
              decoration: const InputDecoration(
                labelText: 'Image reference (optional)',
                helperText: 'Leave blank for a suit symbol. Optional asset: assets/card_back.png',
                helperMaxLines: 2,
              ),
            ),
            const SizedBox(height: 16),
            if (_error != null)
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            FilledButton(
              onPressed: _busy ? null : _save,
              child: Text(_busy ? 'Saving…' : 'Save'),
            ),
            TextButton(
              onPressed: _busy
                  ? null
                  : () => Navigator.pop(
                      context,
                      'Edit canceled. No rows changed.',
                    ),
              child: const Text('Cancel'),
            ),
          ],
        ),
      ),
    ),
  );
}
