# Cost of one function-call layer. Every sample runs N iterations of a no-op body; side dK calls a chain
# of K nested functions (fK -> f(K-1) -> ... -> f1 -> ":"), i.e. exactly K calls. "inline" is the same loop with ":" in place,
# so net_ns/unit = cost of K calls and the slope over x = cost per extra layer (builtin body, no fork).
AB_NAME="call-depth"
AB_DESC="cost per nested function call layer, empty body"
N=10000
AB_UNITS=$N
AB_SIDES=(inline d1 d2 d4 d8 d16)
AB_X=(0 1 2 4 8 16)
AB_UNIT_NAME=iteration
AB_PER=(0 1 2 4 8 16) # calls per iteration
AB_PER_NAME=call
AB_CONTROL=inline
AB_CMDS=(run_d0 run_d1 run_d2 run_d4 run_d8 run_d16)
AB_ROUNDS=30

f1() { :; }
for ((_k = 2; _k <= 16; _k++)); do eval "f$_k() { f$((_k - 1)); }"; done
eval "run_d0() { local i; for ((i = 0; i < $N; i++)); do :; done; }"
for _d in 1 2 4 8 16; do eval "run_d$_d() { local i; for ((i = 0; i < $N; i++)); do f$_d; done; }"; done
