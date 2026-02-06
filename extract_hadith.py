import re

text = open("clean2.txt",encoding="utf8").read()

pattern = r'(ஹதீஸ்\s*[:.]?\s*\d{1,5})'
parts = re.split(pattern, text)

hadiths = []

for i in range(1, len(parts), 2):
    num_part = parts[i]
    content = parts[i+1]

    num = re.findall(r'\d+', num_part)
    if not num:
        continue

    num = int(num[0])

    # remove header garbage inside hadith
    content = re.sub(r'ஸஹீஹ.*', '', content)
    content = re.sub(r'பாகம்\s*\d+.*', '', content)

    content = content.strip()

    # ignore very small blocks
    if len(content) < 40:
        continue

    hadiths.append((num, content))

print("Final hadith:", len(hadiths))
