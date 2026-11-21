# Context for "function calls are cheap": the real cost is the fork behind $(...).
# Fewer units per sample because each command substitution is ~1 ms.
AB_NAME="call-subshell"
AB_DESC="direct call vs command substitution (fork)"
N=300
AB_UNITS=$N
AB_SIDES=(loop direct cmdsub)
AB_CMDS=(run_loop run_direct run_cmdsub)
AB_UNIT_NAME=iteration
AB_PER=(0 1 1) # one call / one $(...) per iteration
AB_PER_NAME=call
AB_CONTROL=loop
AB_ROUNDS=20

g() { r=x; }
h() { printf x; }
eval "run_loop() { local i; for ((i = 0; i < $N; i++)); do :; done; }"
eval "run_direct() { local i r; for ((i = 0; i < $N; i++)); do g; done; }"
eval "run_cmdsub() { local i r; for ((i = 0; i < $N; i++)); do r=\$(h); done; }"
