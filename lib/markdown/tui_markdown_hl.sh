#!/usr/bin/env bash
# tui_markdown_hl.sh - syntax highlighting of fenced code: one line at a time, no state between lines.
#
#   tui.md.highlight LANG FN       FN LINE sets TUI_MD_HL to LINE with SGR spans added (characters unchanged); "" unregisters
#
# Built in: bash (also sh, shell, zsh) and json. The spans use the hl_keyword, hl_string, hl_comment, hl_number and hl_var classes.
# requires: tui_markdown

# tui.md.highlight LANG FN - registers the highlighter of a fence language (case-insensitive).
tui.md.highlight() {
	[[ -n "$1" ]] || return 1
	if [[ -z "${2:-}" ]]; then unset '_TUI_MD_HL[${1,,}]'; else _TUI_MD_HL[${1,,}]=$2; fi
}

# _tui_md.hl_bash LINE - comments, quoted strings, $variables, keywords and numbers of one shell line.
_tui_md.hl_bash() {
	local s=$1 out="" pre w q
	local r=$_TUI_MD_RESET kw=${_TUI_MD_SGR[hl_keyword]} st=${_TUI_MD_SGR[hl_string]} cm=${_TUI_MD_SGR[hl_comment]}
	local nm=${_TUI_MD_SGR[hl_number]} vr=${_TUI_MD_SGR[hl_var]} prev=" "
	while [[ -n "$s" ]]; do
		pre=${s%%[\#\"\'\$A-Za-z_0-9]*}
		if [[ -n "$pre" ]]; then
			out+=$pre
			prev=${pre: -1}
			s=${s:${#pre}}
			continue
		fi
		case "${s:0:1}" in
			'#')
				if [[ "$prev" == [[:space:]] || -z "$out" ]]; then
					out+="${cm}${s}${r}"
					break
				fi
				out+="#"
				s=${s:1} prev="#"
				;;
			'"' | "'")
				q=${s:0:1}
				w=${s:1}
				if [[ "$q" == '"' ]]; then
					# up to the next unescaped quote
					local acc="" rest=$w ch found=0
					while [[ -n "$rest" ]]; do
						ch=${rest:0:1}
						if [[ "$ch" == '\' ]]; then
							acc+=${rest:0:2}
							rest=${rest:2}
							continue
						fi
						acc+=$ch
						rest=${rest:1}
						[[ "$ch" == '"' ]] && {
							found=1
							break
						}
					done
					out+="${st}\"${acc}${r}"
					s=$rest prev='"'
				else
					if [[ "$w" == *"'"* ]]; then
						out+="${st}'${w%%\'*}'${r}"
						s=${w#*\'}
					else
						out+="${st}'${w}${r}"
						s=""
					fi
					prev="'"
				fi
				;;
			'$')
				if [[ "$s" =~ ^\$(\{[^}]*\}|[A-Za-z_][A-Za-z0-9_]*|[0-9@#?*!\$-]) ]]; then
					out+="${vr}${BASH_REMATCH[0]}${r}"
					s=${s:${#BASH_REMATCH[0]}} prev="x"
				else
					out+='$'
					s=${s:1} prev='$'
				fi
				;;
			*)
				if [[ "$s" =~ ^[A-Za-z_][A-Za-z0-9_]* ]]; then
					w=${BASH_REMATCH[0]}
					case " if then else elif fi for in do done while until case esac function select return export local readonly declare unset source break continue exit " in
						*" $w "*) out+="${kw}${w}${r}" ;;
						*) out+=$w ;;
					esac
				elif [[ "$s" =~ ^[0-9]+ ]]; then
					w=${BASH_REMATCH[0]}
					if [[ "$prev" == [[:alnum:]_] ]]; then out+=$w; else out+="${nm}${w}${r}"; fi
				else
					w=${s:0:1}
					out+=$w
				fi
				s=${s:${#w}} prev=${w: -1}
				;;
		esac
	done
	TUI_MD_HL=$out
}

# _tui_md.hl_json LINE - keys, strings, numbers and the true / false / null literals.
_tui_md.hl_json() {
	local s=$1 out="" w pre
	local r=$_TUI_MD_RESET kw=${_TUI_MD_SGR[hl_keyword]} st=${_TUI_MD_SGR[hl_string]} nm=${_TUI_MD_SGR[hl_number]}
	while [[ -n "$s" ]]; do
		pre=${s%%[\"0-9tfn-]*}
		if [[ -n "$pre" ]]; then
			out+=$pre
			s=${s:${#pre}}
			continue
		fi
		if [[ "$s" =~ ^\"([^\"\\]|\\.)*\" ]]; then
			w=${BASH_REMATCH[0]}
			s=${s:${#w}}
			if [[ "$s" =~ ^[[:space:]]*: ]]; then out+="${kw}${w}${r}"; else out+="${st}${w}${r}"; fi
		elif [[ "$s" =~ ^-?[0-9]+(\.[0-9]+)?([eE][+-]?[0-9]+)? ]]; then
			w=${BASH_REMATCH[0]}
			out+="${nm}${w}${r}"
			s=${s:${#w}}
		elif [[ "$s" =~ ^(true|false|null) ]]; then
			w=${BASH_REMATCH[0]}
			out+="${kw}${w}${r}"
			s=${s:${#w}}
		else
			out+=${s:0:1}
			s=${s:1}
		fi
	done
	TUI_MD_HL=$out
}

_TUI_MD_HL[bash]=_tui_md.hl_bash
_TUI_MD_HL[sh]=_tui_md.hl_bash
_TUI_MD_HL[shell]=_tui_md.hl_bash
_TUI_MD_HL[zsh]=_tui_md.hl_bash
_TUI_MD_HL[json]=_tui_md.hl_json
