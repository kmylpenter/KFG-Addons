#!/bin/bash
# gas-html-syntax-check.sh - PostToolUse hook for Edit|Write
# Validates GAS/JS/HTML syntax after each edit
# Catches syntax errors BEFORE user discovers them manually

INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_response.filePath // .tool_input.file_path // empty' 2>/dev/null)

[ -z "$FILE_PATH" ] && echo '{}' && exit 0
[ ! -f "$FILE_PATH" ] && echo '{}' && exit 0

case "$FILE_PATH" in
  *.gs|*.js)
    # node --check does syntax-only parse, no execution
    RESULT=$(node --check "$FILE_PATH" 2>&1)
    if [ $? -ne 0 ]; then
      # Escape newlines for JSON
      ESCAPED=$(echo "$RESULT" | head -5 | tr '\n' ' ')
      echo "{\"decision\":\"report\",\"reason\":\"SYNTAX ERROR in $FILE_PATH: $ESCAPED\"}"
      exit 0
    fi
    echo '{}'
    ;;
  *.html)
    # Python html.parser catches unclosed tags and malformed structure
    RESULT=$(python3 -c "
import html.parser, sys

class Check(html.parser.HTMLParser):
    def __init__(self):
        super().__init__()
        self.stack = []
        self.errors = []
        self.void = {'area','base','br','col','embed','hr','img','input','link','meta','param','source','track','wbr'}
    def handle_starttag(self, tag, attrs):
        if tag not in self.void:
            self.stack.append((tag, self.getpos()))
    def handle_endtag(self, tag):
        if tag in self.void:
            return
        if self.stack and self.stack[-1][0] == tag:
            self.stack.pop()
        elif self.stack:
            self.errors.append(f'Line {self.getpos()[0]}: </{tag}> but expected </{self.stack[-1][0]}>')

c = Check()
try:
    c.feed(open(sys.argv[1]).read())
except Exception as e:
    print(f'Parse error: {e}')
    sys.exit(1)

for e in c.errors[:3]:
    print(e)
if c.stack:
    unclosed = [f'{t[0]}(L{t[1][0]})' for t in c.stack[:5]]
    print(f'Unclosed: {\" \".join(unclosed)}')
if not c.errors and not c.stack:
    print('ok')
" "$FILE_PATH" 2>&1)

    if [ $? -ne 0 ] || ! echo "$RESULT" | grep -q '^ok$'; then
      ESCAPED=$(echo "$RESULT" | head -5 | tr '\n' ' ')
      echo "{\"decision\":\"report\",\"reason\":\"HTML issues in $FILE_PATH: $ESCAPED\"}"
      exit 0
    fi
    echo '{}'
    ;;
  *)
    echo '{}'
    ;;
esac
