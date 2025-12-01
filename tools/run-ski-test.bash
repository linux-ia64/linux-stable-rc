#!/bin/bash

export SKI_USE_FAKE_XTERM=1

_skiBootLoader="$1"
_hpSimLinuxKernel="$2"
_skiPathVar="/bin:/sbin:/usr/bin:/usr/sbin"

bski \
	${_skiBootLoader} \
	${_hpSimLinuxKernel} \
	root=/dev/sda \
	simscsi=./sd \
	simeth=tap0 \
	init=/root/bin/ski_test.bash \
	PATH=${_skiPathVar} \
	rw \
	memblock=debug &

_skiPID=$!

sleep 0.25

_skiLog=ski.*

tail -f -n +1 ${_skiLog} &

_tailPID=$!

while ! grep 'INFO: Ski execution finished.' ${_skiLog} &>/dev/null; do

	sleep 10
done

sleep 5

kill ${_tailPID}
kill ${_skiPID}

if grep 'INFO: Ski test succeeded.' ${_skiLog} &>/dev/null; then

	rm ${_skiLog}
	exit 0
else
	rm ${_skiLog}
	exit 1
fi
