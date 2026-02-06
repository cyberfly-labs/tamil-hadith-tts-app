import re

text = open("unicode.txt",encoding="utf8").read()

# remove publisher / contact
text = re.sub(r'Daya Islamic Media.*', '', text)
text = re.sub(r'Contact:.*', '', text)
text = re.sub(r'@.*', '', text)

# remove book headers
text = re.sub(r'ஸஹீஹ.*புஹாரி.*', '', text)

# remove weird symbol lines
text = re.sub(r'^[^\u0B80-\u0BFF\n]+$', '', text, flags=re.MULTILINE)

# remove extra blank lines
text = re.sub(r'\n\s*\n', '\n\n', text)

open("clean2.txt","w",encoding="utf8").write(text)

print("clean done")
