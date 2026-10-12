import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import 'catalogue_models.dart';

// Part I guest schema and database filename are preserved.
class DatabaseHelper {
  static const columnId = '_id';
  static const columnName = 'name';
  static const columnAge = 'age';
  static const table = 'my_table';
  late Database _db;

  Future<void> init() async {
    final directory = await getApplicationDocumentsDirectory();
    _db = await openDatabase(
      join(directory.path, 'MyDatabase.db'),
      version: 2,
      onConfigure: (db) async {
        await db.execute('PRAGMA foreign_keys = ON');
      },
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE $table (
            $columnId INTEGER PRIMARY KEY,
            $columnName TEXT NOT NULL,
            $columnAge INTEGER NOT NULL
          )
        ''');
        await createCatalogueTables(db);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) await createCatalogueTables(db);
      },
    );
  }

  // sqflite wraps onCreate/onUpgrade in a transaction already.
  static Future<void> createCatalogueTables(Database db) async {
    await db.execute('''CREATE TABLE folders (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      name TEXT NOT NULL UNIQUE,
      created_at TEXT NOT NULL
    )''');
    await db.execute('''CREATE TABLE cards (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      title TEXT NOT NULL,
      suit TEXT NOT NULL,
      notes TEXT NOT NULL DEFAULT '',
      image_ref TEXT,
      folder_id INTEGER NOT NULL,
      FOREIGN KEY (folder_id) REFERENCES folders(id) ON DELETE CASCADE
    )''');
    await db.execute('CREATE INDEX idx_cards_folder_id ON cards(folder_id)');
  }

  Future<int> insertFolder(String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) throw ArgumentError('Folder name cannot be blank.');
    return _db.insert(
      'folders',
      Folder(
        name: trimmed,
        createdAt: DateTime.now().toUtc().toIso8601String(),
      ).toMap(),
    );
  }

  Future<List<Folder>> getFoldersWithCounts() async {
    final rows = await _db.rawQuery('''SELECT f.id, f.name, f.created_at,
      COUNT(c.id) AS card_count FROM folders f
      LEFT JOIN cards c ON c.folder_id = f.id
      GROUP BY f.id, f.name, f.created_at
      ORDER BY f.name COLLATE NOCASE, f.id''');
    return rows.map(Folder.fromMap).toList();
  }

  Future<List<CardRecord>> getCards(int folderId) async => (await _db.query(
    'cards',
    where: 'folder_id = ?',
    whereArgs: [folderId],
    orderBy: 'title COLLATE NOCASE ASC, id ASC',
  )).map(CardRecord.fromMap).toList();

  void _validateCard(CardRecord card) {
    if (card.title.trim().isEmpty || !suits.contains(card.suit)) {
      throw ArgumentError('Enter a title and a valid suit.');
    }
  }

  Map<String, Object?> _cardMap(CardRecord card) => {
    ...card.toMap(),
    'title': card.title.trim(),
    'image_ref': (card.imageRef?.trim().isEmpty ?? true)
        ? null
        : card.imageRef!.trim(),
  };

  Future<int> insertCard(CardRecord card) {
    _validateCard(card);
    final values = _cardMap(card)..remove('id');
    return _db.insert('cards', values);
  }

  Future<int> updateCard(CardRecord card) {
    _validateCard(card);
    if (card.id == null) throw ArgumentError('An update requires an ID.');
    final values = _cardMap(card)..remove('id');
    return _db.update('cards', values, where: 'id = ?', whereArgs: [card.id]);
  }

  Future<int> deleteCard(int id) =>
      _db.delete('cards', where: 'id = ?', whereArgs: [id]);
  Future<int> deleteFolder(int id) =>
      _db.delete('folders', where: 'id = ?', whereArgs: [id]);

  // Read-only evidence from the SAME open connection that performs CRUD.
  Future<Map<String, Object?>> diagnostics() async => {
    'database': 'MyDatabase.db',
    'user_version': await _db.rawQuery('PRAGMA user_version'),
    'foreign_keys': await _db.rawQuery('PRAGMA foreign_keys'),
    'foreign_key_list': await _db.rawQuery('PRAGMA foreign_key_list(cards)'),
    'index_list': await _db.rawQuery('PRAGMA index_list(cards)'),
    'guests': await queryAllRows(),
    'folders': await _db.query('folders', orderBy: 'id'),
    'cards': await _db.query('cards', orderBy: 'id'),
  };

  Future<int> insert(Map<String, dynamic> row) => _db.insert(table, row);

  Future<List<Map<String, dynamic>>> queryAllRows() =>
      _db.query(table, orderBy: '$columnId ASC');

  Future<int> queryRowCount() async =>
      Sqflite.firstIntValue(
        await _db.rawQuery('SELECT COUNT(*) FROM $table'),
      ) ??
      0;

  Future<int> update(Map<String, dynamic> row) {
    final id = row[columnId] as int;
    return _db.update(table, row, where: '$columnId = ?', whereArgs: [id]);
  }

  Future<int> delete(int id) =>
      _db.delete(table, where: '$columnId = ?', whereArgs: [id]);
}
