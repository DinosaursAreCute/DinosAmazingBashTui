# Harness sanity: both sides are the same function. Expect "~noise". A clear verdict here means bias in the runner.
AB_NAME="selfcheck"
AB_DESC="A vs A, must show no difference"
AB_SIDES=(a1 a2)
AB_CMDS=(work work)
AB_ROUNDS=30
work() {
	local i
	for ((i = 0; i < 5000; i++)); do :; done
}
