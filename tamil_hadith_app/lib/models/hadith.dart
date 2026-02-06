/// Hadith data model
class Hadith {
  final int id;
  final int hadithNumber;
  final String book;
  final String chapter;
  final String textTamil;
  final String? audioPath;

  const Hadith({
    required this.id,
    required this.hadithNumber,
    required this.book,
    required this.chapter,
    required this.textTamil,
    this.audioPath,
  });

  factory Hadith.fromMap(Map<String, dynamic> map) {
    return Hadith(
      id: map['id'] as int,
      hadithNumber: map['hadith_number'] as int,
      book: map['book'] as String? ?? '',
      chapter: map['chapter'] as String? ?? '',
      textTamil: map['text_tamil'] as String? ?? '',
      audioPath: map['audio_path'] as String?,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'hadith_number': hadithNumber,
      'book': book,
      'chapter': chapter,
      'text_tamil': textTamil,
      'audio_path': audioPath,
    };
  }

  /// Get a short preview of the hadith text
  String get preview {
    if (textTamil.length <= 120) return textTamil;
    return '${textTamil.substring(0, 120)}...';
  }

  @override
  String toString() => 'Hadith(#$hadithNumber, $book)';
}
