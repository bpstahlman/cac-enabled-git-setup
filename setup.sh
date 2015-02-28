#! /bin/bash
# Starting cwd is base of operations.
# TODO: Check to be sure it seems to contain the package.
Basedir=$PWD
# This will be detected and set in detect_cac_card.
Card_id=

declare -i Step=0
declare -A Skip_steps=()
# These are tied to the --start-step / --end-step options
Start_step=
End_step=

# TODO: Consider adding defaults for all...
declare -A Opts=(
	[extra-certs-dir]=/usr/ssl/certs
	[make-install]="make install"
	[openssl-conf]=/usr/ssl/pkcs11-openssl.cnf
)
# Note: Cfg is less likely to need changing by end-user; of course, we could always move things from here to Opts
declare -A Cfg=(
	[ca-bundle-name]=ca-bundle-plus-dod-root
)
declare -a Steps=(
	install_cyg_pkg
	detect_cac_card
	download_source
	build_opensc
	create_certs
	build_curl
	configure_openssl_conf
	build_git
)

on_exit() {
	if (($? == 0)); then
		echo "Success!"
	else
		echo "Setup aborted with error! Check stdout for details."
		echo "After resolving any issues, resume setup by running ./setup -s ${Steps[$Step]}"
	fi
	cd "$Basedir"
}

run() {
	if [[ -n $Start_step ]]; then started=no; else started=yes; fi
	for step in "${Steps[@]}"; do
		if [[ $started == no && $step == $Start_step ]]; then
			started=yes
		fi
		# If we've passed start step (or none given) and we're not skipping...
		if [[ $started == yes && -n ${Skip_steps[$step]} ]]; then
			log "Beginning step $Step: ${Steps[$Step]}"
			${Steps[$Step]}
			log "Finished step  $Step: ${Steps[$Step]}"
		fi
		if [[ -n $End_step && $step == $End_step ]]; then
			log "Exiting due to --end-step $End_step"
			exit 0
		fi
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

# TODO: This has been obsoleted by --start-step/--end-step options: remove...
set_start_step() {
	if [ "${Opts[start-step]}" ]; then
		idx=0
		for step in "${Steps[@]}"; do
			if [[ "$step" == "${Opts[start-step]}" ]]; then
				Step=$idx
				return
			fi
			((++idx))
		done
		error --usage "Error: Unknown step specified with --start-step: \`${Opts[start-step]}'"
	fi
}

process_opt() {
	# TODO: Consider a different way, which would handle defaults.
	eval set -- $(getopt -os: -lstart-step:,end-step:,skip-step:,extra-certs-dir:,skip-cygwin-install,no-install -- "$@")
	while (($#)); do
		v="$1"
		shift
		case $v in
			-s | --start-step) Start_step=$1; shift;;
			--end-step) End_step=$1; shift;;
			--skip-step)
				# Add to hash of steps to skip.
				Skip_steps["$1"]=yes
				shift;;
			--extra-certs-dir) Opts[extra-certs-dir]="$1"; shift;;
			--openssl-conf) Opts[openssl-conf]="$1"; shift;;
			# TODO: Perhaps just use the --skip-step mechanism internally.
			--skip-cygwin-install) Opts[skip-cygwin-install]=yes;;
			--no-install) Opts[make-install]="echo skipping install...";;
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
	if [[ -z "$Card_id" ]]; then
		# TODO: Clean up message.
		error "Error: Cannot detect CAC card. Have you inserted it?"
	fi
}
# Pre-requisite: Running cygwin setup program standalone fails if the install-info utility is not in the path. Appears
# to be a cygwin bug/oversight: at any rate, we can get it by having user install just the info pkg up-front.
# Note: Using setup -P for an already-installed package appears to re-install harmlessly.
# TODO: Provide special arg for skipping cygwin install (so user needn't know which step follows).
install_cyg_pkg() {
	# Note: If unattended setup causes problems on user's machine, he can install the packages himself through the gui
	# and re-run with skip option.
	if [[ "${Opts[skip-cygwin-install]}" == yes ]]; then
		return
	fi
	# TODO: Document purpose...
	local -a pkgs=(
		git curl wget libnss3 openssl openssl-devel chkconfig pkg-config automake libtool cygwin-devel dos2unix autoconf
		libopenssl100 libcurl4 patch
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
		git clone --config core.autocrlf=input $repo
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
		./bootstrap && ./configure && make && ${Opts[make-install]} && popd
	done
}
create_certs() {
	certs=(rel3_dodroot_2048 dodeca dodeca2)
	url=http://dodpki.c3pki.chamb.disa.mil
	for cert in "${certs[@]}"; do
		wget -O- $url/$cert.p7b | openssl pkcs7 -inform DER -outform PEM -print_certs
	done >"${Opts[extra-certs-dir]}/${Cfg[ca-bundle-name]}.pem"
	# TODO: Perhaps make the above just a full path.
}
build_curl() {
	pushd curl
	patch -u -p0 < curl.patch
	# Note: curl from github doesn't come with a configure script.
	./buildconf && ./configure --with-ca-bundle="${Opts[extra-certs-dir]}/${Cfg[ca-bundle-name]}" && make && ${Opts[make-install]}
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
	cat <<-eof >/etc/profile.d/cac-enabled-git.sh
	#! /bin/bash
	if [[ $(uname -o) == Cygwin ]]; then
		# Add environment vars needed for CAC-enabled Git
		GIT_SSL_CERT=slot_01-id_$Card_id
		GIT_SSL_KEY=slot_01-id_$Card_id
		GIT_SSL_CAINFO=${Opts[extra-certs-dir]}/${Cfg[ca-bundle-name]}.pem
		GIT_SSL_ENGINE=pkcs11
		GIT_SSL_KEYTYPE=ENG
		GIT_SSL_CERTTYPE=ENG

	fi
	eof
}

# Fail on error with indication of last step completed.
# Caveat: Take care not to generate spurious errors (e.g., bare `let step++' when step==0).
set -e

trap on_exit EXIT
process_opt "$@"
#set_start_step
run

# vim:ts=4:sw=4:tw=120
