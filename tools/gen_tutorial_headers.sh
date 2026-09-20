#!/usr/bin/env bash
# Regenerates the colored section headers of docs/tutorials/*.md (block5 font, see tools/gen_header.sh).
set -eu
d=$(cd "$(dirname "$0")" && pwd); out="$d/../docs/tutorials/img"
while IFS='|' read -r slug text; do
  [[ -n "$slug" ]] && "$d/gen_header.sh" "$text" "$out/$slug.svg" 6 >/dev/null
done <<'LIST'
app-title|WRITING YOUR FIRST APP
app-what|WHAT YOU WILL BUILD
app-ideas|THE BIG IDEAS
app-1|STEP 1: THE FOLDER
app-2|STEP 2: A FIRST PAGE
app-3|STEP 3: PANES
app-4|STEP 4: WIDGETS
app-5|STEP 5: BEHAVIOUR
app-6|STEP 6: STYLE
app-7|STEP 7: SAVE DATA
app-8|STEP 8: INSTALL IT
app-recap|RECAP
app-next|WHERE NEXT?
plugin-title|WRITING YOUR FIRST PLUGIN
plugin-what|WHAT YOU WILL BUILD
plugin-ideas|THE BIG IDEAS
plugin-1|STEP 1: THE FILE
plugin-2|STEP 2: ON ENABLE
plugin-3|STEP 3: A COMMAND
plugin-4|STEP 4: A KEY
plugin-5|STEP 5: A TIMER
plugin-6|STEP 6: SETTINGS
plugin-7|STEP 7: CLEAN UP
plugin-8|STEP 8: TRY IT
plugin-9|STEP 9: SCAN IT
plugin-recap|RECAP
plugin-next|WHERE NEXT?
LIST
