#!/usr/bin/env bash

# Frank Scheiner <frank.scheiner@web.de>

# 2023-10-23 - v0.2.0
# Use shortened SHA1 hashes in kernel release to allow for more space for `flavor`

# make-kernel - make kernel and modules (`all`) and install modules (`modules_install`) with given config

_debug=1

# Config
_ramdisk="/usr/src/ramdisk"

_supportedArches=( "alpha" "ia64" )

_threads=$( nproc )

# "-mp" or "-sp" extraversion for e.g. alpha architecture or identifier for special kernels
_flavor=""

usageMsg()
{
	echo "Usage: $0 <KERNEL_CONFIG> <ARCH> <KERNEL_TREE> [<FLAVOR>]"

	return
}

debug()
{
	if [[ ${_debug} -eq 1 ]]; then

		echo "$@" 1>&2
	else
		:
	fi

	return
}

EX_USAGE=64

if [[ "$1" != "" ]]; then

	_kernelConfig="$1"
	shift

	if [[ "$1" != "" ]]; then

		_arch="$1"
		shift

		if [[ "$1" != "" ]]; then

			_kernelTree="$1"
			shift
		else
			usageMsg
			exit $EX_USAGE
		fi
	else
		usageMsg
		exit $EX_USAGE
	fi
else
	usageMsg
	exit $EX_USAGE
fi

if [[ "$1" != "" ]]; then

	_flavor="-${1}"
	shift
fi

####

if [[ ! -e ${_kernelConfig} ]]; then

	echo "$0: given kernel config not existing. Cannot continue."
	exit 1
fi

_archIsSupported=0

for _supportedArch in "${_supportedArches[@]}"; do

	if [[ "$_supportedArch" == "$_arch" ]]; then

		_archIsSupported=1
	else
		continue
	fi
done

if [[ $_archIsSupported -eq 0 ]]; then

	echo "$0: given architecure is not supported yet. Cannot continue."
	exit 1
fi

if [[ -d ${_kernelTree} ]]; then

	#echo "Copying kernel tree to RAMdisk..."
	#debug "cp -rad ${_kernelTree}/ ${_ramdisk}/"
	#cp -rad ${_kernelTree}/ ${_ramdisk}/
	#
	#if [[ $? == 0 ]]; then
	#	echo "done"
	#else
	#	echo "failed"
	#	exit 1
	#fi
	# Expect that the kernel tree is there already.
	:
else
	echo "$0: given kernel tree not existing. Cannot continue."
	exit 1
fi

####

echo "Copying kernel config..."
debug "cp ${_kernelConfig} ${_kernelTree}/.config"
cp ${_kernelConfig} ${_kernelTree}/.config

if [[ $? -eq 0 ]]; then

	echo "done"
else
	echo "failed"
	exit 1
fi

_oldPWD="$PWD"
cd ${_kernelTree} || ( echo "$0: cannot cd to \"${_kernelTree}\"."; exit 1 )

# olddefconfig

echo "Configuring kernel..."
debug "make LOCALVERSION=\"-$( git rev-parse --short HEAD )-${_arch}${_flavor}\" ARCH=${_arch} CROSS_COMPILE=${_arch}-linux- olddefconfig"
make LOCALVERSION="-$( git rev-parse --short HEAD )-${_arch}${_flavor}" ARCH=${_arch} CROSS_COMPILE=${_arch}-linux- olddefconfig

if [[ $? -eq 0 ]]; then

	echo "done"
else
	echo "failed"
	exit 1
fi

# all

echo "Making kernel..."
debug "time make -j${_threads} LOCALVERSION=\"-$( git rev-parse --short HEAD )-${_arch}${_flavor}\" ARCH=${_arch} CROSS_COMPILE=${_arch}-linux- all"
date
time make -j${_threads} LOCALVERSION="-$( git rev-parse --short HEAD )-${_arch}${_flavor}" ARCH=${_arch} CROSS_COMPILE=${_arch}-linux- all
_makeReturned=$?
echo ${_makeReturned}
date

if [[ ${_makeReturned} -eq 0 ]]; then

	echo "done"
else
	echo "failed"
	exit 1
fi

cp vmlinux "../vmlinux${_flavor}"
cp vmlinux.gz "../vmlinux.gz${_flavor}"

exit

# modules_install

echo "Installing modules..."
debug "time make LOCALVERSION=\"-$( git rev-parse --short HEAD )-${_arch}${_flavor}\" ARCH=${_arch} CROSS_COMPILE=${_arch}-linux- modules_install"
date
time make LOCALVERSION="-$( git rev-parse --short HEAD )-${_arch}${_flavor}" ARCH=${_arch} CROSS_COMPILE=${_arch}-linux- modules_install
_makeReturned=$?
echo ${_makeReturned}
date

if [[ ${_makeReturned} -eq 0 ]]; then

	echo "done"
else
	echo "failed"
	exit 1
fi

_kernelRelease=$( make -s LOCALVERSION="-$( git rev-parse --short HEAD )-${_arch}${_flavor}" kernelrelease )

# save artifacts
cp vmlinux /boot/vmlinux-${_kernelRelease}

_uncompressedKernel="/boot/vmlinux-${_kernelRelease}"

if [[ "${_arch}" == "alpha" ]]; then

	# Due to aboot being unable to handle arbitrary large kernel and initrd images (total max size roughly 13 MiB or so!)
	alpha-linux-strip vmlinux
	gzip -c -9 vmlinux > vmlinuz
	_compressedKernel="/boot/vmlinuz-${_kernelRelease}-stripped"
	cp vmlinuz "${_compressedKernel}"
else
	_compressedKernel="/boot/vmlinuz-${_kernelRelease}"
	cp vmlinux.gz "${_compressedKernel}"
fi

cp .config /boot/config-${_kernelRelease}

_configuration="/boot/config-${_kernelRelease}"

cd /lib/modules

if [[ "${_arch}" == "alpha" ]]; then

	# same here (see above)
	tar -cf ${_kernelRelease}-non-stripped.tar ${_kernelRelease}
	cd ${_kernelRelease}
	find . -name "*.ko" -exec alpha-linux-strip --strip-debug '{}' \;
	cd ..
	tar -cf ${_kernelRelease}-stripped.tar ${_kernelRelease}

	_kernelModules=( "/lib/modules/${_kernelRelease}-non-stripped.tar" "/lib/modules/${_kernelRelease}-stripped.tar" )
else
	tar -cf ${_kernelRelease}.tar ${_kernelRelease}

	_kernelModules=( "/lib/modules/${_kernelRelease}.tar" )
fi

cd ${_oldPWD}

echo "Build artifacts:"
echo "${_configuration}"
echo "${_uncompressedKernel}"
echo "${_compressedKernel}"
for _tarball in "${_kernelModules[@]}"; do

	echo "${_tarball}"
done

exit
