is_alive() {
	echo $(kill -s 0 "$1")
}

prev="\e[${1:-1}F" # Beginning of Nth prev line
max=100
i=0
sleep 0.1 &
pid=$!

while ((i < max)); do
	is_alive "$pid" >isAlive
	echo "IS ALIVE?" $isAlive
	if [ -n "${#isAlive[@]}" ]; then
		echo "Starting new sleep after "
		sleep 1 &
		pid=$!
		i=$((i + 1))
	else
		echo -e "${prev}Waiting for $pid\n"
		sleep 1
	fi
done
