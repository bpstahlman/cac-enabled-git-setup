#! /bin/bash
# Starting cwd is base of operations.
# TODO: Check to be sure it seems to contain the package.
Basedir=$PWD
# Make sure we have an unmodified git we can use to clone source repos.
Sys_git=/usr/bin/git
# This will be detected and set in detect_cac_card.
Card_id=
# Facilitate skipping install step when --no-install specified
Make_install="make install"

declare -i Step_idx=0
declare -A Skip_steps=()
# These are tied to the --start-step / --end-step options
Start_step=
End_step=

# TODO: Consider adding defaults for all... For now, missing options assumed to be unset.
declare -A Opts=(
	[ca-bundle-dir]=/usr/ssl/certs
	[ca-bundle-name]=ca-bundle-plus-dod-root
	[openssl-conf]=/usr/ssl/pkcs11-openssl.cnf
)

declare -a Steps=(
	install_cyg_pkg
	download_source
	build_opensc
	create_certs
	build_curl
	configure_openssl_conf
	build_git
	install_env_script
)

on_exit() {
	if (($? == 0)); then
		echo "Success!"
	else
		echo "Setup aborted with error! Check stdout for details."
		echo "After resolving any issues, resume setup by running ./setup -s ${Steps[$Step_idx]}"
	fi
	cd "$Basedir"
}

# Run all steps, starting with the first (or the one specified by --start-step), and ending with the last (or the one
# specified with --end-step), skipping any specified by options such as --skip-step.
run() {
	if [[ -n "$Start_step" ]]; then started=no; else started=yes; fi
	for step in "${Steps[@]}"; do
		if [[ $started == no && $step == $Start_step ]]; then
			started=yes
		fi
		# If we've passed start step (or none given) and we're not skipping...
		if [[ $started == yes && -z ${Skip_steps[$step]} ]]; then
			log "Starting step #$((Step_idx + 1)): $step"
			${Opts[no-execute]:+echo Simulating step} $step
			log "Finished step #$((Step_idx + 1)): $step"
		fi
		if [[ -n $End_step && $step == $End_step ]]; then
			log "Exiting due to --end-step '$End_step'"
			((++Step_idx))
			exit 0
		fi
		((++Step_idx))
	done
}

# TODO: Colorize?
log() {
	echo >&2 "$@" 
}
usage() {
	echo >&2 "Usage: ./setup.sh blah blah"
}
error() {
	usage=no
	if [[ "$1" == "--usage" ]]; then
		usage=yes
		shift
	fi
	echo 2>&1 "$@"
	if [[ $usage == yes ]]; then
		usage
	fi
	# TODO: Consider adding an error code option.
	exit 1
}

process_opt() {
	# TODO: Consider a different way, which would handle defaults.
	# TODO: Perhaps put these in array, at least...
	longs=(
		start-step: end-step: skip-step:
		ca-bundle-dir: ca-bundle-name: openssl-conf:
		skip-cygwin-install no-install no-execute)
	# getopt idiosyncrasy: 1st arg specified to a long opt intended to be used to build an array can lose the 1st arg if
	# there no short opts are specified (e.g., with -o).
	eval set -- $(getopt -os: -l$(IFS=, ; echo "${longs[*]}") -- "$@")
	while (($#)); do
		v=$1
		shift
		case $v in
			-s | --start-step) Start_step=$1; shift;;
			--end-step) End_step=$1; shift;;
			--skip-step)
				# Add to hash of steps to skip.
				# Note: Seems to be some weirdness with getopt handling of multiples when no short opts specified.
				# Workaround: Configure at least on short opt (with -o).
				Skip_steps[$1]=yes
				shift;;
			--ca-bundle-dir) Opts[ca-bundle-dir]=$1; shift;;
			--ca-bundle-name) Opts[ca-bundle-name]=$1; shift;;
			--openssl-conf) Opts[openssl-conf]=$1; shift;;
			# TODO: Perhaps just use the --skip-step mechanism internally.
			--skip-cygwin-install)
				Opts[skip-cygwin-install]=yes
				# This option is really just syntactic sugar.
				Skip_steps[install_cyg_pkg]=yes;;
			--no-install)
				Opts[no-install]=yes
				Make_install="echo Skipping install...";;
			--no-execute)
				Opts[no-execute]=yes;;
		esac
	done
}

detect_cac_card() {
	# Note: Extract the desired id using pkcs15-tool
	# Using reader with a card: Broadcom Corp Contacted SmartCard 0
	# X.509 Certificate [Certificate for PIV Authentication]
	# 		Object Flags   : [0x0]
	# 		Authority      : no
	# 		Path           : 
	# 		ID             : 01
	Card_id=$(pkcs15-tool -c |
		sed -n -e '/PIV/,/ID/p' |
		sed -n '$s/[[:space:]]*ID[[:space:]]*:[[:space:]]*\([0-9]\+\)[[:space:]]*/\1/p')

	# TODO: Allow user to insert and retry.
	if [[ -z $Card_id ]]; then
		# TODO: Clean up message.
		error "Error: Cannot detect CAC card. Have you inserted it?"
	fi
}
check_prerequisites() {
	if [[ -z $Opts[skip-cygwin-install] ]] && ! which install-info; then
		error "Prerequisite error: This script cannot install cygwin packages without a working \`install-info' program." \
			"Install this package (e.g., using Cygwin setup) and re-run."
	fi
}
# Pre-requisite: Running cygwin setup program standalone fails if the install-info utility is not in the path. Appears
# to be a cygwin bug/oversight: at any rate, we can get it by having user install just the info pkg up-front.
# Note: Using setup -P for an already-installed package appears to re-install harmlessly.
# TODO: Provide special arg for skipping cygwin install (so user needn't know which step follows).
# Important Note: If unattended setup causes problems on user's machine, he can install the packages himself through the
# gui and re-run with --skip-cygwin-install or --skip-step install_cyg_pkg.
install_cyg_pkg() {
	# TODO: Document purpose of all these...
	local -a pkgs=(
		git curl wget libnss3 openssl openssl-devel
		chkconfig pkg-config automake libtool cygwin-devel
		dos2unix autoconf libopenssl100 libcurl4 patch
	)
	# Cygwin setup tends to generate spurious (but apparently harmless) errors, so temporarily turn off errexit.
	set +e
	./cyg_setup-x86.exe --no-admin --wait -q -P "${pkgs[@]}"
	set -e
}
download_source() {
	# TODO: Perhaps separate OpenSC from the others, possibly even having a single build_opensc...
	repos=(
		https://github.com/bagder/curl.git
		https://github.com/git/git.git
		https://github.com/OpenSC/engine_pkcs11
		https://github.com/OpenSC/libp11
		https://github.com/OpenSC/OpenSC
	)
	for repo in "${repos[@]}"; do
		# Note: Setting core.autocrlf=input obviates need for dos2unix post-processing.
		# TODO: How to ensure we always use unmodified versions of things like git. Make this configurable somehow?
		$Sys_git clone --config core.autocrlf=input $repo
	done
}
build_opensc() {
	# Caveat: If we don't set PKG_CONFIG_PATH, the libp11 we're about to build won't be found in subsequent build steps.
	export PKG_CONFIG_PATH=/usr/local/lib/pkgconfig
	libs=(libp11 engine_pkcs11 OpenSC)
	for d in "${libs[@]}"; do
		pushd $d;
		# TODO: Make sure error handled as desired (with effective popd).
		# simulate error somehow to test...
		# TEMP DEBUG - Don't really install...
		./bootstrap && ./configure && make && $Make_install && popd
	done
}
create_certs() {
	certs=(rel3_dodroot_2048 dodeca dodeca2)
	url=http://dodpki.c3pki.chamb.disa.mil
	for cert in "${certs[@]}"; do
		wget -O- $url/$cert.p7b | openssl pkcs7 -inform DER -outform PEM -print_certs
	done >"${Opts[ca-bundle-dir]}/${Opts[ca-bundle-name]}.pem"
	# TODO: Perhaps make the above just a full path.
}
build_curl() {
	patch -u -p0 < curl.patch
	pushd curl
	# Note: curl from github doesn't come with a configure script.
	./buildconf && ./configure --with-ca-bundle="${Opts[ca-bundle-dir]}/${Opts[ca-bundle-name]}.pem" && make && $Make_install
	popd
}
configure_openssl_conf() {
	# Important Note: install_env_script will add the env var curl uses to find and load this.
	cat <<-'eof' > "${Opts[openssl-conf]}"
	openssl_conf = openssl_def
	[openssl_def]
	engines = engine_section
	[engine_section]
	pkcs11 = pkcs11_section
	[pkcs11_section]
	engine_id = pkcs11
	dynamic_path = /usr/local/lib/engines/engine_pkcs11.dll
	MODULE_PATH = /usr/local/lib/opensc-pkcs11.dll
	init = 0
	[req]
	distinguished_name = req_distinguished_name
	[req_distinguished_name]
	eof
}
build_git() {
	patch -u -p0 < git.patch
	# Note: Git has no configure script.
	NO_R_TO_GCC_LINKER=1 CURLDIR=/usr/local make -C git prefix=/usr/local all ${Opts[no-install]:-install}
}
install_env_script() {
	# TODO: Any reason to make this configurable?
	# TODO: Consider putting the cac id detection there also (in case slot id moves)...
	cat <<eof >/etc/profile.d/cac-enabled-git.sh
#! /bin/bash
if [[ \$(uname -o) == Cygwin ]]; then
	# Add environment vars needed for CAC-enabled Git
	export GIT_SSL_CERT=slot_01-id_$Card_id
	export GIT_SSL_KEY=slot_01-id_$Card_id
	export GIT_SSL_CAINFO=${Opts[ca-bundle-dir]}/${Opts[ca-bundle-name]}.pem
	export GIT_SSL_ENGINE=pkcs11
	export GIT_SSL_KEYTYPE=ENG
	export GIT_SSL_CERTTYPE=ENG
fi
eof
}

# Fail on error with indication of last step completed.
# Caveat: Take care not to generate spurious errors (e.g., bare `let step++' when step==0).
set -e

trap on_exit EXIT
process_opt "$@"
# Always detect CAC card, since the results of id detection may be needed in other steps.
detect_cac_card
check_prerequisites
run

for k in ${!Opts[@]}; do
	echo "$k: ${Opts[$k]}"
done

# vim:ts=4:sw=4:tw=120
