#!/usr/bin/env python3
"""
clean4.py - Remove garbled PDF headers and fix stray English letters in clean3.txt
Produces clean4.txt

Issues found:
1. "னுயலய ஐளடயஅiஉ ஆநனயை - Pநசலையமரடயஅ ஊழவெயஉவ : னபinயொ"
   → Garbled Bamini conversion of "Daya Islamic Media – Periyakulam Contact : dginnah@yahoo.co.in"
   → 2,207 occurrences (one per PDF page). Remove entire line.

2. Stray English letters (h, i, n, N, p, P) from incomplete Bamini→Unicode conversion
   → ~200 unique broken words, 613 stray chars total
   → Apply pattern-based fixes where possible, strip remainder
"""
import re

with open('clean3.txt', 'r', encoding='utf-8') as f:
    text = f.read()

original_len = len(text)
original_lines = text.count('\n')

# ══════════════════════════════════════════════════════════════
# 1. Remove garbled PDF header/footer lines
# ══════════════════════════════════════════════════════════════
garbled_header = 'னுயலய ஐளடயஅiஉ ஆநனயை - Pநசலையமரடயஅ ஊழவெயஉவ : னபinயொ'
lines = text.split('\n')
lines = [l for l in lines if garbled_header not in l]
text = '\n'.join(lines)
removed_headers = original_lines - text.count('\n')
print(f"1. Removed {removed_headers} garbled PDF header lines")

# ══════════════════════════════════════════════════════════════
# 2. Word-level fixes for common stray-letter patterns
# ══════════════════════════════════════════════════════════════

# Pattern: ந்h → நா (e.g. பெருந்hள் → பெருநாள்)
count_nha = len(re.findall(r'ந்h', text))
text = re.sub(r'ந்h', 'நா', text)
print(f"2a. Fixed {count_nha} 'ந்h' → 'நா' patterns (பெருநாள் etc.)")

# Pattern: க்hள → ர்கள (e.g. அவக்hள் → அவர்கள்)
count_kha = len(re.findall(r'க்hள', text))
text = re.sub(r'க்hள', 'ர்கள', text)
print(f"2b. Fixed {count_kha} 'க்hள' → 'ர்கள' patterns (அவர்கள் etc.)")

# Pattern: ர்h at word boundary → ர் (stray h after pulli: அம்ர்h → அம்ர்)
count_rh = len(re.findall(r'ர்h(?=\s|[,.\'\"]|$)', text))
text = re.sub(r'ர்h(?=\s|[,.\'\"]|$)', 'ர்', text)
print(f"2c. Fixed {count_rh} trailing 'ர்h' → 'ர்' patterns")

# Pattern: standalone 'h' at word start → ந (e.g. hன்கு → நான்கு, hரி → நரி)
# Tamil chars range: \u0B80-\u0BFF
count_h_start = len(re.findall(r'(?<=\s)h(?=[\u0B80-\u0BFF])', text))
text = re.sub(r'(?<=\s)h(?=[\u0B80-\u0BFF])', 'ந', text)
# Also at line start
count_h_start2 = len(re.findall(r'^h(?=[\u0B80-\u0BFF])', text, re.MULTILINE))
text = re.sub(r'^h(?=[\u0B80-\u0BFF])', 'ந', text, flags=re.MULTILINE)
print(f"2d. Fixed {count_h_start + count_h_start2} word-initial 'h' → 'ந' patterns")

# Pattern: 'N' after Tamil chars → remove (these are stray control artifacts)  
count_N = len(re.findall(r'(?<=[\u0B80-\u0BFF])N', text))
text = re.sub(r'(?<=[\u0B80-\u0BFF])N', '', text)
print(f"2e. Removed {count_N} stray 'N' after Tamil chars")

# Pattern: 'n' within Tamil words → remove 
count_n = len(re.findall(r'n(?=[\u0B80-\u0BFF])', text))
text = re.sub(r'n(?=[\u0B80-\u0BFF])', '', text)
print(f"2f. Removed {count_n} stray 'n' within Tamil words")

# Pattern: 'i' within Tamil words → just remove 
count_i = len(re.findall(r'(?<=[\u0B80-\u0BFF])i', text))
text = re.sub(r'(?<=[\u0B80-\u0BFF])i', '', text)
print(f"2g. Removed {count_i} stray 'i' within Tamil words")

# ══════════════════════════════════════════════════════════════
# 3. Remove any remaining stray English letters  
# ══════════════════════════════════════════════════════════════
remaining = re.findall(r'[A-Za-z]', text)
if remaining:
    text = re.sub(r'[A-Za-z]', '', text)
    print(f"3. Removed {len(remaining)} remaining stray English letters")
else:
    print(f"3. No remaining stray English letters!")

# ══════════════════════════════════════════════════════════════
# 4. Cleanup: collapse multiple spaces, trim lines
# ══════════════════════════════════════════════════════════════
text = re.sub(r' {2,}', ' ', text)
lines = text.split('\n')
lines = [l.strip() for l in lines]
# Remove blank lines that result from header removal  
lines = [l for l in lines if l]
text = '\n'.join(lines)

# Write output
with open('clean4.txt', 'w', encoding='utf-8') as f:
    f.write(text)

new_len = len(text)
new_lines = text.count('\n') + 1
print(f"\n{'='*50}")
print(f"Input:  clean3.txt ({original_len:,} chars, {original_lines:,} lines)")
print(f"Output: clean4.txt ({new_len:,} chars, {new_lines:,} lines)")
print(f"Removed: {original_len - new_len:,} chars ({(original_len - new_len) / original_len * 100:.1f}%)")

# Verify: check for any remaining English
with open('clean4.txt', 'r') as f:
    verify = f.read()
eng_remaining = re.findall(r'[A-Za-z]', verify)
print(f"\nVerification: {len(eng_remaining)} English letters remaining in clean4.txt")
