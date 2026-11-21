# What a call costs around the edges: arguments, locals, and a realistic body (arithmetic, [[ ]]).
# Control = the loop with ":" . Compare each "_call" with its "_inline" twin: the gap is pure call overhead,
# and the twin's own net_ns/unit shows what fraction of the call cost that body is.
AB_NAME="call-variants"
AB_DESC="call overhead with args, locals and realistic bodies"
N=10000
AB_UNITS=$N
AB_SIDES=(empty call0 call3args local3 expr_inline expr_call test_inline test_call)
AB_CMDS=(run_empty run_call0 run_call3args run_local3 run_expr_inline run_expr_call run_test_inline run_test_call)
AB_UNIT_NAME=iteration
AB_PER=(0 1 1 1 0 1 0 1) # calls per iteration
AB_PER_NAME=call
AB_CONTROL=empty
AB_ROUNDS=30

c0() { :; }
c3() { :; }
l3() { local a=1 b=2 c=3; }
e1() { x=$((i + 1)); }
t1() { [[ $i -gt 5 ]]; }
_loop() { eval "run_$1() { local i x; for ((i = 0; i < $N; i++)); do $2; done; }"; }
_loop empty ':'
_loop call0 'c0'
_loop call3args 'c3 a b c'
_loop local3 'l3'
_loop expr_inline 'x=$((i + 1))'
_loop expr_call 'e1'
_loop test_inline '[[ $i -gt 5 ]]'
_loop test_call 't1'
