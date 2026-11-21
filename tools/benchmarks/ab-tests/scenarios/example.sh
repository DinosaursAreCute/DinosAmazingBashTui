# Example scenario: string split via subshell fork vs. parameter expansion.
AB_NAME="split-fork-vs-builtin"
AB_DESC="cut in a subshell vs. bash parameter expansion"
A_LABEL="fork" B_LABEL="builtin"
A_CMD="split_fork"
B_CMD="split_builtin"
AB_ROUNDS=40

IN="alpha:beta:gamma:delta"
split_fork() {
	local x
	for _ in {1..50}; do x="$(cut -d: -f3 <<<"$IN")"; done
}
split_builtin() {
	local x r
	for _ in {1..50}; do
		r="${IN#*:*:}"
		x="${r%%:*}"
	done
}
