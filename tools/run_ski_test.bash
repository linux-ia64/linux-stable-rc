#!/bin/bash

#export SKI_USE_FAKE_XTERM=1

_ski="$1"
_skiBootLoader="$2"
_hpSimLinuxKernel="$3"
_skiPathVar="/bin:/sbin:/usr/bin:/usr/sbin"

${_ski} \
	-noconsole \
	${_skiBootLoader} \
	${_hpSimLinuxKernel} \
	root=/dev/sda \
	simscsi=./sd \
	simeth=enp3s0f0 \
	init=/root/bin/ski_test.bash \
	PATH=${_skiPathVar} \
	rw \
	memblock=debug

_skiPID=$!

_skiLog=ski.*

while ! grep 'INFO: Ski execution finished.' ${_skiLog} &>/dev/null; do

	sleep 10
done

sleep 5

kill ${_skiPID}

cat ${_skiLog}

if grep 'INFO: Ski test succeeded.' ${_skiLog} &>/dev/null; then

	rm ${_skiLog}
	exit 0
else
	rm ${_skiLog}
	exit 1
fi

