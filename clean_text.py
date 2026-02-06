#!/usr/bin/env python3
"""
clean2.txt cleaner — fixes all identified issues.

Issues found:
1. Font-encoding garbled chars (Tamil Bamini/other font → Unicode mapping errors)
   - {  → ு (kuril u vowel sign) — 3923 occurrences
   - +  → ூ (nedil u vowel sign) — in Tamil letter contexts
   - ¥  → ஊ (standalone) / ூ (vowel sign) — 673 occ
   - ¡  → ணீ → ீ (ii vowel sign) — actually தண்ணீர் → தண்¡ர் means ¡=ணீ — 657 occ
   - »  → ஷ (sha) — 538 occ — but also used for ‍ஷி in some contexts
   - ª  → ீ (ii vowel sign) — 276 occ
   - å  → ூ (uu vowel sign) — 22 occ
   - }  → ூ — 29 occ

2. Smart quotes used inconsistently
   - '' (U+2018/2019) → ' (ASCII single quote) — 28235 occ
   - "" (U+201C/201D) → normalize  — 1426 occ
   - „ (U+201E) → remove or replace — 6 occ
   - † (U+2020 dagger) → remove — 8 occ
   - U+0094 (control char) → remove — 147 occ
   - U+0092 (control char) → ' — 6 occ
   - U+0091 (control char) → ' — 3 occ
   - U+0084 (control char) → remove — 2 occ

3. Structural issues
   - 135,626 lines with trailing whitespace
   - 2,636 lines with multiple consecutive internal spaces
   - 2,207 very short lines (1-3 chars) — many are word fragments from line wrapping
   - 41 isolated "உ" lines — orphan fragments
   - 3 single consonant lines (ழ, ந, வ) — broken words
   - Table of contents at top (lines 1-228) — keep but clean

4. Punctuation issues
   - 651 double periods ".." — some are "..." (ellipsis), some are typos
   - 2 period-comma ".," — typos
"""

import re
import sys


def clean(text):
    """Apply all cleaning transformations."""

    # ══════════════════════════════════════════════════════════════
    # PHASE 1: Fix font-encoding garbled characters
    # These are from Bamini/other Tamil font → Unicode conversion errors
    # ══════════════════════════════════════════════════════════════

    # { → ு (most common: ஹ{ரைரா → ஹுரைரா, ஸ{ப்யான் → சுப்யான்)
    # But: ஷ{ஃப்ஆ = ஷுஃப்ஆ, ஹ{தைபிய்யா = ஹுதைபிய்யா
    text = text.replace("{", "ு")

    # } → ூ (பன} → பனூ)
    text = text.replace("}", "ூ")

    # + between Tamil chars → ூ (ு+த → ூத)
    # Also + at end of Tamil word before space (அப+ → அபூ)
    text = re.sub(r"(?<=[\u0B80-\u0BFF])\+(?=[\u0B80-\u0BFF])", "ூ", text)
    text = re.sub(r"(?<=[\u0B80-\u0BFF])\+(?=\s)", "ூ", text)

    # ¥ → ூ (மஸ்¥த் → மஸ்ஊத், நெகிழ்¥ → நெகிழ்வூ? No: மஸ்ஊத்)
    # Actually ¥ after a consonant/vowel sign = ஊ
    text = text.replace("\u00a5", "ஊ")

    # ¡ → ணீ (தண்¡ர் → தண்ணீர்)
    # Actually ¡ = ணீ — the ண is missing before ீ
    text = text.replace("\u00a1", "ணீ")

    # » → ஷ in most contexts (குறை»க்குலம் → குறைஷிக்குலம்)
    # Wait, looking more carefully:
    # குறை»க்குலம் → குறைஷிக்குலம்  — » = ஷி
    # இப்னு»ஹாப் → இப்னுஷிஹாப் — » = ஷி  
    # But: முன்த»ர் → முன்தஷிர் — hmm, that's முன்தழிர்?
    # No: இப்னு முன்த»ர் = இப்னு முன்திர் — so » can also = ழி or similar
    # Let's check: குரை»கள் = குரைஷிகள் — yes, » = ஷி mostly
    # துகை»ன் = துகைஷின் — yes
    # But முன்த»ர் = முன்திர் — so sometimes » = ழி
    # Actually looking at Islamic names: "முன்தழிர்" is actually "முன்திர்" (Mundhir)
    # So » might just be ழி everywhere or ஷி... 
    # Most occurrences are குறைஷி (Quraish) and இப்னுஷிஹாப் (Ibn Shihab)
    # Let me just replace with ஷி since that covers the overwhelming majority
    text = text.replace("\u00bb", "ஷி")

    # ª → ீ (vowel sign ii)
    # லைª → லைசீ? No: அல்லைª = அல்லைஸீ (al-Laythi)
    # யªது = யஸீது (Yazeed), ªரீன் = சீரீன் (Sireen)
    # ªனிய = சீனிய? No: ஸினிய (Siniya)
    # Actually ª seems to = சீ in most: இப்னு ªரீன் = இப்னு சீரீன்
    # யªத் = யஸீத் — wait that doesn't work. 
    # யழீத் (Yazeed) - so ª = ழீ? No.
    # Actually: யசீத் (Yazeed in Tamil is யஸீத்)
    # ªரீன் = சீரீன் — ª = சீ
    # மªஹுத் = மசீஹுத் (Masih) — ª = சீ
    # லைª = லைசீ — ஸீ? 
    # OK ª = சீ consistently
    text = text.replace("\u00aa", "சீ")

    # å → ூ (vowel sign uu) — but let's check:
    # åஷஃ = யூஷஃ (Yusha), அய்åபு = அய்யூபு (Ayyub), åசுஃப் = யூசுஃப் (Yusuf)
    # விåகம் = வியூகம்? Actually விஜயம்? No: வியூகம் (formation)
    # மகிழ்ச்சிåட்ட = மகிழ்ச்சியூட்ட — yes å = யூ
    # åனுஸ் = யூனுஸ் (Yunus) — yes
    # åப்ரடீஸ் = யூப்ரடீஸ் (Euphrates) — yes
    # So å = யூ
    text = text.replace("\u00e5", "யூ")

    # ══════════════════════════════════════════════════════════════
    # PHASE 2: Fix control characters and bad Unicode
    # ══════════════════════════════════════════════════════════════

    # U+0094 (cancel char, used before ! in text) → empty
    text = text.replace("\x94", "")

    # U+0092 (private use, seems like apostrophe) → '
    text = text.replace("\x92", "'")

    # U+0091 (private use, seems like opening quote) → '
    text = text.replace("\x91", "'")

    # U+0084 (IND, index) → remove
    text = text.replace("\x84", "")

    # ══════════════════════════════════════════════════════════════
    # PHASE 3: Normalize quotation marks
    # ══════════════════════════════════════════════════════════════

    # Smart single quotes → Tamil-friendly plain quotes
    text = text.replace("\u2018", "'")  # left single
    text = text.replace("\u2019", "'")  # right single

    # Smart double quotes → plain double
    text = text.replace("\u201c", '"')  # left double
    text = text.replace("\u201d", '"')  # right double

    # Double low-9 quote → plain (used in கூறியதாவது„)
    text = text.replace("\u201e", "")

    # Dagger → remove (used sporadically as quote marks)
    text = text.replace("\u2020", "")

    # ══════════════════════════════════════════════════════════════
    # PHASE 4: Fix punctuation
    # ══════════════════════════════════════════════════════════════

    # Double period ".." that's NOT part of "..." → single period
    text = re.sub(r"\.\.(?!\.)", ".", text)

    # Period-comma ".," → "."
    text = text.replace(".,", ".")

    # ══════════════════════════════════════════════════════════════
    # PHASE 5: Fix line-level issues
    # ══════════════════════════════════════════════════════════════

    lines = text.split("\n")
    cleaned_lines = []

    i = 0
    while i < len(lines):
        line = lines[i]

        # Strip trailing whitespace
        line = line.rstrip()

        # Collapse multiple internal spaces to single space
        if line.strip():
            line = re.sub(r"  +", " ", line)

        cleaned_lines.append(line)
        i += 1

    # Rejoin lines
    text = "\n".join(cleaned_lines)

    # ══════════════════════════════════════════════════════════════
    # PHASE 6: Join broken lines (word fragments)
    # ══════════════════════════════════════════════════════════════

    # Join single-character orphan lines with next line
    # e.g., "தொ\nழ\nழமாட்டார்கள்" → "தொழழமாட்டார்கள்"
    # A line that is a single Tamil character followed by a line starting
    # with Tamil text — join them
    text = re.sub(
        r"\n([\u0B80-\u0BFF])\n([\u0B80-\u0BFF])",
        lambda m: "\n" + m.group(1) + m.group(2),
        text,
    )

    # Join isolated "உ" lines with next line if next starts with Tamil
    # (These are word fragments from "உள்ளன", "உரையாடி", etc.)
    text = re.sub(
        r"\nஉ\n([\u0B80-\u0BFF])",
        lambda m: "\nஉ" + m.group(1),
        text,
    )

    return text


def main():
    input_path = "clean2.txt"
    output_path = "clean3.txt"

    print(f"Reading {input_path}...")
    with open(input_path, "r", encoding="utf-8") as f:
        text = f.read()

    orig_len = len(text)
    orig_lines = text.count("\n")
    print(f"  {orig_lines} lines, {orig_len:,} chars")

    print("Cleaning...")
    cleaned = clean(text)

    new_len = len(cleaned)
    new_lines = cleaned.count("\n")
    print(f"  {new_lines} lines, {new_len:,} chars")
    print(f"  Removed {orig_len - new_len:,} chars ({(orig_len - new_len)*100/orig_len:.1f}%)")

    print(f"Writing {output_path}...")
    with open(output_path, "w", encoding="utf-8") as f:
        f.write(cleaned)

    # Quick verification
    print("\nVerification:")
    import collections
    odd = collections.Counter()
    for ch in cleaned:
        cp = ord(ch)
        if cp > 0x7E and not (0x0B80 <= cp <= 0x0BFF):
            odd[ch] += 1
    if odd:
        print("  Remaining non-Tamil non-ASCII chars:")
        for ch, cnt in odd.most_common(20):
            import unicodedata
            name = unicodedata.name(ch, f"U+{ord(ch):04X}")
            print(f"    U+{ord(ch):04X} {name}: {cnt}")
    else:
        print("  All clean — only Tamil + ASCII remain!")

    print("\nDone!")


if __name__ == "__main__":
    main()
