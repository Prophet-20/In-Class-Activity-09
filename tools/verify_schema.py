"""Supplemental host SQLite checks. These do not replace device tests T1-T6."""
from pathlib import Path
import re, sqlite3, json
source=(Path(__file__).resolve().parents[1]/'lib/database_helper.dart').read_text()
section=source.split('static Future<void> createCatalogueTables')[1].split('Future<int> insertFolder')[0]
sql=re.findall(r"await db.execute\(\s*'''(.*?)'''\s*\);",section,re.S)
sql+=re.findall(r"await db.execute\('([^']+)'\);",section)
assert len(sql)==3, sql
def connection():
    db=sqlite3.connect(':memory:')
    db.execute('PRAGMA foreign_keys=ON')
    db.execute('CREATE TABLE my_table (_id INTEGER PRIMARY KEY, name TEXT NOT NULL, age INTEGER NOT NULL)')
    return db
db=connection()
db.execute("INSERT INTO my_table VALUES (7, 'Sample Guest', 31)")
before=db.execute('SELECT * FROM my_table').fetchall()
with db:
    for statement in sql: db.execute(statement)
assert before==db.execute('SELECT * FROM my_table').fetchall()
assert db.execute('PRAGMA foreign_keys').fetchone()==(1,)
for name in ['Atlas','Harbor']:
    db.execute('INSERT INTO folders(name,created_at) VALUES (?,?)',(name,'2026-10-12T00:00:00Z'))
atlas,harbor=[r[0] for r in db.execute('SELECT id FROM folders ORDER BY id')]
for title,folder in [('Compass',atlas),('Compass',atlas),('Signal',harbor)]:
    db.execute('INSERT INTO cards(title,suit,folder_id) VALUES (?,?,?)',(title,'Hearts',folder))
ids=[r[0] for r in db.execute('SELECT id FROM cards ORDER BY id')]
assert len(set(ids))==3
assert db.execute('UPDATE cards SET title=? WHERE id=?',('Compass revised',ids[0])).rowcount==1
assert db.execute('SELECT title FROM cards WHERE id=?',(ids[1],)).fetchone()==('Compass',)
assert db.execute('DELETE FROM cards WHERE id=?',(ids[0],)).rowcount==1
assert db.execute('DELETE FROM folders WHERE id=?',(atlas,)).rowcount==1
assert db.execute('SELECT id FROM cards').fetchall()==[(ids[2],)]
try:
    db.execute('INSERT INTO folders(name,created_at) VALUES (?,?)',('Harbor','now'))
    raise AssertionError('Duplicate folder accepted')
except sqlite3.IntegrityError: pass
try:
    db.execute("INSERT INTO cards(title,suit,folder_id) VALUES ('Invalid','Spades',999)")
    raise AssertionError('Orphan accepted')
except sqlite3.IntegrityError: pass
fresh=connection()
for statement in sql: fresh.execute(statement)
assert {'my_table','folders','cards'} <= {r[0] for r in fresh.execute("SELECT name FROM sqlite_master WHERE type='table'")}
print('PASS: extracted catalogue SQL creates fresh tables; preserves fixture guest; scopes edit by ID; enforces duplicate names and foreign keys; cascades only Atlas cards.')
print('Host SQLite only. These fixture IDs are NOT Android app observations or required T1-T6 evidence.')
print('foreign_key_list(cards):',db.execute('PRAGMA foreign_key_list(cards)').fetchall())
print('index_list(cards):',db.execute('PRAGMA index_list(cards)').fetchall())
