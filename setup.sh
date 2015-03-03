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
# Container for any steps specified with --skip-step
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
	patch_curl
	build_curl
	configure_openssl_conf
	patch_git
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
			return 0
		fi
		((++Step_idx))
	done
}

# TODO: Colorize?
log() {
	echo >&2 "$@" 
}
usage() {
	# TODO: Sensible usage. Also --help.
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
# Processes a ~ (alone) or a ~/ at head of input path, replacing with `$HOME/'.
# Rationale: Bash's tilde expansion is inhibited by quoting a path, but quotes may be necessary to protect spaces.
# TODO: Perhaps remove this if I end up not using (on grounds that user shouldn't quote if he wants it expanded).
expand_path() {
	if [[ $1 == "~" ]]; then
		echo "$HOME"
	else
		echo ${1/#~\//$HOME/}
	fi
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
	# We really need only wget to boostrap things.
	# Caveat: Name of exe and associated package may differ.
	# TODO: No need for loop mechanism if this ends up being the only one...
	local -A exes=([wget]=wget)
	for exe in ${!exes[@]}; do
		if [[ -z $Opts[skip-cygwin-install] ]] && ! which $exe; then
			error "Prerequisite not met: This script cannot proceed without a working \`$exe' program." \
				"Suggested remedy: Install package \`${exes[$exe]}' using Cygwin installer and rerun this script."
		fi
	done
}
# Pre-requisite: Running cygwin setup program standalone fails if the install-info utility is not in the path. Appears
# to be a cygwin bug/oversight: at any rate, we can get it by having user install just the info pkg up-front.
# Note: Using setup -P for an already-installed package appears to re-install harmlessly.
# TODO: Provide special arg for skipping cygwin install (so user needn't know which step follows).
# Important Note: If unattended setup causes problems on user's machine, he can install the packages himself through the
# gui and re-run with --skip-cygwin-install or --skip-step install_cyg_pkg.
install_cyg_pkg() {
	# TODO: Document purpose of all these...
	# Caveat: Make sure info pkg is installed first.
	# Rationale: I've run into issues attempting to install packages when install-info (in info package) didn't exist.
	# Note: libexpat-devel and gettext-devel appear to be hidden dependencies of various configure/make scripts.
	local -a pkgs=(
		info git wget dos2unix patch
		libnss3 openssl openssl-devel libopenssl100
		chkconfig pkg-config automake autoconf libtool cygwin-devel
		libexpat-devel gettext-devel
	)
	# Obtain latest copy of setup program and make executable.
	url=https://cygwin.com/setup-x86.exe
	opt="-q -N -d -W -B"
	setup=./${url##*/}
	wget -O $setup $url
	chmod a+x $setup
	# Install packages one at a time (though -P supports multiple).
	# Rationale: Cygwin setup "quiet" mode doesn't handle dependencies well at all.
	# Cygwin setup tends to generate spurious (but apparently harmless) errors, so temporarily turn off errexit.
	set +e
	$setup $opt -C base
	for p in "${pkgs[@]}"; do
		$setup $opt -P "$p"
	done
	set -e
}
# Make sure there's nothing in the environment (e.g., from a previous run), that could mess us up (e.g., GIT_SSL_<...>
# vars that could cause the vanilla git to attempt to use the CAC card).
clean_env() {
	for v in $(env | grep '^[[:space:]]*GIT_SSL_'); do
		unset ${v%%=*};
	done
	# These 2 shouldn't have any impact, but just in case...
	unset OPENSSL_CONF
	unset GIT_INHIBIT_ASKPASS
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
		rm -rf "$(basename $repo .git)"
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
# TODO: Decide whether these patches should be part of a package or here-docs.
patch_curl() {
	patch -u -p0 <<-'eof'
	--- curl/lib/easy.c.orig	2015-02-25 10:25:12.505452200 -0600
	+++ curl/lib/easy.c	2015-02-25 10:26:35.904222300 -0600
	@@ -947,6 +947,18 @@
	                              data->state.resolver))
	     goto fail;
	 
	+  /* If set, clone the handle to the engine being used. */
	+#if defined(USE_SSLEAY) && defined(HAVE_OPENSSL_ENGINE_H)
	+  if (data->state.engine) {
	+    /* state.engine existing means curl_ossl_set_engine was
	+    * previously successful. Because curl_ossl_set_engine worked,
	+    * we can query the already-set engine for that handle and use
	+    * that to increment a reference:
	+    */
	+    Curl_ssl_set_engine(outcurl, ENGINE_get_id(data->state.engine));
	+  }
	+#endif /* USE_SSLEAY */
	+
	   Curl_convert_setup(outcurl);
	 
	   outcurl->magic = CURLEASY_MAGIC_NUMBER;
	--- curl/lib/vtls/openssl.c.orig	2015-02-25 10:22:35.120450300 -0600
	+++ curl/lib/vtls/openssl.c	2015-02-25 10:23:47.825608800 -0600
	@@ -761,6 +761,11 @@
	   /* Lets get nice error messages */
	   SSL_load_error_strings();
	 
	+  /* Load config file */
	+  OPENSSL_load_builtin_modules();
	+  if (CONF_modules_load_file(getenv("OPENSSL_CONF"), NULL, 0) <= 0)
	+    return 0;
	+
	   /* Init the global ciphers and digests */
	   if(!SSLeay_add_ssl_algorithms())
	     return 0;
	eof
}
build_curl() {
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
patch_git() {
	# Caveat: Leading tabs will be stripped, but need to ensure that patch lines without + or - preserve the leading
	# Space (to avoid "malformed patch at line..." errors).
	patch -u -p0 <<-'eof'
	--- git/http.c.orig	2015-02-26 08:09:14.879850700 -0600
	+++ git/http.c	2015-02-26 16:47:18.067707400 -0600
	@@ -51,6 +51,9 @@
	 struct credential http_auth = CREDENTIAL_INIT;
	 static int http_proactive_auth;
	 static const char *user_agent;
	+static const char *ssl_keytype;
	+static const char *ssl_certtype;
	+static const char *ssl_engine;
	 
	 #if LIBCURL_VERSION_NUM >= 0x071700
	 /* Use CURLOPT_KEYPASSWD as is */
	@@ -252,6 +255,12 @@
	 
	 	if (!strcmp("http.useragent", var))
	 		return git_config_string(&user_agent, var, value);
	+	if (!strcmp("http.sslkeytype", var))
	+		return git_config_string(&ssl_keytype, var, value);
	+	if (!strcmp("http.sslcerttype", var))
	+		return git_config_string(&ssl_certtype, var, value);
	+	if (!strcmp("http.sslengine", var))
	+		return git_config_string(&ssl_engine, var, value);
	 
	 	/* Fall back on the default ones */
	 	return git_default_config(var, value, cb);
	@@ -408,6 +417,17 @@
	 		curl_easy_setopt(result, CURLOPT_PROXYAUTH, CURLAUTH_ANY);
	 	}
	 
	+	/* Adding setting of engine-related curl SSL options. */
	+	if (ssl_engine != NULL) {
	+		curl_easy_setopt(result, CURLOPT_SSLENGINE, ssl_engine);
	+		curl_easy_setopt(result, CURLOPT_SSLENGINE_DEFAULT, 1L);
	+	}
	+
	+	if (ssl_keytype != NULL)
	+		curl_easy_setopt(result, CURLOPT_SSLKEYTYPE, ssl_keytype);
	+	if (ssl_certtype != NULL)
	+		curl_easy_setopt(result, CURLOPT_SSLCERTTYPE, ssl_certtype);
	+
	 	set_curl_keepalive(result);
	 
	 	return result;
	@@ -502,7 +522,10 @@
	 		    starts_with(url, "https://"))
	 			ssl_cert_password_required = 1;
	 	}
	-
	+	/* Added environment variables for expanded engine-related options. */
	+	set_from_env(&ssl_keytype, "GIT_SSL_KEYTYPE");
	+	set_from_env(&ssl_certtype, "GIT_SSL_CERTTYPE");
	+	set_from_env(&ssl_engine, "GIT_SSL_ENGINE");
	 #ifndef NO_CURL_EASY_DUPHANDLE
	 	curl_default = get_curl_handle();
	 #endif
	--- git/prompt.c.orig	2015-02-26 16:39:49.891073200 -0600
	+++ git/prompt.c	2015-02-26 16:39:55.933418800 -0600
	@@ -45,7 +45,7 @@
	 {
	 	char *r = NULL;
	 
	-	if (flags & PROMPT_ASKPASS) {
	+	if (!git_env_bool("GIT_INHIBIT_ASKPASS", 0) && flags & PROMPT_ASKPASS) {
	 		const char *askpass;
	 
	 		askpass = getenv("GIT_ASKPASS");
	eof
}
build_git() {
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
	export GIT_SSL_CAINFO="${Opts[ca-bundle-dir]}/${Opts[ca-bundle-name]}.pem"
	export GIT_SSL_ENGINE=pkcs11
	export GIT_SSL_KEYTYPE=ENG
	export GIT_SSL_CERTTYPE=ENG

	# Make sure curl can load the pkcs11 openssl engine.
	export OPENSSL_CONF="${Opts[openssl-conf]}"

	# Keep Git from using the Tk-based askpass gui (which has an X11 dependency that may not be satisfied) before
	# defaulting to the console-based prompt.
	export GIT_INHIBIT_ASKPASS=yes
fi
eof
}

# Default mode is to fail on error with indication of last step completed.
# Note: Step functions with a need (e.g., install_cyg_pkg) may *temporarily* unset.
# Caveat: Take care not to generate spurious errors: e.g., do ((++var)) instead of ((var++) when var could be 0.
set -e
trap on_exit EXIT
process_opt "$@"
clean_env
# Always detect CAC card, since the results of id detection may be needed in other steps.
detect_cac_card
check_prerequisites
run

# vim:ts=4:sw=4:tw=120
