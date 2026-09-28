# 100 trivial tests to measure and enforce the runner's speed budget (< 200ms / 100 tests).
for _t_i in $(seq 1 100); do
	eval "t_trivial_${_t_i}_arithmetic() { eq $_t_i \$((${_t_i} - 1 + 1)); }"
done
unset _t_i
