import 'dart:convert';
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

  /// Load the vocabulary from tokens.txt asset
  /// tokens.txt format: "char id" per line (derived from vocab.json)
  Future<void> load() async {
    final data = await rootBundle.loadString('assets/models/tokens.txt');
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
  /// 1. Map each character to its vocab ID
  /// 2. If [addBlank] is true, interleave blank tokens:
  ///    [blank, t1, blank, t2, blank, ..., tN, blank]
  ///    This matches HuggingFace VitsTokenizer behavior
  List<int> tokenize(String text) {
    if (!isLoaded) {
      throw StateError('Tokenizer not loaded. Call load() first.');
    }

    // Step 1: character-level tokenization
    final List<int> rawIds = [];
    for (int i = 0; i < text.length; i++) {
      final char = text[i];

      if (_charToId.containsKey(char)) {
        rawIds.add(_charToId[char]!);
      } else {
        // Try case-insensitive match (tokens.txt has both A/a → 15)
        final lower = char.toLowerCase();
        final upper = char.toUpperCase();
        if (_charToId.containsKey(lower)) {
          rawIds.add(_charToId[lower]!);
        } else if (_charToId.containsKey(upper)) {
          rawIds.add(_charToId[upper]!);
        }
        // Skip unknown characters (punctuation not in vocab, etc.)
      }
    }

    if (!addBlank) return rawIds;

    // Step 2: interleave blanks — [blank, t1, blank, t2, blank, ..., tN, blank]
    final List<int> withBlanks = List<int>.filled(rawIds.length * 2 + 1, blankId);
    for (int i = 0; i < rawIds.length; i++) {
      withBlanks[i * 2 + 1] = rawIds[i];
    }

    return withBlanks;
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
