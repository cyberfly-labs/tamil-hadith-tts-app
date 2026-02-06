import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/services.dart';

/// Tokenizer for facebook/mms-tts-tam VITS model
/// Uses vocab.json format and implements add_blank (interleave blank tokens)
/// Reference: https://huggingface.co/facebook/mms-tts-tam
class TamilTokenizer {
  final Map<String, int> _charToId = {};
  final Map<int, String> _idToChar = {};

  /// Blank/pad token ID — the pad_token "3" maps to ID 0 in vocab.json
  static const int blankId = 0;

  /// Whether to insert blank tokens between each character (VITS requirement)
  static const bool addBlank = true;

  bool get isLoaded => _charToId.isNotEmpty;

  /// Tokenization cache: avoids re-tokenizing the same chunk thousands of
  /// times when replaying cached hadith or re-chunking identical text.
  /// Values are [Uint16List] for ~4× smaller footprint than List<int>.
  final Map<String, Uint16List> _cache = {};
  static const int _maxCacheSize = 2048;

  /// Maximum input length guard. Texts beyond this are truncated to
  /// prevent accidental freezes from huge clipboard pastes.
  static const int _maxTextLength = 5000;

  /// Strip invisible Unicode junk that creeps in from PDFs / web scrapes.
  /// Zero-width chars, NBSP, BOM, and directional marks all break the
  /// character→token mapping and cause garbled pronunciation.
  static String normalize(String text) {
    return text
        .replaceAll('\u200C', '')  // zero-width non-joiner
        .replaceAll('\u200D', '')  // zero-width joiner
        .replaceAll('\uFEFF', '')  // BOM
        .replaceAll('\u200B', '')  // zero-width space
        .replaceAll('\u200E', '')  // LTR mark
        .replaceAll('\u200F', '')  // RTL mark
        .replaceAll('\u00A0', ' ') // NBSP → normal space
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  /// Load the vocabulary from tokens.txt asset (Flutter main isolate only)
  /// tokens.txt format: "char id" per line (derived from vocab.json)
  Future<void> load() async {
    final data = await rootBundle.loadString('assets/models/tokens.txt');
    _parseVocab(data);
  }

  /// Load the vocabulary from a file path (works in any isolate).
  void loadFromFile(String path) {
    final data = File(path).readAsStringSync();
    _parseVocab(data);
  }

  /// Parse vocabulary data from string content.
  void _parseVocab(String data) {
    final lines = const LineSplitter().convert(data);

    for (final line in lines) {
      if (line.trim().isEmpty) continue;
      final lastSpace = line.lastIndexOf(' ');
      if (lastSpace == -1) continue;

      final token = line.substring(0, lastSpace);
      final idStr = line.substring(lastSpace + 1).trim();
      final id = int.tryParse(idStr);
      if (id == null) continue;

      _charToId[token] = id;
      if (!_idToChar.containsKey(id)) {
        _idToChar[id] = token;
      }
    }
  }

  /// Tokenize Tamil text into a list of token IDs for VITS
  ///
  /// 1. Unicode-normalize the input (strip zero-width chars, NBSP, etc.)
  /// 2. Map each character to its vocab ID (unknown → space)
  /// 3. If [addBlank] is true, interleave blank tokens:
  ///    [blank, t1, blank, t2, blank, ..., tN, blank]
  ///    This matches HuggingFace VitsTokenizer behavior
  ///
  /// Results are cached for repeated calls with the same text.
  List<int> tokenize(String text) {
    if (!isLoaded) {
      throw StateError('Tokenizer not loaded. Call load() first.');
    }

    // Step 0: Unicode normalization FIRST — so the cache key is canonical.
    // Without this, "text\u200B" and "text" become two separate cache entries.
    var clean = normalize(text);

    // Safety guard: truncate absurdly long input to prevent freeze
    if (clean.length > _maxTextLength) {
      clean = clean.substring(0, _maxTextLength);
    }

    // Check cache (using normalized key)
    final cached = _cache[clean];
    if (cached != null) return cached;

    // Step 1: character-level tokenization into a compact Uint16List
    final spaceId = _charToId[' '] ?? blankId;
    final rawIds = Uint16List(clean.length);
    for (int i = 0; i < clean.length; i++) {
      final char = clean[i];

      if (_charToId.containsKey(char)) {
        rawIds[i] = _charToId[char]!;
      } else {
        // Try case-insensitive match (tokens.txt has both A/a → 15)
        final lower = char.toLowerCase();
        final upper = char.toUpperCase();
        if (_charToId.containsKey(lower)) {
          rawIds[i] = _charToId[lower]!;
        } else if (_charToId.containsKey(upper)) {
          rawIds[i] = _charToId[upper]!;
        } else {
          // Unknown char → space (prevents word-merging artifacts)
          rawIds[i] = spaceId;
        }
      }
    }

    if (!addBlank) {
      _cacheResult(clean, rawIds);
      return rawIds;
    }

    // Step 2: interleave blanks — [blank, t1, blank, t2, blank, ..., tN, blank]
    final withBlanks = Uint16List(rawIds.length * 2 + 1);
    // All slots default to 0 (== blankId), so only fill odd positions.
    for (int i = 0; i < rawIds.length; i++) {
      withBlanks[i * 2 + 1] = rawIds[i];
    }

    _cacheResult(clean, withBlanks);
    return withBlanks;
  }

  /// Store result in cache, evicting oldest entries if over limit.
  void _cacheResult(String text, Uint16List result) {
    if (_cache.length >= _maxCacheSize) {
      // Evict oldest ~25% to avoid constant eviction
      final keysToRemove = _cache.keys.take(_maxCacheSize ~/ 4).toList();
      for (final k in keysToRemove) {
        _cache.remove(k);
      }
    }
    _cache[text] = result;
  }

  /// Clear the tokenization cache (call when app goes to background).
  void clearCache() => _cache.clear();

  /// Warm up the tokenizer by tokenizing sample texts.
  /// Call early (e.g. after init) so the first real tokenize is fast.
  void warmup(List<String> sampleTexts) {
    for (final text in sampleTexts) {
      if (text.trim().isNotEmpty) tokenize(text);
    }
  }

  /// Detokenize token IDs back to text (skipping blank tokens)
  String detokenize(List<int> ids) {
    final buffer = StringBuffer();
    for (final id in ids) {
      if (id == blankId) continue; // skip blanks
      if (_idToChar.containsKey(id)) {
        final char = _idToChar[id]!;
        if (char == ' ') {
          buffer.write(' ');
        } else {
          buffer.write(char);
        }
      }
    }
    return buffer.toString();
  }

  int get vocabSize => _charToId.length;
}
