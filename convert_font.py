from tamil.txt2unicode import bamini2unicode

with open("bukhari_raw.txt", encoding="utf8") as f:
    raw = f.read()

unicode_text = bamini2unicode(raw)

with open("unicode.txt", "w", encoding="utf8") as f:
    f.write(unicode_text)

print("done")

