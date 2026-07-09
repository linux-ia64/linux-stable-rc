#!/bin/bash

set -x

_skiBootLoader="$1"
_hpSimLinuxKernel="$2"

_skiPathVar="/bin:/sbin:/usr/bin:/usr/sbin"
_skiLog="ski-$$.log"
_skiInit="/root/bin/ski_test.bash"


bski \
	-conslog "${_skiLog}" \
	${_skiBootLoader} \
	${_hpSimLinuxKernel} \
	root=/dev/sda \
	simscsi=./sd \
	simeth=tap0 \
	init=${_skiInit} \
	PATH=${_skiPathVar} \
	rw \
	memblock=debug &

_skiPID=$!

tail --pid=${_skiPID} --retry -f -n +1 ${_skiLog} &

_tailPID=$!

set +x

while ! grep 'INFO: Ski execution finished.' ${_skiLog} &>/dev/null; do

	sleep 10
done

set -x

sleep 5

kill ${_skiPID}
kill ${_tailPID} || true

if grep 'INFO: Ski test succeeded.' ${_skiLog} &>/dev/null; then

	exit 0
else
	exit 1
fi
