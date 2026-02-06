/// Represents a hadith collection type
enum HadithCollection {
  bukhari,
  muslim;

  String get displayName {
    switch (this) {
      case HadithCollection.bukhari:
        return 'ஸஹீஹுல் புகாரி';
      case HadithCollection.muslim:
        return 'ஸஹீஹ் முஸ்லிம்';
    }
  }

  String get shortName {
    switch (this) {
      case HadithCollection.bukhari:
        return 'புகாரி';
      case HadithCollection.muslim:
        return 'முஸ்லிம்';
    }
  }

  String get tableName {
    switch (this) {
      case HadithCollection.bukhari:
        return 'bukhari';
      case HadithCollection.muslim:
        return 'sahihmuslim';
    }
  }

  String get headTableName {
    switch (this) {
      case HadithCollection.bukhari:
        return 'bukhari_head';
      case HadithCollection.muslim:
        return 'muslim_head';
    }
  }
}

/// Represents a book/chapter index entry from the head tables
class HadithBookIndex {
  final int firstHadithNumber;
  final int bookNumber;
  final String bookTitle;
  final int? volume; // Bukhari only has volumes

  const HadithBookIndex({
    required this.firstHadithNumber,
    required this.bookNumber,
    required this.bookTitle,
    this.volume,
  });

  factory HadithBookIndex.fromBukhariHead(Map<String, dynamic> map) {
    return HadithBookIndex(
      firstHadithNumber: map['sno'] as int? ?? 0,
      bookNumber: map['book'] as int? ?? 0,
      bookTitle: map['booktitle'] as String? ?? '',
      volume: map['volume'] as int?,
    );
  }

  factory HadithBookIndex.fromMuslimHead(Map<String, dynamic> map) {
    return HadithBookIndex(
      firstHadithNumber: map['hadithno'] as int? ?? 0,
      bookNumber: map['book'] as int? ?? 0,
      bookTitle: map['bookname'] as String? ?? '',
    );
  }

  @override
  String toString() => 'HadithBookIndex(book=$bookNumber, "$bookTitle")';
}

/// Hadith data model — supports both Bukhari and Muslim collections
class Hadith {
  final int hadithNumber;
  final HadithCollection collection;
  final String content; // Main Tamil text
  final String bookTitle;
  final int bookNumber;
  final String lessionHeading;
  final String narratedBy; // Bukhari only
  final String arabic; // Bukhari only
  final int? volume; // Bukhari only

  const Hadith({
    required this.hadithNumber,
    required this.collection,
    required this.content,
    required this.bookTitle,
    required this.bookNumber,
    this.lessionHeading = '',
    this.narratedBy = '',
    this.arabic = '',
    this.volume,
  });

  /// Create from a Bukhari table row
  factory Hadith.fromBukhari(Map<String, dynamic> map) {
    return Hadith(
      hadithNumber: map['sno'] as int? ?? 0,
      collection: HadithCollection.bukhari,
      content: map['content'] as String? ?? '',
      bookTitle: map['booktitle'] as String? ?? '',
      bookNumber: map['book'] is int
          ? map['book'] as int
          : int.tryParse(map['book']?.toString() ?? '') ?? 0,
      lessionHeading: map['lessionheading'] as String? ?? '',
      narratedBy: map['narratedby'] as String? ?? '',
      arabic: map['arabic'] as String? ?? '',
      volume: map['volume'] as int?,
    );
  }

  /// Create from a Sahih Muslim table row
  factory Hadith.fromMuslim(Map<String, dynamic> map) {
    return Hadith(
      hadithNumber: map['hadithno'] as int? ?? 0,
      collection: HadithCollection.muslim,
      content: map['content'] as String? ?? '',
      bookTitle: map['bookname'] as String? ?? '',
      bookNumber: map['book'] is int
          ? map['book'] as int
          : int.tryParse(map['book']?.toString() ?? '') ?? 0,
      lessionHeading: map['lessionheading'] as String? ?? '',
    );
  }

  /// Unified cache key for audio: collection prefix + hadith number
  String get cacheKey => '${collection.name}_$hadithNumber';

  /// Get a short preview of the hadith text
  String get preview {
    if (content.length <= 120) return content;
    return '${content.substring(0, 120)}...';
  }

  /// For display in UI — the book name
  String get book => bookTitle;

  /// For display — the lesson/chapter heading
  String get chapter => lessionHeading;

  /// The main Tamil text
  String get textTamil => content;

  @override
  String toString() =>
      'Hadith(${collection.shortName} #$hadithNumber, book=$bookNumber)';
}
