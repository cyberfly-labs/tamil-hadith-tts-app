import sqlite3
import re

text = open("clean4.txt",encoding="utf8").read()

pattern = r'(ஹதீஸ்\s*[:.]?\s*\d{1,5})'
parts = re.split(pattern, text)

conn = sqlite3.connect("bukhari.db")
c = conn.cursor()

c.execute("DROP TABLE IF EXISTS hadiths")

c.execute("""
CREATE TABLE hadiths(
id INTEGER PRIMARY KEY AUTOINCREMENT,
hadith_number INTEGER,
book TEXT,
chapter TEXT,
text_tamil TEXT,
audio_path TEXT
)
""")

current_book = ""
current_chapter = ""

for i in range(len(parts)):
    block = parts[i]

    # detect book/chapter header
    book_match = re.search(r'பாகம்\s*\d+', block)
    chapter_match = re.search(r'அத்தியாயம்\s*\d+', block)

    if book_match:
        current_book = book_match.group()

    if chapter_match:
        current_chapter = chapter_match.group()

    # hadith
    if re.match(r'ஹதீஸ்', block):
        num = re.findall(r'\d+', block)[0]
        content = parts[i+1].strip()

        if len(content) < 30:
            continue

        c.execute("""
        INSERT INTO hadiths (hadith_number,book,chapter,text_tamil,audio_path)
        VALUES (?,?,?,?,?)
        """,(num,current_book,current_chapter,content,""))

conn.commit()
conn.close()

print("✅ Final DB ready")
