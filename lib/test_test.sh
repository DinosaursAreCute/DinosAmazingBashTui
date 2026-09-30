#!/usr/bin/env bash
source lib/terminal_controls.sh
source lib/dapk/ui.sh
cur.hide
pb.init
pid=
i=0
while [ "$i" != 100 ]; do
	sleep 10 &
	pid=$!
	if kill -s 0 "$pid"; then
		pb.update "$i" i 100
	else
		echo "Done with $i"
		sleep 1 &
		pid=$!
		i++
	fi
	echo "Waiting for $i/$pid"
	sleep 0.1
done
dapk.ui.progress_done
cur.show
