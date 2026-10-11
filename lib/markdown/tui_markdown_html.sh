#!/usr/bin/env bash
# tui_markdown_html.sh - the pre-pass of tui.md.render: a small, safe HTML subset, comments and [label]: url definitions.
# HTML is never interpreted, only mapped onto what the renderer draws: <br> becomes a line break, <img> an image placeholder,
# <a href> a link, <b> <i> <code> <s> their Markdown spans, <hr> a rule, <h1>..<h6> headings; every other tag is dropped and
# its text kept. Fenced code and code spans are left alone. The number of lines never changes (removed lines become
# blank), so the line map of the render still points at the source.
# requires: tui_markdown

_TUI_MD_RE_TAG='<(/?)([A-Za-z][A-Za-z0-9]*)([[:space:]][^<>]*)?(/?)>'
_TUI_MD_RE_REFDEF='^[[:space:]]{0,3}\[([^]]+)\]:[[:space:]]*<?([^[:space:]>]+)>?([[:space:]]+("[^"]*"|'"'"'[^'"'"']*'"'"'|\([^)]*\)))?[[:space:]]*$'
_TUI_MD_RE_HTMLHEAD='^[[:space:]]*<[hH]([1-6])[^>]*>(.*)</[hH]\1>[[:space:]]*$'

# _tui_md.html_inline LINE -> _HTML_LINE - the tags of one line that has no code spans.
_tui_md.html_inline() {
	local s=$1 out="" pre tag closing attrs name href alt src
	while [[ "$s" =~ $_TUI_MD_RE_TAG ]]; do
		tag=${BASH_REMATCH[0]}
		closing=${BASH_REMATCH[1]}
		name=${BASH_REMATCH[2],,}
		attrs=${BASH_REMATCH[3]}
		pre=${s%%"$tag"*}
		out+=$pre
		s=${s#*"$tag"}
		case "$name" in
			br) out+=" "$'\x01'" " ;;
			img)
				alt="" src=""
				[[ "$attrs" =~ alt=\"([^\"]*)\" ]] && alt=${BASH_REMATCH[1]}
				[[ "$attrs" =~ src=\"([^\"]*)\" ]] && src=${BASH_REMATCH[1]}
				out+="![${alt}](${src})"
				;;
			a)
				if [[ -n "$closing" ]]; then
					out+="](${_HTML_HREF:-})"
				else
					href=""
					[[ "$attrs" =~ href=\"([^\"]*)\" ]] && href=${BASH_REMATCH[1]}
					_HTML_HREF=$href
					out+="["
				fi
				;;
			b | strong) out+="**" ;;
			i | em) out+="*" ;;
			code | kbd | tt) out+='`' ;;
			s | del | strike) out+="~~" ;;
			li) [[ -z "$closing" ]] && out+="- " ;;
			*) ;; # div p span center details summary sub sup ul ol table tr td th ...: the tag goes, its text stays
		esac
	done
	_HTML_LINE=$out$s
}

# _tui_md.html_entities LINE -> _HTML_LINE
_tui_md.html_entities() {
	local s=$1
	s=${s//&nbsp;/ }
	s=${s//&lt;/<}
	s=${s//&gt;/>}
	s=${s//&quot;/\"}
	s=${s//&#39;/\'}
	s=${s//&copy;/©}
	s=${s//&amp;/&}
	_HTML_LINE=$s
}

# _tui_md.html_pass TEXT -> _MD_ROW - fills _TUI_MD_REFS and returns TEXT with tags mapped, comments and definitions blanked.
_tui_md.html_pass() {
	local line out="" infence=0 fchar="" flen=0 incomment=0 lead ct run rest seg i n
	local -a lines segs
	mapfile -t lines <<<"$1"
	for line in "${lines[@]}"; do
		if ((incomment)); then
			if [[ "$line" == *"-->"* ]]; then
				incomment=0
				line=${line#*-->}
			else
				out+=$'\n'
				continue
			fi
		fi
		if ((infence)); then
			lead=${line%%[! ]*}
			ct=${line#"$lead"}
			if ((${#lead} <= 3)) && [[ "$ct" == "$fchar"* ]]; then
				run=${ct%%[!"$fchar"]*}
				rest=${ct:${#run}}
				((${#run} >= flen)) && [[ -z "${rest// /}" ]] && infence=0
			fi
			out+=$line$'\n'
			continue
		fi
		if [[ "$line" == *'```'* || "$line" == *'~~~'* ]] && [[ "$line" =~ $_TUI_MD_RE_FENCE ]]; then
			infence=1 fchar=${BASH_REMATCH[1]:0:1} flen=${#BASH_REMATCH[1]}
			out+=$line$'\n'
			continue
		fi
		while [[ "$line" == *"<!--"* ]]; do
			if [[ "${line#*<!--}" == *"-->"* ]]; then
				line="${line%%<!--*}${line#*<!--*-->}"
			else
				line=${line%%<!--*}
				incomment=1
				break
			fi
		done
		if [[ "$line" == *"]:"* && "$line" =~ $_TUI_MD_RE_REFDEF ]]; then
			seg=${BASH_REMATCH[1],,}
			seg=${seg//[[:space:]]/ }
			_TUI_MD_REFS[$seg]=${BASH_REMATCH[2]}
			out+=$'\n'
			continue
		fi
		if [[ "$line" == *"<"* ]]; then
			if [[ "$line" =~ ^[[:space:]]*\<[hH][rR][[:space:]/]*\>[[:space:]]*$ ]]; then
				line="---"
			elif [[ "$line" =~ $_TUI_MD_RE_HTMLHEAD ]]; then
				printf -v seg '%*s' "${BASH_REMATCH[1]}" ''
				line="${seg// /#} ${BASH_REMATCH[2]}"
			fi
			if [[ "$line" == *'`'* ]]; then
				# only the parts between code spans
				IFS='`' read -ra segs <<<"$line"
				line=""
				for i in "${!segs[@]}"; do
					seg=${segs[i]}
					if ((i % 2 == 0)); then
						_tui_md.html_inline "$seg"
						seg=$_HTML_LINE
					fi
					line+=${line:+\`}$seg
				done
			else
				_tui_md.html_inline "$line"
				line=$_HTML_LINE
			fi
		fi
		[[ "$line" == *"&"* ]] && {
			_tui_md.html_entities "$line"
			line=$_HTML_LINE
		}
		out+=$line$'\n'
	done
	_MD_ROW=${out%$'\n'}
}
