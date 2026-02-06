import fitz  # pymupdf

doc = fitz.open("Sahih-Bukari-Tamil-Full-7-Parts.pdf")

full_text = ""

for page in doc:
    full_text += page.get_text("text") + "\n"

open("bukhari_raw.txt","w",encoding="utf8").write(full_text)

