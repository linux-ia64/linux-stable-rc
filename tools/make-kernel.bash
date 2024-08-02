#!/usr/bin/env bash

# Frank Scheiner <frank.scheiner@web.de>

# 2024-08-03 - v0.9.0
# make kernel tarball if needed

# 2024-05-15 - v0.7.0
# Add env var EMPTY_LOCALVERSION to compile with empty localversion

# 2024-05-08 - v0.6.0
# if a commit hash can't be found, ignore that part of LOCALVERSION

# 2024-04-08 - v0.5.0
# create logfile of build

# 2024-03-25 - v0.4.0
# Add System.map to the build artifacts

# 2024-01-28 - v0.3.0
# Also support other arches and do not cross compile if target arch is host arch

# 2023-10-23 - v0.2.0
# Use shortened SHA1 hashes in kernel release to allow for more space for `flavor`

# make-kernel - make kernel and modules (`all`) and install modules (`modules_install`) with given config

_debug=1

# Config
_ramdisk="/usr/src/ramdisk"

_supportedArches=( "alpha" "ia64" "x86_64" )

_threads=$( nproc )

# "-mp" or "-sp" extraversion for e.g. alpha architecture or identifier for special kernels
_flavor=""

usageMsg()
{
	echo "Usage: $0 <KERNEL_CONFIG> <ARCH> <KERNEL_TREE> [<FLAVOR> [tar-pkg]]"

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

compressLogFile()
{
	local _logFile="$1"

	zstdmt "${_logFile}" &>/dev/null &

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

	if [[ "$1" != "" ]]; then

		_extraMakeOption="$1"
		shift
	fi
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

_hostArch=$( uname -m )

if [[ ${_hostArch} == ${_arch} ]]; then

	_crossCompileOption=""
else
	# determine cross compiler tuples
	if hash ${_arch}-unknown-linux-gnu-gcc &>/dev/null; then

		_crossCompileOption="CROSS_COMPILE=${_arch}-unknown-linux-gnu-"

	elif hash ${_arch}-linux-gnu-gcc &>/dev/null; then

		_crossCompileOption="CROSS_COMPILE=${_arch}-linux-gnu-"

	elif hash ${_arch}-linux-gcc &>/dev/null; then

		_crossCompileOption="CROSS_COMPILE=${_arch}-linux-"
	else
		echo "$0: Can't find cross compiler. Cannot continue."
		exit 1
	fi
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

# start of logged operations
_tempLogFile=$( mktemp )
echo "START: $( date )" | tee -a "$_tempLogFile"

(
echo "Copying kernel config..."
debug "cp ${_kernelConfig} ${_kernelTree}/.config"
cp ${_kernelConfig} ${_kernelTree}/.config

if [[ $? -eq 0 ]]; then

	echo "done"
else
	echo "failed"
	exit 1
fi
) | tee -a "$_tempLogFile"

if [[ ! $? -eq 0 ]]; then

        exit 1
fi

_oldPWD="$PWD"
cd ${_kernelTree} || ( echo "$0: cannot cd to \"${_kernelTree}\"."; exit 1 )

# define LOCALVERSION
_currentCommitHashShort=$( git rev-parse --short HEAD )

if [[ "$_currentCommitHashShort" == "" ]]; then

	_localversionCurrentCommit=""
else
	_localversionCurrentCommit="-${_currentCommitHashShort}"
fi

_localversion="${_localversionCurrentCommit}-${_arch}${_flavor}"

if [[ $EMPTY_LOCALVERSION -eq 1 ]]; then

	_localversion=""
fi

# make olddefconfig ############################################################
(
echo "Configuring kernel..."
debug "make LOCALVERSION=\"${_localversion}\" ARCH=${_arch} ${_crossCompileOption} olddefconfig"
make LOCALVERSION="${_localversion}" ARCH=${_arch} ${_crossCompileOption} olddefconfig

if [[ $? -eq 0 ]]; then

	echo "done"
else
	echo "failed"
	exit 1
fi
) 2>&1 | tee -a "$_tempLogFile"

if [[ ! $? -eq 0 ]]; then

	exit 1
fi

_kernelRelease=$( make -s LOCALVERSION="${_localversion}" kernelrelease )

_tarball="linux-${_kernelRelease}.tar"
_finalLogFileName="build.log-${_kernelRelease}"

if [[ "$_extraMakeOption" != "" ]]; then

	# make tarball #####################################################################
	(
	echo "Making kernel tarball..."
	debug "time make -j${_threads} LOCALVERSION=\"${_localversion}\" ARCH=${_arch} ${_crossCompileOption} ${_extraMakeOption}"
	date
	time make -j${_threads} LOCALVERSION="${_localversion}" ARCH=${_arch} ${_crossCompileOption} ${_extraMakeOption}
	_makeReturned=$?
	echo ${_makeReturned}
	date

	if [[ ${_makeReturned} -eq 0 ]]; then

		echo "done"
	else
		echo "failed"
		exit 1
	fi
	) 2>&1 | tee -a "$_tempLogFile"

	if [[ ! $? -eq 0 ]]; then

	        exit 1
	fi

	# replace vmlinuz (which is just a copy of the unstripped and uncompressed vmlinux) with vmlinux.gz
	_vmlinuz="tar-install/boot/vmlinuz-${_kernelRelease}"
	echo "cp vmlinux.gz \"$_vmlinuz\"" | tee -a "$_tempLogFile"
	cp vmlinux.gz "$_vmlinuz"

	rm -f tar-install/boot/*kbuild*

	if [[ -e ${_tarball} ]]; then

		rm -f ${_tarball}
	fi

	# make actual tarball
	pushd tar-install &>/dev/null
	(
	echo "time tar -cf ../${_tarball} boot lib"
	date
	time tar -cf ../${_tarball} boot lib
	date
	) 2>&1 | tee -a "$_tempLogFile"
	popd &>/dev/null

	# compress tarball
	(
	echo "zstd -T0 -9 ${_tarball}"
	date
	time zstd -T0 -9 ${_tarball} &>/dev/null
	date
	) 2>&1 | tee -a "$_tempLogFile"

	(
	echo "Build artifacts:"
	echo "$PWD/${_finalLogFileName}.zst"
	echo "$PWD/${_tarball}.zst"
	echo "END: $( date )"
	) | tee -a "$_tempLogFile"

	zstd -T0 -9 "$_tempLogFile" -o "${_finalLogFileName}.zst" &>/dev/null && rm "$_tempLogFile"

	echo "$PWD/${_finalLogFileName}.zst" > LINUX_BUILD_LOG
	echo "$PWD/${_tarball}.zst" > LINUX_TARBALL
else
	# make all #####################################################################
	(
	echo "Making kernel..."
	debug "time make -j${_threads} LOCALVERSION=\"${_localversion}\" ARCH=${_arch} ${_crossCompileOption} all"
	date
	time make -j${_threads} LOCALVERSION="${_localversion}" ARCH=${_arch} ${_crossCompileOption} all
	_makeReturned=$?
	echo ${_makeReturned}
	date

	if [[ ${_makeReturned} -eq 0 ]]; then

		echo "done"
	else
		echo "failed"
		exit 1
	fi
	) 2>&1 | tee -a "$_tempLogFile"

	if [[ ! $? -eq 0 ]]; then

		exit 1
	fi

	if [[ "$_flavor" == "ski" ]]; then

		# If building a kernel to run in ski exit here already
		exit
	fi

	# make modules_install #########################################################
	(
	echo "Installing modules..."
	debug "time make LOCALVERSION=\"${_localversion}\" ARCH=${_arch} ${_crossCompileOption} modules_install"
	date
	time make LOCALVERSION="${_localversion}" ARCH=${_arch} ${_crossCompileOption} modules_install
	_makeReturned=$?
	echo ${_makeReturned}
	date

	if [[ ${_makeReturned} -eq 0 ]]; then

		echo "done"
	else
		echo "failed"
		exit 1
	fi
	) 2>&1 | tee -a "$_tempLogFile"

	if [[ ! $? -eq 0 ]]; then

		exit 1
	fi
	# save artifacts ###############################################################
	cp vmlinux /boot/vmlinux-${_kernelRelease}

	_uncompressedKernel="/boot/vmlinux-${_kernelRelease}"

	if [[ "${_arch}" == "alpha" ]]; then

		# Due to aboot being unable to handle arbitrary large kernel and initrd images (total max size roughly 13 MiB or so!)
		alpha-linux-strip vmlinux
		gzip -c -9 vmlinux > vmlinuz
		_compressedKernel="/boot/vmlinuz-${_kernelRelease}-stripped"
		cp vmlinuz "${_compressedKernel}"

	elif [[ "${_arch}" == "x86_64" ]]; then

		_compressedKernel="/boot/vmlinuz-${_kernelRelease}"
		cp arch/x86/boot/bzImage "${_compressedKernel}"
	else
		_compressedKernel="/boot/vmlinuz-${_kernelRelease}"
		cp vmlinux.gz "${_compressedKernel}"
	fi

	_configuration="/boot/config-${_kernelRelease}"
	cp .config ${_configuration}

	_systemMap="/boot/System.map-${_kernelRelease}"
	cp System.map ${_systemMap}

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

	_finalLogFile="/boot/build.log-${_kernelRelease}"

	cd ${_oldPWD}
	(
	echo "Build artifacts:"
	echo "${_finalLogFile}.zst"
	echo "${_configuration}"
	echo "${_systemMap}"
	echo "${_uncompressedKernel}"
	echo "${_compressedKernel}"
	for _tarball in "${_kernelModules[@]}"; do

		echo "${_tarball}"
	done
	echo "END: $( date )"
	) | tee -a "$_tempLogFile"

	mv "$_tempLogFile" "$_finalLogFile"

	compressLogFile "$_finalLogFile"

fi

exit
