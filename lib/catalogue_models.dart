const suits = ['Hearts', 'Diamonds', 'Clubs', 'Spades'];
const suitSymbols = {
  'Hearts': '♥',
  'Diamonds': '♦',
  'Clubs': '♣',
  'Spades': '♠',
};

class Folder {
  const Folder({
    this.id,
    required this.name,
    required this.createdAt,
    this.cardCount = 0,
  });
  final int? id;
  final String name;
  final String createdAt;
  final int cardCount;
  factory Folder.fromMap(Map<String, Object?> map) => Folder(
    id: map['id'] as int,
    name: map['name'] as String,
    createdAt: map['created_at'] as String,
    cardCount: (map['card_count'] as int?) ?? 0,
  );
  Map<String, Object?> toMap() => {
    if (id != null) 'id': id,
    'name': name,
    'created_at': createdAt,
  };
}

class CardRecord {
  const CardRecord({
    this.id,
    required this.title,
    required this.suit,
    required this.folderId,
    this.notes = '',
    this.imageRef,
  });
  final int? id;
  final String title;
  final String suit;
  final int folderId;
  final String notes;
  final String? imageRef;
  factory CardRecord.fromMap(Map<String, Object?> map) => CardRecord(
    id: map['id'] as int,
    title: map['title'] as String,
    suit: map['suit'] as String,
    folderId: map['folder_id'] as int,
    notes: map['notes'] as String,
    imageRef: map['image_ref'] as String?,
  );
  Map<String, Object?> toMap() => {
    if (id != null) 'id': id,
    'title': title,
    'suit': suit,
    'folder_id': folderId,
    'notes': notes,
    'image_ref': imageRef,
  };
}
