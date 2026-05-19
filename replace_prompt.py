import re

with open('livekit_basic_agent.py', 'r', encoding='utf-8') as f:
    content = f.read()

with open('new_prompt.txt', 'r', encoding='utf-8') as f:
    new_prompt = f.read()

pattern = re.compile(r'instructions="""========================================================.*?========================================================"""', re.DOTALL)
replacement = 'instructions=' + new_prompt

new_content = pattern.sub(replacement, content)

with open('livekit_basic_agent.py', 'w', encoding='utf-8') as f:
    f.write(new_content)

print("Prompt replaced successfully.")
